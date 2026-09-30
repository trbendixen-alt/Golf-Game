extends SceneTree
## Builds a hole's scenery scene (buildings, cars, trees, lamps, hills, sky props...) and
## bakes its sun shadows. Run it from the golf-game folder:
##
##   godot --path . --resolution 64x64 --script res://tools/build_hole_scenery.gd -- main_street_opener
##
## It needs a real (tiny) window, so don't add --headless: a headless run has no GPU side
## to keep the instanced props' positions, and they would be saved empty.
##
## It reads data/holes/<id>.json: the obstacles there (buildings, cars, lamps, trees,
## cones) are the gameplay colliders, and this tool draws the matching art on top of the
## same spots, so what you see is exactly what the ball hits. Then it adds purely
## decorative things (back rows of buildings, skyline, park trees, barn, hills) from a
## fixed random seed, so a rebuild always gives the same town.
##
## Output (in scenes/holes/<id>/): scenery.tscn, meshes/*.res, materials/*.tres and
## sun_mask.png (the baked shadows). Commit them; the game only LOADS them.
##
## How it keeps the game fast:
##  - MERGING: all the buildings in a 45 m slice of street are ONE mesh (1 draw call).
##  - INSTANCING: cars, trees, lamps and cones are MultiMeshes: one model drawn many times.
##  - LEVEL OF DETAIL: every slice has a detailed and a cheap version, swapped by distance
##    (visibility ranges). Near buildings get the full window shader, far ones the "lite"
##    one; cars and trees switch to simpler models; small clutter disappears.
##  - BAKED LIGHTING: sun shadows and ambient occlusion on the ground are pre-computed
##    into sun_mask.png, so the game needs no real-time shadow pass for this scenery.

const MASK_RESOLUTION := 0.25         # metres per texel of the baked sun mask
const MASK_X := Vector2(-32.0, 32.0)  # the ground area the mask covers
const MASK_Z := Vector2(-124.0, 32.0)
const CHUNK_LENGTH := 45.0            # metres of street per slice
const NEAR_END := 130.0               # full-detail buildings show out to here...
const FAR_BEGIN := 115.0              # ...and the cheap ones take over from here
const PROPS_END := 110.0              # small clutter (awnings, vents) vanishes beyond this
const MODEL_LOD_DISTANCE := 75.0      # cars / trees / lamps switch to the simple model here

const STREET_TOP := 26.0
const FACADE := 8.5

const CAR_COLOR_FALLBACK := Color(0.6, 0.6, 0.6)

var id := ""
var hole: Dictionary
var scenery_data: Dictionary
var out_dir := ""
var rng := RandomNumberGenerator.new()
var scenery: Node3D
var occluders: Array[Dictionary] = []   # For the shadow bake: { shape, transform, size/radius/height }
var materials := {}                      # name -> Material

