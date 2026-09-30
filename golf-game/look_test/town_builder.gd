extends Node3D
## Builds the "Main Street Opener" look-test hole out of primitives + procedural shaders:
## a small-town main street running west into the sunset, a park with the green at the end,
## farmland and a country road to the horizon, and a distant city skyline to one side.
## Also answers ground queries (height / surface) so a real ball can be dropped in later.

# Shaders are loaded at build time (not preloaded) because they use global shader
# uniforms that look_test.gd registers first, so project.godot stays untouched.
const SHADER_DIR := "res://look_test/shaders/"

const STREET_HALF := 5.0
const WALK_OUTER := 8.5
const STREET_START := 45.0
const STREET_END := -112.0
const PARK_END := -162.0
const PARK_HALF := 32.0
const COUNTRY_ROAD_HALF := 3.0
const GREEN_CENTER := Vector2(1.0, -136.0)
const GREEN_RADIUS := 11.0
const CUP_POS := Vector3(1.5, 0.0, -137.0)
const TEE_POS := Vector3(-1.5, 0.0, 0.0)

const WALL_COLORS := [
	Color(0.62, 0.26, 0.20), Color(0.85, 0.78, 0.62), Color(0.55, 0.62, 0.50),
	Color(0.55, 0.66, 0.74), Color(0.78, 0.45, 0.30), Color(0.86, 0.70, 0.35),
	Color(0.45, 0.28, 0.25), Color(0.90, 0.88, 0.84), Color(0.70, 0.52, 0.60),
]
const TRIM_COLORS := [Color(0.93, 0.91, 0.85), Color(0.20, 0.30, 0.25), Color(0.85, 0.80, 0.70)]
const CAR_COLORS := [
	Color(0.75, 0.10, 0.08), Color(0.10, 0.25, 0.60), Color(0.92, 0.92, 0.90),
	Color(0.08, 0.08, 0.09), Color(0.20, 0.55, 0.45), Color(0.95, 0.75, 0.15), Color(0.55, 0.57, 0.60),
]
const AWNING_COLORS := [Color(0.15, 0.40, 0.30), Color(0.70, 0.12, 0.10), Color(0.10, 0.25, 0.45), Color(0.85, 0.55, 0.15)]

## Box colliders the ball can hit: [{"box": AABB, "mat": "glass"|"concrete"|"metal"}]
var colliders: Array = []
var building_mat: ShaderMaterial
var lamp_mat: StandardMaterial3D
var reflection_probe: ReflectionProbe
var rng := RandomNumberGenerator.new()

var _ground_mats := {}
var _foliage_mat: ShaderMaterial
var _trunk_mat: StandardMaterial3D
var _dark_metal: StandardMaterial3D
var _white: StandardMaterial3D
var _car_glass: StandardMaterial3D
var _tire_mat: StandardMaterial3D


func build() -> void:
	rng.seed = 20260929
	_make_materials()
	_build_ground()
	_build_street_buildings()
	_build_back_rows()
	_build_street_props()
	_build_park()
	_build_countryside()
	_build_skyline()
	_build_reflection_probe()


# ---------------------------------------------------------------- ground queries

func height_at(x: float, z: float) -> float:
	if absf(x) > STREET_HALF and absf(x) < WALK_OUTER and z < STREET_START and z > STREET_END:
		return 0.15
	return 0.0


func surface_at(x: float, z: float) -> String:
	if z > STREET_END and z < STREET_START:
		return "asphalt" if absf(x) <= STREET_HALF else "concrete"
	if Vector2(x, z).distance_to(GREEN_CENTER) < GREEN_RADIUS:
		return "green"
	if z > PARK_END and absf(x) < PARK_HALF:
		return "grass"
	if z <= PARK_END and absf(x) < COUNTRY_ROAD_HALF:
		return "asphalt"
	return "rough"


func in_bounds(p: Vector3) -> bool:
	return absf(p.x) < 60.0 and p.z < 60.0 and p.z > -420.0 and p.y > -5.0


## True if a ray from `origin` along `dir` hits any building within `max_dist`.
func ray_blocked(origin: Vector3, dir: Vector3, max_dist: float = 400.0) -> bool:
	for c in colliders:
		if c.mat == "metal":
			continue
		var box: AABB = c.box
		if box.intersects_segment(origin, origin + dir * max_dist):
			return true
	return false


