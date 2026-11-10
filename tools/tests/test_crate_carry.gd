extends SceneTree
## Kleine Holzkiste samt Inhalt aufnehmen und auf die Werkbank stellen. Größere Kisten sind zu schwer.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


## Freier Bodenplatz für eine Kiste neben der Werkbank (nicht auf der Platte).
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


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var top_y: float = load("res://scripts/world/tool_bench.gd").TOP_Y
	var lay = w.layout
	w.money = 100000
	p.clear_carry()
	lay.crates.clear()
	w._rebuild_stands()
	var bench := "lathe"
	if not lay.benches.has(bench):
		w.inventory["bench"] = 1
		w.place_bench("", Vector2(0.6, 0.35), 2)
	ok(lay.benches.has(bench), "Werkbank steht")

	# Kleine Kiste mit zwei Teilen neben der Werkbank
	w.inventory["crate_s"] = 1
	w.inventory["crate_m"] = 1
	var spot: Vector2 = floor_spot(lay, "crate_s", bench)
	ok(spot != Vector2.INF and w.place_crate(-1, "crate_s", spot, 0) == "", "Kleine Kiste am Boden aufgestellt")
	var piece := {"material": "S235", "kind": "cut", "d": 0.0, "w": 60.0, "h": 40.0, "l": 100.0}
	lay.crates[0]["items"] = [piece.duplicate(), piece.duplicate()]
	w.crate_nodes[0].items = lay.crates[0]["items"]
	w.crate_nodes[0].refresh()
	ok(w.crate_prompt(0).contains("Kiste aufnehmen"), "Hinweis: Kiste aufnehmen")

	# Aufnehmen samt Inhalt
	ok(w.crate_lift(0) == "", "Kiste aufgenommen")
	ok(p.carrying_crate() and (p.carry["items"] as Array).size() == 2, "Inhalt kommt mit")
	ok(lay.crates.is_empty() and w.crate_nodes.is_empty(), "Kiste steht nicht mehr am Boden")
	ok(w.store_carried(0) != "", "Kiste geht nicht ins Regal")
	var st: Dictionary = JSON.parse_string(JSON.stringify(p.get_state()))
	ok(str(st["carry"]["kind"]) == "crate" and (st["carry"]["items"] as Array).size() == 2, "Getragene Kiste wird gespeichert")

	# Auf die Werkbank stellen: auf die Platte gezielt
	var top: Rect2 = lay.bench_area(bench)
	var at := Vector3(top.get_center().x, top_y, top.get_center().y)
	ok(w.crate_set_down(at) == "", "Auf die Werkbank gestellt")
	ok(p.hands_free() and lay.crates.size() == 1, "Hände wieder frei")
	ok(lay.crate_is_on_top(lay.crates[0]) and str(lay.crates[0]["bench"]) == bench, "Steht auf der Platte der Werkbank")
	ok(is_equal_approx(w.crate_nodes[0].position.y, top_y), "Auf Plattenhöhe")
	ok((lay.crates[0]["items"] as Array).size() == 2 and w.crate_nodes[0]._content.get_child_count() == 2, "Inhalt liegt noch drin")
	ok(w.crate_take(0) == "" and (lay.crates[0]["items"] as Array).size() == 1, "Teil aus der Kiste auf der Werkbank nehmen")
	p.clear_carry()

	# Wieder herunter neben die Werkbank (Q)
	ok(w.crate_lift(0) == "", "Von der Werkbank aufgenommen")
	spot = floor_spot(lay, "crate_s", bench)
	ok(w.crate_set_down(Vector3(spot.x, 0.0, spot.y)) == "" and not lay.crate_is_on_top(lay.crates[0]), "Neben der Werkbank abgestellt")
	ok(w.crate_lift(0) == "", "Nochmal aufgenommen")
	ok(w.crate_set_down(Vector3(40.0, 0.0, 40.0)) != "" and p.carrying_crate(), "Irgendwo weit weg geht nicht, Kiste bleibt in den Händen")
	ok(w.crate_set_down(at) == "", "Wieder auf die Werkbank")

	# Kiste in den Händen: Die Vorschau zeigt immer den Stellplatz, Linksklick stellt die Kiste dort ab
	ok(w.crate_lift(0) == "", "Für die Vorschau aufgenommen")
	await process_frame
	ok(w._crate_ghost != null and w._crate_ghost.visible, "Vorschau der Kiste sichtbar, ohne Q")

	# Blick auf die Werkbank: Die Platzsuche läuft einmal, danach kostet jedes Bild fast nichts
	var top_c: Vector2 = lay.bench_area(bench).get_center()
	w._rebuild_stands()
	var t0 := Time.get_ticks_usec()
	w.crate_spot(Vector3(top_c.x, top_y, top_c.y))
	var first_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	for i in 60:
		w.crate_spot(Vector3(top_c.x + i * 0.01, top_y, top_c.y), true)
	var frame_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 60.0
	print("Kisten-Platzsuche auf der Werkbank: erstes Mal %.2f ms, danach %.3f ms pro Bild" % [first_ms, frame_ms])
	ok(frame_ms < 0.5, "Blick über die Werkbank wandern lassen ruckelt nicht (%.3f ms pro Bild)" % frame_ms)
	ok(str(w.crate_spot(Vector3(top_c.x, top_y, top_c.y))["err"]) == "" and bool(w.crate_spot(Vector3(top_c.x, top_y, top_c.y))["top"]), "Stellplatz auf der Platte gefunden")

	# Figur so stellen, dass der Blick auf einen freien Platz zeigt
	var me: Vector3 = p.global_position
	var aim_ok := false
	var s: Dictionary = {}
	p.pitch = -0.9
	p.head.rotation.x = -0.9
	for dx in [0.0, 1.0, -1.0, 2.0, -2.0, 3.0]:
		for dz in [0.0, 1.0, -1.0, 2.0, -2.0, 3.0]:
			p.global_position = me + Vector3(dx, 0, dz)
			for i in 2:
				await physics_frame
			p.ray.force_raycast_update()
			s = w.crate_spot(p.crate_aim())
			if str(s["err"]) == "":
				aim_ok = true
				break
		if aim_ok:
			break
	ok(aim_ok, "Freien Stellplatz im Blick gefunden")
	for i in 2:
		await process_frame
	p.ray.force_raycast_update()
	s = w.crate_spot(p.crate_aim())
	ok(str(s["err"]) == "", "Stellplatz noch frei")
	var g: Node3D = w._crate_ghost
	var gpos: Vector2 = s["pos"]
	ok(g.visible and Vector2(g.position.x, g.position.z).distance_to(gpos) < 0.03, "Vorschau steht am Stellplatz")
	ok(w._pallet_ghost_mat.albedo_color.g > 0.9, "Vorschau grün: Platz ist frei")
	var n_before: int = lay.crates.size()
	p.click_focus()
	ok(p.hands_free() and lay.crates.size() == n_before + 1, "Linksklick stellt die Kiste ab")
	if lay.crates.size() > n_before:
		var placed: Dictionary = lay.crates[-1]
		ok((placed["pos"] as Vector2).distance_to(gpos) < 0.03, "Kiste steht dort, wo die Vorschau war")
		ok((placed["items"] as Array).size() == 1, "Inhalt kommt mit")
	else:
		p.clear_carry()
	await process_frame
	ok(not g.visible, "Vorschau weg, sobald die Kiste steht")
	p.global_position = me

	# Mittlere Kiste ist zu schwer
	var mspot: Vector2 = floor_spot(lay, "crate_m", bench)
	ok(mspot != Vector2.INF and w.place_crate(-1, "crate_m", mspot, 0) == "", "Mittlere Kiste aufgestellt")
	var mi: int = lay.crates.size() - 1
	ok(not w.crate_prompt(mi).contains("Kiste aufnehmen"), "Kein Hinweis zum Aufnehmen")
	ok(w.crate_lift(mi) != "" and p.hands_free() and lay.crates.size() == 2, "Mittlere Kiste zu schwer")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