# Per-chunk collections (chunk index -> builder / transforms)
var near_buildings := {}   # MeshBuilder with building data
var props := {}            # MeshBuilder with vertex colours (awnings, rooftop clutter...)
var cars := {}             # Array of { transform, color }
var trees := {}            # Array of Transform3D
var lamps := {}
var cones := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	id = args[0] if args.size() > 0 else "main_street_opener"
	var hole_text := FileAccess.get_file_as_string("res://data/holes/%s.json" % id)
	hole = JSON.parse_string(hole_text)
	scenery_data = hole["scenery"]
	out_dir = scenery_data["scene"].get_base_dir() + "/"
	DirAccess.make_dir_recursive_absolute(out_dir + "meshes")
	DirAccess.make_dir_recursive_absolute(out_dir + "materials")
	rng.seed = int(scenery_data["seed"])

	_make_materials()
	scenery = Node3D.new()
	scenery.name = "Scenery"
	scenery.set_script(load("res://scripts/hole_scenery.gd"))

	_collect_gameplay_obstacles()
	_generate_back_rows()
	_generate_park()
	_generate_countryside()
	_generate_skyline_and_hills()
	_build_chunk_nodes()
	_build_ground_extras()

	await _bake_sun_mask()
	_save_scene()
	print("Built %s: %d occluders" % [scenery_data["scene"], occluders.size()])
	scenery.free()
	quit()


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _std(color: Color, roughness := 0.85, vertex_colors := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.vertex_color_use_as_albedo = vertex_colors
	return material


func _make_materials() -> void:
	var look: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/looks.json"))[hole["look"]]
	for name in ["building", "building_lite"]:
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/town/%s.gdshader" % name)
		material.set_shader_parameter("lit_ratio", look["lit"])
		materials[name] = material
	var foliage := ShaderMaterial.new()
	foliage.shader = load("res://shaders/town/foliage.gdshader")
	materials["foliage"] = foliage
	materials["props"] = _std(Color.WHITE, 0.85, true)
	materials["trunk"] = _std(Color(0.30, 0.22, 0.16), 0.9)
	materials["lamp_metal"] = _std(Color(0.10, 0.12, 0.11), 0.6)
	var lamp_head := _std(Color(1.0, 0.85, 0.6), 0.4)
	lamp_head.emission_enabled = true
	lamp_head.emission = Color(1.0, 0.75, 0.45)
	lamp_head.emission_energy_multiplier = 0.0  # Off at golden hour; the dusk look turns them on.
	materials["lamp_head"] = lamp_head
	# Cars: plain, clean paint (no metal, no clearcoat), so nothing smears or mirrors.
	materials["car_paint"] = _std(Color.WHITE, 0.5, true)   # tinted per car by the instance colour
	materials["car_glass"] = _std(Color(0.07, 0.09, 0.12), 0.3)
	materials["tire"] = _std(Color(0.05, 0.05, 0.055), 0.9)
	materials["hub"] = _std(Color(0.62, 0.64, 0.66), 0.5)
	materials["cone"] = _std(Color(1.0, 0.42, 0.05), 0.6)
	materials["hill"] = _std(Color(0.22, 0.30, 0.20), 0.95)
	for name in materials:
		ResourceSaver.save(materials[name], out_dir + "materials/%s.tres" % name)
		materials[name] = load(out_dir + "materials/%s.tres" % name)
	# The far-away farmland and road use the shared ground shader; HoleGround makes its own
	# copies of it for the playable area.


# ---------------------------------------------------------------------------
# Gameplay obstacles -> matching art
# ---------------------------------------------------------------------------

func _chunk_of(z: float) -> int:
	return int(floor((STREET_TOP + 40.0 - z) / CHUNK_LENGTH))


func _builder(table: Dictionary, chunk: int, use_custom := false) -> MeshBuilder:
	if not table.has(chunk):
		table[chunk] = MeshBuilder.new(use_custom)
	return table[chunk]


func _collect_gameplay_obstacles() -> void:
	for entry in hole["obstacles"]:
		var at := Vector2(entry["at"][0], entry["at"][1])
		var angle := deg_to_rad(float(entry.get("angle", 0.0)))
		match entry["type"]:
			"building":
				var size := Vector3(entry["size"][0], entry["size"][2], entry["size"][1])  # x, height, z
				_add_building(Vector3(at.x, size.y / 2.0, at.y), size, Color(entry["color"]),
						Color(entry.get("trim", "#ede8d9")), float(entry.get("seed", 1.0)), true, true)
			"car":
				_add_car(at, angle, Color(entry.get("color", "#888888")))
			"lamp":
				_add_lamp(at, angle)
			"tree":
				_add_tree(Vector3(at.x, 0, at.y), float(entry.get("scale", 0.9)) * 0.95, cones_and_lamps_table_trees())
			"cone":
				_chunk_list(cones, at.y).append(Transform3D(Basis.IDENTITY, Vector3(at.x, 0.28, at.y)))


func cones_and_lamps_table_trees() -> Dictionary:
	return trees


func _chunk_list(table: Dictionary, z: float) -> Array:
	var chunk := _chunk_of(z)
	if not table.has(chunk):
		table[chunk] = []
	return table[chunk]


## One building: the walls (shader draws the windows), a cornice lip, maybe an awning and
## rooftop clutter. `is_near` buildings are also recorded as shadow casters.
func _add_building(centre: Vector3, size: Vector3, wall: Color, trim: Color, seed_value: float,
		storefront: bool, with_extras: bool) -> void:
	var chunk := _chunk_of(centre.z)
	var builder := _builder(near_buildings, chunk, true)
	builder.add_box(centre, size, wall, Basis.IDENTITY, {
		"size": size, "storefront": 1.0 if storefront else 0.0, "trim": trim,
		"seed": seed_value, "centre": centre})
	# Cornice lip around the roof edge.
	var lip_size := Vector3(size.x + 0.3, 0.25, size.z + 0.3)
	var lip_centre := Vector3(centre.x, size.y + 0.12, centre.z)
	builder.add_box(lip_centre, lip_size, trim, Basis.IDENTITY, {
		"size": lip_size, "storefront": 0.0, "trim": trim, "seed": seed_value, "centre": lip_centre})
	occluders.append({"shape": "box", "transform": Transform3D(Basis.IDENTITY, centre), "size": size})
	if with_extras:
		_awning_and_roof_clutter(centre, size, chunk)


func _awning_and_roof_clutter(centre: Vector3, size: Vector3, chunk: int) -> void:
	var builder := _builder(props, chunk)
	var side := signf(centre.x)
	# Awning over the shop windows (street-facing side only).
	if absf(centre.x) < 40.0 and rng.randf() < 0.55:
		var colors := [Color(0.15, 0.40, 0.30), Color(0.70, 0.12, 0.10), Color(0.10, 0.25, 0.45), Color(0.85, 0.55, 0.15)]
		var tilt := Basis(Vector3.BACK, side * deg_to_rad(18.0))
		builder.add_box(Vector3(side * (FACADE - 0.7), 3.15, centre.z), Vector3(1.5, 0.06, maxf(size.z - 1.6, 1.0)),
				colors[rng.randi() % colors.size()], tilt)
	# Rooftop boxes (vents, units) and now and then a water tank.
	var roof := Vector3(centre.x, size.y + 0.25, centre.z)
	var grey := Color(0.55, 0.55, 0.55)
	for i in rng.randi_range(0, 3):
		var s := Vector3(rng.randf_range(0.8, 2.0), rng.randf_range(0.6, 1.4), rng.randf_range(0.8, 2.0))
		var off := Vector3(rng.randf_range(-size.x, size.x) * 0.3, s.y * 0.5, rng.randf_range(-size.z, size.z) * 0.3)
		builder.add_box(roof + off, s, grey)
	if rng.randf() < 0.2:
		var tank := roof + Vector3(rng.randf_range(-2.0, 2.0), 2.4, rng.randf_range(-2.0, 2.0))
		builder.add_cylinder(tank, 1.0, 1.0, 2.0, 10, Color(0.42, 0.30, 0.20))
		builder.add_cylinder(tank + Vector3(0, 1.3, 0), 0.1, 1.15, 0.6, 10, Color(0.2, 0.2, 0.2))
		builder.add_box(Vector3(tank.x, roof.y + 0.7, tank.z), Vector3(1.6, 1.4, 1.6), Color(0.1, 0.12, 0.1))


func _add_car(at: Vector2, angle: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, -angle)
	_chunk_list(cars, at.y).append({"transform": Transform3D(basis, Vector3(at.x, 0, at.y)), "color": color})
	occluders.append({"shape": "box", "transform": Transform3D(basis, Vector3(at.x, 0.45, at.y)), "size": Vector3(1.8, 0.9, 4.3)})
	occluders.append({"shape": "box", "transform": Transform3D(basis, Vector3(at.x, 1.25, at.y) + basis * Vector3(0, 0, 0.2)), "size": Vector3(1.6, 0.6, 2.2)})


func _add_lamp(at: Vector2, angle: float) -> void:
	_chunk_list(lamps, at.y).append(Transform3D(Basis(Vector3.UP, -angle), Vector3(at.x, 0, at.y)))
	occluders.append({"shape": "cylinder", "transform": Transform3D(Basis.IDENTITY, Vector3(at.x, 2.3, at.y)), "radius": 0.1, "height": 4.6})
	occluders.append({"shape": "sphere", "transform": Transform3D(Basis.IDENTITY, Vector3(at.x - signf(at.x) * 0.8, 4.35, at.y)), "radius": 0.25})


func _add_tree(position: Vector3, scale: float, table: Dictionary) -> void:
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale)
	_chunk_list(table, position.z).append(Transform3D(basis, position))
	occluders.append({"shape": "cylinder", "transform": Transform3D(Basis.IDENTITY, position + Vector3(0, 1.3 * scale, 0)), "radius": 0.15 * scale, "height": 2.6 * scale})
	occluders.append({"shape": "sphere", "transform": Transform3D(Basis.IDENTITY, position + Vector3(0, 3.6 * scale, 0)), "radius": 1.3 * scale})


