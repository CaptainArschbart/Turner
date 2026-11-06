class_name RollDoor
extends Node3D
## Rolltor mit je einem Knopf innen und außen neben dem Tor. Lokal: X = Torbreite, Z+ zeigt nach außen.

signal changed

const WIDTH := 4.5
const HEIGHT := 4.5
const SPEED := 0.45      # Anteil je Sekunde
const SLATS := 22
const PASS_AT := 0.6     # ab hier passt die Spielfigur durch

var title := "Rolltor"
var open_t := 0.0
var target := 0.0
var _curtain: Node3D
var _slats: Array[MeshInstance3D] = []
var _collision: CollisionShape3D
var _lamps: Array[MeshInstance3D] = []
var _lamp_open: Material
var _lamp_closed: Material


## Knopf neben dem Tor, Ziel für den Sichtstrahl.
class DoorButton extends Node:
	var door: RollDoor

	func get_prompt() -> String:
		return "[%s] %s %s" % [Settings.binding_text("interact"), door.title, "schließen" if door.is_opening() else "öffnen"]

	func interact(_p: Node) -> void:
		door.toggle()

	func click(_p: Node) -> void:
		door.toggle()


func _ready() -> void:
	var yellow := Build.mat(Color(0.95, 0.75, 0.05), 0.6)
	var steel := Build.mat(Color(0.7, 0.72, 0.74), 0.5, 0.4)
	var rib := Build.mat(Color(0.55, 0.57, 0.6), 0.5, 0.4)
	var dark := Build.mat(Color(0.18, 0.19, 0.21), 0.6)
	_lamp_open = Build.emissive(Color(0.1, 0.9, 0.2), 1.5)
	_lamp_closed = Build.emissive(Color(0.9, 0.12, 0.08), 1.5)
	for s in [-1.0, 1.0]:
		_outer(Build.box(self, Vector3(0.15, HEIGHT + 0.1, 0.1), Vector3(s * (WIDTH * 0.5 + 0.07), HEIGHT * 0.5, 0), yellow))
	_outer(Build.box(self, Vector3(WIDTH + 0.3, 0.35, 0.35), Vector3(0, HEIGHT + 0.1, 0), dark))
	_curtain = Node3D.new()
	add_child(_curtain)
	_outer(Build.box(_curtain, Vector3(WIDTH, 1.0, 0.04), Vector3(0, -0.5, 0), steel))
	for i in SLATS:
		var m := Build.box(self, Vector3(WIDTH, 0.02, 0.06), Vector3(0, HEIGHT - (i + 0.5) * HEIGHT / SLATS, 0), rib)
		_outer(m)
		_slats.append(m)
	var body := StaticBody3D.new()
	body.position = Vector3(0, HEIGHT * 0.5, 0)
	add_child(body)
	_collision = CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(WIDTH, HEIGHT, 0.12)
	_collision.shape = sh
	body.add_child(_collision)
	for side in [-1.0, 1.0]:
		_add_button(side)
	_apply()


## Licht von draußen fällt nur auf Teile, die auch die Außenlichter sehen sollen.
func _outer(m: MeshInstance3D) -> void:
	m.layers = 1 | Site.OUTDOOR_LAYER


func _add_button(side: float) -> void:
	var x := WIDTH * 0.5 + 0.5
	var z := side * 0.2
	var box := Build.box(self, Vector3(0.28, 0.42, 0.1), Vector3(x, 1.35, z), Build.mat(Color(0.95, 0.75, 0.05), 0.5))
	box.layers = 1 | Site.OUTDOOR_LAYER
	var rot := Vector3.ZERO
	var knob := Build.cyl(self, 0.06, 0.05, Vector3(x, 1.27, z + side * 0.06), Build.mat(Color(0.1, 0.1, 0.12), 0.5), Build.AXIS_Z)
	knob.rotation = Vector3(PI / 2, 0, 0) + rot
	var lamp := Build.cyl(self, 0.03, 0.03, Vector3(x, 1.47, z + side * 0.055), _lamp_closed, Build.AXIS_Z)
	_lamps.append(lamp)
	var hit := Build.collider(self, Vector3(0.4, 0.6, 0.22), Vector3(x, 1.35, z))
	var b := DoorButton.new()
	b.door = self
	add_child(b)
	hit.set_meta("interact", b)


func is_opening() -> bool:
	return target > 0.5


func is_open() -> bool:
	return open_t >= 0.999


func toggle() -> void:
	set_open(not is_opening())


func set_open(on: bool, instant := false) -> void:
	target = 1.0 if on else 0.0
	if instant:
		open_t = target
		_apply()
	changed.emit()


func _process(delta: float) -> void:
	if not is_equal_approx(open_t, target):
		open_t = move_toward(open_t, target, SPEED * delta)
		_apply()


func _apply() -> void:
	var h := HEIGHT * (1.0 - open_t)
	_curtain.position.y = HEIGHT
	_curtain.scale.y = maxf(h, 0.001)
	_curtain.visible = h > 0.01
	var bottom := HEIGHT - h
	for m in _slats:
		m.visible = m.position.y > bottom
	# Beim Schließen sofort wieder fest, beim Öffnen erst, wenn es hoch genug ist
	_collision.disabled = open_t >= PASS_AT and is_opening() or open_t >= 0.999
	for l in _lamps:
		l.material_override = _lamp_open if open_t >= 0.999 else _lamp_closed
