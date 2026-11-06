extends SceneTree
## Rendert Hauptmenü (und optional Pausemenü) als PNG zur Design-Kontrolle.
## Aufruf: Godot --path . -s res://tools/render_menu.gd -- <ausgabeordner> [main|pause|backdrop]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shots"
	var what: String = args[1] if args.size() > 1 else "main"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	await process_frame
	if what == "pause":
		var w = load("res://scenes/world.tscn").instantiate()
		root.add_child(w)
		for i in 20:
			await process_frame
		w.pause_menu.open()
		await _wait(0.6)
		root.get_texture().get_image().save_png(out.path_join("pause.png"))
		w.pause_menu._show_settings()
		await _wait(0.5)
		root.get_texture().get_image().save_png(out.path_join("pause_settings.png"))
		quit()
		return
	var m = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(m)
	if what == "backdrop":
		for c in m.get_children():
			if not c is SubViewportContainer:
				c.visible = false
	var times := [1.0, 3.5, 6.0, 9.0]
	var last := 0.0
	for i in times.size():
		await _wait(times[i] - last)
		last = times[i]
		var img := root.get_texture().get_image()
		var bd = m._backdrop
		print("t=", times[i], " chip_len=", bd._chip_len, " falling=", bd._falling.size(), " screen tip=", bd.camera.unproject_position(bd._tip), " s=0.05 ", bd.camera.unproject_position(bd._chip_point(0.05)), " behind=", bd.camera.is_position_behind(bd._chip_point(0.05)))
		img.save_png(out.path_join("main_%d.png" % i))
		if what == "backdrop":
			var sz := img.get_size()
			var crop := img.get_region(Rect2i(int(sz.x * 0.45), int(sz.y * 0.2), int(sz.x * 0.4), int(sz.y * 0.55)))
			crop.resize(1000, int(1000.0 * crop.get_height() / crop.get_width()))
			crop.save_png(out.path_join("crop_%d.png" % i))
	if what == "main":
		m._show_slots("new")
		await _wait(0.5)
		root.get_texture().get_image().save_png(out.path_join("main_slots.png"))
		m._show_settings()
		await _wait(0.5)
		root.get_texture().get_image().save_png(out.path_join("main_settings.png"))
	print("frames ", Engine.get_frames_drawn(), " fps ", Engine.get_frames_per_second())
	quit()


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame
