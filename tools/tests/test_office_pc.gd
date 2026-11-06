extends SceneTree
## Büro-PC: anvisieren, mit Interagieren öffnen, Übersicht vollständig, mit Interagieren und Esc schließen.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	root.push_input(e)
	await process_frame
func collect(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n.text)
	for c in n.get_children():
		collect(c, out)
func meshes(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D and n.mesh and n.mesh.get_surface_count() > 0:
		c = 1
	for k in n.get_children():
		c += meshes(k)
	return c
func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var pc = w.office_pc
	var p = w.player
	# Vom Büroeingang aus quer durch den Raum zum Monitor schauen
	p.global_position = Vector3(9.3, 0.05, 10.2)
	p.yaw = PI
	p.pitch = -0.3
	for i in 10:
		await physics_frame
	ok(p._focus == pc, "PC lässt sich anvisieren")
	ok(p._prompt.contains("PC bedienen"), "Hinweis wird angezeigt")
	await press("interact")
	ok(p.operating == pc, "Interagieren öffnet den PC")
	ok(pc.overlay.visible, "Overlay sichtbar")
	ok(not w.hud.visible, "HUD ausgeblendet")
	ok(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Mauszeiger frei")
	var texts := []
	collect(pc.overlay, texts)
	for t in ["Drehmaschinen", "Fräsmaschinen", "Rundschleifmaschinen", "Flachschleifmaschinen",
			"Standbohrmaschinen", "Erodiermaschinen", "Feilen", "Handentgrater"]:
		ok(texts.has(t), "Übersicht enthält " + t)
	ok(texts.count("CNC") == 2 and texts.count("Konventionell") == 2, "Dreh- und Fräsmaschinen haben CNC und Konventionell")
	# Maschinenwerkzeuge gibt es nur noch im Shop
	var o = pc.overlay
	ok(o.tabs.get_tab_count() == 5, "Fünf Tabs im Shop")
	ok(o.overview_tabs.get_tab_count() == 2, "Maschinen und Handwerkzeuge in der Maschinenübersicht")
	for i in o.overview_tabs.get_tab_count():
		ok(o.overview_tabs.get_tab_title(i) != "Maschinenwerkzeuge", "Kein Tab Maschinenwerkzeuge in der Übersicht")
	ok(o.tabs.get_tab_title(1) == "Maschinenwerkzeuge", "Im Shop bleibt der Tab")
	o.open_program("overview")
	ok(texts.has("Im Spiel: " + MachineCatalog.MILL_NAME), "Fräsmaschine steht in der Maschinenübersicht")
	o.overview_tabs.current_tab = 0
	await press("interact")
	ok(not pc.overlay.visible and p.operating == null, "Interagieren schließt den PC")
	ok(w.hud.visible, "HUD wieder da")
	ok(not w.pause_menu.visible, "Pause-Menü bleibt zu")
	for i in 3:
		await physics_frame
	await press("interact")
	ok(pc.overlay.visible, "PC lässt sich erneut öffnen")
	await press("pause")
	ok(not pc.overlay.visible, "Esc schließt den PC")
	ok(not w.pause_menu.visible, "Esc öffnet dabei nicht das Pause-Menü")
	# Bürotür: von der Halle aus öffnen und hindurchgehen
	var hit_door = null
	for c in w.get_children():
		if c.has_method("get_prompt") and c.get("opened") != null:
			hit_door = c
	ok(hit_door != null, "Bürotür gibt es")
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(7.55, 0.05, 6.6)
	p.yaw = PI
	p.pitch = 0.0
	for i in 10:
		await physics_frame
	ok(p._focus == hit_door, "Tür lässt sich anvisieren: %s" % str(p._focus))
	ok(p._prompt.contains("Bürotür"), "Hinweis an der Tür: " + p._prompt)
	var blocked_z: float = p.global_position.z
	p.move_and_collide(Vector3(0, 0, 3.0))
	ok(p.global_position.z < 8.0, "Geschlossene Tür sperrt: %.2f" % p.global_position.z)
	p.global_position = Vector3(7.55, 0.05, blocked_z)
	await press("interact")
	ok(hit_door.opened, "E öffnet die Tür")
	for i in 60:
		await process_frame
	await physics_frame
	await physics_frame
	p.move_and_collide(Vector3(0, 0, 3.0))
	ok(p.global_position.z > 8.8, "Offene Tür: Spielfigur kommt ins Büro: %.2f" % p.global_position.z)
	p.move_and_collide(Vector3(0, 0, -3.0))
	ok(p.global_position.z < 7.0, "Und wieder hinaus: %.2f" % p.global_position.z)
	# In der Türöffnung und im Büro steht keine Außenhaut mehr
	var skin_in_room := false
	var umgebung = w.find_child("Umgebung", true, false)
	for m in umgebung.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = m.global_transform * m.get_aabb()
		if box.end.y > 0.1 and box.position.z < 8.5 and box.end.z > 8.2 and box.position.y < 2.5 and box.position.x < 11.6 and box.end.x > 5.4 and box.size.y < 30.0:
			skin_in_room = true
	ok(not skin_in_room, "Keine Außenhaut im Büro oder vor der Tür")
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
