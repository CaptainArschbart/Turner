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
	ok(w.stock.size() == 1 and w.stock[0]["kind"] == "round" and float(w.stock[0]["l"]) == 2000.0 and int(w.stock[0].get("slot", -1)) >= 0, "Eine Stange im Regalfach")
	ok(w.buy_equipment("lathe") != "" and w.buy_equipment("saw") != "", "Nicht noch einmal gratis")
	# Speichern und neu laden: nichts kommt doppelt
	var bench = w.bench_nodes["lathe"]
	ok(bench.holders.size() == 36, "36 Halterungen unter der Werkbank")
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
	ok(not w.day_started and w.accept_job("lathe:0").contains("nicht begonnen"), "Vor Tagesbeginn kein Auftrag")
	ok(w._work_blocked(l, true), "Vor Tagesbeginn keine Bearbeitung")
	o.day_app.start_button.pressed.emit()
	ok(w.day_started, "Tag im Programm gestartet")
	ok(o.day_app.end_button.visible and not o.day_app.start_button.visible, "Jetzt lässt er sich beenden")
	var first := Jobs.describe(Jobs.LIST[0])
	ok(first.contains("150") and first.contains("160"), "Auftrag 1 nennt Länge und Fertiglänge")
	ok(w.day_started and w.accept_job("lathe:0") == "", "Annehmen")

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
	ok(store.holder_id(17) == "T3" and store.has("T3"), "Frei wählbar, letztes Stück geht auch")
	ok(bench.holder_of("T3") == 17, "Steckt in dieser Halterung")
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

	# ---------------------------------------------------- Generierte Aufträge, zufällige Reihenfolge, Grenzen
	ok(Jobs.all().size() > Jobs.LIST.size() and MillJobs.all().size() > MillJobs.LIST.size() and DrillJobs.all().size() > DrillJobs.LIST.size(), "Generierte Aufträge")
	var pd = load("res://scripts/ui/part_drawing.gd")
	for j in Jobs.all().slice(Jobs.LIST.size()):
		var last_d := float(j["stock_d"])
		for f in j["features"]:
			if str(f["type"]) == "dia":
				ok(float(f["d"]) < last_d and float(f["z1"]) > float(f["z0"]) and float(f["z1"]) <= float(j["length"]), "Stufen passen: " + str(j["title"]))
				last_d = float(f["d"])
		ok(float(j["length"]) <= float(j["stock_len"]) and float(j["stock_len"]) <= 800.0, "Länge passt: " + str(j["title"]))
		ok(pd.turned_contour(j).size() >= 4, "Kontur: " + str(j["title"]))
		ok(int(j["reward"]) > w.equipment_price("rack") * 0 + Materials.price(str(j["material"]), "round", float(j["stock_d"]), 0.0, 0.0, Materials.BAR_LEN), "Lohnt sich: " + str(j["title"]))
	for j in MillJobs.all() + DrillJobs.all():
		var s: Array = j["size"]
		for f in j["features"]:
			if str(f["type"]) == "hole":
				ok(float(f["cx"]) > 0.0 and float(f["cx"]) < float(s[0]) and float(f["cy"]) > 0.0 and float(f["cy"]) < float(s[1]) and -float(f["z"]) < float(s[2]), "Bohrung passt: " + str(j["title"]))
			else:
				ok(float(f["x1"]) <= float(s[0]) and float(f["y1"]) <= float(s[1]) and -float(f["z"]) < float(s[2]), "Fläche passt: " + str(j["title"]))
	w.money = 100000
	w.accepted.clear()
	w.grind_jobs.clear()
	w.deadlines.clear()
	var today: Array = w.offers()
	ok(today == w.offers(), "Am selben Tag gleiche Auswahl")
	var per := {}
	for k in today:
		ok(JobBoard.unlocked(k, w.company), "Nur Freigeschaltetes: " + str(k))
		var mk: String = JobBoard.machine_of(k)
		per[mk] = int(per.get(mk, 0)) + 1
		ok(per[mk] <= 2, "Höchstens 2 je Maschine")
	ok(today.size() <= 9, "Höchstens 9 insgesamt")
	var seen := {}
	var saw_other := false
	for d in 30:
		w.day = d + 1
		for k in w.offers():
			seen[k] = true
		if w.offers() != today:
			saw_other = true
	ok(saw_other and seen.size() > 4, "Die Auswahl wechselt: %d verschiedene" % seen.size())
	w.day = 1
	# Tagesbericht
	w.day_stats = {}
	var cash_stat: int = w.money
	w.money = cash_stat - 30
	w.money = w.money + 100
	ok(w.day_stats["earned"] == 100 and w.day_stats["spent"] == 30, "Kasse wird mitgezählt")
	o.day_app.refresh()
	ok(o.day_app.values["profit"].text.contains("70"), "Gewinn: " + o.day_app.values["profit"].text)
	# Tipps im Tab-Menü
	ok(w.accept_job(today[0]) == "", "Auftrag annehmen")
	ok(w.job_menu.show_tips == false, "Tipps sind aus")
	ok(not Jobs.describe(Jobs.LIST[0]).contains("Tipp"), "Auftrag nennt keinen Tipp")
	w.job_menu.toggle_tips()
	ok(w.job_menu.show_tips and w.job_menu.tips_button.text.contains("an"), "Tipps lassen sich einschalten")
	w.job_menu.toggle_tips()
	# Entwicklerprogramm
	o.refresh_all()
	ok(not o.dev_icon.visible, "Entwicklerprogramm nur im Testmodus")
	w.set_free_mode(true)
	ok(o.dev_icon.visible, "Im Testmodus sichtbar")
	o.open()
	o.open_program("dev")
	await process_frame
	o.dev_app.refresh()
	ok(JobBoard.all_keys().size() == 200, "Insgesamt 200 Aufträge: %d" % JobBoard.all_keys().size())
	ok(o.dev_app.cards == 200, "Alle Aufträge gelistet: %d" % o.dev_app.cards)
	var dev_groups: Dictionary = o.dev_app.by_machine()
	ok(o.dev_app.tabs.get_tab_count() == dev_groups.size() and dev_groups.size() >= 4, "Je Maschine ein Tab: %d" % o.dev_app.tabs.get_tab_count())
	var dev_titles := []
	var dev_sum := 0
	for ti in o.dev_app.tabs.get_tab_count():
		dev_titles.append(o.dev_app.tabs.get_tab_title(ti))
	for mk in dev_groups:
		dev_sum += dev_groups[mk].size()
		for k in dev_groups[mk]:
			ok(JobBoard.machine_of(k) == mk, "Auftrag im richtigen Tab: " + str(k))
	ok(dev_sum == 200, "Kein Auftrag fehlt")
	ok(str(dev_titles).contains("Drehmaschine") and str(dev_titles).contains("Fräsmaschine") and str(dev_titles).contains("Standbohrmaschine"), "Tabs: " + str(dev_titles))
	var dev_prefix := false
	for lb in o.dev_app.tabs.find_children("*", "Label", true, false):
		if lb.text.contains("[lathe") or lb.text.contains("[mill") or lb.text.contains("[drill") or lb.text.contains("[ceramic"):
			dev_prefix = true
	ok(not dev_prefix, "Keine Kennung vor den Aufträgen")
	var seen_titles := {}
	for mk in ["lathe", "mill", "drill"]:
		for j in JobBoard.list_of(mk):
			ok(not seen_titles.has(j["title"]), "Titel kommt nur einmal vor: " + str(j["title"]))
			seen_titles[j["title"]] = true
	o.dev_app._show_drawing(Jobs.all()[20])
	ok(w.drawing.visible, "Zeichnung aus dem Programm")
	w.drawing.visible = false
	w.set_free_mode(false)
	ok(o.program == "" and not o.dev_icon.visible, "Ohne Testmodus wieder weg")
	o.close()

	# ---------------------------------------------------- Umspannen: Drehmaschine
	l.set_material("S235")
	l.new_workpiece(60.0, 160.0)
	for i in l.profile.size():
		if (i + 0.5) * l.SEG > 100.0:
			l.profile[i] = 25.0
			l.machined[i] = 1
	var left_r: float = l.radius_at(50.0)
	var right_r: float = l.radius_at(150.0)
	ok(left_r == 30.0 and right_r == 25.0, "Rechts abgedreht")
	ok(l.reclamp(8.0, false) == "" and l.clamp_depth == 8.0 and not l.flipped, "Spanntiefe 8 mm")
	ok(l.z_min() >= 8.0, "Der Meißel kommt nicht in die Backen")
	ok(absf(l.workpiece_mi.position.x + 0.008) < 0.0001, "Teil steckt 8 mm tief")
	ok(l.reclamp(40.0, true) == "" and l.flipped and l.clamp_depth == 40.0, "Umgedreht auf der gedrehten Seite")
	ok(l.radius_at(10.0) == 25.0 and l.radius_at(150.0) == 30.0, "Die gedrehte Seite ist jetzt links")
	var res_turned: Dictionary = l.evaluate({"length": 160.0, "features": [{"type": "dia", "z0": 110.0, "z1": 150.0, "d": 50.0, "tol": 0.2}]})
	ok(int(res_turned["ok"]) == int(res_turned["total"]), "Die Prüfung gilt in der Ausgangslage: " + str(res_turned["lines"]))
	ok(l.radius_at(10.0) == 25.0, "Prüfen dreht nichts dauerhaft um")
	ok(l.reclamp(5.0, true) == "" and not l.flipped and l.radius_at(150.0) == 25.0, "Zurückgedreht")
	var ls: Dictionary = JSON.parse_string(JSON.stringify(l.get_state()))
	ok(float(ls["clamp_depth"]) == 5.0, "Spanntiefe wird gespeichert")
	l.spindle_speed = 500.0
	ok(l.reclamp(5.0, true) != "", "Nicht bei laufender Spindel")
	l.spindle_speed = 0.0
	l.clear_workpiece()
	# Über den Klick: Fenster fragt die Spanntiefe ab
	if p.operating != null:
		p.operating.stop_operating()
	p.clear_held()
	p.set_carry({"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 160.0, "sawn": true})
	w.ask_clamp(l, false)
	ok(w.clamp_dialog.visible and not w.clamp_dialog.flip, "Linksklick fragt nach der Spanntiefe")
	w.clamp_dialog.spin.value = 12.0
	w.clamp_dialog.confirm()
	ok(not w.clamp_dialog.visible and l.has_part and l.clamp_depth == 12.0 and p.carry.is_empty(), "Eingespannt mit 12 mm")
	w.ask_clamp(l, true)
	ok(w.clamp_dialog.visible and w.clamp_dialog.flip, "Rechtsklick spannt andersherum")
	w.clamp_dialog.close()
	l.clear_workpiece()
	p.set_carry({"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 2000.0})
	w.ask_clamp(l, false)
	ok(not w.clamp_dialog.visible, "Ganze Stange: gar nicht erst fragen")
	p.clear_carry()

	# ---------------------------------------------------- Umspannen: Fräse
	var m = w.mill
	m.visible = true
	m.new_workpiece(100.0, 60.0, 40.0)
	m.clear_spindle()
	m.tool_z = 50.0
	m.data[(10 * m.nx + 20) * 2] = -5.0
	m.data[(10 * m.nx + 20) * 2 + 1] = 1.0
	var marked: float = m.data[(10 * m.nx + 20) * 2]
	ok(m.reclamp(30.0, false) == "" and m.grip_depth() == 30.0 and m.jaw_drop() == 10.0, "Spanntiefe 30 mm")
	ok(m.reclamp(30.0, true) == "" and m.flipped, "Kopfüber")
	ok(m.data[(10 * m.nx + 20) * 2] == 0.0, "Die rohe Unterseite zeigt nach oben")
	ok(m.data_back[((m.ny - 1 - 10) * m.nx + 20) * 2] == marked, "Die bearbeitete Seite liegt unten")
	m.data[0] = -2.0
	ok(m.reclamp(30.0, true) == "" and not m.flipped and m.data[(10 * m.nx + 20) * 2] == marked, "Zurück: alles wieder da")
	ok(m.data_back[(m.ny - 1) * m.nx * 2] == -2.0, "Auch die andere Seite behält ihre Bearbeitung")
	var ms: Dictionary = JSON.parse_string(JSON.stringify(m.get_state()))
	ok(float(ms["clamp_depth"]) == 30.0, "Spanntiefe gespeichert")
	m.reclamp(30.0, true)
	var flip_state: Dictionary = JSON.parse_string(JSON.stringify(m.get_state()))
	m.set_state(flip_state)
	ok(m.flipped and m.data_back[((m.ny - 1 - 10) * m.nx + 20) * 2] == marked, "Kopfüber aus dem Spielstand")
	m.clear_workpiece()

	# ---------------------------------------------------- Maschinenprogramm
	for i in o.overview_tabs.get_tab_count():
		ok(o.overview_tabs.get_tab_title(i) != "Maschinenwerkzeuge", "Keine Werkzeuge im Maschinen-Programm")
	print("CHECKS ", checks, " FAILS ", fails)
	quit(1 if fails > 0 else 0)
