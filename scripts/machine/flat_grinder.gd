class_name FlatGrinder
extends Mill
## Konventionelle Flachschleifmaschine. Technik wie die Fräsmaschine: Tisch in X, Querschlitten in Y,
## Schleifkopf in Z, Höhenkarte als Werkstück. Scheiben (siehe Wheels) kommen von der Werkbank. Neben dem
## Werkstück sitzt auf dem Tisch das Abziehwerkzeug: Anfahren zieht die Scheibe ab. Die Maschine spannt nur
## vorbearbeitete Teile, geschliffene Zellen merken sich ihre Rautiefe in der Höhenkarte.

const WHEEL_D := 200.0            # Scheibendurchmesser (mm)
const AP_MAX := 0.05              # größte Zustellung je Hub (mm)
const DRESS_OFFSET := 130.0       # Abziehwerkzeug: so weit rechts der Rohteilmitte (mm)
const DRESS_Z := -3.0             # Abziehdiamant: Spitze so tief unter der Rohteil-Oberseite (mm)
const FZ_REC := 1.0               # Richtwert Tischweg je Scheibenumdrehung (mm)
const COLUMN_Z := -0.6
const RPM := [[900, 1120, 1400, 1800, 2000, 2240, 2500, 2800], [1000, 1250, 1600, 2000, 2240, 2500, 2800, 3150]]
const FEED := [[100, 160, 250, 400, 630, 1000, 1600, 2500], [200, 315, 500, 800, 1250, 2000, 3150, 5000]]

var _wheel_rz := 0.0
var _wheels: Array = []
var _at_dresser := false


func _init() -> void:
	MACHINE_ID = "flat_grinder"
	grinder_type = "flat"
	panel_pos = Vector3(0.46, 1.45, COLUMN_Z)
	panel_stand = Vector3(1.4, 0.0, COLUMN_Z)
	rpm_set = 2500.0
	feed_set = 1000.0
	_wheels = Wheels.list("flat_grinder")


func _ready() -> void:
	super._ready()
	# Magnetspanntisch: keine Schraubstockbacken
	for j in _jaws:
		j.visible = false


func tool() -> Dictionary:
	return _wheels[tool_idx]


func tool_list() -> Array:
	return _wheels


func tool_index(id: String) -> int:
	for i in _wheels.size():
		if _wheels[i]["id"] == id:
			return i
	return -1


func tool_name(id: String) -> String:
	return str(Wheels.by_id("flat_grinder", id)["name"])


func default_tool_index() -> int:
	return 1


func make_tool_model(id: String) -> Node3D:
	return _wheel_model(Wheels.by_id("flat_grinder", id))


func make_bench_model(id: String) -> Node3D:
	return _wheel_model(Wheels.by_id("flat_grinder", id))


func _wheel_model(w: Dictionary) -> Node3D:
	var n := Node3D.new()
	var width := float(w["d"]) * 0.001
	Build.cyl(n, WHEEL_D * 0.0005, width, Vector3.ZERO, Build.mat(Wheels.TYPES[w["type"]]["color"], 0.9), Build.AXIS_Z, false, 48)
	Build.cyl(n, 0.04, width + 0.006, Vector3.ZERO, Build.mat(Color(0.3, 0.32, 0.35), 0.4, 0.8), Build.AXIS_Z, false, 24)
	Build.box(n, Vector3(0.012, 0.03, width + 0.008), Vector3(0, 0.07, 0), Build.mat(Color(0.1, 0.1, 0.12), 0.7))
	return n


