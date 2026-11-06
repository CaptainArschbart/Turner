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
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	w.money = 100000
	w.buy_equipment("cnc_lathe")
	ok(w.place_machine("cnc_lathe", Vector2(-1.0, 4.0), 0) == "", "CNC-Drehmaschine aufgestellt")
	var cnc = w.cnc_lathe
	cnc.interact(w.player)
	for i in 30:
		await physics_frame
	ok(cnc.operating, "Maschine wird bedient")
	# Knapp im Normalfall: Achsen und NC-Werte, keine Kasse, keine aufgeklappten Details
	ok(w.hud._dro_panel.visible and not w.hud._details.is_visible_in_tree(), "Details zu")
	ok(not w.hud._job_panel.visible, "Kassenfeld während der Arbeit aus")
	var main: String = w.hud._main.text
	for t in ["S ", "F ", "KSS", "T ", "Platz 1"]:
		ok(main.contains(t), "NC-Anzeige enthält " + t)
	ok(w.hud._dro.text.contains("X") and w.hud._dro.text.contains("Z"), "Achsen sichtbar")
	ok(not main.contains("vc") and not main.contains("Tür"), "Keine Nebeninfos im Normalfall")
	ok(w.hud._chip.visible and not w.hud._overlay.visible, "Unten rechts nur der Hinweis")
	ok(not w.hud._panel.is_visible_in_tree(), "Bedienpult zu")
	var small: float = w.hud._dro_panel.size.y
	# Links Alt halten
	var la := InputEventKey.new()
	la.keycode = KEY_ALT
	la.location = KEY_LOCATION_LEFT
	la.pressed = true
	w.hud._input(la)
	for i in 3:
		await process_frame
	ok(w.hud._details.is_visible_in_tree(), "Links Alt klappt die Details auf")
	ok(w.hud._status.text.contains("vc") and w.hud._status.text.contains("Tür"), "Details zeigen den Rest")
	ok(w.hud._detail_job.text != "" and not w.hud._detail_job.text.contains("Werkstattkasse"), "Auftrag ohne Kasse")
	ok(w.hud._dro_panel.size.y > small, "Anzeige wächst beim Aufklappen")
	la.pressed = false
	w.hud._input(la)
	for i in 3:
		await process_frame
	ok(not w.hud._details.is_visible_in_tree(), "Loslassen klappt zu")
	ok(absf(w.hud._dro_panel.size.y - small) < 1.0, "Anzeige schrumpft wieder")
	# Rechts Alt schaltet die Übersicht
	var ra := InputEventKey.new()
	ra.keycode = KEY_ALT
	ra.location = KEY_LOCATION_RIGHT
	ra.pressed = true
	w.hud._input(ra)
	await process_frame
	ok(w.hud._overlay.visible and not w.hud._chip.visible, "Rechts Alt öffnet die Übersicht")
	var tabs: TabContainer = w.hud._overlay.tabs
	var titles := []
	for i in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	for t in ["Verfahren", "Spindel", "Werkzeug", "Ansicht", "Sonstiges", "Bedienpult"]:
		ok(titles.has(t), "Tab " + t)
	ok(tabs.get_tab_control(0) is GridContainer and tabs.get_tab_control(0).columns == 2, "Tasten und Wirkung nebeneinander")
	tabs.current_tab = titles.find("Bedienpult")
	await process_frame
	ok(w.hud._panel.is_visible_in_tree(), "Bedienpult im Tab erreichbar")
	var ov: Rect2 = w.hud._overlay.get_global_rect()
	ok(ov.position.y >= 0.0 and ov.end.x <= root.get_visible_rect().size.x, "Übersicht passt ins Bild")
	ra.echo = true
	w.hud._input(ra)
	ok(w.hud._overlay.visible, "Gehaltene Taste wiederholt nicht")
	ra.echo = false
	ra.pressed = false
	w.hud._input(ra)
	ok(w.hud._overlay.visible, "Loslassen lässt sie offen")
	ra.pressed = true
	w.hud._input(ra)
	ok(not w.hud._overlay.visible and w.hud._chip.visible, "Rechts Alt schließt sie wieder")
	w.hud._input(ra)
	ok(w.hud._overlay.visible, "Zum Verlassen offen lassen")
	la.pressed = true
	cnc.stop_operating()
	await process_frame
	ok(not w.hud._overlay.visible, "Verlassen schließt die Übersicht")
	w.hud._input(la)
	ok(not w.hud._details.visible, "Links Alt wirkt beim Gehen nicht")
	w.hud._input(ra)
	await process_frame
	ok(w.hud._overlay.visible and w.hud._overlay.tabs.get_tab_count() == 1, "Beim Gehen nur der Tab Bewegung")
	w.hud._input(ra)
	ok(w.hud._job_panel.visible, "Kassenfeld beim Gehen sichtbar")
	cnc.interact(w.player)
	for i in 3:
		await process_frame
	cnc.stop_operating()
	await process_frame
	ok(not w.hud._panel.is_visible_in_tree(), "Pult nach Verlassen aus")
	# E auf das Bedienpult: direkt in die Pultansicht, Dreh-Anzeigen aus
	var pt: Node = null
	for ch in cnc.get_children():
		if ch.has_method("interact") and ch.has_method("get_prompt") and not ch.has_method("click"):
			pt = ch
	ok(pt != null, "Bedienpult hat ein eigenes Interaktionsziel")
	pt.interact(w.player)
	for i in 3:
		await process_frame
	ok(cnc.operating and cnc.in_panel_view(), "E aufs Pult öffnet die Pultansicht")
	ok(not w.hud._profile.visible and not w.hud._dro_panel.visible, "Dreh-UI in der Pultansicht ausgeblendet")
	ok(w.hud._overlay.tabs.get_tab_title(0) == "Pult" and w.hud._overlay.tabs.get_tab_count() == 1, "Pultansicht hat eigene Tastenliste")
	cnc.toggle_panel_view()
	for i in 3:
		await process_frame
	ok(w.hud._profile.visible and w.hud._dro_panel.visible, "zurück an der Maschine: Dreh-UI wieder da")
	ok(w.hud._overlay.tabs.get_tab_count() == 6, "zurück an der Maschine: alle Tabs wieder da")
	cnc.stop_operating()
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
