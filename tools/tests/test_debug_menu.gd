extends SceneTree
## Debug-Menü auf ^: öffnen und schließen, Testmodus, Noclip, Uhrzeit, Zeitraffer, Geld, Ansehen, Skillpunkte, Springen.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 250, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var d = w.debug_menu
	var caret := InputEventKey.new()
	caret.physical_keycode = KEY_QUOTELEFT
	caret.pressed = true

	# Öffnen und schließen
	w._input(caret)
	ok(d.visible and p.operating == d, "^ öffnet das Menü, die Figur steht still")
	w._input(caret)
	ok(not d.visible and p.operating == null, "^ schließt es wieder")
	d.open()
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	d._input(esc)
	ok(not d.visible, "Esc schließt das Menü")
	d.open()

	# Testmodus und Noclip
	(d._toggles["free"] as Button).pressed.emit()
	ok(w.free_mode, "Testmodus an")
	(d._toggles["free"] as Button).pressed.emit()
	ok(not w.free_mode, "Testmodus aus")
	(d._toggles["noclip"] as Button).pressed.emit()
	ok(p.noclip, "Noclip an")
	d.close()
	var y0: float = p.global_position.y
	for i in 10:
		await physics_frame
	ok(absf(p.global_position.y - y0) < 0.01, "Im Noclip fällt die Figur nicht")
	p.global_position = Vector3(0, 3.0, 0)
	for i in 10:
		await physics_frame
	ok(p.global_position.y > 2.9, "Im Noclip schwebt sie in der Luft")
	# Menü öffnen, während die Figur in der Luft schwebt: Sie fällt nicht herunter
	d.open()
	for i in 10:
		await physics_frame
	ok(p.noclip and p.global_position.y > 2.9, "Noclip bleibt im offenen Menü an, die Figur schwebt weiter")
	d.close()
	ok(p.noclip, "Noclip bleibt nach dem Schließen an")
	ok(w.hud.get("_free") == null, "Kein Testmodus-Hinweis mehr im Bild")
	p.noclip = false
	p.global_position = Vector3(0, 0.1, 4)

	# Uhrzeit setzen: Tag und Nacht
	w.debug_set_hour(12.0)
	ok(w.day_started and not w.day_over and absf(w.sky_hour() - 12.0) < 0.01, "12 Uhr: Arbeitstag läuft")
	ok(w.clock_text().contains("12:00"), "Uhr zeigt 12:00: " + w.clock_text())
	w.debug_set_hour(22.0)
	ok(w.day_over and absf(w.sky_hour() - 22.0) < 0.01, "22 Uhr: Feierabend, Nacht")
	w.debug_set_hour(4.0)
	ok(w.day_over and absf(w.sky_hour() - 28.0) < 0.01 and w.clock_text().contains("04:00"), "4 Uhr morgens: " + w.clock_text())
	w.debug_set_hour(9.0)
	ok(not w.day_over and absf(w.sky_hour() - 9.0) < 0.01, "Zurück auf 9 Uhr")

	# Zeitraffer
	w.time_scale = 10.0
	var t0: float = w.day_time
	w._advance_day(1.0 * w.time_scale)
	ok(absf(w.day_time - t0 - 10.0) < 0.01, "Zeitraffer ×10")
	w.time_scale = 1.0

	# Geld, Ansehen, Skillpunkte
	d._set_money(int(w.company.balance) + 1000)
	ok(int(w.money) == 1250, "+1000 EUR")
	d._set_money(0)
	ok(int(w.money) == 0, "Geld auf 0")
	d._set_money(250)
	ok(int(w.money) == 250, "Startgeld")
	var rep: float = w.company.reputation
	d._reputation(10.0)
	ok(w.company.reputation > rep, "Ansehen steigt")
	var pts: int = w.company.skills.free_points()
	d._skill_point()
	ok(w.company.skills.free_points() == pts + 1, "Ein Skillpunkt mehr")

	# Springen
	d.open()
	d._teleport("Lager")
	ok(not d.visible and p.global_position.distance_to(DebugMenu.PLACES["Lager"][0]) < 0.01, "Sprung ins Lager, Menü zu")

	# Anzeige im Menü läuft ohne Fehler
	d.open()
	d._refresh()
	ok(d._status.text.contains("EUR") and d._status.text.contains("Ansehen"), "Statuszeile: " + d._status.text)
	d.close()

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
