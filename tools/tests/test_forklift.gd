extends SceneTree
## Gabelstapler: steht zum Test in der Lagerhalle, ist im Shop kaufbar, Einsteigen, Fahren (Hinterradlenkung),
## Palettenstapel aufnehmen, absetzen und auf einen Stapel setzen, Aussteigen, Speichern.
var checks := 0
var fails := 0
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


func fk_index(w) -> int:
	for i in w.layout.shelves.size():
		if str(w.layout.shelves[i]["size"]) == "forklift":
			return i
	return -1


func pallets_at(w, at: Vector2) -> int:
	for s in w.layout.shelves:
		if str(s["size"]) == "pallet" and s["pos"].distance_to(at) < 0.3:
			return int(s.get("stack", 1))
	return 0


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 5000, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	w.start_day()
	var p = w.player

	# ---------------------------------------------------- Aufstellung und Shop
	var fi := fk_index(w)
	ok(fi >= 0, "Gabelstapler steht zum Test im Lager")
	var start: Vector2 = w.layout.shelves[fi]["pos"]
	var r: Rect2 = w.layout.shelf_rect("forklift", start, int(w.layout.shelves[fi]["rot"]))
	ok(w.site.in_lager(r), "Und zwar in der Lagerhalle: %s" % r)
	ok(w.shelf_nodes[fi].find_child("Gabeltraeger", true, false) != null, "Modell mit beweglichem Gabelträger geladen")
	ok(w.forklift_prompt(fi).contains("Einsteigen"), "Hinweis: " + w.forklift_prompt(fi))
	var node = w.shelf_nodes[fi]
	var lb: AABB = Build.bounds(node)
	var la := AABB(lb.position - node.global_position, lb.size)
	ok(absf(la.size.x - 3.21) < 0.25 and absf(la.size.y - 2.16) < 0.2 and absf(la.size.z - 1.15) < 0.2, "Echte Größe: %s" % la.size)
	ok(la.position.y > -0.02 and la.position.y < 0.05, "Steht auf dem Boden (%.3f)" % la.position.y)
	var cb: AABB = Build.bounds(node.find_child("Gabeltraeger", true, false))
	ok(cb.get_center().x - node.global_position.x > 0.6, "Gabel zeigt nach vorn (+x)")
	ok(w.layout.to_state()["starter_forklift"] == true, "Nur einmal hingestellt")
	var money0: int = w.money
	ok(w.buy_equipment("forklift") == "" and int(w.inventory.get("forklift", 0)) == 1 and w.money == money0 - 2500, "Im Shop für 2500 EUR kaufbar")

	# ---------------------------------------------------- Einsteigen und fahren
	p.global_position = Vector3(start.x, 0.05, start.y + 1.6)
	await frames(2)
	w.forklift_click(fi)
	var f = w.forklift
	ok(f != null and p.driving_forklift() and fk_index(w) < 0, "Eingestiegen, der Stapler ist jetzt ein Fahrzeug")
	ok(not p.hands_free(), "Auf dem Stapler sind die Hände nicht frei")
	await frames(2)
	ok(p.global_position.distance_to(f.seat_point()) < 0.05, "Figur sitzt auf dem Fahrersitz")
	var o0: Vector2 = f.origin2()
	var phi0: float = f.phi
	await hold("move_forward", 60)
	await frames(60)
	var moved: Vector2 = f.origin2() - o0
	ok(moved.length() > 1.0 and moved.normalized().dot(f.forward()) > 0.95, "W fährt geradeaus vorwärts (%.2f m)" % moved.length())
	ok(absf(f.speed) < 0.05, "Ohne Gas bremst er bis zum Stand")
	ok(p.global_position.distance_to(f.seat_point()) < 0.05, "Figur fährt mit")
	var yaw0: float = p.yaw
	Input.action_press("move_left")
	await hold("move_back", 50)
	Input.action_release("move_left")
	await frames(60)
	ok(f.phi < phi0 - 0.1, "Rückwärts mit Lenkung dreht den Stapler (%.2f -> %.2f)" % [phi0, f.phi])
	ok(absf((p.yaw - yaw0) - (f.phi - phi0)) < 0.01, "Blick dreht mit dem Stapler")
	await hold("fork_up", 30)
	ok(f.lift > 0.15 and f.lift < 0.4, "Bild auf hebt die Gabel (%.2f m)" % f.lift)
	await hold("fork_down", 60)
	ok(is_zero_approx(f.lift), "Und senkt sie wieder bis zum Boden")
	var tip0: Vector2 = f.fork_spot()
	await hold("fork_right", 120)
	ok(is_equal_approx(f.shift, f.MAX_SHIFT) and (f.fork_spot() - tip0).dot(f.side()) > 0.09, "Pfeil rechts schiebt die Gabel 10 cm nach rechts")
	await hold("fork_left", 240)
	ok(is_equal_approx(f.shift, -f.MAX_SHIFT), "Pfeil links schiebt sie bis 10 cm nach links")
	await hold("fork_right", 40)
	ok(absf(f.shift + f.MAX_SHIFT - 0.1) < 0.02, "Seitenschieber bleibt, wo man loslässt")
	f.shift = 0.0
	await hold("fork_tilt_back", 150)
	ok(is_equal_approx(f.tilt, f.TILT_BACK) and is_equal_approx(f.parts["tilt"].rotation.x, f.TILT_BACK), "Bild ab neigt das Hubgerüst 6° nach hinten")
	await hold("fork_tilt_fwd", 300)
	ok(is_equal_approx(f.tilt, -f.TILT_FWD), "Bild auf neigt es 3° nach vorn")
	f.tilt = 0.0

	# ---------------------------------------------------- Palettenstapel aufnehmen
	f.place(Vector2(start.x, start.y), 0.0)
	var spot: Vector2 = f.fork_spot()
	ok(w.layout.check_shelf("pallet", spot, 0) == "", "Platz für den Teststapel vor der Gabel: " + w.layout.check_shelf("pallet", spot, 0))
	w.layout.shelves.append({"size": "pallet", "pos": spot, "rot": 0, "stack": 3})
	w._rebuild_stands()
	await hold("fork_up", 40)
	ok(f.load_n == 3 and pallets_at(w, spot) == 0, "Heben nimmt den ganzen Stapel mit (3 Paletten)")
	ok(f.parts["load"].get_child_count() == 1, "Paletten liegen sichtbar auf der Gabel")
	# Zurücksetzen und mitten auf den Boden absetzen
	await hold("move_back", 110)
	await frames(80)
	var drop_at: Vector2 = f.fork_spot()
	ok(drop_at.distance_to(spot) > 1.0, "Mit Last zurückgesetzt (%.2f m)" % drop_at.distance_to(spot))
	await hold("fork_down", 90)
	ok(f.load_n == 0 and pallets_at(w, drop_at) == 3, "Ganz abgesenkt: Stapel steht am Boden")
	# Noch einen Stapel holen und auf den ersten setzen
	f.place(Vector2(start.x, start.y), 0.0)
	await frames(2)
	await hold("fork_up", 20)
	ok(f.load_n == 0, "Dort ist nichts mehr: die Gabel hebt leer")
	await hold("fork_down", 40)
	var spot2: Vector2 = f.fork_spot()
	w.layout.shelves.append({"size": "pallet", "pos": spot2, "rot": 0, "stack": 2})
	w._rebuild_stands()
	await hold("fork_up", 140)
	ok(f.load_n == 2 and f.lift > 0.8, "Zweiten Stapel aufgenommen und hochgehoben (%.2f m)" % f.lift)
	# über den ersten Stapel fahren: Gabelmitte genau darüber stellen
	var back: Vector2 = drop_at - f.forward() * f.FORK_CENTER
	f.place(back, f.phi)
	await frames(2)
	await hold("fork_down", 200)
	ok(f.load_n == 0 and pallets_at(w, drop_at) == 5, "Auf den Stapel gesetzt: jetzt 5 Paletten")

	# ---------------------------------------------------- Teilstapel: Gabel in die dritte von vier Paletten
	var ph := 0.22
	f.place(Vector2(start.x, start.y), 0.0)
	await frames(2)
	var spot3: Vector2 = f.fork_spot()
	w.layout.shelves.append({"size": "pallet", "pos": spot3, "rot": 0, "stack": 4})
	w._rebuild_stands()
	f.lift = 2 * ph + 0.01                    # Gabel auf Höhe der Unterkante der dritten Palette
	await hold("fork_up", 20)
	ok(f.load_n == 2 and pallets_at(w, spot3) == 2, "Gabel in der dritten Palette: 3 und 4 kommen mit, 1 und 2 bleiben stehen")
	await hold("fork_down", 120)
	ok(f.load_n == 0 and pallets_at(w, spot3) == 4, "Wieder auf den Stapel gesetzt")
	f.lift = 3 * ph - 0.02
	await hold("fork_up", 15)
	ok(f.load_n == 1 and pallets_at(w, spot3) == 3, "In der obersten Palette: nur sie kommt mit")
	await hold("fork_down", 120)
	ok(f.load_n == 0 and pallets_at(w, spot3) == 4, "Und zurückgesetzt")
	for i in w.layout.shelves.size():
		if str(w.layout.shelves[i]["size"]) == "pallet" and w.layout.shelves[i]["pos"].distance_to(spot3) < 0.3:
			w.layout.shelves.remove_at(i)
			break
	w._rebuild_stands()

	# ---------------------------------------------------- Spänebehälter aufnehmen und in den Container kippen
	# Spänebehälter stehen nur in der Werkstatt: Der Stapler fährt dafür in die Halle
	var hall := Vector2(-8.0, 5.5)
	f.place(hall, 0.0)
	await frames(2)
	var bspot: Vector2 = f.fork_spot()
	ok(w.layout.check_bin(bspot, 0, -1, "bin_s") == "", "Platz für den Spänebehälter: " + w.layout.check_bin(bspot, 0, -1, "bin_s"))
	var tray := ChipTray.new(25.0)
	tray.add("baustahl", 12.0)
	w.layout.bins.append({"size": "bin_s", "pos": bspot, "rot": 0, "chips": tray, "out": false})
	w._rebuild_stands()
	var bi: int = w.layout.bins.size() - 1
	ok(w.bin_nodes[bi].get_children().filter(func(n): return n is MeshInstance3D and absf(n.position.y - 0.003) < 0.001).is_empty(), "Keine gelbe Bodenmarkierung mehr")
	await hold("fork_up", 60)
	ok(f.load_bin == bi and w.layout.bins[bi].get("fork", false), "Gabel nimmt den Spänebehälter auf")
	ok(w.bin_nodes[bi].global_position.y > 0.3, "Behälter fährt mit der Gabel hoch")
	# Tief gehalten fahren: Der Behälter darf den Stapler nicht wegschieben
	f.lift = 0.05
	await frames(5)
	var low0: Vector2 = f.origin2()
	await frames(30)
	ok(f.origin2().distance_to(low0) < 0.01, "Tief gehalten im Stand: Stapler bleibt stehen")
	await hold("move_forward", 40)
	await frames(60)
	ok((f.origin2() - low0).dot(f.forward()) > 0.5, "Tief gehalten fährt er vorwärts, nicht zurück (%.2f m)" % (f.origin2() - low0).dot(f.forward()))
	f.place(hall, 0.0)
	f.lift = 0.6
	await frames(2)
	ok(w.forklift_leave() != "" and p.driving_forklift(), "Mit Behälter auf der Gabel nicht aussteigen")
	var ci: int = w.CONTAINER_SORTS.find("stahl")
	var cp: Vector3 = w.site.container_pos(ci)
	f.place(Vector2(cp.x, cp.z) - f.forward() * f.FORK_CENTER, 0.0)
	f.lift = 1.0
	await frames(2)
	var kg0: float = w.containers[ci].kg
	await hold("fork_tilt_fwd", 80)
	ok(is_equal_approx(w.containers[ci].kg, kg0), "Zu tief: nichts gekippt")
	await hold("fork_tilt_back", 60)
	f.lift = 1.6
	await hold("fork_tilt_fwd", 80)
	ok(w.containers[ci].kg > kg0 + 11.9 and tray.is_empty(), "Über dem Container nach vorn gekippt: Späne sind drin")
	ok(f.dump_t > 0.0 and f.dump_angle() > 0.3, "Behälter kippt sichtbar nach vorn")
	await frames(120)
	ok(f.dump_angle() == 0.0, "Und wieder zurück")
	f.place(hall, 0.0)
	await frames(2)
	await hold("fork_tilt_back", 60)
	await hold("fork_down", 300)
	ok(f.load_bin < 0 and not w.layout.bins[bi].has("fork") and w.layout.bins[bi]["pos"].distance_to(bspot) < 0.05, "Behälter wieder abgesetzt")
	ok(w.bin_nodes[bi].global_position.y < 0.01, "Steht auf dem Boden")

	# ---------------------------------------------------- Texturen
	var textured := 0
	for mi in f.find_children("*", "MeshInstance3D", true, false):
		for k in (mi as MeshInstance3D).get_surface_override_material_count():
			var om = (mi as MeshInstance3D).get_surface_override_material(k)
			if om is StandardMaterial3D and om.albedo_texture != null:
				textured += 1
	ok(textured > 25, "Graue Teile haben Texturen (%d Flächen)" % textured)

	# ---------------------------------------------------- Aussteigen und Speichern
	f.place(Vector2(start.x, start.y + 3.0), 0.0)
	await hold("fork_up", 20)
	var lift_saved: float = f.lift
	var saved: Dictionary = w._forklift_entry_state(f)
	ok(saved["pos"] is Array and is_equal_approx(float(saved["lift"]), lift_saved), "Beim Fahren gespeichert: Platz und Gabelhöhe")
	ok(w.forklift_leave() == "", "Ausgestiegen")
	await frames(3)
	ok(not p.driving_forklift() and p.hands_free() and w.forklift == null, "Figur steht wieder, Hände frei")
	fi = fk_index(w)
	ok(fi >= 0 and is_equal_approx(float(w.layout.shelves[fi]["lift"]), lift_saved), "Stapler steht wieder als Ausstattung, Gabel oben")
	ok(p.global_position.distance_to(Vector3(start.x, p.global_position.y, start.y)) < 2.2, "Figur steht neben dem Stapler")
	var st: Dictionary = w.layout.to_state()
	var found := false
	for s in st["shelves"]:
		if str(s["size"]) == "forklift" and s.has("lift") and s.has("angle"):
			found = true
	ok(found, "Gespeichert mit Gabelhöhe und genauem Winkel")
	w.forklift_click(fi)
	ok(w.forklift != null and is_equal_approx(w.forklift.lift, lift_saved), "Wieder eingestiegen, die Gabel steht noch oben")
	w.forklift_leave()

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
