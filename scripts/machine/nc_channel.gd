class_name NcChannel
extends RefCounted
## NC-Kanal der Zyklensteuerung: arbeitet ein Programm (siehe NcCam) an der Maschine ab.
## Ablauf je Abspansatz: Werkzeugwechsel (Wechselpunkt anfahren, Spindel aus, einschwenken),
## Spindel mit konstanter Schnittgeschwindigkeit ein, KSS, dann die Bahn. Die Bahn wird erst
## berechnet, wenn der Satz drankommt - mit dem Material, das dann wirklich da ist.
## Zustände: idle (Reset), run, hold (NC-Stopp / Tür auf), done, error (Alarm).

const OVR_MAX := 1.2

var lathe: Lathe
var state := "idle"
var prog: Dictionary = {}
var block := -1                  # aktueller Satz (Index in prog.blocks)
var override := 1.0              # Vorschub-Override 0 .. 1,2
var alarm := ""
var hold_reason := ""
var moves: Array = []            # Bahn des aktuellen Satzes (für die Anzeige)
var poly := PackedVector2Array() # Kontur des aktuellen Satzes
var move_i := 0                  # nächster Zug in moves
var run_time := 0.0
var _ops: Array = []
var _feed := 0.1                 # mm/U des aktuellen Satzes


func _init(l: Lathe) -> void:
	lathe = l


func busy() -> bool:
	return state == "run" or state == "hold"


func state_text() -> String:
	match state:
		"run":
			return "läuft"
		"hold":
			return "angehalten (%s)" % hold_reason
		"done":
			return "beendet"
		"error":
			return "Alarm"
	return "Reset"


## NC-Start: angewähltes Programm starten bzw. nach NC-Stopp fortsetzen.
func nc_start(p: Dictionary) -> bool:
	if lathe.estop:
		return _refuse("Not-Halt aktiv - erst quittieren.")
	if not lathe.door_closed():
		return _refuse("Schutztür offen - Zyklusstart nur bei geschlossener Tür.")
	if not lathe.guard_closed():
		return _refuse("Futterschutz offen - Zyklusstart nur bei geschlossenem Futterschutz.")
	if state == "hold":
		state = "run"
		hold_reason = ""
		lathe._info("NC-Start: Programm wird fortgesetzt.")
		return true
	if state == "run":
		return true
	if p.is_empty():
		return _refuse("Kein Programm angewählt (Programm-Manager: Anwählen).")
	if lathe.is_indexing():
		return _refuse("Werkzeugwechsel läuft noch.")
	var sim := NcCam.simulate(p, lathe)
	if not sim["errs"].is_empty():
		return _refuse(str(sim["errs"][0]))
	prog = p.duplicate(true)
	_ops.clear()
	var hd := NcCam.head(prog)
	var blocks: Array = prog["blocks"]
	for bi in blocks.size():
		var b: Dictionary = blocks[bi]
		if not NcCam.is_machining(b):
			continue
		_ops.append({"op": "blk", "i": bi})
		_ops.append({"op": "tool", "id": str(b["t"])})
		_ops.append({"op": "spin", "v": float(b["v"]), "smax": float(hd["smax"]), "f": float(b["f"])})
		_ops.append({"op": "kss", "on": int(hd["kss"]) == 1})
		_ops.append({"op": "plan", "i": bi})
	if _ops.is_empty():
		return _refuse("Programm enthält keinen Abspansatz.")
	_ops.append({"op": "end"})
	state = "run"
	alarm = ""
	hold_reason = ""
	block = -1
	moves = []
	poly = PackedVector2Array()
	run_time = 0.0
	lathe.auto_feed = false
	lathe.auto_feed_x = false
	lathe._info("NC-Start: %s" % prog["name"])
	return true


func nc_stop(reason := "NC-Stopp") -> void:
	if state == "run":
		state = "hold"
		hold_reason = reason


func reset() -> void:
	if busy() or state == "error":
		lathe.spindle_on = false
		lathe.coolant = false
	state = "idle"
	_ops.clear()
	block = -1
	moves = []
	poly = PackedVector2Array()
	alarm = ""
	hold_reason = ""


func set_override(v: float) -> void:
	override = clampf(snappedf(v, 0.01), 0.0, OVR_MAX)


func _refuse(text: String) -> bool:
	lathe._warn(text)
	return false


func _fail(text: String) -> void:
	state = "error"
	alarm = text
	_ops.clear()
	lathe.spindle_on = false
	lathe.message.emit("Alarm: " + text, Color(1, 0.3, 0.25))


# ======================================================================= Ablauf