## Scheibe aufziehen. Von Hand nur bei stehender Spindel und oben stehendem Kopf.
func select_tool(i: int, silent := false) -> void:
	i = clampi(i, 0, _wheels.size() - 1)
	if i == tool_idx and _tool_node and not spindle_empty:
		return
	if not silent:
		if spindle_speed > 5.0:
			_warn("Erst Spindel stoppen, dann Scheibe wechseln!")
			return
		if tool_z < 0.0:
			_warn("Erst den Schleifkopf über das Teil fahren (Z > 0).")
			return
	tool_idx = i
	tool_heat = 0.0
	spindle_empty = false
	if silent and tool_stock != null and not tool_stock.has(str(tool()["id"])):
		tool_stock.add(str(tool()["id"]), "wheel")
	refresh_tool_mods()
	if _tool_node:
		spindle.remove_child(_tool_node)
		_tool_node.queue_free()
	_tool_node = _wheel_model(tool())
	spindle.add_child(_tool_node)
	_sync_axes()


## Scheibe verbraucht oder zerstört: Sie ist weg und muss neu gekauft werden.
func _lose_wheel() -> void:
	var id := str(tool()["id"])
	tool_lost.emit(int(tool()["price"]), str(tool()["name"]))
	if tool_stock != null:
		tool_stock.remove(id)
		clear_spindle()


func _refresh_cut_data() -> void:
	_cd = {"vmin": 1400.0, "vmax": 1800.0, "fz_rec": FZ_REC, "fz_max": 3.0, "ap_max": AP_MAX + 0.001}


func cutting_speed() -> float:
	return PI * WHEEL_D * spindle_speed / 1000.0


## Schleifen nutzt die Scheibe ab und macht sie unrund.
func _add_wear(delta: float) -> void:
	if tool_stock == null or spindle_empty:
		return
	var id := str(tool()["id"])
	if Wheels.use(tool_stock, id, str(tool()["type"]), material, ceramic_part, delta):
		_crash("SCHEIBE VERBRAUCHT! %s muss neu gekauft werden." % tool()["name"])
		_lose_wheel()
		return
	if tool_stock.dull(id) >= 0.8:
		_warn("Die Scheibe wird unrund (%d %%): am Abziehwerkzeug abziehen." % int(tool_stock.dull(id) * 100.0))


## Schritt mit Prüfung auf Abziehwerkzeug und Schleifmittel.
func _step_tool(sx: float, sy: float, sz: float, speed: float) -> bool:
	var x := tool_x + sx
	var y := tool_y + sy
	var z := tool_z + sz
	if not spindle_empty:
		var over_dresser := absf(x - dresser_x()) <= 15.0 and absf(y - block_w * 0.5) <= float(tool()["d"]) * 0.5 + 3.0
		if over_dresser and z < DRESS_Z - 0.05:
			_crash("KOLLISION! Scheibe zu tief in das Abziehwerkzeug gefahren - Not-Halt.")
			return false
		_dress_check(over_dresser, z)
		# Keramik schneidet nur Diamant: Die falsche Scheibe rutscht ab und stoppt
		if has_part and ceramic_part and not Wheels.cuts(str(tool()["type"]), true):
			var r := tool_radius()
			if x + r > 0.0 and x - r < block_l and y + r > 0.0 and y - r < block_w and height_at(clampf(x, 0.0, block_l), clampf(y, 0.0, block_w)) > z:
				_crash("%s schneidet keine Keramik. Diamantscheibe aufziehen." % tool()["name"])
				return false
	return super._step_tool(sx, sy, sz, speed)


## X-Stellung des Abziehwerkzeugs, es sitzt neben dem Werkstück auf dem Tisch.
func dresser_x() -> float:
	return block_l * 0.5 + DRESS_OFFSET


func _dress_check(over: bool, z: float) -> void:
	var touching := over and z <= DRESS_Z + 0.001
	if touching and not _at_dresser and spindle_speed > 30.0 and tool_stock != null:
		var id := str(tool()["id"])
		if Wheels.dress(tool_stock, id):
			_crash("SCHEIBE VERBRAUCHT! %s muss neu gekauft werden." % tool()["name"])
			_lose_wheel()
		else:
			_info("Scheibe abgezogen: wieder gerade, %d %% Verschleiß." % int(tool_stock.wear(id) * 100.0))
	_at_dresser = touching


