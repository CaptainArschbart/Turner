extends SceneTree
## Hubwagen als eigener Körper: übernehmen, Fahrkinematik (Ziehen, Einlenken, Anstoßen), Zinken in den
## Palettenöffnungen, Heben und Senken, Parken mit Last, Speichern und Laden.
var checks := 0
var pl = null
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func idx_of(w, id: String) -> int:
	for i in w.layout.shelves.size():
		if str(w.layout.shelves[i]["size"]) == id:
			return i
	return -1


func total(w) -> int:
	var n := 0
	for s in w.layout.shelves:
		if str(s["size"]) == "pallet":
			n += int(s.get("stack", 1))
	return n


func wall(w, at: Vector2, size := Vector3(0.8, 2.0, 0.8)) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	b.add_child(cs)
	w.add_child(b)
	b.global_position = Vector3(at.x, size.y * 0.5, at.y)
	return b


## Wagen hinstellen und einen Physikschritt abwarten, damit die Formen im Raum stehen.
func put(cart, origin: Vector2, phi: float) -> void:
	cart.place(origin, phi)
	if pl != null and pl.jack_cart == cart:
		var h: Vector2 = cart.hold_point(-cart.forward())       # Figur bleibt an der Deichsel, sonst stellt sie den Wagen ab
		pl.global_position = Vector3(h.x, 0.05, h.y)
	await physics_frame


func hits(cart) -> bool:
	return cart.test_move(cart.global_transform, Vector3.ZERO, null, 0.001, true)


