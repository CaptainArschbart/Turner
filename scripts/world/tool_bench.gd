class_name ToolBench
extends Node3D
## Werkbank am Arbeitsplatz: Die Werkzeuge der Maschine liegen darauf und werden per Linksklick in
## die Hand genommen. Ein Klick auf die Bank legt ein Werkzeug aus der Hand zurück auf seinen Platz.
## Was gerade in der Maschine oder in der Hand ist, fehlt auf der Bank. Im unteren Teil der Bank sind
## Halterungen, in die der Spieler jedes Werkzeug frei stecken kann.

const WIDTH := 1.8
const DEPTH := 0.7
const TOP_Y := 0.92
const REFRESH := 0.15
const HOLDER_W := 0.13            # Breite einer Halterung
const HOLDER_ROWS := [0.68, 0.42] # Höhe der Halterungsreihen
const HOLDER_H := 0.24            # so hoch darf ein Werkzeug darin sein

## Maschine mit tool_list(), has_tool(id), tool_name(id), make_tool_model(id), MACHINE_ID, TOOL_UPRIGHT
var machine: Node
var player: Node
var width := WIDTH
var depth := DEPTH
var _slots: Array[BenchSlot] = []
var holders: Array[HolderSlot] = []
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


## Halterung unter der Bank, nimmt ein beliebiges Werkzeug dieser Maschine auf.
class HolderSlot extends Node:
	var bench: ToolBench
	var index := 0
	var at := Vector3.ZERO
	var shown := ""
	var model: Node3D

	func get_prompt() -> String:
		return bench.holder_prompt(index)

	func interact(_p: Node) -> void:
		pass

	func click(p: Node) -> void:
		bench.holder_click(index, p)


func _ready() -> void:
	_build_table()
	_build_holders()
	if machine.has_method("bench_rows"):
		_build_rows()
		refresh()
		return
	var list: Array = machine.tool_list()
	var step := (width - 0.1) / list.size()
	for i in list.size():
		_add_slot(str(list[i]["id"]), str(list[i]["name"]), -(width - 0.1) * 0.5 + step * (i + 0.5), step)
	refresh()


func _build_table() -> void:
	var wood := Build.mat(Color(0.66, 0.52, 0.36), 0.7)
	var frame := Build.mat(Color(0.2, 0.22, 0.25), 0.5, 0.3)
	Build.box(self, Vector3(width, 0.05, depth), Vector3(0, TOP_Y - 0.025, 0), wood)
	for x in [-width * 0.5 + 0.05, width * 0.5 - 0.05]:
		Build.box(self, Vector3(0.06, TOP_Y - 0.05, depth - 0.06), Vector3(x, (TOP_Y - 0.05) * 0.5, 0), frame)
	Build.box(self, Vector3(width - 0.1, 0.03, depth - 0.1), Vector3(0, 0.22, 0), frame)
	Build.box(self, Vector3(width, 0.42, 0.02), Vector3(0, TOP_Y + 0.21, -depth * 0.5 + 0.01), Build.mat(Color(0.85, 0.85, 0.82), 0.8))
	# Die ganze Bank als Ablage: legt das Werkzeug in der Hand auf seinen Platz zurück
	var body := Build.collider(self, Vector3(width, TOP_Y, depth), Vector3(0, TOP_Y * 0.5, 0))
	var whole := BenchSlot.new()
	whole.bench = self
	add_child(whole)
	body.set_meta("interact", whole)