# ---------------------------------------------------------------------------
# Decorative scenery (no gameplay)
# ---------------------------------------------------------------------------

# Saturated pastels (the same family as the hole file's street buildings).
const WALL_COLORS := [
	Color("#f0a3c8"), Color("#b59ae6"), Color("#f7d45e"), Color("#8ec9f2"), Color("#f79c86"),
	Color("#9fe0b4"), Color("#f3ead2"), Color("#7fb5e6"), Color("#e8a0b0")]
const TRIM_COLORS := [Color(0.93, 0.91, 0.85), Color(0.20, 0.30, 0.25), Color(0.85, 0.80, 0.70)]


## A taller second row of buildings behind the street front, so the skyline steps up.
func _generate_back_rows() -> void:
	for side in [-1.0, 1.0]:
		var z := STREET_TOP + 20.0
		while z > float(scenery_data["street_end"]) - 10.0:
			var width := rng.randf_range(10.0, 20.0)
			var height := 5.0 + rng.randi_range(1, 6) * 3.2
			var depth := rng.randf_range(12.0, 18.0)
			var cx: float = side * (FACADE + 18.0 + depth * 0.5)
			_add_building(Vector3(cx, height / 2.0, z - width * 0.5), Vector3(depth, height, width),
					WALL_COLORS[rng.randi() % WALL_COLORS.size()], TRIM_COLORS[rng.randi() % TRIM_COLORS.size()],
					rng.randf() * 100.0, false, false)
			z -= width + rng.randf_range(0.0, 6.0)
	# A cross street's worth of buildings closing the far side of the park.
	# (Nothing there: the park opens onto fields.)


