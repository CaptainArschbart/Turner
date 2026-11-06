class_name RoundGrinder
extends Lathe
## Konventionelle Rundschleifmaschine. Technik wie die Drehmaschine: Das Werkstück dreht im Futter, der
## Schlitten trägt statt des Werkzeughalters einen Schleifkopf. Scheiben (siehe Wheels) kommen von der Werkbank.
## Neben dem Werkstück steht am Bett das Abziehwerkzeug: Anfahren zieht die Scheibe ab. Die Maschine spannt
## nur vorbearbeitete Teile. Grob abgetragen wird hier nicht: 0,05 mm je Durchgang.

const WHEEL_R := 0.15             # Scheibenradius (m)
const AP_MAX := 0.05              # größte Zustellung je Durchgang im Radius (mm)
const DRESS_Z := 800.0            # Abziehwerkzeug: Lage am Bett (mm ab Futter)
const DRESS_X := 60.0             # Spitze des Abziehdiamanten (mm Radius)
const F_REC := 0.15               # Richtwert Längsvorschub (mm/U)

var _wheel: Node3D
var _tools: Dictionary = {}       # Scheiben-id -> fertige Werkzeugdaten
var _at_dresser := false


func _init() -> void:
	MACHINE_ID = "round_grinder"
	grinder_type = "round"
	conventional = true
	use_glb = false
	holder = ["K30", "", "", ""]
	rpm_set = 250.0
	feed_set = 0.15


func _tool_for(id: String) -> Dictionary:
	if not _tools.has(id):
		var w := Wheels.by_id("round_grinder", id)
		var half := float(w["d"]) * 0.5
		_tools[id] = LatheTools._finalize({
			"id": w["id"], "sl": 3, "ext": 0.0, "name": w["name"], "short": "Scheibe", "desc": w["name"], "type": w["type"],
			"poly": PackedVector2Array([Vector2(0, 0), Vector2(half, 0), Vector2(half, 10), Vector2(-half, 10), Vector2(-half, 0)]),
			"nose": 0.5, "ref": "center", "max_dz": AP_MAX, "max_dx": AP_MAX, "feed_dir": -1, "color": Wheels.TYPES[w["type"]]["color"],
		})
	return _tools[id]


func tool() -> Dictionary:
	return _tool_for(str(holder[active_slot]) if has_cutter() else "K30")


## Die Scheibe sitzt immer am Platz 1, es wird nicht geschwenkt.
func index_slot(_slot: int, _silent := false) -> bool:
	return true


func select_tool(_i: int, _silent := false) -> void:
	pass


func holder_clash(_slots: Array, _active: int, _z: float, _x: float, _with_slot := false) -> String:
	return ""


func hand_prompt(held: Dictionary) -> String:
	if held.is_empty():
		return "" if not has_cutter() else "[Linksklick] %s abnehmen" % tool_label(str(holder[0]))
	if held["machine"] != MACHINE_ID:
		return "%s passt nicht auf diese Maschine" % held["name"]
	if not has_cutter():
		return "[Linksklick] %s aufziehen" % held["name"]
	return "[Linksklick] %s aufziehen, %s kommt in die Hand" % [held["name"], tool()["name"]]


func hand_click(p: Node) -> void:
	if spindle_speed > 5.0:
		_warn("Erst Spindel stoppen, dann Scheibe wechseln!")
		return
	var held: Dictionary = p.held
	if held.is_empty():
		if has_cutter():
			var out := str(holder[0])
			_set_wheel("")
			p.set_held(self, out)
		return
	if held["machine"] != MACHINE_ID:
		_warn("%s passt nicht auf diese Maschine." % held["name"])
		return
	var old := str(holder[0])
	_set_wheel(str(held["id"]))
	if old == "":
		p.clear_held()
	else:
		p.set_held(self, old)


func _set_wheel(id: String) -> void:
	holder[0] = id
	active_slot = 0
	_apply_holder()


func _apply_holder(announce := false, animate := false, keep_post := false) -> void:
	super._apply_holder(announce, animate, keep_post)
	if _wheel:
		_wheel.visible = has_cutter()
		if has_cutter():
			_paint_wheel()


func _paint_wheel() -> void:
	var w := Wheels.by_id("round_grinder", str(holder[0]))
	_wheel.scale.x = float(w["d"]) / 30.0
	(_wheel.get_child(0) as MeshInstance3D).material_override = Build.mat(Wheels.TYPES[w["type"]]["color"], 0.9)


