class_name HoleGround
extends Node3D
## Draws a hole's ground from its SurfaceMap: a big base plane, the playable area,
## every surface zone (fairway, green, water, potholes...), white out-of-bounds
## stakes around the edge, and the solid obstacles (cars, walls, hay bales...).
##
## Everything is flat. Zones are stacked a few millimetres apart in draw order so they
## don't flicker where they overlap; the ball physics still treats y = 0 as the ground.

const LAYER_GAP := 0.004     # Height between stacked zones, in metres.
const STAKE_SPACING := 6.0   # Metres between out-of-bounds stakes.

## Set before adding to the scene.
## A themed hole (one with its own scenery scene) draws its ground with the town ground
## shader instead of flat colours. `theme` then holds: sun_mask (Texture2D), mask_rect
## (Rect2), street_half, street_end_z, crosswalk_z (Vector2) and stakes (bool).
## Leave it empty for the plain flat-colour look.
var theme := {}
var surfaces: SurfaceMap
# Which shader "kind" draws each surface in a themed hole (see ground.gdshader).
const THEME_KINDS := {
	"street": 0, "sidewalk": 1, "rough": 2, "green": 3, "oob": 4, "fairway": 5, "tee": 6,
}
const GROUND_SHADER := "res://shaders/town/ground.gdshader"

var _themed_materials := {}

## Where the base plane is centred (the middle of the hole).
var centre := Vector3.ZERO
## Height just above the top zone. Anything painted on the ground goes here.
var top_height := 0.0


func _ready() -> void:
	# The base plane: out of bounds if the hole has a boundary, otherwise its normal ground.
	var base_type := "oob" if not surfaces.bounds.is_empty() else surfaces.ground
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var base := MeshInstance3D.new()
	base.mesh = plane
	base.material_override = _material(base_type)
	base.position = centre
	add_child(base)

	var height := LAYER_GAP
	if not surfaces.bounds.is_empty():
		_add_flat_polygon(surfaces.bounds, surfaces.ground, height)
		if theme.get("stakes", true):
			_add_stakes(surfaces.bounds, height)
		height += LAYER_GAP
	for zone in surfaces.zones:
		_add_flat_polygon(zone["points"], zone["type"], height)
		height += LAYER_GAP
	top_height = height
	# A themed hole's scenery scene already draws its obstacles (cars, buildings...).
	if theme.is_empty():
		for part in surfaces.obstacles.parts:
			_add_obstacle_part(part)


## One box or cylinder of an obstacle, standing on the ground. (Placeholder shapes:
## the art pass in Milestone 7 swaps these for real models and instances repeats.)
func _add_obstacle_part(part: Dictionary) -> void:
	var mesh: Mesh
	if part["shape"] == "box":
		var box := BoxMesh.new()
		box.size = Vector3(part["half"].x * 2.0, part["height"], part["half"].y * 2.0)
		mesh = box
	else:
		var cylinder := CylinderMesh.new()
		cylinder.bottom_radius = part["radius"]
		cylinder.top_radius = part["radius"] * (0.15 if part["taper"] else 1.0)
		cylinder.height = part["height"]
		mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = part["color"]
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	# Meshes are centred on their middle, so lift by half the height. A negative
	# turn around UP is clockwise from above, matching the hole file's "angle".
	instance.transform = Transform3D(Basis(Vector3.UP, -part["angle"]),
			Vector3(part["centre"].x, part["height"] / 2.0, part["centre"].y))
	add_child(instance)


## A flat polygon lying on the ground at `height`, coloured by its surface type.
func _add_flat_polygon(points: PackedVector2Array, type_name: String, height: float) -> void:
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		push_error("Could not draw a %s zone; is its outline crossing itself?" % type_name)
		return
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	# Godot draws a triangle's front when its corners run clockwise as seen from the
	# front. Make sure every triangle faces UP, whichever way the triangulation wound it.
	for i in range(0, triangles.size(), 3):
		var a := Vector3(points[triangles[i]].x, height, points[triangles[i]].y)
		var b := Vector3(points[triangles[i + 1]].x, height, points[triangles[i + 1]].y)
		var c := Vector3(points[triangles[i + 2]].x, height, points[triangles[i + 2]].y)
		if (b - a).cross(c - a).y > 0.0:
			var swap := b
			b = c
			c = swap
		tool.add_vertex(a)
		tool.add_vertex(b)
		tool.add_vertex(c)
	var instance := MeshInstance3D.new()
	instance.mesh = tool.commit()
	instance.material_override = _material(type_name)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## White stakes every few metres along the boundary, like a real course's OB markers.
func _add_stakes(outline: PackedVector2Array, height: float) -> void:
	var stake := BoxMesh.new()
	stake.size = Vector3(0.12, 0.9, 0.12)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	stake.material = material
	var spots: Array[Vector3] = []
	for i in outline.size():
		var from := outline[i]
		var to := outline[(i + 1) % outline.size()]
		var count := maxi(1, int(from.distance_to(to) / STAKE_SPACING))
		for j in count:
			var spot := from.lerp(to, float(j) / count)
			spots.append(Vector3(spot.x, height + stake.size.y / 2.0, spot.y))
	# One MultiMesh for all stakes = one draw call.
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = stake
	multimesh.instance_count = spots.size()
	for i in spots.size():
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i]))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	add_child(instance)


func _material(type_name: String) -> Material:
	if not theme.is_empty() and THEME_KINDS.has(type_name):
		return _themed_material(THEME_KINDS[type_name])
	var material := StandardMaterial3D.new()
	material.albedo_color = SurfaceMap.get_type(type_name)["color"]
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible whichever way the triangles wind.
	if type_name == "water":
		material.roughness = 0.05
		material.metallic_specular = 1.0
	return material


## The town ground shader set to draw one kind of surface. Shared by every zone of that
## kind, and handed the baked sun-shadow mask.
func _themed_material(kind: int) -> ShaderMaterial:
	if _themed_materials.has(kind):
		return _themed_materials[kind]
	var material := ShaderMaterial.new()
	material.shader = load(GROUND_SHADER)
	material.set_shader_parameter("kind", kind)
	material.set_shader_parameter("street_half", theme.get("street_half", 5.0))
	material.set_shader_parameter("street_end_z", theme.get("street_end_z", -82.0))
	material.set_shader_parameter("crosswalk_z", theme.get("crosswalk_z", Vector2(-31.0, -78.0)))
	if theme.has("sun_mask"):
		material.set_shader_parameter("sun_mask", theme["sun_mask"])
		material.set_shader_parameter("mask_rect", Vector4(theme["mask_rect"].position.x,
				theme["mask_rect"].position.y, theme["mask_rect"].size.x, theme["mask_rect"].size.y))
	_themed_materials[kind] = material
	return material
