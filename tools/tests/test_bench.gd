extends SceneTree
## Werkbänke: Werkzeuge stecken nur in den Halterungen, nehmen, von Hand einsetzen, zurückstecken, Laden.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
## Spielfigur auf den Punkt ausrichten und den Sichtstrahl aktualisieren.
func aim(p, from: Vector3, target: Vector3) -> void:
	p.global_position = from
	p.velocity = Vector3.ZERO
	var eye: Vector3 = from + Vector3(0, 1.62, 0)
	var d: Vector3 = target - eye
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	for i in 6:
		await physics_frame
func get_root_drops() -> Array:
	return get_nodes_in_group("dropped_item")
## Linksklick auf das anvisierte Ziel. Headless lässt sich die Maus nicht fangen, deshalb direkt.
func click(p) -> void:
	p.click_focus()
func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var m = w.mill
	var l = w.lathe
	# Werkbänke werden sonst am PC gekauft und mit dem Baumenü aufgestellt
	w.spawn_bench("lathe", Vector2(0.6, 0.35), 2)
	w.spawn_bench("mill", Vector2(6.85, -0.95), 2)
	await process_frame
	var mb = w.mill_bench
	var lb = w.lathe_bench
	mb.refresh()
	lb.refresh()

	# Alles steckt in den Halterungen, was nicht an der Maschine ist
	ok(mb.holders.size() == 36 and lb.holders.size() == 36, "36 Halterungen")
	ok(mb.holder_of("F6") < 0, "F6 steckt in der Spindel und nicht in einer Halterung")
	ok(mb.holder_of("F10") >= 0, "F10 steckt in einer Halterung")
	ok(lb.holder_of("T1") < 0 and lb.holder_of("T3") < 0, "T1 und T3 stecken im Halter")
	ok(lb.holder_of("T5") >= 0, "T5 steckt in einer Halterung")
	for id in ["F25", "B25", "MK125", "MK32", "F3"]:
		var i: int = mb.holder_of(id)
		ok(i >= 0 and mb.holders[i].model != null, "%s ist zu sehen" % id)
		if i >= 0:
			var box: AABB = Build.bounds(mb.holders[i].model)
			ok(box.position.y < mb.TOP_Y - 0.01, "%s steckt unter der Platte" % id)
	# Auf der Platte liegt nichts und steht nichts
	for c in mb.find_children("*", "Label3D", true, false):
		ok(false, "Keine Beschriftung auf der Werkbank: " + c.text)

	# Fräsmaschine: Werkzeug aus der Halterung nehmen
	var stand: Vector3 = Vector3(6.85, 0.05, -2.0)
	var f10: int = mb.holder_of("F10")
	await aim(p, stand, mb.to_global(mb.holders[f10].at + Vector3(0, 0, 0.1)))
	ok(p._focus == mb.holders[f10], "Halterung lässt sich anvisieren")
	ok(p._prompt.contains("nehmen"), "Hinweis zum Nehmen: " + p._prompt)
	click(p)
	ok(p.held.get("id", "") == "F10", "Linksklick nimmt F10 in die Hand")
	ok(p._hand.get_child_count() == 1, "Werkzeug ist in der Hand sichtbar")
	ok(w.hud._held.text.contains("Schaftfräser Ø10"), "HUD zeigt das Werkzeug in der Hand")
	mb.refresh()
	ok(mb.holder_of("F10") < 0, "Die Halterung ist leer")

	# An der Spindel einsetzen
	var from_op: Vector3 = m.to_global(Vector3(0, 0, 0.85)) + Vector3(0, 0.05, 0)
	var tip: Vector3 = m.to_global(Vector3(0, 1.06 + m.tool_z * 0.001 + 0.05, 0))
	await aim(p, from_op, tip)
	ok(p._focus == m.tool_mount, "Spindel lässt sich anvisieren")
	ok(p._prompt.contains("einsetzen"), "Hinweis zum Einsetzen: " + p._prompt)
	m.spindle_on = true
	m.spindle_speed = 500.0
	click(p)
	ok(m.tool()["id"] == "F6" and p.held.get("id", "") == "F10", "Kein Wechsel bei laufender Spindel")
	m.spindle_on = false
	m.spindle_speed = 0.0
	click(p)
	ok(m.tool()["id"] == "F10", "F10 sitzt in der Spindel")
	ok(p.held.get("id", "") == "F6", "F6 kommt in die Hand")
	mb.refresh()
	ok(mb.holder_of("F10") < 0 and mb.holder_of("F6") < 0, "Beide stecken nicht in einer Halterung")

	# Frei wählbar: in eine bestimmte Halterung stecken
	var free: int = mb.free_holder()
	ok(free >= 0, "Es ist eine Halterung frei")
	mb.holder_click(free, p)
	ok(p.held.is_empty() and mb.machine.tool_stock.holder_id(free) == "F6", "F6 steckt in der gewählten Halterung")
	mb.refresh()
	ok(mb.holders[free].model != null, "Modell in der Halterung")
	ok(w.hud._held.text == "", "HUD zeigt freie Hand")

	# Klick auf die Bank: nächste freie Halterung
	await aim(p, from_op, tip)
	click(p)
	ok(m.spindle_empty and p.held.get("id", "") == "F10", "Freie Hand nimmt das Werkzeug aus der Spindel")
	ok(mb.body_prompt().contains("nächste freie"), "Hinweis auf die Bank: " + mb.body_prompt())
	mb.body_click(p)
	ok(p.held.is_empty() and mb.holder_of("F10") >= 0, "Bank steckt F10 in eine freie Halterung")

	# Fremdes Werkzeug passt nicht
	p.set_held(m, "F10")
	ok(lb.body_prompt().contains("gehört nicht"), "Fräser gehört nicht auf die Dreh-Werkbank: " + lb.body_prompt())
	lb.body_click(p)
	ok(p.held.get("id", "") == "F10", "Fräser bleibt in der Hand")
	p.clear_held()

	# Drehmaschine: nehmen und in freien Platz einspannen
	l.tool_z = 300.0
	l.tool_x = 100.0
	l._sync_slides()
	ok(l.holder == ["T1", "", "T3", ""] and l.active_slot == 0, "Grundbestückung")
	lb.holder_click(lb.holder_of("T5"), p)
	ok(p.held.get("id", "") == "T5", "T5 in der Hand")
	ok(p._hand.get_child_count() >= 1 and Build.bounds(p._hand).size.length() > 0.02, "T5 sichtbar in der Hand")
	var lathe_stand: Vector3 = l.to_global(Vector3(0.25, 0, 1.05)) + Vector3(0, 0.05, 0)
	await aim(p, lathe_stand, l._post_center())
	ok(p._focus == l.tool_mount, "Halterkopf lässt sich anvisieren")
	ok(p._prompt.contains("Platz 2"), "Hinweis auf freien Platz: " + p._prompt)
	click(p)
	ok(l.holder[1] == "T5" and p.held.is_empty(), "T5 in Platz 2 eingespannt")
	ok(l.active_slot == 0, "Einspannen schwenkt nicht ein")
	lb.refresh()
	ok(lb.holder_of("T5") < 0, "T5 fehlt in den Halterungen")

	# Freie Hand nimmt ein nicht eingeschwenktes Werkzeug heraus
	await aim(p, lathe_stand, l._post_center())
	ok(p._prompt.contains("T5") and p._prompt.contains("nehmen"), "Hinweis zum Herausnehmen: " + p._prompt)
	click(p)
	ok(l.holder[1] == "" and p.held.get("id", "") == "T5", "T5 wieder in der Hand")
	# Alle Plätze belegt: Tausch mit dem eingeschwenkten
	ok(l.mount_tool(1, "T4") and l.mount_tool(3, "T7"), "Alle Plätze belegt")
	await aim(p, lathe_stand, l._post_center())
	ok(p._prompt.contains("kommt in die Hand"), "Hinweis auf Tausch: " + p._prompt)
	click(p)
	ok(l.holder[0] == "T5" and p.held.get("id", "") == "T1" and str(l.tool()["id"]) == "T5", "T5 gegen T1 getauscht")
	l.spindle_speed = 500.0
	l.spindle_on = true
	click(p)
	ok(l.holder[0] == "T5" and p.held.get("id", "") == "T1", "Kein Tausch bei laufender Spindel")
	l.spindle_on = false
	l.spindle_speed = 0.0

	# Speichern und Laden mit Werkzeug in der Hand
	var st: Dictionary = JSON.parse_string(JSON.stringify(p.get_state()))
	ok(st["held"]["id"] == "T1" and st["held"]["machine"] == "lathe", "Hand wird gespeichert")
	p.clear_held()
	ok(p.held.is_empty(), "Hand geleert")
	w._apply_pending({"player": st, "mill": m.get_state(), "lathe": l.get_state(), "name": "T"})
	ok(p.held.get("id", "") == "T1" and p._hand.get_child_count() >= 1, "Hand wiederhergestellt")
	ok(l.holder[0] == "T5", "Halter wiederhergestellt")
	p.clear_held()
	await process_frame

	# Hand ist beim Bedienen unsichtbar, danach wieder da
	p.set_held(m, "F16")
	m.interact(p)
	ok(not p._hand.visible, "Hand beim Bedienen ausgeblendet")
	m.stop_operating()
	ok(p._hand.visible, "Hand danach wieder sichtbar")
	p.clear_held()

	# Drehmaschine: Werkzeuge liegen auf der Platte
	lb.refresh()
	var t5 := -1
	for h in lb.holders:
		var hid: String = l.tool_stock.holder_id(h.index)
		if hid != "" and not l.has_tool(hid):
			t5 = h.index
			break
	var tid: String = l.tool_stock.holder_id(t5) if t5 >= 0 else ""
	ok(lb.on_top and not mb.on_top, "Nur die Drehmaschine legt auf die Platte")
	ok(t5 >= 0 and lb.holders[t5].model != null, "Ein Drehwerkzeug liegt auf der Werkbank")
	if t5 >= 0:
		var tb: AABB = Build.bounds(lb.holders[t5].model)
		ok(tb.position.y >= lb.TOP_Y - 0.001, "%s liegt auf der Platte, nicht darunter" % tid)
		var lstand: Vector3 = lb.to_global(Vector3(lb.holders[t5].at.x, 0, 0.75))
		lstand.y = 0.05
		await aim(p, lstand, lb.to_global(lb.holders[t5].at + Vector3(0, 0.035, 0)))
		ok(p._focus == lb.holders[t5], "Platz auf der Platte lässt sich anvisieren")
		click(p)
		ok(p.held.get("id", "") == tid, "%s von der Werkbank genommen" % tid)

	# Fallen lassen: Werkzeug
	var drop_at: Vector3 = Vector3(3.0, 0.05, 3.0)
	await aim(p, drop_at, drop_at + Vector3(0, 0.5, -3))
	var dt = p.drop()
	ok(dt != null and p.hands_free(), "Werkzeug fallen gelassen")
	for i in 900:
		await physics_frame
		if i > 30 and dt != null and dt.resting:
			break
	ok(dt != null and dt.resting and Build.bounds(dt).position.y < 0.03, "Werkzeug liegt am Boden")
	lb.refresh()
	ok(lb.holder_of(tid) < 0, "Werkbank holt das liegende Werkzeug nicht zurück")
	var other: int = lb.holder_of(tid)
	ok(other < 0 or lb.holder_prompt(other).contains("liegt schon"), "Zweites Stück wird nicht genommen")
	var saved_drop: Dictionary = JSON.parse_string(JSON.stringify(dt.get_state())) if dt != null else {}
	if dt != null:
		await aim(p, drop_at, dt.global_position)
		ok(p._focus == dt, "Liegendes Werkzeug lässt sich anvisieren")
		click(p)
		ok(p.held.get("id", "") == tid and (not is_instance_valid(dt) or dt.is_queued_for_deletion()), "Werkzeug wieder aufgehoben")
	p.clear_held()
	await process_frame

	# Fallen lassen: Stange in voller Länge, aufheben, Speichern
	var bar := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 2000.0}
	p.set_carry(bar)
	await aim(p, drop_at, drop_at + Vector3(0, 0.5, -3))
	var db = p.drop()
	ok(db != null and p.carry.is_empty(), "Stange fallen gelassen")
	for i in 900:
		await physics_frame
		if i > 30 and db.resting:
			break
	var bb: AABB = Build.bounds(db)
	ok(db.resting and (bb.size.x > 1.9 or bb.size.z > 1.9), "Stange liegt in voller Länge")
	ok(absf(db.global_position.y - 0.03) < 0.006, "Stange liegt auf dem Boden, nicht darin")
	var gs: Array = get_root_drops()
	ok(gs.size() == 1, "Ein Gegenstand liegt herum")
	await aim(p, drop_at, db.global_position)
	click(p)
	ok(str(p.carry.get("kind", "")) == "round" and float(p.carry["l"]) == 2000.0, "Stange wieder aufgehoben")
	p.clear_carry()
	await process_frame

	# Laden: liegendes Werkzeug ist wieder da
	w._apply_pending({"player": p.get_state(), "mill": m.get_state(), "lathe": l.get_state(), "name": "T", "dropped": [saved_drop]})
	await process_frame
	gs = get_root_drops()
	ok(gs.size() == 1 and gs[0].is_tool(), "Liegendes Werkzeug geladen")
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