func tool_name(id: String) -> String:
	return str(Wheels.by_id("round_grinder", id)["name"])


func tool_list() -> Array:
	return Wheels.list("round_grinder")


func make_tool_model(id: String) -> Node3D:
	return _bench_wheel(Wheels.by_id("round_grinder", id))


func make_bench_model(id: String) -> Node3D:
	return _bench_wheel(Wheels.by_id("round_grinder", id))


## Je Schleifmittel eine Reihe auf der Werkbank.
func bench_rows() -> Array:
	var rows := []
	for type_id in Wheels.TYPES:
		rows.append({"depth": 0.2, "flat": true, "tools": Wheels.list("round_grinder").filter(func(w): return w["type"] == type_id)})
	return rows


func _bench_wheel(w: Dictionary) -> Node3D:
	var n := Node3D.new()
	Build.cyl(n, WHEEL_R * 0.6, float(w["d"]) * 0.001, Vector3.ZERO, Build.mat(Wheels.TYPES[w["type"]]["color"], 0.9), Build.AXIS_Z, false, 40)
	return n


func _rpm_dial() -> Array:
	return [[40, 63, 80, 100, 125, 160, 200, 250], [50, 80, 100, 125, 160, 200, 250, 315]]


func _feed_dial() -> Array:
	return [[0.03, 0.05, 0.08, 0.1, 0.12, 0.15, 0.2, 0.25], [0.06, 0.1, 0.14, 0.18, 0.22, 0.28, 0.35, 0.5]]


func machine_title() -> String:
	return "Konventionelle Rundschleifmaschine"


## Schleifkopf statt Werkzeughalter: Der tiefste Punkt der Scheibe ist die Schneide. Dazu das Abziehwerkzeug.
func _build_extra() -> void:
	super._build_extra()
	var tip := _head_pos() - _post_pos(tool())
	var c := Vector3(tip.x, AXIS_H, tip.z + WHEEL_R)
	_wheel = Node3D.new()
	_wheel.position = c
	cross_slide.add_child(_wheel)
	Build.cyl(_wheel, WHEEL_R, 0.03, Vector3.ZERO, Build.mat(Color(0.72, 0.68, 0.6), 0.9), Build.AXIS_X, false, 64)
	Build.cyl(_wheel, 0.05, 0.038, Vector3.ZERO, Build.mat(Color(0.3, 0.32, 0.35), 0.4, 0.8), Build.AXIS_X, false, 32)
	Build.box(_wheel, Vector3(0.04, 0.04, 0.015), Vector3(0, 0.09, 0), Build.mat(Color(0.1, 0.1, 0.12), 0.7))
	# Haube über der Scheibe, Motor dahinter
	var cover := Build.mat(Color(0.72, 0.1, 0.08), 0.5)
	Build.box(cross_slide, Vector3(0.06, 0.05, WHEEL_R * 2.1), c + Vector3(0, WHEEL_R + 0.03, 0), cover)
	Build.box(cross_slide, Vector3(0.06, WHEEL_R + 0.02, 0.05), c + Vector3(0, WHEEL_R * 0.5, WHEEL_R + 0.03), cover)
	Build.box(cross_slide, Vector3(0.3, 0.14, 0.32), c + Vector3(0, -0.13, WHEEL_R - 0.04), Build.mat(Color(0.2, 0.32, 0.46), 0.5, 0.1))
	Build.cyl(cross_slide, 0.08, 0.24, c + Vector3(0.2, 0.0, WHEEL_R - 0.04), Build.mat(Color(0.12, 0.13, 0.15), 0.55, 0.2), Build.AXIS_X)
	# Abziehwerkzeug am Bett neben dem Werkstück: Halter und Diamantspitze bei DRESS_X
	var dark := Build.mat(Color(0.12, 0.13, 0.15), 0.55, 0.2)
	var dz := DRESS_Z * 0.001
	var tip_z := DRESS_X * 0.001
	Build.box(self, Vector3(0.05, AXIS_H - 0.93, 0.05), Vector3(dz, (AXIS_H + 0.93) * 0.5 - 0.02, tip_z - 0.05), dark)
	Build.cyl(self, 0.008, 0.05, Vector3(dz, AXIS_H, tip_z - 0.025), Build.mat(Color(0.9, 0.92, 0.95), 0.15, 0.4), Build.AXIS_Z, false, 12, 0.001)


func _process(delta: float) -> void:
	super._process(delta)
	if _wheel and spindle_on:
		_wheel.rotate_x(-40.0 * TAU * delta)


