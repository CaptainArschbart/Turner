class_name ChipBin
extends Node3D
## Spänebehälter: Mit Linksklick nimmt man ihn auf, ein Klick auf die Maschine schaufelt die Spänewanne
## hinein, ein Klick auf einen Container im Hof leert ihn. Abgestellt wird er auf seinem Stellplatz.

const FOOT := Vector2(0.8, 0.6)
const SIZES := {
	"bin_s": {"title": "Spänebehälter klein", "price": 50, "kg": 25.0, "height": 0.55},
	"bin_l": {"title": "Spänebehälter groß", "price": 120, "kg": 60.0, "height": 0.8},
}

## Spielwelt: bin_prompt(index), bin_click(index)
var world: Node
var index := 0
var size_id := "bin_s"
var _body: Node3D
var _fill: MeshInstance3D


func _ready() -> void:
	var h := float(SIZES[size_id]["height"])
	var yellow := Build.mat(Color(0.95, 0.72, 0.08), 0.6)
	Build.box(self, Vector3(FOOT.x + 0.1, 0.005, FOOT.y + 0.1), Vector3(0, 0.003, 0), yellow)
	_body = Node3D.new()
	add_child(_body)
	var steel := Build.mat(Color(0.24, 0.3, 0.38), 0.6, 0.2)
	Build.box(_body, Vector3(FOOT.x, 0.03, FOOT.y), Vector3(0, 0.1, 0), steel)
	for sz in [-1.0, 1.0]:
		Build.box(_body, Vector3(FOOT.x, h - 0.1, 0.02), Vector3(0, (h + 0.1) * 0.5, sz * (FOOT.y * 0.5 - 0.01)), steel)
	for sx in [-1.0, 1.0]:
		Build.box(_body, Vector3(0.02, h - 0.1, FOOT.y), Vector3(sx * (FOOT.x * 0.5 - 0.01), (h + 0.1) * 0.5, 0), steel)
		Build.cyl(_body, 0.045, FOOT.y - 0.1, Vector3(sx * (FOOT.x * 0.5 - 0.1), 0.045, 0), Build.mat(Color(0.08, 0.08, 0.09), 0.8), Build.AXIS_Z)
	var chips := Build.mat(Color(0.8, 0.82, 0.85), 0.6)
	_fill = Build.box(_body, Vector3(FOOT.x - 0.06, 1.0, FOOT.y - 0.06), Vector3.ZERO, chips)
	_fill.visible = false
	var hit := Build.collider(self, Vector3(FOOT.x, h, FOOT.y), Vector3(0, h * 0.5, 0))
	hit.set_meta("interact", self)


## Füllstand 0..1 anzeigen. out = gerade in den Händen, dann bleibt nur die Markierung.
func show_state(fraction: float, out: bool) -> void:
	_body.visible = not out
	var h := float(SIZES[size_id]["height"]) - 0.1
	_fill.visible = fraction > 0.001
	_fill.scale.y = maxf(h * fraction, 0.001)
	_fill.position.y = 0.1 + h * fraction * 0.5


func get_prompt() -> String:
	return world.bin_prompt(index)


func interact(_p: Node) -> void:
	pass


func click(_p: Node) -> void:
	world.bin_click(index)