## Lochwand mit Halterungen im unteren Teil, zur Vorderseite offen.
func _build_holders() -> void:
	var steel := Build.mat(Color(0.42, 0.45, 0.48), 0.45, 0.6)
	var clip := Build.mat(Color(0.75, 0.77, 0.8), 0.35, 0.9)
	var board_z := depth * 0.5 - 0.22
	Build.box(self, Vector3(width - 0.12, TOP_Y - 0.3, 0.02), Vector3(0, (TOP_Y + 0.2) * 0.5 - 0.03, board_z), steel)
	var cols := int((width - 0.16) / HOLDER_W)
	var x0 := -HOLDER_W * cols * 0.5
	var n := 0
	for y in HOLDER_ROWS:
		Build.box(self, Vector3(width - 0.12, 0.02, 0.12), Vector3(0, float(y) - HOLDER_H * 0.5 - 0.01, board_z + 0.07), steel)
		for c in cols:
			var x := x0 + HOLDER_W * (c + 0.5)
			Build.cyl(self, 0.024, 0.012, Vector3(x, float(y) - HOLDER_H * 0.5 + 0.006, board_z + 0.1), clip)
			var h := HolderSlot.new()
			h.bench = self
			h.index = n
			h.at = Vector3(x, float(y), board_z + 0.1)
			add_child(h)
			holders.append(h)
			# Ragt knapp aus dem Bankkörper, damit der Blick die Halterung trifft
			var hit := Build.collider(self, Vector3(HOLDER_W - 0.005, HOLDER_H, 0.02), Vector3(x, float(y), depth * 0.5 + 0.005))
			hit.set_meta("interact", h)
			n += 1


## Modell in die Halterung setzen: stehend, notfalls verkleinert, damit es in die Zelle passt.
func _show_holder(h: HolderSlot, id: String) -> void:
	h.shown = id
	if h.model != null:
		h.model.free()
		h.model = null
	if id == "":
		return
	var keep := transform
	transform = Transform3D.IDENTITY
	var m: Node3D = machine.make_bench_model(id) if machine.has_method("make_bench_model") else machine.make_tool_model(id)
	add_child(m)
	var box := Build.bounds(m)
	var fit := minf(minf((HOLDER_W - 0.02) / maxf(box.size.x, 0.001), HOLDER_H / maxf(box.size.y, 0.001)), 0.16 / maxf(box.size.z, 0.001))
	if fit < 1.0:
		m.scale = Vector3.ONE * fit
		box = Build.bounds(m)
	var center := box.get_center()
	m.position += Vector3(h.at.x - center.x, h.at.y - HOLDER_H * 0.5 + box.size.y * 0.5 - center.y, h.at.z - center.z)
	h.model = m
	transform = keep


func holder_prompt(i: int) -> String:
	if player == null or machine.tool_stock == null:
		return ""
	var id: String = machine.tool_stock.holder_id(i)
	if not player.carry.is_empty():
		return "Hände voll: Material zuerst ablegen"
	if not player.held.is_empty():
		if player.held["machine"] != machine.MACHINE_ID:
			return "%s gehört nicht auf diese Werkbank" % player.held["name"]
		return "Halterung belegt: %s" % machine.tool_name(id) if id != "" else "[Linksklick] %s in die Halterung stecken" % player.held["name"]
	if id == "":
		return "Halterung frei"
	if machine.has_tool(id):
		return "%s: Ein Stück ist schon an der Maschine" % machine.tool_name(id)
	return "[Linksklick] %s aus der Halterung nehmen" % machine.tool_name(id)


func holder_click(i: int, p: Node) -> void:
	var store = machine.tool_stock
	if store == null or not p.carry.is_empty():
		return
	var id: String = store.holder_id(i)
	if not p.held.is_empty():
		if p.held["machine"] == machine.MACHINE_ID and id == "" and store.place(str(p.held["id"]), i):
			p.clear_held()
	elif id != "" and not machine.has_tool(id):
		store.take(i)
		p.set_held(machine, id)
	refresh()


