extends SceneTree
## Leere Europaletten von Hand stapeln: aufnehmen, auflegen, abstellen, Stapelgrenze, Speichern.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func pallets(w) -> Array:
	var out := []
	for i in w.layout.shelves.size():
		if str(w.layout.shelves[i]["size"]) == "pallet":
			out.append(i)
	return out


func total(w) -> int:
	var n := 0
	for i in pallets(w):
		n += int(w.layout.shelves[i].get("stack", 1))
	return n


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 250, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	ok(pallets(w).size() == 3 and total(w) == 3, "Drei Startpaletten im Lager")
	var first: int = pallets(w)[0]
	ok(w.pallet_prompt(first).contains("aufnehmen"), "Hinweis mit freien Händen: " + w.pallet_prompt(first))

	# Aufnehmen: Die Palette verschwindet vom Boden und liegt in den Händen
	w.pallet_click(first)
	ok(p.carrying_pallet() and not p.hands_free(), "Palette in den Händen")
	ok(pallets(w).size() == 2 and total(w) == 2, "Eine Palette weniger am Boden")
	var target: int = pallets(w)[0]
	ok(w.pallet_prompt(target).contains("auflegen"), "Hinweis mit Palette in den Händen: " + w.pallet_prompt(target))

	# Auflegen: Stapel wächst, Hände frei, Anzeige zeigt zwei Paletten
	w.pallet_click(target)
	ok(p.hands_free(), "Palette aufgelegt, Hände frei")
	ok(int(w.layout.shelves[target]["stack"]) == 2 and total(w) == 3, "Stapel aus zwei Paletten")
	var node: Shelf = w.shelf_nodes[target]
	ok(node.stack == 2 and node.get_child_count() >= 3, "Zwei Palettenmodelle übereinander")
	ok(w.pallet_prompt(target).contains("2 Europaletten"), "Hinweis nennt den Stapel")

	# Vom Stapel wieder eine herunternehmen
	w.pallet_click(target)
	ok(p.carrying_pallet() and int(w.layout.shelves[target]["stack"]) == 1, "Oberste Palette vom Stapel genommen")

	# Abstellen auf freiem Lagerboden, an einem besetzten Platz nicht
	var busy: Vector2 = w.layout.shelves[target]["pos"]
	ok(w.put_pallet(busy) != "" and p.carrying_pallet(), "Auf einem besetzten Platz nicht abstellbar")
	ok(w.put_pallet(Vector2(-200, -200)) != "" and p.carrying_pallet(), "Außerhalb von Werkstatt und Lager nicht")
	var free := Vector2(21.0, -16.0)
	ok(w.put_pallet(free) == "", "Auf freiem Lagerboden abgestellt")
	ok(p.hands_free() and pallets(w).size() == 3 and total(w) == 3, "Wieder drei Paletten am Boden")

	# Stapelgrenze
	var top: int = pallets(w)[0]
	w.layout.shelves[top]["stack"] = Shelf.MAX_STACK
	var other: int = pallets(w)[1]
	w.pallet_click(other)
	ok(p.carrying_pallet(), "Andere Palette aufgenommen")
	top = pallets(w)[0]
	w.pallet_click(top)
	ok(p.carrying_pallet() and int(w.layout.shelves[top]["stack"]) == Shelf.MAX_STACK, "Voller Stapel nimmt keine mehr")
	ok(w.pallet_prompt(top).contains("voll"), "Hinweis: Stapel voll")

	# Ablegen-Taste: vor der Figur abstellen, nicht fallen lassen
	p.global_position = Vector3(21.0, 0.05, -12.0)
	p.yaw = 0.0
	p.rotation.y = 0.0
	p.pitch = -0.9
	p.head.rotation.x = -0.9
	await physics_frame
	var dropped = p.drop()
	ok(dropped == null and p.hands_free(), "Taste stellt die Palette ab statt sie fallen zu lassen")

	# Speichern und Laden behält die Stapelhöhe
	var state: Dictionary = w.layout.to_state()
	var saved_stack := 0
	for s in state["shelves"]:
		saved_stack = maxi(saved_stack, int(s.get("stack", 1)))
	ok(saved_stack == Shelf.MAX_STACK, "Stapelhöhe wird gespeichert")

	# Eine Palette in den Händen übersteht das Speichern
	w.pallet_click(pallets(w)[0])
	var ps: Dictionary = p.get_state()
	p.clear_carry()
	p.set_state(ps)
	ok(p.carrying_pallet(), "Getragene Palette nach dem Laden wieder in den Händen")

	# E auf den Stapel-Knoten selbst (wie im Spiel): der Knoten darf beim Neuaufbau nicht
	# als Geist mit veraltetem Index stehen bleiben
	p.clear_carry()
	var before := total(w)
	var idx: int = pallets(w)[0]
	var clicked: Shelf = w.shelf_nodes[idx]
	clicked.interact(p)
	ok(p.carrying_pallet() and total(w) == before - 1, "Aufnehmen per E auf den Stapel")
	ok(not clicked.is_inside_tree(), "Angeklickter Stapel-Knoten ist aus der Welt genommen")
	await process_frame
	ok(not is_instance_valid(clicked), "Angeklickter Stapel-Knoten wird gelöscht")
	for n in w.shelf_nodes:
		ok(n.index < w.layout.shelves.size(), "Kein Stapel-Knoten mit veraltetem Index")
	# Linksklick legt nichts mehr ab, weder auf den Stapel noch auf den Boden
	var target2: int = pallets(w)[0]
	(w.shelf_nodes[target2] as Shelf).click(p)
	p.click_focus()
	ok(p.carrying_pallet() and total(w) == before - 1, "Linksklick stellt die Palette nicht ab")
	# Vorschau vor der Figur, genau dort, wo Q abstellt
	await process_frame
	var ghost: Node3D = w._pallet_ghost
	var spot: Vector2 = p.pallet_spot()
	ok(ghost != null and ghost.visible, "Vorschau beim Tragen sichtbar")
	ok(ghost != null and Vector2(ghost.position.x, ghost.position.z).distance_to(spot) < 0.01, "Vorschau steht am Abstellpunkt")
	# Mauszielen: steiler Blick nach unten stellt näher ab als flacher
	p.head.rotation.x = -1.2
	var near_spot: Vector2 = p.pallet_spot()
	p.head.rotation.x = -0.45
	var far_spot: Vector2 = p.pallet_spot()
	var me := Vector2(p.global_position.x, p.global_position.z)
	ok(near_spot.distance_to(me) < far_spot.distance_to(me) - 0.3, "Zielpunkt folgt dem Blick: %.2f / %.2f m" % [near_spot.distance_to(me), far_spot.distance_to(me)])
	ok(far_spot.distance_to(me) <= p.PALLET_FAR + 0.01 and near_spot.distance_to(me) >= p.PALLET_NEAR - 0.01, "Zielpunkt bleibt in Reichweite")
	p.head.rotation.x = 0.8
	ok(absf(p.pallet_spot().distance_to(me) - p.PALLET_FAR) < 0.01, "Blick nach oben: größte Weite")
	p.head.rotation.x = p.pitch
	# Vorschau auf dem anvisierten Stapel, oben auf der obersten Palette
	var tgt: Shelf = w.shelf_nodes[target2]
	p._focus = tgt
	w._update_pallet_ghost()
	var ghost_y := float(Shelf.SIZES["pallet"]["height"]) * tgt.stack
	ok(absf(ghost.global_position.y - ghost_y) < 0.02, "Vorschau liegt auf dem Stapel (y %.2f, erwartet %.2f)" % [ghost.global_position.y, ghost_y])
	ok(Vector2(ghost.global_position.x, ghost.global_position.z).distance_to(Vector2(tgt.global_position.x, tgt.global_position.z)) < 0.01, "Vorschau mittig über dem Stapel")
	# Q auf den Stapel gezielt legt dort auf
	p._focus = tgt
	p.drop()
	ok(not p.carrying_pallet() and total(w) == before, "Auflegen per Q auf den anvisierten Stapel")
	await process_frame
	ok(not ghost.visible, "Vorschau ohne Palette verschwunden")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
