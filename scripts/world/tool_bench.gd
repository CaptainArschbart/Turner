class_name ToolBench
extends Node3D
## Werkbank am Arbeitsplatz: Die Werkzeuge der Maschine liegen darauf und werden per Linksklick in
## die Hand genommen. Ein Klick auf die Bank legt ein Werkzeug aus der Hand zurück auf seinen Platz.
## Was gerade in der Maschine oder in der Hand ist, fehlt auf der Bank.

const WIDTH := 1.8
const DEPTH := 0.7
const TOP_Y := 0.92
const REFRESH := 0.15

## Maschine mit tool_list(), has_tool(id), tool_name(id), make_tool_model(id), MACHINE_ID, TOOL_UPRIGHT
var machine: Node
var player: Node
var _slots: Array[BenchSlot] = []
var _refresh_t := 0.0


## Ablageplatz eines Werkzeugs, Ziel für den Sichtstrahl der Spielfigur.
class BenchSlot extends Node:
	var bench: ToolBench
	var tool_id := ""
	var model: Node3D

	func get_prompt() -> String:
		return bench.prompt_for(tool_id)

	func interact(_p: Node) -> void:
		pass

	func click(p: Node) -> void:
		bench.click_on(tool_id, p)


func _ready() -> void:
	_build_table()
	var list: Array = machine.tool_list()
	var step := (WIDTH - 0.1) / list.size()
	for i in list.size():
		_add_slot(str(list[i]["id"]), str(list[i]["name"]), -(WIDTH - 0.1) * 0.5 + step * (i + 0.5), step)
	refresh()


func _build_table() -> void:
	var wood := Build.mat(Color(0.66, 0.52, 0.36), 0.7)
	var frame := Build.mat(Color(0.2, 0.22, 0.25), 0.5, 0.3)
	Build.box(self, Vector3(WIDTH, 0.05, DEPTH), Vector3(0, TOP_Y - 0.025, 0), wood)
	for x in [-WIDTH * 0.5 + 0.05, WIDTH * 0.5 - 0.05]:
		Build.box(self, Vector3(0.06, TOP_Y - 0.05, DEPTH - 0.06), Vector3(x, (TOP_Y - 0.05) * 0.5, 0), frame)
	Build.box(self, Vector3(WIDTH - 0.1, 0.03, DEPTH - 0.1), Vector3(0, 0.22, 0), frame)
	Build.box(self, Vector3(WIDTH, 0.42, 0.02), Vector3(0, TOP_Y + 0.21, -DEPTH * 0.5 + 0.01), Build.mat(Color(0.85, 0.85, 0.82), 0.8))
	# Die ganze Bank als Ablage: legt das Werkzeug in der Hand auf seinen Platz zurück
	var body := Build.collider(self, Vector3(WIDTH, TOP_Y, DEPTH), Vector3(0, TOP_Y * 0.5, 0))
	var whole := BenchSlot.new()
	whole.bench = self
	add_child(whole)
	body.set_meta("interact", whole)


func _add_slot(id: String, tool_name: String, x: float, step: float) -> void:
	var slot := BenchSlot.new()
	slot.bench = self
	slot.tool_id = id
	add_child(slot)
	_slots.append(slot)
	var hit := Build.collider(self, Vector3(step - 0.02, 0.14, 0.46), Vector3(x, TOP_Y + 0.07, 0.0))
	hit.set_meta("interact", slot)
	slot.model = _lay_down(machine.make_tool_model(id), Vector3(x, 0.0, -0.02))
	var l := Build.label(self, tool_name.replace(" ", "\n"), Vector3(x, TOP_Y + 0.002, DEPTH * 0.5 - 0.08), 0.0006, Color(0.1, 0.1, 0.12), 32)
	l.rotation.x = -PI / 2


## Modell flach auf die Platte legen, Mitte auf x/z und Unterseite auf der Platte.
func _lay_down(model: Node3D, at: Vector3) -> Node3D:
	add_child(model)
	if machine.TOOL_UPRIGHT:
		model.rotation.x = PI / 2
	var box := Build.bounds(model)
	var center := to_local(box.get_center())
	model.position += Vector3(at.x - center.x, TOP_Y + box.size.y * 0.5 - center.y, at.z - center.z)
	return model


func _process(delta: float) -> void:
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH
		refresh()


func refresh() -> void:
	for s in _slots:
		s.model.visible = is_available(s.tool_id)


## Liegt das Werkzeug gerade auf der Bank?
func is_available(id: String) -> bool:
	if machine.has_tool(id):
		return false
	return player == null or not _holds(id)


func _holds(id: String) -> bool:
	return not player.held.is_empty() and player.held["machine"] == machine.MACHINE_ID and player.held["id"] == id


func prompt_for(id: String) -> String:
	if player == null:
		return ""
	if not player.held.is_empty():
		if player.held["machine"] != machine.MACHINE_ID:
			return "%s gehört nicht auf diese Werkbank" % player.held["name"]
		return "[Linksklick] %s zurücklegen" % player.held["name"]
	if id != "" and is_available(id):
		return "[Linksklick] %s nehmen" % machine.tool_name(id)
	return ""


func click_on(id: String, p: Node) -> void:
	if not p.held.is_empty():
		if p.held["machine"] == machine.MACHINE_ID:
			p.clear_held()
	elif id != "" and is_available(id):
		p.set_held(machine, id)
	refresh()
