class_name DialPanel
extends RefCounted
## Bedienfeld konventioneller Maschinen: je ein Drehknopf mit Griffhebel für Drehzahl und Vorschub, dazu
## die Tasten für Stufe I und II. Das Modell baut MillModel.add_panel, die Maschine hält rpm_set und
## feed_set. Knöpfe und Stufen schalten nur bei stehender Spindel.

const LABEL_ACTIVE := Color(0.95, 0.95, 0.95)
const LABEL_PICKED := Color(1.0, 0.8, 0.15)
const LABEL_DIM := Color(0.42, 0.44, 0.5)
const HANDLE_GRAB := 0.013        # so nah am Griffhebel (m) beginnt ein Klick das Ziehen

## Maschine: rpm_set, feed_set, spindle_on, spindle_speed, _warn(text), _info(text)
var host: Node
var plate: Node3D
var dials: Array
var rpm_values: Array
var feed_values: Array
var feed_unit: String
var lit: Material
var drag := -1                    # gezogener Knopf
var hover := false


func _init(machine: Node, panel: Node3D, dial_list: Array, rpm: Array, feed: Array, unit: String) -> void:
	host = machine
	plate = panel
	dials = dial_list
	rpm_values = rpm
	feed_values = feed
	feed_unit = unit
	lit = Build.emissive(Color(0.04, 0.32, 0.1), 0.7)


## Rastwerte des Drehknopfs k (0 Drehzahl, 1 Vorschub): [Stufe I, Stufe II].
func values(k: int) -> Array:
	return rpm_values if k == 0 else feed_values


## Raste (x) und Stufe (y), die dem eingestellten Wert am nächsten liegen.
func slot(k: int) -> Vector2i:
	var v: float = host.rpm_set if k == 0 else host.feed_set
	var list := values(k)
	var best := Vector2i.ZERO
	for st in 2:
		for i in list[st].size():
			if absf(float(list[st][i]) - v) < absf(float(list[best.y][best.x]) - v):
				best = Vector2i(i, st)
	return best


func index(k: int) -> int:
	return slot(k).x


func stage(k: int) -> int:
	return slot(k).y


## Drehknopf k auf Raste i stellen, die Stufe bleibt. Er dreht ohne Anschlag rundum.
func set_position(k: int, i: int) -> void:
	apply(k, posmod(i, values(k)[0].size()), stage(k))


## Taste für Stufe st (0 = I, 1 = II) am Drehknopf k drücken, die Raste bleibt.
func set_stage(k: int, st: int) -> void:
	apply(k, index(k), clampi(st, 0, 1))


func apply(k: int, pos: int, st: int) -> void:
	if host.spindle_on or host.spindle_speed > 5.0:
		host._warn("Drehknöpfe und Stufen nur bei stehender Spindel schalten!")
		return
	if pos == index(k) and st == stage(k):
		return
	var v := float(values(k)[st][pos])
	if k == 0:
		host.rpm_set = v
		host._info("Drehzahl: %d /min (Stufe %s)" % [int(v), ["I", "II"][st]])
	else:
		host.feed_set = v
		var txt := "%d" % int(v) if is_equal_approx(v, roundf(v)) else ("%.2f" % v).replace(".", ",")
		host._info("Vorschub: %s %s (Stufe %s)" % [txt, feed_unit, ["I", "II"][st]])
	sync()


## Knöpfe und Tasten auf die eingestellten Werte stellen. Werte außerhalb der Skala rasten ein.
func sync() -> void:
	for k in dials.size():
		var s := slot(k)
		var list := values(k)
		if k == 0:
			host.rpm_set = float(list[s.y][s.x])
		else:
			host.feed_set = float(list[s.y][s.x])
		(dials[k]["knob"] as Node3D).rotation.z = -MillModel.dial_angle(s.x, list[0].size())
		for st in 2:
			var btn: Node3D = dials[k]["stages"][st]
			btn.position.z = -0.004 if st == s.y else 0.0
			var cap := btn.get_child(0) as MeshInstance3D
			if not cap.has_meta("off"):
				cap.set_meta("off", cap.material_override)
			cap.material_override = lit if st == s.y else cap.get_meta("off")
			# Aktive Stufe hell, gewählter Wert hervorgehoben, die andere Stufe gedimmt
			var labels: Array = dials[k]["labels"][st]
			for i in labels.size():
				var col := LABEL_DIM
				if st == s.y:
					col = LABEL_PICKED if i == s.x else LABEL_ACTIVE
				(labels[i] as Label3D).modulate = col


