extends SceneTree
## Lieferpaletten im Hof: Mit Gabelstapler und Hubwagen anheben, samt Material mitnehmen, in Hof, Werkstatt oder Lager
## wieder absetzen (blockierte Stellen werden abgelehnt), Speichern und Laden der verschobenen Lage, danach
## das Material wie gewohnt einzeln aufheben.
var checks := 0
var fails := 0
var pl = null
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func hold(action: String, n: int) -> void:
	Input.action_press(action)
	for i in n:
		await physics_frame
	Input.action_release(action)


func idx_of(w, id: String) -> int:
	for i in w.layout.shelves.size():
		if str(w.layout.shelves[i]["size"]) == id:
			return i
	return -1


func group_of(w, key: String) -> Dictionary:
	for g in w.delivery_view():
		if str(g["key"]) == key:
			return g
	return {}


func xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Hubwagen so hinstellen, dass die Lastmitte bei at liegt (Gabel zeigt in Richtung phi).
func jack_to(cart, at: Vector2, phi: float) -> void:
	var fwd := Vector2(cos(phi), -sin(phi))
	cart.place(at - fwd * Shelf.JACK_LOAD_X, phi)
	var h: Vector2 = cart.hold_point(-cart.forward())
	pl.global_position = Vector3(h.x, 0.05, h.y)


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 5000, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	w.start_day()
	var p = w.player
	pl = p
	var site = w.site

	# ---------------------------------------------------- Aufstellung: zwei Paletten im Raster
	var item_a := {"material": "S235", "kind": "round", "d": 40.0, "w": 0.0, "h": 0.0, "l": 1000.0}
	var item_b := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 1000.0}
	w.stock = []
	w.deliveries = [item_a.duplicate(), item_a.duplicate(), item_a.duplicate(), item_b.duplicate()]
	w.delivery_spots = {}
	w._deliveries_changed()
	var ka: String = w.site.delivery_key(item_a)
	var kb: String = w.site.delivery_key(item_b)
	var ga := group_of(w, ka)
	var gb := group_of(w, kb)
	ok(not ga.is_empty() and not gb.is_empty() and w.delivery_view().size() == 2, "Zwei Paletten")
	ok(xz(ga["pos"]).distance_to(xz(w.site.delivery_pos(0))) < 0.01 and xz(gb["pos"]).distance_to(xz(w.site.delivery_pos(1))) < 0.01, "Ohne Eintrag im Raster wie bisher")
	ok(site._deliveries.get_child_count() == 2 and w.delivery_spots.is_empty(), "Beide sichtbar, noch nichts verschoben")
	var pos_a: Vector2 = xz(ga["pos"])
	var pos_b: Vector2 = xz(gb["pos"])
	# Die Palette hat Öffnungen für die Zinken (Hubwagen) und die Ware obendrauf
	var shapes := 0
	for c in site._deliveries.get_child(0).get_children():
		if c is StaticBody3D:
			shapes += c.get_child_count()
	ok(shapes >= 10, "Palette mit Klötzen und Öffnungen statt Vollkörper (%d Formen)" % shapes)

	# ---------------------------------------------------- Stapler: aufnehmen
	var fi := idx_of(w, "forklift")
	var start: Vector2 = w.layout.shelves[fi]["pos"]
	p.global_position = Vector3(start.x, 0.05, start.y + 1.6)
	await frames(2)
	w.forklift_click(fi)
	var f = w.forklift
	ok(f != null and p.driving_forklift(), "Auf dem Stapler")
	f.place(pos_a - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	await frames(2)
	await hold("fork_up", 40)
	ok(f.load_n == 1 and f.load_goods == ka, "Heben nimmt die Lieferpalette mit (%s)" % f.load_goods)
	ok(w.delivery_spots.has(ka) and bool(w.delivery_spots[ka]["carried"]), "Palette ist als getragen vermerkt")
	ok(w.delivery_spots.has(kb) and not bool(w.delivery_spots[kb]["carried"]), "Die andere Palette bleibt, wo sie war")
	ok(xz(group_of(w, kb)["pos"]).distance_to(pos_b) < 0.01, "Andere Palette rückt nicht nach")
	ok(site._deliveries.get_child_count() == 1, "Vom Boden verschwunden")
	await frames(2)
	var stack0: Node = f.parts["load"].get_child(0)
	var goods_node: Node = stack0.get_node_or_null("Goods")
	ok(goods_node != null and goods_node.get_child_count() == 3, "Ware liegt sichtbar auf der Gabelpalette (%d Stück)" % (goods_node.get_child_count() if goods_node else -1))
	ok(w.deliveries.size() == 4, "Material bleibt in deliveries")
	ok(w.forklift_leave() != "" and p.driving_forklift(), "Mit Lieferpalette nicht aussteigen")
	# Mit der Palette fahren und im Hof absetzen
	var drop_to := Vector2(27.5, -1.0)
	f.place(drop_to - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	await frames(2)
	await hold("fork_down", 60)
	ok(f.load_n == 0 and f.load_goods == "", "Ganz abgesenkt: abgesetzt")
	var sp: Dictionary = w.delivery_spots.get(ka, {})
	ok(not sp.is_empty() and not bool(sp["carried"]) and (sp["pos"] as Vector2).distance_to(drop_to) < 0.05, "Steht jetzt im Hof bei %s" % sp.get("pos"))
	ok(int(sp.get("rot", -1)) == 1, "Drehung wie aufgenommen (rot %s)" % sp.get("rot"))
	ok(site._deliveries.get_child_count() == 2, "Wieder sichtbar")

	# ---------------------------------------------------- Stapler: Absetzen an blockierter Stelle
	f.place(drop_to - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	f.lift = 0.0
	await frames(2)
	await hold("fork_up", 40)
	ok(f.load_goods == ka, "Von dort wieder aufgenommen")
	f.lift = 0.0
	f.place(pos_b + Vector2(0.3, 0.0) - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	await frames(2)
	var err: String = w.forklift_drop(f)
	ok(err.contains("Lieferung") and f.load_goods == ka and bool(w.delivery_spots[ka]["carried"]), "Auf einer anderen Lieferpalette abgelehnt: " + err)
	f.place(Vector2(38.0, 0.0) - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	await frames(2)
	err = w.forklift_drop(f)
	ok(err != "" and f.load_goods == ka, "Außerhalb des Zauns abgelehnt: " + err)
	f.place(Vector2(32.3, -4.5) - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	await frames(2)
	err = w.forklift_drop(f)
	ok(err != "" and f.load_goods == ka, "Im Container abgelehnt: " + err)
	var m_at: Vector2 = w.layout.machines["lathe"]["pos"]
	f.place(m_at - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	await frames(2)
	err = w.forklift_drop(f)
	ok(err != "" and f.load_goods == ka, "In der Maschine abgelehnt: " + err)
	w.layout.shelves.append({"size": "pallet", "pos": Vector2(-8.0, 5.5), "rot": 0, "stack": 2})
	w._rebuild_stands()
	f.place(Vector2(-8.0, 5.5) - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	await frames(2)
	err = w.forklift_drop(f)
	ok(err != "" and f.load_goods == ka, "Auf einem Palettenstapel abgelehnt: " + err)
	w.layout.shelves.remove_at(w.layout.shelves.size() - 1)
	w._rebuild_stands()

	# ---------------------------------------------------- Stapler: in der Werkstatt absetzen
	var hall := Vector2(-8.0, 5.5)
	f.place(hall - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	f.lift = 0.0
	await frames(2)
	err = w.forklift_drop(f)
	if err == "":
		f.load_n = 0
		f.load_goods = ""
	ok(err == "" and (w.delivery_spots[ka]["pos"] as Vector2).distance_to(hall) < 0.05, "In der Werkstatt abgesetzt: " + err)
	await frames(2)
	ok(site._deliveries.get_child_count() == 2, "Dort sichtbar")
	ok(w.layout.check_shelf("pallet", hall, 1) != "", "Der Platz ist jetzt belegt")
	# und im Lager
	var lager := Vector2(15.0, -12.0)
	f.place(lager - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	f.lift = 0.0
	await frames(2)
	await hold("fork_up", 5)
	f.place(hall - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	await frames(2)
	await hold("fork_up", 40)
	ok(f.load_goods == ka, "Aus der Werkstatt aufgenommen")
	f.place(lager - Vector2(1, 0) * f.FORK_CENTER, 0.0)
	f.lift = 0.0
	await frames(2)
	err = w.forklift_drop(f)
	if err == "":
		f.load_n = 0
		f.load_goods = ""
	ok(err == "" and (w.delivery_spots[ka]["pos"] as Vector2).distance_to(lager) < 0.05, "Im Lager abgesetzt: " + err)

	# ---------------------------------------------------- Speichern und Laden
	var leave: String = w.forklift_leave()
	ok(leave == "" and not p.driving_forklift(), "Ausgestiegen: " + leave)
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.save_data()))
	ok(d.has("delivery_spots") and (d["delivery_spots"] as Dictionary).has(ka), "Spielstand enthält die verschobene Lage")
	w.delivery_spots = {}
	w._deliveries_changed()
	ok(xz(group_of(w, ka)["pos"]).distance_to(lager) > 1.0, "Ohne Eintrag stünde sie wieder im Raster")
	w._apply_pending(d)
	await process_frame
	ok(w.delivery_spots.has(ka) and (w.delivery_spots[ka]["pos"] as Vector2).distance_to(lager) < 0.01 and int(w.delivery_spots[ka]["rot"]) == 1, "Lage nach dem Laden: %s" % w.delivery_spots.get(ka))
	ok(xz(group_of(w, ka)["pos"]).distance_to(lager) < 0.01 and site._deliveries.get_child_count() == 2, "Palette steht nach dem Laden dort")
	# Alter Spielstand ohne das Feld lädt
	var old: Dictionary = d.duplicate(true)
	old.erase("delivery_spots")
	w._apply_pending(old)
	await process_frame
	ok(w.delivery_spots.is_empty() and w.deliveries.size() == 4 and site._deliveries.get_child_count() == 2, "Spielstand ohne Feld: Raster wie bisher")
	w._apply_pending(d)
	await process_frame

	# ---------------------------------------------------- Einzeln aufheben wie bisher
	var ga2 := group_of(w, ka)
	ok(w.delivery_prompt(int(ga2["index"])).contains("3 Stück"), "Hinweis: " + w.delivery_prompt(int(ga2["index"])))
	ok(w.pick_delivery(int(ga2["index"])) == "" and not p.hands_free(), "Material per Linksklick aufgehoben")
	ok(w.deliveries.size() == 3 and w.delivery_spots.has(ka), "Zwei Stücke liegen noch dort")
	p.clear_carry()
	for k in 2:
		w.pick_delivery(int(group_of(w, ka)["index"]))
		p.clear_carry()
	ok(not w.delivery_spots.has(ka) and w.deliveries.size() == 1, "Ist die Palette leer, ist der Platz vergessen")

	# ---------------------------------------------------- Hubwagen
	w.deliveries = [item_a.duplicate(), item_a.duplicate(), item_b.duplicate()]
	w.delivery_spots = {}
	w._deliveries_changed()
	await frames(2)
	ga = group_of(w, ka)
	gb = group_of(w, kb)
	pos_a = xz(ga["pos"])
	pos_b = xz(gb["pos"])
	var ji := idx_of(w, "pallet_jack")
	var jpos: Vector2 = w.layout.shelves[ji]["pos"]
	p.global_position = Vector3(jpos.x - 3.0, 0.05, jpos.y + 3.0)
	(w.shelf_nodes[ji] as Shelf).interact(p)
	ok(p.driving_jack(), "Hubwagen übernommen")
	var cart: JackCart = p.jack_cart
	# Zinken stecken nicht darunter: nichts passiert
	jack_to(cart, pos_a + Vector2(0.0, 2.0), PI / 2.0)
	await frames(2)
	w.jack_lift()
	ok(p.jack_load() == 0 and w.delivery_spots.is_empty(), "Zinken nicht unter der Palette: keine Last")
	# Längs unterfahren (Gabel entlang der langen Seite = Z)
	jack_to(cart, pos_a, PI / 2.0)
	await frames(2)
	w.jack_lift()
	ok(p.jack_load() == 1 and p.jack_goods() == ka and not p.jack_cross(), "Hubwagen hebt die Lieferpalette längs (%s)" % p.jack_goods())
	ok(bool(w.delivery_spots[ka]["carried"]) and site._deliveries.get_child_count() == 1, "Vom Boden verschwunden")
	await frames(2)
	ok(cart._load != null and cart._load.get_node_or_null("Goods") != null, "Ware liegt auf dem Hubwagen")
	# Absetzen auf einer anderen Palette abgelehnt
	jack_to(cart, pos_b + Vector2(0.2, 0.0), PI / 2.0)
	await frames(2)
	w.jack_lift()
	ok(p.jack_load() == 1 and p.jack_goods() == ka, "Auf einer anderen Lieferpalette nicht absetzbar")
	# Absetzen im Hof, schräg genug nicht, gerade schon
	var spot_j := Vector2(28.0, 3.0)
	jack_to(cart, spot_j, 1.2)
	await frames(2)
	w.jack_lift()
	ok(p.jack_load() == 1, "Zu schräg: bleibt auf den Zinken")
	jack_to(cart, spot_j, PI / 2.0)
	await frames(2)
	w.jack_lift()
	ok(p.jack_load() == 0 and not bool(w.delivery_spots[ka]["carried"]) and (w.delivery_spots[ka]["pos"] as Vector2).distance_to(spot_j) < 0.05, "Im Hof abgesetzt")
	ok(int(w.delivery_spots[ka]["rot"]) == 1 and site._deliveries.get_child_count() == 2, "Mit gerundeter Drehung, wieder sichtbar")
	# Quer unterfahren: Gabel entlang X
	jack_to(cart, spot_j, 0.0)
	await frames(2)
	w.jack_lift()
	ok(p.jack_load() == 1 and p.jack_goods() == ka and p.jack_cross(), "Auch quer unterfahrbar")
	# Parken mit Last
	w.jack_park()
	await frames(2)
	var pj := idx_of(w, "pallet_jack")
	ok(not p.driving_jack() and pj >= 0 and str(w.layout.shelves[pj].get("goods", "")) == ka and int(w.layout.shelves[pj]["load"]) == 1, "Geparkt mit Lieferpalette")
	ok(bool(w.delivery_spots[ka]["carried"]) and site._deliveries.get_child_count() == 1, "Palette bleibt am Hubwagen")
	ok((w.shelf_nodes[pj] as Shelf).cargo_goods == ka, "Geparkter Hubwagen zeigt die Ware")
	# Speichern und Laden mit geparktem Hubwagen
	var d2: Dictionary = JSON.parse_string(JSON.stringify(w.save_data()))
	w._apply_pending(d2)
	await process_frame
	pj = idx_of(w, "pallet_jack")
	ok(pj >= 0 and str(w.layout.shelves[pj].get("goods", "")) == ka and bool(w.delivery_spots[ka]["carried"]), "Nach dem Laden hängt die Palette noch am Hubwagen")
	# Wieder greifen: Goods-Key erhalten
	p.global_position = Vector3(spot_j.x, 0.05, spot_j.y + 3.0)
	(w.shelf_nodes[pj] as Shelf).interact(p)
	ok(p.driving_jack() and p.jack_goods() == ka and p.jack_load() == 1, "Hubwagen greift samt Lieferpalette")
	# Spielstand während der Fahrt
	var ps: Dictionary = p.get_state()
	ok(str(ps["carry"].get("goods", "")) == ka, "Fahrt-Spielstand enthält die Lieferpalette")
	# Abstellen in der Werkstatt
	cart = p.jack_cart
	jack_to(cart, Vector2(-8.0, 5.5), 0.0)          # die Last liegt quer: Wagen längs X, Palette längs Z
	await frames(2)
	w.jack_lift()
	ok(p.jack_load() == 0 and (w.delivery_spots[ka]["pos"] as Vector2).distance_to(Vector2(-8.0, 5.5)) < 0.05, "In der Werkstatt abgesetzt")
	w.jack_park()
	# Verwaiste Markierung (kein Fahrzeug trägt sie) gibt die Palette am letzten Ort wieder frei
	w.delivery_spots[kb] = {"pos": pos_b, "rot": 1, "carried": true}
	w._release_orphan_goods()
	ok(not bool(w.delivery_spots[kb]["carried"]), "Verwaiste Markierung wird gelöst")
	# Aufheben
	var gi := int(group_of(w, ka)["index"])
	ok(w.pick_delivery(gi) == "" and w.deliveries.size() == 2, "Aufheben nach dem Absetzen")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
