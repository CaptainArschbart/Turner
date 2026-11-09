extends SceneTree
## Hoftor und Orte: Tor im Südzaun, Reisemenü, begehbarer Supermarkt mit Kasse, Zuhause je Spieler mit Bett.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func ray_target(w: Node, eye: Vector3, to: Vector3) -> Object:
	var hit: Dictionary = w.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, to))
	if hit.is_empty() or not hit["collider"].has_meta("interact"):
		return null
	return hit["collider"].get_meta("interact")


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "TestTor", "money": 250, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	w.autosave = false
	var p = w.player
	var gate = w.site.gate
	var pl = w.places

	# ---------------------------------------------------- Tor im Zaun
	ok(gate != null and gate.get_parent() == w.site, "Hoftor gebaut")
	ok(absf(gate.global_position.z - w.site.YARD_Z1) < 0.01 and absf(gate.global_position.x - w.site.GATE_X) < 0.01, "Tor sitzt im Südzaun an der Zufahrt")
	await physics_frame
	var eye := Vector3(w.site.GATE_X, 1.6, w.site.YARD_Z1 - 2.0)
	ok(ray_target(w, eye, eye + Vector3(0, -0.3, 3.0)) == gate, "Blick trifft das Tor")
	ok(gate.get_prompt().contains("Gelände verlassen"), "Hinweis: " + gate.get_prompt())
	ok(p.location == "site" and p.player_id == "local", "Spieler startet auf dem Gelände")

	# ---------------------------------------------------- Reisemenü am Tor
	var tm = w.travel_menu
	gate.interact(p)
	ok(tm.visible and p.operating == tm, "E am Tor öffnet das Reisemenü")
	var ids := []
	for d in pl.destinations(p):
		ids.append(d["id"])
	ok(ids == ["supermarket", "home:local"], "Vom Gelände: Supermarkt und Zuhause: %s" % str(ids))
	ok(tm._list.get_child_count() == 2, "Zwei Knöpfe")

	# ---------------------------------------------------- Supermarkt
	ok(tm.go("supermarket") == "", "Zum Supermarkt")
	ok(not tm.visible and p.operating == null, "Menü zu")
	ok(p.location == "supermarket" and p.global_position.distance_to(pl.supermarket.spawn_point()) < 0.1, "Im Supermarkt angekommen")
	ok(p.global_position.distance_to(gate.global_position) > 1000.0, "Supermarkt ist ein eigener Ort, weit weg vom Gelände")
	for i in 20:
		await physics_frame
	ok(p.global_position.y > -0.5 and p.global_position.y < 0.5, "Steht auf dem Supermarktboden: %.2f" % p.global_position.y)
	var till = null
	var exit_door = null
	for c in pl.supermarket.get_children():
		if "prompt" in c and c.has_method("interact"):
			if c.prompt.contains("Kasse"):
				till = c
			elif c.prompt.contains("Ausgang"):
				exit_door = c
	ok(till != null and exit_door != null, "Kasse und Ausgang")
	var sm = w.shop_menu
	till.interact(p)
	ok(sm.visible and p.operating == sm, "Kasse öffnet den Einkauf")
	var cig = p.cigarette
	var cigs0: int = cig.stock
	var cash0: int = w.money
	ok(sm.buy(0) == "" and cig.stock == cigs0 + 20 and w.money == cash0 - 9, "Schachtel gekauft")
	w.money = 5
	ok(sm.buy(1) != "" and cig.stock == cigs0 + 20 and w.money == 5, "Zu wenig Geld: nichts gekauft")
	w.money = cash0
	sm.close()
	ok(not sm.visible and p.operating == null, "Kasse zu")
	exit_door.interact(p)
	ids = []
	for d in pl.destinations(p):
		ids.append(d["id"])
	ok(tm.visible and ids == ["site", "home:local"], "Ausgang: Werkstatt oder Zuhause: %s" % str(ids))
	tm.close()

	# ---------------------------------------------------- Zigarettenvorrat
	cig.stock = 0
	cig.toggle()
	ok(not cig.lit, "Ohne Zigaretten kein Anzünden")
	cig.stock = 2
	cig.toggle()
	ok(cig.lit and cig.stock == 1, "Anzünden verbraucht eine")
	cig.put_out()
	ok(int(cig.get_state()["stock"]) == 1, "Vorrat im Spielstand")
	cig.set_state({"need": 1.0})
	ok(cig.stock == cig.START_STOCK, "Alter Spielstand: volle Schachtel")

	# ---------------------------------------------------- Mehrere Zuhause
	var mine = pl.home_of("local")
	var other = pl.home_of("spieler2")
	ok(mine != other and mine.id == "home:local" and other.id == "home:spieler2", "Jeder hat sein eigenes Zuhause")
	ok(mine.global_position.distance_to(other.global_position) >= pl.HOME_SPACING - 0.1, "Wohnungen stehen getrennt")
	ok(pl.home_of("local") == mine, "Zuhause wird nur einmal angelegt")
	ok(pl.to_state()["home_slots"] == {"local": 0, "spieler2": 1}, "Plätze im Spielstand")

	# ---------------------------------------------------- Zuhause und Schlafen
	w.whiteboard.overlay.day_app.start_button.pressed.emit()
	ok(pl.travel(p, "home:local") == "" and p.location == "home:local", "Nach Hause")
	for i in 20:
		await physics_frame
	ok(absf(p.global_position.y - mine.global_position.y) < 0.5, "Steht im Zuhause")
	var bed = null
	for c in mine.get_children():
		if "prompt" in c and c.has_method("interact") and c.prompt.contains("Bett"):
			bed = c
	ok(bed != null, "Bett")
	var day0: int = w.day
	bed.interact(p)
	ok(w.day == day0 and w.day_started and not w.day_over, "Tagsüber nicht schlafen")
	w.whiteboard.overlay.day_app.end_button.pressed.emit()
	ok(w.day_over and w.day == day0, "Tag beenden am Whiteboard: Feierabend")
	ok(not w.whiteboard.overlay.day_app.end_button.visible, "Kein zweites Beenden")
	ok(w.hud._clock.text.contains("Hoftor"), "Uhr verweist aufs Hoftor: " + w.hud._clock.text)
	bed.interact(p)
	ok(w.day == day0 + 1 and w.day_started and not w.day_over and w.day_time == 0.0, "Schlafen beginnt den nächsten Tag")
	ok(p.location == "home:local" and p.global_position.distance_to(mine.wake_point()) < 0.5, "Aufwachen zuhause")
	ok(w.sleep_error() != "", "Gleich wieder schlafen geht nicht")
	# Tragen verhindert das Reisen
	p.carry = {"kind": "bar"}
	ok(pl.travel(p, "site") != "" and p.location == "home:local", "Mit Material in den Händen nicht weg")
	p.carry = {}
	ok(pl.travel(p, "site") == "" and p.location == "site" and p.global_position.distance_to(w.site_entry()) < 0.1, "Zurück am Hoftor")
	# Feierabend um 18 Uhr reicht auch
	w._advance_day(w.DAY_SECONDS + 1.0)
	ok(w.day_over and w.go_sleep(p) == "" and w.day == day0 + 2, "Nach 18 Uhr schlafen")
	# Spielstand: Ort und Plätze kommen zurück
	var st: Dictionary = p.get_state()
	ok(st["location"] == "home:local" and st["id"] == "local", "Ort im Spielstand")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
