class_name DroppedItem
extends RigidBody3D
## Fallen gelassener Gegenstand: Material, Teile, Zeichnungen, Spänebehälter oder ein Werkzeug. Echter
## Physikkörper: fällt, kippt, Rundmaterial rollt, bleibt dann liegen und lässt sich mit freien Händen wieder
## aufheben. Die Spielfigur läuft hindurch, schiebt es dabei aber an.
## item ist das, was die Spielfigur getragen hat, ein Werkzeug als {"kind": "tool", "machine", "id", "name"}.

const LAYER := 1 << 4          # Physik-Ebene: der Blick trifft es, die Spielfigur läuft hindurch
const GROUP := "dropped_item"
const DENSITY := 7850.0        # kg/m³, Stahl reicht für alles Metallische
const MAX_FALL := -5.0
const ROLL_SIDES := 18
const SKIN := 0.008            # Kollision etwas größer: die Physik lässt Körper bis ~1 cm einsinken         # durch den Boden gefallen: zurück auf y = 0

var item: Dictionary = {}
var player: Node
var _half := Vector3.ZERO      # halbe Größe der Kollisionsform
var _age := 0.0

## Liegt still?
var resting: bool:
	get:
		return sleeping or (_age > 0.15 and linear_velocity.length() < 0.03 and angular_velocity.length() < 0.08)


## Neu in die Welt setzen. pos = Mitte des Gegenstands, yaw = Drehung um die Hochachse,
## vel = Anfangsgeschwindigkeit (geworfen / fallen gelassen).
static func spawn(parent: Node, p: Node, it: Dictionary, pos: Vector3, yaw: float, vel := Vector3.ZERO) -> DroppedItem:
	var d := DroppedItem.new()
	d.item = it
	d.player = p
	d.position = pos
	d.rotation.y = yaw
	d.linear_velocity = vel
	parent.add_child(d)
	return d


## Aus einem Spielstand wiederherstellen (get_state).
static func restore(parent: Node, p: Node, s: Dictionary) -> DroppedItem:
	var pp: Array = s["pos"]
	var d := DroppedItem.new()
	d.item = s["item"]
	d.player = p
	d.position = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
	var r = s.get("rot")
	if r is Array and r.size() == 3:
		d.rotation = Vector3(float(r[0]), float(r[1]), float(r[2]))
		d.position.y += 0.005
	else:
		# alter Spielstand: pos war die Unterseite
		d.rotation.y = float(s.get("yaw", 0.0))
		d.set_meta("lift", true)
	parent.add_child(d)
	return d


