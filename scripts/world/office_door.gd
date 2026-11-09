class_name OfficeDoor
extends Node3D
## Drehtür zwischen Werkstatt und Büro. Das Scharnier ist der Ursprung, das Blatt geht in +X und schwingt nach +Z.

const WIDTH := 1.1
const HEIGHT := 2.2
const OPEN_ANGLE := -1.7
const SPEED := 3.0

var opened := false
var title := "Bürotür"                     # Name im Interaktionshinweis
var tint := Color(0.86, 0.87, 0.84)        # Farbe des Türblatts, vor dem Einhängen setzen
var _leaf: Node3D


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


func _process(delta: float) -> void:
	_leaf.rotation.y = move_toward(_leaf.rotation.y, OPEN_ANGLE if opened else 0.0, SPEED * delta)
