extends Node
## Visual look test for "Main Street Opener": lighting, sky, glinting windows, haze and
## hit effects. No gameplay — it's separate from the real hole scene on purpose.
##
## Interactive: tap the top half to change camera view, the bottom half to change time of day.
## Stills:      godot --path golf-game res://look_test/look_test.tscn -- --shots=<folder>
##              renders every view/time combo to PNGs at 1080x1920, then quits.

const RENDER_SIZE := Vector2i(1080, 1920)

const TIMES := [
	{
		"name": "golden_hour", "elev": 4.0, "azim": -1.5,
		"sun": Color(1.0, 0.64, 0.36), "energy": 2.6, "ambient": 0.55, "exposure": 1.0,
		"zenith": Color(0.20, 0.30, 0.58), "mid": Color(0.66, 0.58, 0.70), "horizon": Color(1.0, 0.55, 0.28),
		"cloud": Color(1.0, 0.70, 0.52), "cloud_shadow": Color(0.48, 0.36, 0.46), "coverage": 0.42,
		"fog": Color(1.0, 0.66, 0.42), "fog_density": 0.0011, "lit": 0.10, "lamps": 0.0,
	},
	{
		"name": "sunrise", "elev": 9.0, "azim": 70.0,
		"sun": Color(1.0, 0.78, 0.64), "energy": 2.1, "ambient": 0.6, "exposure": 1.05,
		"zenith": Color(0.34, 0.48, 0.78), "mid": Color(0.74, 0.72, 0.84), "horizon": Color(1.0, 0.72, 0.62),
		"cloud": Color(1.0, 0.80, 0.76), "cloud_shadow": Color(0.58, 0.54, 0.66), "coverage": 0.35,
		"fog": Color(0.92, 0.80, 0.80), "fog_density": 0.0016, "lit": 0.06, "lamps": 0.5,
	},
	{
		"name": "midday", "elev": 58.0, "azim": 35.0,
		"sun": Color(1.0, 0.97, 0.92), "energy": 2.7, "ambient": 0.75, "exposure": 0.95,
		"zenith": Color(0.18, 0.40, 0.85), "mid": Color(0.42, 0.63, 0.94), "horizon": Color(0.80, 0.88, 0.97),
		"cloud": Color(1.0, 1.0, 1.0), "cloud_shadow": Color(0.72, 0.76, 0.84), "coverage": 0.38,
		"fog": Color(0.75, 0.84, 0.95), "fog_density": 0.0006, "lit": 0.0, "lamps": 0.0,
	},
	{
		"name": "dusk", "elev": 1.2, "azim": -2.0,
		"sun": Color(1.0, 0.42, 0.28), "energy": 0.9, "ambient": 0.45, "exposure": 1.2,
		"zenith": Color(0.08, 0.09, 0.24), "mid": Color(0.38, 0.26, 0.46), "horizon": Color(0.98, 0.42, 0.30),
		"cloud": Color(0.95, 0.45, 0.40), "cloud_shadow": Color(0.22, 0.18, 0.32), "coverage": 0.45,
		"fog": Color(0.55, 0.36, 0.48), "fog_density": 0.0013, "lit": 0.55, "lamps": 7.0,
	},
]

## [camera position, look-at target]
const VIEWS := {
	"tee": [Vector3(-1.5, 1.9, 6.5), Vector3(0.0, 3.5, -60.0)],
	"street_low": [Vector3(2.2, 0.45, -24.0), Vector3(-6.5, 5.5, -90.0)],
	"green": [Vector3(9.0, 2.0, -121.0), Vector3(0.0, 1.5, -160.0)],
	"aerial": [Vector3(-14.0, 42.0, 48.0), Vector3(0.0, 0.0, -110.0)],
	"sparks": [Vector3(0.9, 0.55, 1.9), Vector3(-1.6, 0.4, -0.8)],
}

var town: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var viewport: SubViewport
var ball: MeshInstance3D
var label: Label

var time_index := 0
var view_index := 0


func _ready() -> void:
	_register_shader_globals()
	_build_viewport()
	_build_lighting()
	town = load("res://look_test/town_builder.gd").new()
	viewport.add_child(town)
	town.build()
	_build_ball()
	_build_label()
	_apply_time(0)
	_apply_view(0)

	var shots_dir := _arg("shots")
	if shots_dir != "":
		_render_all(shots_dir)


func _arg(key: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return ""


# ---------------------------------------------------------------- setup

func _register_shader_globals() -> void:
	var rs := RenderingServer
	# The project now declares these globals itself (project.godot > Shader Globals).
	if rs.global_shader_parameter_get_list().has(&"sun_dir"):
		return
	rs.global_shader_parameter_add("sun_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0, 0.1, -1))
	rs.global_shader_parameter_add("sun_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(1, 0.7, 0.4, 2.0))
	rs.global_shader_parameter_add("wind_vec", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(3.0, 0.0, 1.0))


func _build_viewport() -> void:
	# Render at a fixed phone resolution regardless of the desktop window size.
	# The project's 1080x1920 canvas_items stretch scales the container to the window.
	var container := SubViewportContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.size = Vector2(RENDER_SIZE)
	add_child(container)
	viewport = SubViewport.new()
	viewport.size = RENDER_SIZE
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)


func _build_lighting() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://look_test/shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sun_scatter = 0.2
	env.fog_aerial_perspective = 0.25
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05

	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	sun.light_angular_distance = 0.6
	viewport.add_child(sun)

	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 7000.0
	viewport.add_child(camera)


func _build_ball() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.97, 0.95)
	mat.roughness = 0.35
	ball = MeshInstance3D.new()
	ball.mesh = sm
	ball.material_override = mat
	ball.position = town.TEE_POS + Vector3(0, 0.1, 0)
	viewport.add_child(ball)


func _build_label() -> void:
	label = Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)


