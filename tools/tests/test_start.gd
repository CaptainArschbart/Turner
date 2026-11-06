extends SceneTree
## Neues Spiel mit Startausstattung: Auftragsmaße, Zielmaße, Zeichnung, 5 Stück je Werkzeug, Halterungen.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 250, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var l = w.lathe
	var o = w.office_pc.overlay

	# ---------------------------------------------------- Startausstattung
	ok(w.money == 250, "Startgeld bleibt")
	ok(w.layout.machines.has("lathe") and l.visible and absf(l.global_position.y) < 0.01, "Drehmaschine steht")
	ok(l.conventional, "Es ist die konventionelle")
	ok(w.layout.machines.has("saw") and w.extra_machines.has("saw"), "Bandsäge steht")
	ok(not w.layout.machines.has("mill"), "Keine Fräse")
	ok(w.layout.benches.has("lathe") and w.bench_nodes.has("lathe"), "Werkbank steht")
	var store = w.company.tools["lathe"]
	for id in ["T1", "T3", "T5"]:
		ok(store.count(id) == 1, "Grundwerkzeug " + id)
	ok(store.count("T2") == 0 and store.count("T6") == 0, "Der Rest wird gekauft")
	ok(not l.has_cutter(), "Werkzeuge liegen auf der Werkbank, nicht in der Maschine")
	ok(w.company.tools["mill"].items.is_empty(), "Keine Fräswerkzeuge")
	ok(w.site.capacity() == 6, "Ein Regal")
	ok(w.stock.size() == 1 and w.stock[0]["kind"] == "round" and float(w.stock[0]["l"]) == 3000.0 and int(w.stock[0].get("slot", -1)) >= 0, "Eine Stange im Regalfach")
	ok(w.buy_equipment("lathe") != "" and w.buy_equipment("saw") != "", "Nicht noch einmal gratis")
	# Speichern und neu laden: nichts kommt doppelt
	var bench = w.bench_nodes["lathe"]
	ok(bench.holders.size() == 24, "24 Halterungen unter der Werkbank")
	# Der Blick trifft die Halterung, auch aus dem schmalen Gang zwischen Maschine und Werkbank
	await physics_frame
	var aim: Vector3 = bench.to_global(bench.holders[9].at + Vector3(0, 0, 0.1))
	var eye: Vector3 = bench.to_global(Vector3(bench.holders[9].at.x, 1.62, 0.35 + 0.35))
	var hit: Dictionary = bench.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + (aim - eye) * 1.5))
	ok(hit.has("collider") and hit["collider"].has_meta("interact") and hit["collider"].get_meta("interact") == bench.holders[9], "Sichtstrahl trifft die Halterung")

	# ---------------------------------------------------- Aufträge
	ok(Jobs.LIST.size() >= 13 and MillJobs.LIST.size() >= 12, "Mehr Aufträge")
	for j in Jobs.LIST:
		ok(Jobs.describe(j).contains("Länge"), "Länge genannt: " + str(j["title"]))
		ok(Jobs.target_lines(j).size() > 0, "Zielmaße: " + str(j["title"]))
		ok(Materials.exists(str(j["material"])), "Werkstoff " + str(j["title"]))
		var contour: PackedVector2Array = load("res://scripts/ui/part_drawing.gd").turned_contour(j)
		ok(contour.size() >= 4 and contour[contour.size() - 1].x == float(j["length"]), "Kontur endet bei der Fertiglänge: " + str(j["title"]))
	for j in MillJobs.LIST:
		ok(MillJobs.target_lines(j).size() > 0, "Zielmaße: " + str(j["title"]))
		ok(Materials.exists(str(j["material"])), "Werkstoff " + str(j["title"]))
	var first := Jobs.describe(Jobs.LIST[0])
	ok(first.contains("150") and first.contains("160"), "Auftrag 1 nennt Länge und Fertiglänge")
	ok(w.accept_job("lathe:0") == "", "Annehmen")

	# ---------------------------------------------------- Zielmaße und Zeichnung
	l.interact(p)
	for i in 3:
		await process_frame
	ok(w.hud._target_panel.visible and w.hud._targets.text.contains("Ø56"), "Zielmaße an der Maschine: " + w.hud._targets.text)
	ok(w.hud._profile.visible, "Konturansicht bleibt oben rechts")
	ok(w.drawing_job()["title"] == Jobs.LIST[0]["title"], "Zeichnung gehört zum Auftrag")
	ok(InputMap.has_action("show_drawing"), "Taste angelegt")
	var key := InputEventAction.new()
	key.action = "show_drawing"
	key.pressed = true
	w.drawing._input(key)
	ok(w.drawing.visible, "Taste öffnet die Zeichnung")
	w.drawing._input(key)
	ok(not w.drawing.visible, "Taste schließt sie")
	l.interact(p)
	for i in 3:
		await process_frame
	w.return_job("lathe:0")
	w.tracked = ""
	w.drawing._input(key)
	ok(not w.drawing.visible, "Ohne Auftrag keine Zeichnung")

	# ---------------------------------------------------- Bis zu 5 Stück
	w.money = 100000
	for i in 4:
		ok(w.buy_tool("lathe", "T1", "hm") == "", "T1 kaufen %d" % (i + 2))
	ok(store.count("T1") == 5, "5 Stück")
	ok(w.buy_tool("lathe", "T1", "hm").contains("5"), "Das 6. nicht")
	var cash: int = w.money
	ok(w.buy_tool("lathe", "T2", "hm") == "" and w.money < cash, "Andere Werkzeuge kosten extra")
	o.tool_tab.select_machine("lathe")
	o.tool_tab.refresh()
	ok(o.tool_tab.rows["T1"]["hm"].disabled and o.tool_tab.rows["T1"]["status"].text.contains("5 von 5"), "Shop zeigt den Bestand")
	# Verschleiß je Stück
	store.items["T1"]["wear"] = 0.5
	store.remove("T1")
	ok(store.count("T1") == 4 and store.wear("T1") == 0.0, "Verschlissen: das nächste rückt nach")
	store.items["T1"]["wear"] = 0.3

	# ---------------------------------------------------- Halterungen
	p.set_held(l, "T1")
	ok(bench.holder_prompt(5).contains("Halterung"), "Hinweis mit Werkzeug in der Hand")
	bench.holder_click(5, p)
	ok(p.held.is_empty() and store.holder_id(5) == "T1" and store.count("T1") == 4, "In Halterung 5 gesteckt")
	ok(bench.holders[5].model != null and bench.holders[5].shown == "T1", "Modell in der Halterung")
	ok(store.wear("T1") == 0.0, "Das nächste Stück ist wieder dran")
	p.set_held(l, "T3")
	bench.holder_click(17, p)
	ok(store.holder_id(17) == "T3" and not store.has("T3"), "Frei wählbar, letztes Stück geht auch")
	ok(not bench.is_available("T3"), "Nicht mehr oben auf der Bank")
	p.set_held(l, "T5")
	bench.holder_click(5, p)
	ok(not p.held.is_empty() and store.holder_id(5) == "T1", "Belegte Halterung nimmt nichts")
	p.clear_held()
	bench.holder_click(5, p)
	ok(p.held["id"] == "T1" and store.holder_id(5) == "" and store.wear("T1") == 0.3, "Nehmen: genau dieses Stück")
	ok(store.count("T1") == 4, "Anzahl stimmt")
	bench.holder_click(5, p)
	ok(store.holder_id(5) == "T1", "Wieder hineingesteckt")
	bench.refresh()
	ok(bench.holders[5].model != null, "Modell wieder da")
	# Gleiches Werkzeug schon an der Maschine
	l.mount_tool(0, "T1")
	ok(l.has_tool("T1"), "T1 in der Maschine")
	ok(bench.holder_prompt(5).contains("schon an der Maschine"), "Zweites Stück bleibt in der Halterung")
	bench.holder_click(5, p)
	ok(p.held.is_empty() and store.holder_id(5) == "T1", "Nicht zugleich herausnehmen")
	l.mount_tool(0, "")

	# ---------------------------------------------------- Speichern
	var state: Dictionary = JSON.parse_string(JSON.stringify(store.to_state()))
	var copy = store.get_script().new()
	copy.load_state(state)
	ok(copy.count("T1") == store.count("T1") and copy.holder_id(5) == "T1" and copy.holder_id(17) == "T3", "Bestand und Halterungen gespeichert")
	ok(copy.spare_count("T1") == store.spare_count("T1"), "Reservestücke gespeichert")

	# ---------------------------------------------------- Maschinenprogramm
	for i in o.overview_tabs.get_tab_count():
		ok(o.overview_tabs.get_tab_title(i) != "Maschinenwerkzeuge", "Keine Werkzeuge im Maschinen-Programm")
	print("CHECKS ", checks, " FAILS ", fails)
	quit(1 if fails > 0 else 0)
