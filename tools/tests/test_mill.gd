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
	root.get_node("GameState").pending = {"unlock_all": true}
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
	# Der Blick trifft die Maschine oder ihre Werkzeugaufnahme, beide bedienen sie
	ok(p._focus == m or p._focus == m.tool_mount, "Fräsmaschine lässt sich anvisieren")
	m.interact(p)
	await process_frame
	ok(m.operating and p.operating == m, "Bedienung startet")
	ok(w.mill_hud.visible and not w.hud._cross.visible, "Fräs-HUD an, Fadenkreuz aus")
	ok(not w.hud._job_panel.visible, "Drehauftrag ausgeblendet")
	# Konventionell: nur Achsen, alles andere hinter den Alt-Tasten, nirgends die Kasse
	var mh = w.mill_hud
	ok(mh._dro_panel.visible and not mh._details.is_visible_in_tree(), "Fräs-HUD zeigt im Normalfall nur die Achsen")
	ok(mh._top.is_visible_in_tree(), "Draufsicht bleibt sichtbar")
	ok(mh._chip.visible and not mh._overlay.visible, "Unten rechts nur der Hinweis")
	var alt := InputEventKey.new()
	alt.keycode = KEY_ALT
	alt.location = KEY_LOCATION_LEFT
	alt.pressed = true
	mh._input(alt)
	await process_frame
	ok(mh._details.is_visible_in_tree() and mh._job.text != "", "Links Alt zeigt Werte und Auftrag")
	var mill_labels := []
	for lb in mh.find_children("*", "Label", true, false):
		mill_labels.append(lb.text)
	ok(not " ".join(PackedStringArray(mill_labels)).contains("Werkstattkasse"), "Keine Kasse im Fräs-HUD")
	alt.pressed = false
	mh._input(alt)
	ok(not mh._details.visible, "Links Alt loslassen klappt zu")
	var ralt := InputEventKey.new()
	ralt.keycode = KEY_ALT
	ralt.location = KEY_LOCATION_RIGHT
	ralt.pressed = true
	mh._input(ralt)
	ok(mh._overlay.visible and not mh._chip.visible, "Rechts Alt öffnet die Übersicht")
	ok(mh._overlay.tabs.get_tab_count() == 6 and mh._overlay.tabs.get_tab_title(5) == "Bedienknöpfe", "Fünf Tastenlisten und die Bedienknöpfe")
	ok(mh._overlay.tabs.get_tab_title(0) == "Verfahren", "Erster Tab Verfahren")
	mh._input(ralt)
	ok(not mh._overlay.visible and mh._chip.visible, "Rechts Alt schließt sie wieder")

	# Alle Werkzeuge lassen sich einwechseln
	for i in MillTools.TOOLS.size():
		m.select_tool(i)
		await process_frame
		ok(m.tool_idx == i and m._tool_node != null, "Werkzeug %d eingewechselt" % i)
		ok(absf(m.to_local(m._tool_node.global_position).y - (1.06 + m.tool_z * 0.001)) < 0.0001, "Schneide von Werkzeug %d auf angezeigter Z-Höhe" % i)
	ok(m.head.position.y > 1.0, "Fräskopf steht über dem Tisch")

	# Wechsel gesperrt bei laufender Spindel
	m.select_tool(0)
	await spin_up(m)
	m.select_tool(3)
	ok(m.tool_idx == 0, "Kein Wechsel bei laufender Spindel")
	await stop(m)

	# Fräsauftrag 1: Planfräsen mit dem Messerkopf
	# Neues Spiel startet leer, das Rohteil zu diesem Auftrag einspannen
	w._mill_new_workpiece()
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
	ok(not w.accepted.has("mill:0"), "Fräsauftrag erledigt")
	ok(w.company.skills.xp == 150, "Erfahrung für den Auftrag")
	ok(not m.has_part, "Schraubstock ist nach der Abgabe leer")
	w.accept_job("mill:1")
	w.select_job("mill:1")
	ok(w.mill_job_index == 1, "Nächster Fräsauftrag nach dem Annehmen")

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

	# Drehknöpfe und Stufen: Rasten wie auf der Skala, Sperre bei laufender Spindel
	reset(w)
	m.rpm_set = 630.0
	m.feed_set = 100.0
	m._sync_panel()
	ok(m.dial_stage(0) == 0 and m.dial_stage(1) == 0, "Grundstellung ist Stufe I")
	m.dial_step(0, 1)
	ok(m.rpm_set == 1000.0, "Drehzahl-Knopf eine Raste hoch")
	m.dial_step(1, -1)
	ok(m.feed_set == 63.0, "Vorschub-Knopf eine Raste runter")
	m.dial_step(0, 1)
	ok(m.rpm_set == 40.0, "Knopf dreht ohne Anschlag von 1000 auf 40 /min weiter")
	m.dial_step(0, -1)
	ok(m.rpm_set == 1000.0, "Und rückwärts von 40 auf 1000 /min")
	m.stage_set(0, 1)
	ok(m.rpm_set == 2000.0 and m.dial_stage(0) == 1, "Taste II: 1000 wird 2000 /min")
	m.stage_set(0, 0)
	ok(m.rpm_set == 1000.0 and m.dial_stage(0) == 0, "Taste I: wieder 1000 /min")
	m.stage_set(1, 1)
	ok(m.feed_set == 125.0, "Taste II am Vorschub: 63 wird 125 mm/min")
	ok(m.dial_index(1) == 4, "Die Stufe lässt die Raste stehen")
	m.dial_step(1, 1)
	ok(m.feed_set == 200.0 and m.dial_stage(1) == 1, "Drehen bleibt in Stufe II")
	m.stage_set(1, 0)
	for k in 2:
		var vals: Array = MillModel.RPM_DIAL if k == 0 else MillModel.FEED_DIAL
		ok(vals[0].size() == vals[1].size(), "Beide Stufen haben gleich viele Rasten")
		for v in vals[0]:
			ok(not vals[1].has(v), "Wert %d kommt nur in einer Stufe vor" % v)
	var lab: Array = m._dials[0]["labels"]
	ok(lab[0].size() == 8 and lab[1].size() == 8, "Jede Stufe hat acht eigene Werte")
	var pairs := false
	for st in 2:
		for l in lab[st]:
			pairs = pairs or not str(l.text).is_valid_int()
	ok(not pairs, "Skala zeigt Einzelwerte statt Von-bis-Angaben")
	ok(lab[0][7].text == "1000" and lab[1][7].text == "2000", "Blauer Ring Stufe I, schwarzer Ring Stufe II")
	ok(absf(MillModel.dial_angle(8) - TAU) < 0.001, "Rasten verteilen sich auf die vollen 360°")
	ok(MillModel.RPM_DIAL[0].has(250) and MillModel.RPM_DIAL[1].has(2000) and MillModel.FEED_DIAL[0].has(10) and MillModel.FEED_DIAL[1].has(500), "Werte wie auf dem Bild")
	# Knopf zeigt auf die Raste, Taste der aktiven Stufe ist eingedrückt
	m.rpm_set = 40.0
	m._sync_panel()
	ok(absf(m._dials[0]["knob"].rotation.z) < 0.001, "Kleinster Wert steht oben")
	ok(lab[0][0].modulate == m.LABEL_PICKED and lab[1][0].modulate == m.LABEL_DIM, "Gewählter Wert hervorgehoben, andere Stufe gedimmt")
	m.rpm_set = 2000.0
	m._sync_panel()
	ok(absf(m._dials[0]["knob"].rotation.z + MillModel.dial_angle(7)) < 0.001, "Größter Wert steht eine Raste vor dem kleinsten")
	ok(lab[1][7].modulate == m.LABEL_PICKED and lab[0][7].modulate == m.LABEL_DIM, "Hervorhebung wechselt mit der Stufe")
	ok(m._dials[0]["stages"][1].position.z < 0.0 and m._dials[0]["stages"][0].position.z == 0.0, "Aktive Taste ist eingedrückt")
	# Griffhebel ist vorhanden und reicht über den Knopf hinaus
	ok(Build.bounds(m._dials[0]["knob"]).size.length() > MillModel.HANDLE_R, "Griffhebel am Drehknopf")
	# Alter Spielstand mit Wert außerhalb der Skala rastet ein
	m.rpm_set = 4000.0
	m.feed_set = 1000.0
	m._sync_panel()
	ok(m.rpm_set == 2000.0 and m.feed_set == 500.0, "Alte Werte rasten auf die Skala ein")
	m.rpm_set = 630.0
	m.feed_set = 100.0
	m._sync_panel()
	await spin_up(m)
	m.dial_step(0, 1)
	m.dial_step(1, 1)
	m.stage_set(0, 1)
	m.stage_set(1, 1)
	ok(m.rpm_set == 630.0 and m.feed_set == 100.0, "Knöpfe und Stufen bei laufender Spindel gesperrt")
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
	# Sichtstrahl auf das Bedienfeld
	var plate: Node3D = m._panel_plate
	var ray_to := func(q: Vector2) -> Dictionary:
		var at: Vector3 = plate.to_global(Vector3(q.x, q.y, 0.0))
		return m.panel_hit(at + Vector3(0.5, 0, 0), Vector3(-1, 0, 0))
	m.rpm_set = 630.0
	m.feed_set = 100.0
	m._sync_panel()
	var cy0: float = MillModel.DIAL_Y[0]
	var cy1: float = MillModel.DIAL_Y[1]
	var hit: Dictionary = ray_to.call(Vector2(MillModel.STAGE_X[1], cy0 + MillModel.STAGE_DY))
	ok(hit.get("dial", -1) == 0 and hit.get("stage", -1) == 1, "Taste II der Drehzahl getroffen")
	hit = ray_to.call(Vector2(MillModel.STAGE_X[0], cy1 + MillModel.STAGE_DY))
	ok(hit.get("dial", -1) == 1 and hit.get("stage", -1) == 0, "Taste I des Vorschubs getroffen")
	var cur0: float = MillModel.dial_angle(m.dial_index(0))
	var grip0: float = MillModel.handle_angle(m.dial_index(0))
	hit = ray_to.call(Vector2(sin(grip0), cos(grip0)) * MillModel.HANDLE_R + Vector2(0, cy0))
	ok(hit.get("dial", -1) == 0 and hit.get("grab", false), "Griffkugel lässt sich greifen")
	hit = ray_to.call(Vector2(sin(cur0 + 0.7), cos(cur0 + 0.7)) * MillModel.DIAL_R_BLACK + Vector2(0, cy0))
	ok(hit.get("dial", -1) == 0 and not hit.get("grab", true) and hit.get("dir", 0) == 1, "Klick im Uhrzeigersinn neben den Griff")
	hit = ray_to.call(Vector2(sin(cur0 - 0.7), cos(cur0 - 0.7)) * MillModel.DIAL_R_BLACK + Vector2(0, cy0))
	ok(hit.get("dir", 0) == -1, "Klick gegen den Uhrzeigersinn neben den Griff")
	ok(ray_to.call(Vector2(0.115, 0.0)).is_empty(), "Daneben trifft nichts")
	var back_at: Vector3 = plate.to_global(Vector3(0, cy0, 0))
	ok(m.panel_hit(back_at + Vector3(-0.5, 0, 0), Vector3(1, 0, 0)).is_empty(), "Von hinten kein Treffer")
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
	ok(m._dials.size() == 2, "Drehknöpfe für Drehzahl und Vorschub")
	ok(not hud_text.has("Hebel"), "Kein Hebel-Knopf während der Bearbeitung")
	ok(hud_text.has("Vorschub +") and hud_text.has("Vorschub -"), "Knöpfe Vorschub + und -")
	var auto_btns := hud_text.filter(func(t): return str(t).begins_with("Auto "))
	ok(auto_btns.is_empty(), "Keine einzelnen Auto-Knöpfe mehr")
	# Klick auf das Bedienfeld wirkt an der Maschine nicht
	var rpm0: float = m.rpm_set
	var cl := InputEventMouseButton.new()
	cl.button_index = MOUSE_BUTTON_LEFT
	cl.pressed = true
	cl.position = m.op_cam.unproject_position(MillModel.PANEL_POS)
	m._unhandled_input(cl)
	ok(m.rpm_set == rpm0, "Bedienfeld an der Maschine nicht bedienbar")

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
	ok(absf(tbl.size.x - 0.41) < 0.002 and absf(tbl.size.z - 0.21) < 0.002, "Tisch ist 410 x 210 mm groß")
	ok(w.lathe.Z_MAX == 900.0, "Drehlänge 900 mm")
	var l = w.lathe
	l.tool_z = l.Z_MAX
	l._sync_slides()
	await process_frame
	var ts_nodes: Array = l.get_children().filter(func(n): return n is Node3D and absf(n.position.x - 1.73) < 0.001)
	ok(ts_nodes.size() == 1, "Reitstock an seinem Platz")
	if ts_nodes.size() == 1:
		ok(mesh_bounds(l.carriage).end.x < mesh_bounds(ts_nodes[0]).position.x, "Schlitten erreicht bei voller Drehlänge den Reitstock nicht")
	# ohne das seitlich angewinkelte Bedienpult, das über den Spindelkasten hinausragt
	var lb := mesh_bounds(l)
	ok(lb.size.x < 3.2, "Drehmaschine passt zur Drehlänge")

	# Verlassen
	m.stop_operating()
	await process_frame
	ok(not m.operating and p.operating == null, "Bedienung beendet")
	ok(not w.mill_hud.visible and w.hud._cross.visible and w.hud._job_panel.visible, "HUD zurück")

	# Bedienfeld als eigene Station
	for i in 3:
		await physics_frame
	p.global_position = m.to_global(m.PANEL_STAND) + Vector3(0, 0.05, 0)
	p.yaw = PI / 2.0
	var panel_at: Vector3 = m.to_global(m.panel_pos)
	var eye_at: Vector3 = p.global_position + Vector3(0, 1.62, 0)
	p.pitch = atan2(panel_at.y - eye_at.y, Vector2(panel_at.x - eye_at.x, panel_at.z - eye_at.z).length())
	for i in 10:
		await physics_frame
	ok(p._focus != null and p._focus.get_prompt().contains("Bedienfeld"), "Bedienfeld lässt sich anvisieren")
	if p._focus:
		p._focus.interact(p)
	await process_frame
	ok(m.panel_open and not m.operating, "Bedienfeld benutzen, ohne die Maschine zu bedienen")
	ok(p.operating == m, "Spielfigur steht am Bedienfeld")
	ok(w.mill_hud.visible and w.mill_hud._lever_box.visible and not w.mill_hud._op_nodes[0].visible, "Nur die Anzeige des Bedienfelds ist sichtbar")
	await process_frame
	var screen_of := func(q: Vector2) -> Vector2: return m.op_cam.unproject_position(m._panel_plate.to_global(Vector3(q.x, q.y, 0)))
	var on_dial := func(k: int, a: float, r: float) -> Vector2: return screen_of.call(Vector2(sin(a), cos(a)) * r + Vector2(0, MillModel.DIAL_Y[k]))
	var cl2 := InputEventMouseButton.new()
	cl2.button_index = MOUSE_BUTTON_LEFT
	cl2.pressed = true
	m.rpm_set = 630.0
	m.feed_set = 100.0
	m._sync_panel()
	var ang: float = MillModel.dial_angle(m.dial_index(0))
	cl2.position = on_dial.call(0, ang + 0.8, MillModel.DIAL_R_BLACK)
	m._unhandled_input(cl2)
	ok(m.rpm_set == 1000.0, "Klick auf die Skala dreht die Drehzahl eine Raste weiter")
	ang = MillModel.dial_angle(m.dial_index(0))
	cl2.position = on_dial.call(0, ang - 0.8, MillModel.DIAL_R_BLACK)
	m._unhandled_input(cl2)
	ok(m.rpm_set == 630.0, "Klick gegen den Uhrzeigersinn dreht eine Raste zurück")
	# Tasten I und II von beiden Knöpfen per Klick
	cl2.position = screen_of.call(Vector2(MillModel.STAGE_X[1], MillModel.DIAL_Y[0] + MillModel.STAGE_DY))
	m._unhandled_input(cl2)
	ok(m.rpm_set == 1250.0, "Klick auf Taste II: 630 wird 1250 /min")
	cl2.position = screen_of.call(Vector2(MillModel.STAGE_X[0], MillModel.DIAL_Y[0] + MillModel.STAGE_DY))
	m._unhandled_input(cl2)
	ok(m.rpm_set == 630.0, "Klick auf Taste I: wieder 630 /min")
	cl2.position = screen_of.call(Vector2(MillModel.STAGE_X[1], MillModel.DIAL_Y[1] + MillModel.STAGE_DY))
	m._unhandled_input(cl2)
	ok(m.feed_set == 200.0 and m.rpm_set == 630.0, "Taste II des Vorschubs: 100 wird 200 mm/min, Drehzahl bleibt")
	cl2.position = screen_of.call(Vector2(MillModel.STAGE_X[0], MillModel.DIAL_Y[1] + MillModel.STAGE_DY))
	m._unhandled_input(cl2)
	ok(m.feed_set == 100.0, "Taste I des Vorschubs")
	# Griff festhalten und über mehrere Rasten ziehen
	var grab := InputEventMouseButton.new()
	grab.button_index = MOUSE_BUTTON_LEFT
	grab.pressed = true
	grab.position = on_dial.call(0, MillModel.handle_angle(m.dial_index(0)), MillModel.HANDLE_R)
	m._unhandled_input(grab)
	ok(m._drag_dial == 0 and m.rpm_set == 630.0, "Griff festgehalten, Klick allein verstellt nichts")
	var mv := InputEventMouseMotion.new()
	mv.position = on_dial.call(0, MillModel.handle_angle(1) + 0.05, MillModel.HANDLE_R)
	m._unhandled_input(mv)
	ok(m.rpm_set == 63.0, "Ziehen gegen den Uhrzeigersinn rastet auf 63 /min")
	ok(absf(m._dials[0]["knob"].rotation.z + MillModel.dial_angle(1)) < 0.001, "Griff steht auf der Raste")
	mv.position = on_dial.call(0, MillModel.handle_angle(0), MillModel.HANDLE_R)
	m._unhandled_input(mv)
	ok(m.rpm_set == 40.0, "Ziehen auf die erste Raste: 40 /min")
	mv.position = on_dial.call(0, MillModel.handle_angle(7), MillModel.HANDLE_R)
	m._unhandled_input(mv)
	ok(m.rpm_set == 1000.0, "Griff zieht ohne Anschlag direkt über oben hinweg auf 1000 /min")
	for pos in 8:
		mv.position = on_dial.call(0, MillModel.handle_angle(pos), MillModel.HANDLE_R)
		m._unhandled_input(mv)
		ok(m.dial_index(0) == pos, "Griff erreicht Raste %d" % pos)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = mv.position
	m._unhandled_input(rel)
	ok(m._drag_dial == -1, "Loslassen beendet das Ziehen")
	mv.position = on_dial.call(0, MillModel.handle_angle(4), MillModel.HANDLE_R)
	m._unhandled_input(mv)
	ok(m.rpm_set == 1000.0, "Ohne gehaltene Taste bewegt sich der Griff nicht")
	var feed0: float = m.feed_set
	grab.position = on_dial.call(1, MillModel.handle_angle(m.dial_index(1)), MillModel.HANDLE_R)
	m._unhandled_input(grab)
	ok(m._drag_dial == 1, "Griff am Vorschub-Knopf lässt sich festhalten")
	mv.position = on_dial.call(1, MillModel.handle_angle(7), MillModel.HANDLE_R)
	m._unhandled_input(mv)
	ok(m.feed_set == 250.0 and feed0 != 250.0, "Vorschub-Griff ziehen rastet auf 250 mm/min")
	m._unhandled_input(rel)
	# Beim Ziehen gesperrt, solange die Spindel läuft
	m.spindle_speed = 500.0
	m._drag_dial = 0
	mv.position = on_dial.call(0, MillModel.handle_angle(4), MillModel.HANDLE_R)
	m._unhandled_input(mv)
	ok(m.rpm_set == 1000.0, "Ziehen bei laufender Spindel gesperrt")
	m._drag_dial = -1
	m.spindle_speed = 0.0
	var ik := InputEventAction.new()
	ik.action = "interact"
	ik.pressed = true
	m._unhandled_input(ik)
	await process_frame
	ok(not m.panel_open and p.operating == null, "Taste E verlässt das Bedienfeld")
	ok(not w.mill_hud.visible and w.hud._cross.visible, "HUD nach dem Bedienfeld zurück")
	# Normreihen
	var ds := {"end_mill": [3, 4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 25], "drill": [3, 4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 25], "face_mill": [32, 40, 50, 63, 80, 100, 125]}
	for kind_n in ds:
		var have := []
		for t in MillTools.of_kind(kind_n):
			have.append(int(t["d"]))
		ok(have == ds[kind_n], "Normreihe %s: %s" % [kind_n, str(have)])
	var seen := {}
	for t in MillTools.TOOLS:
		ok(not seen.has(t["id"]), "Werkzeug-id einmalig: " + str(t["id"]))
		seen[t["id"]] = true
		ok(int(t["price"]) > 0 and float(t["ap_max"]) > 0.0 and float(t["fz_max"]) > 0.0, "Werkzeugdaten vollständig: " + str(t["id"]))
		ok(str(t["name"]).contains("Ø%d" % int(t["d"])), "Name nennt den Durchmesser: " + str(t["id"]))
		var asm: Node3D = MillTools.assembly(t)
		root.add_child(asm)
		var box: AABB = Build.bounds(asm)
		var cut_r: float = float(t["d"]) * 0.0005
		ok(absf(box.position.y) < 0.002, "Schneide bei y = 0: " + str(t["id"]))
		ok(box.size.x >= cut_r * 1.8, "Modell hat den Durchmesser: %s %.4f" % [t["id"], box.size.x])
		asm.free()
		var bm: Node3D = MillTools.bench_model(t)
		root.add_child(bm)
		var bb: AABB = Build.bounds(bm)
		ok(bb.size.length() > 0.01, "Werkbank-Modell hat Geometrie: " + str(t["id"]))
		bm.free()
	# Alle Größen schneiden mit passendem Durchmesser
	m.estop = false
	m.spindle_on = false
	m.spindle_speed = 0.0
	m.tool_z = 200.0
	for id in ["F25", "MK125", "B16", "F3"]:
		m.select_tool(m.tool_index(id), true)
		ok(m.tool()["id"] == id and absf(m.tool_radius() - float(MillTools.by_id(id)["d"]) * 0.5) < 0.001, "%s lässt sich einsetzen" % id)
		ok(float(m.cut_data()["fz_max"]) > 0.0, "%s hat Schnittdaten" % id)
	var dr3: Dictionary = Materials.mill_data("S235", MillTools.by_id("B3"), 1000.0)
	var dr16: Dictionary = Materials.mill_data("S235", MillTools.by_id("B16"), 1000.0)
	ok(float(dr3["fz_rec"]) < float(dr16["fz_rec"]), "Dünner Bohrer bekommt weniger Vorschub")
	ok(is_equal_approx(float(Materials.mill_data("S235", MillTools.by_id("B10"), 1000.0)["fz_rec"]), 0.15), "Ø10 bleibt beim Tabellenwert")
	m.select_tool(0, true)
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
