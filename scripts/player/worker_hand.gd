class_name WorkerHand
extends Node3D
## Gegliederte Hand für die Spielfigur und die Ego-Arme.
## Lokal: Handgelenk im Ursprung, Unterarm nach +Z, Finger nach -Z, Handfläche nach -Y,
## Daumen zur Körpermitte (rechte Hand side = 1: Daumen bei -X, linke Hand side = -1: bei +X).
## Ein gegriffener Gegenstand liegt quer zur Hand (Griffachse = lokales X) unter den Fingern,
## seine Mitte bei grip_offset(r).

const KNUCKLE_Z := -0.088
const PALM_T := 0.03

var side := 1.0
var _fingers: Array = []          # je Finger [Gelenk1, Gelenk2, Gelenk3]
var _thumb: Array = []            # [Grundgelenk, Endgelenk]
var _curl := PackedFloat32Array([0.25, 0.35, 0.25])
var _target := PackedFloat32Array([0.25, 0.35, 0.25])
var _index_straight := 0.0        # 1 = Zeigefinger gestreckt (Zeigen / Taste drücken)
var _index_target := 0.0
var _thumb_curl := 0.2
var _thumb_target := 0.2


func _init(s := 1.0, skin: Material = null) -> void:
	side = s
	if skin == null:
		skin = Build.mat(Color(0.86, 0.66, 0.52), 0.65)
	# Handrücken und Ballen
	Build.box(self, Vector3(0.08, PALM_T, 0.088), Vector3(0, 0, -0.046), skin)
	Build.box(self, Vector3(0.066, 0.02, 0.05), Vector3(side * 0.006, -0.012, -0.03), skin)   # Ballen
	Build.box(self, Vector3(0.06, 0.026, 0.03), Vector3(0, 0, 0.005), skin)                    # Handgelenk
	var xs := [-0.029, -0.0097, 0.0097, 0.029]
	var lens := [[0.041, 0.026, 0.021], [0.044, 0.028, 0.022], [0.041, 0.026, 0.021], [0.033, 0.021, 0.018]]
	for f in 4:
		var chain: Array = []
		var parent: Node3D = self
		var z := KNUCKLE_Z
		var w := 0.019 if f < 3 else 0.016
		for k in 3:
			var j := Node3D.new()
			j.position = Vector3(side * xs[f], 0.002, z) if k == 0 else Vector3(0, 0, z)
			parent.add_child(j)
			var l: float = lens[f][k]
			Build.box(j, Vector3(w, w * 0.9, l + 0.004), Vector3(0, 0, -l * 0.5), skin)
			if k == 2:
				Build.box(j, Vector3(w * 0.7, 0.002, l * 0.55), Vector3(0, w * 0.46, -l * 0.62), Build.mat(Color(0.93, 0.8, 0.74), 0.4))  # Nagel
			chain.append(j)
			parent = j
			z = -l
			w *= 0.94
		_fingers.append(chain)
	# Daumen: setzt seitlich am Ballen an und zeigt schräg nach vorn zur Mitte
	var t0 := Node3D.new()
	t0.position = Vector3(-side * 0.036, -0.008, -0.022)
	t0.rotation = Vector3(-0.35, side * 0.75, side * 0.5)
	add_child(t0)
	Build.box(t0, Vector3(0.023, 0.021, 0.042), Vector3(0, 0, -0.019), skin)
	var t1 := Node3D.new()
	t1.position = Vector3(0, 0, -0.04)
	t0.add_child(t1)
	Build.box(t1, Vector3(0.02, 0.019, 0.032), Vector3(0, 0, -0.015), skin)
	_thumb = [t0, t1]
	_apply()


## Mitte eines gegriffenen Gegenstands mit Radius r (in Handkoordinaten).
static func grip_offset(r: float) -> Vector3:
	return Vector3(0, -PALM_T * 0.5 - r, KNUCKLE_Z + 0.012 + minf(r, 0.03))


## Faust um einen Gegenstand mit Radius r schließen (r <= 0: lockere Hand).
func grip(r: float) -> void:
	_index_target = 0.0
	if r <= 0.0:
		_target = PackedFloat32Array([0.25, 0.35, 0.25])
		_thumb_target = 0.2
		return
	var t := clampf(r / 0.035, 0.0, 1.0)
	_target = PackedFloat32Array([lerpf(1.45, 1.05, t), lerpf(1.55, 1.0, t), lerpf(1.2, 0.7, t)])
	_thumb_target = lerpf(1.0, 0.6, t)


## Zeigefinger ausgestreckt, Rest zur Faust (zum Drücken von Tasten).
func point() -> void:
	_target = PackedFloat32Array([1.5, 1.6, 1.2])
	_index_target = 1.0
	_thumb_target = 0.9


## Sofort in die Zielhaltung (ohne Übergang).
func snap() -> void:
	_curl = _target.duplicate()
	_index_straight = _index_target
	_thumb_curl = _thumb_target
	_apply()


func _process(delta: float) -> void:
	var k := clampf(delta * 14.0, 0.0, 1.0)
	for i in 3:
		_curl[i] = lerpf(_curl[i], _target[i], k)
	_index_straight = lerpf(_index_straight, _index_target, k)
	_thumb_curl = lerpf(_thumb_curl, _thumb_target, k)
	_apply()


func _apply() -> void:
	for f in 4:
		var spread := (1.5 - f) * 0.05 * side * (1.0 - _curl[0] / 1.6)
		for k in 3:
			var c: float = _curl[k]
			if f == 0:
				c = lerpf(c, 0.05, _index_straight)
			var j: Node3D = _fingers[f][k]
			j.rotation = Vector3(-c, spread if k == 0 else 0.0, 0)
	# Daumen legt sich über die Finger
	_thumb[0].rotation = Vector3(-0.35 - _thumb_curl * 0.55, side * (0.75 + _thumb_curl * 0.35), side * 0.5)
	_thumb[1].rotation = Vector3(-_thumb_curl * 0.8, 0, 0)
