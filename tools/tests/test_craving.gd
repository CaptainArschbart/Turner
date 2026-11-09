extends SceneTree
## Sucht-Meter: sinkt mit der Zeit, Rauchen füllt es, bei null Entzug mit Nachteilen, wird gespeichert.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	root.push_input(ev)


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var cig = p.cigarette
	var hud = w.hud
	ok(cig.need > 0.99 and not cig.craving, "Zu Beginn ist das Meter voll")
	ok(hud.cigarette == cig and hud._gauge.visible, "Sucht-Meter im HUD sichtbar")
	ok(hud._gauge.get_global_rect().size.x > 50.0, "Meter hat eine Größe")

	# ---------------------------------------------------- Sinkt mit der Zeit
	var start: float = cig.need
	for i in 30:
		await process_frame
	ok(cig.need < start, "Ohne Zigarette sinkt das Meter")
	cig._process(cig.NEED_TIME * 0.5)
	ok(absf(cig.need - (start - 0.5)) < 0.02, "Nach halber Haltezeit halb leer")
	await process_frame
	ok(absf(hud._gauge.value - cig.need) < 0.01, "Zeiger folgt dem Wert")
	var low_angle: float = hud._gauge.needle_angle()

	# ---------------------------------------------------- Rauchen füllt auf
	press("smoke")
	await process_frame
	ok(cig.lit, "Angezündet")
	var before: float = cig.need
	for i in 20:
		cig._process(1.0)
	ok(cig.need > before, "Beim Rauchen steigt das Meter")
	cig.left = 0.6
	cig.need = 0.1
	for i in 300:
		cig._process(1.0)
		if not cig.lit:
			break
	ok(not cig.lit and cig.need > 0.9, "Eine Zigarette füllt das Meter fast ganz")
	for i in 30:
		await process_frame
	ok(hud._gauge.needle_angle() > low_angle, "Zeiger steht nach dem Rauchen weiter rechts")

	# ---------------------------------------------------- Bei null: Entzug
	var speed_normal := 0.0
	cig.need = 0.25
	cig._process(cig.NEED_TIME * 0.1)
	ok(w.hud._msg.text.contains("bald"), "Warnung, wenn das Meter knapp wird")
	cig._process(cig.NEED_TIME)
	ok(cig.need == 0.0 and cig.craving, "Leeres Meter: Entzug")
	ok(w.hud._msg.text.contains("Entzug"), "Hinweis auf den Entzug")
	ok(cig.work_factor() < 0.7, "Im Entzug wird langsamer gearbeitet")
	# Gehen ist im Entzug langsamer
	var home: Vector3 = p.global_position
	Input.action_press("move_forward")
	for i in 40:
		await physics_frame
	var slow := Vector2(p.velocity.x, p.velocity.z).length()
	ok(slow > 0.5 and slow < p.WALK * 0.7, "Im Entzug geht die Figur langsamer (%.2f m/s)" % slow)
	ok(absf(p.head.rotation.z) > 0.0 or absf(p.head.rotation.x - p.pitch) > 0.0, "Der Blick zittert")
	Input.action_release("move_forward")
	for i in 120:
		await process_frame
	ok(hud._withdrawal.visible and hud._withdrawal_amt > 0.2, "Bildrand verschwimmt im Entzug")
	ok(hud._gauge.craving, "Meter zeigt Entzug")

	# ---------------------------------------------------- Rauchen beendet den Entzug
	press("smoke")
	await process_frame
	ok(cig.lit and not cig.craving and cig.work_factor() == 1.0, "Anzünden beendet den Entzug")
	p.global_position = home
	Input.action_press("move_forward")
	for i in 40:
		await physics_frame
	speed_normal = Vector2(p.velocity.x, p.velocity.z).length()
	ok(speed_normal > p.WALK * 0.9, "Danach wieder normales Tempo (%.2f m/s)" % speed_normal)
	Input.action_release("move_forward")

	# ---------------------------------------------------- Spielstand
	press("smoke")
	await process_frame
	cig.need = 0.37
	var st: Dictionary = JSON.parse_string(JSON.stringify(p.get_state()))
	ok(absf(float(st["cigarette"]["need"]) - 0.37) < 0.001, "Meter im Spielstand")
	cig.need = 1.0
	p.set_state(st)
	ok(absf(cig.need - 0.37) < 0.001 and not cig.craving, "Meter aus dem Spielstand geladen")
	st["cigarette"]["need"] = 0.0
	p.set_state(st)
	ok(cig.craving, "Leeres Meter im Spielstand: weiter im Entzug")
	st["cigarette"].erase("need")
	p.set_state(st)
	ok(cig.need == 1.0 and not cig.craving, "Alter Spielstand ohne Meter: voll")
	print("CHECKS ", checks, " FAILS ", fails)
	quit(1 if fails > 0 else 0)
