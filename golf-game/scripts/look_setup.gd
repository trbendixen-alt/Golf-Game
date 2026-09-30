class_name LookSetup
extends RefCounted
## Gives a hole its lighting "look" (golden hour, midday...): the sky, the sun, distance
## haze and bloom. Looks are data: see data/looks.json, and a hole picks one with
## "look": "golden_hour" in its hole file.
##
## The numbers and the sky shader come from Julian's look test (look_test/).
##
## Note the sun has its shadows switched OFF. A themed hole's static scenery has its
## shadows baked into a texture instead (see tools/build_hole_scenery.gd), which is
## much cheaper on a phone than a real-time shadow pass.

const LOOKS_FILE := "res://data/looks.json"
const SKY_SHADER := "res://shaders/town/sky.gdshader"


## Adds a sky, world environment and sun to `host`. Returns { sun, environment }.
static func apply(host: Node3D, look_name: String) -> Dictionary:
	var looks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LOOKS_FILE))
	var look: Dictionary = looks[look_name]

	var sky_material := ShaderMaterial.new()
	sky_material.shader = load(SKY_SHADER)
	sky_material.set_shader_parameter("zenith_color", Color(look["zenith"]))
	sky_material.set_shader_parameter("mid_color", Color(look["mid"]))
	sky_material.set_shader_parameter("horizon_color", Color(look["horizon"]))
	sky_material.set_shader_parameter("cloud_color", Color(look["cloud"]))
	sky_material.set_shader_parameter("cloud_shadow", Color(look["cloud_shadow"]))
	sky_material.set_shader_parameter("cloud_coverage", look["coverage"])
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = look["ambient"]
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = look["exposure"]
	# Bloom: bright things (the sun, window glints) softly glow.
	environment.glow_enabled = true
	environment.glow_intensity = look["glow_intensity"]
	environment.glow_bloom = look["glow_bloom"]
	environment.glow_hdr_threshold = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Light haze: the far end of the street fades toward the warm horizon colour.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(look["fog"])
	environment.fog_density = look["fog_density"]
	environment.fog_sun_scatter = 0.2
	environment.fog_aerial_perspective = 0.25
	environment.fog_sky_affect = 0.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = look["saturation"]
	environment.adjustment_contrast = look["contrast"]
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	host.add_child(world_environment)

	# The sun: a low, strong, warm directional light.
	var elevation := deg_to_rad(float(look["elev"]))
	var azimuth := deg_to_rad(float(look["azim"]))
	var to_sun := Vector3(sin(azimuth) * cos(elevation), sin(elevation),
			-cos(azimuth) * cos(elevation)).normalized()
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(look["sun"])
	sun.light_energy = look["energy"]
	sun.shadow_enabled = false  # Baked instead; see the note at the top.
	host.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP)

	# The shaders (window glints, leaf glow) need to know where the sun is.
	var sun_color := Color(look["sun"])
	RenderingServer.global_shader_parameter_set("sun_dir", to_sun)
	RenderingServer.global_shader_parameter_set("sun_color",
			Color(sun_color.r, sun_color.g, sun_color.b, look["energy"]))
	return {"sun": sun, "environment": environment}
