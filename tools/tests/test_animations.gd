extends SceneTree
## Bewegungen mit Schwung: Kranlast pendelt beim Anfahren und Bremsen nach, die Bürotür schwingt in die
## Endlage, das Rolltor fährt weich an und bremst ab, der Aufbau des Gabelstaplers nickt und wankt.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 5000, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var c = w.crane
	w.start_day()
	const DT := 1.0 / 60.0

	# ---------------------------------------------------- Kran: Last pendelt nach
	c.bridge_x = -6.0
	c.trolley_z = -1.5
	c.hook_y = 2.0
	await frames(3)
	ok(c._sway == Vector2.ZERO, "Steht der Kran, hängt der Haken ruhig")
	p.global_position = Vector3(c.bridge_x + 0.5, 0.05, c.trolley_z + 1.5)
	await frames(2)
	c.grab(p)
	Input.action_press("crane_right")
	var lag := 0.0
	for i in 45:
		await physics_frame
		lag = minf(lag, c._sway.x)
	ok(lag < -0.02, "Beim Anfahren nach Osten bleibt die Last zurück (%.3f m)" % lag)
	var shown: Vector3 = c._hook.global_position
	ok(absf(shown.x - (c.bridge_x + c._sway.x)) < 0.002 and shown.y >= c.hook_y - 0.0001,
		"Haken hängt um die Auslenkung versetzt unter der Katze")
	ok(absf(c.hook_pos().x - c.bridge_x) < 0.0001, "Eingehängt wird weiter senkrecht unter der Katze")
	Input.action_release("crane_right")
	var ahead := 0.0
	var worst := 0.0
	for i in 120:
		await physics_frame
		ahead = maxf(ahead, c._sway.x)
		worst = maxf(worst, c._sway.length())
	ok(ahead > 0.02, "Beim Bremsen schwingt die Last nach vorn durch (%.3f m)" % ahead)
	ok(worst <= c._rope_len() * c.SWAY_MAX + 0.001, "Der Ausschlag bleibt begrenzt (%.3f m bei %.1f m Seil)" % [worst, c._rope_len()])
	await frames(900)
	ok(c._sway.length() < 0.005, "Das Pendeln klingt ab (%.4f m)" % c._sway.length())
	# Langes Seil pendelt langsamer als kurzes
	var period := {}
	for y in [4.2, 1.0]:
		c.hook_y = y
		c._sway = Vector2(0.05, 0)
		c._sway_v = Vector2.ZERO
		var t := 0
		var crossed := 0
		var last: float = c._sway.x
		while crossed < 2 and t < 1200:
			await physics_frame
			t += 1
			if signf(c._sway.x) != signf(last) and absf(c._sway.x) > 0.00001:
				crossed += 1
				last = c._sway.x
		period[y] = t
	ok(int(period[1.0]) > int(period[4.2]) + 10, "Tief hängend pendelt die Last langsamer (%d gegen %d Schritte)" % [period[1.0], period[4.2]])
	c.release()
	c._sway = Vector2.ZERO
	c._sway_v = Vector2.ZERO

	# ---------------------------------------------------- Bürotür schwingt
	var door = load("res://scripts/world/office_door.gd").new()
	w.add_child(door)
	door.position = Vector3(0, 0, 30)
	await process_frame
	door.set_process(false)              # hier von Hand in festen Schritten
	door.opened = true
	var angles: Array[float] = []
	for i in 90:
		door._process(DT)
		angles.append(door._leaf.rotation.y)
	var first := absf(angles[0])           # erster Schritt aus dem Stand
	var fastest := 0.0
	for i in range(1, angles.size()):
		fastest = maxf(fastest, absf(angles[i] - angles[i - 1]))
	ok(fastest > first * 2.5, "Die Tür nimmt Fahrt auf (erster Schritt %.4f, schnellster %.4f rad)" % [first, fastest])
	ok(absf(angles[-1] - door.OPEN_ANGLE) < 0.01, "Nach 1,5 s steht sie offen (%.3f rad)" % angles[-1])
	var past := 0.0
	for a in angles:
		past = minf(past, a - door.OPEN_ANGLE)
	ok(past < -0.002 and past > -0.07, "Sie federt am Anschlag kurz nach (%.3f rad darüber)" % -past)
	door.opened = false
	var closed_max := -INF
	for i in 120:
		door._process(DT)
		closed_max = maxf(closed_max, door._leaf.rotation.y)
	ok(absf(door._leaf.rotation.y) < 0.001 and closed_max <= 0.0, "Zu fällt sie in den Rahmen und schlägt nicht durch")
	door.queue_free()

	# ---------------------------------------------------- Rolltor fährt weich
	var gate = w.site.door_workshop
	gate.set_process(false)
	gate.set_open(false, true)
	gate.set_open(true)
	var steps: Array[float] = []
	var prev: float = gate.open_t
	var n := 0
	while not is_equal_approx(gate.open_t, 1.0) and n < 600:
		gate._process(DT)
		steps.append(gate.open_t - prev)
		prev = gate.open_t
		n += 1
	var top := 0.0
	for s in steps:
		top = maxf(top, s)
	ok(n < 600 and is_equal_approx(gate.open_t, 1.0), "Rolltor fährt ganz auf (%.1f s)" % (n * DT))
	ok(steps[0] < top * 0.2 and absf(top - gate.SPEED * DT) < 0.0005, "Es fährt weich an und erreicht seine Geschwindigkeit")
	ok(steps[-2] < top * 0.5, "Vor dem Ende bremst es ab")
	gate.toggle()
	gate._process(DT)
	ok(not gate._collision.disabled and gate.open_t > 0.99, "Beim Schließen ist es sofort wieder fest, auch im Anfahren")
	gate.set_open(false, true)
	gate.set_process(true)

	# ---------------------------------------------------- Gabelstapler federt
	var f = load("res://scripts/world/forklift.gd").new()
	f.world = null
	w.add_child(f)
	f.place(Vector2(30.0, 30.0), 0.0)
	f.set_physics_process(false)
	await physics_frame
	ok(f.parts.has("body"), "Stapler: Aufbau lässt sich neigen")
	var nose_up := 0.0
	for i in 40:
		f.drive(DT, 1.0, 0.0, 0.0)
		nose_up = maxf(nose_up, f._lean.x)
	ok(nose_up > 0.004, "Beim Anfahren hebt sich die Front (%.2f Grad)" % rad_to_deg(nose_up))
	for i in 240:
		f.drive(DT, 1.0, 0.0, 0.0)
	ok(absf(f._lean.x) < 0.002, "Bei gleichmäßiger Fahrt steht der Aufbau wieder gerade")
	var lean_side := 0.0
	for i in 60:
		f.drive(DT, 1.0, 1.0, 0.0)
		lean_side = maxf(lean_side, absf(f._lean.y))
	ok(lean_side > 0.003, "In der Kurve neigt er sich zur Seite (%.2f Grad)" % rad_to_deg(lean_side))
	var dive := 0.0
	for i in 60:
		f.drive(DT, 0.0, 0.0, 0.0)
		dive = minf(dive, f._lean.x)
	ok(dive < -0.004, "Beim Bremsen taucht die Front ein (%.2f Grad)" % rad_to_deg(-dive))
	for i in 300:
		f.drive(DT, 0.0, 0.0, 0.0)
	ok(f._lean.length() < 0.001 and absf((f.parts["body"] as Node3D).rotation.x) < 0.001, "Im Stand federt er aus")
	f.queue_free()

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
