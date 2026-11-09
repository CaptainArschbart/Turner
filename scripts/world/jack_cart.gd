class_name JackCart
extends CharacterBody3D
## Der Hubwagen als eigener Körper in der Welt. Die Spielfigur hält das Griffende der Deichsel und läuft
## normal; der Wagen folgt kinematisch wie ein echter Hubwagen:
##  - zwei feste Lastrollen in den Zinkenspitzen (Achse bei AXLE_X), ein lenkbares Rad unter der Deichsel (PIVOT_X)
##  - das Lenkrad rollt nur in seiner Richtung, die Lastrollen rutschen nicht seitlich: Das Chassis dreht sich
##    um die Lastachse (Fahrradmodell, Achsabstand WHEELBASE)
##  - der Lenkwinkel ist die Richtung vom Lenkrad zur Figur, bezogen aufs Chassis, auf +-90 Grad begrenzt
##  - die Deichsel hat feste Länge: Die Figur bleibt im Abstand HOLD um das Lenkrad, ob Ziehen oder Drücken
##  - stößt das Chassis irgendwo an, bleibt es stehen und die Figur wird an der Deichsel festgehalten
## Koordinaten im Modell: x entlang der Gabel (Spitze bei +x, Deichsel bei -x), Mitte des Modells im Ursprung.
## Drehung rotation.y = phi: die Gabel zeigt nach (cos phi, -sin phi) in (x, z).

const PIVOT_X := -0.946                  # Drehpunkt des Lenkrads
const AXLE_X := 0.857                    # Achse der festen Lastrollen
const WHEELBASE := AXLE_X - PIVOT_X
const GRIP_REACH := 0.76                 # waagerecht vom Lenkrad bis zum Griff der geneigten Deichsel
const HAND_AHEAD := 0.35                 # die Hände greifen so weit vor dem Körper der Figur
const HOLD := GRIP_REACH + HAND_AHEAD    # Abstand Figur - Lenkrad (Deichsel mit Arm)
const GRIP_MODEL := Vector3(-1.13, 1.30, 0.0)       # Mitte des Griffbügels im Modell
const JOINT_MODEL := Vector3(-0.946, 0.45, 0.0)     # Gelenk unten an der Deichsel
const TILT := 0.97                       # Neigung der Deichsel nach hinten (rad), zusätzlich zur Neigung im Modell
## Zinken-Kollision: Mitte, Breite, Höhe. Das Modell hat die Zinken bei z 0,205 bis 0,36, die Öffnung der
## kurzen Palettenseite reicht von 0,095 bis 0,38. Die Box ist bewusst schmaler als die Optik (0,205 bis 0,325),
## damit die Zinken seitlich gut 5 cm Spiel haben und man die Öffnungen leichter trifft.
const TINE_Z := 0.265
const TINE_W := 0.12
const TINE_TOP := 0.06
const MAX_STEP := 0.2                    # größte Bewegung des Lenkrads je Bild
const LIFT_TIME := 0.4

const BAR_PARTS := ["Box005", "Cylinder005", "Cylinder006", "Line001", "Line002", "Line004"]
const WHEEL_PARTS := ["Cylinder007", "Cylinder008", "Cylinder009", "Cylinder010", "Object", "Object001"]

var load_n := 0                          # Paletten auf der Gabel
var cross := false                       # Last liegt quer (lange Seite quer zur Gabel)
var lift_t := 0.0                        # 0 = Gabel unten, 1 = oben
var phi := 0.0                           # Drehung um Y (rad), nicht aus der Basis gelesen: dort nur +-90 Grad
var steer := 0.0                         # Winkel der Deichsel zum Chassis (rad)
var model: Node3D
var _wheels: Node3D                      # Lenkrad samt Gabel: dreht mit dem begrenzten Lenkwinkel
var _bar_yaw: Node3D                     # Deichsel: dreht mit der Richtung zur Figur
var _bar_tilt: Node3D
var _grip: Node3D
var _load: Node3D
var _load_shape: CollisionShape3D


