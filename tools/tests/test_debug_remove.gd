extends SceneTree
## Debug-Menü: angeschaute Objekte entfernen (Kiste, Behälter, Werkbank, liegender Gegenstand).
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var lay = w.layout

	ok(w.debug_target(null).is_empty(), "Ohne Treffer nichts im Blick")
	ok(w.debug_remove({}) != "", "Leeres Ziel meldet Fehler")

	# ---- Kiste neben der Werkbank der Drehmaschine
	if not lay.benches.has("lathe"):
		w.inventory["bench"] = 1
		w.place_bench("", Vector2(0.6, 0.35), 2)
	ok(lay.benches.has("lathe"), "Werkbank steht")
	w.inventory["crate_s"] = 1
	var spot: Vector2 = floor_spot(lay, "crate_s", "lathe")
	ok(spot != Vector2.INF and w.place_crate(-1, "crate_s", spot, 0) == "", "Kiste aufgestellt")
	await physics_frame
	if lay.crates.size() > 0:
		var n0: int = lay.crates.size()
		var hit = w.crate_nodes[0].find_children("*", "CollisionObject3D", true, false)
		ok(not hit.is_empty(), "Kiste hat einen Körper")
		var t: Dictionary = w.debug_target(hit[0])
		ok(t.get("kind", "") == "crate", "Kiste wird erkannt")
		ok(w.debug_remove(t) == "", "Kiste entfernt")
		ok(lay.crates.size() == n0 - 1, "Kiste fehlt im Layout")
		await process_frame
		ok(w.crate_nodes.size() == n0 - 1, "Kistenknoten neu aufgebaut")

	# ---- Maschine bleibt
	var mh = w.lathe.find_children("*", "CollisionObject3D", true, false)
	if not mh.is_empty():
		var mt: Dictionary = w.debug_target(mh[0])
		if mt.get("kind", "") == "machine":
			ok(w.debug_remove(mt) != "", "Maschine wird nicht entfernt")

	# ---- Werkbank (ohne Kisten)
	var removed_bench := false
	for id in lay.benches.keys():
		if lay.crates_of(id) == 0:
			var bt := {"kind": "bench", "item": id, "index": -1, "title": "Werkbank"}
			ok(w.debug_remove(bt) == "", "Werkbank entfernt")
			removed_bench = true
			ok(not lay.benches.has(id) and not w.bench_nodes.has(id), "Werkbank weg")
			break

	ok(removed_bench, "Eine Werkbank ohne Kisten gefunden")

	# ---- Liegender Gegenstand
	var d = load("res://scripts/world/dropped_item.gd").spawn(w, w.player, {"material": "S235", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0}, Vector3(0, 1, 4), 0.0)
	await physics_frame
	var dt: Dictionary = w.debug_target(d)
	ok(dt.get("kind", "") == "dropped", "Liegender Gegenstand erkannt")
	ok(w.debug_remove(dt) == "", "Gegenstand entfernt")
	ok(not get_nodes_in_group_has(d), "Gegenstand nicht mehr im Spielstand")

	# ---- Beladene Lieferpalette aus dem Shop
	w.money = 1000000
	w.deliveries = []
	var spec := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 1000.0, "qty": 3}
	ok(w.order_material(spec) == "", "Lieferung bestellt")
	spec["material"] = "C45"
	w.order_material(spec)
	await physics_frame
	var g: Dictionary = w.delivery_view()[0]
	var body: Array = w.site._deliveries.get_child(0).find_children("*", "CollisionObject3D", true, false)
	ok(not body.is_empty(), "Lieferpalette hat einen Körper")
	var pt: Dictionary = w.debug_target(body[0])
	ok(pt.get("kind", "") == "delivery" and str(pt.get("item", "")) == str(g["key"]), "Lieferpalette erkannt")
	ok(str(pt.get("title", "")).contains("3 Stück"), "Titel nennt die Stückzahl: %s" % pt.get("title", ""))
	ok(w.debug_remove(pt) == "", "Lieferpalette entfernt")
	await physics_frame
	ok(w.deliveries.size() == 3 and w.delivery_view().size() == 1, "Nur die andere Palette bleibt")
	ok(w.site._deliveries.get_child_count() == 1, "Im Hof steht noch eine Palette")

	# ---- Nach dem Entfernen zielt das Menü neu: zwei Gegenstände hintereinander im Blickstrahl
	var cut := {"material": "S235", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0}
	var dl = load("res://scripts/world/dropped_item.gd")
	var front = dl.spawn(w, w.player, cut.duplicate(), Vector3(0, 3, 6), 0.0)
	var back = dl.spawn(w, w.player, cut.duplicate(), Vector3(0, 3, 7), 0.0)
	front.freeze = true
	back.freeze = true
	await physics_frame
	await physics_frame
	var dm = w.debug_menu
	dm.open()
	dm._look_from = Vector3(0, 3, 5)
	dm._look_to = Vector3(0, 3, 8)
	dm._look = dm.look_again()
	ok(dm._look.get("node") == front, "Vorderer Gegenstand im Blick")
	dm._remove_looked()
	for i in 4:
		await physics_frame
	ok(dm._look.get("node") == back, "Nach dem Entfernen ist der hintere im Blick, ohne neu zu öffnen")
	dm._remove_looked()
	for i in 4:
		await physics_frame
	ok(not get_nodes_in_group_has(back), "Auch der hintere entfernt")
	dm.close()

	# ---- Debug-Menü öffnen und Knopf drücken ohne Ziel
	w.debug_menu.open()
	await process_frame
	ok(w.debug_menu.visible, "Debug-Menü offen")
	w.debug_menu._remove_looked()
	w.debug_menu.close()

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
func floor_spot(lay, size_id: String, bench: String) -> Vector2:
	var area: Rect2 = lay.bench_area(bench).grow(1.2)
	var x := area.position.x
	while x <= area.end.x:
		var z := area.position.y
		while z <= area.end.y:
			var p := Vector2(x, z)
			if lay.check_crate(size_id, p, 0) == "" and not lay.crate_on_top(size_id, p, 0, bench):
				return p
			z += 0.1
		x += 0.1
	return Vector2.INF
func get_nodes_in_group_has(n) -> bool:
	return root.get_tree().get_nodes_in_group("dropped_item").has(n)