## Schritt mit Prüfung auf Abziehwerkzeug und Schleifmittel.
func _step_tool(sz: float, sx: float, rapid: bool, speed: float) -> bool:
	if has_cutter():
		var z := tool_z + sz
		var x := tool_x + sx
		var over := absf(z - DRESS_Z) <= float(tool()["zmax"]) + 3.0
		if over and x < DRESS_X - 0.05:
			_crash("KOLLISION! Scheibe zu tief in das Abziehwerkzeug gefahren - NOT-HALT!")
			return false
		_dress_check(over, x)
		if ceramic_part and has_part and not Wheels.cuts(str(tool()["type"]), true) and _engagement(z, x) > 0.0001:
			_crash("%s schneidet keine Keramik. Diamantscheibe aufziehen." % tool()["name"])
			return false
	return super._step_tool(sz, sx, rapid, speed)


func _dress_check(over: bool, x: float) -> void:
	var touching := over and x <= DRESS_X + 0.001
	if touching and not _at_dresser and spindle_speed > 30.0 and tool_stock != null:
		var id := str(holder[0])
		if Wheels.dress(tool_stock, id):
			_crash("SCHEIBE VERBRAUCHT! %s muss neu gekauft werden." % tool_name(id))
			tool_lost.emit(0, tool_name(id))
			_lose_tool()
		else:
			_info("Scheibe abgezogen: wieder gerade, %d %% Verschleiß." % int(tool_stock.wear(id) * 100.0))
	_at_dresser = touching


## Schleifen nutzt die Scheibe ab und macht sie unrund.
func _add_wear(delta: float) -> void:
	if tool_stock == null or not has_cutter():
		return
	var id := str(holder[0])
	if Wheels.use(tool_stock, id, str(tool()["type"]), material, ceramic_part, delta):
		_crash("SCHEIBE VERBRAUCHT! %s muss neu gekauft werden." % tool_name(id))
		tool_lost.emit(0, tool_name(id))
		_lose_tool()
	elif tool_stock.dull(id) >= 0.8:
		_warn("Die Scheibe wird unrund (%d %%): am Abziehwerkzeug abziehen." % int(tool_stock.dull(id) * 100.0))


## Rautiefe in µm: Längsvorschub und Zustellung, ohne Kühlung schlechter.
func _rz_for(_t: Dictionary, f: float, ap: float, _vc: float, kss: bool, manual: bool, _mat: Dictionary) -> Dictionary:
	var rz := 0.5 + 4.0 * f + 0.6 * clampf(ap / AP_MAX, 0.0, 1.0)
	rz *= 1.0 if kss else 1.4
	if tool_stock != null and has_cutter():
		rz *= Wheels.finish(str(_t["type"]), tool_stock.dull(str(_t["id"])))
	if manual:
		rz += 0.6
	var hint := "Vorschub hoch für feines Schleifen" if f > F_REC * 2.0 else ""
	return {"rz": rz, "hint": hint}


## Schleifprüfung: Alle Maße wie beim Drehen, dazu muss der geforderte Bereich fein genug sein.
func evaluate_grind(job: Dictionary) -> Dictionary:
	var res := evaluate(job)
	var g: Dictionary = job["grind"]
	var a := clampi(int(ceil((float(g["z0"]) + 1.0) / SEG)), 0, profile.size() - 1)
	var b := clampi(int(floor((float(g["z1"]) - 1.0) / SEG)) - 1, a, profile.size() - 1)
	var sum := 0.0
	var worst := 0.0
	for i in range(a, b + 1):
		var v: float = rz[i] if machined[i] else 50.0
		sum += v
		worst = maxf(worst, v)
	var rz_avg := sum / float(b - a + 1)
	var pass_g := rz_avg <= float(g["rz"])
	var lines: Array = res["lines"]
	lines.append("%s  Geschliffen Z %d-%d: Rz %.1f µm  (Soll %.1f)" % [_mark(pass_g), int(g["z0"]), int(g["z1"]), rz_avg, float(g["rz"])])
	res["total"] = int(res["total"]) + 1
	res["ok"] = int(res["ok"]) + (1 if pass_g else 0)
	res["score"] = float(res["ok"]) / float(res["total"])
	return res


func set_state(d: Dictionary) -> void:
	super.set_state(d)
	var h = d.get("holder", [])
	holder = [str(h[0]) if h is Array and h.size() > 0 else "", "", "", ""]
	active_slot = 0
	_apply_holder()
