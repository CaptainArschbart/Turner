extends SceneTree
## Rauchen: in der Halle, mit vollen Händen und an der Maschine.
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
	ok(InputMap.has_action("smoke") and root.get_node("Settings").binding_text("smoke") != "", "Taste zum Rauchen belegt")
	ok(not cig.lit, "Zu Beginn wird nicht geraucht")

	# ---------------------------------------------------- In der Halle
	press("smoke")
	await process_frame
	ok(cig.lit and cig._cigs[0]["root"].visible, "Taste zündet an, Zigarette vor der Kamera")
	ok(p.hands_free(), "Die Hände bleiben frei")
	ok(w.hud._msg.text.contains("angezündet") if w.hud.get("_msg") != null else true, "Hinweis angezeigt")
	var start: float = cig.left
	for i in 30:
		await process_frame
	ok(cig.left < start, "Sie brennt ab")
	ok(cig._wisp.emitting, "Rauch steigt auf")
	# Zug: Die Glut leuchtet auf, danach wird ausgeatmet
	cig._next_drag = 0.0
	cig._process(0.01)
	ok(cig.glow() >= 0.0 and cig._drag_t >= 0.0, "Zug beginnt")
	cig._process(0.6)
	ok(cig.lift() > 0.9 and float(p.body.get("smoke_hand")) > 0.9, "Beim Zug geht die Hand zum Mund")
	cig._process(cig.INHALE - 0.6)
	ok(cig.glow() > 0.9, "Glut leuchtet beim Zug")
	cig._process(cig.EXHALE_DELAY)
	ok(cig._puff.emitting, "Rauch wird ausgeatmet")
	# Selbst ziehen per Linksklick ins Leere: nur wenn gerade kein Zug läuft
	cig._process(cig.DRAG_END)
	var n: int = cig.drags
	ok(cig.take_drag() and cig._drag_t >= 0.0 and cig.drags == n + 1, "Linksklick nimmt einen Zug")
	ok(not cig.take_drag(), "Kein zweiter Zug, solange einer läuft")
	cig._process(cig.DRAG_END + 0.1)

	# ---------------------------------------------------- Außenansicht: im Mund der Figur
	p.third_person = true
	p._update_camera()
	cig._place()
	ok(cig._cigs[1]["root"].visible and not cig._cigs[0]["root"].visible, "Außenansicht: Zigarette im Mund")
	p.third_person = false
	p._update_camera()

	# ---------------------------------------------------- Beim Tragen
	p.set_carry({"kind": Materials.KIND_ROUND, "sawn": true, "material": "S235", "d": 60.0, "l": 160.0})
	ok(cig.lit, "Mit Material in den Händen wird weitergeraucht")
	p.clear_carry()

	# ---------------------------------------------------- An der Maschine
	var l = w.lathe
	l.interact(p)
	for i in 3:
		await process_frame
	ok(p.operating == l and cig.lit, "Beim Bedienen weiter am Rauchen")
	cig._place()
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var head: Node3D = p.body.get("_head")
	ok(not cig._cigs[0]["root"].visible and not cig._cigs[1]["root"].visible, "An der Maschine keine schwebende Zigarette")
	ok(cam != null and cig._wisp.global_position.distance_to(cam.global_position) > 0.3, "Rauch nicht vor der Maschinenkamera")
	ok(cig._wisp.global_position.distance_to(head.global_position) < 0.3, "Rauch steigt bei der Figur auf")
	press("smoke")
	await process_frame
	ok(not cig.lit, "An der Maschine ausgemacht")
	var butts := get_nodes_in_group("cig_butt")
	ok(butts.size() == 1, "Ein Stummel fällt heraus")
	for i in 120:
		await physics_frame
	if butts.size() == 1:
		var b: CigButt = butts[0]
		ok(b.resting and b.global_position.y < 0.05 and b.global_position.distance_to(p.global_position) < 1.5, "Stummel liegt neben der Figur am Boden")
	press("smoke")
	await process_frame
	ok(cig.lit, "An der Maschine angezündet")
	l.interact(p)

	# ---------------------------------------------------- Aufgeraucht und Spielstand
	var st: Dictionary = JSON.parse_string(JSON.stringify(p.get_state()))
	ok(bool(st["cigarette"]["lit"]), "Brennende Zigarette im Spielstand")
	cig.left = 0.001
	cig._process(1.0)
	ok(not cig.lit and not cig._cigs[0]["root"].visible, "Aufgeraucht: weg")
	p.set_state(st)
	ok(cig.lit, "Aus dem Spielstand wieder angezündet")
	print("CHECKS ", checks, " FAILS ", fails)
	quit(1 if fails > 0 else 0)
