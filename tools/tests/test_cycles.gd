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
	l.power_on(true)
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

	# --- Zweite Kontur mitten am Teil: Material rechts davon bleibt stehen
	var prof := PackedFloat32Array()
	prof.resize(int(160.0 / NcCam.SEG))
	prof.fill(30.0)
	var k2 := {"type": "contour", "name": "K2", "x0": 33.0, "z0": -80.0, "els": [
		{"x": 33.0, "z": -120.0, "tr": 0, "tv": 0.0},
		{"x": 60.0, "z": -120.0, "tr": 0, "tv": 0.0}]}
	var k2p := {"blocks": [k2]}
	var sb := {"type": "stock", "contour": "K2", "mode": 1, "dir": 0}
	var tgr: Dictionary = NcCam.target(sb, k2p, prof, 150.0)
	var tg2: PackedFloat32Array = tgr["tg"]
	ok(is_equal_approx(tg2[int(140.0 / NcCam.SEG)], 30.0), "Kontur bei Z-80: rechts davon bleibt Material (%.2f)" % tg2[int(140.0 / NcCam.SEG)])
	ok(absf(tg2[int(50.0 / NcCam.SEG)] - 16.5) < 0.01, "Kontur bei Z-80: Ø33 im Konturbereich (%.2f)" % tg2[int(50.0 / NcCam.SEG)])
	k2["x0"] = 0.0
	tg2 = NcCam.target(sb, k2p, prof, 150.0)["tg"]
	ok(tg2[int(140.0 / NcCam.SEG)] == 0.0, "Kontur ab Drehmitte: rechts davon wird abgespant")

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
	for i in 40:
		l._physics_process(0.05)
	var dx: float = l._door.position.x + l.DOOR_X1 - (l.carriage.position.x + l.CARRIAGE_RIGHT)
	ok(l.door_closed() and absf(dx) < 0.002, "Tür zum Schlitten geschoben und eingerastet (%.3f)" % dx)
	l.move_tool(-40.0, 0.0)
	dx = l._door.position.x + l.DOOR_X1 - (l.carriage.position.x + l.CARRIAGE_RIGHT)
	ok(l.door_closed() and absf(dx) < 0.002, "eingerastete Tür fährt mit dem Schlitten (%.3f)" % dx)
	l.move_tool(40.0, 0.0)

	# --- Tür mit Linksklick: Tür anklicken -> rastet am Schlitten ein, Hebel -> löst
	l.set_door(false)
	l.operating = true
	l.set_view("front")
	l.cam_pan = Vector3(-0.15, 0.1, 0)
	l._dist_t = 1.3                 # vor der Tür (sonst blendet die Kamera sie aus)
	for i in 30:
		l._update_camera(0.1)
	var hp: Vector3 = l.to_global(l.HANDLE_POS)
	var mp: Vector2 = l.op_cam.unproject_position(hp)
	ok(l.handle_hit(mp), "Hebel unter der Maus erkannt (%s)" % mp)
	ok(not l.handle_hit(l.op_cam.unproject_position(hp + Vector3(0.2, 0, 0))), "20 cm daneben kein Hebel")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = l.op_cam.unproject_position(l.to_global(l.DOOR_BOX.get_center()))
	ok(l.door_hit(ev.position), "Türfenster unter der Maus erkannt")
	ok(l._door_input(ev), "Linksklick auf die Tür")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = ev.position
	l._door_input(up)
	l._physics_process(0.05)
	ok(not l.door_closed() and l.door_t > 0.0, "Tür schiebt sich nach rechts (%.2f)" % l.door_t)
	for i in 40:
		l._physics_process(0.05)
	ok(l.door_closed(), "Tür am Schlitten eingerastet")
	ok(not l._door_input(ev) or l.door_closed(), "Klick auf eingerastete Tür löst sie nicht")
	ev.position = l.op_cam.unproject_position(l.to_global(l.HANDLE_POS + Vector3(l._door.position.x, 0, 0)))
	ok(l._door_input(ev) and not l.door_closed(), "Klick auf den schwarzen Hebel löst die Tür")
	up.position = ev.position
	l._door_input(up)
	for i in 40:
		l._physics_process(0.05)
	ok(l.door_t < 0.001, "gelöste Tür aufgeschoben")
	# Ziehen: Tür folgt der Hand träge, rollt nach dem Loslassen nach und bleibt dann stehen
	var dz: float = l.DOOR_BOX.get_center().z
	var o: Vector3 = Vector3(l.DOOR_CX, l.DOOR_BOX.get_center().y, dz + 1.0)
	l.begin_door_drag(o, Vector3(0, 0, -1), false)
	l.drag_door_to(o + Vector3(0.3, 0, 0), Vector3(0, 0, -1))
	l._physics_process(0.02)
	var lag: float = l.door_t * l.DOOR_TRAVEL
	ok(lag > 0.0 and lag < 0.25, "Tür kommt beim Ziehen langsamer hinterher (%.3f m)" % lag)
	for i in 6:
		l._physics_process(0.02)
	var at_release: float = l.door_t
	l.end_door_drag()
	l._physics_process(0.02)
	ok(l.door_t > at_release, "losgelassene Tür rollt nach")
	for i in 100:
		l._physics_process(0.05)
	var rest: float = l.door_t
	l._physics_process(0.05)
	ok(not l.door_closed() and absf(l.door_t - rest) < 0.0001 and rest > 0.0, "Tür bleibt nach dem Ausrollen stehen (%.2f)" % rest)
	l.set_door(false)
	l.operating = false
	l.set_view("reset")

	# --- Ego-Ansicht: Fadenkreuz-Strahl trifft Tür bzw. Hebel, Linksklick (click) wirkt
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = l.get_world_3d().direct_space_state
	var aim := func(pm: Vector3):
		var gp: Vector3 = l.to_global(pm)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(gp + l.global_basis.z * 1.5, gp))
		return hit["collider"].get_meta("interact") if hit and hit["collider"].has_meta("interact") else null
	var tgt = aim.call(l.DOOR_BOX.get_center())
	ok(tgt != null and tgt.has_method("click") and not tgt.get("lever"), "Fadenkreuz auf der Tür: Tür-Ziel (%s)" % tgt)
	if tgt != null and tgt.has_method("click"):
		tgt.click(null)
	for i in 40:
		l._physics_process(0.05)
	ok(l.door_closed(), "Linksklick in der Ego-Ansicht: Tür eingerastet")
	await physics_frame
	await physics_frame
	tgt = aim.call(l.HANDLE_POS + Vector3(l._door.position.x, 0, 0))
	ok(tgt != null and tgt.has_method("click") and tgt.get("lever"), "Fadenkreuz auf dem Hebel: Hebel-Ziel (%s)" % tgt)
	if tgt != null and tgt.has_method("click"):
		tgt.click(null)
	ok(not l.door_closed(), "Linksklick auf den Hebel in der Ego-Ansicht löst die Tür")
	l.set_door(true)

	# --- Simulation vorab
	var sim: Dictionary = NcCam.simulate(prog(l, "WELLE_AUFTRAG2"), l)
	ok(sim["errs"].is_empty(), "Simulation ohne Fehler %s" % [sim["errs"]])
	ok(sim["moves"].size() > 20 and sim["time"] > 30.0, "Simulation: %d Züge, %.0f s" % [sim["moves"].size(), sim["time"]])

	# --- Schlichten: jede Planfläche genau EIN Planspan (kein Zug an der fertigen Fläche zurück)
	var mvs: Array = sim["moves"]
	var lastblk: int = int(mvs[mvs.size() - 1][3])
	var face_feeds := {}
	for k in range(1, mvs.size()):
		var m0: Array = mvs[k - 1]
		var m1: Array = mvs[k]
		if int(m1[3]) != lastblk or bool(m1[2]):
			continue
		if absf(float(m1[0]) - float(m0[0])) < 0.01 and absf(float(m1[1]) - float(m0[1])) > 1.0:
			var key := snappedf(float(m1[0]), 0.5)
			face_feeds[key] = int(face_feeds.get(key, 0)) + 1
	var twice := face_feeds.keys().filter(func(z): return int(face_feeds[z]) > 1)
	ok(face_feeds.size() >= 2 and twice.is_empty(), "Schlichten: jede Planfläche ein Zug (%s)" % [face_feeds])
	# Kontur ohne Absetzen in einem Zug: zwischen erstem und letztem Schnitt kein Eilgang
	var fm: Array = mvs.filter(func(m): return int(m[3]) == lastblk)
	var f0 := fm.find(fm.filter(func(m): return not bool(m[2]))[0])
	var g0_mid := 0
	for k in range(f0, fm.size() - 1):
		if bool(fm[k][2]):
			g0_mid += 1
	ok(g0_mid == 0, "Schlichten fährt die Kontur ohne Absetzen ab (%d Eilgänge dazwischen)" % g0_mid)

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
	for i in 80:
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

	# --- Plan-Schlichten: genau eine Zustellung - Eilgang über die Planfläche, dann in einem Zug
	# über die Mitte, ohne Nachrücken in Z und ohne Weg auf X0
	l.new_workpiece(60.0, 160.0)
	var pf := NcCam.new_program("PF")
	pf["blocks"].append({"type": "cut", "mode": 1, "dir": 1, "t": "T3", "f": 0.1, "v": 200.0,
		"z0": 0.0, "x1": 0.0, "z1": -1.0, "d": 1.0, "ux": 0.0, "uz": 0.0})
	var fs: Dictionary = NcCam.simulate(pf, l)
	var feeds: Array = fs["moves"].filter(func(m): return not bool(m[2]))
	ok(feeds.size() >= 1 and absf(float(feeds[0][0]) - 159.0) < 0.01 and float(feeds[0][1]) < 0.0,
		"Plan-Schlichten: ein Zug bei Z159 über die Mitte (%s)" % [feeds.slice(0, 3)])
	var bp: Dictionary = NcCam.simulate(prog(l, "BUND_PLAN"), l)
	var fin: Array = bp["moves"].filter(func(m): return int(m[3]) == bp["moves"][bp["moves"].size() - 1][3] and not bool(m[2]))
	ok(fin.size() >= 2 and float(fin[0][1]) < 30.0 and absf(float(fin[0][0]) - float(fin[1][0])) > 1.0,
		"Bund-Schlichten beginnt direkt an der Planfläche")
	var on_axis := false
	for k in fin.size() - 1:
		if absf(float(fin[k][1])) < 0.01 and absf(float(fin[k + 1][1])) < 0.01:
			on_axis = true
	ok(not on_axis, "Plan-Schlichten fährt nicht auf X0 in Z weiter")

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
	l2.power_on(true)
	await process_frame
	l2.set_state(st)
	ok(l2.programs.size() == l.programs.size() and l2.prog_sel == "TEST_1" and l2.door_closed(), "Programme, Anwahl und Tür geladen")

	# --- Werkstücknullpunkt an der Stirnfläche: Programm-Z negativ zum Futter hin
	l.new_workpiece(60.0, 170.0)
	ok(is_equal_approx(l.wcs_z, 170.0), "Nullpunkt Z0 an der Rohteil-Stirnfläche (%.1f)" % l.wcs_z)
	ok(float(prog(l, "PLANEN_2MM")["blocks"][1]["z1"]) < 0.0, "Beispielprogramm arbeitet bei Z minus")
	l.tool_z = 180.0
	s.show_page("jog")
	s._update_jog()
	ok(s._jog_pos.text.ends_with("10.000"), "Pult zeigt Z im WKS (%s)" % s._jog_pos.text.replace("\n", " / "))
	l.nc.reset()
	l.set_door(true)
	ok(l.nc.nc_start(prog(l, "PLANEN_2MM")), "NC-Start PLANEN_2MM am 170er Rohteil")
	run(l)
	ok(absf(l.part_length() - 168.0) < 0.3, "Planen um 2 mm ab Stirnfläche: Länge %.2f" % l.part_length())
	l.tool_z = 175.0
	l.set_wcs_face()
	ok(is_equal_approx(l.wcs_z, l.part_length()), "Z0 an die neue Stirnfläche gesetzt")
	l.set_wcs_tool()
	ok(is_equal_approx(l.wcs_z, 175.0), "Z0 an die Schneide gesetzt")
	var st2: Dictionary = l.get_state()
	l2.set_state(st2)
	ok(is_equal_approx(l2.wcs_z, 175.0), "Nullpunkt wird gespeichert")
	# alter Spielstand: Programme ab Backen-Stirnfläche werden auf WKS umgerechnet
	var old := {"name": "ALT", "blocks": [{"type": "head", "sc": 1.0, "xt": 160.0, "zt": 230.0, "smax": 2500.0, "kss": 1},
		{"type": "cut", "mode": 0, "dir": 1, "t": "T1", "f": 0.2, "v": 180.0, "z0": 160.0, "x1": 0.0, "z1": 158.0,
		"d": 1.0, "ux": 0.0, "uz": 0.0}]}
	var st3 := st2.duplicate(true)
	st3.erase("wcs_z")
	st3["stock_len"] = 160.0
	st3["programs"] = [old]
	l2.set_state(st3)
	var mb: Dictionary = l2.programs[0]["blocks"][1]
	ok(is_equal_approx(float(mb["z0"]), 0.0) and is_equal_approx(float(mb["z1"]), -2.0)
		and is_equal_approx(float(l2.programs[0]["blocks"][0]["zt"]), 70.0) and is_equal_approx(l2.wcs_z, 160.0),
		"alter Spielstand umgerechnet (Z0 %s Z1 %s)" % [mb["z0"], mb["z1"]])

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
