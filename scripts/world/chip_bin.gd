class_name ChipBin
extends Node3D
## Spänebehälter: zu groß und zu schwer zum Tragen, er steht fest auf seinem Stellplatz (im Baumodus umstellbar).
## Die Spänekiste unter dem Späneförderer der E50 ist auch so ein Behälter, sie steht fest unter dem Abwurf.

## Maße der Spänekiste in models/non_machine_parts.glb (Breite mit Kippseite, Höhe, Tiefe).
const MODEL := Vector3(2.66, 1.68, 1.31)
## scale: Faktor auf die Modellgröße, die Proportionen bleiben erhalten.
const SIZES := {
	"bin_s": {"title": "Spänebehälter klein", "price": 50, "kg": 25.0, "scale": 0.8},
	"bin_l": {"title": "Spänebehälter groß", "price": 120, "kg": 60.0, "scale": 1.0},
}

## Spielwelt: bin_prompt(index), bin_click(index)
var world: Node
var index := 0
var size_id := "bin_s"
var _body: Node3D
var _fill: MeshInstance3D


static func size_of(id: String) -> Vector3:
	return MODEL * float(SIZES.get(id, SIZES["bin_s"])["scale"])


## Stellfläche (Breite, Tiefe)
static func foot(id: String) -> Vector2:
	var s := size_of(id)
	return Vector2(s.x, s.z)


static func height(id: String) -> float:
	return size_of(id).y


func _ready() -> void:
	var s := size_of(size_id)
	var yellow := Build.mat(Color(0.95, 0.72, 0.08), 0.6)
	Build.box(self, Vector3(s.x + 0.1, 0.005, s.z + 0.1), Vector3(0, 0.003, 0), yellow)
	# Spänekiste aus dem Modell in Originalproportionen. Die schräge Kippseite zeigt nach +X.
	_body = Props.make("chip_box", s)
	add_child(_body)
	var chips := Build.mat(Color(0.8, 0.82, 0.85), 0.6)
	_fill = Build.box(_body, Vector3(s.x * 0.62, 1.0, s.z - 0.08), Vector3.ZERO, chips)
	_fill.visible = false
	var hit := Build.collider(self, s, Vector3(0, s.y * 0.5, 0))
	hit.set_meta("interact", self)


## Füllstand 0..1 anzeigen. out = gerade in den Händen, dann bleibt nur die Markierung.
func show_state(fraction: float, out: bool) -> void:
	_body.visible = not out
	var s := size_of(size_id)
	var h := s.y - 0.1
	_fill.visible = fraction > 0.001
	_fill.scale.y = maxf(h * fraction, 0.001)
	_fill.position = Vector3(-s.x * 0.12, 0.1 + h * fraction * 0.5, 0)


func get_prompt() -> String:
	return world.bin_prompt(index)


func interact(_p: Node) -> void:
	pass


func click(_p: Node) -> void:
	world.bin_click(index)
