extends SceneTree
## CNC-Fräsmaschine: Aufbau, Achsen, Tür, Ein/Aus, Magazin und Werkzeugwechsel, Bezugspunkt, NC-Kanal, MDI,
## echtes Beispielprogramm mit Auftragsprüfung, Speichern und Laden.
## Aufruf: Godot --headless --path . -s res://tools/tests/test_cnc_mill.gd
var checks := 0
var fails := 0
const FPS_MAX := 60000


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


func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


## Maschine direkt takten (ein Takt = 1/60 s), damit lange Läufe nicht in Echtzeit ablaufen müssen.
var cur = null
const DT := 1.0 / 60.0


func frames(n: int) -> void:
	for i in n:
		cur._physics_process(DT)


## Läuft, bis der Kanal nicht mehr läuft (oder max Bilder). Gibt die Bilder zurück.
func run_channel(m, max_frames := 20000) -> int:
	var n := 0
	while m.channel.state == "run" and n < max_frames:
		m._physics_process(DT)
		n += 1
	return n


func make_mill():
	var m = load("res://scripts/machine/cnc_mill.gd").new()
	root.add_child(m)
	return m


func ready_mill():
	var m = make_mill()
	await process_frame
	await process_frame
	m.power_on(true)
	return m


func mesh_count(n: Node) -> int:
	var c := 0
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		stack.append_array(x.get_children())
		if x is MeshInstance3D:
			c += 1
	return c


var t_start := 0