var park_trees := {}
var far_props: MeshBuilder
var fence_posts: Array[Transform3D] = []


func _generate_park() -> void:
	var end_z := float(scenery_data["street_end"])
	# Trees around the park, outside the playing area, leaving the view down the road open.
	for i in 34:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var z := rng.randf_range(end_z - 2.0, end_z - 62.0)
		var x := side * rng.randf_range(32.0, 46.0)
		_add_tree(Vector3(x, 0, z), rng.randf_range(1.1, 1.6), park_trees)
	for i in 14:
		var x := rng.randf_range(-44.0, 44.0)
		if absf(x) < 10.0:
			continue
		_add_tree(Vector3(x, 0, rng.randf_range(-124.0, -138.0)), rng.randf_range(1.1, 1.6), park_trees)
	# Benches on the lawn.
	var wood := Color(0.45, 0.30, 0.18)
	var bench_builder := _builder(props, _chunk_of(end_z - 25.0))
	for spot in [Vector3(-14, 0, end_z - 18), Vector3(14, 0, end_z - 21), Vector3(-12, 0, end_z - 40)]:
		bench_builder.add_box(spot + Vector3(0, 0.45, 0), Vector3(0.5, 0.08, 1.8), wood)
		bench_builder.add_box(spot + Vector3(0.22, 0.75, 0), Vector3(0.08, 0.5, 1.8), wood)
		occluders.append({"shape": "box", "transform": Transform3D(Basis.IDENTITY, spot + Vector3(0, 0.6, 0)), "size": Vector3(0.6, 0.8, 1.8)})
	# A low white picket fence along the park's edge (the boundary of the playing area).
	var points: Array = hole["bounds"]["polygon"]
	var rails := _builder(props, _chunk_of(end_z - 25.0))
	for i in points.size():
		var a := Vector2(points[i][0], points[i][1])
		var b := Vector2(points[(i + 1) % points.size()][0], points[(i + 1) % points.size()][1])
		if a.y > end_z + 1.0 or b.y > end_z + 1.0:
			continue  # Only the park part; the street side is walled by buildings.
		if absf(a.x) < 10.0 and absf(b.x) < 10.0 and a.y == b.y:
			continue
		var length := a.distance_to(b)
		var dir := (b - a).normalized()
		var yaw := atan2(-dir.x, -dir.y)
		var mid := (a + b) / 2.0
		var basis := Basis(Vector3.UP, yaw)
		rails.add_box(Vector3(mid.x, 0.7, mid.y), Vector3(0.05, 0.07, length), Color(0.92, 0.9, 0.85), basis)
		rails.add_box(Vector3(mid.x, 0.4, mid.y), Vector3(0.05, 0.07, length), Color(0.92, 0.9, 0.85), basis)
		var count := int(length / 1.6)
		for j in count + 1:
			var p := a.lerp(b, float(j) / count)
			fence_posts.append(Transform3D(basis, Vector3(p.x, 0.45, p.y)))


