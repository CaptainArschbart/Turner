extends SceneTree
## Headless-Prüfung der Zyklensteuerung: Konturen, Längs-/Planschruppen und Schlichten an der
## Maschine abarbeiten, Teil gegen den Auftrag prüfen, Schutztür-Verriegelung, Pult-Software.
## Aufruf: godot --headless --path . -s res://tools/tests/test_cycles.gd

var checks := 0
var fails := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


func run(l, max_s := 3000.0) -> float:
	var t := 0.0
	var dt := 0.05
	while l.nc.busy() and t < max_s:
		l._physics_process(dt)
		l._step_index_anim(dt)
		t += dt
	return t


func prog(l, n: String) -> Dictionary:
	for p in l.programs:
		if str(p["name"]) == n:
			return p
	return {}


func _initialize() -> void:
	await process_frame
	var l = load("res://scripts/machine/lathe.gd").new()
	root.add_child(l)
	await process_frame

	# --- Kontur mit Fase und Radius
	var c := {"type": "contour", "name": "K", "x0": 0.0, "z0": 100.0, "els": [
		{"x": 40.0, "z": 100.0, "tr": 1, "tv": 2.0},
		{"x": 40.0, "z": 60.0, "tr": 2, "tv": 3.0},
		{"x": 60.0, "z": 60.0, "tr": 0, "tv": 0.0}]}
	var pts: PackedVector2Array = NcCam.contour_points(c)
	ok(pts[1].is_equal_approx(Vector2(100, 18)) and pts[2].is_equal_approx(Vector2(98, 20)), "Fase 2 an der Ecke X40 Z100 (%s %s)" % [pts[1], pts[2]])
	var arc_ok := false
	for q in pts:
		if absf(q.x - (60.0 + 3.0 - 3.0 * cos(PI / 4.0))) < 0.3 and q.y > 20.5 and q.y < 21.5:
			arc_ok = true
	ok(arc_ok and pts[pts.size() - 1].is_equal_approx(Vector2(60, 30)), "Radius 3 in der Kehle eingerechnet")

	# --- Prüfung der Satzwerte
	var t1: Dictionary = LatheTools.get_tool(LatheTools.index_of("T1"))
	var t2: Dictionary = LatheTools.get_tool(LatheTools.index_of("T2"))
	var t3: Dictionary = LatheTools.get_tool(LatheTools.index_of("T3"))
	var b := NcCam.new_block("cut")
	ok(NcCam.check_block(b, t1) == "", "Abspanen mit T1 zulässig")
	b["d"] = 3.0
	ok(NcCam.check_block(b, t3) != "", "D 3 mm mit T3 abgelehnt")
	ok(NcCam.check_block(b, t2) != "", "Linksmeißel abgelehnt")

	# --- Schutztür: Start nur bei geschlossener Tür
	l.new_workpiece(60.0, 160.0)
	l.set_door(false)
	l.prog_sel = "WELLE_AUFTRAG2"
	ok(not l.nc.nc_start(prog(l, "WELLE_AUFTRAG2")), "Zyklusstart bei offener Tür verweigert")
	l.toggle_door()
	for i in 30:
		l._physics_process(0.05)
	ok(l.door_closed() and l._door.position.x > l.DOOR_TRAVEL - 0.001, "Tür zugeschoben (Pult fährt mit)")

	# --- Tür am Griff mit der Maus ziehen
	l.set_door(false)
	l.operating = true
	l.set_view("front")
	l.cam_pan = Vector3(-0.15, 0.1, 0)
	for i in 30:
		l._update_camera(0.1)
	var hp: Vector3 = l.to_global(l.HANDLE_POS)
	var mp: Vector2 = l.op_cam.unproject_position(hp)
	ok(l.handle_hit(mp), "Griff unter der Maus erkannt (%s)" % mp)
	ok(not l.handle_hit(l.op_cam.unproject_position(hp + Vector3(0.2, 0, 0))), "20 cm daneben kein Griff")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = mp
	ok(l._door_input(ev), "Griff gepackt")
	var target_px: Vector2 = l.op_cam.unproject_position(l.to_global(l.HANDLE_POS + Vector3(l.DOOR_TRAVEL * 0.5, 0, 0)))
	var mv := InputEventMouseMotion.new()
	mv.position = target_px
	l._door_input(mv)
	ok(absf(l.door_t - 0.5) < 0.05 and not l.door_closed(), "halb zugezogen (%.2f)" % l.door_t)
	mv.position = l.op_cam.unproject_position(l.to_global(l.HANDLE_POS + Vector3(l.DOOR_TRAVEL * 0.97, 0, 0)))
	l._door_input(mv)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	l._door_input(up)
	for i in 10:
		l._physics_process(0.05)
	ok(l.door_closed(), "losgelassen nahe am Ende: rastet zu (%.3f)" % l.door_t)
	l.operating = false
	l.set_view("reset")

	# --- Simulation vorab
	var sim: Dictionary = NcCam.simulate(prog(l, "WELLE_AUFTRAG2"), l)
	ok(sim["errs"].is_empty(), "Simulation ohne Fehler %s" % [sim["errs"]])
	ok(sim["moves"].size() > 20 and sim["time"] > 30.0, "Simulation: %d Züge, %.0f s" % [sim["moves"].size(), sim["time"]])

	# --- Längsschruppen + Schlichten (Auftrag 2)
	ok(l.nc.nc_start(prog(l, "WELLE_AUFTRAG2")), "NC-Start WELLE_AUFTRAG2")
	l.nc.set_override(1.2)
	# Tür während des Laufs öffnen -> Halt, Spindel aus
	for i in 200:
		l._physics_process(0.05)
	l.toggle_door()
	l._physics_process(0.05)
	ok(l.nc.state == "hold" and not l.spindle_on, "Tür auf: Programm angehalten, Spindel aus (%s)" % l.nc.state)
	var zh: float = l.tool_z
	for i in 20:
		l._physics_process(0.05)
	ok(is_equal_approx(zh, l.tool_z), "angehalten: keine Bewegung")
	l.toggle_spindle()
	ok(not l.spindle_on, "Handbedienung im Automatik gesperrt")
	ok(not l.nc.nc_start({}), "Fortsetzen bei offener Tür verweigert")
	l.toggle_door()
	for i in 30:
		l._physics_process(0.05)
	ok(l.nc.nc_start({}), "Tür zu: NC-Start setzt fort")
	var dur := run(l)
	ok(l.nc.state == "done", "Programm beendet (%s %s) nach %.0f s" % [l.nc.state, l.nc.alarm, dur])
	ok(not l.estop, "keine Kollision")
	ok(str(l.tool()["id"]) == "T3", "zuletzt T3 eingeschwenkt")
	var res: Dictionary = l.evaluate(Jobs.LIST[1])
	print("\n".join(res["lines"]))
	ok(res["score"] >= 0.999, "Auftrag 2 aus dem Programm erfüllt (%d/%d)" % [res["ok"], res["total"]])
	ok(absf(l.radius_at(149.4) - 25.0) < 0.6 and l.radius_at(149.4) < 25.0, "Fase an der Stirnseite (Ø%.2f bei Z149,4)" % (l.radius_at(149.4) * 2.0))
	ok(absf(l.radius_at(120.0) * 2.0 - 50.0) < 0.05, "Schlichtmaß Ø50 (%.3f)" % (l.radius_at(120.0) * 2.0))
	ok(l.rz[int(120.0 / l.SEG)] < 8.0, "geschlichtete Oberfläche Rz %.1f" % l.rz[int(120.0 / l.SEG)])

	# --- Planschruppen Rechteck: 2 mm von der Stirnseite
	l.new_workpiece(60.0, 160.0)
	l.nc.reset()
	l.index_slot(0, true)
	ok(l.nc.nc_start(prog(l, "PLANEN_2MM")), "NC-Start PLANEN_2MM")
	run(l)
	ok(l.nc.state == "done" and not l.estop, "Planen beendet (%s %s)" % [l.nc.state, l.nc.alarm])
	ok(absf(l.part_length() - 158.0) < 0.3, "Länge nach dem Planen %.2f" % l.part_length())
	ok(absf(l.radius_at(100.0) - 30.0) < 0.01, "Umfang nicht angetastet")

	# --- Planschruppen + Plan-Schlichten an der Kontur (Bund)
	l.new_workpiece(60.0, 160.0)
	l.nc.reset()
	ok(l.nc.nc_start(prog(l, "BUND_PLAN")), "NC-Start BUND_PLAN")
	run(l)
	ok(l.nc.state == "done" and not l.estop, "Bund beendet (%s %s)" % [l.nc.state, l.nc.alarm])
	ok(absf(l.part_length() - 156.0) < 0.3, "Bund: Länge %.2f" % l.part_length())
	ok(absf(l.radius_at(150.0) * 2.0 - 30.0) < 0.1, "Bund: Zapfen Ø%.3f" % (l.radius_at(150.0) * 2.0))
	ok(absf(l.radius_at(130.0) * 2.0 - 52.0) < 0.1, "Bund: Ø%.3f" % (l.radius_at(130.0) * 2.0))
	ok(absf(l.radius_at(110.0) - 30.0) < 0.01, "Bund: Rohteil links unberührt")

	# --- Pult-Software
	var s = l.screen
	ok(s != null, "Pult-Software vorhanden")
	await process_frame
	for pg in ["jog", "auto", "pm", "edit", "sim", "tools", "msgs"]:
		s.show_page(pg)
		await process_frame
		ok(s.page == pg, "Seite %s" % pg)
	# neues Programm: Kontur + Längsschruppen über die Softkeys
	s.show_page("pm")
	s._pm_name.text = "test 1"
	s._pm_new()
	ok(s.open_prog == "TEST_1" and s.page == "edit", "Neues Programm TEST_1 im Editor")
	s._ed_new("contour")
	ok(s.page == "contour", "Konturrechner offen")
	var n0: int = s._ct["els"].size()
	s._ct_sel = n0
	s._ct_add(Vector2(-20.0, 0.0))
	ok(s._ct["els"].size() == n0 + 1, "Element angehängt")
	s._ct_accept()
	var tp: Dictionary = s.prog_by_name("TEST_1")
	ok(tp["blocks"].size() == 2 and str(tp["blocks"][1]["type"]) == "contour", "Kontur im Arbeitsplan")
	s._ed_new("stock")
	ok(s.page == "form" and str(s._form_blk["contour"]) == "KONTUR1", "Maske Konturabspanen mit KONTUR1")
	s._form_blk["d"] = 9.0
	s._form_accept()
	ok(s.page == "form", "D 9 mm wird nicht übernommen")
	s._form_blk["d"] = 2.0
	s._form_accept()
	ok(s.page == "edit" and tp["blocks"].size() == 3, "Abspansatz übernommen")
	s.show_page("sim")
	ok(s._sim_plot.moves.size() > 0, "Simulation zeichnet Bahnen (%d)" % s._sim_plot.moves.size())
	s._select_prog("TEST_1")
	ok(l.prog_sel == "TEST_1" and s.page == "auto", "Programm angewählt, AUTO")
	# Softkey per Mausklick auf dem Bildschirm: JOG, Spindel
	s.show_page("jog")
	await process_frame
	var was: bool = l.spindle_on
	var cpos: Vector2 = s.vsk[0].get_global_rect().get_center()
	_click(l, cpos)
	ok(l.spindle_on != was, "Softkey Spindel per Klick")
	l.spindle_on = false
	# Programme werden gespeichert
	var st: Dictionary = l.get_state()
	var l2 = load("res://scripts/machine/lathe.gd").new()
	root.add_child(l2)
	await process_frame
	l2.set_state(st)
	ok(l2.programs.size() == l.programs.size() and l2.prog_sel == "TEST_1" and l2.door_closed(), "Programme, Anwahl und Tür geladen")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()


func _click(l, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	l.push_screen_event(e, p)
	var e2 := e.duplicate() as InputEventMouseButton
	e2.pressed = false
	l.push_screen_event(e2, p)