# ---------------------------------------------------------------- time of day + views

func _apply_time(i: int) -> void:
	time_index = i
	var t: Dictionary = TIMES[i]
	var el := deg_to_rad(t.elev)
	var az := deg_to_rad(t.azim)
	var s := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()
	sun.look_at_from_position(Vector3.ZERO, -s, Vector3.UP)
	sun.light_color = t.sun
	sun.light_energy = t.energy
	for key in ["zenith", "mid", "horizon"]:
		sky_mat.set_shader_parameter(key + "_color", t[key])
	sky_mat.set_shader_parameter("cloud_color", t.cloud)
	sky_mat.set_shader_parameter("cloud_shadow", t.cloud_shadow)
	sky_mat.set_shader_parameter("cloud_coverage", t.coverage)
	env.ambient_light_energy = t.ambient
	env.tonemap_exposure = t.exposure
	env.fog_light_color = t.fog
	env.fog_density = t.fog_density
	town.building_mat.set_shader_parameter("lit_ratio", t.lit)
	town.lamp_mat.emission_energy_multiplier = t.lamps
	var c: Color = t.sun
	RenderingServer.global_shader_parameter_set("sun_dir", s)
	RenderingServer.global_shader_parameter_set("sun_color", Color(c.r, c.g, c.b, t.energy))
	# re-capture window reflections for the new sky
	town.reflection_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	await get_tree().process_frame
	await get_tree().process_frame
	town.reflection_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_update_label()


func _apply_view(i: int) -> void:
	view_index = i
	var key: String = VIEWS.keys()[i]
	var v: Array = VIEWS[key]
	camera.look_at_from_position(v[0], v[1], Vector3.UP)
	camera.fov = 50.0 if key == "sparks" else 62.0
	if key == "sparks":
		_spark_burst(ball.position, Vector3(0, 0, -1))
	_update_label()


func _update_label() -> void:
	if label:
		label.text = "%s · %s\ntap top: view · tap bottom: time" % [VIEWS.keys()[view_index], TIMES[time_index].name]


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	if event.position.y < get_viewport().get_visible_rect().size.y * 0.5:
		_apply_view((view_index + 1) % VIEWS.size())
	else:
		_apply_time((time_index + 1) % TIMES.size())


# ---------------------------------------------------------------- hit effects

## Perfect-strike sparks: hot white-orange needles that bloom, plus a glow flash on the ball.
func _spark_burst(pos: Vector3, forward: Vector3) -> void:
	var add_shader: Shader = load("res://look_test/shaders/fx_add.gdshader")

	var needle := CylinderMesh.new()
	needle.top_radius = 0.004
	needle.bottom_radius = 0.012
	needle.height = 0.22
	needle.radial_segments = 4
	needle.rings = 1
	var spark_mat := ShaderMaterial.new()
	spark_mat.shader = add_shader
	spark_mat.set_shader_parameter("energy", 2.6)
	needle.material = spark_mat

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	ramp.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	ramp.add_point(0.3, Color(1.0, 0.45, 0.08, 1.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp

	var pm := ParticleProcessMaterial.new()
	pm.direction = (forward * 0.7 + Vector3.UP).normalized()
	pm.spread = 55.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = ramp_tex

	var sparks := GPUParticles3D.new()
	sparks.process_material = pm
	sparks.draw_pass_1 = needle
	sparks.amount = 70
	sparks.lifetime = 0.6
	sparks.explosiveness = 1.0
	sparks.one_shot = true
	sparks.local_coords = false
	sparks.position = pos
	viewport.add_child(sparks)
	sparks.emitting = true
	sparks.finished.connect(sparks.queue_free)

	# glow flash at the contact point
	var flash_mesh := QuadMesh.new()
	flash_mesh.size = Vector2(1.2, 1.2)
	var flash_mat := ShaderMaterial.new()
	flash_mat.shader = add_shader
	flash_mat.set_shader_parameter("billboard", true)
	flash_mat.set_shader_parameter("soft", true)
	flash_mat.set_shader_parameter("energy", 1.5)
	var flash := MeshInstance3D.new()
	flash.mesh = flash_mesh
	flash.material_override = flash_mat
	flash.position = pos
	viewport.add_child(flash)
	var tw := create_tween()
	tw.tween_method(func(e: float): flash_mat.set_shader_parameter("energy", e), 1.5, 0.0, 0.35)
	tw.tween_callback(flash.queue_free)


# ---------------------------------------------------------------- stills

func _render_all(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var combos: Array = []
	for v in VIEWS.size():
		combos.append([v, 0])        # every view at golden hour
	for t in range(1, TIMES.size()):
		combos.append([0, t])        # the tee view at every other time of day
		combos.append([2, t])        # and the green / horizon view
	for combo in combos:
		await _apply_time(combo[1])
		_apply_view(combo[0])
		# let shadows, probes and (for sparks) particles settle
		var wait := 0.12 if VIEWS.keys()[combo[0]] == "sparks" else 0.6
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		var img := viewport.get_texture().get_image()
		var path := "%s/%s_%s.png" % [dir, VIEWS.keys()[combo[0]], TIMES[combo[1]].name]
		img.save_png(path)
		print("saved ", path)
	get_tree().quit()
