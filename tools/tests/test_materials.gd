extends SceneTree
## Werkstoffe: Daten aus den Schnittdaten-PDFs, Verhalten beim Zerspanen, Rohmaterial am PC.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
## Lieferungen aus dem Hof aufheben und ins Regal legen.
func deliver(w) -> void:
	while not w.deliveries.is_empty():
		w.pick_delivery(0)
		w.store_carried(-1)
func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var m = w.mill
	var l = w.lathe
	var start_money: int = root.get_node("GameState").START_MONEY

	# Daten
	var titles := []
	var ids := {}
	for g in Materials.GROUPS:
		titles.append(g["title"])
		ok(g["list"].size() >= 2, "Mehrere Werkstoffe in " + str(g["title"]))
		ok(Materials.MILL_VC.has(g["mill"]), "Fräsgruppe gültig in " + str(g["title"]))
		for mt in g["list"]:
			ok(not ids.has(mt["id"]), "Werkstoff eindeutig: " + str(mt["id"]))
			ids[mt["id"]] = true
			ok(Materials.MILL_VC.has(Materials.mill_group(str(mt["id"]))), "Fräsgruppe: " + str(mt["id"]))
	for t in ["Baustahl", "Edelstahl", "Automatenstahl", "Aluminium", "Messing"]:
		ok(titles.has(t), "Materialgruppe " + t)
	ok(ids.has("S235") and ids.has("C45") and ids.has("1.4301") and ids.has("CuZn37") and ids.has("AW-7075"), "Werkstoffe aus den PDFs")
	# Tabellenwerte
	var f10: Dictionary = MillTools.TOOLS[2]
	var cs: Dictionary = Materials.mill_data("S235", f10, 62.8)
	ok(cs["vmax"] == 30.0 and cs["vmin"] == 25.0, "S235 Schaftfräser vc 25-30 (S. 6)")
	ok(is_equal_approx(cs["fz_rec"], 0.015), "S235 Ø10 fz 0,015 (S. 6)")
	ok(is_equal_approx(cs["fz_max"], float(f10["fz_max"])) and is_equal_approx(cs["ap_max"], float(f10["ap_max"])), "S235 lässt die Werkzeuggrenzen unverändert")
	var ss: Dictionary = Materials.mill_data("1.4301", f10, 62.8)
	ok(ss["vmax"] == 16.0 and ss["ap_max"] < cs["ap_max"], "Edelstahl: vc bis 16, weniger Zustellung")
	var ms: Dictionary = Materials.mill_data("CuZn39Pb3", f10, 62.8)
	ok(ms["vmax"] == 70.0 and ms["fz_rec"] > cs["fz_rec"], "Messing: vc bis 70, mehr Vorschub")
	var al: Dictionary = Materials.mill_data("AW-6082", f10, 62.8)
	ok(al["vmax"] == 300.0 and al["vmin"] <= 62.8 * 0.7 + 0.01, "Aluminium: Soll auf das Erreichbare gesenkt")
	var drill: Dictionary = MillTools.TOOLS[6]
	ok(is_equal_approx(Materials.mill_data("S235", drill, 62.8)["vmax"], 43.0 * 1.2), "Bohrer S235 um 43 m/min (S. 13)")
	ok(is_equal_approx(Materials.turn_factor("S235"), 1.0), "Drehfenster S235 unverändert")
	ok(Materials.turn_factor("1.4301") < 0.5 and Materials.turn_factor("CuZn37") > 1.5, "Drehfenster folgt dem Werkstoff")
	# Rautiefe
	var t1: Dictionary = LatheTools.get_tool(0)
	var base: float = l.surface_rz(t1, 0.15, 1.0, 200.0, true, false)["rz"]
	ok(is_equal_approx(l.surface_rz(t1, 0.15, 1.0, 200.0, true, false, Materials.turn_params("S235", 500.0))["rz"], base), "S235 wie bisher")
	var v14: Dictionary = l.surface_rz(t1, 0.15, 1.0, 200.0, true, false, Materials.turn_params("1.4301", 500.0))
	ok(v14["rz"] > base and str(v14["hint"]).contains("Verschleiß"), "Edelstahl bei 200 m/min: Verschleiß")
	var ali: Dictionary = l.surface_rz(t1, 0.15, 1.0, 350.0, false, false, Materials.turn_params("AW-6082", 500.0))
	ok(str(ali["hint"]) != "", "Aluminium trocken: Hinweis (%s)" % ali["hint"])
	var dry: float = l.surface_rz(t1, 0.15, 1.0, 400.0, false, false, Materials.turn_params("CuZn37", 500.0))["rz"]
	var wet: float = l.surface_rz(t1, 0.15, 1.0, 400.0, true, false, Materials.turn_params("CuZn37", 500.0))["rz"]
	ok(is_equal_approx(dry, wet), "Messing braucht keine Kühlung")

	# Farben
	m.set_material("CuZn39Pb3")
	var cc: Color = Materials.cut_color("CuZn39Pb3")
	ok(cc.r > cc.b + 0.3, "Messing ist gelblich")
	ok(Color(m._block_mat.get_shader_parameter("cut_col")).is_equal_approx(cc), "Fräsrohteil in Messingfarbe")
	ok(m._chip_mesh.material.albedo_color == cc, "Späne in Messingfarbe")
	l.set_material("AW-6082")
	ok(l._cut_col == Materials.cut_color("AW-6082") and l._raw_col == Materials.raw_color("AW-6082"), "Drehteil in Aluminiumfarbe")
	ok(Materials.raw_color("S235").v < Materials.raw_color("AW-6082").v, "Stahl dunkler als Aluminium wie auf den Fotos")

	# Verhalten an der Fräsmaschine: zu hohes vc glüht das Werkzeug aus
	m.new_workpiece(100.0, 60.0, 40.0)
	m.set_material("1.4301")
	m.select_tool(4, true)
	m.coolant = false
	m.estop = false
	m.rpm_set = 2000.0
	m.spindle_on = true
	m.tool_heat = 0.0
	m._harden_t = 0.0
	for i in 40:
		await physics_frame
	for i in 200:
		m._cut_t = 0.2
		m._update_heat(0.05)
		if m.estop:
			break
	ok(m.estop, "Ø16 in Edelstahl bei 2000 /min glüht aus")
	m.estop = false
	m.tool_heat = 0.0
	m.coolant = true
	m._cut_t = 0.2
	m._update_heat(0.1)
	var wet_heat: float = m.tool_heat
	m.tool_heat = 0.0
	m.coolant = false
	m._cut_t = 0.2
	m._update_heat(0.1)
	ok(wet_heat < m.tool_heat, "Kühlung bremst die Erwärmung")
	m.set_material("S235")
	m.select_tool(0, true)
	m.rpm_set = 1250.0
	m.tool_heat = 0.0
	for i in 40:
		await physics_frame
	m._cut_t = 0.2
	m._update_heat(0.1)
	ok(m.tool_heat == 0.0, "Im Sollbereich keine Erwärmung")
	m.spindle_on = false
	m.spindle_speed = 0.0
	m.coolant = false

	# Rohmaterial am PC
	var raw = w.office_pc.overlay.raw
	ok(raw.shop == w, "Tab kennt die Spielwelt")
	var kind_titles := []
	for i in raw.kinds.get_tab_count():
		kind_titles.append(raw.kinds.get_tab_title(i))
	ok(kind_titles.has("Stangenmaterial") and kind_titles.has("Fertigschnitt Material"), "Stangen und Fertigschnitt")
	var bars: TabContainer = raw.kinds.get_tab_control(0)
	ok(bars.get_tab_title(0) == "Rundmaterial" and bars.get_tab_title(1) == "Vierkantmaterial", "Stangen: Rund und Vierkant")
	var pr = raw.pages[Materials.KIND_ROUND]
	var pq = raw.pages[Materials.KIND_SQUARE]
	var pc = raw.pages[Materials.KIND_CUT]
	ok(pr.groups.get_tab_count() == Materials.GROUPS.size(), "Gruppen-Tabs bei Rundmaterial")
	ok(pq.groups.get_tab_count() == Materials.GROUPS.size() and pc.groups.get_tab_count() == Materials.GROUPS.size(), "Gruppen-Tabs überall")
	ok(pr.fields.keys() == ["d"], "Rundstange: nur Durchmesser einstellbar")
	ok(pq.fields.has("w") and pq.fields.has("h") and pq.fields.size() == 2, "Vierkant: nur Breite und Höhe einstellbar")
	ok(pc.fields.has("l") and pc.fields.has("w") and pc.fields.has("h"), "Fertigschnitt: alle Maße frei")
	pr.length_opt.select(0)
	ok(pr.spec()["l"] == 1000.0, "Auch 1 m wählbar")
	pr.length_opt.select(1)
	ok(pr.spec()["l"] == 2000.0 and pq.spec()["l"] == 2000.0, "Voreingestellt 2 m")
	pc.fields["l"].value = 77.0
	ok(pc.spec()["l"] == 77.0, "Fertigschnitt-Länge frei")
	for g in Materials.GROUPS:
		for k in [Materials.KIND_ROUND, Materials.KIND_SQUARE, Materials.KIND_CUT]:
			var ph: Dictionary = Materials.photo(str(g["list"][0]["id"]), k)
			ok(ResourceLoader.exists(str(ph["path"])), "Foto da: %s" % ph["path"])
	pr.select("1.4301")
	ok(pr.groups.get_tab_title(pr.groups.current_tab) == "Edelstahl", "Auswahl öffnet die Gruppe")
	ok(pr._photo.texture is AtlasTexture, "Werkstoff-Nr. im Foto abgeschnitten")
	pr.select("CuZn37")
	ok(pr._photo.texture != null and pr._photo.modulate == Color.WHITE, "Messing hat eigenes Foto")
	pr.select("E-Cu")
	ok(pr._photo.modulate != Color.WHITE, "Kupfer: eingefärbt")
	ok(Materials.price("S235", "round", 60.0, 0.0, 0.0, 3000.0) > 0, "Preis berechnet")
	ok(Materials.weight_kg("AW-6082", "round", 60.0, 0.0, 0.0, 1000.0) < Materials.weight_kg("S235", "round", 60.0, 0.0, 0.0, 1000.0) * 0.5, "Aluminium ist leichter")

	# Bestellen: Geld wird fällig
	w.money = 0
	pr.select("S235")
	pr.fields["d"].value = 60.0
	raw.refresh()
	ok(pr.order_button.disabled, "Ohne Geld keine Bestellung")
	ok(w.order_material(pr.spec()) != "", "Bestellung abgelehnt")
	ok(w.stock.is_empty(), "Lager leer")
	w.money = 5000
	raw.refresh()
	ok(not pr.order_button.disabled, "Mit Geld möglich")
	var cost: int = pr.total()
	pr.order()
	deliver(w)
	ok(w.money == 5000 - cost and w.stock.size() == 1, "Bestellt und bezahlt")
	# Abschnitt sägen
	ok(w.load_stock(0, 160.0) == "", "Abschnitt eingespannt")
	ok(l.stock_d == 60.0 and l.stock_len == 160.0 and l.material == "S235", "Drehmaschine hat den Abschnitt")
	ok(w.stock[0]["l"] == 2000.0 - 160.0 - Materials.KERF, "Stange um Abschnitt und Sägeschnitt kürzer")
	ok(w.load_stock(0, 900.0) != "", "Zu langer Abschnitt abgelehnt")
	l.spindle_speed = 500.0
	ok(w.load_stock(0, 160.0) != "", "Nicht bei laufender Spindel")
	l.spindle_speed = 0.0
	# Fertigschnitt an die Fräse
	pc.select("AW-6082")
	pc.fields["l"].value = 120.0
	pc.fields["w"].value = 80.0
	pc.fields["h"].value = 30.0
	pc.order()
	deliver(w)
	ok(w.stock.size() == 2, "Fertigschnitt im Lager")
	ok(w.load_stock(1, 0.0) == "", "Fertigschnitt eingespannt")
	ok(m.block_l == 120.0 and m.block_w == 80.0 and m.block_h == 30.0 and m.material == "AW-6082", "Fräse hat das Teil")
	ok(w.stock.size() == 1, "Fertigschnitt ist verbraucht")
	w.office_pc.overlay.stock_view.refresh()
	ok(w.office_pc.overlay.stock_view.list.get_child_count() == 1, "Lagerliste zeigt den Rest")
	# Aufträge brauchen gekauftes Material
	w.stock = []
	w.money = 5000
	w.job_index = 0
	w.mill_job_index = 0
	w._apply_pending({"name": "Neu", "money": start_money, "unlock_all": true})
	ok(not l.has_part and not m.has_part, "Neues Spiel: Maschinen sind leer")
	ok(not l.workpiece_mi.visible and not m._block.visible, "Kein Rohteil sichtbar")
	ok(w._job_cost("lathe") + w._job_cost("mill") <= start_money, "Startgeld reicht für das erste Material beider Maschinen")
	var part_before: float = l.tool_x
	l.tool_x = 5.0
	l.tool_z = 50.0
	ok(l.radius_at(50.0) == 0.0, "Leeres Futter: nichts zu schneiden")
	l.tool_x = part_before
	ok(m.height_at(10.0, 10.0) < -1000.0, "Leerer Schraubstock: nichts zu schneiden")
	var want_empty := str(w._lathe_take_part())
	ok(want_empty.contains("kaufen") and not l.has_part, "N ohne Material: Hinweis, kein Rohteil: " + want_empty)
	ok(str(w._mill_take_part()).contains("kaufen") and not m.has_part, "Fräse ebenso")
	w._on_submit()
	ok(w.job_index == 0 and w.parts == 0, "Ohne Rohteil keine Abgabe")
	# Bestellvorschlag zum Auftrag
	raw.pick_for_job("lathe")
	ok(pr.material_id() == "S235" and pr.fields["d"].value == 60.0, "Vorschlag für den Drehauftrag")
	ok(raw.kinds.current_tab == 0, "Vorschlag öffnet das Stangenmaterial")
	raw.pick_for_job("mill")
	ok(pc.material_id() == "S235" and pc.fields["l"].value == 100.0 and pc.fields["w"].value == 60.0 and pc.fields["h"].value == 40.0, "Vorschlag für den Fräsauftrag")
	ok(raw.kinds.current_tab == 1, "Vorschlag öffnet den Fertigschnitt")
	ok(raw._needs.text == "" or raw._needs.text.contains("Ø60"), "Anzeige zeigt den Bedarf")
	raw.refresh()
	ok(raw._needs.text.contains("Ø60") and raw._needs.text.contains("100 x 60 x 40"), "Bedarf steht am PC")
	# Kaufen, einspannen, zweites Stück von derselben Stange
	raw.pick_for_job("lathe")
	pr.qty.value = 1.0
	pr.order()
	raw.pick_for_job("mill")
	pc.qty.value = 1.0
	pc.order()
	deliver(w)
	ok(w.money < start_money and w.stock.size() == 2, "Gekauft")
	ok(str(w._lathe_take_part()).contains("Lager") and not l.has_part and w.stock[0]["l"] == 2000.0, "Taste lädt nichts aus dem Lager")
	ok(str(w._mill_take_part()).contains("Lager") and not m.has_part, "An der Fräse ebenso")
	ok(w.take_from_stock(0) == "" and w.clamp_carried(l).contains("Bandsäge") and not l.has_part, "Ganze Stange passt nicht in die Maschine")
	var rest_bar: Dictionary = w.player.carry.duplicate()
	w.player.set_carry(Materials.cut_off(rest_bar, 160.0))
	ok(w.clamp_carried(l) == "" and l.has_part and l.stock_d == 60.0 and l.stock_len == 160.0, "Abgesägtes Stück einspannen gibt das Rohteil")
	ok(l.workpiece_mi.visible, "Rohteil sichtbar")
	var rest0: float = rest_bar["l"]
	ok(rest0 == 2000.0 - 160.0 - Materials.KERF, "Stange gekürzt")
	w.player.set_carry(rest_bar)
	w.store_carried()
	var cut_i: int = w._find_mill_stock()
	ok(w.take_from_stock(cut_i) == "" and w.clamp_carried(m) == "" and m.has_part and m.block_l == 100.0 and m._block.visible, "Fertigschnitt kommt auf die Fräse")
	var n0: int = w.stock.size()
	ok(str(w._lathe_take_part()).contains("unbearbeitet") and w.stock.size() == n0, "Unbearbeitetes Rohteil bleibt, nichts wird verbraucht")
	l.machined[0] = 1
	ok(w.take_from_stock(0) == "", "Stange wieder nehmen")
	rest_bar = w.player.carry.duplicate()
	w.player.set_carry(Materials.cut_off(rest_bar, 160.0))
	ok(w.clamp_carried(l) == "", "Nächstes Rohteil von derselben Stange")
	ok(rest_bar["l"] == rest0 - 160.0 - Materials.KERF, "Stange wieder kürzer")
	w.player.set_carry(rest_bar)
	w.store_carried()
	# Falsches Material nimmt der Auftrag nicht aus dem Lager
	w.stock = [{"material": "C45", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0},
		{"material": "S235", "kind": "round", "d": 40.0, "w": 0.0, "h": 0.0, "l": 3000.0},
		{"material": "S235", "kind": "cut", "d": 0.0, "w": 40.0, "h": 60.0, "l": 100.0}]
	ok(w._find_lathe_stock() == -1, "Falscher Werkstoff oder zu dünn passt nicht")
	ok(w._find_mill_stock() == 2 and w.stock[2]["w"] == 60.0 and w.stock[2]["h"] == 40.0, "Fertigschnitt wird passend gedreht")
	w.stock = [{"material": "S235", "kind": "square", "d": 0.0, "w": 40.0, "h": 60.0, "l": 3000.0}]
	ok(w._find_mill_stock() == 0, "Vierkantstange mit passendem Querschnitt")
	w.stock = []
	# Ohne Material gibt die Taste nur den Hinweis
	l.clear_workpiece()
	m.clear_workpiece()
	w.money = 5000
	ok(str(w._lathe_take_part()).contains("kaufen") and not l.has_part, "Ohne Material bleibt das Futter leer")
	ok(str(w._mill_take_part()).contains("kaufen") and not m.has_part, "Ohne Material bleibt der Schraubstock leer")
	# Ohne Geld kommt man nicht in eine Sackgasse
	w.money = 0
	ok(str(w._lathe_take_part()).contains("Kunde") and l.has_part, "Pleite: Kunde stellt das Rohteil")
	ok(str(w._mill_take_part()).contains("Kunde") and m.has_part, "Pleite: auch an der Fräse")
	# Speichern mit leerer Maschine
	l.clear_workpiece()
	m.clear_workpiece()
	var est: Dictionary = JSON.parse_string(JSON.stringify(l.get_state()))
	var ems: Dictionary = JSON.parse_string(JSON.stringify(m.get_state()))
	l.new_workpiece(60.0, 160.0)
	m.new_workpiece(100.0, 60.0, 40.0)
	l.set_state(est)
	m.set_state(ems)
	ok(not l.has_part and not l.workpiece_mi.visible, "Leeres Futter gespeichert")
	ok(not m.has_part and not m._block.visible, "Leerer Schraubstock gespeichert")
	var old_state: Dictionary = ems.duplicate()
	old_state.erase("has_part")
	m.set_state(old_state)
	ok(m.has_part, "Alter Spielstand: Teil bleibt eingespannt")
	# Werkzeugkosten
	var worst_tool := 0
	for t in MillTools.TOOLS:
		ok(int(t.get("price", 0)) > 0, "Werkzeug hat einen Preis: " + str(t["id"]))
		worst_tool = maxi(worst_tool, int(t.get("price", 0)))
	w.money = 100
	m.select_tool(4, true)
	m.estop = false
	m._tool_broken("Testbruch")
	ok(w.money == 100 and m.estop and m.spindle_empty, "Werkzeugbruch: Not-Halt, Werkzeug ist weg, abgebucht wird nichts")
	ok(not w.company.tools["mill"].has("F16"), "Es fehlt im Bestand")
	ok(w.buy_tool("mill", "F16", "hm") == "" and w.money == 100 - int(MillTools.TOOLS[4]["price"]), "Neu kaufen kostet Geld")
	m.estop = false
	l.estop = false
	m.select_tool(4, true)
	# Jeder Auftrag bringt mehr, als Material und ein zerstörtes Werkzeug kosten
	for i in Jobs.LIST.size():
		w.job_index = i
		var jb: Dictionary = Jobs.LIST[i]
		var c: int = w._job_cost("lathe") + l.INSERT_PRICE * 4
		ok(int(jb["reward"]) > c, "%s: %d EUR > Stange und vier Platten %d EUR" % [jb["title"], int(jb["reward"]), c])
	for i in MillJobs.LIST.size():
		w.mill_job_index = i
		var jb: Dictionary = MillJobs.LIST[i]
		var c: int = w._job_cost("mill") + worst_tool
		ok(int(jb["reward"]) > c, "%s: %d EUR > Material und Werkzeug %d EUR" % [jb["title"], int(jb["reward"]), c])
	w.job_index = 0
	w.mill_job_index = 0
	# Taste ^ öffnet das Debug-Menü, dort schaltet ein Button den Testmodus: alles gratis
	var caret := InputEventKey.new()
	caret.physical_keycode = KEY_QUOTELEFT
	caret.pressed = true
	ok(not w.free_mode, "Testmodus ist anfangs aus")
	w._input(caret)
	ok(w.debug_menu.visible and not w.free_mode, "Taste ^ öffnet das Debug-Menü, der Testmodus bleibt aus")
	caret.echo = true
	w._input(caret)
	ok(w.debug_menu.visible, "Gehaltene Taste schließt nicht gleich wieder")
	caret.echo = false
	(w.debug_menu._toggles["free"] as Button).pressed.emit()
	ok(w.free_mode, "Button schaltet den Testmodus ein")
	var other := InputEventKey.new()
	other.keycode = KEY_A
	other.pressed = true
	w._input(other)
	ok(w.free_mode and w.debug_menu.visible, "Andere Taste ändert nichts")
	w._input(caret)
	ok(not w.debug_menu.visible and w.free_mode, "Taste ^ schließt das Menü, der Testmodus bleibt an")
	w.money = 0
	w.stock = []
	raw.pick_for_job("lathe")
	raw.refresh()
	ok(not pr.order_button.disabled, "Bestellen ohne Geld möglich")
	ok(pr._price.text.contains("gratis"), "Preis zeigt gratis")
	ok(raw._money.text.contains("TESTMODUS"), "PC zeigt den Testmodus")
	pr.qty.value = 3.0
	pr.order()
	pr.qty.value = 1.0
	deliver(w)
	ok(w.money == 0 and w.stock.size() == 3, "Bestellung kostet nichts")
	m._tool_broken("Testbruch")
	ok(w.money == 0 and m.estop, "Werkzeugbruch kostet nichts")
	m.estop = false
	w.money = 40
	l.tool_lost.emit(l.INSERT_PRICE, "Wendeplatte")
	ok(w.money == 40, "Platte kostet nichts")
	m.select_tool(0, true)
	w.stock = []
	w.money = 5000
	l.machined[0] = 1
	ok(str(w._lathe_take_part()).contains("Testmodus") and l.has_part and w.stock.is_empty(), "Rohteil Drehmaschine gratis, auch mit Geld")
	m.untouched = false
	ok(str(w._mill_take_part()).contains("Testmodus") and m.has_part, "Rohteil Fräsmaschine gratis")
	ok(w.money == 5000, "Rohteile kosten nichts")
	# Nach dem Laden ist der Testmodus nicht aus dem Spielstand gekommen
	ok(w.free_mode, "Testmodus läuft noch")
	var was_free: bool = w.free_mode
	w._apply_pending({"name": "T", "money": 5000, "free_mode": false, "lathe": l.get_state(), "mill": m.get_state()})
	ok(w.free_mode == was_free, "Spielstand ändert den Testmodus nicht")
	# Beim Tippen schaltet die Taste nicht um
	var typed := pr.fields["d"].get_line_edit() as LineEdit
	w.office_pc.overlay.open()
	w.office_pc.overlay.open_program("shop")
	w.office_pc.overlay.tabs.current_tab = 2
	raw.kinds.current_tab = 0
	await process_frame
	typed.grab_focus()
	await process_frame
	ok(typed.has_focus(), "Eingabefeld hat den Fokus")
	w._input(caret)
	ok(w.free_mode, "Im Eingabefeld schaltet ^ nicht um")
	typed.release_focus()
	w.office_pc.overlay.visible = false
	w.player.stop_operating()
	var dead := InputEventKey.new()
	dead.keycode = KEY_ASCIICIRCUM
	dead.pressed = true
	w._input(dead)
	ok(w.debug_menu.visible, "Auch das Zeichen ^ öffnet das Debug-Menü")
	(w.debug_menu._toggles["free"] as Button).pressed.emit()
	ok(not w.free_mode, "Button schaltet den Testmodus wieder aus")
	w._input(dead)
	ok(not w.debug_menu.visible, "Und das Menü wieder zu")
	w.money = 0
	raw.pick_for_job("lathe")
	raw.refresh()
	ok(pr.order_button.disabled and pr._price.text.contains("EUR"), "Danach kostet es wieder")
	w.stock = []
	# Falscher Werkstoff ist Ausschuss
	var job: Dictionary = MillJobs.get_job(0)
	ok(w._material_score(1.0, "AW-6082", job) == 0.0, "Falscher Werkstoff: Ausschuss")
	ok(w._material_score(1.0, "S235", job) == 1.0, "Richtiger Werkstoff zählt")
	# Speichern und Laden
	m.set_material("AW-6082")
	var st: Dictionary = JSON.parse_string(JSON.stringify(m.get_state()))
	var lst: Dictionary = JSON.parse_string(JSON.stringify(l.get_state()))
	m.set_material("S235")
	l.set_material("S235")
	m.set_state(st)
	l.set_state(lst)
	ok(m.material == "AW-6082", "Werkstoff Fräse gespeichert")
	ok(l.material == "S235", "Werkstoff Drehmaschine gespeichert")
	w.stock = [{"material": "C45", "kind": "round", "d": 40.0, "w": 0.0, "h": 0.0, "l": 3000.0}]
	w._apply_pending({"name": "T", "stock": JSON.parse_string(JSON.stringify(w.stock)), "money": 7})
	ok(w.stock.size() == 1 and w.stock[0]["material"] == "C45" and w.money == 7, "Lager gespeichert")
	w._apply_pending({"name": "T"})
	ok(w.stock.is_empty(), "Alter Spielstand: Lager leer")
	ok(w.money == start_money, "Ohne Kassenstand gilt das Startgeld")
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
