class_name MeshBuilder
extends RefCounted
## Collects boxes, cylinders and spheres into ONE mesh, so a whole row of buildings (or
## every rooftop vent on a block) is a single object the GPU draws in a single call.
## Used by the scenery generator tools; the game itself never needs this.
##
## Everything is added in final (world) positions. Each shape gets a vertex colour.
## Building boxes also carry extra per-vertex data ("custom" channels) that the building
## shader reads: see shaders/town/building_common.gdshaderinc.

var _surface := SurfaceTool.new()
var _use_custom := false
var vertex_count := 0


func _init(use_custom := false) -> void:
	_use_custom = use_custom
	_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if use_custom:
		_surface.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
		_surface.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
		_surface.set_custom_format(2, SurfaceTool.CUSTOM_RGB_FLOAT)


func is_empty() -> bool:
	return vertex_count == 0


## The finished mesh (with `material` on it). The builder can be committed more than
## once, e.g. to make near and far copies of the same geometry.
func commit(material: Material) -> ArrayMesh:
	var mesh := _surface.commit()
	mesh.surface_set_material(0, material)
	return mesh


## Add a finished mesh as another surface of `mesh` (for models with several materials).
func commit_into(mesh: ArrayMesh, material: Material) -> void:
	_surface.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


# ---------------------------------------------------------------------------
# Shapes
# ---------------------------------------------------------------------------

## A box. `custom` = optional per-building data for the building shader:
## { size: Vector3, storefront: float, trim: Color, seed: float, centre: Vector3 }.
func add_box(centre: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY,
		custom := {}) -> void:
	var half := size / 2.0
	var faces := [
		[Vector3.RIGHT, Vector3.BACK], [Vector3.LEFT, Vector3.FORWARD],
		[Vector3.UP, Vector3.RIGHT], [Vector3.DOWN, Vector3.LEFT],
		[Vector3.BACK, Vector3.LEFT], [Vector3.FORWARD, Vector3.RIGHT],
	]
	for face in faces:
		var normal: Vector3 = face[0]
		var tangent: Vector3 = face[1]
		var bitangent := normal.cross(tangent)
		var centre_of_face := normal * (half * normal.abs()).length()
		var t := tangent * (half * tangent.abs()).length()
		var b := bitangent * (half * bitangent.abs()).length()
		var corners: Array[Vector3] = [
			centre_of_face - t - b, centre_of_face + t - b,
			centre_of_face + t + b, centre_of_face - t + b]
		_add_quad(corners, normal, centre, basis, color, custom)


## An upright cylinder (or cone, if the radii differ), axis = local Y.
func add_cylinder(centre: Vector3, radius_top: float, radius_bottom: float, height: float,
		segments: int, color: Color, basis := Basis.IDENTITY, caps := true) -> void:
	var half := height / 2.0
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var top0 := d0 * radius_top + Vector3(0, half, 0)
		var top1 := d1 * radius_top + Vector3(0, half, 0)
		var bottom0 := d0 * radius_bottom + Vector3(0, -half, 0)
		var bottom1 := d1 * radius_bottom + Vector3(0, -half, 0)
		# Side: smooth shading, so each corner gets its own outward normal.
		_add_tri([top0, top1, bottom1], [d0, d1, d1], centre, basis, color, {})
		_add_tri([top0, bottom1, bottom0], [d0, d1, d0], centre, basis, color, {})
		if caps:
			_add_tri([Vector3(0, half, 0), top1, top0], [Vector3.UP, Vector3.UP, Vector3.UP], centre, basis, color, {})
			_add_tri([Vector3(0, -half, 0), bottom0, bottom1], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], centre, basis, color, {})


## A sphere, optionally squashed (y_scale < 1 makes a flattened blob, like a tree crown).
func add_sphere(centre: Vector3, radius: float, color: Color, y_scale := 1.0,
		segments := 12, rings := 8) -> void:
	for ring in rings:
		var p0 := PI * ring / rings
		var p1 := PI * (ring + 1) / rings
		for i in segments:
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var n00 := _sphere_point(p0, a0)
			var n01 := _sphere_point(p0, a1)
			var n10 := _sphere_point(p1, a0)
			var n11 := _sphere_point(p1, a1)
			var scale := Vector3(1, y_scale, 1) * radius
			if ring > 0:
				_add_tri([n00 * scale, n01 * scale, n11 * scale], [n00, n01, n11], centre, Basis.IDENTITY, color, {})
			if ring < rings - 1:
				_add_tri([n00 * scale, n11 * scale, n10 * scale], [n00, n11, n10], centre, Basis.IDENTITY, color, {})


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _sphere_point(polar: float, azimuth: float) -> Vector3:
	return Vector3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))


## One flat quad. Godot draws triangles that run CLOCKWISE when seen from the front,
## so if the corners came out counter-clockwise we flip them.
func _add_quad(corners: Array[Vector3], normal: Vector3, centre: Vector3, basis: Basis,
		color: Color, custom: Dictionary) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for index in order:
		_add_vertex(corners[index], normal, centre, basis, color, custom)


func _add_tri(points: Array, normals: Array, centre: Vector3, basis: Basis, color: Color,
		custom: Dictionary) -> void:
	var flat_normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	var average: Vector3 = normals[0] + normals[1] + normals[2]
	var order := [0, 1, 2]
	if flat_normal.dot(average) > 0.0:  # Counter-clockwise from the front: flip.
		order = [0, 2, 1]
	for index in order:
		_add_vertex(points[index], normals[index], centre, basis, color, custom)


func _add_vertex(point: Vector3, normal: Vector3, centre: Vector3, basis: Basis,
		color: Color, custom: Dictionary) -> void:
	_surface.set_color(color)
	if _use_custom:
		var size: Vector3 = custom.get("size", Vector3.ONE)
		var trim: Color = custom.get("trim", Color.WHITE)
		var where: Vector3 = custom.get("centre", centre)
		_surface.set_custom(0, Color(size.x, size.y, size.z, custom.get("storefront", 0.0)))
		_surface.set_custom(1, Color(trim.r, trim.g, trim.b, custom.get("seed", 0.0)))
		_surface.set_custom(2, Color(where.x, where.y, where.z))
	_surface.set_normal((basis * normal).normalized())
	_surface.add_vertex(centre + basis * point)
	vertex_count += 1
