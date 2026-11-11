extends SceneTree
## Rendert die CNC-Fräsmaschine aus mehreren Blickwinkeln und den Bildschirminhalt als PNG (Design-Kontrolle).
## Aufruf: Godot --path . -s res://tools/render_cncmill.gd -- <ausgabeordner>

const SHOTS := {
	"front_closed": [Vector3(0.6, 1.7, 5.6), Vector3(0.3, 1.3, 0.3), 45.0],
	"front_open": [Vector3(0.6, 1.7, 5.6), Vector3(0.3, 1.3, 0.3), 45.0],
	"right": [Vector3(5.2, 2.0, 3.6), Vector3(0.6, 1.2, 0.4), 45.0],
	"left": [Vector3(-4.8, 2.2, 3.6), Vector3(-0.2, 1.2, 0.2), 45.0],
	"work": [Vector3(0.9, 2.0, 1.7), Vector3(0.0, 1.55, 0.0), 55.0],
	"magazine": [Vector3(-2.6, 2.4, 1.6), Vector3(-0.7, 2.0, 0.0), 45.0],
	"pult": [Vector3(0.9, 1.7, 2.9), Vector3(1.55, 1.45, 1.55), 40.0],
}


func shot(cam: Camera3D, out: String, name: String, spec: Array) -> void:
	cam.position = spec[0]
	cam.fov = float(spec[2])
	cam.look_at(spec[1])
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _initialize() -> void:
	var out := "user://shots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	var scene := Node3D.new()
	root.add_child(scene)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.58, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.77, 0.8)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(24, 24)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.37, 0.38)
	floor_mi.material_override = fm
	scene.add_child(floor_mi)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(14, 6, 12)
	probe.position = Vector3(0.0, 2.5, 1.0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	scene.add_child(probe)
	var mill = load("res://scripts/machine/cnc_mill.gd").new()
	scene.add_child(mill)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	for i in 10:
		await process_frame
	mill.power_on(true)
	mill.magazine_set(1, "F10")
	mill.magazine_set(2, "MK63")
	mill.magazine_set(3, "B10")
	mill.magazine_set(5, "F6")
	mill.magazine_set(12, "B25")
	mill.select_tool(mill.tool_index("F10"), true)
	mill.tool_z = 60.0
	mill.tool_x = mill.block_l * 0.5
	mill.tool_y = mill.block_w * 0.5
	mill._sync_axes()
	for i in 4:
		await process_frame
	await shot(cam, out, "front_closed", SHOTS["front_closed"])
	mill.set_door(false, true)
	await shot(cam, out, "front_open", SHOTS["front_open"])
	for k in ["right", "left", "work"]:
		await shot(cam, out, k, SHOTS[k])
	for m in mill._mp["shell"]:
		m.visible = false
	await shot(cam, out, "magazine", SHOTS["magazine"])
	await shot(cam, out, "magazine_front", [Vector3(-0.5, 2.3, 3.0), Vector3(-0.5, 2.0, 0.0), 40.0])
	for m in mill._mp["shell"]:
		m.visible = true
	await shot(cam, out, "pult", SHOTS["pult"])
	for m in mill._mp["shell"]:
		m.visible = false
	# Endlagen der Achsen
	var lim: Dictionary = mill.limits()
	var corners := {"x_min": Vector3(lim["min"].x, 30, 60), "x_max": Vector3(lim["max"].x, 30, 60),
		"y_min": Vector3(50, lim["min"].y, 60), "y_max": Vector3(50, lim["max"].y, 60), "z_max": Vector3(50, 30, mill.z_max)}
	for k in corners:
		var c: Vector3 = corners[k]
		mill.tool_x = c.x + mill.datum.x
		mill.tool_y = c.y + mill.datum.y
		mill.tool_z = c.z + mill.datum.z
		mill._sync_axes()
		await shot(cam, out, "lim_" + k, SHOTS["work"])
	mill.tool_x = mill.block_l * 0.5
	mill.tool_y = mill.block_w * 0.5
	mill.tool_z = 60.0
	mill._sync_axes()
	# Werkzeugwechsel: Zwischenbilder
	mill.set_door(true, true)
	var err: String = mill.tool_change(2)
	print("tool_change: ", err)
	var n := 0
	var marks := {20: "tc_a", 70: "tc_c", 130: "tc_e", 200: "tc_g", 250: "tc_h"}
	while mill.changing and n < 1200:
		await physics_frame
		n += 1
		if marks.has(n):
			await shot(cam, out, str(marks[n]), SHOTS["magazine"])
	print("Wechsel dauerte ", n, " Bilder, T", mill.tool_t)
	await shot(cam, out, "after_change", SHOTS["work"])
	# Bildschirm
	mill.screen_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 6:
		await process_frame
	mill.screen_vp.get_texture().get_image().save_png(out.path_join("screen.png"))
	await screens(mill, out, cam)
	quit()


# ----------------------------------------------------------------------- Steuerung (TncScreen): jede Betriebsart als PNG

class FakeP extends Node:
	var held := {}
	var operating = null

	func set_held(m, id: String) -> void:
		held = {"machine": m.MACHINE_ID, "id": id, "name": m.tool_name(id)}

	func clear_held() -> void:
		held = {}

	func start_operating(m, _pos, _yaw) -> void:
		operating = m

	func stop_operating() -> void:
		operating = null


func scr(mill, out: String, nm: String) -> void:
	for i in 4:
		await process_frame
	mill.screen._tick()
	# Ohne Bedienung zeichnet der Bildschirm nur alle 0,25 s neu: hier ein frisches Bild erzwingen
	mill.screen_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 4:
		await process_frame
	mill.screen_vp.get_texture().get_image().save_png(out.path_join("screen_%s.png" % nm))


func prog_index(mill, nm: String) -> int:
	for i in mill.programs.size():
		if mill.programs[i]["name"] == nm:
			return i
	return -1


func screens(mill, out: String, cam: Camera3D) -> void:
	var s = mill.screen
	for m in mill._mp["shell"]:
		m.visible = true
	mill.set_door(true, true)
	mill.magazine.fill("")
	mill.clear_spindle()
	mill.magazine_set(1, "MK63")
	mill.magazine_set(2, "F12")
	mill.magazine_set(3, "B10")
	mill.magazine_set(5, "F6")
	mill.tool_change(2)
	var n := 0
	while mill.changing and n < 3000:
		await physics_frame
		n += 1
	mill.prog_sel = prog_index(mill, "TASCHE")
	mill.tool_x = 42.5
	mill.tool_y = 18.25
	mill.tool_z = 35.0
	mill._sync_axes()
	s.show_mode("manual")
	await scr(mill, out, "manual")
	s._sub = "m"
	s._sk_refresh()
	await scr(mill, out, "manual_m")
	s._sub = ""
	s._ask_datum(0)
	await scr(mill, out, "manual_input")
	s._bar_cancel()
	s.show_mode("mdi")
	s._mdi_text = "L X+50 Y+30 Z+2 R0 F300 M3"
	s._mdi_hist.assign(["L Z+100 R0 FMAX", "TOOL CALL 2 Z S3500", "L X+20 Y+20 FMAX"])
	s._hist_sig = ""
	s._bar_default()
	await scr(mill, out, "mdi")
	s.show_mode("pgm")
	await scr(mill, out, "pgm")
	# Editor
	s.show_mode("edit")
	s._cursor = 8
	s._ed_rebuild()
	s._bar_text_open()
	await scr(mill, out, "edit")
	s._cursor = 7
	s._dlg_new("cycl_def", {"cycle": 251})
	s._bar_submit("60")
	await scr(mill, out, "edit_dialog")
	s._dlg_abort()
	s._cursor = 6
	s._dlg_new("l")
	s._bar_submit("50")
	s._bar_submit("30")
	s._dlg_skip()
	await scr(mill, out, "edit_dialog_choice")
	s._dlg_abort()
	s._sub = "cycl"
	s._sk_refresh()
	await scr(mill, out, "edit_cycles")
	s._sub = ""
	# Programm-Test: gutes und fehlerhaftes Programm
	mill.save_program("KAPUTT", ["BEGIN PGM KAPUTT MM", "BLK FORM 0.1 Z X+0 Y+0 Z-40", "BLK FORM 0.2 X+100 Y+60 Z+0", "TOOL CALL 1 Z S800",
		"L X+10 Y+10 F200", "L X+20 Y+x", "FOO BAR", "M30", "END PGM KAPUTT MM"])
	mill.prog_sel = prog_index(mill, "BOHRBILD")
	s.show_mode("test")
	await scr(mill, out, "test_bohrbild")
	mill.prog_sel = prog_index(mill, "TASCHE")
	s.show_mode("test")
	await scr(mill, out, "test")
	mill.prog_sel = prog_index(mill, "PLANEN")
	s.show_mode("test")
	await scr(mill, out, "test_planen")
	mill.prog_sel = prog_index(mill, "KAPUTT")
	s.show_mode("test")
	await scr(mill, out, "test_fehler")
	s.show_mode("edit")
	await scr(mill, out, "edit_fehler")
	mill.delete_program("KAPUTT")
	s.show_mode("tools")
	await scr(mill, out, "tools")
	# Programmlauf
	mill.prog_sel = prog_index(mill, "TASCHE")
	mill.set_material("AW-6082")
	mill.new_workpiece(100.0, 60.0, 40.0)
	mill.tool_z = 100.0
	mill._sync_axes()
	s.show_mode("auto")
	s._nc_start()
	n = 0
	while n < 900 and mill.channel.state == "run":
		await physics_frame
		n += 1
	await scr(mill, out, "run")
	mill.nc_stop()
	await scr(mill, out, "run_halt")
	mill.nc_reset()
	# Störungen
	mill.toggle_estop()
	s.show_mode("manual")
	await scr(mill, out, "estop")
	mill.toggle_estop()
	mill.set_door(false, true)
	s._ce()
	s._msg_list_panel.visible = false
	await scr(mill, out, "door_open")
	mill.set_door(true, true)
	mill.message.emit("Kabinentür offen - NC-Start nur bei geschlossener Tür.", Color(1.0, 0.75, 0.2))
	mill.message.emit("Alarm: Bewegung blockiert bei X12.000 Y3.000 Z-4.000 (Verfahrgrenze oder Meldung beachten).", Color(1, 0.3, 0.25))
	s._on_msg_input(_click_event())
	await scr(mill, out, "messages")
	s._ce()
	s._msg_list_panel.visible = false
	# Pultansicht im Spielbild
	var fp := FakeP.new()
	root.add_child(fp)
	for m in mill._mp["shell"]:
		m.visible = true
	s.show_mode("manual")
	mill.interact(fp, true)
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("pult_view.png"))
	s.show_mode("edit")
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("pult_view_edit.png"))
	mill.stop_operating()


func _click_event() -> InputEvent:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e
