extends SceneTree
## Neues Spiel: leere Halle, Bandsäge gratis, Sägen und Abschnitt einspannen, Preise, PC-Programme.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func _initialize() -> void:
	await process_frame
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var l = w.lathe
	var o = w.office_pc.overlay
	var money0: int = w.money

	# ---------------------------------------------------- Halle und Gratis-Maschinen
	ok(money0 == 250, "Start mit 250 EUR")
	ok(Layout.OBSTACLES.size() == 3, "Nur Büro, Torweg und Durchgang zum Qualitätsmanagement sind fest")
	ok(w.layout.check_machine("lathe", Vector2(-6.0, -5.0), 0) == "", "Der Platz der CNC-Fräse ist frei")
	ok(w.layout.check_machine("drill", Vector2(-10.6, -3.5), 0) == "", "Der Platz des Regals ist frei")
	ok(w.layout.check_machine("mill", Vector2(3.6, -1.0), 0) == "", "Der Platz der Spänekiste ist frei")
	ok(w.layout.check_machine("mill", Vector2(9.5, 6.0), 0) != "", "Das Büro bleibt")
	ok(w.equipment_price("lathe") == 0 and w.equipment_price("saw") == 0, "Drehmaschine und Bandsäge kosten nichts")
	ok(o.machines_tab.buttons.has("saw"), "Bandsäge steht im Maschinen-Tab")
	o.machines_tab.refresh()
	ok(o.machines_tab.buttons["saw"].text == "Gratis mitnehmen" and not o.machines_tab.buttons["saw"].disabled, "Knopf Gratis mitnehmen")
	ok(w.buy_equipment("saw") == "" and w.money == money0, "Mitgenommen, ohne zu zahlen")
	ok(w.buy_equipment("saw") != "", "Nur einmal")
	o.machines_tab.refresh()
	ok(o.machines_tab.buttons["saw"].disabled, "Knopf danach aus")
	ok(w.place_machine("saw", Vector2(-5.0, 3.0), 0) == "", "Aufgestellt")
	var saw = w.extra_machines["saw"]
	ok(saw.has_method("start_cut"), "Eine echte Bandsäge, kein Platzhalter")
	ok(w.buy_equipment("saw") != "", "Auch aufgestellt nicht noch einmal")
	ok(w.buy_equipment("lathe") == "" and w.money == money0, "Drehmaschine gratis")
	ok(w.place_machine("lathe", Vector2(0.0, -2.0), 0) == "", "Drehmaschine aufgestellt")
	ok(not w._work_machines().has(saw), "Säge zählt nicht zu den Bearbeitungsmaschinen")
	for t in saw.get_children():
		if t is StaticBody3D:
			ok(t.get_meta("interact") == saw, "Anvisieren trifft die Säge")

	# ---------------------------------------------------- Stange auflegen und sägen
	var bar := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0}
	p.set_carry(bar.duplicate())
	ok(w.clamp_carried(l).contains("Bandsäge") and not l.has_part and not p.carry.is_empty(), "Ganze Stange passt nicht in die Drehmaschine")
	ok(saw.get_machine() == saw and saw.carry_prompt(p.carry).contains("Rollbahn"), "Hinweis mit Stange in der Hand")
	ok(w.clamp_carried(saw) == "" and p.carry.is_empty() and saw.has_bar(), "Auf die Rollbahn gelegt")
	ok(saw.get_prompt().contains("sägen"), "Hinweis zum Sägen: " + saw.get_prompt())
	var seen := func() -> int: return saw._stock_node.get_child_count()
	ok(seen.call() == 1, "Stange ist sichtbar")
	ok(saw.start_cut(5.0) != "", "Zu kurz")
	ok(saw.start_cut(1200.0) != "", "Zu lang für den Anschlag")
	ok(saw.start_cut(160.0) == "" and saw.cutting and w.machine_busy("saw"), "Säge läuft")
	ok(saw.start_cut(160.0) != "", "Läuft schon")
	ok(w.place_machine("saw", Vector2(-5.0, 5.0), 0) != "", "Nicht umstellen, solange sie läuft")
	saw.stop_cut()
	ok(not saw.cutting and float(saw.bar["l"]) == 3000.0 and not saw.has_piece(), "Stoppen lässt die Stange ganz")
	saw.start_cut(160.0)
	saw._process(0.5)
	ok(saw.cutting and saw.progress > 0.0 and saw._arm.rotation.x > saw.ARM_REST, "Der Bügel senkt sich")
	saw._process(1000.0)
	ok(not saw.cutting and saw.has_piece(), "Durchgesägt")
	ok(float(saw.piece["l"]) == 160.0 and bool(saw.piece["sawn"]), "Abschnitt 160 mm")
	ok(float(saw.bar["l"]) == 3000.0 - 160.0 - Materials.KERF, "Stange um Abschnitt und Schnitt kürzer")
	ok(saw.tray.kg > 0.0 and saw.tray.kg < 1.0, "Etwas Späne in der Wanne: %f" % saw.tray.kg)
	ok(seen.call() == 2, "Stange und Abschnitt sichtbar")
	ok(saw.start_cut(160.0) != "", "Erst den Abschnitt nehmen")
	p.set_carry(bar.duplicate())
	ok(w.clamp_carried(saw) != "" and not p.carry.is_empty(), "Belegt: keine zweite Stange")
	p.clear_carry()

	# ---------------------------------------------------- Abschnitt nehmen und einspannen
	w.saw_click(saw)
	ok(p.carry.get("sawn", false) and not saw.has_piece(), "Abschnitt in den Händen")
	ok(Crate.accepts(p.carry), "Abschnitt darf in die Kiste")
	ok(w.clamp_carried(l) == "" and l.has_part and l.stock_len == 160.0 and p.carry.is_empty(), "Abschnitt wird ganz eingespannt")
	l.clear_workpiece()

	# Reststück zu kurz: Schrott
	saw.load_bar({"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 170.0})
	saw.bar = {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 170.0}
	ok(saw.start_cut(160.0) == "", "Letzter Schnitt")
	saw._process(1000.0)
	ok(saw.has_piece() and not saw.has_bar(), "Zu kurzer Rest ist weg")
	w.saw_click(saw)
	p.clear_carry()
	# Falsche Dinge
	p.set_carry({"material": "S235", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0})
	ok(w.clamp_carried(saw) != "" and not saw.has_bar(), "Fertigschnitt wird nicht gesägt")
	p.clear_carry()
	# Späne dürfen sich nicht mischen, Wanne leeren geht wie überall
	saw.load_bar({"material": "AW-6082", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0})
	ok(saw.start_cut(160.0).contains("Spänewanne"), "Aluminium nicht zu Stahlspänen")
	w.saw_click(saw)
	ok(p.carry["material"] == "AW-6082" and not saw.has_bar(), "Stange wieder nehmen")
	p.clear_carry()

	# ---------------------------------------------------- Bedienfenster
	saw.load_bar({"material": "S235", "kind": "square", "d": 0.0, "w": 60.0, "h": 40.0, "l": 3000.0})
	saw.panel.open()
	ok(saw.panel.visible and p.operating == saw.panel, "Fenster öffnet")
	saw.panel.spin.value = 250.0
	ok(saw.length_mm == 250.0 and is_equal_approx(saw._stop.position.x, 0.25), "Anschlag fährt mit")
	saw.panel.start()
	ok(not saw.panel.visible and p.operating == null and saw.cutting, "Sägen schließt das Fenster")
	saw._process(1000.0)
	ok(saw.piece["kind"] == "square" and float(saw.piece["w"]) == 60.0, "Vierkant gesägt")

	# ---------------------------------------------------- Speichern
	var state: Dictionary = JSON.parse_string(JSON.stringify(saw.get_state()))
	saw.set_state({})
	ok(not saw.has_bar() and saw.tray.is_empty(), "Geleert")
	saw.set_state(state)
	ok(saw.has_bar() and saw.has_piece() and float(saw.piece["l"]) == 250.0 and saw.tray.kg > 0.0, "Stand gespeichert: %s" % str(state))

	# ---------------------------------------------------- Preise
	var rnd: int = Materials.price("S235", "round", 60.0, 0.0, 0.0, 3000.0)
	var sq: int = Materials.price("S235", "square", 0.0, 60.0, 60.0, 3000.0)
	ok(rnd > 80 and float(rnd) / sq > 0.88 and rnd < sq, "Rund Ø60 %d EUR, Vierkant 60 x 60 %d EUR" % [rnd, sq])
	var kg := Materials.weight_kg("S235", "cut", 0.0, 60.0, 40.0, 100.0)
	var cut: int = Materials.price("S235", "cut", 0.0, 60.0, 40.0, 100.0)
	ok(cut >= kg * 1.2 * 1.6 + 8.0, "Fertigschnitt teurer: %d EUR" % cut)
	ok(rnd + 100 + 30 <= money0, "Startgeld reicht für Werkbank, Werkzeug und Stange")

	# ---------------------------------------------------- PC-Programme
	o.open()
	o.open_program("stock")
	ok(o.stock_view.visible and not o.tabs.visible and not o.desktop.visible, "Lager ist ein eigenes Programm")
	o.open_program("waste")
	ok(o.waste_tab.visible and not o.stock_view.visible and not o.tabs.visible, "Entsorgung ist ein eigenes Programm")
	o.show_desktop()
	ok(not o.stock_view.visible and not o.waste_tab.visible, "Desktop zeigt keines davon")
	var titles := []
	for i in o.raw.kinds.get_tab_count():
		titles.append(o.raw.kinds.get_tab_title(i))
	ok(titles == ["Rundmaterial", "Vierkantmaterial", "Fertigschnitt"], "Rohmaterial ohne Lager: %s" % str(titles))
	for i in o.tabs.get_tab_count():
		ok(o.tabs.get_tab_title(i) != "Entsorgung", "Kein Tab Entsorgung im Shop")
	o.close()

	print("CHECKS ", checks, " FAILS ", fails)
	quit(1 if fails > 0 else 0)
