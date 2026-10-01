extends SceneTree
## Developer tool: plays a hole in a real window and saves screenshots.
##   godot --path . --resolution 540x960 --script res://tools/shoot_hole.gd -- main_street_opener /tmp/shots
## (Needs a window, so don't use --headless.)
##
## Saves <hole>_tee.png (the window as it looks, with the HUD) and <hole>_3d.png: the
## 3D view alone rendered at the real phone size of 1080x1920, plus crops of the middle.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var hole_id: String = args[0] if args.size() > 0 else "main_street_opener"
	var folder: String = args[1] if args.size() > 1 else "/tmp/shots"
	DirAccess.make_dir_recursive_absolute(folder)
	await process_frame
	var rounds: Node = root.get_node("RoundManager")
	rounds.start_preview(hole_id)
	for i in 90:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s_tee.png" % [folder, hole_id])

	# 3D view at full phone resolution, sharing the hole's world.
	var hole: Node = current_scene
	var view := SubViewport.new()
	view.size = Vector2i(1080, 1920)
	view.world_3d = root.world_3d
	view.msaa_3d = Viewport.MSAA_2X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera := Camera3D.new()
	camera.fov = hole.camera.fov
	camera.far = hole.camera.far
	camera.global_transform = hole.camera.global_transform
	view.add_child(camera)
	camera.current = true
	for i in 6:
		await process_frame
	var image := view.get_texture().get_image()
	image.save_png("%s/%s_3d.png" % [folder, hole_id])
	# Crops (2x zoom) of the far end of the street and of the foreground.
	var far := image.get_region(Rect2i(290, 640, 500, 340)); far.resize(1000, 680, Image.INTERPOLATE_LANCZOS)
	far.save_png("%s/%s_far.png" % [folder, hole_id])
	var near := image.get_region(Rect2i(0, 820, 540, 400)); near.resize(1080, 800, Image.INTERPOLATE_LANCZOS)
	near.save_png("%s/%s_near.png" % [folder, hole_id])
	print("saved")
	quit()
