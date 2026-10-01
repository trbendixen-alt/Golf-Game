extends SceneTree
## Developer tool: pre-renders the main menu background from the Main Street Opener
## scene (street, buildings, cars, trees, sun), WITHOUT the fairway, tee, green or ball.
## A picture keeps the menu fast: it costs one texture instead of a whole 3D scene.
##
##   godot --path . --resolution 540x960 --script res://tools/render_menu_background.gd
##
## Writes ui/menu/menu_bg.jpg (1125x2000, the mockup's size). Needs a window (not --headless).

const OUTPUT := "res://ui/menu/menu_bg.jpg"
const SIZE := Vector2i(1125, 2000)
const CAMERA_POSITION := Vector3(-1.5, 1.9, 6.5)
const CAMERA_TARGET := Vector3(0.0, 4.6, -60.0)
const HOLE := "main_street_opener"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var hole: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/holes/%s.json" % HOLE))
	var view := SubViewport.new()
	view.size = SIZE
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var world := Node3D.new()
	view.add_child(world)

	LookSetup.apply(world, "menu")
	var scenery_data: Dictionary = hole["scenery"]
	var scenery: HoleScenery = load(scenery_data["scene"]).instantiate()
	world.add_child(scenery)

	# The street and kerbs only: drop the golf zones (fairway, tee, green) from the ground.
	var zones := []
	for zone in hole["surfaces"]:
		if not ["fairway", "tee", "green"].has(zone["type"]):
			zones.append(zone)
	var ground := HoleGround.new()
	ground.theme = {
		"street_half": scenery_data["street_half"], "street_end_z": scenery_data["street_end"],
		"crosswalk_z": Vector2(-19.0, -60.0), "stakes": false,
	}
	ground.surfaces = SurfaceMap.new(zones, hole["bounds"], hole["ground"], [])
	ground.centre = Vector3(0, 0, -50)
	world.add_child(ground)

	var camera := Camera3D.new()
	camera.fov = 62.0
	camera.far = 2500.0
	world.add_child(camera)
	camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)
	camera.current = true
	for i in 12:
		await process_frame
	var image := view.get_texture().get_image()
	image.save_jpg(ProjectSettings.globalize_path(OUTPUT), 0.92)
	print("saved ", OUTPUT, " ", image.get_size())
	quit()
