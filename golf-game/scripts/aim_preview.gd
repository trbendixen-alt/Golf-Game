class_name AimPreview
extends MultiMeshInstance3D
## The dotted arc showing where a 100% power shot with the selected club would go,
## straight along the aim line (it ignores wind and the accuracy tap; that's up to you).
##
## Like the wind trails it's cheap: a fixed pool of DOT_COUNT dots drawn with one
## MultiMesh, so it's a single draw call. Dots are spread evenly along the path.

const DOT_COUNT := 40
const DOT_RADIUS := 0.12


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = DOT_RADIUS
	mesh.height = DOT_RADIUS * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 1, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = DOT_COUNT
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Lay the dots out along `path` (a list of positions, e.g. from ClubSystem.simulate_path).
func show_path(path: PackedVector3Array) -> void:
	# Total length of the path, so we can space the dots evenly along it.
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	var spacing := total / DOT_COUNT

	# Walk along the path, dropping a dot every `spacing` metres. The first dot sits
	# one spacing out, so it doesn't cover the ball.
	var dot := 0
	var travelled := 0.0
	var next_dot_at := spacing
	for i in range(1, path.size()):
		var segment := path[i].distance_to(path[i - 1])
		while dot < DOT_COUNT and travelled + segment >= next_dot_at and segment > 0.0:
			var t := (next_dot_at - travelled) / segment
			multimesh.set_instance_transform(dot,
					Transform3D(Basis.IDENTITY, path[i - 1].lerp(path[i], t)))
			dot += 1
			next_dot_at += spacing
		travelled += segment
	# Any dots left over (rounding) sit at the very end.
	while dot < DOT_COUNT:
		multimesh.set_instance_transform(dot, Transform3D(Basis.IDENTITY, path[path.size() - 1]))
		dot += 1
