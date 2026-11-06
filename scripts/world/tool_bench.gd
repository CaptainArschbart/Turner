class_name ToolBench
extends Node3D
## Werkbank am Arbeitsplatz: Die Werkzeuge der Maschine stecken in den Halterungen im unteren Teil. Auf der
## Platte liegt nichts. Gekaufte Werkzeuge kommen in die nächste freie Halterung, der Spieler kann sie frei
## umstecken. Ein Klick auf die Bank steckt ein Werkzeug aus der Hand in die nächste freie Halterung.

const WIDTH := 1.8
const DEPTH := 0.7
const TOP_Y := 0.92
const REFRESH := 0.15
const HOLDER_W := 0.13            # Breite einer Halterung
const HOLDER_ROWS := [0.79, 0.57, 0.35]   # Höhe der Halterungsreihen
const HOLDER_H := 0.21            # so hoch darf ein Werkzeug darin sein

## Maschine mit tool_stock, has_tool(id), tool_name(id), make_tool_model(id), MACHINE_ID
var machine: Node
var player: Node
var width := WIDTH
var depth := DEPTH
var holders: Array[HolderSlot] = []
var _refresh_t := 0.0


## Die ganze Bank als Ablage: steckt das Werkzeug aus der Hand in die nächste freie Halterung.
class BenchBody extends Node:
	var bench: ToolBench

	func get_prompt() -> String:
		return bench.body_prompt()

	func interact(_p: Node) -> void:
		pass

	func click(p: Node) -> void:
		bench.body_click(p)


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
	refresh()


func _build_table() -> void:
	var wood := Build.mat(Color(0.66, 0.52, 0.36), 0.7)
	var frame := Build.mat(Color(0.2, 0.22, 0.25), 0.5, 0.3)
	Build.box(self, Vector3(width, 0.05, depth), Vector3(0, TOP_Y - 0.025, 0), wood)
	for x in [-width * 0.5 + 0.05, width * 0.5 - 0.05]:
		Build.box(self, Vector3(0.06, TOP_Y - 0.05, depth - 0.06), Vector3(x, (TOP_Y - 0.05) * 0.5, 0), frame)
	Build.box(self, Vector3(width - 0.1, 0.03, depth - 0.1), Vector3(0, 0.2, 0), frame)
	Build.box(self, Vector3(width, 0.42, 0.02), Vector3(0, TOP_Y + 0.21, -depth * 0.5 + 0.01), Build.mat(Color(0.85, 0.85, 0.82), 0.8))
	var body := Build.collider(self, Vector3(width, TOP_Y, depth), Vector3(0, TOP_Y * 0.5, 0))
	var whole := BenchBody.new()
	whole.bench = self
	add_child(whole)
	body.set_meta("interact", whole)


## Lochwand mit Halterungen im unteren Teil, zur Vorderseite offen.
func _build_holders() -> void:
	var steel := Build.mat(Color(0.42, 0.45, 0.48), 0.45, 0.6)
	var clip := Build.mat(Color(0.75, 0.77, 0.8), 0.35, 0.9)
	var board_z := depth * 0.5 - 0.22
	Build.box(self, Vector3(width - 0.12, TOP_Y - 0.28, 0.02), Vector3(0, (TOP_Y + 0.2) * 0.5, board_z), steel)
	var cols := int((width - 0.16) / HOLDER_W)
	var x0 := -HOLDER_W * cols * 0.5
	var n := 0
	for y in HOLDER_ROWS:
		Build.box(self, Vector3(width - 0.12, 0.012, 0.13), Vector3(0, float(y) - HOLDER_H * 0.5 - 0.006, board_z + 0.075), steel)
		for c in cols:
			var x := x0 + HOLDER_W * (c + 0.5)
			Build.cyl(self, 0.024, 0.008, Vector3(x, float(y) - HOLDER_H * 0.5 + 0.004, board_z + 0.1), clip)
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


func _process(delta: float) -> void:
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH
		refresh()


func refresh() -> void:
	var store = machine.tool_stock
	if store == null:
		return
	_stow(store)
	for h in holders:
		var id: String = store.holder_id(h.index)
		if id != h.shown:
			_show_holder(h, id)


## Alles, was nicht an der Maschine oder in der Hand ist, kommt in die Halterungen.
func _stow(store: ToolStore) -> void:
	for id in store.items.keys():
		if not _out(str(id)):
			var free := free_holder()
			if free < 0 or not store.place(str(id), free):
				return
	for id in store.spares.keys():
		while store.spare_count(str(id)) > 0:
			var free := free_holder()
			if free < 0:
				return
			store.place_spare(str(id), free)


## Ist ein Stück dieses Werkzeugs gerade an der Maschine oder in der Hand?
func _out(id: String) -> bool:
	return machine.has_tool(id) or _holds(id)


func _holds(id: String) -> bool:
	return player != null and not player.held.is_empty() and player.held["machine"] == machine.MACHINE_ID and player.held["id"] == id


## Nächste freie Halterung, -1 = alle belegt.
func free_holder() -> int:
	var store = machine.tool_stock
	if store == null:
		return -1
	for h in holders:
		if store.holder_id(h.index) == "":
			return h.index
	return -1


## Erste Halterung mit diesem Werkzeug, -1 = keine.
func holder_of(id: String) -> int:
	var store = machine.tool_stock
	if store == null:
		return -1
	for h in holders:
		if store.holder_id(h.index) == id:
			return h.index
	return -1


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
		if p.held["machine"] == machine.MACHINE_ID and id == "":
			store.activate(str(p.held["id"]))
			if store.place(str(p.held["id"]), i):
				p.clear_held()
	elif id != "" and not machine.has_tool(id):
		store.take(i)
		p.set_held(machine, id)
	refresh()


func body_prompt() -> String:
	if player == null:
		return ""
	if not player.carry.is_empty():
		return "Hände voll: Material zuerst ablegen"
	if player.held.is_empty():
		return ""
	if player.held["machine"] != machine.MACHINE_ID:
		return "%s gehört nicht auf diese Werkbank" % player.held["name"]
	return "[Linksklick] %s in die nächste freie Halterung" % player.held["name"] if free_holder() >= 0 else "Alle Halterungen sind belegt"


func body_click(p: Node) -> void:
	if p.held.is_empty() or p.held["machine"] != machine.MACHINE_ID:
		return
	var free := free_holder()
	if free >= 0:
		holder_click(free, p)