# ---------------------------------------------------------------- materials

func _make_materials() -> void:
	building_mat = ShaderMaterial.new()
	building_mat.shader = load(SHADER_DIR + "building.gdshader")
	var ground_shader: Shader = load(SHADER_DIR + "ground.gdshader")

	for kind in 5:
		var m := ShaderMaterial.new()
		m.shader = ground_shader
		m.set_shader_parameter("kind", kind)
		_ground_mats[kind] = m

	_foliage_mat = ShaderMaterial.new()
	_foliage_mat.shader = load(SHADER_DIR + "foliage.gdshader")

	_trunk_mat = _std(Color(0.30, 0.22, 0.16), 0.9)
	_dark_metal = _std(Color(0.08, 0.12, 0.10), 0.45, 0.6)
	_white = _std(Color(0.92, 0.92, 0.9), 0.5)
	_tire_mat = _std(Color(0.05, 0.05, 0.05), 0.8)
	_car_glass = _std(Color(0.06, 0.08, 0.10), 0.04, 0.9)

	lamp_mat = _std(Color(1.0, 0.85, 0.6), 0.4)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.75, 0.45)
	lamp_mat.emission_energy_multiplier = 0.0


func _std(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


# ---------------------------------------------------------------- helpers

func _box(size: Vector3, pos: Vector3, mat: Material, shadows := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _cyl(radius_top: float, radius_bottom: float, height: float, pos: Vector3, mat: Material, segments := 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_top
	mesh.bottom_radius = radius_bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _sphere(radius: float, pos: Vector3, mat: Material, squash := 1.0, segments := 16) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 * squash
	mesh.radial_segments = segments
	mesh.rings = segments / 2
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _plane(size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _add_collider(center: Vector3, size: Vector3, mat: String) -> void:
	colliders.append({"box": AABB(center - size * 0.5, size), "mat": mat})


# ---------------------------------------------------------------- ground

func _build_ground() -> void:
	var street_len := STREET_START - STREET_END
	var street_mid := (STREET_START + STREET_END) * 0.5
	# farmland to the horizon
	_plane(Vector2(9000, 9000), Vector3(0, -0.02, -2000), _ground_mats[4])
	# main street + sidewalks (sidewalks are raised 15 cm)
	_plane(Vector2(STREET_HALF * 2.0, street_len), Vector3(0, 0, street_mid), _ground_mats[0])
	for side in [-1.0, 1.0]:
		var w := WALK_OUTER - STREET_HALF
		var walk := _box(Vector3(w, 0.15, street_len), Vector3(side * (STREET_HALF + w * 0.5), 0.075, street_mid), _ground_mats[1], false)
		walk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# park lawn
	var park_len := STREET_END - PARK_END
	_plane(Vector2(PARK_HALF * 2.0, park_len), Vector3(0, -0.005, (STREET_END + PARK_END) * 0.5), _ground_mats[2])
	# putting green (a very flat disc)
	var green := _cyl(GREEN_RADIUS, GREEN_RADIUS, 0.02, Vector3(GREEN_CENTER.x, 0.0, GREEN_CENTER.y), _ground_mats[3], 48)
	green.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# country road running off toward the sunset
	var road_len := 1400.0
	_plane(Vector2(COUNTRY_ROAD_HALF * 2.0, road_len), Vector3(0, 0.0, PARK_END - road_len * 0.5), _ground_mats[0])


# ---------------------------------------------------------------- buildings

func _building(center_xz: Vector2, size: Vector3, storefront: bool) -> MeshInstance3D:
	var pos := Vector3(center_xz.x, size.y * 0.5, center_xz.y)
	var mi := _box(size, pos, building_mat)
	mi.set_instance_shader_parameter("bldg_size", size)
	mi.set_instance_shader_parameter("wall_color", WALL_COLORS[rng.randi() % WALL_COLORS.size()])
	mi.set_instance_shader_parameter("trim_color", TRIM_COLORS[rng.randi() % TRIM_COLORS.size()])
	mi.set_instance_shader_parameter("seed", rng.randf() * 100.0)
	mi.set_instance_shader_parameter("storefront", 1.0 if storefront else 0.0)
	# cornice lip
	var lip_mat := _std(Color(0.85, 0.82, 0.76), 0.8)
	_box(Vector3(size.x + 0.3, 0.25, size.z + 0.3), Vector3(pos.x, size.y + 0.12, pos.z), lip_mat)
	return mi


func _build_street_buildings() -> void:
	for side in [-1.0, 1.0]:
		var z := STREET_START
		while z > STREET_END + 6.0:
			if rng.randf() < 0.14:
				z -= rng.randf_range(2.5, 4.0)   # alley
				continue
			var width := minf(rng.randf_range(7.0, 14.0), z - STREET_END)
			var depth := rng.randf_range(10.0, 15.0)
			var stories := rng.randi_range(1, 4)
			var height := 3.8 + (stories - 1) * 3.2 + 1.0
			var cx: float = side * (WALK_OUTER + depth * 0.5)
			var cz := z - width * 0.5
			var size := Vector3(depth, height, width)
			_building(Vector2(cx, cz), size, true)
			_add_collider(Vector3(cx, height * 0.5, cz), size, "glass")
			if rng.randf() < 0.55:
				_awning(side, cz, width)
			_rooftop_clutter(Vector3(cx, height, cz), size)
			z -= width


func _awning(side: float, cz: float, width: float) -> void:
	var mat := _std(AWNING_COLORS[rng.randi() % AWNING_COLORS.size()], 0.8)
	var aw := _box(Vector3(1.5, 0.06, width - 1.6), Vector3(side * (WALK_OUTER - 0.7), 3.15, cz), mat)
	aw.rotation.z = side * deg_to_rad(18.0)


func _rooftop_clutter(roof: Vector3, size: Vector3) -> void:
	var grey := _std(Color(0.55, 0.55, 0.55), 0.6, 0.4)
	for i in rng.randi_range(0, 3):
		var s := Vector3(rng.randf_range(0.8, 2.0), rng.randf_range(0.6, 1.4), rng.randf_range(0.8, 2.0))
		var off := Vector3(rng.randf_range(-size.x, size.x) * 0.3, s.y * 0.5, rng.randf_range(-size.z, size.z) * 0.3)
		_box(s, roof + off, grey)
	if rng.randf() < 0.2:
		# wooden water tank on legs
		var tank_pos := roof + Vector3(rng.randf_range(-2.0, 2.0), 2.4, rng.randf_range(-2.0, 2.0))
		_cyl(1.0, 1.0, 2.0, tank_pos, _std(Color(0.42, 0.30, 0.20), 0.9), 10)
		_cyl(0.1, 1.15, 0.6, tank_pos + Vector3(0, 1.3, 0), _std(Color(0.2, 0.2, 0.2), 0.7), 10)
		_box(Vector3(1.6, 1.4, 1.6), roof + Vector3(tank_pos.x - roof.x, 0.7, tank_pos.z - roof.z), _dark_metal)


func _build_back_rows() -> void:
	# taller second row behind main street so the roofline steps up
	for side in [-1.0, 1.0]:
		var z := STREET_START + 20.0
		while z > STREET_END - 10.0:
			var width := rng.randf_range(10.0, 20.0)
			var height := 5.0 + rng.randi_range(1, 6) * 3.2
			var depth := rng.randf_range(12.0, 18.0)
			var cx: float = side * (WALK_OUTER + 18.0 + depth * 0.5)
			_building(Vector2(cx, z - width * 0.5), Vector3(depth, height, width), false)
			z -= width + rng.randf_range(0.0, 6.0)


# ---------------------------------------------------------------- street props

func _build_street_props() -> void:
	for side in [-1.0, 1.0]:
		var z := STREET_START - 4.0
		var i := 0
		while z > STREET_END + 4.0:
			if i % 2 == 0:
				_lamp(Vector3(side * 5.6, 0.15, z), side)
			elif rng.randf() < 0.8:
				_tree(Vector3(side * 6.4, 0.15, z), 0.85)
			z -= 8.0
			i += 1
		# parked cars along the curb
		z = STREET_START - 6.0
		while z > STREET_END + 6.0:
			if rng.randf() < 0.55 and absf(z + 19.0) > 5.0:
				_car(Vector3(side * 3.9, 0.0, z), side)
			z -= 6.5


func _lamp(pos: Vector3, side: float) -> void:
	var pole := _cyl(0.06, 0.09, 4.6, pos + Vector3(0, 2.3, 0), _dark_metal, 8)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_box(Vector3(0.9, 0.06, 0.06), pos + Vector3(-side * 0.4, 4.5, 0), _dark_metal)
	_sphere(0.22, pos + Vector3(-side * 0.8, 4.35, 0), lamp_mat, 1.0, 10)
	_add_collider(pos + Vector3(0, 2.3, 0), Vector3(0.18, 4.6, 0.18), "metal")


func _tree(pos: Vector3, scale: float) -> void:
	var trunk_h := 2.6 * scale
	_cyl(0.1 * scale, 0.16 * scale, trunk_h, pos + Vector3(0, trunk_h * 0.5, 0), _trunk_mat, 7)
	for k in 3:
		var r := rng.randf_range(1.0, 1.5) * scale
		var off := Vector3(rng.randf_range(-0.6, 0.6), trunk_h + rng.randf_range(0.3, 1.4), rng.randf_range(-0.6, 0.6)) * scale
		_sphere(r, pos + off, _foliage_mat, 0.85, 14)


func _car(pos: Vector3, side: float) -> void:
	var paint := _std(CAR_COLORS[rng.randi() % CAR_COLORS.size()], 0.28, 0.45)
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.8
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = 0.0 if side > 0.0 else PI
	add_child(root)
	var body := _box(Vector3(1.8, 0.7, 4.3), Vector3(0, 0.62, 0), paint)
	body.reparent(root, false)
	var cabin := _box(Vector3(1.6, 0.55, 2.2), Vector3(0, 1.22, 0.2), _car_glass)
	cabin.reparent(root, false)
	var roof := _box(Vector3(1.55, 0.06, 1.9), Vector3(0, 1.5, 0.25), paint)
	roof.reparent(root, false)
	for wx in [-0.8, 0.8]:
		for wz in [-1.35, 1.35]:
			var wheel := _cyl(0.33, 0.33, 0.24, Vector3(wx, 0.33, wz), _tire_mat, 12)
			wheel.rotation.z = PI * 0.5
			wheel.reparent(root, false)
	_add_collider(pos + Vector3(0, 0.75, 0), Vector3(1.8, 1.5, 4.3), "metal")


# ---------------------------------------------------------------- park + green

func _build_park() -> void:
	# ring of trees around the park, leaving the view down the country road open
	for i in 26:
		var t := float(i) / 26.0
		var z := lerpf(STREET_END - 6.0, PARK_END + 2.0, t)
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.75:
				_tree(Vector3(side * rng.randf_range(20.0, 30.0), 0.0, z + rng.randf_range(-2.0, 2.0)), rng.randf_range(1.1, 1.6))
	# benches
	var wood := _std(Color(0.45, 0.30, 0.18), 0.85)
	for b in [Vector3(-14, 0, -125), Vector3(14, 0, -128), Vector3(-12, 0, -150)]:
		_box(Vector3(0.5, 0.08, 1.8), b + Vector3(0, 0.45, 0), wood)
		_box(Vector3(0.08, 0.5, 1.8), b + Vector3(0.22, 0.75, 0), wood)
	# traffic cones where the street meets the park
	var cone_mat := _std(Color(1.0, 0.42, 0.05), 0.6)
	for x in [-3.5, -1.2, 1.2, 3.5]:
		_cyl(0.03, 0.18, 0.55, Vector3(x, 0.28, STREET_END - 1.5), cone_mat, 10)
	# cup + pin + flag
	var cup := _cyl(0.2, 0.2, 0.02, CUP_POS + Vector3(0, 0.012, 0), _std(Color(0.02, 0.02, 0.02), 1.0), 20)
	cup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cyl(0.025, 0.025, 2.6, CUP_POS + Vector3(0, 1.3, 0), _white, 8)
	var flag_mesh := PlaneMesh.new()
	flag_mesh.size = Vector2(0.9, 0.6)
	flag_mesh.orientation = PlaneMesh.FACE_Z
	flag_mesh.subdivide_width = 12
	var flag_mat := ShaderMaterial.new()
	flag_mat.shader = load(SHADER_DIR + "flag.gdshader")
	var flag := MeshInstance3D.new()
	flag.mesh = flag_mesh
	flag.material_override = flag_mat
	flag.position = CUP_POS + Vector3(0.45, 2.3, 0)
	add_child(flag)


# ---------------------------------------------------------------- countryside + horizon

func _build_countryside() -> void:
	var red_barn := _std(Color(0.55, 0.12, 0.08), 0.85)
	var roof_mat := _std(Color(0.25, 0.22, 0.22), 0.7, 0.3)
	var silo_mat := _std(Color(0.75, 0.75, 0.72), 0.35, 0.6)
	# barn + silos on the right
	_box(Vector3(14, 7, 22), Vector3(34, 3.5, -250), red_barn)
	var roof := _box(Vector3(10.5, 0.3, 23), Vector3(30.5, 8.6, -250), roof_mat)
	roof.rotation.z = deg_to_rad(35.0)
	var roof2 := _box(Vector3(10.5, 0.3, 23), Vector3(37.5, 8.6, -250), roof_mat)
	roof2.rotation.z = deg_to_rad(-35.0)
	for i in 2:
		var sp := Vector3(46 + i * 7.5, 0, -262)
		_cyl(3.2, 3.2, 16, sp + Vector3(0, 8, 0), silo_mat, 20)
		_sphere(3.2, sp + Vector3(0, 16, 0), silo_mat, 0.6, 20)
	# small-town water tower on the left
	var tower_mat := _std(Color(0.72, 0.78, 0.80), 0.4, 0.5)
	var tp := Vector3(-42, 0, -240)
	for a in 4:
		var ang := a * PI * 0.5 + PI * 0.25
		var leg := _cyl(0.2, 0.28, 20, tp + Vector3(cos(ang) * 3.2, 10, sin(ang) * 3.2), _dark_metal, 6)
		leg.rotation.z = cos(ang) * 0.06
		leg.rotation.x = -sin(ang) * 0.06
	_sphere(5.0, tp + Vector3(0, 23, 0), tower_mat, 0.75, 24)
	_cyl(0.3, 5.2, 2.0, tp + Vector3(0, 27.5, 0), tower_mat, 24)
	# fence lines + tree rows along field edges
	var fence_mat := _std(Color(0.35, 0.28, 0.2), 0.9)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.08, 0.08, 500), Vector3(side * 8.0, 1.0, PARK_END - 250), fence_mat)
		_box(Vector3(0.08, 0.08, 500), Vector3(side * 8.0, 0.55, PARK_END - 250), fence_mat)
		var z := PARK_END - 4.0
		while z > PARK_END - 500.0:
			_cyl(0.06, 0.06, 1.3, Vector3(side * 8.0, 0.65, z), fence_mat, 5)
			z -= 5.0
	for i in 40:
		var x := rng.randf_range(-220, 220)
		var z := rng.randf_range(-230, -520)
		if absf(x) < 14.0:
			continue
		_tree(Vector3(x, 0, z), rng.randf_range(1.4, 2.4))
	# rolling hills on the horizon for the sun to set behind
	var hill_mat := _std(Color(0.22, 0.30, 0.20), 0.95)
	for i in 14:
		var hx := -900.0 + i * 140.0 + rng.randf_range(-40, 40)
		var hz := rng.randf_range(-850, -1150)
		var r := rng.randf_range(120, 220)
		var hill := _sphere(r, Vector3(hx, -r * 0.82, hz), hill_mat, 1.0, 24)
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_skyline() -> void:
	# a distant downtown off to the right, hazed by fog; its glass catches the sun
	for i in 22:
		var w := rng.randf_range(18, 40)
		var h := rng.randf_range(40, 140)
		var x := rng.randf_range(260, 520)
		var z := rng.randf_range(-520, -760)
		var mi := _building(Vector2(x, z), Vector3(w, h, w), false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_reflection_probe() -> void:
	reflection_probe = ReflectionProbe.new()
	reflection_probe.size = Vector3(60, 40, 220)
	reflection_probe.position = Vector3(0, 12, -40)
	reflection_probe.box_projection = true
	reflection_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	reflection_probe.intensity = 1.0
	reflection_probe.max_distance = 1500.0
	add_child(reflection_probe)