func step(delta: float) -> void:
	if not busy():
		return
	if lathe.estop:
		_fail("Not-Halt - Programm abgebrochen.")
		return
	if not lathe.door_closed() or not lathe.guard_closed():
		if state == "run":
			state = "hold"
			hold_reason = "Schutztür offen" if not lathe.door_closed() else "Futterschutz offen"
			lathe._warn("%s - Vorschub und Spindel gestoppt." % hold_reason)
		lathe.spindle_on = false
		return
	if state != "run":
		return
	run_time += delta
	var t_left := delta
	var guard := 0
	while t_left > 0.0 and state == "run" and not _ops.is_empty() and guard < 400:
		guard += 1
		var op: Dictionary = _ops[0]
		match str(op["op"]):
			"blk":
				block = int(op["i"])
				_ops.pop_front()
			"tool":
				_ops.pop_front()
				if str(lathe.tool()["id"]) != str(op["id"]):
					var chg: Array = _wp_moves()
					chg.append({"op": "chg", "id": op["id"]})
					_ops = chg + _ops
			"chg":
				if lathe.spindle_on:
					lathe.spindle_on = false
				if lathe.spindle_speed > 5.0 or lathe.is_indexing():
					return
				if str(lathe.tool()["id"]) == str(op["id"]):
					_ops.pop_front()
					continue
				var slot: int = lathe.holder.find(str(op["id"]))
				if slot < 0:
					_fail("%s ist nicht im Werkzeughalter bestückt." % op["id"])
					return
				lathe.nc_internal = true
				var ok := lathe.index_slot(slot)
				lathe.nc_internal = false
				if not ok:
					_fail("Werkzeugwechsel auf %s nicht möglich (siehe Meldung)." % op["id"])
					return
				return
			"spin":
				_feed = float(op["f"])
				lathe.set_feed(_feed)
				lathe.set_vc(float(op["v"]))
				lathe.set_rpm_limit(float(op["smax"]))
				lathe.css = true
				lathe.spindle_on = true
				_ops.pop_front()
			"kss":
				lathe.coolant = bool(op["on"])
				if bool(op["on"]) and not lathe.coolant and lathe.kss != null:
					_fail("KSS-Tank leer – nachfüllen")
					return
				_ops.pop_front()
			"plan":
				_ops.pop_front()
				var b: Dictionary = prog["blocks"][int(op["i"])]
				var t := lathe.tool()
				var r := NcCam.plan(b, prog, t, {"prof": lathe.profile, "pos": Vector2(lathe.tool_z, lathe.tool_x), "zlim": lathe.z_min(), "zoff": lathe.wcs_z})
				if r.has("err"):
					_fail("Satz %d: %s" % [int(op["i"]) + 1, r["err"]])
					return
				moves = r["moves"]
				poly = r.get("poly", PackedVector2Array())
				move_i = 0
				var mv_ops: Array = []
				var fin := bool(r.get("finish", false))
				var fin_from := int(r.get("fin_from", -1))   # Komplett: ab hier Schlichtzüge
				for k in moves.size():
					var m: Array = moves[k]
					mv_ops.append({"op": "mv", "z": m[0], "x": m[1], "r": m[2], "p": true,
						"fin": fin or (fin_from >= 0 and k >= fin_from)})
				_ops = mv_ops + _ops
			"mv":
				t_left = _do_move(op, t_left)
			"end":
				_ops.pop_front()
				var back: Array = _wp_moves()
				back.append({"op": "fin"})
				_ops = back + _ops
			"fin":
				_ops.pop_front()
				lathe.spindle_on = false
				lathe.coolant = false
				state = "done"
				block = -1
				@warning_ignore("integer_division")
				lathe._info("Programm %s beendet (%d:%02d min)." % [prog["name"], int(run_time) / 60, int(run_time) % 60])


## Eilgang zum Werkzeugwechselpunkt: erst X hoch, dann Z, dann X.
func _wp_moves() -> Array:
	var hd := NcCam.head(prog)
	var xw := float(hd["xt"]) * 0.5
	var zw := float(hd["zt"]) + lathe.wcs_z
	var out: Array = []
	var x_up := maxf(lathe.tool_x, xw)
	if x_up > lathe.tool_x + 0.001:
		out.append({"op": "mv", "z": lathe.tool_z, "x": x_up, "r": true})
	out.append({"op": "mv", "z": zw, "x": x_up, "r": true})
	out.append({"op": "mv", "z": zw, "x": xw, "r": true})
	return out


## Einen Zug abarbeiten; gibt die übrige Zeit dieses Bildes zurück.
func _do_move(op: Dictionary, t_left: float) -> float:
	var rapid := bool(op["r"])
	var spd := 0.0
	var spd_cmd := 0.0
	if rapid:
		spd = NcCam.RAPID * minf(override, 1.0)
	else:
		if not lathe.spindle_on:
			lathe.spindle_on = true       # nach NC-Stopp / Tür: Spindel wieder hochlaufen lassen
		if lathe.spindle_speed < lathe.rpm() * 0.9:
			return 0.0
		spd = _feed * lathe.spindle_speed / 60.0 * override
		spd_cmd = spd
		spd *= lathe.kss_speed()      # KSS OPTIMAL: Satz läuft schneller durch, Vorschub je Umdrehung bleibt
	if spd <= 0.0:
		return 0.0
	var pos := Vector2(lathe.tool_z, lathe.tool_x)
	var tgt := Vector2(float(op["z"]), float(op["x"]))
	var d := tgt - pos
	var dist := d.length()
	if dist < 0.0005:
		_next_move()
		return t_left
	var travel := minf(dist, spd * t_left)
	var dv := d / dist * travel
	lathe.nc_finish = bool(op.get("fin", false))
	lathe.move_tool(dv.x, dv.y, rapid, spd_cmd if not rapid else -1.0)
	lathe.nc_finish = false
	if lathe.estop:
		_fail("Kollision - Programm abgebrochen.")
		return 0.0
	var moved := Vector2(lathe.tool_z, lathe.tool_x) - pos
	if moved.length() < travel * 0.5 - 0.001:
		_fail("Bewegung blockiert bei X Ø%.3f Z%.3f (siehe Meldung)." % [lathe.tool_x * 2.0, lathe.tool_z - lathe.wcs_z])
		return 0.0
	if travel >= dist - 0.00001:
		lathe.tool_z = tgt.x
		lathe.tool_x = tgt.y
		_next_move()
	return t_left - travel / spd


func _next_move() -> void:
	var op: Dictionary = _ops.pop_front()
	if op.get("p", false):
		move_i += 1


## Restweg des aktuellen Zugs (Z, X), für die Anzeige.
func remaining() -> Vector2:
	if not busy() or _ops.is_empty() or str(_ops[0]["op"]) != "mv":
		return Vector2.ZERO
	return Vector2(float(_ops[0]["z"]) - lathe.tool_z, float(_ops[0]["x"]) - lathe.tool_x)