func _generate_countryside() -> void:
	far_props = MeshBuilder.new()
	var barn := Color(0.55, 0.12, 0.08)
	var roof := Color(0.25, 0.22, 0.22)
	var silo := Color(0.75, 0.75, 0.72)
	far_props.add_box(Vector3(34, 3.5, -250), Vector3(14, 7, 22), barn)
	far_props.add_box(Vector3(30.5, 8.6, -250), Vector3(10.5, 0.3, 23), roof, Basis(Vector3.BACK, deg_to_rad(35.0)))
	far_props.add_box(Vector3(37.5, 8.6, -250), Vector3(10.5, 0.3, 23), roof, Basis(Vector3.BACK, deg_to_rad(-35.0)))
	occluders.append({"shape": "box", "transform": Transform3D(Basis.IDENTITY, Vector3(34, 3.5, -250)), "size": Vector3(14, 7, 22)})
	for i in 2:
		var spot := Vector3(46 + i * 7.5, 0, -262)
		far_props.add_cylinder(spot + Vector3(0, 8, 0), 3.2, 3.2, 16, 20, silo)
		far_props.add_sphere(spot + Vector3(0, 16, 0), 3.2, silo, 0.6, 20, 10)
	# Water tower on the left.
	var tower := Color(0.72, 0.78, 0.80)
	var leg_color := Color(0.12, 0.14, 0.13)
	var tp := Vector3(-42, 0, -240)
	for a in 4:
		var ang := a * PI * 0.5 + PI * 0.25
		far_props.add_cylinder(tp + Vector3(cos(ang) * 3.2, 10, sin(ang) * 3.2), 0.2, 0.28, 20, 6, leg_color)
	far_props.add_sphere(tp + Vector3(0, 23, 0), 5.0, tower, 0.75, 24, 12)
	far_props.add_cylinder(tp + Vector3(0, 27.5, 0), 0.3, 5.2, 2.0, 24, tower)
	# Fence lines down the country road, and tree rows in the fields.
	var fence := Color(0.35, 0.28, 0.2)
	for side in [-1.0, 1.0]:
		far_props.add_box(Vector3(side * 8.0, 1.0, -118.0 - 250.0), Vector3(0.08, 0.08, 500), fence)
		far_props.add_box(Vector3(side * 8.0, 0.55, -118.0 - 250.0), Vector3(0.08, 0.08, 500), fence)
	for i in 40:
		var x := rng.randf_range(-220, 220)
		if absf(x) < 14.0:
			continue
		_add_tree(Vector3(x, 0, rng.randf_range(-230, -520)), rng.randf_range(1.4, 2.4), park_trees)


var skyline: MeshBuilder
var hills: MeshBuilder


func _generate_skyline_and_hills() -> void:
	# A distant downtown off to the right, hazed by fog. Cheap "lite" buildings only.
	skyline = MeshBuilder.new(true)
	for i in 22:
		var w := rng.randf_range(18, 40)
		var h := rng.randf_range(40, 140)
		var x := rng.randf_range(260, 520)
		var z := rng.randf_range(-520, -760)
		var centre := Vector3(x, h / 2.0, z)
		var size := Vector3(w, h, w)
		skyline.add_box(centre, size, WALL_COLORS[rng.randi() % WALL_COLORS.size()], Basis.IDENTITY, {
			"size": size, "storefront": 0.0, "trim": TRIM_COLORS[rng.randi() % TRIM_COLORS.size()],
			"seed": rng.randf() * 100.0, "centre": centre})
	# Rolling hills on the horizon for the sun to set behind.
	hills = MeshBuilder.new()
	for i in 14:
		var hx := -900.0 + i * 140.0 + rng.randf_range(-40, 40)
		var hz := rng.randf_range(-850, -1150)
		var r := rng.randf_range(120, 220)
		hills.add_sphere(Vector3(hx, -r * 0.82, hz), r, Color.WHITE, 1.0, 20, 10)


# ---------------------------------------------------------------------------
# Models (built once, instanced many times)
# ---------------------------------------------------------------------------

