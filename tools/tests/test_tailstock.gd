extends SceneTree
## Headless-Prüfung: Reitstock der E50 aus dem Modell - Station mit [E], Verschieben (A/D), Pinole
## mit dem Mausrad (großes Handrad dreht mit), Klemmhebel mit der Leertaste, Endlagen.
## Aufruf: godot --headless --path . -s res://tools/tests/test_tailstock.gd

var checks := 0
var fails := 0


class FakePlayer extends Node3D:
	var op: Node = null

	func start_operating(m: Node, _pos: Vector3, _yaw: float) -> void:
		op = m

	func stop_operating() -> void:
		op = null


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


func _initialize() -> void:
	await process_frame
	var l = load("res://scripts/machine/lathe.gd").new()
	root.add_child(l)
	await process_frame
	ok(l.e50, "E50-Modell geladen")
	ok(l.has_tailstock(), "Reitstock kommt aus dem Modell")
	if not l.has_tailstock():
		_done()
		return
	var ts: Dictionary = l._ts
	ok(ts.has("quill") and ts.has("crank") and ts.has("lever"), "Pinole, Handrad und Klemmhebel sind eigene Knoten")
	ok(l.find_child("Klemmhebel", true, false) != null, "Klemmhebel aus dem Reitstockkörper gelöst")
	ok(l.find_child("live_center", true, false) != null and (ts["quill"] as Node).find_child("live_center", true, false) != null,
		"Mitlaufende Spitze steckt in der Pinole")
	var box: AABB = l.tailstock_box()
	ok(box.size.x > 0.1 and box.position.x > 0.3, "Reitstock steht rechts vom Futter (%s)" % box)
	ok(absf(box.get_center().z) < 0.3 and box.position.y < l.AXIS_H and box.end.y > l.AXIS_H, "Reitstock sitzt auf Spitzenhöhe")
	ok(float(ts["tip_x"]) < box.position.x + 0.05 and float(ts["tip_x"]) > 0.0, "Spitze zeigt zum Futter")

	# --- Blick auf den Reitstock lenkt [E] auf ihn (Tür offen)
	var c: Vector3 = l.to_global(box.get_center())
	var eye: Vector3 = c + Vector3(0, 0.3, 1.5)
	ok(l.focus_for(eye, (c - eye).normalized()) == l._ts_target, "Blick auf den Reitstock -> Reitstock-Ziel")
	var away: Vector3 = l.to_global(Vector3(-0.8, l.AXIS_H, 0))
	ok(l.focus_for(eye, (away - eye).normalized()) != l._ts_target, "Blick daneben -> nicht der Reitstock")

	# --- Station
	var p := FakePlayer.new()
	root.add_child(p)
	l._ts_target.interact(p)
	ok(l.ts_mode and p.op == l, "[E] öffnet die Reitstock-Station")
	ok(l.station_prompt().contains("Pinole"), "Hinweiszeile zeigt die Tasten")

	# Pinole: Mausrad aus, Handrad dreht mit
	var q: Node3D = ts["quill"]
	var cr: Node3D = ts["crank"]
	for i in 10:
		l.move_quill(l.TS_QUILL_STEP)
	ok(is_equal_approx(l.ts_ext, 10 * l.TS_QUILL_STEP), "10 Rasten = %.0f mm Pinole" % (l.ts_ext * 1000.0))
	for i in 60:
		l._step_tailstock(0.05)
	ok(is_equal_approx(q.position.x, -l.ts_ext), "Pinole fährt sichtbar aus (zum Futter)")
	ok(absf(cr.rotation.x) > 1.0, "Großes Handrad dreht sich mit")
	for i in 200:
		l.move_quill(l.TS_QUILL_STEP)
	ok(l.ts_ext <= l.TS_QUILL_TRAVEL + 0.0001, "Pinolenhub begrenzt")
	for i in 200:
		l.move_quill(-l.TS_QUILL_STEP)
	ok(l.ts_ext == 0.0, "Pinole ganz eingefahren")

	# Klemmhebel: Leertaste zieht ihn nach hinten, geklemmt lässt sich nichts verschieben
	var lv: Node3D = ts["lever"]
	var ev := InputEventAction.new()
	ev.action = "jump"
	ev.pressed = true
	l._ts_input(ev)
	ok(l.ts_brake, "Leertaste klemmt den Reitstock")
	for i in 30:
		l._step_tailstock(0.05)
	ok(is_equal_approx(lv.rotation.z, l.TS_BRAKE_ANGLE), "Klemmhebel steht hinten")
	var off0: float = l.ts_off
	l.move_tailstock(-0.1)
	ok(l.ts_off == off0, "Geklemmt bleibt der Reitstock stehen")
	l._ts_input(ev)
	ok(not l.ts_brake, "Leertaste löst wieder")
	for i in 30:
		l._step_tailstock(0.05)
	ok(is_equal_approx(lv.rotation.z, 0.0), "Klemmhebel wieder vorne")

	# Verschieben: Richtung Futter bis an Werkstück / Bettschlitten, nach rechts bis ans Bettende
	l.move_tailstock(-0.05)
	ok(is_equal_approx(l.ts_off, off0 - 0.05), "Gelöst verschiebt A den Reitstock zum Futter")
	l._step_tailstock(0.016)
	ok(is_equal_approx(l.tailstock.position.x, l.ts_off), "Reitstock-Knoten folgt")
	for i in 100:
		l.move_tailstock(-0.05)
	var stop: float = l._carriage_stop()
	ok(stop > -INF, "Bettschlitten liegt in der Bahn des Reitstocks")
	ok(l.ts_off >= stop - 0.0001, "Nicht in den Bettschlitten")
	var saddle := l.find_child("z_axis", true, false) as MeshInstance3D
	var sb: AABB = (l.global_transform.affine_inverse() * saddle.global_transform) * saddle.get_aabb()
	ok(l.tailstock_box().position.x < sb.end.x - 0.05, "Pinolengehäuse fährt über den Bettschlitten (%.0f mm)" % ((sb.end.x - l.tailstock_box().position.x) * 1000.0))
	var gap: float = l.ts_off - stop
	ok(gap < 0.01 or l._ts_tip(l.ts_off, l.ts_ext) <= l._ts_tip_min() + 0.001, "Reitstock steht dicht am Schlitten (%.1f mm)" % (gap * 1000.0))
	for i in 200:
		l.move_quill(l.TS_QUILL_STEP)
	ok(is_equal_approx(l._ts_tip(l.ts_off, l.ts_ext), l._ts_tip_min()) or is_equal_approx(l.ts_ext, l.TS_QUILL_TRAVEL),
		"Pinole fährt bis ans Werkstück (oder Hubende), nicht nur bis zum Schlitten")
	for i in 200:
		l.move_quill(-l.TS_QUILL_STEP)
	ok(l._ts_tip(l.ts_off, l.ts_ext) >= l._ts_tip_min() - 0.001, "Spitze nicht im Werkstück")
	for i in 100:
		l.move_tailstock(0.05)
	ok(l.ts_off <= l._ts_off_max() + 0.0001, "Rechts endet das Bett")

	# Zurück
	var e := InputEventAction.new()
	e.action = "interact"
	e.pressed = true
	l._ts_input(e)
	ok(not l.ts_mode and p.op == null, "[E] verlässt die Station")
	_done()


func _done() -> void:
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