func _init() -> void:
	collision_layer = 0                  # nur der Wagen selbst prüft gegen die Welt, nichts prallt an ihm ab
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED


func _ready() -> void:
	model = Props.make("pallet_jack")
	add_child(model)
	_split_model()
	# Gehäuse hinten, die beiden Zinken vorn (Mitte TINE_Z, schmaler als im Modell)
	_shape(Vector3(0.73, 0.58, 0.6), Vector3(-0.865, 0.33, 0.0))
	for sgn in [1.0, -1.0]:
		_shape(Vector3(1.73, TINE_TOP - 0.01, TINE_W), Vector3(0.365, 0.01 + (TINE_TOP - 0.01) * 0.5, sgn * TINE_Z))
	_show_load()


## Deichsel und Lenkrad aus dem Modell lösen, damit sie sich drehen lassen.
func _split_model() -> void:
	var pivot := Vector3(PIVOT_X, 0, 0)
	_wheels = Node3D.new()
	_wheels.position = pivot
	model.add_child(_wheels)
	_bar_yaw = Node3D.new()
	_bar_yaw.position = pivot
	model.add_child(_bar_yaw)
	_bar_tilt = Node3D.new()
	_bar_tilt.position = JOINT_MODEL - pivot
	_bar_yaw.add_child(_bar_tilt)
	_grip = Node3D.new()
	_grip.position = GRIP_MODEL - JOINT_MODEL
	_bar_tilt.add_child(_grip)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var target: Node3D = null
		if mi.name in BAR_PARTS:
			target = _bar_tilt
		elif mi.name in WHEEL_PARTS:
			target = _wheels
		if target:
			(mi as Node3D).reparent(target, true)
	_bar_tilt.rotation.z = TILT


