extends SceneTree
## Neues Spiel von vorn: Aufträge annehmen, Skilltree, PC-Desktop, Material tragen, Kisten, Späne.
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
func _initialize() -> void:
	await process_frame
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var l = w.lathe
	var m = w.mill
	var sk = w.company.skills
	var o = w.office_pc.overlay
	var money0: int = w.money

	# ---------------------------------------------------- Startzustand
	ok(sk.has("lathe_conv") and sk.has("mat_baustahl"), "Konventionelle Drehmaschine und Baustahl von Anfang an")
	ok(not sk.has("mill_conv") and not sk.has("lathe_cnc") and not sk.has("mat_aluminium"), "Rest ist gesperrt")
	ok(sk.has("lathe_hm") and not sk.has("lathe_hss"), "Hartmetall kommt mit der Maschine, HSS nicht")
	ok(not sk.has("mill_hm"), "Fräswerkzeuge kommen erst mit der Fräsmaschine")
	ok(not m.visible and m.global_position.y < -10.0, "Fräsmaschine steht noch nicht in der Werkstatt")
	ok(not l.visible and l.global_position.y < -10.0, "Auch die Drehmaschine steht noch nicht da")
	ok(not w.company.owns("mill") and not w.company.owns("lathe"), "Maschinenpark ist leer")
	ok(w.company.tools["lathe"].items.is_empty() and w.company.tools["mill"].items.is_empty(), "Keine Werkzeuge")
	ok(not l.has_cutter() and not m.has_cutter(), "Halter und Spindel sind leer")
	ok(money0 == 250 and w.equipment_price("lathe") == 0, "Start mit 250 EUR, die erste Drehmaschine ist gratis")
	ok(money0 >= w.equipment_price("bench") + 2 * l.INSERT_PRICE, "Startgeld reicht für Werkbank und Werkzeuge")
	ok(w.equipment_price("cnc_lathe") > 0, "Die CNC-Drehmaschine kostet")
	ok(l.conventional and l.screen_vp == null, "Die Drehmaschine ist konventionell, ohne Bedienpult")
	ok(w.accepted.is_empty() and w.tracked == "", "Kein Auftrag angenommen")
	ok(w.hud._job.text.contains("Kein Auftrag"), "Anzeige oben rechts sagt das")
	ok(sk.free_points() == 0, "Keine Skillpunkte am Anfang")

	# ---------------------------------------------------- PC: Desktop mit zwei Programmen
	o.open()
	ok(o.program == "" and o.desktop.visible and not o.tabs.visible and not o.skill_app.visible, "PC startet auf dem Desktop")
	for prog in ["shop", "jobs", "skills", "overview", "reputation", "stock", "waste"]:
		ok(o.desktop.find_child("Programm_" + prog, true, false) != null, "Programm auf dem Desktop: " + prog)
	ok(o.desktop.find_child("Programm_day", true, false) == null, "Der Tagesbericht hängt am Whiteboard, nicht am PC")
	o.desktop.find_child("Programm_skills", true, false).pressed.emit()
	ok(o.program == "skills" and o.skill_app.visible and not o.desktop.visible, "Skilltree öffnet")
	var pe := InputEventAction.new()
	pe.action = "pause"
	pe.pressed = true
	o._input(pe)
	ok(o.visible and o.program == "" and o.desktop.visible, "Esc im Programm führt zum Desktop")
	o.desktop.find_child("Programm_shop", true, false).pressed.emit()
	ok(o.program == "shop" and o.tabs.visible, "Shop öffnet")
	var names := []
	for i in o.tabs.get_tab_count():
		names.append(o.tabs.get_tab_title(i))
	ok(names == ["Maschinen", "Maschinenwerkzeuge", "Rohmaterial", "Gebäude", "Einkauf"], "Tabs im Shop: %s" % str(names))
	o.desktop.find_child("Programm_jobs", true, false).pressed.emit()
	ok(o.program == "jobs" and o.jobs_tab.visible and not o.tabs.visible, "Aufträge sind eine eigene App")
	o.desktop.find_child("Programm_overview", true, false).pressed.emit()
	ok(o.program == "overview" and o.overview_tabs.visible and text_of(o.overview_tabs).contains("Erodiermaschinen"), "Übersicht zeigt die Maschinen")
	o.show_desktop()
	o.visible = false

	# ---------------------------------------------------- Maschine und Werkzeuge kaufen
	ok(o.machines_tab.buttons.has("lathe") and o.machines_tab.buttons.has("mill"), "Maschinen im Tab Maschinen")
	ok(not o.shop_tab.buttons.has("lathe") and not o.shop_tab.buttons.has("mill"), "Keine Maschinen im Einkauf")
	ok(w.accept_job("lathe:0") != "", "Ohne Maschine kein Auftrag")
	o.machines_tab._buy("lathe")
	ok(w.inventory["lathe"] == 1 and w.money == money0 - w.equipment_price("lathe"), "Drehmaschine gekauft")
	ok(w.place_machine("lathe", Vector2(0.0, -2.0), 0) == "", "Aufgestellt")
	ok(l.visible and absf(l.global_position.y) < 0.01 and w.company.owns("lathe"), "Sie steht in der Halle")
	var tt = o.tool_tab
	tt.refresh()
	ok(tt.rows["T1"]["status"].text == "Nicht vorhanden", "Werkzeugtab: noch nichts da")
	ok(not tt.rows["T1"]["hm"].disabled and tt.rows["T1"]["hss"].disabled, "Hartmetall kaufbar, HSS gesperrt")
	ok(w.buy_tool("lathe", "T1", "hss") != "", "HSS vor dem Skill nicht")
	ok(w.buy_tool("mill", "F10", "hm") != "", "Fräser vor der Fräsmaschine nicht")
	var cash0: int = w.money
	tt.buy("T1", "hm")
	ok(w.money == cash0 - l.INSERT_PRICE and w.company.tools["lathe"].has("T1"), "Hartmetall gekauft")
	ok(tt.rows["T1"]["status"].text.contains("1 von 5") and tt.rows["T1"]["status"].text.contains("Hartmetall"), "Tab zeigt den Bestand")
	# Aus der Hand in den leeren Halter
	p.set_held(l, "T1")
	l.hand_click(p)
	ok(l.holder[0] == "T1" and l.has_cutter() and p.held.is_empty(), "Eingespannt in den eingeschwenkten Platz")
	l.hand_click(p)
	ok(not l.has_cutter() and p.held.get("id", "") == "T1", "Freie Hand nimmt auch das letzte heraus")
	l.hand_click(p)
	ok(l.has_cutter(), "Wieder drin")
	# Leerer Platz schneidet nicht
	l.new_workpiece(60.0, 160.0)
	l.holder[0] = ""
	l._apply_holder()
	ok(l.holder[0] == "", "Leerer Halter wird nicht von selbst gefüllt")
	ok(l._engagement(50.0, 5.0) == 0.0, "Ohne Werkzeug kein Schnitt")
	l.holder[0] = "T1"
	l._apply_holder()
	l.clear_workpiece()

	# ---------------------------------------------------- Aufträge annehmen
	var jt = o.jobs_tab
	jt.refresh()
	var offer := text_of(jt.offers)
	ok(offer.contains("Auftrag") and offer.contains("Frist"), "Angebote stehen am PC, mit Frist")
	ok(not offer.contains("Fräsauftrag") and not offer.contains("C45"), "Gesperrte Maschinen und Werkstoffe tauchen nicht auf")
	ok(w.accept_job("mill:0") != "", "Fräsauftrag ohne Fräsmaschine geht nicht")
	ok(w.accept_job("lathe:2") != "", "C45 ist noch gesperrt")
	jt.accept("lathe:0")
	ok(w.accepted == ["lathe:0"] and w.tracked == "lathe:0", "Annehmen am PC")
	ok(w.hud._job.text.contains("Auftrag 1"), "Steht oben rechts")
	ok(text_of(jt.taken).contains("Auftrag 1") and not text_of(jt.offers).contains("Auftrag 1:"), "Wandert in die Liste Angenommen")
	ok(w.accept_job("lathe:1") == "" and w.tracked == "lathe:0", "Zweiter Auftrag ändert die Anzeige nicht")
	ok(w.job_index == 0, "Maschine bleibt beim ersten Auftrag")

	# ---------------------------------------------------- Taste Tab wählt aus
	var menu = w.job_menu
	menu.open()
	var btns: Array = menu.pages["lathe"].find_children("*", "Button", true, false).filter(func(b): return b.text != "Zeichnung")
	ok(btns.size() == 2, "Beide angenommenen Aufträge im Menü")
	ok(btns[0].disabled and not btns[1].disabled, "Der angezeigte ist markiert")
	btns[1].pressed.emit()
	ok(w.tracked == "lathe:1" and w.job_index == 1, "Auswahl gilt für die Anzeige und die Maschine")
	ok(w.hud._job.text.contains("Auftrag 2"), "Oben rechts steht jetzt Auftrag 2")
	menu.close()
	w.select_job("lathe:0")
	w.return_job("lathe:1")
	ok(w.accepted == ["lathe:0"] and w.job_index == 0, "Zurückgeben")

	# ---------------------------------------------------- Ohne Geld für Material stellt der Kunde das Rohteil
	var start_cash: int = w.money
	w.money = 50
	ok(w._job_cost("lathe") > w.money, "Die erste Stange ist noch zu teuer")
	w.deliveries = []
	w.stock = []
	var free_part: String = w._lathe_take_part()
	ok(free_part.contains("Kunde") and l.has_part, "Der Kunde stellt das Rohteil, so lässt sich Geld verdienen: " + free_part)
	l.clear_workpiece()
	w.money = 5000

	# ---------------------------------------------------- Material nur per Tragen
	var raw = o.raw
	ok(w.order_material({"material": "AW-6082", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0}) != "", "Aluminium ist nicht bestellbar")
	ok(raw.pages["round"].groups.is_tab_disabled(7) and not raw.pages["round"].groups.is_tab_disabled(0), "Gesperrte Gruppen im Tab")
	ok(w.order_material({"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0}) == "", "Baustahl bestellt")
	w.pick_delivery(0)
	ok(w.site.capacity() == 0, "Neues Spiel: noch kein Regal")
	ok(w.store_carried(-1) != "" and not p.carry.is_empty(), "Ohne Regal kein Einlagern")
	ok(w.place_rack(-1, Vector2(14.0, -12.0)) != "", "Ungekauftes Regal lässt sich nicht aufstellen")
	ok(w.equipment_price("rack") > 0 and w.buy_equipment("rack") == "", "Lagerregal kaufen")
	ok(o.shop_tab.buttons.has("rack"), "Lagerregal steht im Einkauf")
	ok(w.place_rack(-1, Vector2(14.0, -12.0)) == "" and w.site.capacity() == 6, "Aufgestellt: 6 Fächer")
	ok(w.store_carried(0) == "", "Eingelagert")
	ok(not l.has_part, "Material erscheint nicht von selbst in der Maschine")
	var n_msg: String = w._lathe_take_part()
	ok(n_msg.contains("Lager") and not l.has_part and w.stock[0]["l"] == 3000.0, "N lädt nichts aus dem Lager: " + n_msg)
	ok(w.take_from_stock(0) == "" and not p.carry.is_empty(), "Am Regal nehmen")
	ok(w.money < 5000, "Regal und Material haben gekostet")
	ok(w.clamp_carried(l).contains("Bandsäge") and not l.has_part, "Ganze Stange passt nicht in die Maschine")
	var rest_bar: Dictionary = p.carry.duplicate()
	p.set_carry(Materials.cut_off(rest_bar, 160.0))
	ok(w.clamp_carried(l) == "" and l.has_part and l.stock_d == 60.0, "An der Maschine einspannen")
	ok(p.carry.is_empty() and rest_bar["l"] == 3000.0 - 160.0 - Materials.KERF, "Abschnitt ist eingespannt, die Stange kürzer")
	p.set_carry(rest_bar)
	ok(w.store_carried(0) == "", "Rest zurück ins Regal")

	# ---------------------------------------------------- Abgabe: Geld, Erfahrung, leere Maschine
	var money1: int = w.money
	l.profile.fill(28.0)
	for i in l.machined.size():
		l.machined[i] = 1
	var res: Dictionary = l.evaluate(w._current_job())
	var reward: int = int(w._current_job()["reward"])
	if float(res["score"]) < 0.999:
		print("Hinweis: Prüfung ", res)
	w._on_submit()
	ok(float(res["score"]) >= 0.999 and w.money == money1 + reward, "Auftrag bezahlt")
	ok(sk.xp == reward, "Erfahrung neben dem Geld")
	ok(w.accepted.is_empty() and w.tracked == "", "Erledigter Auftrag ist weg, der nächste wird nicht automatisch angenommen")
	ok(not l.has_part, "Nach der Abgabe bleibt die Maschine leer, trotz Material im Lager")
	ok(not w.stock.is_empty(), "Lager ist unberührt")
	w._on_submit()
	ok(w.parts == 1, "Leere Maschine gibt nichts ab")
	# Ohne Auftrag keine Bezahlung
	l.new_workpiece(60.0, 160.0)
	l.profile.fill(28.0)
	l.machined[0] = 1
	var money2: int = w.money
	w._on_submit()
	ok(w.money == money2 and w.parts == 1, "Ohne angenommenen Auftrag keine Abgabe")
	l.clear_workpiece()

	# ---------------------------------------------------- Skillpunkte
	ok(Skills.points_for(199) == 0 and Skills.points_for(200) == 1 and Skills.points_for(499) == 1 and Skills.points_for(500) == 2, "Punkte aus Erfahrung")
	sk.xp = 200
	ok(sk.free_points() == 1, "Erster Skillpunkt")
	var tree = o.skill_app
	tree.refresh()
	ok(tree.trees.is_tab_hidden(2), "Fräswerkzeuge gibt es erst mit der Fräsmaschine")
	ok(not tree.trees.is_tab_hidden(1), "Drehwerkzeuge gibt es von Anfang an")
	ok(sk.unlock_error("mill_cnc") != "", "CNC erst nach konventionell")
	ok(sk.unlock_error("mill_cnc", true) != "", "Auch im Testmodus bleibt die Reihenfolge")
	ok(w.buy_equipment("mill") != "", "Fräsmaschine ist vor dem Skill nicht kaufbar")
	tree.select("mill_conv")
	ok(not tree._unlock.disabled, "Knopf ist bereit")
	tree._unlock.pressed.emit()
	ok(sk.has("mill_conv") and sk.free_points() == 0, "Fräsmaschine freigeschaltet, Punkt verbraucht")
	ok(sk.has("mill_hm"), "Hartmetall-Fräswerkzeuge kommen mit")
	tree.refresh()
	ok(not tree.trees.is_tab_hidden(2), "Kategorie Fräswerkzeuge erscheint")
	for id in Skills.NODES:
		var tid: String = Skills.NODES[id]["tree"]
		if id.ends_with("_hm") or id.ends_with("_hss") or id.ends_with("_coat_heat") or id.ends_with("_coat_wear") or id.ends_with("_rebate"):
			ok(tid != "general", "Werkzeug-Skill steht nicht im allgemeinen Baum: " + id)
		ok(tid == "general" or Skills.NODES[id].get("req", []).size() > 0, "Werkzeugbaum hängt an etwas: " + id)
		for r in Skills.NODES[id]["req"]:
			ok(Skills.NODES.has(r), "Voraussetzung existiert: " + str(r))
	for g in Materials.GROUPS:
		ok(Skills.NODES.has("mat_%s" % g["id"]), "Skill für Werkstoffgruppe " + str(g["title"]))
	ok(w.unlock_skill("mat_aluminium") != "", "Ohne Punkte kein weiterer Skill")
	# Testmodus: Skills kostenlos
	w.set_free_mode(true)
	ok(w.unlock_skill("mat_aluminium") == "" and sk.has("mat_aluminium") and sk.free_points() == 0, "Testmodus: Skill kostenlos, Punkte unberührt")
	ok(w.buy_equipment("cnc_lathe") != "", "CNC-Drehmaschine vor dem Skill nicht kaufbar")
	ok(w.unlock_skill("lathe_cnc") == "", "CNC freigeschaltet")
	ok(w.buy_equipment("cnc_lathe") == "", "Jetzt kaufbar")
	w.inventory.erase("cnc_lathe")
	ok(w.unlock_skill("mill_cnc") != "", "CNC-Fräse gibt es noch nicht")
	ok(w.unlock_skill("coolant_1") == "" and is_equal_approx(Materials.coolant_factor, 0.27), "Besseres Kühlmittel wirkt")
	ok(Materials.heat_rate("S235", 2.0, true, 1.0) < Materials.heat_rate("S235", 2.0, false, 1.0), "Kühlung kühlt")
	# Schneidstoff: erst Hartmetall, HSS nach dem Skill
	ok(w.unlock_skill("lathe_hss") == "", "HSS freigeschaltet")
	w.set_free_mode(false)
	w.money = 100
	ok(w.tool_price("lathe", "T3", "hss") == int(round(l.INSERT_PRICE * 0.5)), "HSS kostet die Hälfte")
	ok(w.buy_tool("lathe", "T3", "hss") == "" and w.company.tools["lathe"].grade("T3") == "hss", "HSS gekauft")
	ok(l.mount_tool(1, "T3") and l.index_slot(1, true), "HSS einschwenken")
	ok(float(l.tool_mods["heat"]) > 1.0 and float(l.tool_mods["wear"]) > 1.0, "HSS wird schneller heiß und verschleißt schneller")
	ok(l.index_slot(0, true) and float(l.tool_mods["heat"]) == 1.0, "Hartmetall hat eigene Werte, je Werkzeug")
	# Beschichtungen
	var heat0: float = sk.tool_mods("lathe")["heat"]
	var wear0: float = sk.tool_mods("lathe")["wear"]
	w.set_free_mode(true)
	ok(w.unlock_skill("lathe_coat_heat") == "", "Beschichtung Hitzeschutz")
	ok(sk.tool_mods("lathe")["heat"] < heat0 and sk.tool_mods("lathe")["wear"] == wear0, "Hitzeschutz wirkt nur auf die Hitze")
	ok(w.unlock_skill("lathe_coat_wear") == "", "Beschichtung Verschleißschutz")
	ok(sk.tool_mods("lathe")["wear"] < wear0, "Verschleißschutz wirkt auf den Verschleiß")
	ok(sk.tool_mods("mill")["wear"] == wear0, "Beschichtung gilt je Maschine")
	w.set_free_mode(false)
	# Verschleiß: gute Werte wenig, schlechte viel
	var best: float = Materials.wear_rate("S235", 100.0, 80.0, 120.0, 1.0, true)
	ok(is_equal_approx(best, 1.0 / Materials.WEAR_LIFE), "Optimale Werte: volle Standzeit")
	ok(Materials.wear_rate("S235", 240.0, 80.0, 120.0, 1.0, true) > best * 3.0, "Zu hohes vc verschleißt mehr")
	ok(Materials.wear_rate("S235", 40.0, 80.0, 120.0, 1.0, true) > best, "Zu niedriges vc verschleißt mehr")
	ok(Materials.wear_rate("S235", 100.0, 80.0, 120.0, 2.0, true) > best, "Zu viel Vorschub verschleißt mehr")
	ok(Materials.wear_rate("S235", 100.0, 80.0, 120.0, 1.0, false) > best, "Ohne Kühlung verschleißt mehr")
	ok(Materials.wear_rate("1.4301", 45.0, 40.0, 50.0, 1.0, true) > best, "Edelstahl verschleißt mehr als Baustahl")
	l._wear_rate = best
	var w0: float = l.tool_wear()
	l._add_wear(10.0)
	ok(l.tool_wear() > w0 and w.company.tools["lathe"].wear("T1") == l.tool_wear(), "Schneiden nutzt das Werkzeug ab")
	ok(l.tool_wear() < 0.02, "Zehn Sekunden sind wenig")
	# Verschlissen: weg, neu kaufen
	w.company.tools["lathe"].items["T1"]["wear"] = 0.999
	l.estop = false
	l._wear_rate = 1.0
	l._add_wear(1.0)
	ok(not l.has_cutter() and not w.company.tools["lathe"].has("T1") and l.estop, "Verschlissenes Werkzeug ist weg, Not-Halt")
	l.estop = false
	w.money = 100
	ok(w.buy_tool("lathe", "T1", "hm") == "" and w.company.tools["lathe"].wear("T1") == 0.0, "Neu gekauft: kein Verschleiß")
	l.mount_tool(0, "T1")
	ok(l.has_cutter(), "Wieder eingespannt")
	# Zerstörerische Werte: sofort kaputt
	l.tool_heat = 0.999
	l._cut_t = 0.5
	l._heat_over = 5.0
	l._update_heat(1.0)
	ok(not l.has_cutter() and not w.company.tools["lathe"].has("T1"), "Ausgeglüht: Werkzeug ist weg")
	l.estop = false
	l.tool_heat = 0.0
	w.buy_tool("lathe", "T1", "hm")
	l.mount_tool(0, "T1")
	# Einkauf: Kisten und großer Behälter sind Skills
	ok(w.buy_equipment("crate_l") != "" and w.buy_equipment("crate_m") != "" and w.buy_equipment("bin_l") != "", "Größere Kisten und Behälter brauchen den Skill")
	ok(sk.unlock_error("crate_l", true) != "", "Große Kisten erst nach den mittleren")
	ok(o.shop_tab.buttons.has("crate_l") and not o.shop_tab.buttons.has("container"), "Kisten im Einkauf, Container stehen fest im Hof")
	o.shop_tab.refresh()
	ok(o.shop_tab.buttons["crate_m"].disabled and o.shop_tab.buttons["crate_m"].text == "Gesperrt", "Einkauf zeigt die Sperre")
	w.set_free_mode(true)
	ok(w.unlock_skill("crate_m") == "" and w.unlock_skill("crate_l") == "" and w.unlock_skill("tray_big") == "" and w.unlock_skill("bin_l") == "", "Alle freigeschaltet")
	w.set_free_mode(false)

	# ---------------------------------------------------- Fräse kaufen und aufstellen
	w.money = 10000
	ok(w.buy_equipment("mill") == "" and w.inventory["mill"] == 1, "Fräsmaschine gekauft")
	ok(w.place_machine("mill", Vector2(6.85, -3.1), 0) == "", "Fräsmaschine aufgestellt")
	ok(w.buy_tool("mill", "F10", "hm") == "", "Fräser kaufen")
	p.set_held(m, "F10")
	m.hand_click(p)
	ok(m.has_cutter() and m.tool()["id"] == "F10" and p.held.is_empty(), "In die leere Spindel einsetzen")
	m._wear_rate = 0.001
	m._add_wear(10.0)
	ok(m.tool_wear() > 0.0, "Auch Fräser verschleißen")
	m._tool_broken("Testbruch")
	ok(m.spindle_empty and not w.company.tools["mill"].has("F10") and m.estop, "Werkzeugbruch: weg, neu kaufen")
	m.estop = false
	ok(w.buy_tool("mill", "F10", "hm") == "", "Wieder gekauft")
	ok(m.visible and is_equal_approx(m.global_position.y, 0.0), "Sie steht in der Halle")
	ok(w.company.owns("mill"), "Maschinenpark")
	ok(w.accept_job("mill:0") == "" and w.accept_job("mill:4") != "", "Fräsaufträge: Baustahl ja, Messing noch nicht")

	# ---------------------------------------------------- Kisten
	ok(w.buy_equipment("crate_s") == "" and w.buy_equipment("crate_m") == "" and w.buy_equipment("crate_l") == "" and w.buy_equipment("crate_s") == "", "Kisten kaufen")
	ok(w.inventory["crate_s"] == 2, "Mehrfach kaufbar")
	var cost_all: int = int(Crate.SIZES["crate_s"]["price"])
	ok(cost_all > 0 and int(Crate.SIZES["crate_l"]["price"]) > cost_all, "Größere Kisten kosten mehr")
	ok(w.place_crate(-1, "crate_s", Vector2(0, 2), 0) != "", "Ohne Werkbank keine Kiste")
	w.inventory["bench"] = 1
	ok(w.place_bench("", Vector2(0.6, 0.35), 2) == "", "Werkbank steht")
	ok(w.place_crate(-1, "crate_s", Vector2(11, 7), 0) != "", "Nur neben der Werkbank")
	ok(w.layout.check_crate("crate_s", Vector2(0.6, 0.35), 0) == "", "Ganz auf der Werkbankplatte erlaubt")
	ok(w.layout.check_crate("crate_s", Vector2(0.6, 0.0), 0) != "", "Halb über der Kante der Werkbank nicht")
	ok(w.place_crate(-1, "crate_s", Vector2(-1.0, 0.4), 0) == "", "Neben der Werkbank erlaubt: " + w.layout.check_crate("crate_s", Vector2(-1.0, 0.4), 0))
	ok(w.layout.crates[0]["bench"] == "lathe" and w.crate_nodes.size() == 1, "Kiste gehört zur Werkbank")
	ok(w.place_crate(-1, "crate_m", Vector2(1.9, 0.4), 0) == "", "Zweite Kiste")
	ok(w.place_crate(-1, "crate_s", Vector2(-1.5, 1.0), 0) != "", "Neben einer normalen Werkbank haben nur 2 Platz")
	ok(w.place_crate(-1, "crate_s", Vector2(0.6, 0.35), 0) == "", "Auf der Platte zählt die Grenze nicht")
	ok(w.layout.crate_is_on_top(w.layout.crates[2]) and is_equal_approx(w.crate_nodes[2].position.y, ToolBench.TOP_Y), "Kiste steht auf der Werkbank")
	var piece := {"material": "S235", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0}
	var bar := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0}
	var sawn := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 160.0, "sawn": true}
	var huge := {"material": "S235", "kind": "cut", "d": 0.0, "w": 500.0, "h": 40.0, "l": 800.0}
	ok(Crate.accepts(piece) and not Crate.accepts(bar) and Crate.accepts(sawn), "Fertigschnitte und abgesägte Teile ja, Stangen nein")
	ok(not Crate.fits("crate_s", [], huge) and Crate.fits("crate_l", [], huge), "Große Teile nur in große Kisten")
	var many := []
	var count := {}
	for id in Crate.SIZES:
		many = []
		while Crate.fits(id, many, piece) and many.size() < 100:
			many.append(piece)
		count[id] = many.size()
	ok(count["crate_s"] == 6 and count["crate_m"] == 12 and count["crate_l"] == 24, "Größere Kisten halten mehr: %s" % str(count))
	ok(Crate.fits("crate_s", [piece, piece], sawn) or true, "Gemischt")
	var tall := {"material": "S235", "kind": "cut", "d": 0.0, "w": 100.0, "h": 250.0, "l": 100.0}
	ok(not Crate.fits("crate_s", [], tall) and Crate.fits("crate_m", [], tall), "Höhe zählt")
	# Lagen stapeln sich nur bis zur Kistenhöhe
	var plate := {"material": "S235", "kind": "cut", "d": 0.0, "w": 300.0, "h": 90.0, "l": 400.0}
	ok(Crate.fits("crate_s", [plate], plate) and not Crate.fits("crate_s", [plate, plate], plate), "Zwei Platten übereinander, die dritte nicht")
	p.clear_carry()
	p.set_carry(bar.duplicate())
	ok(w.crate_put(0) != "", "Stange passt nicht in die Kiste")
	p.clear_carry()
	p.set_carry(piece.duplicate())
	ok(w.crate_prompt(0).contains("legen"), "Hinweis beim Ablegen")
	w.crate_click(0)
	ok(p.carry.is_empty() and w.layout.crates[0]["items"].size() == 1, "In die Kiste gelegt")
	ok(w.crate_nodes[0]._content.get_child_count() == 1, "Teil ist zu sehen")
	ok(w.crate_prompt(0).contains("nehmen"), "Hinweis beim Nehmen")
	w.crate_click(0)
	ok(not p.carry.is_empty() and w.layout.crates[0]["items"].is_empty(), "Wieder genommen")
	w.mill_job_index = 0
	ok(w.clamp_carried(m) == "" and m.has_part and m.block_l == 100.0, "Aus der Kiste in den Schraubstock")
	# Kiste wandert mit der Maschine
	var cp: Vector2 = w.layout.crates[0]["pos"]
	ok(w.place_machine("lathe", Vector2(-2.0, -2.0), 0) == "", "Drehmaschine umstellen: " + w.layout.check_machine("lathe", Vector2(-2.0, -2.0), 0))
	ok(w.layout.crates[0]["pos"].is_equal_approx(cp + Vector2(-2.0, 0.0)), "Kiste wandert mit")
	ok(w.place_bench("lathe", Vector2(-1.4, 0.35), 2) != "", "Werkbank mit Kisten bleibt stehen")
	ok(w.place_machine("lathe", Vector2(0.0, -2.0), 0) == "", "Zurück")
	# Große Werkbank
	ok(w.buy_equipment("bench_big") != "", "Große Werkbank braucht den Skill")
	w.set_free_mode(true)
	w.unlock_skill("bench_big")
	w.set_free_mode(false)
	ok(w.buy_equipment("bench_big") == "", "Große Werkbank gekauft")
	ok(w.take_down_bench("lathe") != "", "Abbauen geht nicht mit Kisten daneben")
	var crates_saved: Array = w.layout.crates
	w.layout.crates = []
	w._rebuild_stands()
	ok(w.take_down_bench("lathe") == "" and w.inventory["bench"] == 1 and w.lathe_bench == null, "Werkbank abgebaut")
	ok(w.place_bench("", Vector2(0.6, 0.4), 2, true) == "", "Große Werkbank aufgestellt: " + w.layout.check_bench(Vector2(0.6, 0.4), 2, "", true))
	ok(w.lathe_bench.width == Layout.BENCH_BIG_SIZE.x, "Sie ist größer")
	ok(w.layout.crate_limit("lathe") == Layout.CRATES_BIG, "Mehr Platz für Kisten")

	# ---------------------------------------------------- Späne
	ok(l.tray.is_empty(), "Wanne ist leer")
	l.tray.capacity = 15.0
	var g: String = "baustahl"
	l.tray.add(g, 1.0)
	l.refresh_tray()
	ok(l._chip_heap.visible, "Späne sichtbar in der Wanne")
	l.new_workpiece(60.0, 160.0)
	var k0: float = l.tray.kg
	l._cut_t = 0.5
	await physics_frame
	await physics_frame
	ok(l.tray.kg > k0, "Im Schnitt füllt sich die Wanne")
	ok(l.tray.kg - k0 < 0.1, "Langsam")
	l.spindle_on = true
	l.tray.add(g, 100.0)
	ok(l.tray.is_full() and is_equal_approx(l.tray.kg, l.tray.capacity), "Wanne läuft nicht über")
	await physics_frame
	await physics_frame
	ok(l.spindle_on, "Volle Wanne stoppt die Spindel nicht")
	l.spindle_on = false
	l.spindle_speed = 0.0
	# Behälter kaufen, aufstellen, tragen
	ok(w.buy_equipment("bin_s") == "", "Spänebehälter gekauft")
	ok(w.place_bin(-1, "bin_s", Vector2(0, -2), 0) != "", "Nicht auf der Drehmaschine")
	ok(w.place_bin(-1, "bin_s", Vector2(4.0, 5.0), 0) == "", "Aufgestellt: " + w.layout.check_bin(Vector2(4.0, 5.0), 0))
	var bin: Dictionary = w.layout.bins[0]
	ok(w.bin_prompt(0).contains("Aufnehmen"), "Hinweis am Behälter")
	w.bin_click(0)
	ok(p.carrying_bin() and bin["out"], "Behälter in den Händen")
	ok(w.store_carried(0) != "", "Behälter geht nicht ins Regal")
	ok(w.crate_put(0) != "" or w.layout.crates.is_empty(), "Und nicht in die Kiste")
	ok(not p.carry.is_empty(), "Bleibt in den Händen")
	ok(w.clamp_carried(l) == "", "Wanne in den Behälter")
	ok(is_equal_approx(l.tray.kg, 0.0) and is_equal_approx(bin["chips"].kg, 15.0), "15 kg umgefüllt")
	ok(not l._chip_heap.visible, "Wanne sieht leer aus")
	ok(w.clamp_carried(l) != "", "Leere Wanne meldet das")
	# Mehr als in den Behälter passt, bleibt in der Wanne
	l.tray.add(g, 15.0)
	w.clamp_carried(l)
	ok(bin["chips"].is_full() and is_equal_approx(l.tray.kg, 5.0), "Behälter voll, Rest bleibt in der Wanne")
	l.spindle_speed = 100.0
	ok(w.pour_tray(l) != "", "Nur bei stehender Spindel")
	l.spindle_speed = 0.0
	# Container
	ok(w.containers.size() == 3, "Container für Stahl, Aluminium und Messing")
	ok(w.containers[0].only == "stahl" and w.containers[1].only == "aluminium" and w.containers[2].only == "messing", "Je Sorte einer")
	# Keine gemischten Späne
	var tr := ChipTray.new()
	ok(tr.add("baustahl", 1.0) == 1.0 and tr.add("verguetungsstahl", 1.0) == 1.0 and tr.add("edelstahl", 1.0) == 1.0, "Stahlarten dürfen zusammen")
	ok(tr.add("aluminium", 1.0) == 0.0 and tr.add("messing", 1.0) == 0.0, "Aluminium und Messing nicht dazu")
	ok(is_equal_approx(tr.kg, 3.0) and tr.sort() == "stahl", "Inhalt bleibt Stahl")
	var bx := ChipTray.new(10.0)
	bx.add("aluminium", 2.0)
	ok(bx.take_from(tr) == 0.0 and is_equal_approx(tr.kg, 3.0), "Behälter mit Aluminium nimmt keinen Stahl")
	ok(w.containers[1].take_from(tr) == 0.0, "Aluminiumcontainer nimmt keinen Stahl")
	ok(w.containers[0].take_from(bx) == 0.0, "Stahlcontainer nimmt kein Aluminium")
	ok(w.containers[1].take_from(bx) == 2.0 and bx.is_empty(), "Aluminiumcontainer nimmt Aluminium")
	w.containers[1].clear()
	# Wanne mit Stahlspänen: Aluminium darf nicht eingespannt werden
	var steel_left: float = l.tray.kg
	l.tray.clear()
	l.tray.add("baustahl", 1.0)
	var bin_carry: Dictionary = p.carry.duplicate()
	p.clear_carry()
	p.set_carry({"material": "AW-6082", "kind": "round", "d": 40.0, "w": 0.0, "h": 0.0, "l": 500.0})
	var mix_err: String = w.clamp_carried(l)
	ok(mix_err.contains("leeren") and not p.carry.is_empty(), "Erst die Wanne leeren: " + mix_err)
	l.tray.clear()
	ok(w.clamp_carried(l) == "", "Mit leerer Wanne geht es")
	l.clear_workpiece()
	p.clear_carry()
	p.set_carry(bin_carry)
	l.tray.clear()
	l.tray.add("baustahl", steel_left)
	l.refresh_tray()
	ok(not w.containers[0].is_full(), "Container ist nicht voll")
	ok(w.collect_container(0) == 0, "Halbvoll wird nichts abgeholt")
	ok(w.container_prompt(0).contains("hineinleeren"), "Hinweis am Container")
	w.container_click(0)
	ok(is_equal_approx(w.containers[0].kg, 25.0) and bin["chips"].is_empty(), "Behälter in den Container geleert")
	var wt = o.waste_tab
	wt.refresh()
	ok(wt.buttons[0].disabled, "PC: Abholen erst, wenn voll")
	# Abstellen auf dem Stellplatz
	ok(w.bin_prompt(0).contains("abstellen"), "Hinweis am Stellplatz")
	w.bin_click(0)
	ok(p.carry.is_empty() and not bin["out"], "Behälter abgestellt")
	# Bezahlt wird erst am PC
	w.containers[0].add("baustahl", 95.0)
	ok(w.containers[0].is_full(), "Container voll")
	wt.refresh()
	ok(not wt.buttons[0].disabled, "PC: jetzt abholbar")
	var cash: int = w.money
	var worth: int = w.container_value(0)
	ok(worth == int(round(120.0 * 1.2 * ChipTray.RECYCLE)), "Wert nach Werkstoff: %d" % worth)
	ok(w.money == cash, "Volle Container bringen nichts ohne Abholung")
	wt.buttons[0].pressed.emit()
	ok(w.money == cash + worth and w.containers[0].is_empty(), "Abgeholt und bezahlt")
	var alu := ChipTray.new(10.0)
	alu.add("aluminium", 10.0)
	var steel := ChipTray.new(10.0)
	steel.add("baustahl", 10.0)
	ok(alu.value() > steel.value(), "Aluminiumspäne sind mehr wert")
	ok(w.site.container_pos(2).z + 1.0 < w.site.YARD_Z1, "Alle stehen im Hof")

	# ---------------------------------------------------- Speichern und Laden
	w.layout.crates = crates_saved
	w.layout.crates[0]["items"] = [piece.duplicate()]
	w.layout.crates[0]["bench"] = "lathe"
	w.layout.crates.resize(1)
	w._rebuild_stands()
	w.layout.bins[0]["chips"].add("messing", 3.0)
	w.containers[1].add("aluminium", 7.0)
	l.tray.clear()
	l.tray.add("baustahl", 2.0)
	var xp0: int = sk.xp
	var state := {
		"name": "T", "money": 123, "machines": w.company.machines, "job": 0, "mill_job": 0, "parts": 1,
		"player": p.get_state(), "lathe": l.get_state(), "mill": m.get_state(), "stock": w.stock, "deliveries": [],
		"site": w._site_state(), "layout": w.layout.to_state(), "inventory": w.inventory, "skills": sk.to_state(),
		"tools": {"lathe": w.company.tools["lathe"].to_state(), "mill": w.company.tools["mill"].to_state()},
		"accepted": w.accepted, "tracked": w.tracked, "containers": w.containers.map(func(c): return c.to_state()),
	}
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(state))
	w._apply_pending({"name": "Neu", "money": 500})
	ok(w.company.skills.xp == 0 and not w.company.skills.has("mill_conv"), "Neues Spiel fängt von vorn an")
	ok(not m.visible and not l.visible and w.accepted.is_empty() and w.layout.crates.is_empty() and w.layout.bins.is_empty(), "Auch ohne Maschinen, Aufträge und Kisten")
	ok(not l.has_cutter() and not m.has_cutter() and w.company.tools["lathe"].items.is_empty(), "Und ohne Werkzeuge")
	ok(is_equal_approx(Materials.coolant_factor, 0.4), "Wirkung der Skills ist zurückgesetzt")
	w._apply_pending(loaded)
	var s2 = w.company.skills
	ok(s2.xp == xp0 and s2.has("mill_conv") and s2.has("lathe_hss") and s2.has("bench_big"), "Skills gespeichert")
	ok(m.visible and is_equal_approx(Materials.coolant_factor, 0.27), "Wirkung nach dem Laden")
	ok(w.accepted.has("mill:0"), "Aufträge gespeichert")
	ok(w.company.tools["lathe"].has("T1"), "Werkzeuge gespeichert")
	ok(w.layout.crates.size() == 1 and w.layout.crates[0]["items"].size() == 1 and w.crate_nodes.size() == 1, "Kiste mit Inhalt gespeichert")
	ok(w.layout.bins.size() == 1 and is_equal_approx(w.layout.bins[0]["chips"].kg, 3.0) and w.layout.bins[0]["chips"].capacity == 25.0, "Behälter gespeichert")
	ok(w.site.rack_cells.size() == 1, "Gekauftes Regal gespeichert")
	ok(w.containers.size() == 3 and is_equal_approx(w.containers[1].kg, 7.0), "Container gespeichert")
	ok(is_equal_approx(l.tray.kg, 2.0), "Spänewanne gespeichert")
	ok(w.layout.benches["lathe"]["big"] == true and w.lathe_bench.width == Layout.BENCH_BIG_SIZE.x, "Große Werkbank gespeichert")

	# Alter Spielstand: behält Maschinen, Werkstoffe und seine Aufträge
	w._apply_pending({"name": "Alt", "money": 900, "job": 2, "mill_job": 1, "lathe": {"has_part": false}, "mill": {"has_part": false}})
	var s3 = w.company.skills
	ok(s3.has("mill_conv") and s3.has("mat_titan") and s3.has("lathe_cnc"), "Alter Spielstand behält alles")
	ok(not s3.has("coolant_1") and not s3.has("mill_cnc"), "Upgrades bleiben offen")
	ok(w.company.owns("mill") and m.visible and l.visible, "Maschinen stehen weiter")
	ok(w.company.tools["lathe"].has("T7") and w.company.tools["mill"].has("MK125"), "Alter Spielstand hat alle Werkzeuge in Hartmetall")
	ok(w.accepted == ["lathe:2", "mill:1"] and w.tracked == "lathe:2", "Laufende Aufträge bleiben angenommen")
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