func new_pallet(w, pos: Vector2, rot := 0, stack := 1) -> void:
	w.layout.shelves.append({"size": "pallet", "pos": pos, "rot": rot, "stack": stack})
	w._rebuild_stands()


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 250, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	pl = p
	var ji := idx_of(w, "pallet_jack")
	ok(ji >= 0, "Hubwagen steht im Lager")
	ok(w.jack_prompt(ji).contains("Deichsel"), "Hinweis auf dem Hubwagen: " + w.jack_prompt(ji))
	var jpos: Vector2 = w.layout.shelves[ji]["pos"]
	var jrot := int(w.layout.shelves[ji]["rot"])
	var jphi := jrot * PI / 2.0
	var jf := Vector2(cos(jphi), -sin(jphi))
	var jpivot: Vector2 = jpos + jf * JackCart.PIVOT_X

	# Gesperrte Übernahme: ein Ring aus Hindernissen um das Lenkrad, auf dem die Figur stehen müsste
	var ring: Array = []
	for k in 16:
		var a := k * TAU / 16.0
		ring.append(wall(w, jpivot + Vector2(cos(a), sin(a)) * JackCart.HOLD))
	await physics_frame
	await physics_frame
	p.global_position = Vector3(jpos.x - 3.0, 0.05, jpos.y + 3.0)
	(w.shelf_nodes[ji] as Shelf).interact(p)
	ok(not p.driving_jack() and idx_of(w, "pallet_jack") == ji, "Gesperrte Position: Hubwagen bleibt stehen")
	for b in ring:
		b.free()
	await physics_frame
	await physics_frame

	# Übernehmen
	(w.shelf_nodes[ji] as Shelf).interact(p)
	ok(p.driving_jack() and not p.hands_free(), "Hubwagen übernommen, Hände belegt")
	ok(idx_of(w, "pallet_jack") == -1, "Hubwagen nicht mehr im Lager")
	var cart: JackCart = p.jack_cart
	ok(cart != null and cart.get_parent() == w, "Wagen ist ein eigener Körper in der Welt")
	ok(cart.origin2().distance_to(jpos) < 0.01 and absf(cart.phi - jphi) < 0.01, "Wagen bleibt an seinem Platz")
	var me := Vector2(p.global_position.x, p.global_position.z)
	ok(absf(me.distance_to(cart.pivot()) - JackCart.HOLD) < 0.02, "Figur steht eine Deichsellänge hinter dem Lenkrad")
	ok(p.get_collision_layer() == 1 and cart.collision_layer == 0, "Wagen stößt die Figur nicht")
	await process_frame
	ok(p.arms.mode == "grip" and p.arms.grip_world.size() == 2 and p.body.grab.size() == 2, "Beide Hände am Griffbügel")

	# Ziehen geradeaus (auf freier Fläche): Figur läuft vom Wagen weg, Wagen folgt mit der Deichsel voran, ohne Drehung
	await put(cart, Vector2(21.0, -14.0), 0.0)
	jphi = 0.0
	var start := cart.origin2()
	var rear := -cart.forward()
	var q := cart.hold_point(rear)
	p.global_position = Vector3(q.x, 0.05, q.y)
	for k in 40:
		q += rear * 0.03
		p.global_position = Vector3(q.x, 0.05, q.y)
		p._drive_jack()
		q = Vector2(p.global_position.x, p.global_position.z)
	var moved := cart.origin2() - start
	ok(moved.dot(rear) > 1.0 and absf(moved.dot(cart.lateral())) < 0.02, "Ziehen: Wagen folgt geradeaus (%s)" % moved)
	ok(absf(cart.phi - jphi) < 0.02 and absf(cart.steer) < 0.05, "Ziehen geradeaus ändert die Richtung nicht")
	ok(absf(q.distance_to(cart.pivot()) - JackCart.HOLD) < 0.02, "Deichsel bleibt gleich lang")

	# Einlenken: Figur schwenkt seitlich um das Lenkrad und zieht an. Das Chassis dreht sich um die Lastachse.
	var phi0 := cart.phi
	var slip := 0.0
	var wb_ok := true
	for k in 60:
		var pv := cart.pivot()
		var off := q - pv
		off = off.rotated(0.025)                       # seitlich schwenken
		q = pv + off + off.normalized() * 0.02         # und ein Stück ziehen
		p.global_position = Vector3(q.x, 0.05, q.y)
		var before_axle := cart.origin2() + cart.forward() * JackCart.AXLE_X
		var before_fwd := cart.forward()
		p._drive_jack()
		q = Vector2(p.global_position.x, p.global_position.z)
		var after_axle := cart.origin2() + cart.forward() * JackCart.AXLE_X
		# Lastrollen rutschen nicht seitlich: Bewegung der Achse liegt in Chassisrichtung
		var mv := after_axle - before_axle
		slip = maxf(slip, absf(mv.dot(Vector2(-before_fwd.y, before_fwd.x))))
		if absf((cart.pivot() - after_axle).length() - JackCart.WHEELBASE) > 0.01:
			wb_ok = false
	ok(wb_ok, "Achsabstand Lenkrad - Lastachse bleibt konstant")
	ok(absf(angle_difference(phi0, cart.phi)) > 0.2, "Einlenken dreht das Chassis (%f rad)" % angle_difference(phi0, cart.phi))
	ok(slip < 0.01, "Lastrollen rutschen nicht seitlich: %f" % slip)
	ok(cart.steer != 0.0, "Deichsel zeigt Lenkwinkel")

	# Anstoßen: Wand hinter dem Wagen. Er bleibt stehen, die Figur wird an der Deichsel festgehalten.
	cart.place(Vector2(21.0, -14.0), 0.0)
	var blocker := wall(w, cart.origin2() - cart.forward() * 1.6, Vector3(0.2, 2.0, 3.0))
	await physics_frame
	await physics_frame
	var pos0 := cart.origin2()
	q = cart.hold_point(-cart.forward())
	for k in 30:
		q = cart.step(q - cart.forward() * 0.04)
	ok(not hits(cart), "Wagen steckt nicht im Hindernis")
	ok(cart.origin2().distance_to(pos0) < 0.5, "Wagen stößt an und bleibt stehen (%f)" % cart.origin2().distance_to(pos0))
	ok(absf(q.distance_to(cart.pivot()) - JackCart.HOLD) < 0.02, "Figur wird an der Deichsel festgehalten")
	blocker.free()
	await physics_frame

	# Zinken in den Palettenöffnungen: längs und quer, je eine Zinke je Öffnung
	var ppos := Vector2(21.0, -18.0)
	new_pallet(w, ppos)
	await physics_frame
	await physics_frame
	await put(cart, ppos - Vector2(Shelf.JACK_LOAD_X, 0), 0.0)                  # längs, von der kurzen Seite
	ok(not hits(cart), "Zinken längs in den Öffnungen der kurzen Seite")
	await put(cart, ppos - Vector2(Shelf.JACK_LOAD_X, 0.3), 0.0)
	ok(hits(cart), "Seitlich versetzt stoßen die Zinken an die Klötze")
	for side in [0.05, -0.05]:
		await put(cart, ppos - Vector2(Shelf.JACK_LOAD_X, side), 0.0)
		ok(not hits(cart), "Zinken mit %.2f m Versatz passen noch in die Öffnungen" % side)
	await put(cart, ppos + Vector2(Shelf.JACK_LOAD_X, 0), PI)                   # längs, von der anderen Seite
	ok(not hits(cart), "Zinken längs von der Gegenseite")
	await put(cart, ppos + Vector2(0, Shelf.JACK_LOAD_X), PI / 2.0)             # quer, von der langen Seite
	ok(not hits(cart), "Zinken quer in den Öffnungen der langen Seite")
	await put(cart, ppos - Vector2(0, Shelf.JACK_LOAD_X), -PI / 2.0)
	ok(not hits(cart), "Zinken quer von der Gegenseite")
	await put(cart, ppos + Vector2(0.3, Shelf.JACK_LOAD_X), PI / 2.0)
	ok(hits(cart), "Quer versetzt stoßen die Zinken an die Klötze")

	# Heben: nur mit den Zinken unter der Palette, Ausrichtung längs oder quer
	var tot := total(w)
	await put(cart, ppos + Vector2(0.0, 3.0), 0.0)
	w.jack_lift()
	ok(cart.load_n == 0, "Zinken nicht unter einer Palette: nichts angehoben")
	await put(cart, ppos - Vector2(Shelf.JACK_LOAD_X, 0), 0.6)
	w.jack_lift()
	ok(cart.load_n == 0, "Schräg zur Palette nicht angehoben")
	await put(cart, ppos - Vector2(Shelf.JACK_LOAD_X, 0.1), 0.0)
	w.jack_lift()
	ok(cart.load_n == 0, "Seitlicher Versatz 0,1 m: nicht angehoben")
	await put(cart, ppos - Vector2(Shelf.JACK_LOAD_X, 0.05), 0.0)
	w.jack_lift()
	ok(cart.load_n == 1, "Seitlicher Versatz 0,05 m: trotzdem angehoben")
	w.jack_lift()
	await physics_frame
	await physics_frame
	ok(cart.load_n == 0, "Wieder abgesenkt")
	await put(cart, ppos - Vector2(Shelf.JACK_LOAD_X, 0), 0.0)
	w.jack_lift()
	ok(cart.load_n == 1 and not cart.cross and total(w) == tot - 1, "Palette längs angehoben")
	ok(int(p.carry["load"]) == 1, "Last steht im Träger")
	ok(cart._load_shape != null, "Eigene Kollisionsbox für die Last")
	for k in 40:
		await physics_frame
	ok(absf(cart.lift_t - 1.0) < 0.01, "Hebeanimation fertig")
	await process_frame
	await process_frame
	ok(w._pallet_ghost != null and w._pallet_ghost.visible, "Vorschau mit Last")
	# Absenken
	await put(cart, ppos - Vector2(Shelf.JACK_LOAD_X, 0), 0.5)
	w.jack_lift()
	ok(cart.load_n == 1, "Schief nicht absenkbar (Palette gerader ausrichten)")
	await put(cart, ppos - Vector2(Shelf.JACK_LOAD_X, 0), 0.0)
	w.jack_lift()
	ok(cart.load_n == 0 and cart._load_shape == null and total(w) == tot, "Palette abgesenkt, Lastbox weg")
	await physics_frame
	await physics_frame
	# Quer anheben, mit passender Drehung wieder absenken
	await put(cart, ppos + Vector2(0, Shelf.JACK_LOAD_X), PI / 2.0)
	w.jack_lift()
	ok(cart.load_n == 1 and cart.cross, "Palette quer angehoben")
	w.jack_lift()
	var low := -1
	for k in w.layout.shelves.size():
		if str(w.layout.shelves[k]["size"]) == "pallet" and (w.layout.shelves[k]["pos"] as Vector2).distance_to(ppos) < 0.05:
			low = k
	ok(low >= 0 and posmod(int(w.layout.shelves[low]["rot"]), 2) == 0, "Quer abgesenkt steht wieder wie vorher")

	# Stapel aus drei Paletten fahren und mit Last parken
	w.layout.shelves[low]["stack"] = 3
	w._rebuild_stands()
	await physics_frame
	await physics_frame
	await put(cart, ppos - Vector2(Shelf.JACK_LOAD_X, 0), 0.0)
	w.jack_lift()
	ok(cart.load_n == 3, "Stapel aus drei Paletten angehoben")
	ok(absf((cart._load_shape.shape as BoxShape3D).size.y - 3.0 * 0.219143) < 0.02, "Lastbox: Höhe load * Palettenhöhe")
	await put(cart, Vector2(21.0, -11.0), 0.5)
	ok(w.jack_park() != "" and p.driving_jack(), "Schief nicht abstellbar: Hubwagen gerader ausrichten")
	await put(cart, Vector2(21.0, -11.0), 0.1)
	ok(w.jack_park() == "", "Mit Last abgestellt (Einrasten bei kleiner Abweichung)")
	ok(not p.driving_jack() and p.hands_free() and p.jack_cart == null, "Hände frei, Wagen weg")
	await process_frame
	var pj := idx_of(w, "pallet_jack")
	ok(pj >= 0 and int(w.layout.shelves[pj]["load"]) == 3 and int(w.layout.shelves[pj]["rot"]) == 0, "Eintrag mit load 3, Drehung eingerastet")
	ok((w.shelf_nodes[pj] as Shelf).cargo == 3, "Last am abgestellten Hubwagen sichtbar")
	var loaded: Rect2 = w.layout.shelf_rect("pallet_jack", Vector2.ZERO, 0, 3, false)
	var empty_rect: Rect2 = w.layout.shelf_rect("pallet_jack", Vector2.ZERO, 0)
	ok(loaded.size.y > 1.0 and empty_rect.size.y < 0.8, "Footprint mit Last breiter")
	var hit_size := Vector3.ZERO
	for c in (w.shelf_nodes[pj] as Shelf).get_children():
		if c is StaticBody3D:
			hit_size = ((c.get_child(0) as CollisionShape3D).shape as BoxShape3D).size
	ok(absf(hit_size.z - loaded.size.y) < 0.01 and absf(hit_size.x - loaded.size.x) < 0.01, "Kollisionsbox des Hubwagens passt zum Footprint")

	# Speichern mitten in der Fahrt: Wagen samt Last und Lage landen im Spielstand
	var parked: Vector2 = w.layout.shelves[pj]["pos"]
	p.global_position = Vector3(parked.x - 3.0, 0.05, parked.y + 2.0)
	(w.shelf_nodes[pj] as Shelf).interact(p)
	ok(p.driving_jack() and p.jack_load() == 3, "Hubwagen samt Last wieder übernommen")
	var ps: Dictionary = p.get_state()
	ok(ps["carry"].has("pos") and int(ps["carry"]["load"]) == 3, "Spielstand enthält Lage und Last")
	p.jack_cart.place(Vector2(21.0, -9.0), 1.0)
	var hp: Vector2 = p.jack_cart.hold_point(-p.jack_cart.forward())
	p.global_position = Vector3(hp.x, 0.05, hp.y)
	ps = p.get_state()
	p.clear_carry()
	ok(not p.driving_jack() and p.jack_cart == null, "Zurückgesetzt")
	p.set_state(ps)
	ok(p.driving_jack() and p.jack_load() == 3 and p.jack_cart != null, "Fahrt samt Last nach dem Laden wieder da")
	ok(p.jack_cart.origin2().distance_to(Vector2(21.0, -9.0)) < 0.01 and absf(p.jack_cart.phi - 1.0) < 0.01, "Lage des Wagens nach dem Laden")
	ok(idx_of(w, "pallet_jack") == -1, "Kein zweiter Hubwagen im Lager (nichts dupliziert)")
	var snap: Dictionary = p.get_state()
	snap["carry"]["load"] = 99
	ok(p.jack_load() == 3 and int(p.carry["load"]) == 3, "get_state liefert eine Kopie")

	# Q stellt ebenfalls ab; außerhalb von Werkstatt und Lager geht es nicht
	await put(p.jack_cart, Vector2(-200.0, -200.0), 0.0)
	ok(w.jack_park() != "" and p.driving_jack(), "Außerhalb nicht abstellbar")
	await put(p.jack_cart, Vector2(21.0, -9.0), 0.0)
	p.drop()
	ok(not p.driving_jack() and idx_of(w, "pallet_jack") >= 0, "Ablegen-Taste stellt den Hubwagen ab")

	# Figur teleportiert (Schlafen, Ortswechsel, Noclip): Wagen bleibt an seiner Stelle stehen, nichts geht verloren
	p.global_position = Vector3(parked.x - 3.0, 0.05, parked.y + 2.0)
	var pj2 := idx_of(w, "pallet_jack")
	(w.shelf_nodes[pj2] as Shelf).interact(p)
	ok(p.driving_jack(), "Noch einmal übernommen")
	var cart_pos: Vector2 = p.jack_cart.origin2()
	p.global_position = Vector3(cart_pos.x + 40.0, 0.05, cart_pos.y)
	p._physics_process(0.016)
	ok(not p.driving_jack() and p.jack_cart == null, "Zu weit weg: Hubwagen wird abgestellt")
	var left := idx_of(w, "pallet_jack")
	ok(left >= 0 and (w.layout.shelves[left]["pos"] as Vector2).distance_to(cart_pos) < 0.01, "Hubwagen steht an der Wagenposition im Layout")
	var n_jacks := 0
	for s in w.layout.shelves:
		if str(s["size"]) == "pallet_jack":
			n_jacks += 1
	ok(n_jacks == 1, "Genau ein Hubwagen (nichts verloren, nichts doppelt)")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