func _shape(size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	add_child(cs)
	return cs


## Last auf der Gabel setzen (Anzahl, quer?). Die Gabel hebt dann in LIFT_TIME an, ohne Last senkt sie sich.
func set_load(n: int, is_cross := false, lifted := false) -> void:
	load_n = n
	cross = is_cross and n > 0
	if lifted:
		lift_t = 1.0 if n > 0 else 0.0
	elif n == 0:
		lift_t = 0.0
	_show_load()


func _show_load() -> void:
	if _load:
		model.remove_child(_load)
		_load.queue_free()
		_load = null
	if _load_shape:
		remove_child(_load_shape)
		_load_shape.queue_free()
		_load_shape = null
	if load_n <= 0:
		return
	_load = Node3D.new()
	_load.rotation.y = PI / 2.0 if cross else 0.0
	model.add_child(_load)
	Shelf.add_pallets(_load, load_n)
	# Eigene Kollisionsbox für den Stapel (Modellkoordinaten, x = entlang der Gabel)
	var pf: Vector2 = Shelf.SIZES["pallet"]["foot"]
	var h := float(Shelf.SIZES["pallet"]["height"]) * load_n
	_load_shape = _shape(Vector3(pf.y, h, pf.x) if cross else Vector3(pf.x, h, pf.y), Vector3.ZERO)
	_place_load()


func _place_load() -> void:
	if _load == null:
		return
	var e := 1.0 - pow(1.0 - lift_t, 2.0)
	var y := Shelf.JACK_LIFT * e
	_load.position = Vector3(Shelf.JACK_LOAD_X, y, 0)
	var h := float(Shelf.SIZES["pallet"]["height"]) * load_n
	_load_shape.position = Vector3(Shelf.JACK_LOAD_X, 0.02 + y + h * 0.5, 0)


func _physics_process(delta: float) -> void:
	var want := 1.0 if load_n > 0 else 0.0
	if not is_equal_approx(lift_t, want):
		lift_t = move_toward(lift_t, want, delta / LIFT_TIME)
		_place_load()


# ------------------------------------------------------------ Lage

func forward() -> Vector2:
	return Vector2(cos(phi), -sin(phi))


func lateral() -> Vector2:
	return Vector2(sin(phi), cos(phi))


func origin2() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func pivot() -> Vector2:
	return origin2() + forward() * PIVOT_X


## Bodenpunkt der Lastmitte (Mitte der Zinken).
func load_spot() -> Vector2:
	return origin2() + forward() * Shelf.JACK_LOAD_X


func place(origin: Vector2, angle: float) -> void:
	phi = angle
	global_transform = Transform3D(Basis(Vector3.UP, angle), Vector3(origin.x, 0.0, origin.y))


## Wo die Figur steht, wenn sie die Deichsel greift: HOLD hinter dem Lenkrad, in Richtung dir.
func hold_point(dir: Vector2) -> Vector2:
	return pivot() + dir * HOLD


## Weltpunkte für beide Hände am Griffbügel.
func grip_points() -> Array[Vector3]:
	var axis := _grip.global_basis.z.normalized()
	var c := _grip.global_position
	return [c + axis * 0.17, c - axis * 0.17]


# ------------------------------------------------------------ Fahren

## Ein Schritt: Die Figur steht bei q (x, z). Gibt zurück, wo sie nach der Deichsel-Bindung steht
## (stößt der Wagen an, wird sie auf den Kreis um das Lenkrad zurückgezogen).
func step(q: Vector2) -> Vector2:
	var f := forward()
	var l := lateral()
	var p := pivot()
	var w := q - p
	var dist := w.length()
	if dist < 0.05:
		return q
	var u := w / dist
	var raw := atan2(u.dot(l), u.dot(-f))
	var dc := clampf(raw, -PI / 2.0, PI / 2.0)
	steer = raw
	_bar_yaw.rotation.y = raw
	_wheels.rotation.y = dc
	# Das Lenkrad rollt nur entlang seiner Achse a (zeigt von ihm zur Figur), so weit, dass die Deichsel wieder HOLD lang ist
	var a := -f * cos(dc) + l * sin(dc)
	var wa := w.dot(a)
	var disc := wa * wa - (dist * dist - HOLD * HOLD)
	var s := wa if disc < 0.0 else wa - sqrt(disc)
	s = clampf(s, -MAX_STEP, MAX_STEP)
	if absf(s) > 0.0001:
		var pn := p + a * s
		# Lastachse: darf nur längs des Chassis rollen, Abstand zum Lenkrad bleibt WHEELBASE
		var rr := origin2() + f * AXLE_X
		var d := pn - rr
		var df := d.dot(f)
		var t := df + sqrt(maxf(df * df - d.length_squared() + WHEELBASE * WHEELBASE, 0.0))
		var rr2 := rr + f * t
		var f2 := (rr2 - pn).normalized()
		var o2 := rr2 - f2 * AXLE_X
		var phi2 := atan2(-f2.y, f2.x)
		# In Teilschritten prüfen (höchstens 5 cm oder 3 Grad), damit nichts durch dünne Wände tunnelt
		var o1 := origin2()
		var phi0 := phi
		var dphi := angle_difference(phi, phi2)
		var n := maxi(1, ceili(maxf((o2 - o1).length() / 0.05, absf(dphi) / deg_to_rad(3.0))))
		for k in range(1, n + 1):
			var t2 := float(k) / n
			var oi := o1.lerp(o2, t2)
			var pi_ := phi0 + dphi * t2
			var xf := Transform3D(Basis(Vector3.UP, pi_), Vector3(oi.x, 0.0, oi.y))
			if test_move(xf, Vector3.ZERO, null, 0.001, true):
				break
			global_transform = xf
			phi = pi_
		p = pivot()
	# Deichsel fest: Figur auf den Kreis um das Lenkrad
	var off := q - p
	if off.length() < 0.001:
		return q
	return p + off.normalized() * HOLD
