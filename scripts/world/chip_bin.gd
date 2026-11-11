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

## Kranösen im Modell: Mitten der vier Bohrungen (Ursprung = Mitte der Unterkante) und ihr Radius
const LUGS := [Vector3(-0.88, 1.5975, -0.612), Vector3(-0.88, 1.5975, 0.612), Vector3(1.067, 1.5975, -0.612), Vector3(1.067, 1.5975, 0.612)]
const LUG_HOLE := 0.0475

## Spielwelt: bin_prompt(index), bin_click(index)
var world: Node
var index := 0
var size_id := "bin_s"
var _body: Node3D
var _fill: MeshInstance3D
var _hit: StaticBody3D
var _fill_shape: BoxShape3D          # Späne im Behälter tragen, was hineinfällt
var _fill_body: CollisionShape3D
var _last_pos := Vector3.INF
## Ebene, die nur der Blickstrahl trifft (wie DroppedItem.LAYER; hier als Zahl, damit ChipBin ohne Autoloads kompiliert)
const RAY_ONLY_LAYER := 1 << 4


static func size_of(id: String) -> Vector3:
	return MODEL * float(SIZES.get(id, SIZES["bin_s"])["scale"])


## Stellfläche (Breite, Tiefe)
static func foot(id: String) -> Vector2:
	var s := size_of(id)
	return Vector2(s.x, s.z)


static func height(id: String) -> float:
	return size_of(id).y


## Anschlagpunkte für die Ketten des Krans: oben in den Bohrungen der vier Kranösen, von der Mitte der
## Unterkante aus.
static func lugs(id: String) -> Array[Vector3]:
	var k := float(SIZES.get(id, SIZES["bin_s"])["scale"])
	var out: Array[Vector3] = []
	for p in LUGS:
		out.append((p + Vector3(0, LUG_HOLE * 0.6, 0)) * k)
	return out


func _ready() -> void:
	var s := size_of(size_id)
	# Spänekiste aus dem Modell in Originalproportionen. Die schräge Kippseite zeigt nach +X.
	_body = Props.make("chip_box", s)
	add_child(_body)
	var chips := Build.mat(Color(0.8, 0.82, 0.85), 0.6)
	_fill = Build.box(_body, Vector3(s.x * 0.62, 1.0, s.z - 0.08), Vector3.ZERO, chips)
	_fill.visible = false
	_hit = Build.collider(self, s, Vector3(0, s.y * 0.5, 0))
	_hit.set_meta("interact", self)
	_hit.set_meta("reach_in", true)          # man greift hinein: Teile im Behälter lassen sich aufheben
	# Lose Gegenstände fallen in den Behälter: Sie stoßen an seine Wände und den Boden (Solid), nicht an
	# die Hülle. Die Späne darin sind eine eigene Fläche, die mit dem Füllstand steigt.
	_fill.set_meta(Solid.SKIP_META, true)
	Solid.add(self, true)
	var heap := AnimatableBody3D.new()
	heap.sync_to_physics = false             # fährt mit dem Behälter, nicht aus eigener Bewegung
	heap.add_to_group(Solid.DETAIL_GROUP)
	heap.collision_layer = Solid.DETAIL_LAYER
	heap.collision_mask = Solid.ITEM_LAYER
	_fill_shape = BoxShape3D.new()
	_fill_body = CollisionShape3D.new()
	_fill_body.shape = _fill_shape
	_fill_body.disabled = true
	heap.add_child(_fill_body)
	add_child(heap)


## Wird der Behälter bewegt (Kran, Stapler, Schieben), wachen die Gegenstände darin auf: Schlafende Körper
## merken sonst nicht, dass ihnen der Boden unter den Füßen wegfährt.
func _physics_process(_delta: float) -> void:
	var at := global_position
	if at.is_equal_approx(_last_pos):
		return
	_last_pos = at
	var s := size_of(size_id)
	for it in get_tree().get_nodes_in_group(Solid.ITEM_GROUP):
		var q: Vector3 = to_local((it as Node3D).global_position)
		if absf(q.x) < s.x * 0.5 and absf(q.z) < s.z * 0.5 and q.y > -0.1 and q.y < s.y + 0.3:
			(it as RigidBody3D).sleeping = false


## Auf der Gabel des Staplers: kein fester Körper mehr (er steckte sonst tief gehalten im Fahrgestell und
## schob den Stapler weg), nur noch für den Blickstrahl. Abgesetzt wieder fest.
func set_carried(on: bool) -> void:
	if _hit:
		_hit.collision_layer = RAY_ONLY_LAYER if on else 1


## Füllstand 0..1 anzeigen. out = gerade in den Händen, dann bleibt nur die Markierung.
func show_state(fraction: float, out: bool) -> void:
	_body.visible = not out
	var s := size_of(size_id)
	var h := s.y - 0.1
	_fill.visible = fraction > 0.001
	_fill.scale.y = maxf(h * fraction, 0.001)
	_fill.position = Vector3(-s.x * 0.12, 0.1 + h * fraction * 0.5, 0)
	if _fill_body:
		_fill_body.disabled = out or fraction <= 0.001
		_fill_shape.size = Vector3(s.x * 0.62, maxf(h * fraction, 0.01), s.z - 0.08)
		_fill_body.position = _fill.position


func get_prompt() -> String:
	return world.bin_prompt(index)


func interact(_p: Node) -> void:
	pass


func click(_p: Node) -> void:
	world.bin_click(index)
