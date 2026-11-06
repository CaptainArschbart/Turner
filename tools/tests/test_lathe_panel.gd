extends SceneTree
## Headless-Prüfung: Drehrichtung, Verfahren über die Drehmitte, konstante Schnittgeschwindigkeit,
## Vierfach-Werkzeughalter mit Kollisionsprüfung, Speichern/Laden und Bedienpult.
## Aufruf: godot --headless --path . -s res://tools/tests/test_lathe_panel.gd

var checks := 0
var fails := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


func _initialize() -> void:
	await process_frame
	var l = load("res://scripts/machine/lathe.gd").new()
	root.add_child(l)
	await process_frame
	l.new_workpiece(60.0, 160.0)

	# --- Drehrichtung: Oberfläche an der Schneide (Bedienerseite +Z) läuft nach unten
	l.spindle_on = true
	l.spindle_speed = l.rpm()
	l.spindle_pivot.transform.basis = Basis.IDENTITY
	l._physics_process(0.002)
	var front: Vector3 = l.spindle_pivot.transform.basis * Vector3(0, 0, 1)
	ok(front.y < -0.01, "Rechtslauf: Vorderseite dreht nach unten (y=%.3f)" % front.y)
	l.spindle_on = false
	l.spindle_speed = 0.0

	# --- Drehzahl / Vorschub / G96
	l.set_rpm(5000.0)
	ok(is_equal_approx(l.rpm_set, 3000.0), "Drehzahl begrenzt auf 3000")
	l.set_rpm(1234.4)
	ok(is_equal_approx(l.rpm(), 1234.0), "Drehzahl stufenlos")
	l.step_rpm(1)
	ok(is_equal_approx(l.rpm_set, 1250.0), "Taste: nächste Stufe 1250")
	l.set_feed(0.123)
	ok(is_equal_approx(l.feed(), 0.12), "Vorschub auf 0,01 gerundet")
	l.set_feed(2.0)
	ok(is_equal_approx(l.feed(), 0.5), "Vorschub begrenzt")
	l.css = true
	l.set_vc(150.0)
	l.set_rpm_limit(2000.0)
	l.tool_x = 25.0
	ok(absf(l.rpm() - 150000.0 / (PI * 50.0)) < 0.5, "G96: n = vc*1000/(pi*d) bei Ø50 (%.1f)" % l.rpm())
	l.tool_x = 0.0
	ok(is_equal_approx(l.rpm(), 2000.0), "G96: an der Drehmitte auf n max begrenzt")
	l.tool_x = 150.0
	ok(l.rpm() > 150.0 and l.rpm() < 170.0, "G96: großer Durchmesser -> kleine Drehzahl")
	l.step_rpm(1)
	ok(is_equal_approx(l.vc_set, 160.0), "G96: Taste ändert vc")
	l.css = false
	l.set_rpm(800.0)

	# --- Über die Drehmitte hinaus (frei, hinter dem Werkstück)
	l.tool_z = 200.0
	l.tool_x = 50.0
	l.move_tool(0.0, -300.0)
	ok(is_equal_approx(l.tool_x, l.X_MIN), "X fährt bis %.1f (Anzeige %.0f)" % [l.tool_x, l.tool_x * 2.0])
	ok(not l.estop, "frei hinter der Mitte: kein Not-Halt")

	# Plandrehen bis über die Mitte
	l.tool_x = 40.0
	l.tool_z = 158.0
	l.spindle_speed = 800.0
	l.spindle_on = true
	for i in 120:
		l.move_tool(0.0, -0.5, false, 2.0)
	ok(not l.estop, "Plandrehen durch die Mitte ohne Not-Halt")
	ok(l.tool_x < -5.0, "nach dem Plandrehen hinter der Mitte (X %.1f)" % (l.tool_x * 2.0))
	ok(l.radius_at(158.2) <= 0.05, "Stirnfläche bis zur Mitte abgedreht")

	# Hinter der Mitte in Z ins Material: Plattenbruch
	l.tool_z = 200.0
	l.tool_x = -20.0
	l.move_tool(-60.0, 0.0, false, 2.0)
	ok(l.estop, "Hinter der Mitte ins Material -> Not-Halt")
	ok(l.tool_z > 150.0, "bleibt vor dem Werkstück stehen (Z %.1f)" % l.tool_z)
	l.estop = false
	l.spindle_on = false
	l.spindle_speed = 0.0

	# --- Werkzeughalter
	l.new_workpiece(60.0, 160.0)
	ok(l.holder == ["T1", "", "T3", ""] and l.active_slot == 0, "Grundbestückung T1 / T3 gegenüber")
	ok(l.slot_status(2)["level"] == 0, "Platz 3 (gegenüber) frei: %s" % l.slot_status(2)["text"])
	l.tool_z = 170.0
	l.tool_x = 40.0
	ok(l.mount_tool(1, "T6"), "T6 in Platz 2 einspannen (vor dem Werkstück)")
	var t6: int = LatheTools.index_of("T6")
	if l.model:
		ok(l.model.has_tool("T6") and (l.model._holders["T6"]["node"] as Node3D).visible and not l.tool_nodes[t6].visible,
			"T6 als Stechschwert aus dem Modell im Halter")
	else:
		ok(l.tool_nodes[t6].visible, "T6 sichtbar im Halter")
	# prozedurales Werkzeug (T4): Klemmhalter aus dem Modell
	var t4: int = LatheTools.index_of("T4")
	if l.model:
		ok(l.model.shank_box.size.x > 10.0, "Schaftmaß aus dem Modell (%s)" % l.model.shank_box)
		var kh: Node = l.tool_nodes[t4].find_child("Klemmhalter", false, false)
		ok(kh != null, "T4 hat einen Klemmhalter aus dem Modell")
		if kh:
			var msh: Array = kh.find_children("*", "MeshInstance3D", true, false)
			ok(msh.size() >= 3, "Klemmhalter mit Schrauben/Höheneinstellung (%d Teile)" % msh.size())
			ok(kh.find_child("insert*", true, false) == null, "Klemmhalter ohne Modell-Platte")
			# Klemmhalter-Kopie liegt dort, wo im Modell der T1-Halter sitzt (gleicher Platz, gleiche Höhe)
			var hb: AABB = _world_aabb(kh)
			print("T4 Klemmhalter ", hb, "  T1 Halter ", _world_aabb(l.model._holders["T1"]["node"]))
			ok(absf(hb.end.y - _world_aabb(l.model._holders["T1"]["node"]).end.y) < 0.002, "Klemmhalter auf Halterhöhe")
	# Linksmeißel: Schaft schließt zur Reitstockseite mit der Platte ab
	var sp2: Vector2 = l._shank_span(LatheTools.get_tool(LatheTools.index_of("T2")))
	ok(is_equal_approx(sp2.y, float(LatheTools.get_tool(LatheTools.index_of("T2"))["zmax"])), "T2-Schaft bündig zur Reitstockseite")
	# Stechschwert: Platte sitzt außen am Blockhalter (L2 ~110 mm), weggedreht reicht die Spitze
	# bis etwa 110 mm unter die Kopfachse -> bei X Ø80 trifft es das Ø60-Teil, bei Ø120 frei
	ok(l.slot_status(1)["level"] != 0, "Platz 2 (Stechschwert) bei X Ø80 über dem Ø60-Teil: %s" % l.slot_status(1)["text"])
	l.tool_x = 60.0
	ok(l.slot_status(1)["level"] == 0, "Platz 2 bei X Ø120 über dem Ø60-Teil frei: %s" % l.slot_status(1)["text"])
	# vorgedrehtes Teil: Ø60 bis Z 60, danach Ø38
	for i in l.profile.size():
		if i * l.SEG >= 60.0:
			l.profile[i] = 19.0
	l.tool_x = 20.0
	var st: Dictionary = l.slot_status(1)
	ok(st["level"] == 1, "Platz 2 warnt vor Werkstück beim Längsdrehen: %s" % st["text"])
	ok(not l.mount_tool(0, ""), "eingeschwenktes Werkzeug lässt sich nicht ausbauen")
	ok(not l.mount_tool(1, "T1"), "aktives T1 nicht umsetzbar")
	ok(l.mount_tool(3, "T6") and l.holder[1] == "" and l.holder[3] == "T6", "T6 von Platz 2 nach 4 umgesetzt")
	ok(l.mount_tool(1, "T6"), "T6 zurück in Platz 2")

	# Längsdrehen Richtung Futter mit T6 in Platz 2: Halter rammt das Werkstück
	l.tool_x = 20.0
	l.tool_z = 230.0
	l.spindle_on = true
	l.spindle_speed = 800.0
	l.move_tool(-200.0, 0.0, false, 2.0)
	ok(l.estop, "Kollision Halterplatz 2 mit Werkstück -> Not-Halt")
	ok(l.tool_z > 100.0, "Halt vor dem Werkstück (Z %.1f)" % l.tool_z)
	l.estop = false
	l.spindle_on = false
	l.spindle_speed = 0.0

	# Spindel steht: nur Warnung, keine Bewegung
	var z_before: float = l.tool_z
	l.move_tool(-5.0, 0.0)
	ok(not l.estop and is_equal_approx(l.tool_z, z_before), "stehende Spindel: blockiert ohne Not-Halt")

	# Einschwenken
	l.tool_z = 250.0
	l.tool_x = 60.0
	l.spindle_speed = 800.0
	ok(not l.index_slot(2), "Einschwenken bei laufender Spindel verweigert")
	l.spindle_speed = 0.0
	l._physics_process(0.0)
	var piv_before: Vector3 = l.model._post_root.global_position if l.model else Vector3.ZERO
	var coord_before := Vector2(l.tool_z, l.tool_x)
	var slide_before: Vector3 = l.cross_slide.global_position
	var mks_before: Vector2 = l.machine_pos()
	var mid_slide := Vector3.INF
	var expect: Vector2 = l._coord_after("T3")
	ok(l.index_slot(2) and l.active_slot == 2, "Platz 3 eingeschwenkt")
	ok(str(l.tool()["id"]) == "T3", "aktives Werkzeug T3")
	ok(l.is_indexing(), "Einschwenken wird animiert")
	ok(absf(l._anim_to - l._anim_from) > 3.1, "180° Drehung (%.2f rad)" % (l._anim_to - l._anim_from))
	ok(not l.index_slot(1), "während der Drehung kein weiteres Einschwenken")
	l.toggle_spindle()
	ok(not l.spindle_on, "Spindel startet nicht während des Einschwenkens")
	l._step_index_anim(l.INDEX_LEVER_T * 0.5)
	if l.model and l.model._lever:
		ok(not l.model._lever.transform.basis.is_equal_approx(l.model._lever_xf.basis), "Spannhebel wird gelöst")
	l._step_index_anim(l.INDEX_LEVER_T * 0.5 + l.INDEX_ROT_T)
	var mid_a: float = fposmod(l._vis_angle, TAU)
	ok(mid_a > 0.3 and mid_a < 2.9 or mid_a > 3.4 and mid_a < 6.0, "Kopf mitten in der Drehung (%.2f rad)" % mid_a)
	mid_slide = l.cross_slide.global_position
	l._step_index_anim(5.0)
	ok(not l.is_indexing(), "Animation beendet")
	l._physics_process(0.0)
	if l.model:
		var piv_after: Vector3 = l.model._post_root.global_position
		ok(piv_after.distance_to(piv_before) < 0.0002, "Halterkopf dreht nur, verschiebt sich nicht (%.2f mm)" % (piv_after.distance_to(piv_before) * 1000.0))
	ok(Vector2(l.tool_z, l.tool_x).distance_to(expect) < 0.01, "Koordinaten auf die neue Schneide umgerechnet (%s -> %s)" % [coord_before, Vector2(l.tool_z, l.tool_x)])
	ok(l.cross_slide.global_position.distance_to(slide_before) < 0.00001 and mid_slide.distance_to(slide_before) < 0.00001,
		"Schlitten bleibt beim Einschwenken stehen (%.3f mm)" % (l.cross_slide.global_position.distance_to(slide_before) * 1000.0))
	ok(l.machine_pos().distance_to(mks_before) < 0.001, "MKS des Bezugspunkts F unverändert (%s -> %s)" % [mks_before, l.machine_pos()])
	ok(Vector2(l.tool_z, l.tool_x).distance_to(coord_before) > 0.5, "Anzeige springt auf die neue Schneide (Nullpunktverschiebung)")
	var t3d: Dictionary = l.tool_data(l.tool())
	ok(Vector2(l.tool_z, l.tool_x).distance_to(l.machine_pos() + Vector2(t3d["l2"], t3d["l1"])) < 0.001, "Schneide = F + Korrektur (L2, L1)")
	# alle Werkzeuge mit eigener Korrektur
	var offs: Array = []
	for i in LatheTools.count():
		offs.append(l.tool_offset(LatheTools.get_tool(i)))
	var distinct := true
	for i in offs.size():
		for j in range(i + 1, offs.size()):
			if (offs[i] as Vector2).distance_to(offs[j]) < 0.5:
				distinct = false
	ok(distinct, "jedes Werkzeug hat eigene Korrekturwerte %s" % [offs])
	if l.model:
		ok(l.model.has_tool("T5"), "45°-Fasenmeißel T5 aus dem Modell auf dem Kopf")
		var x1: Transform3D = l.model._holders["T1"]["xf"]
		var x5: Transform3D = l.model._holders["T5"]["xf"]
		ok(x1.origin.distance_to(x5.origin) < 0.001, "T5-Halter sitzt am selben Schwalbenschwanz wie T1")
	ok(not l.index_slot(3), "leerer Platz 4 lässt sich nicht einschwenken")
	if l.model:
		ok(is_equal_approx(l.model._post.transform.basis.get_euler().y, PI) or absf(absf(l.model._post.transform.basis.get_euler().y) - PI) < 0.01, "Halterkopf um 180° gedreht")
	l.select_tool(LatheTools.index_of("T7"))
	ok(l.holder[2] == "T7" and str(l.tool()["id"]) == "T7", "select_tool spannt T7 in den aktiven Platz")


	# --- Oberfläche: Schruppen rau, Schlichten fein, typische Fehler verschlechtern
	var LT = load("res://scripts/machine/lathe.gd")
	var t1: Dictionary = LatheTools.get_tool(LatheTools.index_of("T1"))
	var t3: Dictionary = LatheTools.get_tool(LatheTools.index_of("T3"))
	var rough: float = LT.surface_rz(t1, 0.3, 2.0, 150.0, true, false)["rz"]
	var fine: float = LT.surface_rz(t3, 0.08, 0.3, 200.0, true, false)["rz"]
	ok(rough > 15.0 and fine < 4.0 and rough > fine * 5.0, "Schruppen rau (%.1f), Schlichten fein (%.1f)" % [rough, fine])
	ok(LT.surface_rz(t3, 0.08, 0.3, 50.0, true, false)["rz"] > fine * 2.0, "zu niedriges vc: Aufbauschneide")
	ok(LT.surface_rz(t3, 0.08, 0.3, 200.0, false, false)["rz"] > fine, "ohne KSS schlechter")
	ok(LT.surface_rz(t3, 0.015, 0.3, 200.0, true, false)["rz"] > fine, "zu kleiner Vorschub quetscht")
	ok(LT.surface_rz(t3, 0.08, 0.02, 200.0, true, false)["rz"] > fine, "zu kleine Zustellung reibt")
	ok(LT.surface_rz(t1, 0.3, 3.8, 150.0, true, false)["rz"] > rough * 1.5, "zu große Zustellung rattert")
	ok(LT.surface_rz(t3, 0.08, 0.3, 200.0, true, true)["rz"] > fine, "Handvorschub ungleichmäßig")
	# Schnitt im Auto-Vorschub schreibt die Rautiefe aufs Teil
	l.new_workpiece(60.0, 160.0)
	l.estop = false
	l.select_tool(LatheTools.index_of("T3"), true)
	l.set_rpm(1200.0)
	l.css = false
	l.set_feed(0.08)
	l.coolant = true
	l.tool_z = 165.0
	l.tool_x = 29.7
	l.spindle_on = true
	l.spindle_speed = 1200.0
	l.set_auto_dir(1, -1)
	for i in 900:
		l._physics_process(1.0 / 60.0)
	var seg := int(150.0 / l.SEG)
	ok(l.machined[seg] == 1 and l.rz[seg] < 5.0, "Schlichtschnitt: Rz %.1f auf dem Teil (%s)" % [l.rz[seg], l.last_rz_hint])
	l.set_auto_dir(-1, 0)
	l.spindle_on = false
	l.spindle_speed = 0.0
	# --- Speichern / Laden
	l.css = true
	l.set_vc(180.0)
	l.set_rpm(1111.0)
	l.set_feed(0.22)
	var state: Dictionary = l.get_state()
	var l2 = load("res://scripts/machine/lathe.gd").new()
	root.add_child(l2)
	await process_frame
	l2.set_state(state)
	ok(l2.holder == l.holder and l2.active_slot == 2, "Halterbestückung geladen %s" % str(l2.holder))
	ok(l2.css and is_equal_approx(l2.vc_set, 180.0), "G96 geladen")
	ok(is_equal_approx(l2.rpm_set, 1111.0) and is_equal_approx(l2.feed_set, 0.22), "n und f geladen")
	var old_state := {"stock_d": 60.0, "stock_len": 160.0, "rpm_idx": 9, "feed_idx": 5, "tool": 3}
	l2.set_state(old_state)
	ok(is_equal_approx(l2.rpm_set, 800.0) and is_equal_approx(l2.feed_set, 0.15), "alter Spielstand: Stufen übernommen")
	ok(str(l2.tool()["id"]) == "T4", "alter Spielstand: Werkzeug T4 aktiv")

	# --- Bedienpult
	var panel = load("res://scripts/ui/machine_panel.gd").new()
	panel.lathe = l2
	root.add_child(panel)
	await process_frame
	await process_frame
	panel._rpm["slider"].value = 1500.0
	ok(is_equal_approx(l2.rpm_set, 1500.0), "Schieber setzt Drehzahl")
	panel._feed["slider"].value = 0.3
	ok(is_equal_approx(l2.feed_set, 0.3), "Schieber setzt Vorschub")
	panel._css_btn.button_pressed = false
	ok(not l2.css, "G96-Schalter aus")
	panel._css_btn.button_pressed = true
	ok(l2.css, "G96-Schalter an")
	panel._on_mount(1, LatheTools.index_of("T5") + 1)
	ok(l2.holder[1] == "T5", "Auswahlliste spannt T5 in Platz 2")
	panel._slot_btns[1].pressed.emit()
	l2._step_index_anim(5.0)
	ok(l2.active_slot == 1, "Knopf schwenkt Platz 2 ein")
	panel._spindle_btn.pressed.emit()
	ok(l2.spindle_on, "Knopf startet Spindel")
	var btn_dir := func(d: Vector2i) -> Button:
		for b in panel._feed_btns:
			if b.get_meta("dir") == d:
				return b
		return null
	ok(panel._feed_btns.size() == 5, "Kreuzschalter mit 4 Richtungen + Stopp")
	btn_dir.call(Vector2i(-1, 0)).pressed.emit()
	ok(l2.auto_feed and l2.auto_sign_z == -1, "Pfeil links: Längsvorschub Z-")
	btn_dir.call(Vector2i(1, 0)).pressed.emit()
	ok(l2.auto_feed and l2.auto_sign_z == 1 and not l2.auto_feed_x, "Pfeil rechts: Z+")
	btn_dir.call(Vector2i(0, 1)).pressed.emit()
	ok(l2.auto_feed_x and l2.auto_sign_x == 1 and not l2.auto_feed, "Pfeil runter: X+")
	btn_dir.call(Vector2i(0, 1)).pressed.emit()
	ok(not l2.auto_feed_x, "gleicher Pfeil nochmal: aus")
	btn_dir.call(Vector2i(0, -1)).pressed.emit()
	ok(l2.auto_feed_x and l2.auto_sign_x == -1, "Pfeil hoch: X-")
	btn_dir.call(Vector2i(0, 0)).pressed.emit()
	ok(not l2.auto_feed and not l2.auto_feed_x, "Mitte: Vorschub aus")
	# Handrad-Wahlschalter
	var sett = root.get_node("Settings")
	var step_before := int(sett.mouse["handwheel_step"])
	panel._hw_step_btns[2].pressed.emit()
	ok(is_equal_approx(sett.handwheel_step(), 0.1), "Wahlschalter: Handrad 0,1 mm")
	panel._hw_step_btns[0].pressed.emit()
	ok(is_equal_approx(sett.handwheel_step(), 0.001), "Wahlschalter: Handrad 0,001 mm")
	sett.set_handwheel_step(step_before)
	panel._hw_axis_btns[1].pressed.emit()
	ok(l2.hw_axis == 1, "Handrad-Achse Z")
	panel._hw_axis_btns[0].pressed.emit()
	ok(l2.hw_axis == 0, "Handrad-Achse X")
	# Tippen im Vorschub, Shift 10-fach
	l2.spindle_speed = 1000.0
	ok(is_equal_approx(l2.jog_speed(), l2.feed() * 1000.0 / 60.0), "WASD fährt im eingestellten Vorschub (%.2f mm/s)" % l2.jog_speed())
	ok(is_equal_approx(l2.jog_speed(true), l2.jog_speed() * 10.0), "Shift: 10-facher Vorschub")
	# Auto-Vorschub läuft nach dem Verlassen weiter
	l2.tool_z = 300.0
	l2.tool_x = 80.0
	l2.set_auto_dir(1, -1)
	l2.operating = true
	l2.stop_operating()
	var z0: float = l2.tool_z
	for i in 5:
		l2._physics_process(0.05)
	ok(l2.auto_feed and l2.tool_z < z0 - 0.01, "Auto-Vorschub läuft nach dem Verlassen weiter (Z %.2f -> %.2f)" % [z0, l2.tool_z])
	l2.set_auto_dir(-1, 0)
	await process_frame
	ok(panel._slot_btns[1].text == "AKTIV", "Pult zeigt aktiven Platz")
	ok(panel.size.x <= 450.0, "HUD-Menü schmaler (%.0f px)" % panel.size.x)

	# --- Bildschirm am Bedienpult der Maschine
	ok(l2.screen_vp != null and l2.screen != null, "Pult-Bildschirm mit Zyklensteuerung vorhanden")
	var sp = l2.screen
	sp.show_page("jog")
	await process_frame
	await process_frame
	var vp_size := Vector2(l2.screen_vp.size)
	ok(sp.get_global_rect().end.y <= vp_size.y + 1.0 and sp.hsk[7].get_global_rect().end.x <= vp_size.x + 1.0, "Oberfläche passt auf den Bildschirm (%s in %s)" % [sp.get_global_rect(), vp_size])
	# Klick direkt in den Bildschirm
	var was_on: bool = l2.spindle_on
	var c: Vector2 = sp.vsk[0].get_global_rect().get_center()
	_click_px(l2, c)
	ok(l2.spindle_on != was_on, "Klick auf Pult-Bildschirm schaltet Spindel")
	# Über die Kamera: Pultansicht, Strahl aus der Mausposition trifft den Bildschirm
	l2.operating = true
	l2.set_view("panel")
	for i in 3:
		l2._update_camera(1.0)
	var mid: Vector2 = l2.op_cam.unproject_position(l2.to_global(l2.screen_center()))
	var px: Vector2 = l2.screen_pixel(mid)
	ok(px.distance_to(vp_size * 0.5) < 3.0, "Pultansicht: Bildmitte = Bildschirmmitte (%s)" % px)
	ok(l2.screen_pixel(mid + Vector2(5000, 0)).x < 0.0, "neben dem Bildschirm kein Treffer")
	l2.spindle_on = false
	var bc: Vector2 = sp.vsk[2].get_global_rect().get_center()
	var uv := bc / vp_size
	var gp: Vector3 = l2._screen_mi.global_transform * Vector3((uv.x - 0.5) * l2.SCREEN_SIZE.x, (0.5 - uv.y) * l2.SCREEN_SIZE.y, 0.0)
	var mpos: Vector2 = l2.op_cam.unproject_position(gp)
	var css_before: bool = l2.css
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = mpos
	ok(l2._screen_input(ev), "Mausklick auf Pult wird verbraucht")
	var ev2 := ev.duplicate() as InputEventMouseButton
	ev2.pressed = false
	l2._screen_input(ev2)
	ok(l2.css != css_before, "Mausklick über Kamera schaltet G96 am Pult")
	l2.set_view("back")
	ok(not l2._panel_view, "Pultansicht verlassen")
	l2.operating = false

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()


func _world_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		list.append(n)
	for m in list:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


func _click_px(l, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	l.push_screen_event(e, p)
	var e2 := e.duplicate() as InputEventMouseButton
	e2.pressed = false
	l.push_screen_event(e2, p)