## Viele Werkzeuge: je Art eine Reihe, davor die Durchmesser als Beschriftung.
func _build_rows() -> void:
	var z := -depth * 0.5 + 0.04
	for row in machine.bench_rows():
		var row_d := float(row["depth"])
		var list: Array = row["tools"]
		var step := (width - 0.1) / list.size()
		for i in list.size():
			var id := str(list[i]["id"])
			var x := -(width - 0.1) * 0.5 + step * (i + 0.5)
			var slot := BenchSlot.new()
			slot.bench = self
			slot.tool_id = id
			add_child(slot)
			_slots.append(slot)
			# Flach: Die vorderen Reihen dürfen den Blick auf die hinteren nicht verdecken
			var hit := Build.collider(self, Vector3(step - 0.01, 0.05, row_d - 0.005), Vector3(x, TOP_Y + 0.025, z + row_d * 0.5))
			hit.set_meta("interact", slot)
			slot.model = _lay_down(machine.make_bench_model(id), Vector3(x, 0.0, z + (row_d - 0.04) * 0.5), bool(row["flat"]))
			var l := Build.label(self, "Ø%d" % int(list[i]["d"]), Vector3(x, TOP_Y + 0.002, z + row_d - 0.018), 0.0009, Color(0.1, 0.1, 0.12), 32)
			l.rotation.x = -PI / 2
		z += row_d


func _add_slot(id: String, tool_name: String, x: float, step: float) -> void:
	var slot := BenchSlot.new()
	slot.bench = self
	slot.tool_id = id
	add_child(slot)
	_slots.append(slot)
	var hit := Build.collider(self, Vector3(step - 0.02, 0.14, 0.46), Vector3(x, TOP_Y + 0.07, 0.0))
	hit.set_meta("interact", slot)
	slot.model = _lay_down(machine.make_tool_model(id), Vector3(x, 0.0, -0.02))
	var l := Build.label(self, tool_name.replace(" ", "\n"), Vector3(x, TOP_Y + 0.002, depth * 0.5 - 0.08), 0.0006, Color(0.1, 0.1, 0.12), 32)
	l.rotation.x = -PI / 2


## Modell flach auf die Platte legen, Mitte auf x/z und Unterseite auf der Platte.
func _lay_down(model: Node3D, at: Vector3, flat := false) -> Node3D:
	add_child(model)
	if machine.TOOL_UPRIGHT and not flat:
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
		s.model.visible = is_available(s.tool_id) or _spares(s.tool_id) > 0
	var store = machine.tool_stock
	if store == null:
		return
	for h in holders:
		var id: String = store.holder_id(h.index)
		if id != h.shown:
			_show_holder(h, id)


## Liegt das Werkzeug gerade auf der Bank?
func is_available(id: String) -> bool:
	if machine.has_tool(id) or not machine.owns_tool(id):
		return false
	return player == null or not _holds(id)


func _spares(id: String) -> int:
	return machine.tool_stock.spare_count(id) if machine.tool_stock != null else 0


func _holds(id: String) -> bool:
	return not player.held.is_empty() and player.held["machine"] == machine.MACHINE_ID and player.held["id"] == id


func prompt_for(id: String) -> String:
	if player == null:
		return ""
	if not player.carry.is_empty():
		return "Hände voll: Material zuerst ablegen"
	if not player.held.is_empty():
		if player.held["machine"] != machine.MACHINE_ID:
			return "%s gehört nicht auf diese Werkbank" % player.held["name"]
		return "[Linksklick] %s zurücklegen" % player.held["name"]
	if id != "" and is_available(id):
		var more := _spares(id)
		return "[Linksklick] %s nehmen%s" % [machine.tool_label(id), "    |    %d weitere" % more if more > 0 else ""]
	if id != "" and _spares(id) > 0:
		return "%s: Ein Stück ist schon an der Maschine" % machine.tool_name(id)
	if id != "" and not machine.owns_tool(id):
		return "%s: am PC im Shop kaufen" % machine.tool_name(id)
	return ""


func click_on(id: String, p: Node) -> void:
	if not p.held.is_empty():
		if p.held["machine"] == machine.MACHINE_ID:
			p.clear_held()
	elif id != "" and is_available(id):
		p.set_held(machine, id)
	refresh()
