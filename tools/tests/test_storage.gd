extends SceneTree
## Regalplätze: Stangen als Pyramide, Fertigschnitte nach Maßen, Regal-Menü per Linksklick.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func bar(d: float, mat := "S235") -> Dictionary:
	return {"material": mat, "kind": "round", "d": d, "w": 0.0, "h": 0.0, "l": 3000.0}
func square(w: float, h: float, mat := "S235") -> Dictionary:
	return {"material": mat, "kind": "square", "d": 0.0, "w": w, "h": h, "l": 3000.0}
func cut(l: float, w: float, h: float, mat := "S235") -> Dictionary:
	return {"material": mat, "kind": "cut", "d": 0.0, "w": w, "h": h, "l": l}
func aim(p, from: Vector3, target: Vector3) -> void:
	p.global_position = from
	p.velocity = Vector3.ZERO
	var eye: Vector3 = from + Vector3(0, 1.62, 0)
	var d: Vector3 = target - eye
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	for i in 6:
		await physics_frame
## Lieferungen aus dem Hof aufheben und ins Regal legen.
func deliver(w) -> void:
	while not w.deliveries.is_empty():
		w.pick_delivery(0)
		w.store_carried(-1)
func _initialize() -> void:
	await process_frame

	# Maße
	ok(Storage.BOARD_L >= Materials.BAR_LEN, "Eine Stange passt der Länge nach auf den Boden")

	# Pyramide 5-4-3-2-1
	ok(Storage.bar_capacity(bar(60.0)) == 15, "Rund Ø60: 15 Stangen")
	ok(Storage.bar_capacity(square(60.0, 40.0)) == 15, "Vierkant 60 x 40: 15 Stangen")
	ok(Storage.bar_capacity(bar(180.0)) == 15, "Rund Ø180 füllt die Tiefe genau")
	ok(Storage.bar_capacity(bar(181.0)) < 15, "Dicker: weniger in der Reihe")
	ok(Storage.bar_capacity(bar(300.0)) == 6, "Rund Ø300: 3 unten, darauf 2 und 1")
	ok(Storage.bar_capacity(square(200.0, 200.0)) == 10, "Vierkant 200: 4+3+2+1")
	ok(Storage.bar_capacity(square(60.0, 300.0)) == 12, "Hohes Vierkant: nur drei Reihen, 5+4+3")
	ok(Storage.bar_capacity(bar(901.0)) == 0, "Zu dick für das Regal")
	ok(Storage.bar_capacity(square(100.0, 1001.0)) == 0, "Zu hoch für das Regal")
	# Lage in der Pyramide
	var item := bar(60.0)
	var same := []
	for i in 15:
		same.append(item)
	var lay_b: Array = Storage.layout_bars(same)
	ok(lay_b.size() == 15, "15 Stangen haben eine Lage")
	var rows := {}
	for i in 15:
		var pos: Vector2 = lay_b[i]
		rows[snappedf(pos.y, 0.01)] = rows.get(snappedf(pos.y, 0.01), 0) + 1
		ok(absf(pos.x) + 30.0 <= Storage.BOARD_D * 0.5, "Stange %d liegt auf dem Boden" % i)
		ok(pos.y + 60.0 <= Storage.BOARD_H, "Stange %d unter dem nächsten Boden" % i)
	var counts: Array = rows.values()
	counts.sort()
	ok(counts == [1, 2, 3, 4, 5], "Reihen 5, 4, 3, 2, 1: " + str(counts))
	ok(is_equal_approx(lay_b[0].x, -120.0) and lay_b[0].y == 0.0, "Erste Stange unten außen")
	ok(is_equal_approx(lay_b[5].x, -90.0) and lay_b[5].y > 0.0, "Zweite Reihe liegt versetzt darauf")
	ok(is_equal_approx(lay_b[14].x, 0.0), "Oberste Stange mittig")
	# Eine Materialart je Boden, Durchmesser dürfen sich unterscheiden
	ok(Storage.fits_with([bar(60.0)], bar(60.0, "C45")), "Gleicher Durchmesser passt dazu")
	ok(Storage.fits_with([bar(60.0)], bar(40.0)), "Anderer Durchmesser auch")
	ok(not Storage.fits_with([bar(60.0)], square(60.0, 60.0)), "Kein Vierkant auf Rundmaterial")
	ok(not Storage.fits_with([bar(60.0)], cut(100.0, 60.0, 40.0)), "Kein Fertigschnitt auf Rundmaterial")
	ok(not Storage.fits_with([cut(100.0, 60.0, 40.0)], bar(60.0)), "Keine Stange auf Fertigschnitt")
	var full := []
	for i in 15:
		full.append(bar(60.0))
	ok(not Storage.fits_with(full, bar(60.0)), "Sechzehnte Stange passt nicht")
	full.pop_back()
	ok(Storage.fits_with(full, bar(60.0)), "Fünfzehnte passt")

	# Fertigschnitt nach Maßen: das Beispiel 100 mm = 60 + 40
	var a := cut(60.0, 50.0, 40.0)
	var b := cut(40.0, 50.0, 40.0)
	var lay: Array = Storage.layout_cut([a, b], 100.0, 50.0)
	ok(lay.size() == 2, "60 und 40 passen nebeneinander auf 100")
	ok(lay[0]["along"] == 0.0 and lay[1]["along"] == 60.0 and lay[1]["across"] == 0.0, "Direkt nebeneinander")
	ok(Storage.layout_cut([a, cut(41.0, 50.0, 40.0)], 100.0, 50.0).is_empty(), "60 und 41 passen nicht auf 100")
	ok(Storage.layout_cut([cut(60.0, 20.0, 10.0), cut(60.0, 20.0, 10.0)], 100.0, 50.0).size() == 2, "Zwei Reihen hintereinander")
	ok(Storage.layout_cut([cut(60.0, 30.0, 10.0), cut(60.0, 30.0, 10.0)], 100.0, 50.0).is_empty(), "Tiefe reicht nicht für zwei Reihen")
	var turned: Array = Storage.layout_cut([cut(30.0, 90.0, 10.0)], 100.0, 50.0)
	ok(turned.size() == 1 and turned[0]["rot"], "Stück wird bei Bedarf gedreht")
	ok(Storage.layout_cut([cut(100.0, 50.0, 60.0)], 100.0, 50.0, 50.0).is_empty(), "Zu hoch für den Boden")
	ok(not Storage.fits_empty(cut(3001.0, 901.0, 10.0)), "Zu groß für jeden Boden")
	ok(Storage.fits_empty(cut(3000.0, 900.0, 1000.0)), "Füllt den Boden genau")
	# Viele kleine Stücke auf dem Standardboden, nichts überlappt
	var many := []
	for i in 40:
		many.append(cut(100.0 + i * 7.0, 60.0, 40.0))
	var places: Array = Storage.layout_cut(many)
	ok(places.size() == 40, "40 Stücke passen")
	for i in places.size():
		var p: Dictionary = places[i]
		var l1: float = many[i]["w"] if p["rot"] else many[i]["l"]
		var w1: float = many[i]["l"] if p["rot"] else many[i]["w"]
		ok(p["along"] + l1 <= Storage.BOARD_L + 0.01 and p["across"] + w1 <= Storage.BOARD_D + 0.01, "Stück %d auf dem Boden" % i)
		for j in range(i + 1, places.size()):
			var q: Dictionary = places[j]
			var l2: float = many[j]["w"] if q["rot"] else many[j]["l"]
			var w2: float = many[j]["l"] if q["rot"] else many[j]["w"]
			var apart: bool = p["along"] + l1 <= q["along"] + 0.01 or q["along"] + l2 <= p["along"] + 0.01 or p["across"] + w1 <= q["across"] + 0.01 or q["across"] + w2 <= p["across"] + 0.01
			ok(apart, "Stücke %d und %d überlappen nicht" % [i, j])

	# Platzsuche
	var st := []
	var one := bar(60.0)
	ok(Storage.find_slot(st, one, 24) == 0, "Erstes Stück auf den ersten Boden")
	one["slot"] = 0
	st.append(one)
	ok(Storage.find_slot(st, bar(60.0), 24) == 0, "Gleiche Stange legt sich dazu")
	ok(Storage.find_slot(st, bar(40.0), 24) == 0, "Andere Stange legt sich auch dazu")
	ok(Storage.find_slot(st, square(40.0, 40.0), 24) == 1, "Vierkant auf den nächsten Boden")
	ok(Storage.find_slot(st, cut(100.0, 60.0, 40.0), 24) == 1, "Fertigschnitt auf den nächsten Boden")
	ok(Storage.used_slots(st) == 1, "Ein Boden belegt")
	ok(Storage.find_slot(st, square(40.0, 40.0), 1) == -1, "Keine freien Böden")
	ok(Storage.find_slot([], bar(901.0), 24) == -1, "Zu großes Stück findet keinen Platz")

	# Im Spiel
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var site = w.site
	var pl = w.player
	var menu = w.rack_menu
	w.money = 100000
	w.stock = []
	# 15 Stangen auf einem Platz, die 16. auf dem nächsten
	var spec := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0, "qty": 16}
	ok(w.order_material(spec) == "", "16 Stangen bestellt")
	deliver(w)
	ok(Storage.on_board(w.stock, 0).size() == 15, "15 Stangen auf dem ersten Platz")
	ok(Storage.on_board(w.stock, 1).size() == 1, "Die 16. auf dem zweiten")
	ok(Storage.used_slots(w.stock) == 2, "Zwei Plätze belegt")
	ok(site._stored.get_child_count() == 16, "Alle Stangen sind zu sehen")
	# Stangen liegen im Regal
	var meshes: Array = site._stored.get_children()
	var slot0: Vector3 = site._slot_pos(0)
	for i in 15:
		var pos: Vector3 = meshes[i].position
		ok(absf(pos.x - slot0.x) <= Storage.BOARD_D * 0.0005, "Stange %d innerhalb der Regaltiefe" % i)
		ok(absf(pos.z - slot0.z) <= 0.001, "Stange %d längs mittig" % i)
		ok(pos.y >= slot0.y and pos.y <= slot0.y + Storage.BOARD_H * 0.001, "Stange %d unter dem nächsten Boden" % i)
	ok(meshes[14].position.y > meshes[0].position.y, "Oben liegen Stangen auf den unteren")
	# Regalfach und Lagerabschnitt passen zusammen
	ok(site.L_TILE.y >= 2.0 * (Storage.BOARD_L * 0.001 + 0.08), "Zwei Fächer und Stützen passen in eine Kachel")
	for i in site.capacity():
		ok(site.slot_name(i).contains("Regal") and site.slot_name(i).contains("Fach"), "Platz hat einen Namen %d" % i)
	ok(site._slot_pos(0).z != site._slot_pos(1).z, "Zwei Fächer je Boden")
	ok(absf(absf(site._slot_pos(0).z - site._slot_pos(1).z) - (Storage.BOARD_L * 0.001 + 0.08)) < 0.001, "Fachabstand passt zu den Stützen")
	# Abschnitt absägen verbraucht vorn in der Liste, Rest bleibt auf dem Boden
	ok(w.load_stock(0, 160.0) == "", "Abschnitt")
	ok(w.stock[0]["slot"] == 0, "Stange bleibt auf ihrem Platz")
	# Fertigschnitte auf einen Boden
	w.stock = []
	w.deliveries = []
	w.order_material({"material": "AW-6082", "kind": "cut", "d": 0.0, "w": 80.0, "h": 40.0, "l": 120.0, "qty": 3})
	deliver(w)
	ok(Storage.on_board(w.stock, 0).size() == 3, "Drei Fertigschnitte auf einem Platz")
	# Zu Großes lässt sich gar nicht erst bestellen
	var money0: int = w.money
	var huge := {"material": "S235", "kind": "cut", "d": 0.0, "w": 1000.0, "h": 1200.0, "l": 3100.0, "qty": 1}
	ok(w.order_material(huge) != "" and w.deliveries.is_empty() and w.money == money0, "Zu großes Stück lehnt die Bestellung ab")
	var thick := {"material": "S235", "kind": "round", "d": 950.0, "w": 0.0, "h": 0.0, "l": 3000.0, "qty": 1}
	ok(w.order_material(thick) != "" and w.money == money0, "Zu dicke Stange ebenso")
	# Alter Spielstand ohne Plätze
	w._apply_pending({"name": "T", "money": 1, "unlock_all": true, "stock": [bar(60.0), bar(60.0), cut(100.0, 60.0, 40.0)]})
	ok(w.stock[0]["slot"] == 0 and w.stock[1]["slot"] == 0 and w.stock[2]["slot"] == 1, "Alte Bestände werden einsortiert")
	# Speichern erhält die Plätze
	var js: Array = JSON.parse_string(JSON.stringify(w.stock))
	w._apply_pending({"name": "T", "money": 1, "unlock_all": true, "stock": js})
	ok(int(w.stock[2]["slot"]) == 1, "Plätze aus dem Spielstand")
	ok(site._stored.get_child_count() == 3, "Bestand nach dem Laden zu sehen")

	# Linksklick auf das Regal öffnet das Menü
	var rack_target: Vector3 = site._slot_pos(0) + Vector3(0, 0.5, 0)
	var stand: Vector3 = Vector3(site._slot_pos(0).x + 1.6, 0.05, site._slot_pos(0).z)
	await aim(pl, stand, rack_target)
	ok(pl._focus != null and pl._focus.get_prompt().contains("Linksklick") and pl._focus.get_prompt().contains("Lager"), "Regal lässt sich anvisieren")
	ok(not menu.visible, "Menü ist zu")
	if pl._focus:
		pl.click_focus()
	ok(menu.visible and pl.operating == menu, "Linksklick öffnet das Regal-Menü")
	ok(menu.view.list.get_child_count() == 2, "Alle Materialien stehen im Menü, gleiche in einer Zeile")
	ok(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE or DisplayServer.get_name() == "headless", "Mauszeiger frei")
	# Dasselbe wie am PC
	var labels := []
	for lb in menu.view.list.find_children("*", "Label", true, false):
		labels.append(lb.text)
	var text := "\n".join(PackedStringArray(labels))
	ok(text.contains("Rund Ø60") and text.contains("Fertigschnitt 100 x 60 x 40"), "Maße stehen da: " + text)
	ok(text.contains("2 x") and text.contains("1 x"), "Stückzahl steht da: " + text)
	ok(text.contains("Fach"), "Fach steht da")
	var btns := []
	for bt in menu.view.list.find_children("*", "Button", true, false):
		btns.append(bt.text)
	ok(btns.has("Nehmen"), "Material lässt sich aus dem Regal nehmen")
	w.office_pc.overlay.stock_view.refresh()
	ok(w.office_pc.overlay.stock_view.list.get_child_count() == 2, "PC zeigt denselben Bestand")
	var pc_btns: Array = w.office_pc.overlay.stock_view.list.find_children("*", "Button", true, false)
	ok(pc_btns.is_empty(), "Am PC lässt sich nichts herausnehmen")
	var pe := InputEventAction.new()
	pe.action = "pause"
	pe.pressed = true
	menu._input(pe)
	ok(not menu.visible and pl.operating == null, "Esc schließt")
	ok(not w.pause_menu.visible, "Esc öffnet dabei nicht das Pause-Menü")
	menu.open()
	var ie := InputEventAction.new()
	ie.action = "interact"
	ie.pressed = true
	menu._input(ie)
	ok(not menu.visible, "E schließt")
	# Auftragsmenü und Regal-Menü sperren sich
	menu.open()
	w.job_menu.open()
	ok(not w.job_menu.visible, "Kein Auftragsmenü über dem Regal-Menü")
	menu.close()
	w.lathe.interact(pl)
	menu.open()
	ok(not menu.visible, "An der Maschine kein Regal-Menü")
	w.lathe.stop_operating()
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
