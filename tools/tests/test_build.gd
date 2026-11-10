extends SceneTree
## Tragen von Material, gemischte Regale, Schild, Kacheln, Einkauf, Baumenü und Maschinenbereiche.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func ray_blocked(from: Vector3, to: Vector3) -> bool:
	var space := (root.get_world_3d() as World3D).direct_space_state
	return not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to)).is_empty()
func aim(p, from: Vector3, target: Vector3) -> void:
	p.global_position = from
	p.velocity = Vector3.ZERO
	var eye: Vector3 = from + Vector3(0, 1.62, 0)
	var d: Vector3 = target - eye
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	for i in 6:
		await physics_frame
func key_action(a: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = true
	return e
func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var site = w.site
	var lay = w.layout
	var menu = w.build_menu
	w.money = 100000
	for i in 3:
		await physics_frame

	# ---- Gemischte Durchmesser auf einem Regalplatz
	var b60 := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0}
	var b40 := {"material": "C45", "kind": "round", "d": 40.0, "w": 0.0, "h": 0.0, "l": 3000.0}
	var sq := {"material": "S235", "kind": "square", "d": 0.0, "w": 50.0, "h": 50.0, "l": 3000.0}
	ok(Storage.fits_with([b60], b40), "Anderer Durchmesser darf dazu")
	ok(not Storage.fits_with([b60], sq), "Vierkant bleibt getrennt vom Rundmaterial")
	var mix := [b60, b40, b60, b40, b60, b40, b60]
	var placed: Array = Storage.layout_bars(mix)
	ok(placed.size() == 7, "Gemischte Stangen haben eine Lage")
	ok(placed[0].y == 0.0 and placed[5].y > 0.0, "Sechste Stange liegt in der zweiten Reihe")
	var fifteen := []
	for i in 15:
		fifteen.append(b60 if i % 2 == 0 else b40)
	ok(Storage.layout_bars(fifteen).size() == 15, "Auch gemischt passen 15")
	fifteen.append(b40)
	ok(Storage.layout_bars(fifteen).is_empty(), "Die 16. passt nicht")

	# ---- Material von Hand tragen
	w.stock = []
	w.deliveries = []
	w.order_material({"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0, "qty": 2})
	w.order_material({"material": "C45", "kind": "round", "d": 40.0, "w": 0.0, "h": 0.0, "l": 3000.0, "qty": 1})
	ok(w.stock.is_empty() and w.deliveries.size() == 3, "Bestellung steht im Hof")
	await process_frame
	var pos: Vector3 = site.delivery_pos(0)
	await aim(p, pos + Vector3(-0.1, 0.05, 2.0), pos + Vector3(0, 0.05, 0))
	ok(p._focus != null and p._focus.get_prompt().contains("aufheben"), "Hinweis aufheben")
	p.click_focus()
	ok(not p.carry.is_empty() and w.deliveries.size() == 2 and w.stock.is_empty(), "Linksklick hebt auf, noch nicht im Lager")
	ok(w.hud._held.text.contains("In den Händen"), "Anzeige: " + w.hud._held.text)
	ok(p._hand.get_child_count() == 1, "Material ist in der Hand zu sehen")
	ok(w.pick_delivery(0) != "", "Zweite Lieferung geht nicht, Hände voll")
	ok(w.deliveries.size() == 2, "Lieferung bleibt stehen")
	await process_frame
	var pos1: Vector3 = site.delivery_pos(0)
	await aim(p, pos1 + Vector3(-0.1, 0.05, 2.0), pos1 + Vector3(0, 0.05, 0))
	ok(p._focus != null and p._focus.get_prompt().contains("Hände voll"), "Hinweis Hände voll")
	# Ablegen im angeschauten Fach: Regal 2, Fach 5 ist der obere Boden
	var slot4: Vector3 = site._slot_pos(6 + 4)
	site.door_lager.set_open(true, true)
	await aim(p, Vector3(slot4.x - 1.7, 0.05, slot4.z), slot4 + Vector3(-0.5, 0.3, 0))
	ok(p._focus != null and p._focus.get_prompt().contains("Regal 2, Fach 5"), "Hinweis nennt das Fach: " + str(p._prompt))
	p.click_focus()
	ok(p.carry.is_empty() and w.stock.size() == 1, "Linksklick legt ab")
	ok(int(w.stock[0]["slot"]) == 10, "Liegt genau in Regal 2, Fach 5: %d" % int(w.stock[0]["slot"]))
	ok(not w.rack_menu.visible, "Ablegen öffnet kein Menü")
	ok(site._signs[1].text.contains("Fach 5"), "Schild nennt das Fach")
	# Alle sechs Fächer sind einzeln zu treffen
	var keep_stock: Array = w.stock
	w.stock = []
	for n in 6:
		var at: Vector3 = site._slot_pos(n)
		var eye_z: float = at.z
		await aim(p, Vector3(at.x + 1.7, 0.05, eye_z), at + Vector3(0.5, 0.3, 0))
		ok(p._focus != null and p._focus.get("slot") == n, "Fach %d lässt sich anvisieren" % (n + 1))
		p.set_carry({"material": "S235", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0})
		p.click_focus()
		ok(p.carry.is_empty() and int(w.stock[-1]["slot"]) == n, "Fach %d nimmt das Stück" % (n + 1))
	w.stock = keep_stock
	w._stock_changed()
	await physics_frame
	await physics_frame
	# Volles oder unpassendes Fach legt nicht woanders ab
	w.stock = keep_stock + [{"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0, "slot": 3}]
	p.set_carry({"material": "S235", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0})
	ok(w.store_at(3) != "" and not p.carry.is_empty(), "Fertigschnitt nicht auf Stangen")
	ok(w.rack_prompt(3).contains("passt hier nicht"), "Hinweis sagt das")
	ok(w.store_at(4) == "" and int(w.stock[-1]["slot"]) == 4, "Nächstes Fach geht")
	w.stock = keep_stock
	w._stock_changed()
	# Volles Regal
	var occupied := []
	for s in site.rack_slots(0):
		occupied.append({"material": "S235", "kind": "cut", "d": 0.0, "w": 900.0, "h": 40.0, "l": 3000.0, "slot": s})
	p.set_carry({"material": "S235", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0})
	var keep: Array = w.stock.duplicate()
	w.stock = keep + occupied
	ok(w.store_carried(0) != "" and not p.carry.is_empty(), "Volles Regal nimmt nichts an")
	ok(w.store_carried(1) == "", "Anderes Regal schon")
	w.stock = keep
	w._stock_changed()
	# Werkzeug und Material schließen sich aus
	p.set_carry(b40.duplicate())
	p.set_held(w.mill, "F10")
	ok(p.held.is_empty(), "Mit Material keine Werkzeuge")
	p.clear_carry()
	p.set_held(w.mill, "F10")
	ok(w.pick_delivery(0) != "", "Mit Werkzeug kein Material")
	p.clear_held()
	# Schild am Regal
	w.pick_delivery(0)
	w.store_carried(1)
	w.pick_delivery(0)
	w.store_carried(1)
	var sign_text: String = site._signs[1].text
	ok(sign_text.contains("S235") and sign_text.contains("C45"), "Schild zeigt das Material: " + sign_text)
	ok(sign_text.contains("Ø60") and sign_text.contains("Ø40"), "Schild zeigt die Durchmesser")
	ok(Storage.on_board(w.stock, 10).size() == 3, "Verschiedene Durchmesser in einem Fach")
	ok(site._signs[2].text.contains("leer"), "Leeres Regal: " + site._signs[2].text)
	# Nehmen im Regal-Menü
	w.rack_menu.open()
	var names := []
	for b in w.rack_menu.view.list.find_children("*", "Button", true, false):
		names.append(b.text)
	ok(names.has("Nehmen") and not names.has("An Drehmaschine"), "Schaltfläche Nehmen")
	w.rack_menu.view._take(0)
	ok(not p.carry.is_empty() and w.stock.size() == 2 and not w.rack_menu.visible, "Nehmen legt es in die Hände")
	ok(not p.carry.has("slot"), "Stück hat keinen Platz mehr")
	ok(not site._signs[1].text.contains("S235") or site._signs[1].text.contains("1x"), "Schild aktualisiert")
	# Einspannen an der Maschine
	ok(w.clamp_carried(w.mill) != "", "Rundmaterial nicht in den Schraubstock")
	ok(w.clamp_carried(w.lathe).contains("Bandsäge") and not w.lathe.has_part, "Ganze Stange erst an die Bandsäge")
	var rest_bar: Dictionary = p.carry.duplicate()
	var section := Materials.cut_off(rest_bar, 160.0)
	p.set_carry(section)
	ok(w.clamp_carried(w.lathe) == "" and p.carry.is_empty(), "An der Drehmaschine einspannen")
	ok(w.lathe.has_part and w.lathe.stock_d == 60.0 and w.lathe.stock_len == 160.0, "Abschnitt wird ganz eingespannt")
	ok(float(rest_bar["l"]) == 3000.0 - 160.0 - Materials.KERF, "Stange um Abschnitt und Schnitt kürzer")
	p.set_carry(rest_bar)
	ok(w.store_carried(1) == "", "Rest wieder ablegen")
	var full_cut := {"material": "AW-6082", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0}
	p.set_carry(full_cut)
	ok(w.clamp_carried(w.lathe) != "", "Fertigschnitt nicht an die Drehmaschine")
	ok(w.clamp_carried(w.mill) == "" and p.carry.is_empty(), "Fertigschnitt ist verbraucht")
	ok(w.mill.has_part and w.mill.material == "AW-6082", "Liegt im Schraubstock")
	# Hände werden gespeichert
	p.set_carry(b40.duplicate())
	var st: Dictionary = JSON.parse_string(JSON.stringify(p.get_state()))
	p.clear_carry()
	p.set_state(st)
	ok(not p.carry.is_empty() and p.carry["material"] == "C45", "Material in den Händen gespeichert")
	p.clear_carry()

	# ---- Kacheln
	ok(site.has_cell("workshop", Vector2i(-3, 0)), "Grundhalle gehört dazu")
	ok(site.lager_cells.size() == 4 and site.rack_cells.size() == 4 and site.capacity() == 24, "Alter Stand: 4 Regale, 24 Fächer")
	ok(site.can_buy("workshop", Vector2i(-4, 0)), "Kachel neben der Halle")
	ok(not site.can_buy("workshop", Vector2i(-5, 0)), "Ohne Anschluss nicht")
	ok(not site.can_buy("workshop", Vector2i(0, 0)), "Eigene Kachel nicht")
	ok(not site.can_buy("workshop", Vector2i(0, -3)), "Nördlich der Grundhalle nicht")
	ok(site.can_buy("lager", Vector2i(0, 2)) and site.can_buy("lager", Vector2i(2, 0)), "Lager nach Norden und Osten")
	ok(not site.can_buy("lager", Vector2i(3, 0)), "Lager ohne Anschluss nicht")
	var pw0: int = site.tile_price("workshop")
	await physics_frame
	ok(ray_blocked(Vector3(-11.0, 1.0, 2.0), Vector3(-14.0, 1.0, 2.0)), "Westwand steht")
	w.money = 0
	ok(w.buy_tile("workshop", Vector2i(-4, 0)) != "", "Ohne Geld nicht")
	w.money = pw0
	ok(w.buy_tile("workshop", Vector2i(-4, 0)) == "" and w.money == 0, "Kachel gekauft")
	ok(site.tile_price("workshop") > pw0, "Jede Kachel wird teurer")
	await physics_frame
	await physics_frame
	ok(not ray_blocked(Vector3(-11.0, 1.0, 2.0), Vector3(-14.0, 1.0, 2.0)), "Wand zur neuen Kachel ist weg")
	ok(ray_blocked(Vector3(-11.0, 1.0, -2.0), Vector3(-14.0, 1.0, -2.0)), "Wand der Nachbarkachel steht noch")
	ok(ray_blocked(Vector3(-14.0, 1.0, 2.0), Vector3(-18.0, 1.0, 2.0)), "Neue Kachel hat Außenwand im Westen")
	ok(ray_blocked(Vector3(-14.0, 1.0, 2.0), Vector3(-14.0, 1.0, -2.0)), "Neue Kachel hat Außenwand im Norden")
	ok(ray_blocked(Vector3(-14.0, 2.0, 2.0), Vector3(-14.0, -1.0, 2.0)), "Neue Kachel hat Boden")
	ok(site.can_buy("workshop", Vector2i(-5, 0)) and site.can_buy("workshop", Vector2i(-4, 1)), "Daran lässt sich weiterbauen")
	ok(site.can_buy("workshop", Vector2i(-4, -1)), "Auch quer dazu")
	var cap0: int = site.capacity()
	w.money = 100000
	ok(w.buy_tile("lager", Vector2i(2, 0)) == "", "Lager nach Osten")
	ok(site.capacity() == cap0, "Eine Kachel allein bringt kein Regal")
	ok(w.place_rack(-1, Vector2(26.0, -12.0)) != "", "Ohne Kauf kein Regal")
	ok(w.buy_equipment("rack") == "" and w.inventory["rack"] == 1, "Regal gekauft")
	ok(w.place_rack(-1, Vector2(0.0, 0.0)) != "", "Nicht außerhalb des Lagers")
	ok(w.place_rack(-1, Vector2(15.0, -12.0)) != "", "Kachel hat schon ein Regal")
	ok(w.inventory["rack"] == 1, "Fehlversuch verbraucht nichts")
	ok(w.place_rack(-1, Vector2(26.0, -12.0)) == "" and w.inventory["rack"] == 0, "Regal aufgestellt")
	ok(site.capacity() == cap0 + 6, "Ein Regal bringt 6 Fächer")
	await physics_frame
	await physics_frame
	var east: Rect2 = site.l_rect(Vector2i(2, 0))
	ok(ray_blocked(Vector3(east.get_center().x, 2.0, east.get_center().y), Vector3(east.get_center().x, -1.0, east.get_center().y)), "Lagerkachel hat Boden")
	# Über den Quergang kommt man in die neue Kachel, die Regalreihen stehen Rücken an Rücken
	var cross_z: float = east.end.y - 0.6
	ok(not ray_blocked(Vector3(21.0, 1.0, cross_z), Vector3(27.0, 1.0, cross_z)), "Quergang führt in die neue Kachel")
	ok(not ray_blocked(Vector3(21.0, 0.2, cross_z), Vector3(27.0, 0.2, cross_z)), "Quergang ist auch unten frei")
	# Auch von Reihe zu Reihe im Mittelgang
	ok(not ray_blocked(Vector3(18.0, 1.0, -9.0), Vector3(18.0, 1.0, site.LAGER_Z - site.L_TILE.y * 1.9)), "Mittelgang ist frei")
	ok(ray_blocked(Vector3(east.get_center().x, 1.0, -9.0), Vector3(east.get_center().x, 1.0, -6.0)), "Neue Südwand schließt zum Hof")
	var last_rack: int = site.rack_cells.size() - 1
	ok(site._signs.has(last_rack), "Neues Regal hat ein Schild")
	var sp: Vector3 = site._slot_pos(last_rack * 6)
	ok(east.has_point(Vector2(sp.x, sp.z)), "Regalplätze liegen in der neuen Kachel")
	# Regal-Plätze bleiben beim Ausbau stabil
	var name0: Vector3 = site._slot_pos(0)
	w.buy_tile("lager", Vector2i(0, 2))
	ok(site._slot_pos(0) == name0, "Vorhandene Plätze bleiben, wo sie sind")
	# Lageplan am PC
	var tab = w.office_pc.overlay.site_tab
	tab.refresh()
	var c1: Dictionary = tab.map.cell_at(tab.map.to_map(-22.0, 2.0))
	ok(c1["area"] == "workshop" and c1["cell"] == Vector2i(-6, 0), "Plan: Werkstattkachel unter der Maus")
	var c2: Dictionary = tab.map.cell_at(tab.map.to_map(20.0, -30.0))
	ok(c2["area"] == "lager" and c2["cell"] == Vector2i(1, 2), "Plan: Lagerkachel unter der Maus")
	ok(tab.map.cell_at(tab.map.to_map(20.0, 0.0)).is_empty(), "Plan: Hof ist keine Kachel")
	tab.select("workshop", Vector2i(-8, 0))
	ok(tab.buy_button.disabled, "Kachel ohne Anschluss: kein Kauf")
	tab.select("workshop", Vector2i(-5, 0))
	ok(not tab.buy_button.disabled and tab.buy_button.text.contains("EUR"), "Kaufknopf: " + tab.buy_button.text)
	var n0: int = site.workshop_cells.size()
	tab.buy()
	ok(site.workshop_cells.size() == n0 + 1 and tab.selected.is_empty(), "Kauf über den Plan")
	# Testmodus
	w.set_free_mode(true)
	w.money = 0
	ok(w.buy_tile("workshop", Vector2i(-6, 0)) == "" and w.money == 0, "Testmodus: Kachel gratis")
	ok(w.buy_equipment("bench") == "" and w.money == 0, "Testmodus: Werkbank gratis")
	w.set_free_mode(false)
	w.inventory.erase("bench")
	# Speichern und Laden der Kacheln
	var saved: Dictionary = JSON.parse_string(JSON.stringify(w._site_state()))
	var racks0: int = site.rack_cells.size()
	site.set_tiles([], [])
	ok(site.capacity() == 0, "Ohne Regale kein Platz")
	w._apply_site(saved)
	ok(site.has_cell("workshop", Vector2i(-6, 0)) and site.has_cell("lager", Vector2i(2, 0)), "Kacheln gespeichert")
	ok(site.rack_cells.size() == racks0 and site.rack_cells.has(Vector2i(2, 0)), "Regale gespeichert")
	w._apply_site({"workshop": 1, "lager": 1})
	ok(site.has_cell("workshop", Vector2i(-4, 0)) and site.has_cell("lager", Vector2i(1, 2)), "Alter Spielstand: Stufen werden Kacheln")
	w._apply_site({}, true)
	ok(site.workshop_cells.is_empty() and site.capacity() == 24, "Alter Spielstand behält seine Regale")
	w._apply_site({})
	ok(site.capacity() == 0 and site.lager_cells.size() == 4, "Neues Spiel: Lagerfläche ohne Regale")
	w._apply_site({}, true)

	# ---- Einkauf
	w.money = 500
	var shop = w.office_pc.overlay.shop_tab
	var mt = w.office_pc.overlay.machines_tab
	shop.refresh()
	mt.refresh()
	ok(not shop.buttons["bench"].disabled, "Werkbank bezahlbar")
	ok(mt.buttons["edm"].disabled, "Erodiermaschine zu teuer")
	ok(mt.buttons["lathe"].text == "Schon gekauft", "Drehmaschine steht schon")
	for id in Layout.SPECS:
		ok(not shop.buttons.has(id), "Keine Maschine im Einkauf: " + id)
	ok(w.lathe_bench == null and w.mill_bench == null, "Neues Spiel: keine Werkbank")
	shop._buy("bench")
	ok(w.money == 500 - Layout.BENCH_PRICE and w.inventory["bench"] == 1, "Werkbank gekauft, wartet aufs Aufstellen")
	w.money = 100000
	ok(w.buy_equipment("drill") == "" and w.buy_equipment("drill") != "", "Maschine nur einmal")
	ok(not w.company.owns("drill"), "Aufträge erst, wenn sie steht")

	# ---- Standorte und Bereiche
	ok(lay.check_machine("lathe", Vector2(0.0, -2.0), 0) == "", "Drehmaschine an ihrem Platz erlaubt")
	ok(lay.check_machine("mill", Vector2(6.85, -3.1), 0) == "", "Fräse an ihrem Platz erlaubt")
	ok(site._areas.get_child_count() == 8, "Zwei gelbe Bereiche")
	ok(lay.check_machine("lathe", Vector2(5.0, -3.0), 0).contains("Fräsmaschine"), "Bereiche dürfen nicht kollidieren")
	ok(lay.check_machine("lathe", Vector2(30.0, 0.0), 0) != "", "Nicht außerhalb der Werkstatt")
	ok(lay.check_machine("lathe", Vector2(-6.0, -5.0), 0) == "", "Die Halle ist frei: Dort stand früher die CNC-Fräse")
	ok(lay.check_machine("lathe", Vector2(9.5, 6.0), 0) != "", "Nicht ins Büro")
	ok(lay.check_machine("mill", Vector2(10.5, -2.5), 0) != "", "Nicht vor das Rolltor")
	# Rotation dreht den Bereich
	var turned := Layout.rect_at(Rect2(-1.0, -2.0, 4.0, 3.0), Vector2.ZERO, 1)
	ok(turned.is_equal_approx(Rect2(-2.0, -3.0, 3.0, 4.0)), "Bereich dreht mit: %s" % turned)
	# Drehung passt zum Knoten
	var node := Node3D.new()
	root.add_child(node)
	node.rotation.y = PI / 2.0
	var world_pt: Vector3 = node.to_global(Vector3(1.0, 0, 2.0))
	var turned_pt: Vector2 = Layout._turn(Vector2(1.0, 2.0), 1)
	ok(absf(world_pt.x - turned_pt.x) < 0.001 and absf(world_pt.z - turned_pt.y) < 0.001, "Drehrichtung wie im Spiel")
	node.free()

	# Werkbank aufstellen
	w.inventory["bench"] = 2
	ok(lay.check_bench(Vector2(-5.0, 3.0), 0) != "", "Werkbank nur im Maschinenbereich")
	ok(lay.check_bench(Vector2(0.6, -2.0), 0).contains("zu dicht"), "Nicht in die Maschine")
	ok(lay.check_bench(Vector2(0.6, 0.35), 2) == "", "Im Bereich der Drehmaschine")
	ok(w.place_bench("", Vector2(-5.0, 3.0), 0) != "" and w.lathe_bench == null, "Falscher Platz: nichts passiert")
	ok(w.place_bench("", Vector2(0.6, 0.35), 2) == "", "Werkbank aufgestellt")
	ok(w.lathe_bench != null and w.lathe_bench.machine == w.lathe, "Sie gehört zur Drehmaschine")
	ok(w.inventory["bench"] == 1, "Ein Stück weniger")
	ok(lay.check_bench(Vector2(0.6, 0.35), 2).contains("schon"), "Eine Werkbank je Maschine")
	ok(w.place_bench("", Vector2(6.85, -0.95), 2) == "", "Zweite Werkbank an der Fräse")
	ok(w.mill_bench.machine == w.mill, "Sie gehört zur Fräse")
	ok(w.inventory["bench"] == 0 and w.place_bench("", Vector2(6.85, -0.95), 2) != "", "Keine weitere gekauft")
	# Werkbank umstellen, auch zu einer anderen Maschine
	ok(w.place_bench("lathe", Vector2(1.0, 0.35), 2) == "", "Werkbank umstellen")
	ok(absf(w.lathe_bench.position.x - 1.0) < 0.001, "Sie steht am neuen Platz")

	# Maschine umstellen
	var old_area: Rect2 = lay.area_of("lathe")
	var old_bench: Vector3 = w.lathe_bench.position
	w.lathe.spindle_speed = 500.0
	ok(w.place_machine("lathe", Vector2(-2.0, 3.0), 1).contains("Spindel"), "Nicht bei laufender Spindel")
	w.lathe.spindle_speed = 0.0
	ok(w.place_machine("lathe", Vector2(5.0, -3.0), 0) != "" and w.lathe.position.x == 0.0, "Kollision: Maschine bleibt stehen")
	ok(w.place_machine("lathe", Vector2(-2.0, 3.0), 1) == "", "Drehmaschine umgestellt")
	ok(absf(w.lathe.position.x + 2.0) < 0.001 and absf(w.lathe.position.z - 3.0) < 0.001, "Maschine steht dort")
	ok(absf(w.lathe.rotation.y - PI / 2.0) < 0.001, "Gedreht")
	ok(not lay.area_of("lathe").is_equal_approx(old_area), "Bereich hat sich angepasst")
	ok(lay.area_of("lathe").has_point(Vector2(w.lathe.position.x, w.lathe.position.z)), "Bereich liegt um die Maschine")
	ok(w.lathe_bench.position != old_bench, "Werkbank ist mitgewandert")
	var bp: Vector2 = Vector2(w.lathe_bench.position.x, w.lathe_bench.position.z)
	ok(lay.area_of("lathe").encloses(Layout.bench_rect(bp, lay.benches["lathe"]["rot"]).grow(-0.01)), "Werkbank bleibt im Bereich")
	# Die gelbe Markierung liegt am neuen Platz
	var marks: Array = site._areas.get_children()
	var mark_box := AABB(marks[0].position, Vector3.ZERO)
	for mk in marks:
		mark_box = mark_box.expand(mk.position)
	ok(mark_box.has_point(Vector3(-2.0, mark_box.position.y, 3.0)), "Markierung am neuen Platz")
	await process_frame
	# Bedienen funktioniert am neuen Platz
	w.lathe.interact(p)
	var stand: Vector3 = p.global_position
	ok(Vector2(stand.x, stand.z).distance_to(Vector2(-2.0, 3.0)) < 2.0, "Standplatz wandert mit")
	w.lathe.stop_operating()
	await process_frame
	# Wieder zurück
	ok(w.place_machine("lathe", Vector2(0.0, -2.0), 0) == "", "Zurückstellen")
	# Neue Maschine aufstellen
	ok(w.inventory["drill"] == 1, "Standbohrmaschine wartet")
	ok(w.place_machine("round_grinder", Vector2(-4.0, 3.0), 0) != "", "Nicht gekaufte Maschine nicht")
	ok(w.place_machine("drill", Vector2(-1.0, 4.5), 0) == "", "Standbohrmaschine aufgestellt")
	ok(w.inventory["drill"] == 0 and w.extra_machines.has("drill"), "Sie steht in der Halle")
	ok(w.company.owns("drill"), "Jetzt gehört sie zum Maschinenpark")
	ok(site._areas.get_child_count() == 12, "Dritter gelber Bereich")
	ok(lay.check_bench(Vector2(-0.9, 6.1), 0) == "", "Auch die Bohrmaschine hat eine Werkbank: " + lay.check_bench(Vector2(-0.9, 6.1), 0))
	await physics_frame
	await physics_frame
	# Speichern und Laden des Stellplans
	var ld: Dictionary = {"name": "T", "money": 5, "layout": JSON.parse_string(JSON.stringify(lay.to_state())), "inventory": {"bench": 3}, "lathe": w.lathe.get_state(), "mill": w.mill.get_state()}
	w.extra_machines["drill"].position = Vector3.ZERO
	w._apply_pending(ld)
	await process_frame
	ok(w.extra_machines.has("drill") and absf(w.extra_machines["drill"].position.z - 4.5) < 0.001, "Maschine aus dem Spielstand")
	ok(w.inventory["bench"] == 3, "Lagerbestand an Bauteilen gespeichert")
	ok(w.lathe_bench != null and w.mill_bench != null, "Werkbänke aus dem Spielstand")
	# Neuer Spielstand ohne Plan: Grundaufstellung, keine Werkbänke, keine Zusatzmaschinen
	w._apply_pending({"name": "N", "money": 500})
	await process_frame
	ok(w.lathe_bench == null and w.mill_bench == null, "Neues Spiel ohne Werkbank")
	ok(not w.extra_machines.has("drill"), "Neues Spiel ohne Zusatzmaschine")
	ok(lay.machines.is_empty() and not w.lathe.visible, "Neues Spiel: leere Halle")
	# Alter Spielstand: Werkbänke waren schon da
	w._apply_pending({"name": "A", "money": 1, "lathe": w.lathe.get_state(), "mill": w.mill.get_state()})
	await process_frame
	ok(w.lathe_bench != null and w.mill_bench != null, "Alter Spielstand behält seine Werkbänke")
	w._apply_pending({"name": "N", "money": 100000, "unlock_all": true})
	await process_frame

	# ---- Baumenü auf B
	ok(not menu.menu_open(), "Menü ist zu")
	w.inventory = {"bench": 1}
	menu._input(key_action("build_menu"))
	ok(menu.menu_open() and p.operating == null and p.build_mode, "B startet den Baumodus, man läuft weiter frei")
	var texts := []
	for lb in menu._list.find_children("*", "Label", true, false):
		texts.append(lb.text)
	var joined := "\n".join(PackedStringArray(texts))
	ok(joined.contains("Werkbank"), "Liste zeigt Gekauftes: " + joined)
	ok(not joined.contains("Drehmaschine") and not joined.contains("Fräsmaschine"), "Aufgestellte Maschinen stehen nicht mehr in der Liste")
	# Zifferntaste nimmt aus der Liste
	var k1 := InputEventKey.new()
	k1.keycode = KEY_1
	k1.pressed = true
	menu._input(k1)
	ok(menu.placing and menu.kind == "bench", "Taste 1 nimmt die Werkbank")
	menu.cancel()
	ok(menu.menu_open() and not menu.placing and w.inventory["bench"] == 1, "Zurückgelegt, Baumodus läuft weiter")
	# Anvisieren und E nimmt die Maschine
	await aim(p, Vector3(6.85, 0.05, 1.0), Vector3(6.85, 1.0, -3.1))
	await process_frame
	ok(menu.target.get("item", "") == "mill", "Blick trifft die Fräse: %s" % str(menu.target))
	ok(p._focus == null and p._prompt == "", "Im Baumodus wird nichts bedient")
	ok(menu._hint.text.contains("Fräsmaschine") and menu._hint.text.contains("E nehmen"), "Hinweis: " + menu._hint.text)
	var op_before = p.operating
	menu._input(key_action("interact"))
	ok(menu.placing and menu.kind == "machine" and menu.item == "mill" and p.operating == op_before, "E nimmt die Fräse, statt sie zu bedienen")
	ok(not w.mill.visible, "Sie ist aus der Halle genommen")
	menu.cancel()
	ok(w.mill.visible and absf(w.mill.position.x - 6.85) < 0.001, "Zurückgelegt steht sie wieder da")
	# Regal: anvisieren, nehmen, auf eine freie Kachel stellen
	site.door_lager.set_open(true, true)
	var rack_at: Vector2 = site.rack_center(site.rack_cells[0])
	await aim(p, Vector3(rack_at.x + 2.0, 0.05, rack_at.y), Vector3(rack_at.x, 1.0, rack_at.y + 1.5))
	await process_frame
	ok(menu.target.get("kind", "") == "rack" and int(menu.target["index"]) == 0, "Blick trifft das Regal: %s" % str(menu.target))
	menu.take_target()
	ok(menu.placing and menu.kind == "rack" and menu.move_index == 0, "E nimmt das Regal")
	w.stock = [{"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0, "slot": 0}]
	w._stock_changed()
	w.buy_tile("lager", Vector2i(2, 1))
	ok(w.place_rack(0, site.rack_center(Vector2i(1, 0))) != "", "Belegte Kachel nicht")
	ok(w.place_rack(0, site.rack_center(Vector2i(2, 1))) == "", "Regal umgestellt")
	ok(site.rack_cells[0] == Vector2i(2, 1), "Es steht auf der neuen Kachel")
	ok(int(w.stock[0]["slot"]) == 0 and site._stored.get_child_count() == 1, "Inhalt ist mitgewandert")
	var sp0: Vector3 = site._slot_pos(0)
	ok(site.l_rect(Vector2i(2, 1)).has_point(Vector2(sp0.x, sp0.z)), "Fach 1 liegt jetzt dort")
	menu.cancel()
	w.place_rack(0, site.rack_center(Vector2i(0, 0)))
	w.stock = []
	w._stock_changed()
	menu._input(key_action("build_menu"))
	ok(not menu.menu_open() and not p.build_mode, "B beendet den Baumodus")
	ok(is_equal_approx(p.ray.target_position.z, -p.REACH), "Sichtstrahl wieder kurz")
	menu.open_menu()
	menu._input(key_action("pause"))
	ok(not menu.menu_open(), "Esc beendet")
	ok(not w.pause_menu.visible, "Esc öffnet kein Pause-Menü")
	w.lathe.interact(p)
	menu._input(key_action("build_menu"))
	ok(not menu.menu_open(), "An der Maschine kein Baumenü")
	w.lathe.stop_operating()
	await process_frame
	# Vorschau
	menu.start("machine", "mill")
	ok(menu.placing and p.operating == null, "Mit Vorschau läuft man herum")
	ok(not w.mill.visible, "Die umgestellte Maschine ist genommen")
	ok(not w.job_menu.can_open(), "Dabei kein Auftragsmenü")
	await aim(p, Vector3(-1.0, 0.05, 4.0), Vector3(-1.0, 0.0, 2.0))
	await process_frame
	ok(absf(menu.ghost_pos.x + 1.0) < 0.3 and absf(menu.ghost_pos.y - 2.0) < 0.3, "Vorschau folgt dem Blick: %s" % menu.ghost_pos)
	ok(fmod(absf(menu.ghost_pos.x), menu.SNAP) < 0.001, "Vorschau rastet ein")
	var r0: int = menu.ghost_rot
	var rk := InputEventKey.new()
	rk.keycode = KEY_R
	rk.pressed = true
	menu._input(rk)
	ok(menu.ghost_rot == posmod(r0 + 1, 4), "R dreht")
	# Rot bei Kollision: dort steht die Drehmaschine
	menu.ghost_pos = Vector2(0.0, -2.0)
	menu._update_ghost()
	ok(menu.error != "", "Vorschau meldet Kollision: " + menu.error)
	ok(menu._ghost_area.material_override.albedo_color == menu.BAD, "Vorschau ist rot")
	ok(not menu.confirm() and menu.placing, "Falscher Platz: Vorschau bleibt")
	ok(absf(w.mill.position.x - 6.85) < 0.001, "Maschine bleibt stehen")
	menu.ghost_rot = 0
	menu.ghost_pos = Vector2(-2.5, 3.5)
	menu._update_ghost()
	ok(menu.error == "", "Freier Platz: " + menu.error)
	ok(menu._ghost_area.material_override.albedo_color == menu.GOOD, "Vorschau ist grün")
	ok(menu.confirm() and not menu.placing, "Aufgestellt")
	ok(absf(w.mill.position.x + 2.5) < 0.001, "Fräse steht am neuen Platz")
	ok(w.mill.visible, "Und ist wieder zu sehen")
	ok(menu.active, "Baumodus läuft weiter")
	await process_frame
	ok(not is_instance_valid(menu._ghost_area), "Vorschau ist weg")
	# Abbrechen
	menu.start("machine", "mill")
	var cancel_ev := InputEventMouseButton.new()
	cancel_ev.button_index = MOUSE_BUTTON_RIGHT
	cancel_ev.pressed = true
	menu._input(cancel_ev)
	ok(not menu.placing, "Rechtsklick bricht ab")
	ok(absf(w.mill.position.x + 2.5) < 0.001, "Nichts verändert")
	# Laufende Spindel
	w.mill.spindle_speed = 500.0
	menu.start("machine", "mill")
	ok(not menu.placing, "Laufende Spindel: kein Umstellen")
	w.mill.spindle_speed = 0.0
	menu.close_menu()

	# ---- Holzregal kaufen, aufstellen, umstellen. Paletten, Hubwagen und Sackkarre stehen schon im Lager.
	var pre: int = lay.shelves.size()
	ok(pre == 7 and lay.shelves.all(func(s): return s["pos"].x > 12.0), "Startausstattung steht im Lager (3 Paletten, Hubwagen, Sackkarre, Eimer, Test-Gabelstapler)")
	ok(w.buy_equipment("shelf_wide") == "", "Holzregal gekauft")
	ok(int(w.inventory.get("shelf_wide", 0)) == 1, "Wartet aufs Aufstellen")
	var spot := Vector2.INF
	for gx in range(-10, 11):
		for gz in range(-6, 7):
			var c := Vector2(gx, gz)
			if spot == Vector2.INF and lay.check_shelf("shelf_wide", c, 0) == "" and not Layout.shelf_rect("shelf_wide", c, 0).has_point(Vector2(p.global_position.x, p.global_position.z)):
				spot = c
	ok(spot != Vector2.INF, "Freier Platz für das Regal gefunden")
	menu.open_menu()
	menu.take_from_stock(menu.stock_keys.find("shelf_wide"))
	ok(menu.placing and menu.kind == "shelf", "Regal in der Vorschau")
	menu.ghost_pos = spot
	menu.ghost_rot = 0
	menu._update_ghost()
	ok(menu.error == "", "Regalplatz frei: " + menu.error)
	ok(menu.confirm(), "Regal aufgestellt")
	ok(lay.shelves.size() == pre + 1 and w.shelf_nodes.size() == pre + 1, "Regal steht in der Werkstatt")
	ok(int(w.inventory.get("shelf_wide", 0)) == 0, "Nicht mehr im Bestand")
	ok(lay.check_shelf("shelf_narrow", spot, 1) != "", "Zweites Regal nicht auf dem ersten")
	ok(lay.check_bin(spot, 0) != "", "Spänebehälter nicht im Regal")
	ok(Props.bounds(w.shelf_nodes[pre]).size.y > 2.0, "Regalmodell geladen")
	var lst: Dictionary = lay.to_state()
	ok(lst["shelves"].size() == pre + 1 and lst["shelves"][pre]["size"] == "shelf_wide" and lst["starter_transport"], "Regal wird gespeichert")
	ok(w.place_shelf(0, "shelf_wide", spot, 1) == "" or lay.check_shelf("shelf_wide", spot, 1, 0) != "", "Drehen am Platz")
	menu.close_menu()
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
