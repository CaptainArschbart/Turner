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
	p.global_position = Vector3(10.5, 0.05, 6.0)
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
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
