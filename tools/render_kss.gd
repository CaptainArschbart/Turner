extends SceneTree
## Rendert das KSS-Panel (Chemiemeister) als PNG zur Design-Kontrolle.
## Aufruf: Godot --path . -s res://tools/render_kss.gd -- <ausgabeordner>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	await process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.3, 0.35)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var t := KssTank.new()
	var p := KssPanel.new()
	root.add_child(p)
	p.setup(t, "CNC-Drehmaschine E50")
	p.set_valve(KssPanel.WATER, true)
	p.set_valve(KssPanel.CONC, true)
	await _wait(1.2)
	root.get_texture().get_image().save_png(out.path_join("kss_fliessen.png"))
	p.set_valve(KssPanel.WATER, false)
	p.set_valve(KssPanel.CONC, false)
	t.water = 52.0
	t.concentrate = 3.9
	t.changed.emit()
	p.set_valve(KssPanel.WATER, true)
	await _wait(2.5)
	root.get_texture().get_image().save_png(out.path_join("kss_voll.png"))
	quit()


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame
