extends SceneTree
## Rauchtest: Werkstatt laden, Maschine bedienen, Bedienpult sichtbar, ein paar Frames ohne Fehler.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func _initialize() -> void:
	await process_frame
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	w.lathe.interact(w.player)
	for i in 30:
		await physics_frame
	ok(w.lathe.operating, "Maschine wird bedient")
	ok(w.hud._panel.is_visible_in_tree(), "Bedienpult sichtbar")
	ok(w.hud._status.text.contains("Platz 1"), "Status zeigt Halterplatz")
	var box: Rect2 = w.hud._tool_box.get_global_rect()
	var job: Rect2 = w.hud._job_panel.get_global_rect()
	print("viewport ", root.get_visible_rect().size, " box ", box, " job ", job, " panel ", w.hud._panel.size)
	ok(not box.intersects(job), "Pult überdeckt den Auftrag nicht")
	ok(box.size.y + job.end.y + 20.0 <= 900.0, "Pult passt bei 900 px Höhe unter den Auftrag")
	var help: Rect2 = w.hud._help_panel.get_global_rect()
	print("help ", help)
	ok(help.end.x < box.position.x, "Steuerungshilfe und Pult überlappen nicht")
	w.lathe.stop_operating()
	await process_frame
	ok(not w.hud._panel.is_visible_in_tree(), "Pult nach Verlassen aus")
	# E auf das Bedienpult: direkt in die Pultansicht, Dreh-Anzeigen aus
	var pt: Node = null
	for ch in w.lathe.get_children():
		if ch.has_method("interact") and ch.has_method("get_prompt"):
			pt = ch
	ok(pt != null, "Bedienpult hat ein eigenes Interaktionsziel")
	pt.interact(w.player)
	for i in 3:
		await process_frame
	ok(w.lathe.operating and w.lathe.in_panel_view(), "E aufs Pult öffnet die Pultansicht")
	ok(not w.hud._panel.is_visible_in_tree() and not w.hud._dro_panel.visible, "Dreh-UI in der Pultansicht ausgeblendet")
	w.lathe.toggle_panel_view()
	for i in 3:
		await process_frame
	ok(w.hud._panel.is_visible_in_tree() and w.hud._dro_panel.visible, "zurück an der Maschine: Dreh-UI wieder da")
	w.lathe.stop_operating()
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
