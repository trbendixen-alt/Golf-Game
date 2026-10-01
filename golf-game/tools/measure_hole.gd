extends SceneTree
## Developer tool: measures how heavy a hole is to draw. Renders the hole's 3D view at the
## real phone size (1080x1920) and reports frame rate, draw calls, triangles and GPU time
## from three spots along the hole.
##   godot --path . --disable-vsync --resolution 540x960 --script res://tools/measure_hole.gd -- main_street_opener [scale]
## Use --disable-vsync, or every number is capped at the monitor's 60 fps. `scale` (default 1)
## multiplies the 1080x1920 size, e.g. 2 renders 2160x3840 to see how resolution-bound it is.
## (Needs a window. Numbers are for THIS computer's GPU: a phone will be slower.)

const FRAMES := 240
const WARMUP := 60

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var hole_id: String = args[0] if args.size() > 0 else "main_street_opener"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # Measure the true speed, not the monitor's 60 Hz.
	await process_frame
	root.get_node("RoundManager").start_preview(hole_id)
	for i in 60:
		await process_frame
	var hole: Node = current_scene

	var view := SubViewport.new()
	var scale := float(args[1]) if args.size() > 1 else 1.0
	view.size = Vector2i(int(1080 * scale), int(1920 * scale))
	view.world_3d = root.world_3d
	view.msaa_3d = root.msaa_3d if root.msaa_3d != Viewport.MSAA_DISABLED else Viewport.MSAA_2X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera := Camera3D.new()
	camera.fov = hole.camera.fov
	camera.far = hole.camera.far
	view.add_child(camera)
	camera.current = true
	root.disable_3d = true  # Don't also draw the small window: measure the phone-size view only.
	var view_rid := view.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(view_rid, true)

	for label in ["tee (z=0)", "mid-hole (z=-45)", "by the green (z=-88)"]:
		var z := 0.0 if label.begins_with("tee") else (-45.0 if label.begins_with("mid") else -88.0)
		hole.ball.place_at(Vector3(0, 0, z))
		hole._aim_at_cup()
		hole._snap_camera()
		camera.global_transform = hole.camera.global_transform
		for with_hud in [true, false]:
			hole.hud.visible = with_hud
			for i in WARMUP:
				camera.global_transform = hole.camera.global_transform
				await process_frame
			var t0 := Time.get_ticks_usec()
			var calls := 0.0
			var prims := 0.0
			var objects := 0.0
			var gpu := 0.0
			var cpu := 0.0
			for i in FRAMES:
				await process_frame
				calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
				objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(view_rid)
				cpu += RenderingServer.viewport_get_measured_render_time_cpu(view_rid)
			var seconds := (Time.get_ticks_usec() - t0) / 1e6
			print("%-22s HUD %-3s  %6.1f fps | %4.0f draw calls | %5.0fk triangles | %4.0f objects | GPU %.2f ms | CPU %.2f ms" % [
					label, "on" if with_hud else "off", FRAMES / seconds, calls / FRAMES, prims / FRAMES / 1000.0,
					objects / FRAMES, gpu / FRAMES, cpu / FRAMES])
	print("render size: %s" % view.size)
	print("video memory used: %.1f MB, texture memory: %.1f MB" % [
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
	print("renderer: ", RenderingServer.get_video_adapter_name(), " | ", ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	quit()