func _initialize() -> void:
	t_start = Time.get_ticks_msec()
	await process_frame
	var m = await ready_mill()
	cur = m
	if OS.has_environment("CNC_TEST_VERBOSE"):
		m.message.connect(func(t: String, _c: Color): print("   MSG: ", t))
	var fp := FakeP.new()
	root.add_child(fp)

	# ------------------------------------------------------------------ Aufbau
	ok(m.has_method("hand_click") and m.MACHINE_ID == "cnc_mill" and m.tool_family == "mill", "CncMill ist eine Mill mit eigener Kennung")
	ok(mesh_count(m) > 150, "Modell geladen (%d Meshes)" % mesh_count(m))
	for k in ["saddle", "table", "head", "spindle", "disk", "arm", "door"]:
		ok(m._mp.has(k) and m._mp[k] != null, "Modellteil " + k)
	ok(m.POCKETS == 24 and m.magazine.size() == 24, "24 Magazinplätze")
	ok(m.screen_vp != null and m.screen != null and m.screen_vp.size == Vector2i(m.SCREEN_UI * m.SCREEN_SCALE), "Bildschirm-Viewport")
	ok(m.spindle_empty and m.tool_t == 0, "neue Maschine: Spindel leer")
	ok(m.machine_title() == "CNC-Fräsmaschine", "Maschinentitel")
	ok(m.get_prompt().contains("CNC-Fräsmaschine"), "Hinweis nennt die Maschine ohne Layout-Eintrag")
	ok(not m.programs.is_empty() and m.prog_sel == 0, "Beispielprogramme vorhanden")
	ok(m.door_closed(), "Tür ist zu")
	ok(m.has_part and m.block_l == 100.0, "Rohteil eingespannt")

	# ------------------------------------------------------------------ Ein / Aus
	m.power_off()
	ok(not m.powered and not m.is_ready(), "aus")
	var x0: float = m.tool_x
	m.move_tool(10.0, 0.0, 0.0, 3.0)
	ok(m.tool_x == x0, "ohne Strom keine Bewegung")
	m.toggle_spindle()
	ok(not m.spindle_on, "ohne Strom keine Spindel")
	ok(not m.screen_vp.get_child(0).visible or not m.screen.visible, "Steuerung dunkel")
	m.power_on()
	ok(m.powered and not m.is_ready() and m.booting > 0.0, "Hochfahren läuft")
	await frames(int(m.BOOT_TIME * 60.0) + 10)
	ok(m.is_ready() and m.screen.visible, "nach dem Hochfahren bereit")
	m.power_off()
	m.power_on(true)
	ok(m.is_ready(), "sofort einschalten")

	# ------------------------------------------------------------------ Achsen und Modellknoten
	m.tool_x = m.block_l * 0.5
	m.tool_y = m.block_w * 0.5
	m.tool_z = 60.0
	m._sync_axes()
	var tx: float = m._mp["table"].position.x
	var sz: float = m._mp["saddle"].position.z
	var hy: float = m.head.position.y
	m.move_tool(10.0, 0.0, 0.0, 3.0)
	ok(is_equal_approx(m._mp["table"].position.x, tx - 0.01), "X fährt den Tisch")
	m.move_tool(0.0, 10.0, 0.0, 3.0)
	ok(is_equal_approx(m._mp["saddle"].position.z, sz + 0.01), "Y fährt den Schlitten")
	m.move_tool(0.0, 0.0, 20.0, 3.0)
	ok(is_equal_approx(m.head.position.y, hy + 0.02), "Z fährt den Kopf")
	m.move_tool(10000.0, 0.0, 0.0, 3.0)
	ok(is_equal_approx(m.tool_x, m.block_l * 0.5 + m.x_travel * 0.5), "X-Grenze")
	m.move_tool(0.0, -10000.0, 0.0, 3.0)
	ok(is_equal_approx(m.tool_y, m.block_w * 0.5 - m.y_travel * 0.5), "Y-Grenze")
	m.move_tool(0.0, 0.0, 10000.0, 3.0)
	ok(is_equal_approx(m.tool_z, m.z_max), "Z-Grenze")
	ok(m.x_travel >= 500.0 and m.y_travel >= 240.0 and m.z_max >= 300.0, "Verfahrwege größer als an der konventionellen Fräse")
	ok(absf(m.top_y - (m._mp["table"].position.y + m.OFS.y + 0.11)) < 0.001, "Rohteil sitzt auf dem Tisch des Modells")
	m.tool_x = m.block_l * 0.5
	m.tool_y = m.block_w * 0.5
	m.tool_z = 60.0
	m._sync_axes()
	ok(absf(m._mp["table"].position.x - (m._mp["table"].position.x)) < 0.0001, "Ausgangslage")

	# ------------------------------------------------------------------ Bezugspunkt
	m.tool_x = 50.0
	m.tool_y = 30.0
	m.tool_z = 10.0
	m.set_datum(0, 0.0)
	m.set_datum(2, 0.0)
	ok(m.datum.x == 50.0 and m.datum.z == 10.0 and m.datum.y == 0.0, "set_datum")
	ok(m.pos().is_equal_approx(Vector3(0, 30, 0)), "pos() bezogen auf den Bezugspunkt")
	ok(m.machine_pos().is_equal_approx(Vector3(50, 30, 10)), "machine_pos()")
	var lim: Dictionary = m.limits()
	ok(is_equal_approx(lim["min"].x, 50.0 - 250.0 - 50.0), "Verfahrgrenzen in Programmkoordinaten")
	m.set_datum(0, 50.0)
	m.set_datum(2, 10.0)
	ok(m.datum.x == 0.0 and m.datum.z == 0.0, "Bezugspunkt zurücksetzen")
	m.new_workpiece(100.0, 60.0, 40.0)
	ok(m.datum == Vector3.ZERO, "neues Teil setzt den Bezugspunkt zurück")
	m.tool_z = 60.0

	# ------------------------------------------------------------------ Tür
	ok(m.set_door(false), "Tür öffnen")
	await frames(100)
	ok(m.door_open_ok() and not m.door_closed(), "Tür offen")
	ok(m._mp["door"].position.x < -0.9, "Türblatt ist aufgeschoben")
	ok(m.clamp_blocked() == "", "bei offener Tür darf gespannt werden")
	m.toggle_spindle()
	ok(not m.spindle_on, "Spindel bei offener Tür gesperrt")
	ok(m.set_door(true), "Tür schließen")
	await frames(100)
	ok(m.door_closed() and absf(m._mp["door"].position.x) < 0.001, "Tür zu")
	ok(m.clamp_blocked() != "", "bei geschlossener Tür kein Umspannen")
	ok(m.reclamp(10.0, false) != "", "reclamp gesperrt bei geschlossener Tür")
	m.select_tool(m.tool_index("F10"), true)
	m.toggle_spindle()
	ok(m.spindle_on, "Spindel ein bei geschlossener Tür")
	ok(not m.set_door(false), "Tür bleibt bei laufender Spindel zu")
	m.toggle_spindle()
	await frames(60)
	ok(m.set_door(false), "Tür geht nach Spindelstopp auf")
	await frames(100)
	m.set_door(true)
	await frames(100)
	m.clear_spindle()

	# ------------------------------------------------------------------ Strahltest: Kollisionskörper und Griff
	await physics_frame
	var space := root.world_3d.direct_space_state
	var hb: Vector3 = m._handle_body.position
	var q := PhysicsRayQueryParameters3D.create(m.to_global(hb + Vector3(0, 0, 1.0)), m.to_global(hb))
	var hit := space.intersect_ray(q)
	ok(not hit.is_empty() and hit["collider"].has_meta("interact") and hit["collider"].get_meta("interact").handle, "Strahl trifft den Türgriff")
	q = PhysicsRayQueryParameters3D.create(m.to_global(Vector3(0.25, 1.5, 3.0)), m.to_global(Vector3(0.25, 1.5, 0.0)))
	hit = space.intersect_ray(q)
	ok(not hit.is_empty() and hit["collider"].get_meta("interact") != null, "geschlossene Tür ist ein Ziel")
	q = PhysicsRayQueryParameters3D.create(m.to_global(Vector3(-1.9, 0.6, 0.0)), m.to_global(Vector3(-1.3, 0.6, 0.0)))
	hit = space.intersect_ray(q)
	ok(not hit.is_empty(), "Späneförderer ist fest")
	m.set_door(false, true)
	await physics_frame
	q = PhysicsRayQueryParameters3D.create(m.to_global(Vector3(0.1, 1.9, 2.5)), m.to_global(Vector3(0.0, 1.9, -0.8)))
	hit = space.intersect_ray(q)
	ok(not hit.is_empty() and hit["collider"].get_meta("interact") == m, "bei offener Tür trifft der Blick die Maschine hinter der Spindel")
	m.set_door(true, true)
	# Vom Standplatz am Pult aus: grüner Knopf, Not-Halt und Monitor sind je ein eigenes Ziel
	var eye: Vector3 = m.STAND_PULT + Vector3(0, 1.6, 0)
	for zn in ["power", "estop", "pult"]:
		var zc := Vector3.ZERO
		for z in m._zones:
			if str(z["name"]) == zn:
				zc = (z["box"] as AABB).get_center()
		if zn == "pult":
			zc = m._screen_mi.global_position
		else:
			zc = m.to_global(zc)
		var from: Vector3 = m.to_global(eye)
		q = PhysicsRayQueryParameters3D.create(from, zc + (zc - from).normalized() * 0.3)
		hit = space.intersect_ray(q)
		var tgt = hit["collider"].get_meta("interact") if not hit.is_empty() and hit["collider"].has_meta("interact") else null
		ok(tgt != null and "kind" in tgt and str(tgt.kind) == zn, "Blick vom Pult-Standplatz trifft %s (%s)" % [zn, str(tgt.kind) if tgt != null and "kind" in tgt else str(tgt)])

	# ------------------------------------------------------------------ Magazin, Bestücken von Hand
	ok(m.magazine_set(1, "F10") and m.magazine_set(2, "MK63") and m.magazine_set(3, "B10"), "Magazin bestücken")
	ok(not m.magazine_set(4, "F10"), "Werkzeug nur einmal im Magazin")
	ok(m.pocket_of("MK63") == 2 and m.pocket_of("F6") == 0 and m.free_pocket() == 4, "Platzbuchhaltung")
	ok(m.has_tool("B10") and not m.has_tool("F6"), "has_tool zählt das Magazin mit")
	ok(m.magazine_tools().size() == 3 and str(m.magazine_tools()[2]["id"]) == "MK63", "magazine_tools")
	fp.held = {"machine": "cnc_mill", "id": "F6", "name": "Schaftfräser Ø6"}
	m.hand_click(fp)
	ok(m.spindle_empty and fp.held.has("id"), "bei geschlossener Tür nicht von Hand wechseln")
	m.set_door(false, true)
	m.hand_click(fp)
	ok(not m.spindle_empty and m.tool_t == 4 and m.magazine[3] == "F6" and fp.held.is_empty(), "von Hand eingesetzt: erster freier Platz")
	fp.held = {"machine": "cnc_mill", "id": "B10", "name": "x"}
	m.hand_click(fp)
	ok(m.tool_t == 4 and m.magazine[3] == "F6" and not fp.held.is_empty(), "Werkzeug aus dem Magazin lässt sich nicht doppelt einsetzen")
	fp.held = {"machine": "cnc_mill", "id": "F8", "name": "x"}
	m.hand_click(fp)
	ok(m.tool_t == 4 and m.magazine[3] == "F8" and str(fp.held.get("id", "")) == "F6", "Austausch belegt den Platz der aktiven T-Nummer")
	fp.clear_held()
	m.hand_click(fp)
	ok(m.spindle_empty and m.tool_t == 0 and m.magazine[3] == "" and str(fp.held.get("id", "")) == "F8", "Herausnehmen gibt den Platz frei")
	fp.clear_held()
	ok(m.pocket_of("F8") == 0 and m.free_pocket() == 4, "Platz ist wieder frei")
	var stock := ToolStore.new()
	for id in ["F10", "MK63", "B10"]:
		stock.add(id)
	m.tool_stock = stock
	ok(m.owns_tool("F10"), "Bestand der Maschine")
	m.tool_stock = null

	# ------------------------------------------------------------------ Werkzeugwechsel
	ok(m.tool_change(9) != "", "nicht bestückter Platz wird abgelehnt")
	ok(m.tool_change(30) != "", "Platz außerhalb des Magazins")
	m.set_door(false, true)
	ok(m.tool_change(1) != "" and not m.changing, "Wechsel bei offener Tür verweigert")
	m.set_door(true, true)
	m.select_tool(m.tool_index("F10"), true)
	ok(m.tool_t == 1, "F10 steckt als T1")
	m.toggle_spindle()
	await frames(20)
	ok(m.tool_change(2) != "" and not m.changing, "Wechsel bei laufender Spindel verweigert")
	m.toggle_spindle()
	await frames(60)
	ok(m.spindle_speed < 5.0, "Spindel steht")
	var err: String = m.tool_change(2)
	ok(err == "" and m.changing, "Wechsel startet")
	ok(not m.set_door(false), "Tür bleibt beim Wechsel zu")
	var n := 0
	var tool_mid := false
	while m.changing and n < 2000:
		m._physics_process(DT)
		n += 1
		if m._tc.has("phase") and m._tc["phase"] == "f" and m.spindle_empty:
			tool_mid = true
	ok(not m.changing and n > 180 and n < 700, "Wechsel dauert 3 bis 11 s (%d Bilder)" % n)
	ok(tool_mid, "Spindel ist mitten im Wechsel leer")
	ok(m.tool_t == 2 and str(m.tool()["id"]) == "MK63" and not m.spindle_empty, "MK63 steckt als T2")
	ok(m.magazine[0] == "F10" and m.magazine[1] == "MK63" and m.magazine[2] == "B10", "Magazin bleibt bestückt")
	ok(m._tool_node != null and m._tool_node.get_parent() == m.spindle, "Werkzeugmodell in der Spindel")
	ok(not m._pocket_nodes[1].visible and m._pocket_nodes[0].visible, "Anzeige im Magazin: T2 fehlt, T1 liegt wieder da")
	ok(absf(m.head.position.y - (m.NOSE_CHG - m.OFS.y)) < 0.002, "Kopf steht in Wechselhöhe")
	ok(m.z_max <= 380.0 and m.z_max > 100.0, "Z-Grenze folgt der Werkzeuglänge (%.0f)" % m.z_max)
	m.tool_z = 60.0
	m._sync_axes()
	# Platzbuchhaltung bei Bruch: tool_lost räumt den Platz
	var lost := [0]
	m.tool_lost.connect(func(_p, _n): lost[0] += 1)
	m.tool_stock = ToolStore.new()
	m.tool_stock.add("MK63")
	m._tool_broken("Test")
	ok(m.spindle_empty and m.tool_t == 0 and m.magazine[1] == "" and lost[0] == 1, "Bruch räumt den Platz")
	m.estop = false
	m.tool_stock = null
	m.magazine_set(2, "MK63")
	# Wechsel auf ein leeres Spindelwerkzeug und zurück ablegen
	ok(m.tool_change(3) == "" , "Wechsel bei leerer Spindel")
	await run_channel_free(m)
	ok(m.tool_t == 3 and str(m.tool()["id"]) == "B10", "B10 als T3")
	ok(m.tool_change(0) == "", "Ablegen")
	await run_channel_free(m)
	ok(m.spindle_empty and m.tool_t == 0 and m.magazine[2] == "B10", "T0: Spindel leer, Werkzeug im Magazin")
	ok(m.tool_change(0) == "", "T0 bei leerer Spindel ist nichts zu tun")
	# Not-Halt mitten im Wechsel
	ok(m.tool_change(1) == "", "Wechsel für den Not-Halt-Test")
	await frames(120)
	m.estop = true
	await frames(5)
	ok(not m.changing and m.tool_t == 1 and not m.spindle_empty, "Not-Halt beendet den Wechsel in stimmigem Zustand")
	m.toggle_estop()
	ok(not m.estop, "Not-Halt quittiert")

	# ------------------------------------------------------------------ NC-Kanal mit handgebauter Schrittliste
	m.new_workpiece(100.0, 60.0, 40.0)
	m.set_material("AW-6082")
	m.tool_x = 50.0
	m.tool_y = 30.0
	m.tool_z = 60.0
	m._sync_axes()
	var ops := [
		{"op": "blk", "n": 1}, {"op": "tool", "t": 1, "s": 3000.0}, {"op": "spindle", "on": true, "ccw": false},
		{"op": "blk", "n": 2}, {"op": "mv", "to": Vector3(10, 30, 5), "f": 0.0, "rapid": true},
		{"op": "blk", "n": 3}, {"op": "mv", "to": Vector3(10, 30, -1), "f": 300.0, "rapid": false},
		{"op": "blk", "n": 4}, {"op": "mv", "to": Vector3(90, 30, -1), "f": 600.0, "rapid": false},
		{"op": "blk", "n": 5}, {"op": "mv", "to": Vector3(90, 30, 20), "f": 0.0, "rapid": true},
		{"op": "dwell", "t": 0.1}, {"op": "spindle", "on": false, "ccw": false}, {"op": "end", "n": 5},
	]
	m.set_door(false, true)
	ok(not m.channel.start_ops(ops, "T1"), "Start bei offener Tür verweigert")
	m.set_door(true, true)
	m.estop = true
	ok(not m.channel.start_ops(ops, "T1"), "Start bei Not-Halt verweigert")
	m.estop = false
	m.power_off()
	ok(not m.channel.start_ops(ops, "T1"), "Start ohne Strom verweigert")
	m.power_on(true)
	m.magazine_clear(m.tool_t)
	ok(m.channel.start_ops(ops, "T1") and m.channel.state == "run" and m.channel.busy(), "Start")
	await frames(30)
	ok(m.channel.line >= 1 and m.channel.op_i > 0, "Satzzeiger läuft (Satz %d)" % m.channel.line)
	ok(m.channel.state_text() == "läuft", "Zustandstext")
	var ticks := await run_channel(m)
	ok(m.channel.state == "done", "Programm beendet (%s %s)" % [m.channel.state, m.channel.alarm])
	print("Lauf 1: ", ticks, " Bilder, ", Time.get_ticks_msec() - t_start, " ms seit Start")
	ok(absf(m.height_at(50.0, 30.0) + 1.0) < 0.01, "Abtrag liegt an der erwarteten Stelle: %.2f" % m.height_at(50.0, 30.0))
	ok(absf(m.height_at(50.0, 50.0)) < 0.01 and absf(m.height_at(50.0, 10.0)) < 0.01, "daneben ist das Teil unberührt")
	ok(m.channel.run_time > 1.0 and not m.spindle_on, "Laufzeit, Spindel aus am Ende")
	ok(m.pos().is_equal_approx(Vector3(90, 30, 20)), "Endposition")
	m.channel.reset()
	ok(m.channel.state == "idle" and m.channel.line == -1, "Reset")

	# Halt bei Tür auf, Fortsetzen
	m.new_workpiece(100.0, 60.0, 40.0)
	m.select_tool(m.tool_index("F10"), true)
	m.tool_x = 50.0
	m.tool_y = 30.0
	m.tool_z = 60.0
	m._sync_axes()
	var ops2 := [
		{"op": "blk", "n": 1}, {"op": "spindle", "on": true, "ccw": false},
		{"op": "mv", "to": Vector3(10, 30, 5), "f": 0.0, "rapid": true},
		{"op": "mv", "to": Vector3(10, 30, -1), "f": 300.0, "rapid": false},
		{"op": "blk", "n": 2}, {"op": "mv", "to": Vector3(90, 30, -1), "f": 600.0, "rapid": false},
		{"op": "blk", "n": 3}, {"op": "mv", "to": Vector3(90, 30, 20), "f": 0.0, "rapid": true},
		{"op": "spindle", "on": false, "ccw": false}, {"op": "end", "n": 3},
	]
	m.rpm_set = 3000.0
	ok(m.channel.start_ops(ops2, "T2"), "zweiter Lauf")
	while m.channel.state == "run" and m.pos().x < 40.0 and m.pos().z > -0.9:
		m._physics_process(DT)
	await frames(30)
	ok(m.channel.state == "run", "läuft im Material")
	ok(not m.set_door(false), "Tür bleibt bei laufendem Programm zu")
	m.channel.nc_stop()
	ok(m.channel.state == "hold" and m.channel.hold_reason == "NC-Stopp", "NC-Stopp hält an")
	var px: float = m.pos().x
	await frames(30)
	ok(is_equal_approx(m.pos().x, px), "Vorschub steht im Halt")
	ok(m.spindle_on, "Spindel läuft nach NC-Stopp weiter")
	m.toggle_spindle()
	await frames(200)
	ok(m.set_door(false), "im Halt darf die Tür auf, wenn die Spindel steht")
	await frames(100)
	ok(not m.channel.nc_start([]), "NC-Start bei offener Tür verweigert")
	ok(m.channel.state == "hold", "bleibt im Halt")
	# Im Halt bei offener Tür: kein Teilwechsel, solange das Programm noch ansteht (umspannen bleibt möglich)
	ok(m.door_open_ok() and m.clamp_blocked() != "", "Teilwechsel im NC-Halt gesperrt: %s" % m.clamp_blocked())
	ok(m._clamp_gate() == "", "Umspannen im NC-Halt bleibt erlaubt")
	var asked := [0]
	var count_ask := func() -> void: asked[0] += 1
	m.submit_requested.connect(count_ask)
	m.new_part_requested.connect(count_ask)
	m.request_submit()
	m.request_new_part()
	ok(asked[0] == 0, "Abgeben und neues Rohteil im NC-Halt verweigert")
	m.submit_requested.disconnect(count_ask)
	m.new_part_requested.disconnect(count_ask)
	var d_before: Vector3 = m.datum
	m.set_datum(0, 5.0)
	ok(m.datum == d_before, "Bezugspunkt bleibt bei anstehendem Programm stehen")
	m.set_door(true)
	await frames(100)
	ok(m.channel.nc_start([]) and m.channel.state == "run", "Fortsetzen mit NC-Start")
	await frames(120)
	ok(m.spindle_on, "Spindel läuft nach dem Fortsetzen wieder")
	# Override 0 hält den Vorschub an
	await frames(5)
	m.channel.feed_ovr = 0.0
	await frames(10)
	var pz: Vector3 = m.pos()
	await frames(40)
	ok(m.pos().is_equal_approx(pz), "Override 0 hält den Vorschub an")
	m.channel.feed_ovr = 2.0
	ok(m.channel.feed_ovr == 1.5, "Override auf 1,5 begrenzt")
	m.channel.feed_ovr = 1.0
	m.channel.rapid_ovr = 3.0
	ok(m.channel.rapid_ovr == 1.0, "Eilgang-Override auf 1,0 begrenzt")
	# Tür öffnet sich erzwungen (Sicherheitsnetz im Kanal)
	await frames(10)
	if m.channel.state == "run":
		m._door_goal = 0.0
		await frames(5)
		ok(m.channel.state == "hold" and not m.spindle_on, "erzwungen offene Tür hält an")
		m._door_goal = 1.0
		m.door_t = 1.0
		m._place_door()
		m.channel.nc_start([])
	ticks = await run_channel(m, 6000)
	ok(m.channel.state == "done", "zweiter Lauf beendet (%s)" % m.channel.alarm)
	m.channel.reset()

	# Einzelsatz
	m.tool_x = 50.0
	m.tool_y = 30.0
	m.tool_z = 60.0
	m._sync_axes()
	var ops3 := [
		{"op": "blk", "n": 1}, {"op": "mv", "to": Vector3(0, 30, 60), "f": 0.0, "rapid": true},
		{"op": "blk", "n": 2}, {"op": "mv", "to": Vector3(0, 30, 80), "f": 0.0, "rapid": true},
		{"op": "blk", "n": 3}, {"op": "mv", "to": Vector3(0, 30, 100), "f": 0.0, "rapid": true},
		{"op": "end", "n": 3},
	]
	m.channel.single_block = true
	ok(m.channel.start_ops(ops3, "SB"), "Einzelsatz starten")
	await frames(60)
	ok(m.channel.state == "hold" and m.channel.hold_reason == "Einzelsatz" and m.channel.line == 1, "Einzelsatz hält nach Satz 1")
	ok(is_equal_approx(m.pos().z, 60.0) and m.pos().x < 1.0, "Satz 1 ist abgearbeitet, Satz 2 noch nicht")
	m.channel.nc_start([])
	await frames(60)
	ok(m.channel.state == "hold" and m.channel.line == 2 and is_equal_approx(m.pos().z, 80.0), "dann hält er nach Satz 2")
	m.channel.single_block = false
	m.channel.nc_start([])
	ticks = await run_channel(m)
	ok(m.channel.state == "done" and is_equal_approx(m.pos().z, 100.0), "ohne Einzelsatz läuft er durch")
	m.channel.reset()
	var ops_stop := [{"op": "blk", "n": 1}, {"op": "stop"}, {"op": "blk", "n": 2}, {"op": "dwell", "t": 0.05}, {"op": "end", "n": 2}]
	m.channel.start_ops(ops_stop, "STOP")
	await frames(10)
	ok(m.channel.state == "hold" and m.channel.hold_reason == "Programmierter Halt", "programmierter Halt")
	m.channel.nc_start([])
	await run_channel(m)
	ok(m.channel.state == "done", "nach dem Halt weiter bis zum Ende")
	m.channel.reset()

	# Not-Halt und blockierte Bewegung
	m.tool_x = 50.0
	m.tool_y = 30.0
	m.tool_z = 60.0
	m._sync_axes()
	var ops_long := [{"op": "blk", "n": 1}, {"op": "mv", "to": Vector3(0, 30, 300), "f": 0.0, "rapid": true}, {"op": "end", "n": 1}]
	m.channel.start_ops(ops_long, "LANG")
	await frames(10)
	m.toggle_estop()
	await frames(3)
	ok(m.channel.state == "error" and m.channel.alarm.contains("Not-Halt"), "Not-Halt -> Alarm")
	m.toggle_estop()
	m.channel.reset()
	ok(m.channel.state == "idle" and m.channel.alarm == "", "Reset löscht den Alarm")
	var ops_far := [{"op": "blk", "n": 1}, {"op": "mv", "to": Vector3(5000, 30, 60), "f": 0.0, "rapid": true}, {"op": "end", "n": 1}]
	m.channel.start_ops(ops_far, "ZU WEIT")
	await run_channel(m)
	ok(m.channel.state == "error" and m.channel.alarm.contains("blockiert"), "Verfahrgrenze -> Alarm (%s)" % m.channel.alarm)
	m.channel.reset()
	# Kollision im Schraubstock
	m.tool_x = 50.0
	m.tool_y = -3.0
	m.tool_z = 5.0
	m._sync_axes()
	var ops_crash := [{"op": "blk", "n": 1}, {"op": "mv", "to": Vector3(50, -3, -30), "f": 0.0, "rapid": true}, {"op": "end", "n": 1}]
	m.channel.start_ops(ops_crash, "CRASH")
	await run_channel(m)
	ok(m.channel.state == "error" and m.estop, "Kollision -> Alarm und Not-Halt (%s)" % m.channel.alarm)
	m.toggle_estop()
	m.channel.reset()

	# ------------------------------------------------------------------ MDI
	m.new_workpiece(100.0, 60.0, 40.0)
	m.tool_z = 60.0
	m._sync_axes()
	ok(m.mdi("L Z+50 R0 FMAX"), "MDI starten")
	await run_channel(m)
	ok(m.channel.state == "done" and is_equal_approx(m.pos().z, 50.0), "MDI fährt Z+50")
	m.channel.reset()
	ok(m.mdi("TOOL CALL 2 Z S2500"), "MDI Werkzeugwechsel")
	await run_channel(m)
	ok(m.channel.state == "done" and m.tool_t == 2 and is_equal_approx(m.rpm_set, 2500.0), "TOOL CALL 2 wechselt auf T2 und setzt S2500 (T%d S%d)" % [m.tool_t, int(m.rpm_set)])
	m.channel.reset()
	ok(not m.mdi("KAUDERWELSCH 12"), "MDI: Fehler wird abgelehnt")

	# ------------------------------------------------------------------ echtes Beispielprogramm, Auftrag prüfen
	var jobs_ok := 0
	for pair in [["PLANEN", 0], ["TASCHE", 3], ["BOHRBILD", 4]]:
		var job: Dictionary = MillJobs.get_job(int(pair[1]))
		m.set_material(str(job["material"]))
		var sz_job: Array = job["size"]
		m.new_workpiece(float(sz_job[0]), float(sz_job[1]), float(sz_job[2]))
		m.tool_z = 100.0
		m._sync_axes()
		for i in m.programs.size():
			if str(m.programs[i]["name"]) == pair[0]:
				m.prog_sel = i
		m.magazine.fill("")
		m.clear_spindle()
		m.magazine_set(1, "MK63")
		m.magazine_set(2, "F12")
		m.magazine_set(3, "B10")
		ok(m.nc_start(), "Beispielprogramm %s startet" % pair[0])
		var t0 := Time.get_ticks_msec()
		await run_channel(m, FPS_MAX)
		print("   %s: %d ms seit Start" % [pair[0], Time.get_ticks_msec() - t_start])
		ok(m.channel.state == "done", "%s läuft durch (%s)" % [pair[0], m.channel.alarm])
		var res: Dictionary = m.evaluate(job)
		ok(res["ok"] == res["total"], "%s: Auftrag bestanden (%d von %d)" % [pair[0], res["ok"], res["total"]])
		if res["ok"] != res["total"]:
			for l in res["lines"]:
				print("   ", l)
			var bad := []
			for j in m.ny:
				for i in m.nx:
					var xx: float = (i + 0.5) * m.CELL
					var yy: float = (j + 0.5) * m.CELL
					if xx > 26.0 and xx < 74.0 and yy > 16.0 and yy < 44.0 and m.data[(j * m.nx + i) * 2] > -9.8:
						bad.append(Vector2(xx, yy))
			print("   unberührt: ", bad.size(), " Zellen, erste ", bad.slice(0, 5), " letzte ", bad.slice(-3))
		m.channel.reset()
		jobs_ok += 1
	ok(jobs_ok == 3, "drei Aufträge geprüft")
	# Tasche mit F12: die Ecken behalten Radius 6 (kein Rundfräsen im Auftrag möglich), der Boden ist sauber
	m.set_material("AW-6082")
	m.new_workpiece(100.0, 60.0, 40.0)
	m.tool_z = 100.0
	m._sync_axes()
	m.prog_sel = 1
	m.magazine.fill("")
	m.clear_spindle()
	m.magazine_set(1, "MK63")
	m.magazine_set(2, "F12")
	ok(m.nc_start(), "Beispielprogramm TASCHE startet")
	await run_channel(m, FPS_MAX)
	ok(m.channel.state == "done" and absf(m.height_at(50.0, 30.0) + 10.0) < 0.01 and absf(m.height_at(35.0, 22.0) + 10.0) < 0.01, "TASCHE: Boden bei Z-10, Rand angefahren")
	ok(absf(m.height_at(20.0, 30.0)) < 0.01 and absf(m.height_at(50.0, 10.0)) < 0.01, "TASCHE: Umgebung unberührt")
	m.channel.reset()

	# ------------------------------------------------------------------ Programme verwalten
	m.save_program("NEU", ["BEGIN PGM NEU MM", "END PGM NEU MM"])
	ok(not m.program("NEU").is_empty() and m.program("NEU")["lines"].size() == 2, "Programm speichern")
	m.save_program("NEU", ["BEGIN PGM NEU MM", "M30", "END PGM NEU MM"])
	ok(m.program("NEU")["lines"].size() == 3, "Programm überschreiben")
	m.prog_sel = m.programs.size() - 1
	m.delete_program("NEU")
	ok(m.program("NEU").is_empty() and m.prog_sel == m.programs.size() - 1, "Programm löschen")

	# ------------------------------------------------------------------ Speichern und Laden
	m.new_workpiece(100.0, 60.0, 40.0)
	m.magazine.fill("")
	m.clear_spindle()
	m.magazine_set(1, "F10")
	m.magazine_set(5, "B10")
	m.select_tool(m.tool_index("F6"), true)
	m.tool_x = 40.0
	m.tool_y = 20.0
	m.tool_z = 33.0
	m.set_datum(0, 0.0)
	m.set_datum(2, 3.0)
	m.save_program("SAVE", ["BEGIN PGM SAVE MM", "END PGM SAVE MM"])
	m.prog_sel = 1
	await frames(200)
	m.set_door(false, true)
	ok(m.door_open_ok(), "Tür vor dem Speichern offen")
	var st: Dictionary = m.get_state()
	var m2 = make_mill()
	await process_frame
	await process_frame
	cur = m2
	m2.power_on(true)
	m2.set_door(true, true)
	m2.magazine_set(9, "F4")
	m2.set_door(true, true)
	m2.channel.start_ops([{"op": "blk", "n": 1}, {"op": "dwell", "t": 5.0}, {"op": "end", "n": 1}], "X")
	ok(m2.channel.busy(), "zweite Maschine läuft")
	m2.set_state(st)
	ok(m2.magazine == m.magazine, "Magazin geladen")
	ok(m2.tool_t == m.tool_t and m2.tool_t > 0 and str(m2.tool()["id"]) == "F6", "T und Spindelwerkzeug geladen (T%d)" % m2.tool_t)
	ok(m2.datum.is_equal_approx(m.datum), "Bezugspunkt geladen")
	ok(m2.programs.size() == m.programs.size() and m2.prog_sel == 1 and not m2.program("SAVE").is_empty(), "Programme geladen")
	ok(m2.door_open_ok(), "Tür offen geladen")
	ok(m2.powered and m2.is_ready(), "Strom geladen")
	ok(m2.channel.state == "idle", "nach dem Laden läuft kein Programm")
	cur = m
	ok(is_equal_approx(m2.tool_x, 40.0) and is_equal_approx(m2.tool_z, 33.0), "Position geladen")
	ok(m2._pocket_nodes[0] != null and m2._pocket_nodes[0].visible and m2._pocket_nodes[4].visible, "Magazinanzeige nach dem Laden")
	m2.queue_free()

	# ------------------------------------------------------------------ Bedienung: Ansichten
	m.set_door(true, true)
	m.interact(fp)
	ok(m.operating and fp.operating == m, "Bedienung startet")
	await process_frame
	ok(not m.op_cam.get_cull_mask_value(3), "im Arbeitsraum blendet sich die Kabine aus")
	m.toggle_panel_view()
	ok(m.in_panel_view(), "Pultansicht")
	for i in 90:
		await process_frame
	ok(m.op_cam.get_cull_mask_value(3), "am Pult ist die Kabine sichtbar")
	var spx: Vector2 = m.screen_pixel(get_root_center())
	ok(spx.x >= 0.0 and spx.x <= m.screen_vp.size.x, "Bildschirmmitte liegt in der Bildmitte (%s)" % spx)
	if spx.x < 0.0:
		print("   cam ", m.op_cam.global_position, " dir ", -m.op_cam.global_basis.z, " screen ", m._screen_mi.global_position, " normal ", m._screen_mi.global_basis.z, " root ", root.size, " cam_target ", m.cam_target, " want ", m.screen_center())
		var inv: Transform3D = m._screen_mi.global_transform.affine_inverse()
		var o: Vector3 = inv * m.op_cam.project_ray_origin(get_root_center())
		var d: Vector3 = inv.basis * m.op_cam.project_ray_normal(get_root_center())
		print("   o ", o, " d ", d, " size ", m._screen_size, " inside ", m._screen_mi.is_inside_tree(), " cur ", m.op_cam.is_current())
	m.toggle_panel_view()
	ok(not m.in_panel_view(), "zurück zur Arbeitsansicht")
	m.stop_operating()
	ok(not m.operating and fp.operating == null, "Bedienung endet")
	m.interact(fp, true)
	ok(m.in_panel_view(), "[E] am Pult öffnet die Pultansicht")
	m.stop_operating()
	ok(not m.in_panel_view(), "Pultansicht endet mit der Bedienung")

	# ------------------------------------------------------------------ Tippen im Eingabefeld der Steuerung
	# Tasten wie X (Not-Halt), E (verlassen), N, Enter (abgeben), O (Tür), Leertaste (Spindel) dürfen beim
	# Schreiben eines Satzes nichts an der Maschine auslösen.
	m.channel.reset()
	m.estop = false
	m.set_door(true, true)
	m.interact(fp, true)
	press(KEY_X)
	ok(m.estop, "ohne Eingabefeld löst X den Not-Halt aus (Tasten kommen im Test an)")
	press(KEY_X)
	ok(not m.estop, "X quittiert wieder")
	var le := LineEdit.new()
	m.screen_vp.add_child(le)
	le.grab_focus()
	await process_frame
	ok(m.typing(), "Eingabefeld der Steuerung hat den Fokus")
	var typed := [0]
	var count_typed := func() -> void: typed[0] += 1
	m.submit_requested.connect(count_typed)
	m.new_part_requested.connect(count_typed)
	for key in [KEY_X, KEY_E, KEY_N, KEY_ENTER, KEY_O, KEY_SPACE, KEY_C]:
		press(key)
	ok(not m.estop, "X im Eingabefeld löst keinen Not-Halt aus")
	ok(m.operating and fp.operating == m, "E im Eingabefeld verlässt die Maschine nicht")
	ok(typed[0] == 0, "N und Enter im Eingabefeld fordern kein Teil an und geben keins ab")
	ok(m.door_closed(), "O im Eingabefeld öffnet die Tür nicht")
	ok(not m.spindle_on and not m.coolant, "Leertaste und C im Eingabefeld schalten nichts")
	ok(le.text.to_lower().contains("x"), "die Taste landet im Eingabefeld (%s)" % le.text)
	m.submit_requested.disconnect(count_typed)
	m.new_part_requested.disconnect(count_typed)
	m.stop_operating()
	ok(not m.typing(), "beim Verlassen gibt das Eingabefeld den Fokus ab")
	le.queue_free()

	print("CHECKS ", checks, " FAILS ", fails)
	quit(1 if fails > 0 else 0)


func get_root_center() -> Vector2:
	return root.get_visible_rect().size * 0.5


## Taste drücken und loslassen, so wie sie vom Fenster käme.
func press(key: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.key_label = key
		if key >= KEY_A and key <= KEY_Z:
			ev.unicode = int(key) + 32      # Kleinbuchstabe
		ev.pressed = down
		root.push_input(ev)


## Wechsel abwarten (ohne Kanal).
func run_channel_free(m) -> void:
	var n := 0
	while m.changing and n < 2000:
		m._physics_process(DT)
		n += 1