## Liegt von diesem Werkzeug ein Stück herum?
static func tool_dropped(tree: SceneTree, machine_id: String, id: String) -> bool:
	for n in tree.get_nodes_in_group(GROUP):
		var it: Dictionary = n.item
		if str(it.get("kind", "")) == "tool" and str(it.get("machine", "")) == machine_id and str(it.get("id", "")) == id:
			return true
	return false


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER
	collision_mask = 1 | LAYER        # Welt, Spielfigur und andere liegende Dinge
	continuous_cd = true
	can_sleep = true
	set_meta("interact", self)
	var model := Node3D.new()
	add_child(model)
	if is_tool():
		var m: Node = _machine()
		if m != null:
			var t: Node3D = m.make_tool_model(str(item["id"]))
			model.add_child(t)
			if m.TOOL_UPRIGHT:
				t.rotation.z = PI / 2       # stehende Werkzeuge liegen auf der Seite
	elif player != null:
		player.item_model(model, item, true)
	# Mitte des Modells auf den Ursprung (= Schwerpunkt)
	var box := global_transform.affine_inverse() * Build.bounds(model)
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-0.05, -0.05, -0.05), Vector3(0.1, 0.1, 0.1))
	model.position -= box.get_center()
	var size := Vector3(maxf(box.size.x, 0.02), maxf(box.size.y, 0.006), maxf(box.size.z, 0.02))
	_half = size * 0.5
	if has_meta("lift"):
		remove_meta("lift")
		position.y += _half.y + 0.005

	var cs := CollisionShape3D.new()
	var volume: float
	if _rolls():
		# Rund: Vieleck-Prisma längs X, damit es rollen kann (stabiler als die Zylinderform)
		var rad := maxf(size.y, size.z) * 0.5
		var vrad := (rad + SKIN) / cos(PI / ROLL_SIDES)     # Flächen des Vielecks liegen auf dem Radius
		var pts := PackedVector3Array()
		for k in ROLL_SIDES:
			var a := TAU * k / ROLL_SIDES
			for e in [-0.5, 0.5]:
				pts.append(Vector3(e * size.x, cos(a) * vrad, sin(a) * vrad))
		var poly := ConvexPolygonShape3D.new()
		poly.points = pts
		cs.shape = poly
		volume = PI * rad * rad * size.x
	else:
		var sh := BoxShape3D.new()
		sh.size = size + Vector3.ONE * SKIN * 2.0
		cs.shape = sh
		volume = size.x * size.y * size.z * (0.35 if is_tool() else 1.0)
	add_child(cs)

	var pm := PhysicsMaterial.new()
	match str(item.get("kind", "")):
		"drawing":
			# Papier: segelt und bleibt liegen
			mass = 0.01
			linear_damp = 6.0
			angular_damp = 6.0
			pm.friction = 1.0
			pm.bounce = 0.0
		_:
			mass = clampf(volume * DENSITY, 0.1, 8.0)
			pm.friction = 0.7
			pm.bounce = 0.15
			angular_damp = 2.5 if _rolls() else 0.6     # Rollen läuft nach gut einem Meter aus
			linear_damp = 0.3
	physics_material_override = pm
	# Ein kleiner Drall, damit es nicht wie ein Brett senkrecht landet
	if linear_velocity != Vector3.ZERO and str(item.get("kind", "")) != "drawing":
		angular_velocity = global_basis * Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3), randf_range(-1.0, 1.0))


## Rundmaterial und runde Teile rollen.
func _rolls() -> bool:
	match str(item.get("kind", "")):
		Materials.KIND_ROUND:
			return true
		"part":
			return str(item.get("shape", "")) == "round"
	return false


func is_tool() -> bool:
	return str(item.get("kind", "")) == "tool"


func _machine() -> Node:
	if player == null or not player.machine_lookup.is_valid():
		return null
	return player.machine_lookup.call(str(item.get("machine", "")))


func _physics_process(delta: float) -> void:
	_age += delta
	if global_position.y < MAX_FALL:
		# Durch eine Lücke gefallen: zurück auf den Hallenboden
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		global_position.y = _half.y + 0.05


func title() -> String:
	match str(item.get("kind", "")):
		"tool":
			return str(item.get("name", "Werkzeug"))
		"drawing":
			return "Zeichnung %s" % str(item["job"].get("title", ""))
		"part", "semi":
			return str(item.get("title", "Teil"))
	return "%s  %s" % [Materials.label(str(item.get("material", ""))), RawMaterialTab.describe(item)]


func get_prompt() -> String:
	if player == null:
		return ""
	if not player.hands_free():
		return "%s    |    Hände voll" % title()
	return "[Linksklick] Aufheben: %s" % title()


func interact(p: Node) -> void:
	click(p)


func click(p: Node) -> void:
	if not p.hands_free():
		return
	if is_tool():
		var m := _machine()
		if m == null:
			return
		discard()                      # vorher weg, sonst steckt die Werkbank es gleich zurück
		p.set_held(m, str(item["id"]))
	else:
		discard()
		p.set_carry(item)


## Aus der Welt nehmen (aufgehoben oder verfallen).
func discard() -> void:
	remove_from_group(GROUP)
	if has_meta("interact"):
		remove_meta("interact")
	collision_layer = 0
	queue_free()


func get_state() -> Dictionary:
	var r := global_rotation
	return {"item": item, "pos": [global_position.x, global_position.y, global_position.z],
		"rot": [r.x, r.y, r.z], "yaw": r.y}
