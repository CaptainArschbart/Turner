extends SceneTree
## Lieferpaletten: höchstens 1000 mm Ladung, Überschuss kommt auf weitere Paletten mit eigenem Zähler.
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
	var site_cls = load("res://scripts/world/site.gd")
	w.money = 10000000
	w.deliveries = []
	w._deliveries_changed()

	var spec := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 1000.0, "qty": 1}
	var cap: int = site_cls.pallet_capacity(spec)
	ok(cap > 1, "Mehr als ein Stück passt auf eine Palette (%d)" % cap)
	# Lagen: 1000 mm / 62 mm = 16 Lagen
	var per_layer: int = cap / 16
	ok(per_layer * 16 == cap, "Kapazität ist ganze Lagen bis 1000 mm (%d)" % cap)

	var n := cap * 2 + 3
	spec["qty"] = n
	var err: String = w.order_material(spec)
	ok(err == "", "Bestellung angenommen: %s" % err)
	ok(w.deliveries.size() == n, "Alle Stücke geliefert")
	var groups: Array = w.delivery_view()
	ok(groups.size() == 3, "Drei Paletten statt einer (%d)" % groups.size())
	var keys := {}
	for g in groups:
		keys[str(g["key"])] = true
		ok((g["items"] as Array).size() <= cap, "Palette nicht übervoll")
		var holder := Node3D.new()
		w.add_child(holder)
		var height: float = w.site.add_goods(holder, g["items"])
		ok(height <= 1.0 + 0.0001, "Ladung höchstens 1000 mm hoch (%.3f)" % height)
		holder.free()
	ok(keys.size() == 3, "Jede Palette hat ihren eigenen Schlüssel")
	ok((groups[0]["items"] as Array).size() == cap and (groups[2]["items"] as Array).size() == 3, "Erste voll, letzte mit dem Rest")

	# Zähler je Palette getrennt
	var last: Dictionary = groups[2]
	var prompt: String = w.delivery_prompt(int(last["index"]))
	ok(prompt.contains("3 Stück"), "Zähler der letzten Palette zeigt 3: %s" % prompt)
	var first_prompt: String = w.delivery_prompt(int(groups[0]["index"]))
	ok(first_prompt.contains("%d Stück" % cap), "Zähler der ersten Palette zeigt %d: %s" % [cap, first_prompt])

	# Nachbestellung füllt zuerst die angefangene Palette
	spec["qty"] = 2
	w.order_material(spec)
	groups = w.delivery_view()
	ok(groups.size() == 3 and (groups[2]["items"] as Array).size() == 5, "Nachbestellung landet auf der angefangenen Palette")

	# Aufheben: Das Stück in der Hand trägt keine Palettennummer mehr
	ok(w.pick_delivery(int(groups[1]["index"])) == "", "Stück aufgehoben")
	ok(not w.player.carry.has("pallet"), "Getragenes Stück ohne Palettennummer")
	groups = w.delivery_view()
	ok((groups[1]["items"] as Array).size() == cap - 1, "Mittlere Palette hat eins weniger")

	# Alter Spielstand: alles ohne Palettennummer auf einem Haufen wird verteilt
	var old := []
	for i in cap + 1:
		old.append({"material": "C45", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 1000.0})
	ok(site_cls.split_pallets(old), "Alter Haufen wird verteilt")
	ok(old.filter(func(it): return int(it["pallet"]) == 1).size() == 1, "Ein Stück auf der zweiten Palette")
	ok(not site_cls.split_pallets(old), "Zweiter Durchlauf ändert nichts")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