func _spin_spindle(delta: float) -> void:
	spindle.rotate_z(-spindle_speed / 60.0 * TAU * delta)


func _build_model() -> Dictionary:
	# Nach dem Vorbild: heller Maschinenkörper, roter Tisch und Schleifkopf, Faltenbalg am Ständer
	var body := Build.mat(Color(0.9, 0.9, 0.86), 0.5)
	var red := Build.mat(Color(0.74, 0.1, 0.08), 0.45)
	var light := Build.mat(Color(0.8, 0.82, 0.84), 0.5)
	var dark := Build.mat(Color(0.12, 0.13, 0.15), 0.55, 0.2)
	var black := Build.mat(Color(0.05, 0.05, 0.06), 0.6)
	var steel := Build.mat(Color(0.65, 0.67, 0.7), 0.3, 0.9)

	# Maschinenbett: Sockel, Körper mit Blende und Wanne, darüber läuft der Tisch
	Build.box(self, Vector3(1.96, 0.08, 1.06), Vector3(0, 0.04, -0.1), dark)
	Build.box(self, Vector3(1.9, 0.64, 1.0), Vector3(0, 0.4, -0.1), body)
	Build.box(self, Vector3(1.9, 0.02, 0.92), Vector3(0, 0.73, -0.1), light)
	Build.box(self, Vector3(1.9, 0.1, 0.03), Vector3(0, 0.79, 0.385), body)
	Build.box(self, Vector3(1.9, 0.1, 0.03), Vector3(0, 0.79, -0.385), body)
	Build.box(self, Vector3(1.9, 0.015, 0.035), Vector3(0, 0.83, 0.387), red)
	# Tür mit rotem Schild in der Mitte
	Build.box(self, Vector3(0.62, 0.42, 0.012), Vector3(0, 0.36, 0.404), Build.mat(Color(0.84, 0.84, 0.8), 0.5))
	Build.box(self, Vector3(0.18, 0.2, 0.006), Vector3(0, 0.38, 0.412), red)
	Build.box(self, Vector3(0.12, 0.02, 0.006), Vector3(0.22, 0.2, 0.412), dark)

	# Kreuzschlitten (Y) und Tisch (X) mit Magnetspannplatte und roten Spritzschutzkästen an den Enden
	var saddle_n := Node3D.new()
	saddle_n.position.y = MillModel.TABLE_Y
	add_child(saddle_n)
	Build.box(saddle_n, Vector3(0.6, 0.1, 0.5), Vector3(0, -0.1, 0), body)
	var table_n := Node3D.new()
	saddle_n.add_child(table_n)
	Build.box(table_n, Vector3(1.72, 0.035, 0.42), Vector3(0, -0.035, 0), red)
	Build.box(table_n, Vector3(0.92, 0.03, 0.36), Vector3(0, -0.015, 0), Build.mat(Color(0.34, 0.36, 0.38), 0.45, 0.6))
	for i in 9:
		Build.box(table_n, Vector3(0.88, 0.002, 0.008), Vector3(0, 0.001, -0.16 + i * 0.04), Build.mat(Color(0.65, 0.66, 0.68), 0.3, 0.8))
	for s in [-1.0, 1.0]:
		Build.box(table_n, Vector3(0.2, 0.26, 0.42), Vector3(s * 0.76, 0.11, 0), red)
	# Abziehwerkzeug neben dem Werkstück: Halter mit Diamantspitze, Spitze bei DRESS_Z
	var tip_y := MillModel.TOP_Y - MillModel.TABLE_Y + DRESS_Z * 0.001
	Build.box(table_n, Vector3(0.05, tip_y - 0.012, 0.05), Vector3(DRESS_OFFSET * 0.001, (tip_y - 0.012) * 0.5, 0), dark)
	Build.cyl(table_n, 0.008, 0.012, Vector3(DRESS_OFFSET * 0.001, tip_y - 0.006, 0), Build.mat(Color(0.9, 0.92, 0.95), 0.15, 0.4), Build.AXIS_Y, false, 12, 0.001)
	var wheel_x := MillModel._handwheel(self, Vector3(-0.42, 0.56, 0.42), Build.AXIS_Z, steel, black)
	var wheel_y := MillModel._handwheel(self, Vector3(0.42, 0.56, 0.42), Build.AXIS_Z, steel, black)
	var vise := Node3D.new()
	table_n.add_child(vise)
	Build.box(vise, Vector3(0.4, 0.03, 0.3), Vector3(0, 0.017, 0), Build.mat(Color(0.45, 0.47, 0.5), 0.4, 0.7))

	# Ständer hinter dem Tisch mit Faltenbalg, Schleifkopf vorn daran
	Build.box(self, Vector3(0.7, 1.46, 0.36), Vector3(0, 1.33, COLUMN_Z), body)
	Build.box(self, Vector3(0.36, 0.86, 0.008), Vector3(0, 1.5, COLUMN_Z + 0.183), black)
	for i in 12:
		Build.box(self, Vector3(0.36, 0.012, 0.012), Vector3(0, 1.1 + i * 0.07, COLUMN_Z + 0.188), dark)
	var head_n := Node3D.new()
	head_n.position.y = MillModel.TOP_Y + 0.2
	add_child(head_n)
	Build.box(head_n, Vector3(0.42, 0.3, 0.36), Vector3(0, 0.18, -0.21), red)
	Build.box(head_n, Vector3(0.28, 0.2, 0.09), Vector3(0, 0.02, -0.03), light)
	Build.cyl(head_n, 0.09, 0.28, Vector3(0, 0.42, -0.22), dark, Build.AXIS_Z)
	Build.box(head_n, Vector3(0.14, 0.09, 0.012), Vector3(0, 0.2, -0.024), light)
	var wheel_z := MillModel._handwheel(head_n, Vector3(0.26, 0.18, -0.2), Build.AXIS_X, steel, black)
	# Scheibenschutz: halbe Haube über der Scheibe, die untere Hälfte schleift
	Build.box(head_n, Vector3(0.24, 0.13, 0.07), Vector3(0, 0.055, 0.0), red)
	Build.box(head_n, Vector3(0.02, 0.1, 0.07), Vector3(-0.12, -0.04, 0.0), red)
	Build.box(head_n, Vector3(0.02, 0.1, 0.07), Vector3(0.12, -0.04, 0.0), red)
	# Scheibenmitte: Der tiefste Punkt der Scheibe liegt tool_length unter der Nase
	var spindle_n := Node3D.new()
	spindle_n.position.y = -MillTools.tool_length({"kind": "wheel"}) * 0.001 + WHEEL_D * 0.0005
	head_n.add_child(spindle_n)
	var lamp_n := SpotLight3D.new()
	lamp_n.position = Vector3(-0.2, 0.1, 0.22)
	lamp_n.basis = Basis.looking_at((Vector3(0, -0.15, 0) - lamp_n.position).normalized(), Vector3.BACK)
	lamp_n.light_energy = 1.4
	lamp_n.spot_range = 1.2
	lamp_n.spot_angle = 22
	lamp_n.light_color = Color(1.0, 0.96, 0.9)
	head_n.add_child(lamp_n)
	# Lampe am Gelenkarm auf dem Ständer
	Build.cyl(self, 0.012, 0.3, Vector3(-0.24, 2.2, COLUMN_Z), dark)
	Build.cyl(self, 0.01, 0.4, Vector3(-0.24, 2.34, COLUMN_Z + 0.2), dark, Build.AXIS_Z)
	Build.cyl(self, 0.06, 0.11, Vector3(-0.24, 2.3, COLUMN_Z + 0.42), steel, Build.AXIS_Y, false, 16, 0.025)

	# Anzeige auf einem Arm neben dem Ständer
	var sx := -0.62
	Build.box(self, Vector3(0.28, 0.04, 0.04), Vector3(-0.42, 1.72, COLUMN_Z), body)
	Build.box(self, Vector3(0.46, 0.26, 0.06), Vector3(sx, 1.72, COLUMN_Z), dark)
	Build.box(self, Vector3(0.4, 0.2, 0.004), Vector3(sx, 1.72, COLUMN_Z + 0.032), Build.emissive(Color(0.04, 0.14, 0.26), 1.0))
	var screen := Label3D.new()
	screen.position = Vector3(sx, 1.72, COLUMN_Z + 0.037)
	screen.pixel_size = 0.0004
	screen.font_size = 40
	screen.outline_size = 0
	screen.modulate = Color(0.55, 0.95, 1.0)
	screen.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(screen)
	var led := Build.cyl(self, 0.01, 0.012, Vector3(0.28, 1.95, COLUMN_Z + 0.186), Build.mat(Color(0.05, 0.2, 0.05), 0.5), Build.AXIS_Z)

	# Bedienfeld an einem Kasten rechts am Ständer
	Build.box(self, Vector3(0.1, 0.5, 0.3), Vector3(0.4, 1.45, COLUMN_Z), red)
	var p := MillModel.add_panel(self, panel_pos, PI / 2, rpm_dial(), feed_dial(), "Tischvorschub mm/min", dark, light, black, steel)
	# Schaltpult auf einem Wagen rechts neben der Maschine
	Build.box(self, Vector3(0.42, 0.06, 0.5), Vector3(1.28, 0.12, 0.0), dark)
	Build.box(self, Vector3(0.36, 0.64, 0.44), Vector3(1.28, 0.47, 0.0), body)
	Build.box(self, Vector3(0.38, 0.1, 0.46), Vector3(1.28, 0.3, 0.0), red)
	Build.box(self, Vector3(0.4, 0.12, 0.48), Vector3(1.28, 0.85, 0.0), red, false, Vector3(0.3, 0, 0))
	for i in 8:
		Build.cyl(self, 0.012, 0.012, Vector3(1.16 + (i % 4) * 0.08, 0.92 - floorf(i / 4.0) * 0.03, 0.02 + floorf(i / 4.0) * 0.09), black if i % 3 else Build.mat(Color(0.2, 0.6, 0.25), 0.5), Build.AXIS_Y)
	return {"saddle": saddle_n, "table": table_n, "vise": vise, "head": head_n, "spindle": spindle_n,
		"hw_x": wheel_x, "hw_y": wheel_y, "hw_z": wheel_z, "screen": screen, "led": led, "lamp": lamp_n,
		"panel": p["panel"], "dials": p["dials"]}


