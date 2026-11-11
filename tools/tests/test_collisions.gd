extends SceneTree
## Kollisionen loser Gegenstände: Form nach dem Modell, Landen auf den sichtbaren Flächen statt auf den Hüllen
## (im Spänebehälter, auf den Spänen, auf dem Bett der Drehmaschine) und Aufheben von dort.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


## Spielfigur auf den Punkt ausrichten und den Sichtstrahl aktualisieren.
func aim(p, from: Vector3, target: Vector3) -> void:
	p.global_position = from
	p.velocity = Vector3.ZERO
	var eye: Vector3 = from + Vector3(0, 1.62, 0)
	var d: Vector3 = target - eye
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	for i in 6:
		await physics_frame


## Warten, bis der Gegenstand liegt (höchstens 15 s Spielzeit).
func settle(d) -> void:
	for i in 900:
		await physics_frame
		if i > 30 and is_instance_valid(d) and d.resting:
			break


func shape_of(d) -> Shape3D:
	for c in d.get_children():
		if c is CollisionShape3D:
			return (c as CollisionShape3D).shape
	return null


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 5000, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var l = w.lathe
	w.start_day()
	var steel: String = l.material
	var DI = load("res://scripts/world/dropped_item.gd")     # erst jetzt laden: braucht die Autoloads
	var block := {"kind": "part", "key": "", "machine": "mill", "material": steel, "part": {}, "res": {},
		"title": "Block", "shape": "block", "l": 80.0, "w": 60.0, "h": 30.0}

	# ---------------------------------------------------- Form nach dem Modell
	var d0 = DI.spawn(w, p, block.duplicate(true), Vector3(3.0, 0.6, 3.0), 0.3)
	await physics_frame
	var s0 := shape_of(d0)
	ok(s0 is ConvexPolygonShape3D and (s0 as ConvexPolygonShape3D).points.size() == 8, "Block: Form aus den acht Ecken des Modells")
	if s0 is ConvexPolygonShape3D:
		var far := 0.0
		for q in (s0 as ConvexPolygonShape3D).points:
			far = maxf(far, absf(q.x))
		ok(absf(far - (0.04 + d0.SKIN * 0.74)) < 0.004, "Block: halbe Länge 40 mm plus Rand (%.1f mm)" % (far * 1000.0))
	await settle(d0)
	ok(d0.resting and d0.global_position.y < 0.05, "Block liegt auf dem Hallenboden (%.3f m)" % d0.global_position.y)
	var tool_item := {"kind": "tool", "machine": "lathe", "id": "T5", "name": "Fasenmeißel"}
	var dt = DI.spawn(w, p, tool_item, Vector3(3.6, 0.6, 3.0), 0.0)
	await physics_frame
	var st := shape_of(dt)
	ok(st is ConvexPolygonShape3D and (st as ConvexPolygonShape3D).points.size() > 8, "Werkzeug: Form folgt dem Meißel, kein Quader")
	await settle(dt)
	ok(dt.resting and Build.bounds(dt).position.y < 0.03, "Werkzeug liegt auf dem Boden")
	d0.discard()
	dt.discard()

	# ---------------------------------------------------- In den Spänebehälter
	var at := Vector2(-4.0, 3.0)
	w.layout.bins.append({"size": "bin_l", "pos": at, "rot": 0, "chips": ChipTray.new(60.0), "out": false})
	w._rebuild_stands()
	var bi: int = w.layout.bins.size() - 1
	var bin: Node3D = w.bin_nodes[bi]
	var size: Vector3 = ChipBin.size_of("bin_l")
	await physics_frame
	ok(bin._hit.is_in_group("solid_hull"), "Hülle des Behälters ist für lose Gegenstände durchlässig")
	ok(not bin.find_children("Solid", "AnimatableBody3D", true, false).is_empty(), "Behälter hat Wände und Boden als eigene Körper")
	var inside := Vector3(at.x - 0.3, size.y + 0.4, at.y)
	var d1 = DI.spawn(w, p, block.duplicate(true), inside, 0.2)
	await settle(d1)
	ok(d1.resting and d1.global_position.y < size.y * 0.5 and d1.global_position.y > 0.02,
		"Block fällt in den Behälter (liegt auf %.2f m, Rand bei %.2f m)" % [d1.global_position.y, size.y])
	ok(absf(d1.global_position.x - at.x) < size.x * 0.5 and absf(d1.global_position.z - at.y) < size.z * 0.5, "Block liegt innerhalb der Wände")
	# Hineingreifen: Der Behälter ist höher als die Augen, der Blick trifft seine Wand
	p.clear_carry()
	await aim(p, Vector3(at.x - 0.3, 0.05, at.y + size.z * 0.5 + 0.45), d1.global_position)
	ok(p._focus == d1, "Griff in den Behälter trifft den Block (Ziel: %s)" % [p._focus])
	p.click_focus()
	ok(p.carrying_part() and not is_instance_valid(d1) or d1.is_queued_for_deletion(), "Block aus dem Behälter genommen")
	p.clear_carry()
	# Daneben: prallt außen ab und bleibt draußen
	var d2 = DI.spawn(w, p, block.duplicate(true), Vector3(at.x - size.x * 0.5 - 0.25, 1.0, at.y), 0.0)
	await settle(d2)
	ok(d2.resting and absf(d2.global_position.x - at.x) > size.x * 0.5 - 0.1, "Neben dem Behälter bleibt der Block draußen")
	d2.discard()
	# Auf den Spänen: halb voller Behälter
	(w.layout.bins[bi]["chips"] as ChipTray).add("stahl", 30.0)
	bin.show_state(0.5, false)
	await physics_frame
	var d3 = DI.spawn(w, p, block.duplicate(true), inside, 0.2)
	await settle(d3)
	ok(d3.resting and d3.global_position.y > size.y * 0.4, "Auf den Spänen liegt der Block höher (%.2f m)" % d3.global_position.y)
	# Am Kran: Der Block fährt im Behälter mit nach oben
	var c = w.crane
	c.bridge_x = at.x
	c.trolley_z = at.y
	c.hook_y = c.SLING + size.y + 0.02
	await physics_frame
	c.hook_click()
	ok(c.hooked == bi, "Behälter am Kran eingehängt")
	var y0: float = d3.global_position.y
	for i in 200:
		c.hook_y = minf(c.hook_y + 0.006, c.SLING + size.y + 1.0)
		await physics_frame
	await settle(d3)
	ok(d3.global_position.y > y0 + 0.8 and absf(d3.global_position.x - at.x) < size.x * 0.5,
		"Der Block wird mit dem Behälter gehoben (%.2f -> %.2f m)" % [y0, d3.global_position.y])
	c.hook_y = 0.0
	for i in 240:
		await physics_frame
	c.hook_click()
	d3.discard()

	# ---------------------------------------------------- Auf der Drehmaschine
	var hull_top := 1.62
	var over_bed: Vector3 = l.to_global(Vector3(0.9, hull_top + 0.5, 0.05))
	var d4 = DI.spawn(w, p, block.duplicate(true), over_bed, 0.0)
	await settle(d4)
	ok(d4.resting and d4.global_position.y < hull_top - 0.3 and d4.global_position.y > 0.3,
		"Block liegt auf der Maschine und nicht auf ihrer Hülle (%.2f m)" % d4.global_position.y)
	# Von vorn, nah an der Maschine und von oben: Der Blick geht über den Bettschlitten hinweg
	var front: Vector3 = l.to_global(Vector3(0.9, 0.05, 0.95))
	await aim(p, front, d4.global_position + Vector3(0, 0.012, 0))
	ok(p._focus == d4, "Block auf der Maschine lässt sich anvisieren (Ziel: %s)" % [p._focus])
	p.click_focus()
	ok(p.carrying_part(), "Block von der Maschine genommen")
	p.clear_carry()
	# Ohne Gegenstand im Weg trifft der Blick weiter die Maschine
	await aim(p, front, l.to_global(Vector3(0.9, 1.0, 0.0)))
	ok(p._focus != null and p._focus.has_method("get_machine"), "Blick auf die Maschine trifft die Maschine (Ziel: %s)" % [p._focus])

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
