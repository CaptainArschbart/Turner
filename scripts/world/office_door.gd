class_name OfficeDoor
extends Node3D
## Drehtür zwischen Werkstatt und Büro. Das Scharnier ist der Ursprung, das Blatt geht in +X und schwingt nach +Z.

const WIDTH := 1.1
const HEIGHT := 2.2
const OPEN_ANGLE := -1.7
const STIFF := 60.0                        # 1/s²: Zug zur Endlage
const DAMP := 13.0                         # 1/s: Dämpfung, leicht unterkritisch (kurzes Nachfedern)

var opened := false
var title := "Bürotür"                     # Name im Interaktionshinweis
var tint := Color(0.86, 0.87, 0.84)        # Farbe des Türblatts, vor dem Einhängen setzen
var _leaf: Node3D
var _vel := 0.0                            # Winkelgeschwindigkeit des Türblatts (rad/s)


func _ready() -> void:
	_leaf = Node3D.new()
	add_child(_leaf)
	var panel := Build.mat(tint, 0.5)
	var dark := Build.mat(Color(0.15, 0.16, 0.18), 0.5, 0.4)
	var w := WIDTH - 0.04
	var x0 := WIDTH * 0.5 - 0.25
	var x1 := WIDTH * 0.5 + 0.25
	var y0 := 1.15
	var y1 := 1.85
	var top := HEIGHT - 0.02
	Build.box(_leaf, Vector3(w, y0, 0.05), Vector3(WIDTH * 0.5, y0 * 0.5, 0), panel)
	Build.box(_leaf, Vector3(w, top - y1, 0.05), Vector3(WIDTH * 0.5, (top + y1) * 0.5, 0), panel)
	Build.box(_leaf, Vector3(x0 - 0.02, y1 - y0, 0.05), Vector3((x0 + 0.02) * 0.5, (y0 + y1) * 0.5, 0), panel)
	Build.box(_leaf, Vector3(WIDTH - 0.02 - x1, y1 - y0, 0.05), Vector3((x1 + WIDTH - 0.02) * 0.5, (y0 + y1) * 0.5, 0), panel)
	Build.box(_leaf, Vector3(x1 - x0, y1 - y0, 0.01), Vector3(WIDTH * 0.5, (y0 + y1) * 0.5, 0), Build.glass(Color(0.75, 0.85, 0.92, 0.3)))
	for z in [-0.05, 0.05]:
		Build.box(_leaf, Vector3(0.14, 0.02, 0.02), Vector3(WIDTH - 0.14, 1.05, z), dark)
	var hit := Build.collider(_leaf, Vector3(WIDTH, HEIGHT, 0.08), Vector3(WIDTH * 0.5, HEIGHT * 0.5, 0))
	hit.set_meta("interact", self)


func get_prompt() -> String:
	return "[%s] %s %s" % [Settings.binding_text("interact"), title, "schließen" if opened else "öffnen"]


func interact(_p: Node) -> void:
	opened = not opened


func click(_p: Node) -> void:
	opened = not opened


## Das Blatt schwingt: Es nimmt Fahrt auf, läuft in die Endlage und federt dort kurz nach. Zu fällt es in
## den Rahmen (Anschlag), weiter als offen geht es nicht.
func _process(delta: float) -> void:
	var goal := OPEN_ANGLE if opened else 0.0
	var a := _leaf.rotation.y
	if absf(a - goal) < 0.0005 and absf(_vel) < 0.002:
		_leaf.rotation.y = goal
		_vel = 0.0
		return
	var steps := maxi(1, ceili(delta / 0.008))
	var dt := delta / steps
	for i in steps:
		_vel += ((goal - a) * STIFF - _vel * DAMP) * dt
		a += _vel * dt
		if a > 0.0:
			a = 0.0                        # Rahmen
			_vel = 0.0
		elif a < OPEN_ANGLE - 0.06:
			a = OPEN_ANGLE - 0.06          # Türstopper
			_vel = -_vel * 0.3
	_leaf.rotation.y = a