func _build_colliders() -> void:
	for b in [[Vector3(1.9, 0.86, 1.0), Vector3(0, 0.43, -0.1)], [Vector3(0.7, 2.06, 0.36), Vector3(0, 1.03, COLUMN_Z)],
			[Vector3(1.72, 0.16, 0.42), Vector3(0, 0.94, 0.0)], [Vector3(0.42, 0.34, 0.45), Vector3(0, 1.5, -0.22)],
			[Vector3(0.42, 1.0, 0.5), Vector3(1.28, 0.5, 0.0)]]:
		Build.collider(self, b[0], b[1]).set_meta("interact", self)
	var levers := Build.collider(self, Vector3(0.04, MillModel.PANEL_H, MillModel.PANEL_W), panel_pos)
	levers.set_meta("interact", _lever_station)


func rpm_dial() -> Array:
	return RPM


func feed_dial() -> Array:
	return FEED


func machine_title() -> String:
	return "Konventionelle Flachschleifmaschine"


func head_title() -> String:
	return "Schleifkopf"


func axis_name(axis: int) -> String:
	return ["X (Tisch)", "Y (Querschlitten)", "Z (Schleifkopf)"][axis]


func chip_position() -> Vector3:
	return Vector3(randf_range(-0.85, 0.85), 0.742 + randf() * 0.004, randf_range(-0.45, 0.3))


