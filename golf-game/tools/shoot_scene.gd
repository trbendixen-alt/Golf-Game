extends SceneTree
## Developer tool: opens any scene in a real window and saves screenshots of it.
##   godot --path . --resolution 540x960 --script res://tools/shoot_scene.gd -- res://scenes/main_menu.tscn /tmp/shots/menu [frames ...]
## Saves <prefix>_<n>.png after each frame count n (default 100). Give "t250" instead of a number
## to wait until 250 milliseconds after the scene started. Needs a window.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0]
	var prefix: String = args[1]
	var stops: Array = args.slice(2)
	if stops.is_empty():
		stops = ["100"]
	await process_frame
	change_scene_to_file(scene_path)
	var start := Time.get_ticks_msec()
	var frame := 0
	for stop in stops:
		if String(stop).begins_with("t"):
			while Time.get_ticks_msec() - start < int(String(stop).substr(1)):
				await process_frame
		else:
			while frame < int(stop):
				await process_frame
				frame += 1
		root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, stop])
	print("saved")
	quit()