func _car_model(detailed: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var paint := MeshBuilder.new()
	paint.add_box(Vector3(0, 0.62, 0), Vector3(1.8, 0.7, 4.3), Color.WHITE)
	paint.add_box(Vector3(0, 1.5, 0.25), Vector3(1.55, 0.06, 1.9), Color.WHITE)   # roof
	if not detailed:
		paint.add_box(Vector3(0, 1.22, 0.2), Vector3(1.6, 0.55, 2.2), Color(0.4, 0.4, 0.45))
		paint.commit_into(mesh, materials["car_paint"])
		return mesh
	paint.commit_into(mesh, materials["car_paint"])
	var glass := MeshBuilder.new()
	glass.add_box(Vector3(0, 1.22, 0.2), Vector3(1.6, 0.55, 2.1), Color.WHITE)
	glass.commit_into(mesh, materials["car_glass"])
	# Round wheels: 20-sided tyres with a lighter hub disc on the outside of each.
	var tire := MeshBuilder.new()
	var hub := MeshBuilder.new()
	var turn := Basis(Vector3.BACK, PI / 2.0)  # cylinder axis Y -> X
	for wx in [-0.8, 0.8]:
		for wz in [-1.35, 1.35]:
			tire.add_cylinder(Vector3(wx, 0.34, wz), 0.34, 0.34, 0.26, 20, Color.WHITE, turn)
			hub.add_cylinder(Vector3(wx + signf(wx) * 0.135, 0.34, wz), 0.19, 0.19, 0.03, 16, Color.WHITE, turn)
	tire.commit_into(mesh, materials["tire"])
	hub.commit_into(mesh, materials["hub"])
	return mesh


func _tree_model(detailed: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var trunk := MeshBuilder.new()
	trunk.add_cylinder(Vector3(0, 1.3, 0), 0.1, 0.16, 2.6, 7 if detailed else 5, Color.WHITE)
	trunk.commit_into(mesh, materials["trunk"])
	var crown := MeshBuilder.new()
	if detailed:
		# Three overlapping blobs make a lumpy crown.
		crown.add_sphere(Vector3(-0.5, 3.4, 0.2), 1.3, Color.WHITE, 0.85, 14, 8)
		crown.add_sphere(Vector3(0.5, 3.1, -0.3), 1.1, Color.WHITE, 0.85, 14, 8)
		crown.add_sphere(Vector3(0.0, 4.0, 0.2), 1.2, Color.WHITE, 0.85, 14, 8)
	else:
		crown.add_sphere(Vector3(0.0, 3.5, 0.0), 1.6, Color.WHITE, 0.85, 8, 5)
	crown.commit_into(mesh, materials["foliage"])
	return mesh


func _lamp_model(detailed: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var metal := MeshBuilder.new()
	metal.add_cylinder(Vector3(0, 2.3, 0), 0.06, 0.09, 4.6, 8 if detailed else 4, Color.WHITE)
	if detailed:
		metal.add_box(Vector3(-0.4, 4.5, 0), Vector3(0.9, 0.06, 0.06), Color.WHITE)
	metal.commit_into(mesh, materials["lamp_metal"])
	if detailed:
		var head := MeshBuilder.new()
		head.add_sphere(Vector3(-0.8, 4.35, 0), 0.22, Color.WHITE, 1.0, 10, 6)
		head.commit_into(mesh, materials["lamp_head"])
	return mesh


func _cone_model() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var cone := MeshBuilder.new()
	cone.add_cylinder(Vector3(0, 0, 0), 0.03, 0.18, 0.55, 10, Color.WHITE)
	cone.commit_into(mesh, materials["cone"])
	return mesh


func _save_mesh(mesh: ArrayMesh, name: String) -> ArrayMesh:
	var path := out_dir + "meshes/%s.res" % name
	ResourceSaver.save(mesh, path)
	return load(path)


# ---------------------------------------------------------------------------
# Putting it together
# ---------------------------------------------------------------------------

func _group(parent: Node3D, name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	parent.add_child(node)
	return node


func _mesh_node(parent: Node3D, name: String, mesh: Mesh, begin := 0.0, end := 0.0, margin := 12.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # shadows are baked
	_set_range(node, begin, end, margin)
	parent.add_child(node)
	return node


func _set_range(node: GeometryInstance3D, begin: float, end: float, margin: float) -> void:
	node.visibility_range_begin = begin
	node.visibility_range_end = end
	if begin > 0.0 or end > 0.0:
		node.visibility_range_begin_margin = margin if begin > 0.0 else 0.0
		node.visibility_range_end_margin = margin if end > 0.0 else 0.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _multimesh_node(parent: Node3D, name: String, mesh: Mesh, transforms: Array, colors: Array,
		begin: float, end: float) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = not colors.is_empty()
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		if not colors.is_empty():
			multimesh.set_instance_color(i, colors[i])
	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set_range(node, begin, end, 8.0)
	parent.add_child(node)


func _build_chunk_nodes() -> void:
	var near_meshes := {
		"car": [_save_mesh(_car_model(true), "car_hi"), _save_mesh(_car_model(false), "car_lo")],
		"tree": [_save_mesh(_tree_model(true), "tree_hi"), _save_mesh(_tree_model(false), "tree_lo")],
		"lamp": [_save_mesh(_lamp_model(true), "lamp_hi"), _save_mesh(_lamp_model(false), "lamp_lo")],
	}
	var cone_mesh := _save_mesh(_cone_model(), "cone")

	var buildings := _group(scenery, "Buildings")
	for chunk in near_buildings:
		var builder: MeshBuilder = near_buildings[chunk]
		_mesh_node(buildings, "near_%d" % chunk, _save_mesh(builder.commit(materials["building"]), "buildings_near_%d" % chunk), 0.0, NEAR_END)
		_mesh_node(buildings, "far_%d" % chunk, _save_mesh(builder.commit(materials["building_lite"]), "buildings_far_%d" % chunk), FAR_BEGIN, 0.0)
	var clutter := _group(scenery, "Clutter")
	for chunk in props:
		var builder: MeshBuilder = props[chunk]
		_mesh_node(clutter, "props_%d" % chunk, _save_mesh(builder.commit(materials["props"]), "props_%d" % chunk), 0.0, PROPS_END)

	var street := _group(scenery, "Street")
	for chunk in cars:
		var transforms: Array = []
		var colors: Array = []
		for car in cars[chunk]:
			transforms.append(car["transform"])
			colors.append(car["color"])
		_multimesh_node(street, "cars_hi_%d" % chunk, near_meshes["car"][0], transforms, colors, 0.0, MODEL_LOD_DISTANCE)
		_multimesh_node(street, "cars_lo_%d" % chunk, near_meshes["car"][1], transforms, colors, MODEL_LOD_DISTANCE, 0.0)
	for chunk in lamps:
		_multimesh_node(street, "lamps_hi_%d" % chunk, near_meshes["lamp"][0], lamps[chunk], [], 0.0, MODEL_LOD_DISTANCE)
		_multimesh_node(street, "lamps_lo_%d" % chunk, near_meshes["lamp"][1], lamps[chunk], [], MODEL_LOD_DISTANCE, 0.0)
	for chunk in trees:
		_multimesh_node(street, "trees_hi_%d" % chunk, near_meshes["tree"][0], trees[chunk], [], 0.0, MODEL_LOD_DISTANCE)
		_multimesh_node(street, "trees_lo_%d" % chunk, near_meshes["tree"][1], trees[chunk], [], MODEL_LOD_DISTANCE, 0.0)
	for chunk in cones:
		_multimesh_node(street, "cones_%d" % chunk, cone_mesh, cones[chunk], [], 0.0, PROPS_END)

	var park := _group(scenery, "Park")
	for chunk in park_trees:
		_multimesh_node(park, "trees_hi_%d" % chunk, near_meshes["tree"][0], park_trees[chunk], [], 0.0, 120.0)
		_multimesh_node(park, "trees_lo_%d" % chunk, near_meshes["tree"][1], park_trees[chunk], [], 120.0, 0.0)
	var post_mesh := ArrayMesh.new()
	var post := MeshBuilder.new()
	post.add_box(Vector3.ZERO, Vector3(0.09, 0.9, 0.09), Color.WHITE)
	post.commit_into(post_mesh, _std(Color(0.92, 0.9, 0.85)))
	_multimesh_node(park, "fence_posts", _save_mesh(post_mesh, "fence_post"), fence_posts, [], 0.0, 160.0)

	var far := _group(scenery, "Far")
	_mesh_node(far, "countryside", _save_mesh(far_props.commit(materials["props"]), "countryside"))
	_mesh_node(far, "skyline", _save_mesh(skyline.commit(materials["building_lite"]), "skyline"))
	_mesh_node(far, "hills", _save_mesh(hills.commit(materials["hill"]), "hills"))


func _build_ground_extras() -> void:
	# Farmland to the horizon under everything, and a country road running toward the sunset.
	var far := scenery.get_node("Far")
	var ground_shader: Shader = load("res://shaders/town/ground.gdshader")
	var farm_material := ShaderMaterial.new()
	farm_material.shader = ground_shader
	farm_material.set_shader_parameter("kind", 4)
	farm_material.set_shader_parameter("mask_strength", 0.0)
	ResourceSaver.save(farm_material, out_dir + "materials/ground_farm.tres")
	var road_material := ShaderMaterial.new()
	road_material.shader = ground_shader
	road_material.set_shader_parameter("kind", 0)
	road_material.set_shader_parameter("street_half", 3.0)
	road_material.set_shader_parameter("street_end_z", 1000.0)  # No town markings out here.
	road_material.set_shader_parameter("mask_strength", 0.0)
	ResourceSaver.save(road_material, out_dir + "materials/ground_road.tres")
	var farm_mesh := PlaneMesh.new()
	farm_mesh.size = Vector2(9000, 9000)
	var farm := _mesh_node(far, "farmland", farm_mesh)
	farm.material_override = load(out_dir + "materials/ground_farm.tres")
	farm.position = Vector3(0, -0.02, -2000)
	var road_mesh := PlaneMesh.new()
	road_mesh.size = Vector2(6, 1400)
	var road := _mesh_node(far, "country_road", road_mesh)
	road.material_override = load(out_dir + "materials/ground_road.tres")
	road.position = Vector3(0, -0.005, -118.0 - 700.0)


# ---------------------------------------------------------------------------
# Baked lighting: sun shadows + ambient occlusion on the ground
# ---------------------------------------------------------------------------

func _bake_sun_mask() -> void:
	var look: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/looks.json"))[hole["look"]]
	var elevation := deg_to_rad(float(look["elev"]))
	var azimuth := deg_to_rad(float(look["azim"]))
	# Direction from the ground toward the sun (same convention as LookSetup).
	var to_sun := Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation)).normalized()

	# Put every shadow-casting shape into a private physics world, so we can shoot rays at it.
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var physics_rids: Array[RID] = []
	for occluder in occluders:
		var shape: RID
		match occluder["shape"]:
			"box":
				shape = PhysicsServer3D.box_shape_create()
				PhysicsServer3D.shape_set_data(shape, occluder["size"] / 2.0)
			"sphere":
				shape = PhysicsServer3D.sphere_shape_create()
				PhysicsServer3D.shape_set_data(shape, occluder["radius"])
			_:
				shape = PhysicsServer3D.cylinder_shape_create()
				PhysicsServer3D.shape_set_data(shape, {"radius": occluder["radius"], "height": occluder["height"]})
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, occluder["transform"])
		physics_rids.append(body)
		physics_rids.append(shape)
	await physics_frame
	await physics_frame
	var state := PhysicsServer3D.space_get_direct_state(space)

	var width := int((MASK_X.y - MASK_X.x) / MASK_RESOLUTION)
	var length := int((MASK_Z.y - MASK_Z.x) / MASK_RESOLUTION)
	var sun := PackedFloat32Array()
	var open_sky := PackedFloat32Array()
	sun.resize(width * length)
	open_sky.resize(width * length)
	# A few sun rays spread across the sun's disc give soft shadow edges; a few short
	# rays fanned overhead measure how enclosed a spot is (ambient occlusion).
	var sun_jitter := [Vector3.ZERO, Vector3(0.012, 0.004, 0), Vector3(-0.012, 0.004, 0), Vector3(0, 0.012, 0), Vector3(0, -0.002, 0)]
	var sky_rays := [Vector3(0, 1, 0), Vector3(0.6, 0.8, 0), Vector3(-0.6, 0.8, 0), Vector3(0, 0.8, 0.6), Vector3(0, 0.8, -0.6)]
	var query := PhysicsRayQueryParameters3D.new()
	query.hit_from_inside = true  # A point under a car is inside its box: that counts as shadow.
	for row in length:
		for col in width:
			var origin := Vector3(MASK_X.x + (col + 0.5) * MASK_RESOLUTION, 0.05, MASK_Z.x + (row + 0.5) * MASK_RESOLUTION)
			var lit := 0
			for jitter in sun_jitter:
				query.from = origin
				query.to = origin + (to_sun + jitter).normalized() * 500.0
				if state.intersect_ray(query).is_empty():
					lit += 1
			var open := 0
			for ray in sky_rays:
				query.from = origin
				query.to = origin + ray.normalized() * 2.5
				if state.intersect_ray(query).is_empty():
					open += 1
			sun[row * width + col] = float(lit) / sun_jitter.size()
			open_sky[row * width + col] = float(open) / sky_rays.size()

	# A light blur softens the pixel stair-steps on the shadow edges.
	var image := Image.create(width, length, false, Image.FORMAT_RG8)
	for row in length:
		for col in width:
			var total := 0.0
			var count := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var r := clampi(row + dy, 0, length - 1)
					var c := clampi(col + dx, 0, width - 1)
					total += sun[r * width + c]
					count += 1
			# Ambient occlusion keeps some light even in the darkest corner.
			var ao := lerpf(0.45, 1.0, open_sky[row * width + col])
			image.set_pixel(col, row, Color(total / count, ao, 0.0))
	for rid in physics_rids:
		PhysicsServer3D.free_rid(rid)
	PhysicsServer3D.free_rid(space)
	image.save_png(scenery_data["sun_mask"])
	scenery.set("mask_rect", Rect2(MASK_X.x, MASK_Z.x, MASK_X.y - MASK_X.x, MASK_Z.y - MASK_Z.x))
	scenery.set("to_sun", to_sun)


func _save_scene() -> void:
	_set_owner(scenery, scenery)
	var packed := PackedScene.new()
	packed.pack(scenery)
	ResourceSaver.save(packed, scenery_data["scene"])


func _set_owner(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_set_owner(child, owner_node)