## Nur Backenkollision gibt es hier nicht: Das Teil liegt auf der Magnetplatte.
func _clash(x: float, y: float, z: float) -> String:
	var r := tool_radius()
	if has_part and z < -block_h and x + r > 0.0 and x - r < block_l and y + r > 0.0 and y - r < block_w:
		return "KOLLISION! Scheibe auf der Magnetplatte - Not-Halt."
	return ""


## Überlastung zerstört nichts: Not-Halt.
func _tool_broken(text: String) -> void:
	if text.contains("VERSCHLISSEN"):
		_crash(text)
	elif text.contains("AUSGEGLÜHT"):
		_crash("SCHLEIFBRAND! Scheibe zu schnell für %s. Drehzahl senken." % _mat_group["title"])
	else:
		_crash("SCHEIBE ÜBERLASTET! Höchstens %s mm je Hub zustellen und langsamer fahren." % str(AP_MAX).replace(".", ","))


## Vor dem Schleifen: Die Rautiefe dieses Hubs wird in die Zellen geschrieben.
func _before_stamp(speed: float) -> void:
	_wheel_rz = grind_rz(speed * 60.0 / maxf(spindle_speed, 1.0), last_ap, coolant)
	if tool_stock != null:
		_wheel_rz *= Wheels.finish(str(tool()["type"]), tool_stock.dull(str(tool()["id"])))
	_cut_mark = 2.0 + _wheel_rz * 0.01


