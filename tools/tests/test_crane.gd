extends SceneTree
## Hallenkran mit Funkfernbedienung: aus der Halterung nehmen, in die Halterung oder auf eine Werkbank legen,
## Fahren mit den Pfeiltasten (Figur läuft dabei frei), Behälter einhängen, heben, versetzen, absetzen. Dazu der Späneweg ohne Kran: Behälter schieben,
## Spänewanne hineinleeren, im Hof in den Container kippen, abstellen. Speichern und Laden der Kranstellung.
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


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 5000, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var c = w.crane
	w.start_day()
	ok(c != null and c.get_parent() == w, "Hallenkran steht in der Werkstatt")

	# ---------------------------------------------------- Behälter aufstellen
	var at := Vector2(-4.0, -3.0)
	ok(w.layout.check_bin(at, 0, -1, "bin_l") == "", "Platz frei: " + w.layout.check_bin(at, 0, -1, "bin_l"))
	w.layout.bins.append({"size": "bin_l", "pos": at, "rot": 0, "chips": ChipTray.new(60.0), "out": false})
	w._rebuild_stands()
	var bi: int = w.layout.bins.size() - 1
	var node = w.bin_nodes[bi]
	var h: float = w.crane_bin_height(bi)
	ok(w.bin_prompt(bi).contains("schieben"), "Behälter lässt sich schieben: " + w.bin_prompt(bi))

	# ---------------------------------------------------- Taster nehmen, frei laufen, fahren
	p.global_position = Vector3(c.bridge_x + 0.5, 0.05, c.trolley_z + 0.5)
	await frames(2)
	ok(c.get_prompt().contains("Fernbedienung nehmen"), "Hinweis an der Halterung: " + c.get_prompt())
	ok(c._remote.visible, "Fernbedienung steckt in der Halterung")
	c.grab(p)
	ok(p.carrying_pendant() and c.held_by == p and not c._remote.visible, "Fernbedienung in der Hand, Halterung leer")
	ok(p.operating == null, "Figur bedient keine Maschine, sie läuft frei")
	var x0: float = c.bridge_x
	var z0: float = c.trolley_z
	p.yaw = 0.0                       # Blick nach -Z
	Input.action_press("crane_forward")
	await frames(40)
	Input.action_release("crane_forward")
	await frames(40)
	ok(c.trolley_z < z0 - 0.2 and absf(c.bridge_x - x0) < 0.05, "Pfeil hoch fährt die Katze in Blickrichtung (%.2f -> %.2f)" % [z0, c.trolley_z])
	p.yaw = PI / 2.0                  # Blick nach -X
	Input.action_press("crane_forward")
	await frames(40)
	Input.action_release("crane_forward")
	await frames(40)
	ok(c.bridge_x < x0 - 0.2, "Nach Drehen fährt die Brücke (%.2f -> %.2f)" % [x0, c.bridge_x])
	var y0: float = c.hook_y
	Input.action_press("crane_down")
	await frames(40)
	Input.action_release("crane_down")
	await frames(30)
	ok(c.hook_y < y0 - 0.2, "Haken senkt sich")
	var walk0: Vector3 = p.global_position
	Input.action_press("move_forward")
	await frames(20)
	Input.action_release("move_forward")
	await frames(10)
	ok(p.global_position.distance_to(walk0) > 0.2 and p.carrying_pendant(), "Mit der Fernbedienung in der Hand gelaufen")

	# ---------------------------------------------------- Einhängen, heben, versetzen, absetzen
	c.bridge_x = at.x
	c.trolley_z = at.y
	c.hook_y = 3.5
	c.hook_click()
	ok(c.hooked < 0, "Zu hoch: nichts eingehängt")
	c.hook_y = c.SLING + h + 0.2
	c.hook_click()
	ok(c.hooked == bi and w.layout.bins[bi].get("hooked", false), "Behälter eingehängt")
	c.hook_y = 4.0
	await frames(3)
	ok(node.global_position.y > 1.0, "Behälter hängt in der Luft (%.2f m)" % node.global_position.y)
	c.hook_click()
	ok(c.hooked == bi, "In der Luft lässt er sich nicht aushängen")
	var to := Vector2(-4.0, 1.5)
	c.bridge_x = to.x
	c.trolley_z = to.y
	c.hook_y = 0.0
	await frames(3)
	ok(is_equal_approx(c.hook_y, c.SLING + h), "Haken stoppt, wenn der Behälter aufsteht")
	ok(node.global_position.y < 0.01, "Behälter steht am Boden")
	c.hook_click()
	ok(c.hooked < 0 and not w.layout.bins[bi].has("hooked"), "Ausgehängt")
	ok(w.layout.bins[bi]["pos"].distance_to(to) < 0.01, "Neuer Stellplatz gespeichert")

	# ---------------------------------------------------- Weit weg laufen, ablegen
	p.global_position = Vector3(c.bridge_x + 8.0, 0.05, c.trolley_z)
	await frames(2)
	ok(p.carrying_pendant() and c.held_by == p, "Funk: Auch weiter weg bleibt sie in der Hand")
	p.drop()
	ok(p.carrying_pendant() and c.held_by == p, "Q lässt sie nicht fallen")
	ok(c.get_prompt().contains("in die Halterung"), "An der Halterung: ablegen")
	c.interact(p)
	ok(not p.carrying_pendant() and c.held_by == null and c._remote.visible, "In die Halterung gelegt")
	# Auf der Werkbank ablegen und wieder nehmen
	ok(not w.bench_nodes.is_empty(), "Eine Werkbank steht in der Werkstatt")
	var bid: String = str(w.bench_nodes.keys()[0])
	var bench = w.bench_nodes[bid]
	var top := Vector3(bench.global_position.x, 0.92, bench.global_position.z)
	c.grab(p)
	ok(w.crane_bench_at(bench, top, Vector3.UP) == bid, "Werkbankplatte erkannt")
	ok(w.crane_bench_at(bench, top + Vector3(0, -0.5, 0), Vector3.UP) == "", "Nicht unter der Platte")
	ok(w.crane_put_on_bench(bench, top, Vector3.UP), "Auf die Werkbank gelegt")
	ok(not p.carrying_pendant() and c.remote_bench == bid and not c._remote.visible, "Liegt auf der Werkbank, Halterung leer")
	ok(c.get_prompt().contains("Werkbank"), "Halterung verweist auf die Werkbank: " + c.get_prompt())
	c.interact(p)
	ok(not p.carrying_pendant(), "Aus der leeren Halterung nichts zu nehmen")
	var saved_b: Dictionary = c.get_state()
	ok(saved_b.has("remote") and str(saved_b["remote"]["bench"]) == bid, "Platz auf der Werkbank gespeichert")
	c.set_state({})
	ok(c.remote_bench == "" and c._remote.visible, "Ohne Angabe: zurück in die Halterung")
	c.set_state(saved_b)
	ok(c.remote_bench == bid and c._loose.global_position.distance_to(top) < 0.1, "Geladen: wieder auf der Werkbank")
	var pick = c._loose.get_children().filter(func(n): return n.has_method("interact"))[0]
	ok(pick.get_prompt().contains("nehmen"), "Hinweis auf der Werkbank")
	pick.interact(p)
	await frames(1)
	ok(p.carrying_pendant() and c.remote_bench == "" and c.held_by == p, "Von der Werkbank genommen")
	c.put_on_bench(bid, bench, top, 0.0)
	c.bench_gone(bid)
	ok(c.remote_bench == "" and c._remote.visible, "Werkbank abgebaut: zurück in die Halterung")

	# ---------------------------------------------------- Späneweg ohne Kran: schieben, leeren, kippen
	var l = w.lathe
	l.tray.add("baustahl", 6.0)
	l.spindle_speed = 0.0
	p.global_position = Vector3(to.x + 2.0, 0.05, to.y)
	w.bin_click(bi)
	ok(p.carrying_bin() and w.layout.bins[bi]["out"], "Behälter wird geschoben")
	w.clamp_carried(l)
	ok(l.tray.is_empty() and w.layout.bins[bi]["chips"].kg > 5.9, "Spänewanne in den Behälter geleert")
	var ci: int = w.CONTAINER_SORTS.find("stahl")
	var before: float = w.containers[ci].kg
	w.container_click(ci)
	ok(w.containers[ci].kg > before + 5.9 and w.layout.bins[bi]["chips"].is_empty(), "Im Container ausgekippt")
	p.global_position = Vector3(-6.0, 0.05, 5.0)
	p.yaw = PI                        # Blick nach +Z
	await frames(2)
	p.drop()
	ok(not p.carrying_bin() and not w.layout.bins[bi]["out"], "Q stellt den Behälter vor der Figur ab")
	ok(w.layout.bins[bi]["pos"].y > 5.5, "Neuer Platz vor der Figur")

	# ---------------------------------------------------- Speichern und Laden
	c.bridge_x = 3.0
	c.trolley_z = -2.0
	var st: Dictionary = c.get_state()
	c.bridge_x = 0.0
	c.set_state(st)
	ok(is_equal_approx(c.bridge_x, 3.0) and is_equal_approx(c.trolley_z, -2.0), "Kranstellung geladen")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
