extends SceneTree
## Gelände: Rolltore, Lieferungen vor dem Lagertor, Ausbau am PC.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func aim(p, from: Vector3, target: Vector3) -> void:
	p.global_position = from
	p.velocity = Vector3.ZERO
	var eye: Vector3 = from + Vector3(0, 1.62, 0)
	var d: Vector3 = target - eye
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	for i in 6:
		await physics_frame
func ray_blocked(from: Vector3, to: Vector3) -> bool:
	var space := (root.get_world_3d() as World3D).direct_space_state
	return not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to)).is_empty()
## Lieferungen aus dem Hof aufheben und ins Regal legen.
func deliver(w) -> void:
	while not w.deliveries.is_empty():
		w.pick_delivery(0)
		w.store_carried(-1)
func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var site = w.site
	var p = w.player
	for i in 5:
		await physics_frame

	# Zwei Bereiche mit eigenem Rolltor
	ok(site.door_workshop != site.door_lager, "Zwei Rolltore")
	var wd = site.door_workshop
	var ld = site.door_lager
	ok(wd.target == 0.0 and ld.target == 0.0, "Tore sind anfangs zu")
	# Wand: Durch das geschlossene Tor kommt man nicht, durch das offene schon
	var in_w := Vector3(11.0, 1.0, -2.0)
	var out_w := Vector3(13.5, 1.0, -2.0)
	ok(ray_blocked(in_w, out_w), "Geschlossenes Werkstatttor sperrt")
	ok(ray_blocked(Vector3(11.0, 1.0, 3.0), Vector3(13.5, 1.0, 3.0)), "Wand neben dem Tor sperrt")
	# Knopf innen neben dem Tor
	await aim(p, Vector3(10.4, 0.05, -4.75), wd.to_global(Vector3(wd.WIDTH * 0.5 + 0.5, 1.35, -0.3)))
	ok(p._focus != null and p._focus.get_prompt().contains("Werkstatt-Rolltor"), "Knopf innen lässt sich anvisieren")
	if p._focus:
		ok(p._focus.get_prompt().contains("öffnen"), "Hinweis öffnen: " + p._focus.get_prompt())
		p._focus.interact(p)
	ok(wd.is_opening(), "E öffnet das Tor")
	ok(p._focus.get_prompt().contains("schließen"), "Hinweis schließen")
	for i in 20:
		await process_frame
	ok(wd.open_t > 0.0 and wd.open_t < 1.0, "Tor fährt langsam")
	wd.set_open(true, true)
	await physics_frame
	await physics_frame
	ok(wd.is_open(), "Tor ist offen")
	ok(not ray_blocked(in_w, out_w), "Offenes Tor lässt durch")
	wd.toggle()
	await physics_frame
	await physics_frame
	ok(ray_blocked(in_w, out_w), "Beim Schließen sofort wieder fest")
	wd.set_open(true, true)
	# Knopf außen, per Linksklick
	await aim(p, Vector3(13.8, 0.05, -4.75), wd.to_global(Vector3(wd.WIDTH * 0.5 + 0.5, 1.35, 0.3)))
	ok(p._focus != null and p._focus.get_prompt().contains("Werkstatt-Rolltor"), "Knopf außen lässt sich anvisieren")
	if p._focus:
		p.click_focus()
	ok(not wd.is_opening(), "Linksklick auf den Knopf schließt")
	wd.set_open(false, true)
	# Lagertor: Spielfigur kommt erst durch, wenn es offen ist
	var in_l := Vector3(18.0, 1.0, -9.5)
	var out_l := Vector3(18.0, 1.0, -6.5)
	ok(ray_blocked(in_l, out_l), "Geschlossenes Lagertor sperrt")
	ld.set_open(true, true)
	await physics_frame
	await physics_frame
	ok(not ray_blocked(in_l, out_l), "Offenes Lagertor lässt durch")
	ld.set_open(false, true)

	# Hof ist umschlossen, Boden überall
	ok(ray_blocked(Vector3(20.0, 2.0, 0.0), Vector3(20.0, -1.0, 0.0)), "Hofboden")
	ok(ray_blocked(Vector3(18.0, 2.0, -12.0), Vector3(18.0, -1.0, -12.0)), "Lagerboden")
	ok(ray_blocked(Vector3(33.0, 1.0, 0.0), Vector3(36.0, 1.0, 0.0)), "Zaun Osten")
	ok(ray_blocked(Vector3(20.0, 1.0, 11.0), Vector3(20.0, 1.0, 14.0)), "Zaun Süden")
	ok(ray_blocked(Vector3(13.0, 1.0, 10.0), Vector3(10.0, 1.0, 10.0)), "Zaun Westen")
	ok(ray_blocked(Vector3(28.0, 1.0, -7.0), Vector3(28.0, 1.0, -10.0)), "Zaun Norden")

	# Bestellung landet vor dem Lagertor, nicht im Lager
	w.money = 1000
	w.stock = []
	var spec := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 3000.0, "qty": 2}
	ok(w.order_material(spec) == "", "Bestellt")
	ok(w.stock.is_empty() and w.deliveries.size() == 2, "Liegt vor dem Tor, nicht im Lager")
	await process_frame
	ok(site._deliveries.get_child_count() == 2, "Lieferungen sichtbar")
	var pos: Vector3 = site.delivery_pos(0)
	ok(pos.x > 12.0 and pos.x < 34.0 and pos.z > -8.0, "Lieferung steht im Hof")
	ok(absf(site.delivery_pos(0).z - site.LAGER_Z) < 4.0, "Direkt vor dem Lagertor")
	for i in 40:
		var q: Vector3 = site.delivery_pos(i)
		ok(q.x > 13.5, "Weg am Werkstatttor bleibt frei %d" % i)
		ok(q.z - 1.35 > site.LAGER_Z, "Tor bleibt frei %d" % i)
		ok(q.x < site.YARD_X1 and q.z < site.YARD_Z1, "Im Hof %d" % i)
	# Ohne Lagerbestand gibt es kein Rohteil, der Hinweis nennt die Lieferung
	w.stock = []
	var msg: String = w._lathe_take_part()
	ok(msg.contains("Rolltor") and not w.lathe.has_part, "Hinweis auf die wartende Lieferung: " + msg)
	# Tragen und Ablegen prüft test_build, hier nur das Ergebnis
	deliver(w)
	ok(w.stock.size() == 2 and w.deliveries.is_empty(), "Alles im Lager")
	ok(site._stored.get_child_count() == 2, "Stücke liegen sichtbar im Regal")
	ok(str(w._lathe_take_part()).contains("Lager") and not w.lathe.has_part, "Jetzt liegt das Rohteil bereit, geholt wird es von Hand")
	# Regalplätze innerhalb der Kacheln
	for i in site.capacity():
		var s: Vector3 = site._slot_pos(i)
		ok(s.x > site.LAGER_X0 and s.x < site.LAGER_X0 + site.L_TILE.x * 2.0, "Platz %d in der Breite" % i)
		ok(s.z < site.LAGER_Z and s.z > site.LAGER_Z - site.L_TILE.y * 2.0, "Platz %d in der Tiefe" % i)
	# Volles Lager nimmt nichts mehr an
	w.stock = []
	var one := {"material": "S235", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0}
	for i in site.capacity():
		w.stock.append({"material": "S235", "kind": "cut", "d": 0.0, "w": 900.0, "h": 40.0, "l": 3000.0, "slot": i})
	w.deliveries = [one.duplicate()]
	w._deliveries_changed()
	ok(w.pick_delivery(0) == "", "Aufheben geht auch bei vollem Lager")
	ok(w.store_carried(-1) != "" and not p.carry.is_empty(), "Volles Lager nimmt nichts mehr an")
	p.clear_carry()
	w.stock = []
	w.deliveries = []
	w._deliveries_changed()
	w._stock_changed()

	# Speichern und Laden
	w.money = 123
	wd.set_open(true, true)
	w.deliveries = [one.duplicate()]
	var d := {"name": "T", "money": 123, "site": w._site_state(), "deliveries": JSON.parse_string(JSON.stringify(w.deliveries)), "lathe": w.lathe.get_state(), "mill": w.mill.get_state()}
	d = JSON.parse_string(JSON.stringify(d))
	wd.set_open(false, true)
	w.deliveries = []
	w._apply_pending(d)
	await process_frame
	ok(wd.is_open() and not ld.is_open(), "Torstellung gespeichert")
	ok(w.deliveries.size() == 1 and site._deliveries.get_child_count() == 1, "Lieferung gespeichert")
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
