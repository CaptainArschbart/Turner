extends SceneTree
## Fräsmaschine: bedienen, Werkzeugwechsel, Zerspanen, Kollisionen, Aufträge, Speichern und Laden.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func spin_up(m) -> void:
	if not m.spindle_on:
		m.toggle_spindle()
	for i in 30:
		await physics_frame
func stop(m) -> void:
	if m.spindle_on:
		m.toggle_spindle()
	for i in 40:
		await physics_frame
func go(m, x: float, y: float, z: float, speed := 3.0) -> void:
	m.move_tool(x - m.tool_x, y - m.tool_y, z - m.tool_z, speed)
func mesh_bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		stack.append_array(c.get_children())
		if c is MeshInstance3D and c.mesh and c.is_visible_in_tree():
			var b: AABB = c.global_transform * c.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box
func reset(w) -> void:
	w.mill.estop = false
	w.mill.spindle_on = false
	w.mill.spindle_speed = 0.0
	w.mill.tool_z = 50.0
	w._mill_new_workpiece()
func _initialize() -> void:
	await process_frame
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var m = w.mill
	var p = w.player

	# Anvisieren und bedienen
	p.global_position = Vector3(6.85, 0.05, -1.4)
	p.yaw = 0.0
	p.pitch = -0.2
	for i in 10:
		await physics_frame
	ok(p._focus == m, "Fräsmaschine lässt sich anvisieren")
	m.interact(p)
	await process_frame
	ok(m.operating and p.operating == m, "Bedienung startet")
	ok(w.mill_hud.visible and not w.hud._cross.visible, "Fräs-HUD an, Fadenkreuz aus")
	ok(not w.hud._job_panel.visible, "Drehauftrag ausgeblendet")

	# Alle Werkzeuge lassen sich einwechseln
	for i in MillTools.TOOLS.size():
		m.select_tool(i)
		await process_frame
		ok(m.tool_idx == i and m._tool_node != null, "Werkzeug %d eingewechselt" % i)
		ok(absf(m._tool_node.global_position.y - (1.06 + m.tool_z * 0.001)) < 0.0001, "Schneide von Werkzeug %d auf angezeigter Z-Höhe" % i)
	ok(m.head.position.y > 1.0, "Fräskopf steht über dem Tisch")

	# Wechsel gesperrt bei laufender Spindel
	m.select_tool(0)
	await spin_up(m)
	m.select_tool(3)
	ok(m.tool_idx == 0, "Kein Wechsel bei laufender Spindel")
	await stop(m)

	# Fräsauftrag 1: Planfräsen mit dem Messerkopf
	m.select_tool(5)
	m.rpm_set = 630.0
	go(m, -40.0, 15.0, -2.0, 50.0)
	await spin_up(m)
	var money0: int = w.money
	for y in [15.0, 45.0]:
		go(m, -40.0, y, -2.0, 50.0)
		go(m, 140.0, y, -2.0, 3.0)
		go(m, 140.0, y, 5.0, 50.0)
		go(m, -40.0, y, 5.0, 50.0)
		go(m, -40.0, y, -2.0, 50.0)
	ok(not m.estop, "Planfräsen ohne Kollision")
	ok(absf(m.height_at(50.0, 30.0) + 2.0) < 0.01, "Höhe nach dem Planfräsen")
	var res: Dictionary = m.evaluate(MillJobs.get_job(0))
	ok(float(res["score"]) >= 0.999, "Auftrag 1 in Toleranz: " + str(res["lines"]))
	go(m, -40.0, 30.0, 40.0, 50.0)
	await stop(m)
	w._on_mill_submit()
	ok(w.money == money0 + 150, "Vergütung gezahlt")
	ok(w.mill_job_index == 1, "Nächster Fräsauftrag")
	ok(m.untouched, "Neues Rohteil nach der Abgabe")

	# Fräsauftrag 3: Nut mit Ø10
	reset(w)
	m.select_tool(2)
	m.rpm_set = 1000.0
	go(m, -10.0, 30.0, -6.0, 50.0)
	await spin_up(m)
	go(m, 110.0, 30.0, -6.0, 1.0)
	ok(not m.estop, "Nut ohne Kollision")
	res = m.evaluate(MillJobs.get_job(2))
	ok(float(res["score"]) >= 0.999, "Nut in Toleranz: " + str(res["lines"]))
	go(m, 110.0, 30.0, 40.0, 50.0)

	# Fräsauftrag 5: Bohrbild
	reset(w)
	m.select_tool(6)
	m.rpm_set = 630.0
	await spin_up(m)
	for x in [25.0, 75.0]:
		go(m, x, 30.0, 5.0, 50.0)
		go(m, x, 30.0, -25.0, 1.0)
		go(m, x, 30.0, 5.0, 50.0)
	ok(not m.estop, "Bohren ohne Kollision")
	res = m.evaluate(MillJobs.get_job(4))
	ok(float(res["score"]) >= 0.999, "Bohrbild in Toleranz: " + str(res["lines"]))

	# Falsche Maße werden erkannt
	reset(w)
	m.select_tool(2)
	go(m, -10.0, 30.0, -3.0, 50.0)
	await spin_up(m)
	go(m, 110.0, 30.0, -3.0, 1.0)
	res = m.evaluate(MillJobs.get_job(2))
	ok(float(res["score"]) < 0.999, "Zu flache Nut fällt durch")
	go(m, 110.0, 30.0, 40.0, 50.0)

	# Kollisionen und Fehlbedienung
	reset(w)
	m.select_tool(2)
	go(m, -10.0, 30.0, -3.0, 50.0)
	go(m, 20.0, 30.0, -3.0, 1.0)
	ok(m.estop, "Spindel steht: Kollision im Material")

	reset(w)
	m.select_tool(6)
	await spin_up(m)
	go(m, 50.0, 30.0, 5.0, 50.0)
	go(m, 50.0, 30.0, -5.0, 1.0)
	ok(not m.estop, "Bohrer taucht ein")
	go(m, 55.0, 30.0, -5.0, 1.0)
	ok(m.estop, "Bohrer bricht bei seitlicher Bewegung")

	reset(w)
	m.select_tool(5)
	await spin_up(m)
	go(m, 50.0, 30.0, 5.0, 50.0)
	go(m, 50.0, 30.0, -1.0, 1.0)
	ok(m.estop, "Messerkopf kann nicht eintauchen")

	reset(w)
	m.select_tool(5)
	go(m, -40.0, 30.0, -8.0, 50.0)
	await spin_up(m)
	go(m, 20.0, 30.0, -8.0, 1.0)
	ok(m.estop, "Messerkopf: Schnitttiefe zu groß")

	reset(w)
	m.select_tool(0)
	go(m, -10.0, 30.0, -2.0, 50.0)
	await spin_up(m)
	go(m, 20.0, 30.0, -2.0, 200.0)
	ok(m.estop, "Vorschub zu hoch bricht den Fräser")

	reset(w)
	m.select_tool(4)
	await spin_up(m)
	go(m, 50.0, -20.0, 5.0, 50.0)
	go(m, 50.0, -20.0, -20.0, 1.0)
	ok(m.estop, "Kollision mit der Schraubstockbacke")

	reset(w)
	m.select_tool(6)
	await spin_up(m)
	go(m, 50.0, 30.0, 5.0, 50.0)
	go(m, 50.0, 30.0, -39.0, 1.0)
	ok(not m.estop, "Bohrer kommt bis kurz vor die Unterlage")
	go(m, 50.0, 30.0, -41.0, 1.0)
	ok(m.estop, "Bohrer trifft die Unterlage")

	# Auto-Vorschub
	reset(w)
	m.select_tool(2)
	m.rpm_set = 1000.0
	m.feed_set = 250.0
	go(m, -10.0, 30.0, 5.0, 50.0)
	await spin_up(m)
	m.set_auto(0, 1)
	var x0: float = m.tool_x
	for i in 30:
		await physics_frame
	ok(m.tool_x > x0 + 1.0, "Auto-Vorschub bewegt X")
	m.set_auto(-1, 0)
	var x1: float = m.tool_x
	for i in 5:
		await physics_frame
	ok(absf(m.tool_x - x1) < 0.001, "Auto-Vorschub aus")

	# Speichern und Laden
	reset(w)
	m.select_tool(2)
	go(m, -10.0, 30.0, -6.0, 50.0)
	await spin_up(m)
	go(m, 40.0, 30.0, -6.0, 1.0)
	var state: Dictionary = JSON.parse_string(JSON.stringify(m.get_state()))
	print("Speichergröße Rohteil: ", str(state["data"]).length(), " Zeichen")
	var h: float = m.height_at(20.0, 30.0)
	await stop(m)
	reset(w)
	ok(absf(m.height_at(20.0, 30.0)) < 0.001, "Neues Rohteil ist unbearbeitet")
	m.set_state(state)
	ok(absf(m.height_at(20.0, 30.0) - h) < 0.001 and h < -5.0, "Höhenkarte wiederhergestellt")
	ok(m.tool_idx == 2 and absf(m.tool_x - 40.0) < 0.01, "Werkzeug und Position wiederhergestellt")
	ok(not m.untouched, "Bearbeitet-Status wiederhergestellt")

	# Draufsicht: zeigt die Höhenkarte, Marke verschwindet ein Werkzeug-Ø neben dem Rohteil
	await process_frame
	await process_frame
	ok(w.mill_hud._top.part.texture == m.height_texture(), "Draufsicht zeigt das aktuelle Rohteil")
	m.tool_x = 50.0
	m.tool_y = 30.0
	ok(m.tool_near_part(), "Marke über dem Rohteil sichtbar")
	m.tool_x = -9.0
	ok(m.tool_near_part(), "Marke bis ein Ø neben dem Rohteil sichtbar")
	m.tool_x = -11.0
	ok(not m.tool_near_part(), "Marke weg, sobald die Mitte mehr als ein Ø neben dem Rohteil steht")

	# Hebel: Sperre bei laufender Spindel, Tasten und HUD-Knöpfe verstellen nichts
	reset(w)
	m.rpm_set = 630.0
	m.feed_set = 100.0
	m.lever_step(0, 1)
	ok(m.rpm_set == 1000.0, "Drehzahl-Hebel eine Stufe hoch")
	m.lever_step(1, -1)
	ok(m.feed_set == 63.0, "Vorschub-Hebel eine Stufe runter")
	for i in 20:
		m.lever_step(0, 1)
	ok(m.rpm_set == 4000.0, "Hebel bleibt an der obersten Stufe")
	m.rpm_set = 630.0
	m.feed_set = 100.0
	m._sync_levers()
	await spin_up(m)
	m.lever_step(0, 1)
	m.lever_step(1, 1)
	ok(m.rpm_set == 630.0 and m.feed_set == 100.0, "Hebel bei laufender Spindel gesperrt")
	for a in ["rpm_up", "rpm_down", "feed_up", "feed_down"]:
		var e := InputEventAction.new()
		e.action = a
		e.pressed = true
		m._unhandled_input(e)
	ok(m.rpm_set == 630.0 and m.feed_set == 100.0, "Tasten verstellen nichts")
	var ck := InputEventAction.new()
	ck.action = "coolant"
	ck.pressed = true
	m._unhandled_input(ck)
	ok(m.coolant and m.spindle_on, "Kühlung lässt sich während der Bearbeitung einschalten")
	m._unhandled_input(ck)
	ok(not m.coolant, "Kühlung lässt sich während der Bearbeitung ausschalten")
	var sp := InputEventAction.new()
	sp.action = "spindle_toggle"
	sp.pressed = true
	var af := InputEventAction.new()
	af.action = "auto_feed"
	af.pressed = true
	m._unhandled_input(af)
	ok(m.auto_axis == 0, "Auto-Vorschub läuft per Taste an")
	m._unhandled_input(af)
	ok(m.auto_axis == -1, "Auto-Vorschub läuft per Taste aus")
	m._unhandled_input(sp)
	ok(not m.spindle_on, "Spindel per Taste aus")
	await stop(m)
	# Klick auf die Platte: Strahl auf die Hebelkulisse
	var plate: Node3D = m._lever_plate
	var above: Vector3 = plate.to_global(Vector3(MillModel.LEVER_X[0], m._knobs[0].position.y + 0.03, 0.0))
	var hit: Dictionary = m.lever_at(above + Vector3(0.5, 0, 0), Vector3(-1, 0, 0))
	ok(hit.get("lever", -1) == 0 and hit.get("up", false), "Klick über dem Griff = Stufe hoch")
	var below: Vector3 = plate.to_global(Vector3(MillModel.LEVER_X[1], m._knobs[1].position.y - 0.03, 0.0))
	hit = m.lever_at(below + Vector3(0.5, 0, 0), Vector3(-1, 0, 0))
	ok(hit.get("lever", -1) == 1 and not hit.get("up", true), "Klick unter dem Griff = Stufe runter")
	ok(m.lever_at(above + Vector3(-0.5, 0, 0), Vector3(1, 0, 0)).is_empty(), "Von hinten kein Hebel")
	var hud_text := []
	for b in w.mill_hud.find_children("*", "Button", true, false):
		hud_text.append(b.text)
	ok(not hud_text.has("Drehz. +") and not hud_text.has("Vorsch. +") and not hud_text.has("KSS"), "Keine HUD-Knöpfe für Drehzahl und Vorschub")
	ok(hud_text.has("Kühlung"), "Knopf für die Kühlung")
	for t in MillTools.TOOLS:
		for txt in hud_text:
			ok(not str(txt).contains(str(t["id"])), "Kein Werkzeug-Knopf %s" % t["id"])
	var kt := InputEventKey.new()
	kt.keycode = KEY_3
	kt.pressed = true
	var tool0: int = m.tool_idx
	m._unhandled_input(kt)
	ok(m.tool_idx == tool0, "Zifferntasten wechseln kein Werkzeug")
	ok(m._knobs.size() == 2, "Nur noch Hebel für Drehzahl und Vorschub")
	ok(not hud_text.has("Hebel"), "Kein Hebel-Knopf während der Bearbeitung")
	ok(hud_text.has("Vorschub +") and hud_text.has("Vorschub -"), "Knöpfe Vorschub + und -")
	var auto_btns := hud_text.filter(func(t): return str(t).begins_with("Auto "))
	ok(auto_btns.is_empty(), "Keine einzelnen Auto-Knöpfe mehr")
	# Klick auf die Hebel wirkt an der Maschine nicht
	var rpm0: float = m.rpm_set
	var cl := InputEventMouseButton.new()
	cl.button_index = MOUSE_BUTTON_LEFT
	cl.pressed = true
	cl.position = m.op_cam.unproject_position(MillModel.LEVER_POS)
	m._unhandled_input(cl)
	ok(m.rpm_set == rpm0, "Hebel an der Maschine nicht bedienbar")

	# Vorschub + und - gelten für die gewählte Achse
	reset(w)
	m.select_tool(2)
	m.rpm_set = 1000.0
	go(m, -10.0, 30.0, 40.0, 50.0)
	await spin_up(m)
	m.hw_axis = 1
	m.feed_selected(1)
	ok(m.auto_axis == 1 and m.auto_sign == 1, "Vorschub + auf Achse Y")
	m.feed_selected(-1)
	ok(m.auto_axis == 1 and m.auto_sign == -1, "Vorschub - auf Achse Y")
	m.feed_selected(-1)
	ok(m.auto_axis == -1, "Gleicher Knopf schaltet den Vorschub aus")
	m.hw_axis = 2
	m.feed_selected(1)
	var z0: float = m.tool_z
	for i in 20:
		await physics_frame
	ok(m.auto_axis == 2 and m.tool_z > z0, "Vorschub + auf Achse Z hebt den Kopf")
	m.set_auto(-1, 0)
	m.hw_axis = 0
	await stop(m)

	# Feste Schutzwand: keine Türen, Spindel läuft ohne Freigabe, Wand nur wenig über dem Tisch
	ok(not hud_text.has("Türen auf") and not hud_text.has("Türen zu") and not hud_text.has("Türen"), "Kein Türen-Knopf")
	ok(not InputMap.has_action("mill_door"), "Keine Türen-Taste")
	ok(MillModel.GUARD_TOP > MillModel.TABLE_Y and MillModel.GUARD_TOP - MillModel.TABLE_Y <= 0.15, "Schutzwand nur etwas höher als der Spanntisch")
	await spin_up(m)
	ok(m.spindle_on, "Spindel startet ohne Türfreigabe")
	await stop(m)

	# Wanne: Späne sammeln sich, sie liegen im Becken neben der Führung
	reset(w)
	m.select_tool(2)
	m.rpm_set = 1000.0
	go(m, -10.0, 30.0, -3.0, 50.0)
	await spin_up(m)
	var chips0: int = m.chips_in_tray
	for i in 60:
		m.move_tool(0.1, 0.0, 0.0, 3.0)
		await physics_frame
	ok(m.chips_in_tray > chips0, "Späne landen in der Wanne")
	var all_in := true
	for i in 500:
		var q: Vector3 = m.chip_position()
		if absf(q.x) >= MillModel.TRAY_X or absf(q.x) <= MillModel.PEDESTAL_X or q.z <= MillModel.TRAY_Z0 or q.z >= MillModel.TRAY_Z1 or q.y < MillModel.TRAY_FLOOR:
			all_in = false
	ok(all_in, "Späne liegen innerhalb der Wanne")
	await stop(m)
	ok(MillModel.TABLE_L * 0.5 < MillModel.TRAY_X and MillModel.TABLE_W * 0.5 + m.Y_TRAVEL * 0.0005 < MillModel.TRAY_Z1, "Tisch bleibt über der Wanne")

	# Maßstab: Arbeitsfläche in echten Millimetern
	var tbl: AABB = (m.table.get_child(0) as MeshInstance3D).get_aabb()
	ok(absf(tbl.size.x - 0.41) < 0.001 and absf(tbl.size.z - 0.21) < 0.001, "Tisch ist 410 x 210 mm groß")
	ok(w.lathe.Z_MAX == 900.0, "Drehlänge 900 mm")
	var l = w.lathe
	l.tool_z = l.Z_MAX
	l._sync_slides()
	await process_frame
	var ts_nodes: Array = l.get_children().filter(func(n): return n is Node3D and absf(n.position.x - 1.73) < 0.001)
	ok(ts_nodes.size() == 1, "Reitstock an seinem Platz")
	if ts_nodes.size() == 1:
		ok(mesh_bounds(l.carriage).end.x < mesh_bounds(ts_nodes[0]).position.x, "Schlitten erreicht bei voller Drehlänge den Reitstock nicht")
	ok(mesh_bounds(l).size.x < 3.2, "Drehmaschine passt zur Drehlänge")

	# Verlassen
	m.stop_operating()
	await process_frame
	ok(not m.operating and p.operating == null, "Bedienung beendet")
	ok(not w.mill_hud.visible and w.hud._cross.visible and w.hud._job_panel.visible, "HUD zurück")

	# Hebelfeld als eigene Station
	for i in 3:
		await physics_frame
	p.global_position = m.to_global(m.LEVER_STAND) + Vector3(0, 0.05, 0)
	p.yaw = PI / 2.0
	p.pitch = -0.5
	for i in 10:
		await physics_frame
	ok(p._focus != null and p._focus.get_prompt().contains("Hebelfeld"), "Hebelfeld lässt sich anvisieren")
	if p._focus:
		p._focus.interact(p)
	await process_frame
	ok(m.panel_open and not m.operating, "Hebelfeld bedienen, ohne die Maschine zu bedienen")
	ok(p.operating == m, "Spielfigur steht am Hebelfeld")
	ok(w.mill_hud.visible and w.mill_hud._lever_box.visible and not w.mill_hud._op_nodes[0].visible, "Nur die Hebel-Anzeige ist sichtbar")
	await process_frame
	var cl2 := InputEventMouseButton.new()
	cl2.button_index = MOUSE_BUTTON_LEFT
	cl2.pressed = true
	m.rpm_set = 630.0
	m._sync_levers()
	cl2.position = m.op_cam.unproject_position(m._lever_plate.to_global(Vector3(MillModel.LEVER_X[0], m._knobs[0].position.y + 0.05, 0)))
	m._unhandled_input(cl2)
	ok(m.rpm_set == 1000.0, "Klick im Hebelfeld stellt die Drehzahl eine Stufe hoch")
	cl2.position = m.op_cam.unproject_position(m._lever_plate.to_global(Vector3(MillModel.LEVER_X[0], m._knobs[0].position.y - 0.05, 0)))
	m._unhandled_input(cl2)
	ok(m.rpm_set == 630.0, "Klick unter den Griff stellt sie eine Stufe zurück")
	# Griff festhalten und über mehrere Stufen ziehen, er rastet auf der nächsten Stufe
	var knob_pos := func(y: float) -> Vector2: return m.op_cam.unproject_position(m._lever_plate.to_global(Vector3(MillModel.LEVER_X[0], y, 0)))
	var grab := InputEventMouseButton.new()
	grab.button_index = MOUSE_BUTTON_LEFT
	grab.pressed = true
	grab.position = knob_pos.call(m._knobs[0].position.y)
	m._unhandled_input(grab)
	ok(m._drag_lever == 0 and m.rpm_set == 630.0, "Griff festgehalten, Klick allein verstellt nichts")
	var mv := InputEventMouseMotion.new()
	mv.position = knob_pos.call(MillModel.lever_y(8, MillModel.RPM_STEPS.size()) + 0.004)
	m._unhandled_input(mv)
	ok(m.rpm_set == 2500.0, "Ziehen nach oben rastet auf 2500 /min")
	ok(absf(m._knobs[0].position.y - MillModel.lever_y(8, MillModel.RPM_STEPS.size())) < 0.0001, "Griff steht auf der Stufe")
	mv.position = knob_pos.call(-1.0)
	m._unhandled_input(mv)
	ok(m.rpm_set == 63.0, "Ziehen über das Ende bleibt auf der untersten Stufe")
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = mv.position
	m._unhandled_input(rel)
	ok(m._drag_lever == -1, "Loslassen beendet das Ziehen")
	mv.position = knob_pos.call(0.1)
	m._unhandled_input(mv)
	ok(m.rpm_set == 63.0, "Ohne gehaltene Taste bewegt sich der Griff nicht")
	var feed0: float = m.feed_set
	grab.position = m.op_cam.unproject_position(m._lever_plate.to_global(Vector3(MillModel.LEVER_X[1], m._knobs[1].position.y, 0)))
	m._unhandled_input(grab)
	ok(m._drag_lever == 1, "Vorschub-Griff lässt sich festhalten")
	mv.position = m.op_cam.unproject_position(m._lever_plate.to_global(Vector3(MillModel.LEVER_X[1], MillModel.lever_y(9, MillModel.FEED_STEPS.size()), 0)))
	m._unhandled_input(mv)
	ok(m.feed_set == 630.0 and feed0 != 630.0, "Vorschub-Griff ziehen rastet auf 630 mm/min")
	m._unhandled_input(rel)
	# Beim Ziehen gesperrt, solange die Spindel läuft
	m.spindle_speed = 500.0
	m._drag_lever = 0
	mv.position = knob_pos.call(0.1)
	m._unhandled_input(mv)
	ok(m.rpm_set == 63.0, "Ziehen bei laufender Spindel gesperrt")
	m._drag_lever = -1
	m.spindle_speed = 0.0
	var ik := InputEventAction.new()
	ik.action = "interact"
	ik.pressed = true
	m._unhandled_input(ik)
	await process_frame
	ok(not m.panel_open and p.operating == null, "Taste E verlässt das Hebelfeld")
	ok(not w.mill_hud.visible and w.hud._cross.visible, "HUD nach dem Hebelfeld zurück")
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