## Punkt, an dem ein Sichtstrahl das Bedienfeld trifft (lokal). Null, wenn er von hinten kommt.
func plate_point(origin: Vector3, dir: Vector3) -> Variant:
	var inv := plate.global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * dir
	if d.z >= -0.00001:
		return null
	return o + d * (-o.z / d.z)


## Was ein Sichtstrahl auf dem Bedienfeld trifft: {"dial", "stage"} für eine Taste,
## {"dial", "grab", "dir"} für einen Drehknopf, sonst leer. dir = Drehrichtung zum Klickpunkt.
func hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var p = plate_point(origin, dir)
	if p == null:
		return {}
	for k in dials.size():
		var cy: float = MillModel.DIAL_Y[k]
		for st in 2:
			if Vector2(p.x - float(MillModel.STAGE_X[st]), p.y - cy - MillModel.STAGE_DY).length() <= MillModel.STAGE_R + 0.003:
				return {"dial": k, "stage": st}
		var v := Vector2(p.x, p.y - cy)
		if v.length() > MillModel.HANDLE_R + HANDLE_GRAB:
			continue
		var pos := index(k)
		var handle_a := MillModel.handle_angle(pos)
		var handle := Vector2(sin(handle_a), cos(handle_a))
		var along := v.dot(handle)
		var grab := along >= 0.02 and absf(v.cross(handle)) <= HANDLE_GRAB
		# Klick neben den Griff dreht auf kürzestem Weg in Richtung des Klickpunkts
		var turn := 0
		var diff := wrapf(atan2(v.x, v.y) - MillModel.dial_angle(pos), -PI, PI)
		if v.length() > 0.021 and absf(diff) > 0.2:
			turn = 1 if diff > 0.0 else -1
		return {"dial": k, "grab": grab, "dir": turn}
	return {}


## Beim Ziehen: Griff rastet auf die nächste Raste zur Mausposition und dreht frei über die vollen 360°.
func drag_to(origin: Vector3, dir: Vector3) -> void:
	var p = plate_point(origin, dir)
	if p == null:
		return
	var v := Vector2(p.x, p.y - float(MillModel.DIAL_Y[drag]))
	if v.length() < 0.012:
		return
	var step := TAU / float(values(drag)[0].size())
	var a := wrapf(atan2(v.x, v.y) - MillModel.HANDLE_OFFSET, 0.0, TAU)
	set_position(drag, int(round(a / step)))


## Maus über dem Bedienfeld. Gibt true zurück, wenn ein Klick dort verbraucht wurde.
func input(event: InputEvent, cam: Camera3D) -> bool:
	if event is InputEventMouseMotion:
		var o := cam.project_ray_origin(event.position)
		var d := cam.project_ray_normal(event.position)
		if drag >= 0:
			drag_to(o, d)
		else:
			set_hover(not hit(o, d).is_empty())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			drag = -1
			return false
		var h := hit(cam.project_ray_origin(event.position), cam.project_ray_normal(event.position))
		if h.is_empty():
			return false
		# Taste drücken, Griff festhalten und ziehen, auf die Skala klicken dreht eine Raste
		if h.has("stage"):
			set_stage(h["dial"], h["stage"])
		elif h["grab"]:
			drag = h["dial"]
		elif h["dir"] != 0:
			set_position(h["dial"], index(h["dial"]) + int(h["dir"]))
		return true
	return false


func set_hover(on: bool) -> void:
	if on != hover:
		hover = on
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if on else Input.CURSOR_ARROW)
