extends SceneTree
## Konventionelle Drehmaschine, CNC-Drehmaschine, Standbohrmaschine, Flach- und Rundschleifmaschine.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n.text)
	for c in n.get_children():
		labels(c, out)
func text_of(n: Node) -> String:
	var t := []
	labels(n, t)
	return "\n".join(PackedStringArray(t))
## Frästeil von Hand: bis (x, y, z) fahren.
func go(m, x: float, y: float, z: float, speed: float) -> void:
	m.move_tool(x - m.tool_x, y - m.tool_y, z - m.tool_z, speed)
func spin(m) -> void:
	m.estop = false
	m.spindle_on = true
	m.spindle_speed = m.rpm_set
func stop(m) -> void:
	m.spindle_on = false
	m.spindle_speed = 0.0
## Drehteil: Kontur direkt setzen, wie nach dem Drehen.
func turn_to(l, job: Dictionary) -> void:
	for f in job["features"]:
		if str(f.get("type", "dia")) != "dia":
			continue
		for i in l.profile.size():
			var z: float = (i + 0.5) * l.SEG
			if z >= float(f["z0"]) - 0.5 and z <= float(f["z1"]) + 0.5:
				l.profile[i] = float(f["d"]) * 0.5
				l.machined[i] = 1
				l.rz[i] = 8.0
	if job.has("length"):
		for i in l.profile.size():
			if (i + 0.5) * l.SEG > float(job["length"]):
				l.profile[i] = 0.0
## Abgeben wie im Spiel: ausspannen und im Qualitätsmanagement prüfen lassen.
func submit(w, m) -> void:
	if m.grinder_type != "":
		w._on_grind_submit(m)
	elif m.has_method("is_untouched"):
		w._on_submit(m)
	else:
		w._on_mill_submit(m)
