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
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