## Rautiefe in µm aus Tischweg je Scheibenumdrehung und Zustellung. Ohne Kühlung schlechter.
static func grind_rz(feed_per_rev: float, ap: float, kss: bool) -> float:
	var rz := 0.5 + 0.9 * feed_per_rev / FZ_REC + 0.6 * clampf(ap / AP_MAX, 0.0, 1.0)
	return rz * (1.0 if kss else 1.4)


## Schleifprüfung: Alle Maße wie beim Fräsen, dazu muss die geforderte Fläche geschliffen und fein genug sein.
## Tiefer liegende Stellen wie Taschen und Bohrungen zählen nicht zur Fläche.
func evaluate_grind(job: Dictionary) -> Dictionary:
	if flipped:
		_flip_maps()
		flipped = false
		var turned := evaluate_grind(job)
		_flip_maps()
		flipped = true
		return turned
	var res := evaluate(job)
	var g: Dictionary = job["grind"]
	var a: Array = g["area"]
	var top := -1.0e9
	for j in ny:
		var y := (j + 0.5) * CELL
		if y < float(a[2]) or y > float(a[3]):
			continue
		for i in nx:
			var x := (i + 0.5) * CELL
			if x >= float(a[0]) and x <= float(a[1]):
				top = maxf(top, data[(j * nx + i) * 2])
	var cells := 0
	var ground := 0
	var rz_sum := 0.0
	for j in ny:
		var y := (j + 0.5) * CELL
		if y < float(a[2]) or y > float(a[3]):
			continue
		for i in nx:
			var x := (i + 0.5) * CELL
			if x < float(a[0]) or x > float(a[1]):
				continue
			var k := (j * nx + i) * 2
			if data[k] < top - 0.3:
				continue
			cells += 1
			if data[k + 1] >= 2.0:
				ground += 1
				rz_sum += (data[k + 1] - 2.0) * 100.0
	var share := float(ground) / maxf(cells, 1)
	var rz_avg := rz_sum / maxf(ground, 1)
	var pass_g := share >= 0.97 and rz_avg <= float(g["rz"])
	var lines: Array = res["lines"]
	lines.append("%s  Geschliffen: %d %% der Fläche, Rz %.1f µm  (Soll %.1f)" % [_mark(pass_g), int(share * 100.0), rz_avg, float(g["rz"])])
	res["total"] = int(res["total"]) + 1
	res["ok"] = int(res["ok"]) + (1 if pass_g else 0)
	res["score"] = float(res["ok"]) / float(res["total"])
	return res