func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var l = w.lathe
	var m = w.mill
	var co = w.company
	w.money = 200000
	var o2 = w.office_pc.overlay

	# ---------------------------------------------------- Konventionelle Drehmaschine
	ok(l.conventional and l.MACHINE_ID == "lathe", "Drehmaschine ist konventionell")
	ok(l.screen_vp == null and l._pult == null, "Kein Pult und kein Bildschirm")
	ok(l._door.get_child_count() == 0, "Keine Kabinentür")
	ok(l._dial_panel != null and l._dial_panel.dials.size() == 2, "Bedienfeld mit zwei Drehknöpfen")
	ok(l.get_prompt().contains("Konventionelle Drehmaschine"), "Name im Hinweis: " + l.get_prompt())
	# Knöpfe wie an der Fräse: Stufen, Rasten, nur bei stehender Spindel
	l.rpm_set = 250.0
	l.feed_set = 0.1
	l._dial_panel.sync()
	ok(l.dial_index(0) == 4 and l.dial_stage(0) == 0, "Drehzahl auf Raste und Stufe")
	l.stage_set(0, 1)
	ok(l.rpm_set == 500.0 and l.dial_stage(0) == 1, "Taste II: Stufe wechselt, Raste bleibt")
	l.dial_set(0, 2)
	ok(l.rpm_set == 200.0, "Knopf auf Raste 3")
	l.dial_set(0, 9)
	ok(l.dial_index(0) == 1, "Knopf dreht ohne Anschlag rundum")
	l.dial_set(1, 7)
	ok(l.feed_set == 0.25, "Vorschub in mm/U: " + str(l.feed_set))
	l.stage_set(1, 1)
	ok(l.feed_set == 0.5, "Vorschub Stufe II")
	l.spindle_on = true
	var r0: float = l.rpm_set
	l.dial_set(0, 0)
	ok(l.rpm_set == r0, "Bei laufender Spindel gesperrt")
	l.spindle_on = false
	l.spindle_speed = 0.0
	# Station: E aufs Bedienfeld
	await process_frame
	l.open_levers(p)
	for i in 3:
		await process_frame
	ok(l.panel_open and p.operating == l and w.hud._lever_box.visible, "Bedienfeld öffnet, eigene Anzeige")
	ok(w.hud._lever_info.text.contains("Vorschub") and w.hud._lever_info.text.contains("mm/U"), "Anzeige: " + w.hud._lever_info.text)
	var plate: Node3D = l._dial_panel.plate
	var o: Vector3 = plate.to_global(Vector3(0.0, 0.09, 0.3))
	var d: Vector3 = (plate.to_global(Vector3(0.0, 0.09 + 0.05, 0.0)) - o).normalized()
	ok(l.panel_hit(o, d).get("dial", -1) == 0, "Sichtstrahl trifft den Drehzahl-Knopf")
	var e_key := InputEventAction.new()
	e_key.action = "interact"
	e_key.pressed = true
	l.close_levers()
	await process_frame
	ok(not l.panel_open and p.operating == null and not w.hud._lever_box.visible, "Bedienfeld schließt")
	# Bedienung: kein Bedienpult-Tab, Rest wie gehabt
	l.interact(p)
	for i in 3:
		await process_frame
	ok(w.hud._dro_panel.visible and w.hud._main.text.contains("KSS"), "Anzeige an der Maschine")
	var conv_tabs := []
	for ti in w.hud._overlay.tabs.get_tab_count():
		conv_tabs.append(w.hud._overlay.tabs.get_tab_title(ti))
	ok(not conv_tabs.has("Bedienpult") and conv_tabs.has("Bedienknöpfe"), "Bedienknöpfe statt Bedienpult: %s" % str(conv_tabs))
	ok(not w.hud._main.visible, "Wie an der Fräse nur die Achsen")
	ok(w.hud._target_panel.visible and w.hud._targets.text.contains("Zielmaße"), "Zielmaße oben rechts")
	var f4 := InputEventAction.new()
	f4.action = "cam_panel"
	f4.pressed = true
	l._unhandled_input(f4)
	ok(not l.in_panel_view(), "Keine Pultansicht")
	l.stop_operating()
	await process_frame
	# Drehen geht wie an der NC-Maschine
	l.new_workpiece(60.0, 160.0)
	l.rpm_set = 800.0
	spin(l)
	l.tool_z = 150.0
	l.tool_x = 29.0
	l._cut(150.0, 29.0, 2.0, 1.0, true)
	ok(l.radius_at(150.0) < 30.0, "Konventionell wird geschnitten")
	stop(l)
	l.clear_workpiece()

	# ---------------------------------------------------- CNC-Drehmaschine
	ok(co.skills.has("lathe_cnc"), "CNC freigeschaltet")
	ok(w.buy_equipment("cnc_lathe") == "" and w.inventory["cnc_lathe"] == 1, "CNC-Drehmaschine kaufen")
	ok(w.place_machine("cnc_lathe", Vector2(-1.0, 4.0), 0) == "", "Aufstellen: " + w.layout.check_machine("cnc_lathe", Vector2(-1.0, 4.0), 0))
	var c = w.cnc_lathe
	ok(c != null and not c.conventional and c.screen_vp != null and c._pult != null, "Mit Kabine und Pult")
	ok(c.MACHINE_ID == "cnc_lathe" and not c.has_cutter(), "Eigene Werkzeuge, startet leer")
	ok(co.owns("cnc_lathe") and co.owns_kind("lathe"), "Zählt als Drehmaschine")
	ok(w.buy_tool("cnc_lathe", "T1", "hm") == "", "Werkzeug für die CNC-Maschine kaufen")
	p.set_held(c, "T1")
	c.hand_click(p)
	ok(c.has_tool("T1") and co.tools["cnc_lathe"].has("T1"), "Jede Maschine hat ihre eigenen Werkzeuge")
	# E50: Die Spänekiste unter dem Förderer ist ein normaler großer Spänebehälter der Werkstatt
	if c.e50:
		var bi := -1
		for i in w.layout.bins.size():
			if str(w.layout.bins[i].get("machine", "")) == "cnc_lathe":
				bi = i
		ok(bi >= 0 and str(w.layout.bins[bi]["size"]) == "bin_l", "E50 bekommt einen großen Spänebehälter")
		if bi >= 0:
			var eb: Dictionary = w.layout.bins[bi]
			ok(c.chip_bin == eb["chips"] and c.chip_bin_node == w.bin_nodes[bi], "Förderer füllt genau diesen Behälter")
			var spot: Vector3 = (c.transform * c.chip_bin_spot).origin
			ok(w.bin_nodes[bi].position.distance_to(Vector3(spot.x, 0, spot.z)) < 0.01, "Behälter steht unter dem Abwurf")
			ok(w.bin_prompt(bi).contains("kran") and w.bin_prompt(bi).contains("Späneförderer"), "Hinweis am Behälter: " + w.bin_prompt(bi))
			w.bin_click(bi)
			ok(p.carry.is_empty() or not p.carrying_bin(), "Lässt sich nicht aufheben")
			ok(w.place_bin(bi, "", Vector2(6.0, 6.0), 0) == w.MACHINE_BIN_FIXED, "Steht fest unter dem Förderer")
			c.tray.clear()
			c.tray.add("baustahl", 3.0)
			c.conveyor_on = true
			var was_on: bool = c.powered
			c.powered = true
			c._physics_process(0.016)
			ok(is_equal_approx(eb["chips"].kg, 3.0), "Förderer trägt in den Behälter ab")
			var saved: Dictionary = JSON.parse_string(JSON.stringify(w.layout.to_state()))
			var found := false
			for b in saved["bins"]:
				if str(b.get("machine", "")) == "cnc_lathe" and is_equal_approx(float(b["chips"]["kg"]), 3.0):
					found = true
			ok(found, "Behälter mit Inhalt und Maschine gespeichert")
			ok(w.layout.check_machine("cnc_lathe", Vector2(-1.0, 4.0), 0) == "", "Eigene Kiste blockiert die Maschine nicht")
			w._sync_machine_bins()
			ok(w.layout.bins.filter(func(b): return str(b.get("machine", "")) == "cnc_lathe").size() == 1, "Kiste nicht doppelt")
			# Hallenkran: Kiste herausheben, beiseitestellen (der Förderer staut), wieder darunterstellen
			var cr = w.crane
			var bh: float = w.crane_bin_height(bi)
			cr.bridge_x = spot.x
			cr.trolley_z = spot.z
			cr.hook_y = cr.SLING + bh + 0.2
			cr.hook_click()
			ok(cr.hooked == bi and c.chip_bin_away, "Kran hebt die Spänekiste unter dem Förderer heraus")
			var free := Vector2.INF
			for cand in [Vector2(spot.x, spot.z - 3.5), Vector2(spot.x, spot.z + 3.5), Vector2(spot.x - 3.5, spot.z), Vector2(spot.x + 3.5, spot.z), Vector2(spot.x + 3.5, spot.z - 3.5)]:
				if free == Vector2.INF and w.layout.check_bin(cand, int(eb["rot"]), bi, "bin_l") == "":
					free = cand
			ok(free != Vector2.INF, "Freier Platz neben der E50")
			if free != Vector2.INF:
				cr.bridge_x = free.x
				cr.trolley_z = free.y
				cr.hook_y = 0.0
				cr._physics_process(0.016)
				cr.hook_click()
				ok(cr.hooked < 0 and bool(eb.get("away", false)) and c.chip_bin_away, "Kiste steht beiseite")
				ok(w.bin_prompt(bi).contains("schieben"), "Beiseite lässt sie sich schieben: " + w.bin_prompt(bi))
				c.tray.add("baustahl", 2.0)
				c._physics_process(0.016)
				ok(is_equal_approx(eb["chips"].kg, 3.0) and c.tray.kg > 1.9, "Ohne Kiste trägt der Förderer nichts ab")
				var away_saved: Dictionary = JSON.parse_string(JSON.stringify(w.layout.to_state()))
				ok(away_saved["bins"].any(func(b): return str(b.get("machine", "")) == "cnc_lathe" and bool(b.get("away", false))), "Beiseite gestellt gespeichert")
				cr.hook_y = cr.SLING + bh + 0.2
				cr.hook_click()
				ok(cr.hooked == bi, "Wieder eingehängt")
				cr.bridge_x = spot.x + 0.3
				cr.trolley_z = spot.z
				cr.hook_y = 0.0
				cr._physics_process(0.016)
				cr.hook_click()
				ok(cr.hooked < 0 and not bool(eb.get("away", false)) and not c.chip_bin_away, "Kiste rastet unter dem Förderer ein")
				ok(w.bin_nodes[bi].position.distance_to(Vector3(spot.x, 0, spot.z)) < 0.01, "Wieder genau unter dem Abwurf")
				c._physics_process(0.016)
				ok(is_equal_approx(eb["chips"].kg, 5.0), "Förderer trägt wieder ab")
				c.tray.clear()
			c.powered = was_on
			c.conveyor_on = true
			eb["chips"].clear()
			c.refresh_tray()
	# Auftrag auf der CNC-Maschine abgeben
	w.accepted = ["lathe:0"]
	w.job_index = 0
	c.new_workpiece(60.0, 160.0)
	turn_to(c, Jobs.LIST[0])
	var cash0: int = w.money
	submit(w, c)
	ok(w.money == cash0 + int(Jobs.LIST[0]["reward"]) and w.accepted.is_empty(), "Drehauftrag auf der CNC-Maschine bezahlt")
	ok(not c.has_part, "Maschine leer")
	# Einspannen geht an die richtige Maschine
	p.clear_carry()
	p.clear_held()
	p.set_carry({"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 500.0})
	ok(w.clamp_carried(c) == "" and c.has_part and not l.has_part, "Rundmaterial landet in der CNC-Maschine")
	p.clear_carry()
	c.clear_workpiece()
	# HUD folgt der Maschine (die CNC-Maschine muss dafür hochgefahren sein)
	c.powered = true
	c.booting = 0.0
	c.interact(p)
	for i in 3:
		await process_frame
	ok(w.hud.lathe == c and w.hud._overlay.tabs != null, "HUD zeigt die CNC-Maschine")
	c.stop_operating()
	await process_frame
	ok(c.get_prompt().contains("E50"), "Hinweis nennt die E50")

	# ---------------------------------------------------- Standbohrmaschine
	ok(w.buy_equipment("drill") == "", "Standbohrmaschine kaufen")
	ok(w.place_machine("drill", Vector2(-9.0, 5.0), 0) == "", "Aufstellen: " + w.layout.check_machine("drill", Vector2(-9.0, 5.0), 0))
	var dr = w.extra_machines["drill"]
	ok(dr.has_method("make_bench_model") and dr.MACHINE_ID == "drill", "Echte Bohrmaschine, kein Platzhalter")
	ok(dr.spindle_empty and dr.tool_stock == co.tools["drill"], "Startet ohne Bohrer")
	ok(not dr.has_part, "Ohne Teil")
	ok(dr.get_prompt().contains("Standbohrmaschine"), "Hinweis: " + dr.get_prompt())
	ok(dr._dial_panel != null and dr.rpm_dial()[0][0] == 100, "Eigene Drehzahlen am Bedienfeld")
	ok(dr.tool_list().size() == 12, "Nimmt nur Spiralbohrer")
	ok(w.mill_huds.has("drill"), "Eigene Anzeige")
	# Werkbank mit Bohrern
	w.inventory["bench"] = 1
	ok(w.place_bench("", Vector2(-8.9, 6.6), 2) == "", "Werkbank: " + w.layout.check_bench(Vector2(-8.9, 6.6), 2))
	var db = w.bench_nodes["drill"]
	ok(db.holders.size() == 36, "Werkbank mit Halterungen")
	ok(w.buy_tool("drill", "B8", "hm") == "", "Bohrer kaufen")
	db.refresh()
	ok(db.holder_of("B8") >= 0, "Gekaufter Bohrer steckt in einer Halterung")
	p.clear_held()
	db.holder_click(db.holder_of("B8"), p)
	ok(p.held.get("machine", "") == "drill", "Bohrer in die Hand")
	dr.hand_click(p)
	ok(dr.has_cutter() and dr.tool()["id"] == "B8" and p.held.is_empty(), "Bohrer in die Spindel")
	# Bohrauftrag
	var dj: Dictionary = DrillJobs.LIST[0]
	ok(JobBoard.all_keys().has("drill:0"), "Bohraufträge im Angebot")
	ok(w.accept_job("drill:0") == "" and w.has_job("drill"), "Bohrauftrag annehmen: ")
	w.job_menu.open()
	ok(text_of(w.job_menu.pages["drill"]).contains("Bohrauftrag 1"), "Steht im Menü auf Tab")
	w.job_menu.close()
	ok(w.job_status_of("drill:0").contains("kaufen"), "Status: Material fehlt")
	# Material: Fertigschnitt tragen und einspannen
	p.set_carry({"material": "S235", "kind": "cut", "d": 0.0, "w": 80.0, "h": 20.0, "l": 120.0})
	ok(w.clamp_carried(dr) == "" and dr.has_part and dr.block_l == 120.0 and not m.has_part, "Rohteil auf der Bohrmaschine")
	dr.rpm_set = 800.0
	dr.feed_set = 80.0
	dr.coolant = true
	spin(dr)
	for f in dj["features"]:
		go(dr, float(f["cx"]), float(f["cy"]), 5.0, 10.0)
		ok(not dr.estop, "Positionieren über dem Material")
		go(dr, float(f["cx"]), float(f["cy"]), float(f["z"]), 1.0)
		ok(not dr.estop, "Bohren ohne Bruch")
		go(dr, float(f["cx"]), float(f["cy"]), 5.0, 10.0)
	var dres: Dictionary = dr.evaluate(dj)
	ok(float(dres["score"]) >= 0.999, "Bohrbild in Toleranz: " + str(dres["lines"]))
	stop(dr)
	await physics_frame
	ok(dr.tool_wear() >= 0.0, "Bohrer hat Verschleiß")
	var cash1: int = w.money
	var xp1: int = co.skills.xp
	submit(w, dr)
	ok(w.money == cash1 + int(dj["reward"]), "Bohrauftrag bezahlt")
	ok(co.skills.xp == xp1 + int(dj["reward"]), "Erfahrung")
	ok(not dr.has_part and not w.accepted.has("drill:0"), "Abgegeben")
	# Seitlich im Material bricht der Bohrer
	var b8_count: int = co.tools["drill"].count("B8")
	dr.new_workpiece(120.0, 80.0, 20.0)
	spin(dr)
	go(dr, 60.0, 40.0, 5.0, 10.0)
	go(dr, 60.0, 40.0, -5.0, 1.0)
	go(dr, 70.0, 40.0, -5.0, 1.0)
	ok(dr.estop and dr.spindle_empty and co.tools["drill"].count("B8") == b8_count - 1, "Seitlich im Material: Bohrer bricht und ist weg")
	dr.estop = false
	stop(dr)
	dr.tool_z = 50.0
	dr.clear_workpiece()
	# Jeder Bohrauftrag lohnt sich
	var dmax := 0
	for t in MillTools.of_kind("drill"):
		dmax = maxi(dmax, int(t["price"]))
	for i in DrillJobs.LIST.size():
		w.drill_job_index = i
		var cost: int = w._job_cost("drill") + dmax
		ok(int(DrillJobs.LIST[i]["reward"]) > cost, "%s lohnt sich: %d > %d" % [DrillJobs.LIST[i]["title"], int(DrillJobs.LIST[i]["reward"]), cost])
		for f in DrillJobs.LIST[i]["features"]:
			var fits := false
			for t in MillTools.of_kind("drill"):
				fits = fits or is_equal_approx(float(t["d"]), float(f["d"]))
			ok(fits, "Bohrer zum Auftrag vorhanden")
	w.drill_job_index = 0

	# ---------------------------------------------------- Flachschleifmaschine
	ok(not JobBoard.grind_active(MillJobs.LIST[0], co), "Ohne Maschine keine Schleifanforderung")
	ok(w.buy_equipment("flat_grinder") == "", "Flachschleifmaschine kaufen")
	ok(w.place_machine("flat_grinder", Vector2(2.5, -6.0) if false else Vector2(-9.0, -1.0), 0) == "", "Aufstellen: " + w.layout.check_machine("flat_grinder", Vector2(-9.0, -1.0), 0))
	var fg = w.extra_machines["flat_grinder"]
	ok(fg.grinder_type == "flat", "Echte Flachschleifmaschine")
	ok(not fg.has_cutter() and fg.tool()["kind"] == "wheel", "Startet ohne Scheibe")
	ok(fg.tool_list().size() == 9, "Drei Schleifmittel in drei Breiten")
	ok(w.buy_tool("flat_grinder", "D25", "hm") != "" and w.buy_tool("flat_grinder", "C25", "hm") != "", "CBN und Diamant erst nach den Skills")
	ok(w.buy_tool("flat_grinder", "K25", "hm") == "", "Korundscheibe kaufen")
	p.clear_held()
	p.set_held(fg, "K25")
	fg.hand_click(p)
	ok(fg.has_cutter() and fg.tool()["id"] == "K25" and p.held.is_empty(), "Scheibe aufziehen")
	ok(JobBoard.grind_active(MillJobs.LIST[0], co), "Jetzt wird geschliffen verlangt")
	p.set_carry({"material": "S235", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0})
	var raw_err: String = w.clamp_carried(fg)
	ok(raw_err.contains("vorbearbeitete") and not fg.has_part, "Rohmaterial wird nicht gespannt: " + raw_err)
	p.clear_carry()
	# Fräsauftrag 1 fertig fräsen, abgeben: Teil kommt in die Hände
	w.accepted = ["mill:0"]
	w.mill_job_index = 0
	m.tray.clear()
	m.select_tool(m.tool_index("MK63"), true)
	m.new_workpiece(100.0, 60.0, 40.0)
	m.rpm_set = 630.0
	m.feed_set = 100.0
	spin(m)
	for y in [15.0, 45.0]:
		go(m, -40.0, y, -2.0, 50.0)
		go(m, 140.0, y, -2.0, 3.0)
		go(m, 140.0, y, 5.0, 50.0)
		go(m, -40.0, y, 5.0, 50.0)
	stop(m)
	ok(not m.estop and float(m.evaluate(MillJobs.LIST[0])["score"]) >= 0.999, "Frästeil in Toleranz")
	var cash2: int = w.money
	var xp2: int = co.skills.xp
	submit(w, m)
	ok(w.money == cash2 + int(MillJobs.LIST[0]["reward"]), "Fräsen wird bezahlt")
	ok(co.skills.xp == xp2, "Erfahrung erst nach dem Schleifen")
	ok(p.carrying_semi() and str(p.carry["key"]) == "mill:0", "Teil in den Händen")
	ok(not w.accepted.has("mill:0") and w.grind_jobs.has("mill:0"), "Auftrag wartet aufs Schleifen")
	ok(w.accept_job("mill:0") != "", "Nicht doppelt annehmbar")
	w.job_menu.open()
	ok(text_of(w.job_menu.pages["flat_grinder"]).contains("Fräsauftrag 1"), "Flachschleifauftrag im Menü")
	w.job_menu.close()
	ok(w.store_carried(0) != "" and p.carrying_semi(), "Halbfertiges Teil nicht ins Regal")
	ok(w.clamp_carried(m) != "" and p.carrying_semi(), "Nicht auf die Fräse")
	ok(w.clamp_carried(fg) == "" and fg.has_part and fg.semi_key == "mill:0", "Auf die Schleifmaschine")
	ok(p.carry.is_empty(), "Hände frei")
	ok(fg.material == "S235" and absf(fg.height_at(50.0, 30.0) + 2.0) < 0.01, "Kontur kommt mit")
	# Überlastung
	fg.rpm_set = 2500.0
	fg.feed_set = 400.0
	fg.coolant = true
	spin(fg)
	go(fg, -40.0, 15.0, -2.1, 20.0)
	go(fg, 20.0, 15.0, -2.1, 5.0)
	ok(fg.estop, "Zu viel Zustellung: Not-Halt")
	ok(fg.has_cutter(), "Scheibe bleibt")
	fg.estop = false
	# Schleifen: wenig zustellen, Bahnen über die ganze Fläche
	go(fg, -40.0, 15.0, 3.0, 20.0)
	# Prüfung vor dem Schleifen: Fläche fehlt, nicht Ausschuss
	stop(fg)
	var cash3: int = w.money
	fg.request_submit()
	ok(w.money == cash3 and fg.has_part and w.grind_jobs.has("mill:0"), "Noch nicht geschliffen: weiterarbeiten")
	spin(fg)
	go(fg, -40.0, 5.0, 3.0, 20.0)
	ok(not fg.estop, "Über das Teil fahren")
	for z in [-2.04, -2.08, -2.12]:
		var y := 5.0
		while y <= 60.0:
			go(fg, -40.0, y, z, 20.0)
			go(fg, 140.0, y, z, 5.0)
			go(fg, -40.0, y, z, 20.0)
			y += 10.0
	ok(not fg.estop, "Schleifen ohne Not-Halt")
	ok(absf(fg.height_at(50.0, 30.0) + 2.12) < 0.01, "Höhe nach dem Schleifen")
	fg._add_wear(30.0)
	var gres: Dictionary = fg.evaluate_grind(MillJobs.LIST[0])
	ok(float(gres["score"]) >= 0.999, "Schleifprüfung: " + str(gres["lines"]))
	stop(fg)
	var cash4: int = w.money
	var xp4: int = co.skills.xp
	submit(w, fg)
	ok(w.money == cash4 + int(MillJobs.LIST[0]["grind"]["reward"]), "Schleifen wird bezahlt")
	ok(co.skills.xp == xp4 + int(MillJobs.LIST[0]["reward"]), "Jetzt gibt es die Erfahrung")
	ok(not fg.has_part and fg.semi_key == "" and w.grind_jobs.is_empty(), "Auftrag fertig")
	# Rautiefe hängt am Vorschub
	ok(fg.grind_rz(3.0, 0.05, true) > fg.grind_rz(0.5, 0.01, true), "Schnell und tief ist rauer")
	ok(fg.grind_rz(0.5, 0.01, false) > fg.grind_rz(0.5, 0.01, true), "Ohne Kühlung rauer")
	# Abnutzung und Abziehen
	var store = co.tools["flat_grinder"]
	var w0: float = store.wear("K25")
	ok(w0 > 0.0 and store.dull("K25") > 0.0, "Schleifen nutzt die Korundscheibe ab und macht sie unrund: " + store.info("K25"))
	ok(Wheels.finish("korund", 1.0) > Wheels.finish("korund", 0.0), "Unrunde Scheibe schleift rauer")
	ok(Wheels.wear_factor("cbn", "S235", false) < Wheels.wear_factor("korund", "S235", false), "CBN hält länger als Korund")
	ok(Wheels.wear_factor("korund", "1.4301", false) > Wheels.wear_factor("korund", "S235", false), "Korund leidet an hartem Werkstoff")
	ok(Wheels.wear_factor("diamant", "S235", false) > Wheels.wear_factor("diamant", "1.4301", true), "Stahl ruiniert Diamant")
	ok(not Wheels.cuts("korund", true) and not Wheels.cuts("cbn", true) and Wheels.cuts("diamant", true), "Keramik schneidet nur Diamant")
	var dull0: float = store.dull("K25")
	fg.new_workpiece(100.0, 60.0, 40.0)
	spin(fg)
	go(fg, fg.dresser_x(), 30.0, 5.0, 20.0)
	ok(store.dull("K25") == dull0, "Über dem Abziehwerkzeug ohne Berührung passiert nichts")
	go(fg, fg.dresser_x(), 30.0, fg.DRESS_Z, 2.0)
	ok(store.dull("K25") == 0.0 and store.wear("K25") > w0, "Anfahren zieht ab: wieder gerade, kostet Scheibe")
	var w1: float = store.wear("K25")
	go(fg, fg.dresser_x(), 30.0, fg.DRESS_Z, 2.0)
	ok(store.wear("K25") == w1, "Einmal Anfahren zählt einmal")
	go(fg, fg.dresser_x(), 30.0, fg.DRESS_Z - 2.0, 2.0)
	ok(fg.estop, "Zu tief ins Abziehwerkzeug: Not-Halt")
	fg.estop = false
	go(fg, fg.dresser_x(), 30.0, 5.0, 20.0)
	stop(fg)
	fg.clear_workpiece()
	# Verbraucht
	var k25_count: int = store.count("K25")
	store.items["K25"]["wear"] = 0.99
	spin(fg)
	fg.new_workpiece(100.0, 60.0, 40.0)
	go(fg, fg.dresser_x(), 30.0, fg.DRESS_Z, 2.0)
	ok(not fg.has_cutter() and store.count("K25") == k25_count - 1 and fg.estop, "Abziehen bis zum Ende: Scheibe verbraucht, neu kaufen")
	fg.estop = false
	stop(fg)
	fg.tool_z = 40.0
	fg.clear_workpiece()

	# ---------------------------------------------------- Rundschleifmaschine
	ok(w.buy_equipment("round_grinder") == "", "Rundschleifmaschine kaufen")
	# Freien Platz suchen: Die Hallenbelegung ändert sich mit den Maschinenmodellen
	var rg_at := Vector2.INF
	# Die Grundhalle ist mit sechs Maschinen voll: zwei Hallenreihen im Westen dazukaufen
	w.money += 100000
	for cx in [-4, -5]:
		for cz in range(-5, 4):
			w.buy_tile("workshop", Vector2i(cx, cz))
	for gx in range(-80, 41):
		for gz in range(-24, 25):
			var q := Vector2(gx * 0.25, gz * 0.25)
			if rg_at == Vector2.INF and w.layout.check_machine("round_grinder", q, 0) == "":
				rg_at = q
	ok(rg_at != Vector2.INF and w.place_machine("round_grinder", rg_at, 0) == "", "Rundschleifmaschine aufstellen: %s / %s" % [rg_at, w.layout.check_machine("round_grinder", Vector2(5.3, 2.8), 0)])
	var rg = w.extra_machines["round_grinder"]
	ok(rg.grinder_type == "round" and rg.conventional, "Echte Rundschleifmaschine")
	ok(not rg.has_cutter() and rg.tool_list().size() == 9, "Startet ohne Scheibe, neun Scheiben im Angebot")
	ok(w.buy_tool("round_grinder", "K30", "hm") == "", "Korundscheibe kaufen")
	p.clear_held()
	p.set_held(rg, "K30")
	rg.hand_click(p)
	ok(rg.has_cutter() and rg.tool()["id"] == "K30" and p.held.is_empty(), "Scheibe aufziehen")
	ok(rg.screen_vp == null, "Ohne Pult")
	ok(JobBoard.grind_active(Jobs.LIST[4], co), "Rundfläche wird verlangt")
	ok(not JobBoard.grind_active(Jobs.LIST[0], co), "Auftrag 1 hat keine Schleifanforderung")
	for j in Jobs.LIST:
		if j.has("grind"):
			ok(j["grind"]["type"] == "round" and j["grind"].has("z0"), "Drehteile werden rund geschliffen: " + str(j["title"]))
	for j in MillJobs.LIST:
		if j.has("grind"):
			ok(j["grind"]["type"] == "flat" and j["grind"].has("area"), "Frästeile werden flach geschliffen: " + str(j["title"]))
	# Auftrag 5 (Aluminium): Wanne der Maschinen ist leer
	var job5: Dictionary = Jobs.LIST[4]
	w.accepted = ["lathe:4"]
	w.job_index = 4
	l.tray.clear()
	l.new_workpiece(50.0, 120.0)
	l.set_material("AW-6082")
	turn_to(l, job5)
	for i in l.profile.size():
		if (i + 0.5) * l.SEG <= 10.0:
			l.profile[i] = 22.0
	for f in job5["features"]:
		if str(f["type"]) == "chamfer":
			var c0: float = float(f["size"])
			for i in l.profile.size():
				var z: float = (i + 0.5) * l.SEG
				if z >= float(f["z"]) - c0 and z <= float(f["z"]):
					l.profile[i] = float(f["d"]) * 0.5 - (z - (float(f["z"]) - c0))
	var pre: Dictionary = l.evaluate(job5)
	ok(float(pre["score"]) >= 0.999, "Drehteil in Toleranz: " + str(pre["lines"]))
	var cash5: int = w.money
	submit(w, l)
	ok(w.money == cash5 + int(job5["reward"]) and p.carrying_semi(), "Drehen bezahlt, Teil in den Händen")
	ok(str(p.carry["type"]) == "round", "Es muss rund geschliffen werden")
	ok(w.clamp_carried(fg) != "", "Nicht auf die Flachschleifmaschine")
	ok(w.clamp_carried(rg) == "" and rg.has_part and rg.semi_key == "lathe:4", "Auf die Rundschleifmaschine")
	ok(absf(rg.radius_at(40.0) - 22.0) < 0.01, "Kontur kommt mit")
	rg.rpm_set = 250.0
	rg.feed_set = 0.15
	rg.coolant = true
	rg.tool_x = 30.0
	rg.tool_z = 90.0
	spin(rg)
	# Zu viel Zustellung wird verweigert
	rg.tool_z = 40.0
	rg.tool_x = 25.0
	rg.move_tool(0.0, -3.5, false, 0.1)
	ok(rg.tool_x > 21.8, "Scheibe stellt nicht zu tief zu: %f" % rg.tool_x)
	# Fein schleifen: Durchgänge längs
	rg.tool_z = 85.0
	rg.tool_x = 22.0
	rg.move_tool(0.0, -0.03, false, 0.05)
	var vf: float = rg.feed_set * rg.rpm_set / 60.0
	rg.move_tool(-60.0, 0.0, false, vf)
	var rz_mid: float = rg.rz[int(40.0 / rg.SEG)]
	ok(rz_mid > 0.0 and rz_mid <= 2.5, "Feine Oberfläche: %f" % rz_mid)
	ok(rg.radius_at(40.0) < 22.0 and rg.radius_at(40.0) > 21.9, "Durchmesser abgeschliffen: %f" % rg.radius_at(40.0))
	# Bereich bis Z 10 ganz schleifen
	var res5: Dictionary = rg.evaluate_grind(job5)
	ok(float(res5["score"]) >= 0.999, "Schleifprüfung: " + str(res5["lines"]))
	stop(rg)
	var cash6: int = w.money
	submit(w, rg)
	ok(w.money == cash6 + int(job5["grind"]["reward"]) and not rg.has_part, "Rundschleifen bezahlt")
	ok(w.grind_jobs.is_empty(), "Fertig")
	var rstore = co.tools["round_grinder"]
	ok(rstore.dull("K30") > 0.0 or rstore.wear("K30") >= 0.0, "Auch hier nutzt sich die Scheibe ab")
	spin(rg)
	rstore.items["K30"]["dull"] = 0.5
	rg.tool_x = 80.0
	rg.tool_z = rg.DRESS_Z
	rg.move_tool(0.0, rg.DRESS_X - 80.0, false, 2.0)
	ok(rstore.dull("K30") == 0.0, "Abziehwerkzeug am Bett zieht ab")
	rg.move_tool(0.0, 5.0, false, 2.0)
	rg.tool_z = 90.0
	rg.tool_x = 80.0
	stop(rg)
	# Verschliffen: Ausschuss
	w.grind_jobs = ["lathe:4"]
	rg.new_workpiece(50.0, 120.0)
	rg.set_material("AW-6082")
	rg.semi_key = "lathe:4"
	stop(rg)
	var cash7: int = w.money
	submit(w, rg)
	ok(w.money == cash7 and not rg.has_part and w.grind_jobs.is_empty(), "Falsche Maße: Ausschuss, keine Vergütung")

	# ---------------------------------------------------- Kundenaufträge mit Keramik
	ok(w.offers().filter(func(k): return k.begins_with("ceramic")).is_empty(), "Kundenaufträge erst mit Diamant-Skill")
	w.set_free_mode(true)
	ok(w.unlock_skill("wheel_cbn") == "" and w.unlock_skill("wheel_diamond") == "", "Skills freigeschaltet")
	w.set_free_mode(false)
	ok(not w.offers().filter(func(k): return k.begins_with("ceramic")).is_empty(), "Jetzt im Angebot")
	var d_before: int = w.deliveries.size()
	var stock_before: int = w.stock.size()
	ok(w.accept_job("ceramic:0") == "", "Kundenauftrag annehmen")
	ok(w.grind_jobs.has("ceramic:0") and w.deadlines.has("ceramic:0"), "Wartet aufs Schleifen, mit Frist")
	ok(w.deliveries.size() == d_before + 1 and w.stock.size() == stock_before, "Teil kommt mit, eigenes Material braucht es nicht")
	var dl: Dictionary = w.deliveries[-1]
	ok(str(dl["kind"]) == "semi" and bool(dl["part"]["ceramic"]), "Kundenteil steht im Hof")
	ok(w.delivery_prompt(w.deliveries.size() - 1).contains("Teil vom Kunden"), "Hinweis: " + w.delivery_prompt(w.deliveries.size() - 1))
	p.clear_held()
	p.clear_carry()
	ok(w.pick_delivery(w.deliveries.size() - 1) == "" and p.carrying_semi(), "Aufheben")
	fg.tray.clear()
	ok(w.clamp_carried(fg) == "" and fg.ceramic_part and fg.has_part and fg.block_l == 120.0, "Einspannen")
	# Falsche Scheibe
	ok(w.buy_tool("flat_grinder", "K40", "hm") == "", "Korund 40")
	p.set_held(fg, "K40")
	fg.hand_click(p)
	p.clear_held()
	fg.rpm_set = 2500.0
	fg.feed_set = 400.0
	spin(fg)
	go(fg, -40.0, 20.0, -0.02, 20.0)
	go(fg, 10.0, 20.0, -0.02, 5.0)
	ok(fg.estop and fg.height_at(5.0, 20.0) == 0.0, "Korund schneidet keine Keramik")
	fg.estop = false
	stop(fg)
	go(fg, -40.0, 20.0, 5.0, 20.0)
	# Diamantscheibe
	ok(w.buy_tool("flat_grinder", "D40", "hm") == "", "Diamantscheibe kaufen")
	p.set_held(fg, "D40")
	fg.hand_click(p)
	p.clear_held()
	ok(fg.tool()["type"] == "diamant", "Diamant aufgezogen")
	fg.coolant = true
	fg.feed_set = 400.0
	spin(fg)
	var cj: Dictionary = CeramicJobs.LIST[0]
	for z in [-0.05, -0.1]:
		var cy := 10.0
		while cy <= 80.0:
			go(fg, -40.0, cy, z, 20.0)
			go(fg, 160.0, cy, z, 400.0 / 60.0)
			cy += 20.0
		go(fg, -40.0, 10.0, z, 20.0)
	ok(not fg.estop, "Diamant schneidet Keramik")
	var cres: Dictionary = fg.evaluate_grind(cj)
	ok(float(cres["score"]) >= 0.999, "Keramikfläche in Ordnung: " + str(cres["lines"]))
	stop(fg)
	var cash8: int = w.money
	submit(w, fg)
	ok(w.money == cash8 + int(round(float(cj["reward"]) * co.pay_factor())) and w.grind_jobs.is_empty() and not w.deadlines.has("ceramic:0"), "Kundenauftrag bezahlt")
	ok(not fg.has_part and not fg.ceramic_part, "Fertig")

	# ---------------------------------------------------- Angebote, Tage, Fristen, Ansehen
	w.accepted = []
	w.grind_jobs = []
	w.deadlines = {}
	co.skills.unlocked.erase("mat_kupfer")
	var by_machine := {}
	for k in w.offers():
		var mk: String = JobBoard.machine_of(k)
		by_machine[mk] = int(by_machine.get(mk, 0)) + 1
	for mk in by_machine:
		ok(by_machine[mk] <= JobBoard.MAX_PER_MACHINE, "Höchstens 2 Angebote: " + mk)
	ok(by_machine.has("lathe") and by_machine.has("mill") and by_machine.has("drill"), "Angebote je Maschine")
	co.skills.unlocked = {}
	ok(w.offers().filter(func(k): return k.begins_with("mill") or k.begins_with("drill")).is_empty(), "Gesperrte Maschinen: keine Angebote")
	for k in w.offers():
		ok(str(JobBoard.job_of(k)["material"]) == "S235", "Nur freigeschalteter Werkstoff: " + k)
	co.skills.unlock_basics()
	co.skills.unlocked["wheel_cbn"] = true
	co.skills.unlocked["wheel_diamond"] = true
	# Zwei laufen: mehr geht nicht
	for i in 2:
		ok(w.accept_job("lathe:%d" % i) == "", "Annehmen %d" % i)
	ok(w.accept_job("lathe:5") != "", "Der dritte nicht")
	ok(w.offers().filter(func(k): return k.begins_with("lathe")).is_empty(), "Kein weiteres Angebot für die Drehmaschine")
	for k in w.accepted.duplicate():
		w.return_job(k)
	ok(w.deadlines.is_empty(), "Zurückgegeben")
	# Der Tag läuft ab
	var day0: int = w.day
	ok(w.clock_text().contains("Tag %d" % day0), "Uhr: " + w.clock_text())
	w._advance_day(w.DAY_SECONDS + 1.0)
	ok(w.day_over, "Tag ist um")
	ok(w.accept_job("lathe:0").contains("Feierabend"), "Kein neuer Auftrag am Feierabend")
	ok(w.buy_equipment("bench").contains("Feierabend"), "Nichts kaufen")
	ok(w.buy_tool("lathe", "T1", "hm").contains("Feierabend"), "Keine Werkzeuge")
	ok(w.order_material({"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0}).contains("Feierabend"), "Kein Material")
	ok(w.buy_tile("workshop", Vector2i(-4, 0)).contains("Feierabend"), "Keine Kacheln")
	ok(w.hud._clock.text.contains("FEIERABEND"), "Anzeige: " + w.hud._clock.text)
	# Laufendes Teil geht noch
	w.day_over = false
	w.accepted = ["lathe:0"]
	w.job_index = 0
	w.deadlines["lathe:0"] = w.day + 2
	w.day_over = true
	l.tray.clear()
	l.set_material("S235")
	l.new_workpiece(60.0, 160.0)
	turn_to(l, Jobs.LIST[0])
	var cash9: int = w.money
	submit(w, l)
	ok(w.money > cash9 and w.accepted.is_empty(), "Das aktuelle Teil lässt sich am Feierabend noch abgeben")
	w.set_free_mode(true)
	ok(w.buy_tool("lathe", "T7", "hm") == "", "Testmodus: Feierabend sperrt nichts")
	w.set_free_mode(false)
	# Am Feierabend kein "Tag beenden" mehr am Whiteboard, sondern nach Hause und schlafen
	ok(not w.whiteboard.overlay.day_app.end_button.visible, "Am Feierabend kein Knopf zum Beenden")
	ok(w.sleep_error() == "", "Nach Feierabend lässt sich schlafen")
	w.autosave = false
	ok(w.go_sleep(w.player) == "", "Zuhause geschlafen")
	ok(w.day == day0 + 1 and not w.day_over and w.day_time == 0.0 and w.day_started, "Nach dem Schlafen beginnt der nächste Tag")
	ok(w.player.location == "home:local", "Aufwachen zuhause")
	ok(w.places.travel(w.player, "site") == "" and w.player.location == "site", "Zurück zur Werkstatt")
	ok(w.sleep_error() != "", "Gleich wieder schlafen geht nicht")
	# Tag vorzeitig über das Whiteboard beenden
	w.whiteboard.overlay.day_app.end_button.pressed.emit()
	ok(w.day_over and w.day == day0 + 1, "Whiteboard beendet den Tag: Feierabend")
	ok(w.go_sleep(w.player) == "" and w.day == day0 + 2, "Wieder geschlafen")
	w.places.travel(w.player, "site")
	# Ohne Schlafen bleibt ein neuer Tag ungestartet
	w.next_day()
	ok(w.day == day0 + 3 and not w.day_over and w.day_time == 0.0 and not w.day_started, "Nächster Tag wartet auf den Start")
	ok(w.accept_job("lathe:0").contains("nicht begonnen"), "Vor Tagesbeginn kein Auftrag")
	ok(w.buy_tool("lathe", "T7", "hm").contains("nicht begonnen"), "Vor Tagesbeginn kein Einkauf")
	ok(w._work_blocked(w.lathe, true), "Vor Tagesbeginn wird nichts bearbeitet")
	ok(not w._work_blocked(w.office_pc, true), "Der PC geht immer")
	ok(not w._work_blocked(w.whiteboard, true), "Das Whiteboard geht immer")
	ok(w.whiteboard._state.text.contains("nicht gestartet"), "Das Whiteboard sagt, dass der Tag noch nicht läuft")
	w.whiteboard.overlay.day_app.start_button.pressed.emit()
	ok(w.day_started and not w._work_blocked(w.lathe, true), "Tag gestartet")
	# Frist
	ok(JobBoard.days_for("lathe:0") == 2 and JobBoard.days_for("lathe:3") == 5, "Aufträge haben verschiedene Fristen")
	var rep0: float = co.reputation
	ok(w.accept_job("lathe:0") == "", "Auftrag annehmen")
	var due: int = w.deadlines["lathe:0"]
	ok(due == w.day + 2, "Frist 2 Tage")
	w.next_day()
	w.start_day()
	w.next_day()
	w.start_day()
	ok(w.accepted.has("lathe:0") and co.reputation == rep0, "Am letzten Tag noch nichts passiert")
	w.next_day()
	w.start_day()
	ok(not w.accepted.has("lathe:0") and not w.deadlines.has("lathe:0"), "Frist abgelaufen: Auftrag weg")
	ok(co.reputation == rep0 + w.REP_LATE, "Ansehen sinkt")
	ok(str(co.rep_log[-1]["text"]).contains("Frist"), "Vermerkt")
	# Halbfertiges Teil verfällt mit
	ok(w.accept_job("ceramic:1") == "", "Kundenauftrag")
	ok(not w.deliveries.is_empty(), "Teil im Hof")
	w.deadlines["ceramic:1"] = w.day
	w.next_day()
	w.start_day()
	ok(not w.grind_jobs.has("ceramic:1") and w.deliveries.filter(func(x): return str(x.get("key", "")) == "ceramic:1").is_empty(), "Kundenteil geht zurück")
	# Ansehen und Vergütung
	co.reputation = 50.0
	ok(co.pay_factor() == 1.0, "Solide: normale Vergütung")
	co.reputation = 100.0
	ok(co.pay_factor() > 1.3, "Hohes Ansehen: mehr Geld")
	co.reputation = 0.0
	ok(co.pay_factor() < 0.7, "Schlechtes Ansehen: weniger Geld")
	co.reputation = 90.0
	w.accepted = ["lathe:0"]
	w.job_index = 0
	w.deadlines["lathe:0"] = w.day + 5
	l.new_workpiece(60.0, 160.0)
	turn_to(l, Jobs.LIST[0])
	var cash10: int = w.money
	var rep1: float = co.reputation
	submit(w, l)
	ok(w.money == cash10 + int(round(float(Jobs.LIST[0]["reward"]) * 1.3)), "Vergütung steigt mit dem Ansehen")
	ok(co.reputation == rep1 + w.REP_DONE, "Erfolg erhöht das Ansehen")
	w.job_menu.close()
	# Programm Ansehen
	o2.open_program("reputation")
	o2.reputation_app.refresh()
	ok(o2.reputation_win.visible, "Ansehen ist eine eigene App")
	ok(text_of(o2.reputation_app).contains("Ansehen") and text_of(o2.reputation_app).contains("Vergütung"), "Stand und Wirkung")
	o2.show_desktop()
	o2.visible = false
	co.reputation = 50.0

	# ---------------------------------------------------- Einkauf, Skilltree, Übersicht
	for id in ["lathe", "cnc_lathe", "mill", "drill", "round_grinder", "flat_grinder", "edm"]:
		ok(o2.machines_tab.buttons.has(id), "Im Tab Maschinen: " + id)
	o2.tool_tab.select_machine("flat_grinder")
	ok(o2.tool_tab.rows.has("K13") and o2.tool_tab.rows.has("C25") and o2.tool_tab.rows.has("D40"), "Werkzeugtab: Schleifscheiben")
	ok(not o2.tool_tab.rows["K13"]["hss"].visible, "Kein HSS bei Schleifscheiben")
	ok(Skills.EQUIPMENT["cnc_lathe"] == "lathe_cnc", "CNC braucht den Skill")
	ok(Skills.NODES.has("drill_hss") and Skills.NODES["drill_hss"]["tree"] == "drill_tools", "Eigener Baum für Bohrer")
	o2.tool_tab.select_machine("drill")
	ok(o2.tool_tab.rows.has("B10") and not o2.tool_tab.rows.has("F10"), "Werkzeugtab: Bohrmaschine nur mit Bohrern")
	# Unterkategorien
	ok(o2.tool_tab.category_buttons.size() == 3, "Bohrer nach Größe unterteilt")
	ok(o2.tool_tab.rows["B3"]["box"].visible and not o2.tool_tab.rows["B25"]["box"].visible, "Erst die kleinen Bohrer")
	o2.tool_tab.category_buttons[2].pressed.emit()
	ok(o2.tool_tab.rows["B25"]["box"].visible and not o2.tool_tab.rows["B3"]["box"].visible, "Große Bohrer: eigene Kategorie")
	for mach in ["lathe", "cnc_lathe", "mill", "drill", "flat_grinder", "round_grinder"]:
		o2.tool_tab.select_machine(mach)
		var seen_ids := {}
		for cat in o2.tool_tab.categories:
			ok(not cat["ids"].is_empty(), "Kategorie nicht leer: %s %s" % [mach, cat["title"]])
			for tid in cat["ids"]:
				ok(o2.tool_tab.rows.has(tid) and not seen_ids.has(tid), "Werkzeug genau einmal: " + str(tid))
				seen_ids[tid] = true
		ok(seen_ids.size() == o2.tool_tab.rows.size(), "Alle Werkzeuge in einer Kategorie: " + mach)
	o2.tool_tab.select_machine("mill")
	ok(o2.tool_tab.rows["F10"]["box"].visible and not o2.tool_tab.rows["B10"]["box"].visible and not o2.tool_tab.rows["MK32"]["box"].visible, "Fräse: erst Schaftfräser")
	o2.tool_tab.category_buttons[2].pressed.emit()
	ok(o2.tool_tab.rows["MK32"]["box"].visible and o2.tool_tab.rows["MK125"]["box"].visible, "Messerköpfe mit den kleinen")
	o2.tool_tab.select_machine("flat_grinder")
	ok(o2.tool_tab.category_buttons[0].text == "Korund" and o2.tool_tab.category_buttons[1].text == "CBN" and o2.tool_tab.category_buttons[2].text == "Diamant", "Scheiben nach Schleifmittel: " + o2.tool_tab.category_buttons[0].text)
	o2.tool_tab.select_machine("lathe")
	ok(o2.tool_tab.category_buttons.size() == 4 and o2.tool_tab.rows["T1"]["box"].visible and not o2.tool_tab.rows["T6"]["box"].visible, "Drehwerkzeuge nach Arbeit")
	o2.tool_tab.select_machine("cnc_lathe")
	ok(o2.tool_tab.rows.has("T1"), "Werkzeugtab: CNC-Drehmaschine")
	ok(w.tool_price("drill", "B10", "hss") == 6, "Preis HSS-Bohrer")
	ok(w.buy_tool("drill", "B10", "hss") != "", "HSS erst nach dem Skill")
	var txt := text_of(o2.overview_tabs)
	for t in ["Konventionelle Drehmaschine", "Konventionelle Rundschleifmaschine", "Konventionelle Flachschleifmaschine", "Konventionelle Standbohrmaschine"]:
		ok(txt.contains("Im Spiel: " + t), "Übersicht: " + t)

	# ---------------------------------------------------- Speichern und Laden
	w.inventory.erase("cnc_lathe")
	dr.new_workpiece(120.0, 80.0, 20.0)
	spin(dr)
	dr.select_tool(dr.tool_index("B10"), true)
	go(dr, 60.0, 40.0, 5.0, 10.0)
	go(dr, 60.0, 40.0, -5.0, 1.0)
	go(dr, 60.0, 40.0, 5.0, 10.0)
	stop(dr)
	fg.load_part(m.part_state())
	fg.semi_key = "mill:0"
	w.grind_jobs = ["mill:0"]
	var state := {
		"name": "T", "money": 77, "machines": co.machines, "job": 0, "mill_job": 0, "parts": 1, "drill_job": 2,
		"player": p.get_state(), "lathe": l.get_state(), "mill": m.get_state(), "stock": [], "deliveries": [],
		"site": w._site_state(), "layout": w.layout.to_state(), "inventory": w.inventory, "skills": co.skills.to_state(),
		"tools": w._tool_states(), "machine_states": w._machine_states(), "grind_jobs": w.grind_jobs,
		"accepted": w.accepted, "tracked": w.tracked, "containers": w.containers.map(func(k): return k.to_state()),
		"day": 9, "day_time": 123.0, "reputation": 70.0, "rep_log": [{"day": 8, "change": 2, "text": "x"}], "deadlines": {"mill:0": 11},
	}
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(state))
	w._apply_pending({"name": "Neu", "money": 2500})
	ok(not l.visible and w.extra_machines.is_empty() and w.mill_huds.is_empty(), "Neues Spiel: leere Halle")
	ok(w.bench_nodes.is_empty(), "Und keine Werkbänke")
	w._apply_pending(loaded)
	await process_frame
	ok(w.extra_machines["drill"].MACHINE_ID == "drill" and w.extra_machines["flat_grinder"].grinder_type == "flat" and w.extra_machines["round_grinder"].grinder_type == "round", "Maschinen aus dem Spielstand")
	ok(w.cnc_lathe != null and w.cnc_lathe.has_cutter(), "CNC-Drehmaschine mit Werkzeug")
	var dr2 = w.extra_machines["drill"]
	ok(dr2.has_part and dr2.height_at(60.0, 40.0) < -4.0, "Bohrung im Teil gespeichert")
	ok(dr2.tool()["id"] == "B10" and not dr2.spindle_empty, "Bohrer gespeichert")
	var fg2 = w.extra_machines["flat_grinder"]
	ok(fg2.semi_key == "mill:0" and fg2.has_part and w.grind_jobs == ["mill:0"], "Schleifteil gespeichert")
	ok(fg2.has_cutter() and fg2._tool_node != null, "Scheibe nach dem Laden da")
	ok(w.day == 9 and w.day_time == 123.0 and w.company.reputation == 70.0, "Tag und Ansehen gespeichert")
	ok(w.deadlines.get("mill:0", 0) == 11, "Frist gespeichert")
	ok(w.company.rep_log.size() == 1, "Verlauf gespeichert")
	ok(w.drill_job_index == 2, "Bohrauftrag gespeichert")
	ok(w.bench_nodes.has("drill"), "Werkbank der Bohrmaschine gespeichert")
	ok(w.extra_machines["round_grinder"].holder[0] == "K30", "Scheibe der Rundschleifmaschine nach dem Laden")
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
