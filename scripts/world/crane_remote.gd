class_name CraneRemote
extends Node3D
## Funkfernbedienung des Hallenkrans aus models/crane_remote.glb: Gehäuse mit zwei Joysticks.
## Linker Stick fährt den Kran (vor / zurück = Nord / Süd, links / rechts = West / Ost),
## rechter Stick bewegt den Haken (vor = heben, zurück = senken).
## Lage: Gehäusemitte im Ursprung, Sticks nach +Y, Bedienerseite nach +Z, Tragbügel hinten (-Z).
## Alle Exemplare (Hand, Halterung, Werkbank) zeigen die Sticks so, wie der Kran gerade gesteuert wird (input).

const PATH := "res://models/crane_remote.glb"
const WIDTH := 0.26               # Breite des Gehäuses in m
const MODEL_WIDTH := 1.6636       # Breite im Modell (Blender-Einheiten)
const MODEL_HEIGHT := 0.571       # Gehäusehöhe im Modell
const PIVOT_Y := 0.6              # Drehpunkt der Sticks über dem Modellboden (in der Gummimanschette)
const TILT := 0.35                # größter Ausschlag (rad)
const RATE := 7.0                 # wie schnell die Sticks dem Tastendruck folgen (1/s)
const LEFT_STICK := ["Cylinder_005", "Icosphere_003"]
const RIGHT_STICK := ["Cylinder", "Icosphere_001"]

## Steuerung: x = rechts (Ost), y = Haken heben, z = zurück (Süd); je -1 .. 1. Setzt der Hallenkran.
static var input := Vector3.ZERO

var _left: Node3D
var _right: Node3D
var _tilt := Vector3.ZERO


func _init() -> void:
	var scene := load(PATH) as PackedScene
	if scene == null:
		return
	var m := scene.instantiate() as Node3D
	var s := WIDTH / MODEL_WIDTH
	m.scale = Vector3.ONE * s
	m.position = Vector3(0, -MODEL_HEIGHT * 0.5 * s, 0)
	add_child(m)
	_left = _pivot(m, LEFT_STICK)
	_right = _pivot(m, RIGHT_STICK)


## Stick und Knauf unter einen Drehpunkt in der Manschette hängen, damit sie gemeinsam kippen.
func _pivot(m: Node3D, names: Array) -> Node3D:
	var first := m.get_node_or_null(NodePath(str(names[0]))) as Node3D
	if first == null:
		return null
	var p := Node3D.new()
	p.name = "Stick_" + str(names[0])
	p.position = Vector3(first.position.x, PIVOT_Y, first.position.z)
	m.add_child(p)
	for n in names:
		var part := m.get_node_or_null(NodePath(str(n))) as Node3D
		if part != null:
			var xf := part.transform
			part.owner = null              # Besitzer aus der Modellszene passt nach dem Umhängen nicht mehr
			m.remove_child(part)
			p.add_child(part)
			part.transform = Transform3D(xf.basis, xf.origin - p.position)
	return p


func _process(delta: float) -> void:
	_tilt = _tilt.move_toward(input, RATE * delta)
	# Vor (z < 0) kippt die Spitze nach -Z (Drehung um X negativ), rechts (x > 0) nach +X (um Z negativ)
	if _left != null:
		_left.rotation = Vector3(_tilt.z * TILT, 0.0, -_tilt.x * TILT)
	if _right != null:
		_right.rotation = Vector3(-_tilt.y * TILT, 0.0, 0.0)


## Aktueller Ausschlag (für Tests): x, y, z wie input.
func tilt() -> Vector3:
	return _tilt
