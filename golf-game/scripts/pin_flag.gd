class_name PinFlag
extends Node3D
## The flag stick at the cup: a white pole with a flag that ripples in the wind.
## Tall and bright on purpose, so the green is easy to spot from the tee.

const POLE_HEIGHT := 6.0   # Taller than a real pin, so it stands out from the far end of the street.
const FLAG_SIZE := Vector2(2.0, 1.25)


func _ready() -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.045
	pole_mesh.bottom_radius = 0.045
	pole_mesh.height = POLE_HEIGHT
	pole_mesh.radial_segments = 8
	pole_mesh.rings = 1
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.95, 0.95, 0.92)
	pole_material.roughness = 0.5
	var pole := MeshInstance3D.new()
	pole.mesh = pole_mesh
	pole.material_override = pole_material
	pole.position = Vector3(0, POLE_HEIGHT / 2.0, 0)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pole)

	# The flag is a flat, finely divided plane; the shader ripples it (see flag.gdshader).
	var flag_mesh := PlaneMesh.new()
	flag_mesh.size = FLAG_SIZE
	flag_mesh.orientation = PlaneMesh.FACE_Z
	flag_mesh.subdivide_width = 14
	var flag_material := ShaderMaterial.new()
	flag_material.shader = load("res://shaders/town/flag.gdshader")
	flag_material.set_shader_parameter("width", FLAG_SIZE.x)
	var flag := MeshInstance3D.new()
	flag.mesh = flag_mesh
	flag.material_override = flag_material
	flag.position = Vector3(FLAG_SIZE.x / 2.0, POLE_HEIGHT - FLAG_SIZE.y / 2.0 - 0.05, 0)
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flag)
