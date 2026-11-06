extends SceneTree
## Werkbänke: Werkzeug per Linksklick nehmen, von Hand einsetzen, zurücklegen, Speichern und Laden.
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
func slot_of(bench, id: String):
	for s in bench._slots:
		if s.tool_id == id:
			return s
	return null
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

	# An jedem Arbeitsplatz eine Werkbank mit allen Werkzeugen der Maschine
	ok(mb._slots.size() == MillTools.TOOLS.size(), "Fräs-Werkbank hat alle Werkzeuge")
	ok(lb._slots.size() == LatheTools.count(), "Dreh-Werkbank hat alle Werkzeuge")
	ok(not slot_of(mb, "F6").model.visible, "F6 steckt in der Spindel und fehlt auf der Bank")
	ok(slot_of(mb, "F10").model.visible, "F10 liegt auf der Bank")
	ok(not slot_of(lb, "T1").model.visible and not slot_of(lb, "T3").model.visible, "T1 und T3 stecken im Halter")
	# Drei Reihen, alles bleibt auf der Platte
	for s in mb._slots:
		var box: AABB = Build.bounds(s.model)
		var c: Vector3 = mb.to_local(box.get_center())
		ok(absf(c.x) < mb.width * 0.5 and absf(c.z) < mb.depth * 0.5, "%s liegt auf der Werkbank" % s.tool_id)
		ok(box.position.y >= mb.TOP_Y - 0.01, "%s liegt auf der Platte" % s.tool_id)
	for id in ["F25", "B25", "MK125", "MK32", "F3"]:
		var mdl = slot_of(mb, id).model
		ok(mdl.visible and mb.is_available(id), "%s liegt bereit" % id)
	ok(slot_of(lb, "T5").model.visible, "T5 liegt auf der Bank")

	# Fräsmaschine: Werkzeug nehmen
	var stand: Vector3 = Vector3(6.85, 0.05, -1.75)
	var f10_pos: Vector3 = slot_of(mb, "F10").model.global_transform * Vector3.ZERO
	await aim(p, stand, Build.bounds(slot_of(mb, "F10").model).get_center())
	ok(p._focus == slot_of(mb, "F10"), "F10 auf der Bank lässt sich anvisieren")
	ok(p._prompt.contains("Linksklick") and p._prompt.contains("nehmen"), "Hinweis zum Nehmen: " + p._prompt)
	click(p)
	ok(p.held.get("id", "") == "F10", "Linksklick nimmt F10 in die Hand")
	ok(p._hand.get_child_count() == 1, "Werkzeug ist in der Hand sichtbar")
	ok(w.hud._held.text.contains("Schaftfräser Ø10"), "HUD zeigt das Werkzeug in der Hand")
	mb.refresh()
	ok(not slot_of(mb, "F10").model.visible, "F10 fehlt jetzt auf der Bank")

	# An der Spindel einsetzen
	var from_op: Vector3 = m.to_global(Vector3(0, 0, 0.85)) + Vector3(0, 0.05, 0)
	var tip: Vector3 = m.to_global(Vector3(0, 1.06 + m.tool_z * 0.001 + 0.05, 0))
	await aim(p, from_op, tip)
	ok(p._focus == m.tool_mount, "Spindel lässt sich anvisieren")
	ok(p._prompt.contains("einsetzen"), "Hinweis zum Einsetzen: " + p._prompt)
	# Bei laufender Spindel gesperrt
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
	ok(not slot_of(mb, "F10").model.visible and not slot_of(mb, "F6").model.visible, "Beide fehlen auf der Bank")

	# Zurücklegen
	await aim(p, stand, Build.bounds(slot_of(mb, "F12").model).get_center())
	ok(p._prompt.contains("zurücklegen"), "Hinweis zum Zurücklegen: " + p._prompt)
	click(p)
	ok(p.held.is_empty() and p._hand.get_child_count() >= 0, "F6 zurückgelegt")
	mb.refresh()
	ok(slot_of(mb, "F6").model.visible, "F6 liegt wieder auf der Bank")
	ok(w.hud._held.text == "", "HUD zeigt freie Hand")

	# Freie Hand an der Spindel: E bedient weiter die Maschine, Klick tut nichts
	await aim(p, from_op, tip)
	ok(p._focus == m.tool_mount and p._prompt.contains("Fräsmaschine bedienen"), "Freie Hand: Maschine bedienen")
	click(p)
	ok(m.spindle_empty and p.held.get("id", "") == "F10", "Freie Hand nimmt das Werkzeug aus der Spindel")
	click(p)
	ok(m.tool()["id"] == "F10" and not m.spindle_empty and p.held.is_empty(), "In die leere Spindel einsetzen, kein Tausch")

	# Messerkopf: alle Werkzeuge lassen sich von Hand wechseln
	await aim(p, stand, Build.bounds(slot_of(mb, "MK63").model).get_center())
	click(p)
	ok(p.held.get("id", "") == "MK63", "Messerkopf in der Hand")
	await aim(p, from_op, tip)
	click(p)
	ok(m.tool()["id"] == "MK63" and p.held.get("id", "") == "F10", "Messerkopf eingesetzt, F10 in der Hand")

	# Fremdes Werkzeug passt nicht
	await aim(p, Vector3(0.6, 0.05, -0.5), Build.bounds(slot_of(lb, "T5").model).get_center())
	ok(p._prompt.contains("gehört nicht"), "Fräser gehört nicht auf die Dreh-Werkbank: " + p._prompt)
	click(p)
	ok(p.held.get("id", "") == "F10", "Fräser bleibt in der Hand")
	# Wieder zurück an die Fräs-Werkbank
	await aim(p, stand, Build.bounds(slot_of(mb, "F12").model).get_center())
	click(p)
	ok(p.held.is_empty(), "F10 zurückgelegt")

	# Drehmaschine: nehmen und in freien Platz einspannen
	l.tool_z = 300.0
	l.tool_x = 100.0
	l._sync_slides()
	ok(l.holder == ["T1", "", "T3", ""] and l.active_slot == 0, "Grundbestückung")
	var bench_from: Vector3 = Vector3(0.6, 0.05, -0.5)
	await aim(p, bench_from, Build.bounds(slot_of(lb, "T5").model).get_center())
	ok(p._focus == slot_of(lb, "T5"), "T5 lässt sich anvisieren")
	click(p)
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
	ok(not slot_of(lb, "T5").model.visible, "T5 fehlt auf der Bank")

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
	# Spindel läuft: gesperrt
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
	lb.refresh()
	ok(not slot_of(lb, "T1").model.visible, "T1 in der Hand fehlt auf der Bank")
	p.clear_held()
	await process_frame

	# Hand ist beim Bedienen unsichtbar, danach wieder da
	p.set_held(m, "F16")
	m.interact(p)
	ok(not p._hand.visible, "Hand beim Bedienen ausgeblendet")
	m.stop_operating()
	ok(p._hand.visible, "Hand danach wieder sichtbar")
	p.clear_held()
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
