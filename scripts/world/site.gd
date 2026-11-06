class_name Site
extends Node3D
## Gelände aus Kacheln: Werkstatt (Grundhalle, wächst nach Westen) und Lager (wächst nach Norden und
## Osten), jeweils mit Rolltor zum Hof. Wände, Böden und Dächer entstehen aus den gekauften Kacheln.
##
## Lageplan (Z nach unten):  Werkstatt-Kachel 4 x 4 m, Grundhalle X -12..12, Z -8..8
##                           Lager-Kachel 6 x 7,6 m mit Platz für ein Regal, Grund X 12..24, Z -8..-23,2
##                           Hof X 12..34, Z -8..12

const OUTDOOR_LAYER := 2          # Sonne und Himmel treffen nur diese Ebene, nicht das Halleninnere
const W_TILE := 4.0
const L_TILE := Vector2(6.0, 7.6) # zwei Regalfächer je 3 m mit Stützen, dazu ein Quergang
const RACK_SHIFT := 0.6           # Regal steht nach Norden versetzt, im Süden bleibt der Quergang frei
const RACK_POST := 0.08
const RACK_X := 0.55              # Mitte des Regals ab der Kachelkante
const SLOTS_PER_RACK := 6
const RACK_PRICE := 150
const BOARD_Y0 := 0.28            # Oberkante unterster Boden
const BOARD_STEP := 1.1           # 1000 mm lichte Höhe plus Boden und Traverse
const LAGER_X0 := 12.0
const LAGER_Z := -8.0
const LAGER_H := 5.5
const YARD_X1 := 34.0
const YARD_Z1 := 12.0
const WORKSHOP_DOOR_X := 12.15
const LAGER_DOOR_X := 18.0
# Kacheln, die man kaufen kann
const W_CX_MIN := -9
const W_CX_BASE := -3             # westlichste Spalte der Grundhalle
const W_CZ := Vector2i(-5, 3)
const L_CX_MAX := 3
const L_CZ_MAX := 3
const W_PRICE := [500, 100]       # erste Kachel, Aufschlag je weiterer
const L_PRICE := [400, 100]
const LAGER_BASE: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

var world: Node
var door_workshop: RollDoor
var door_lager: RollDoor
var workshop_cells: Array[Vector2i] = []  # gekaufte Kacheln, ohne Grundhalle
var lager_cells: Array[Vector2i] = []     # in Kaufreihenfolge
var rack_cells: Array[Vector2i] = []      # Kachel je gekauftem Regal, daran hängen die Regalnummern
var _tiles: Node3D
var _deliveries: Node3D
var _stored: Node3D
var _areas: Node3D
var _signs: Dictionary = {}       # Regalnummer -> Label3D
var _slot_signs: Dictionary = {}  # Regalplatz -> Label3D am Fach
var _containers: Node3D


## Ein Fach im Lagerregal als Ziel für den Sichtstrahl. Linksklick legt genau dort ab oder zeigt den Bestand.
class RackTarget extends Node:
	var world: Node
	var rack := 0
	var slot := 0

	func get_prompt() -> String:
		return world.rack_prompt(slot)

	func interact(_p: Node) -> void:
		pass

	func click(_p: Node) -> void:
		world.rack_click(slot)


## Spänecontainer im Hof, Ziel für den Sichtstrahl.
class ContainerTarget extends Node:
	var world: Node
	var index := 0

	func get_prompt() -> String:
		return world.container_prompt(index)

	func interact(_p: Node) -> void:
		pass

	func click(_p: Node) -> void:
		world.container_click(index)


## Lieferung im Hof, Ziel für den Sichtstrahl.
class Delivery extends Node:
	var world: Node
	var index := 0

	func get_prompt() -> String:
		return world.delivery_prompt(index)

	func interact(_p: Node) -> void:
		pass

	func click(_p: Node) -> void:
		world.pick_delivery(index)


func _ready() -> void:
	_build_yard()
	_build_lager_front()
	door_workshop = _door("Werkstatt-Rolltor", Vector3(WORKSHOP_DOOR_X, 0, Workshop.DOOR_Z), PI / 2)
	door_lager = _door("Lager-Rolltor", Vector3(LAGER_DOOR_X, 0, LAGER_Z), 0.0)
	_tiles = Node3D.new()
	add_child(_tiles)
	_deliveries = Node3D.new()
	add_child(_deliveries)
	_stored = Node3D.new()
	add_child(_stored)
	_areas = Node3D.new()
	add_child(_areas)
	_containers = Node3D.new()
	add_child(_containers)
	set_tiles([], [])


func _door(title: String, pos: Vector3, rot_y: float) -> RollDoor:
	var d := RollDoor.new()
	d.title = title
	d.position = pos
	d.rotation.y = rot_y
	add_child(d)
	return d


## Sichtbar von außen: nur die Sonne trifft diese Ebene.
func _out(m: MeshInstance3D) -> MeshInstance3D:
	m.layers = OUTDOOR_LAYER
	return m


# ======================================================================= Hof

func _build_yard() -> void:
	var w := YARD_X1 - LAGER_X0
	var d := YARD_Z1 - LAGER_Z
	var asphalt := Build.mat(Color(0.3, 0.3, 0.31), 0.9)
	var yellow := Build.mat(Color(0.95, 0.75, 0.05), 0.6)
	var fence := Build.mat(Color(0.35, 0.42, 0.38), 0.6, 0.3)
	var wall := Build.mat(Color(0.78, 0.8, 0.8), 0.9)
	var cx := LAGER_X0 + w * 0.5
	var cz := LAGER_Z + d * 0.5
	_out(Build.box(self, Vector3(w, 0.2, d), Vector3(cx, -0.1, cz), asphalt, true))
	# Zaun rund um den Hof
	_fence(Vector3(0.1, 2.6, d), Vector3(YARD_X1, 1.3, cz), fence)
	_fence(Vector3(w, 2.6, 0.1), Vector3(cx, 1.3, YARD_Z1), fence)
	_fence(Vector3(0.1, 2.6, YARD_Z1 - Workshop.D / 2.0), Vector3(LAGER_X0, 1.3, (YARD_Z1 + Workshop.D / 2.0) * 0.5), fence)
	var east := LAGER_X0 + L_TILE.x * 2.0
	_fence(Vector3(YARD_X1 - east, 2.6, 0.1), Vector3((YARD_X1 + east) * 0.5, 1.3, LAGER_Z), fence)
	# Außenhaut der Werkstatt mit Aussparung für das Tor
	var x := Workshop.W * 0.5 + 0.31
	var z0 := Workshop.DOOR_Z - RollDoor.WIDTH * 0.5
	var z1 := Workshop.DOOR_Z + RollDoor.WIDTH * 0.5
	var half := Workshop.D * 0.5
	var h := Workshop.H
	_out(Build.box(self, Vector3(0.02, h, z0 + half), Vector3(x, h * 0.5, (z0 - half) * 0.5), wall))
	_out(Build.box(self, Vector3(0.02, h, half - z1), Vector3(x, h * 0.5, (z1 + half) * 0.5), wall))
	_out(Build.box(self, Vector3(0.02, h - RollDoor.HEIGHT, RollDoor.WIDTH), Vector3(x, (h + RollDoor.HEIGHT) * 0.5, Workshop.DOOR_Z), wall))
	Build.label(self, "WERKSTATT", Vector3(x + 0.02, 5.3, Workshop.DOOR_Z), 0.01, Color(0.15, 0.2, 0.3), 96, PI / 2)
	# Wareneingang vor dem Lagertor
	_out(Build.box(self, Vector3(9.0, 0.004, 0.1), Vector3(LAGER_DOOR_X, 0.003, LAGER_Z + 0.4), yellow))
	_out(Build.box(self, Vector3(1.8, 0.8, 0.04), Vector3(LAGER_DOOR_X + 3.9, 2.0, LAGER_Z + 0.2), Build.mat(Color(0.05, 0.35, 0.75), 0.6)))
	Build.label(self, "WARENEINGANG", Vector3(LAGER_DOOR_X + 3.9, 2.0, LAGER_Z + 0.23), 0.0034, Color.WHITE, 48)
	# Tageslicht nur für die Außenebene, sie scheint nicht durch das Hallendach
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.7, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_cull_mask = OUTDOOR_LAYER
	add_child(sun)


## Stabgitterzaun: Pfosten, Riegel und Gitterfeld. Die Kollision ist eine glatte Wand.
func _fence(size: Vector3, pos: Vector3, m: Material) -> void:
	Build.collider(self, size, pos)
	var along_x := size.x > size.z
	var length := size.x if along_x else size.z
	var dir := Vector3.RIGHT if along_x else Vector3.BACK
	var mesh := Build.mat(Color(0.3, 0.38, 0.34, 0.35), 0.6)
	mesh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.cull_mode = BaseMaterial3D.CULL_DISABLED
	_out(Build.box(self, Vector3(length, size.y - 0.1, 0.01) if along_x else Vector3(0.01, size.y - 0.1, length), pos, mesh))
	for y in [0.15, size.y * 0.5, size.y - 0.05]:
		var at := Vector3(pos.x, y, pos.z)
		_out(Build.box(self, Vector3(length, 0.04, 0.03) if along_x else Vector3(0.03, 0.04, length), at, m))
	var n := maxi(int(length / 2.5), 1)
	for i in n + 1:
		var at := pos + dir * (-length * 0.5 + i * length / n)
		_out(Build.box(self, Vector3(0.07, size.y, 0.07), at, m))


## Südwand der zwei Grundkacheln mit Toröffnung, innen und außen getrennt beleuchtet.
func _build_lager_front() -> void:
	var wall := Build.mat(Color(0.82, 0.83, 0.82), 0.9)
	var clad := Build.mat(Color(0.78, 0.8, 0.8), 0.9)
	var x1 := LAGER_X0 + L_TILE.x * 2.0
	var dx0 := LAGER_DOOR_X - RollDoor.WIDTH * 0.5
	var dx1 := LAGER_DOOR_X + RollDoor.WIDTH * 0.5
	for t in [[LAGER_X0, dx0], [dx1, x1]]:
		var len_x: float = t[1] - t[0]
		var cx: float = (t[0] + t[1]) * 0.5
		Build.box(self, Vector3(len_x, LAGER_H, 0.3), Vector3(cx, LAGER_H * 0.5, LAGER_Z), wall, true)
		_out(Build.box(self, Vector3(len_x, LAGER_H, 0.02), Vector3(cx, LAGER_H * 0.5, LAGER_Z + 0.16), clad))
	var top := LAGER_H - RollDoor.HEIGHT
	Build.box(self, Vector3(RollDoor.WIDTH, top, 0.3), Vector3(LAGER_DOOR_X, RollDoor.HEIGHT + top * 0.5, LAGER_Z), wall)
	_out(Build.box(self, Vector3(RollDoor.WIDTH, top, 0.02), Vector3(LAGER_DOOR_X, RollDoor.HEIGHT + top * 0.5, LAGER_Z + 0.16), clad))
	Build.label(self, "LAGER", Vector3(LAGER_DOOR_X, 5.0, LAGER_Z + 0.18), 0.01, Color(0.15, 0.2, 0.3), 96)


# ======================================================================= Kacheln

## Rechteck einer Werkstatt-Kachel (x, z).
static func w_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x * W_TILE, c.y * W_TILE, W_TILE, W_TILE)


## Rechteck einer Lager-Kachel (x, z). Spalte nach Osten, Reihe nach Norden.
static func l_rect(c: Vector2i) -> Rect2:
	return Rect2(LAGER_X0 + c.x * L_TILE.x, LAGER_Z - (c.y + 1) * L_TILE.y, L_TILE.x, L_TILE.y)


static func is_base_workshop(c: Vector2i) -> bool:
	return c.x >= W_CX_BASE and c.x <= 2 and c.y >= -2 and c.y <= 1


func has_cell(area: String, c: Vector2i) -> bool:
	if area == "workshop":
		return is_base_workshop(c) or workshop_cells.has(c)
	return lager_cells.has(c)


## Kann diese Kachel als Nächstes gekauft werden? Sie muss an den Bereich angrenzen.
func can_buy(area: String, c: Vector2i) -> bool:
	if has_cell(area, c):
		return false
	if area == "workshop":
		if c.x < W_CX_MIN or c.x >= W_CX_BASE or c.y < W_CZ.x or c.y > W_CZ.y:
			return false
	elif c.x < 0 or c.x > L_CX_MAX or c.y < 0 or c.y > L_CZ_MAX:
		return false
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if has_cell(area, c + d):
			return true
	return false


func tile_price(area: String) -> int:
	var p: Array = W_PRICE if area == "workshop" else L_PRICE
	var bought: int = workshop_cells.size() if area == "workshop" else lager_cells.size() - LAGER_BASE.size()
	return p[0] + p[1] * bought


## Liegt das Rechteck ganz auf Werkstatt-Kacheln?
func in_workshop(r: Rect2) -> bool:
	var step := 0.5
	var x := r.position.x
	while true:
		var z := r.position.y
		while true:
			var c := Vector2i(int(floor(x / W_TILE)), int(floor(z / W_TILE)))
			if not has_cell("workshop", c):
				return false
			if z >= r.end.y - 0.001:
				break
			z = minf(z + step, r.end.y - 0.001)
		if x >= r.end.x - 0.001:
			break
		x = minf(x + step, r.end.x - 0.001)
	return true


## Kacheln und Regale setzen und alles daraus neu aufbauen. Das Lager hat immer seine Grundkacheln.
func set_tiles(workshop: Array, lager: Array, racks: Array = []) -> void:
	workshop_cells.clear()
	for c in workshop:
		if not workshop_cells.has(c):
			workshop_cells.append(c)
	lager_cells.clear()
	for c in LAGER_BASE:
		lager_cells.append(c)
	for c in lager:
		if not lager_cells.has(c):
			lager_cells.append(c)
	rack_cells.clear()
	for c in racks:
		if lager_cells.has(c) and not rack_cells.has(c):
			rack_cells.append(c)
	_rebuild_tiles()


func buy_cell(area: String, c: Vector2i) -> void:
	if area == "workshop":
		workshop_cells.append(c)
	else:
		lager_cells.append(c)
	_rebuild_tiles()


func _rebuild_tiles() -> void:
	for k in _tiles.get_children():
		_tiles.remove_child(k)
		k.free()
	_signs.clear()
	_slot_signs.clear()
	for c in workshop_cells:
		_workshop_tile(c)
	for row in range(-2, 2):
		var edge := Vector2i(W_CX_BASE, row)
		if not has_cell("workshop", edge + Vector2i.LEFT):
			_workshop_wall(edge, Vector2i.LEFT)
	for c in lager_cells:
		_lager_tile(c)
	for i in rack_cells.size():
		var c: Vector2i = rack_cells[i]
		var at := rack_center(c)
		_rack(Vector3(at.x, 0, at.y), i, 1.0 if c.x % 2 == 0 else -1.0)


func _workshop_tile(c: Vector2i) -> void:
	var r := w_rect(c)
	var ctr := r.get_center()
	var h := Workshop.H
	Build.box(_tiles, Vector3(W_TILE, 0.4, W_TILE), Vector3(ctr.x, -0.2, ctr.y), Build.mat(Color(0.42, 0.46, 0.45), 0.42), true)
	Build.box(_tiles, Vector3(W_TILE, 0.3, W_TILE), Vector3(ctr.x, h + 0.15, ctr.y), Build.mat(Color(0.32, 0.33, 0.35), 0.9))
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not has_cell("workshop", c + d):
			_workshop_wall(c, d)
	# Jede zweite Kachel bekommt eine Leuchte
	if posmod(c.x + c.y, 2) == 0:
		Build.box(_tiles, Vector3(1.32, 0.02, 0.28), Vector3(ctr.x, h - 0.8, ctr.y), Build.emissive(Color(1.0, 0.98, 0.94), 4.0))
		_light(Vector3(ctr.x, h - 1.1, ctr.y), 1.1, 9.0)


func _workshop_wall(c: Vector2i, d: Vector2i) -> void:
	var r := w_rect(c)
	var ctr := r.get_center()
	var h := Workshop.H
	var along_x := d.y != 0
	var size := Vector3(W_TILE, h, 0.3) if along_x else Vector3(0.3, h, W_TILE)
	var at := Vector3(ctr.x + d.x * (W_TILE * 0.5 + 0.15), h * 0.5, ctr.y + d.y * (W_TILE * 0.5 + 0.15))
	Build.box(_tiles, size, at, Build.mat(Color(0.86, 0.87, 0.86), 0.9), true)
	var low := Vector3(W_TILE, 1.2, 0.04) if along_x else Vector3(0.04, 1.2, W_TILE)
	var low_at := Vector3(ctr.x + d.x * (W_TILE * 0.5 - 0.02), 0.6, ctr.y + d.y * (W_TILE * 0.5 - 0.02))
	Build.box(_tiles, low, low_at, Build.mat(Color(0.24, 0.27, 0.30), 0.8))


func _light(pos: Vector3, energy: float, reach: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = Color(1.0, 0.97, 0.92)
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.2
	_tiles.add_child(l)


## Lager-Kachel: Boden, Dach, Wände außen und Licht.
func _lager_tile(c: Vector2i) -> void:
	var r := l_rect(c)
	var ctr := r.get_center()
	Build.box(_tiles, Vector3(r.size.x, 0.2, r.size.y), Vector3(ctr.x, -0.1, ctr.y), Build.mat(Color(0.42, 0.43, 0.43), 0.8), true)
	Build.box(_tiles, Vector3(r.size.x, 0.2, r.size.y), Vector3(ctr.x, LAGER_H + 0.1, ctr.y), Build.mat(Color(0.32, 0.33, 0.35), 0.9))
	var wall := Build.mat(Color(0.82, 0.83, 0.82), 0.9)
	if not has_cell("lager", c + Vector2i.LEFT):
		Build.box(_tiles, Vector3(0.3, LAGER_H, r.size.y), Vector3(r.position.x - 0.15, LAGER_H * 0.5, ctr.y), wall, true)
	if not has_cell("lager", c + Vector2i.RIGHT):
		Build.box(_tiles, Vector3(0.3, LAGER_H, r.size.y), Vector3(r.end.x + 0.15, LAGER_H * 0.5, ctr.y), wall, true)
	# Reihen wachsen nach Norden: Vector2i.DOWN (Reihe + 1) ist die Nordseite
	if not has_cell("lager", c + Vector2i.DOWN):
		Build.box(_tiles, Vector3(r.size.x, LAGER_H, 0.3), Vector3(ctr.x, LAGER_H * 0.5, r.position.y), wall, true)
	# Südseite der Grundkacheln ist die feste Torwand
	if c.y == 0 and c.x >= 2:
		Build.box(_tiles, Vector3(r.size.x, LAGER_H, 0.3), Vector3(ctr.x, LAGER_H * 0.5, LAGER_Z), wall, true)
		_out(Build.box(_tiles, Vector3(r.size.x, LAGER_H, 0.02), Vector3(ctr.x, LAGER_H * 0.5, LAGER_Z + 0.16), Build.mat(Color(0.78, 0.8, 0.8), 0.9)))
	elif c.y > 0 and not has_cell("lager", c + Vector2i.UP):
		Build.box(_tiles, Vector3(r.size.x, LAGER_H, 0.3), Vector3(ctr.x, LAGER_H * 0.5, r.end.y), wall, true)
	Build.box(_tiles, Vector3(1.32, 0.03, 0.28), Vector3(ctr.x, LAGER_H - 0.3, ctr.y), Build.emissive(Color(1.0, 0.98, 0.94), 4.0))
	_light(Vector3(ctr.x, LAGER_H - 0.6, ctr.y), 1.6, 10.0)


## Kachel unter einem Punkt (x, z) im Lager.
static func l_cell_at(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - LAGER_X0) / L_TILE.x)), int(floor((LAGER_Z - p.y) / L_TILE.y)))


## Mitte des Regals einer Kachel (x, z). Gerade Spalten: Regal an der Westkante.
static func rack_center(c: Vector2i) -> Vector2:
	return Vector2(_rack_x(c), l_rect(c).get_center().y - RACK_SHIFT)


## Grundfläche des Regals einer Kachel.
static func rack_rect(c: Vector2i) -> Rect2:
	var size := Vector2(Storage.BOARD_D * 0.001 + 0.16, (Storage.BOARD_L * 0.001 + RACK_POST) * 2.0 + RACK_POST)
	return Rect2(rack_center(c) - size * 0.5, size)


## Grund, warum auf dieser Kachel kein Regal stehen kann. moving = umgestelltes Regal, sonst -1.
func rack_error(c: Vector2i, moving := -1) -> String:
	if not lager_cells.has(c):
		return "Lagerregale stehen im Lager, jede Kachel hat Platz für eines."
	var i := rack_cells.find(c)
	if i >= 0 and i != moving:
		return "Auf dieser Kachel steht schon ein Regal."
	return ""


func add_rack(c: Vector2i) -> void:
	rack_cells.append(c)
	_rebuild_tiles()


func move_rack(i: int, c: Vector2i) -> void:
	rack_cells[i] = c
	_rebuild_tiles()


static func _rack_x(c: Vector2i) -> float:
	var r := l_rect(c)
	return r.position.x + RACK_X if c.x % 2 == 0 else r.end.x - RACK_X


## Regal mit 6 Fächern: 2 nebeneinander auf je 3 Böden (Maße in Storage). Fach 1 und 2 unten, 5 und 6 oben.
## Jedes Fach ist ein eigenes Ziel für den Sichtstrahl und trägt seine Nummer an der Traverse.
## aisle: Richtung zum Gang, dort hängt das Schild.
func _rack(pos: Vector3, rack: int, aisle: float) -> void:
	var up := Build.mat(Color(0.14, 0.3, 0.55), 0.5)
	var beam := Build.mat(Color(0.95, 0.45, 0.08), 0.5)
	var board := Build.mat(Color(0.5, 0.5, 0.5), 0.8)
	var depth := Storage.BOARD_D * 0.001
	var bay := Storage.BOARD_L * 0.001 + RACK_POST
	var length := bay * 2.0
	var post_x := depth * 0.5 + RACK_POST * 0.5
	for dz in [-bay, 0.0, bay]:
		for dx in [-post_x, post_x]:
			Build.box(_tiles, Vector3(RACK_POST, 3.6, RACK_POST), pos + Vector3(dx, 1.8, dz), up)
	for y in [BOARD_Y0, BOARD_Y0 + BOARD_STEP, BOARD_Y0 + BOARD_STEP * 2.0]:
		Build.box(_tiles, Vector3(depth, 0.03, length), pos + Vector3(0, y - 0.015, 0), board)
		for dx in [-post_x, post_x]:
			Build.box(_tiles, Vector3(0.06, 0.1, length), pos + Vector3(dx, y - 0.05, 0), beam)
	for n in SLOTS_PER_RACK:
		var shelf := n / 2
		var side := -0.5 if n % 2 == 0 else 0.5
		var y0: float = 0.0 if shelf == 0 else BOARD_Y0 + BOARD_STEP * shelf
		var y1: float = 3.6 if shelf == 2 else BOARD_Y0 + BOARD_STEP * (shelf + 1)
		var hit := Build.collider(_tiles, Vector3(depth + 0.16, y1 - y0, bay + RACK_POST * 0.5), pos + Vector3(0, (y0 + y1) * 0.5, side * (bay + RACK_POST * 0.5)))
		var target := RackTarget.new()
		target.world = world
		target.rack = rack
		target.slot = rack * SLOTS_PER_RACK + n
		_tiles.add_child(target)
		hit.set_meta("interact", target)
		# Kleines Schild am Fach, an der Traverse zur Gangseite: Nummer und Inhalt
		var at := pos + Vector3(aisle * (post_x + 0.04), BOARD_Y0 + BOARD_STEP * shelf - 0.05, side * bay)
		Build.box(_tiles, Vector3(0.012, 0.13, 0.9), at, Build.mat(Color(0.95, 0.95, 0.92), 0.7))
		var plate := Build.label(_tiles, "Fach %d" % (n + 1), at + Vector3(aisle * 0.009, 0, 0), 0.0015, Color(0.05, 0.05, 0.08), 32, PI / 2 * aisle)
		plate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		plate.width = 0.86 / plate.pixel_size
		_slot_signs[target.slot] = plate
	# Schild an der Gangseite der Mittelstütze
	var sign_at := pos + Vector3(aisle * (post_x + 0.07), 1.75, 0)
	Build.box(_tiles, Vector3(0.02, 1.0, 1.2), sign_at, Build.mat(Color(0.93, 0.93, 0.9), 0.8))
	var label := Build.label(_tiles, "", sign_at + Vector3(aisle * 0.015, 0, 0), 0.0018, Color(0.08, 0.08, 0.1), 32, PI / 2 * aisle)
	# Lange Einträge brechen um, statt über das Schild zu laufen
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = 1.1 / label.pixel_size
	_signs[rack] = label


func capacity() -> int:
	return rack_cells.size() * SLOTS_PER_RACK


## Regalplätze eines Regals.
static func rack_slots(rack: int) -> Array:
	var out := []
	for i in SLOTS_PER_RACK:
		out.append(rack * SLOTS_PER_RACK + i)
	return out


## Mitte der Oberkante von Regalplatz i.
func _slot_pos(i: int) -> Vector3:
	var a := _slot_address(i)
	var c: Vector2i = rack_cells[a["rack"]]
	var bay := Storage.BOARD_L * 0.001 + RACK_POST
	var z: float = rack_center(c).y + (-0.5 if a["bay"] == 0 else 0.5) * bay
	return Vector3(_rack_x(c), BOARD_Y0 + a["shelf"] * BOARD_STEP, z)


static func _slot_address(i: int) -> Dictionary:
	var n := i % SLOTS_PER_RACK
	return {"rack": i / SLOTS_PER_RACK, "shelf": n / 2, "bay": n % 2}


## Name eines Regalplatzes für die Anzeige.
static func slot_name(i: int) -> String:
	if i < 0:
		return "ohne Platz"
	var a := _slot_address(i)
	return "Regal %d, Fach %d" % [a["rack"] + 1, i % SLOTS_PER_RACK + 1]


# ======================================================================= Maschinenbereiche

## Gelbe Markierungen neu zeichnen.
func show_areas(layout: Layout) -> void:
	for k in _areas.get_children():
		_areas.remove_child(k)
		k.free()
	var yellow := Build.mat(Color(0.95, 0.75, 0.05), 0.6)
	for id in layout.machines:
		var r := layout.area_of(id)
		Workshop.rect_marking(_areas, r.position, r.end, yellow)


# ======================================================================= Lieferungen und Lager

## Stellplatz des i-ten Spänecontainers am Ostzaun des Hofs.
static func container_pos(i: int) -> Vector3:
	return Vector3(YARD_X1 - 1.7, 0.0, -4.5 + i * 4.5)


## Spänecontainer im Hof zeichnen: Absetzmulde mit schrägen Stirnseiten, Rippen und Schild zum Hof hin.
func show_containers(list: Array) -> void:
	for c in _containers.get_children():
		_containers.remove_child(c)
		c.free()
	var blue := Build.mat(Color(0.1, 0.27, 0.62), 0.6, 0.15)
	blue.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rim := Build.mat(Color(0.08, 0.22, 0.52), 0.55, 0.2)
	var inner := Build.mat(Color(0.2, 0.22, 0.25), 0.9)
	var top := Vector2(3.6, 1.9)
	var bottom := Vector2(2.1, 1.5)
	var h := 1.35
	for i in list.size():
		var node := Node3D.new()
		node.position = container_pos(i)
		# Lange Seite zeigt zum Hof, also nach Westen
		node.rotation.y = PI / 2.0
		_containers.add_child(node)
		_out(Build.box(node, Vector3(bottom.x, 0.05, bottom.y), Vector3(0, 0.125, 0), inner))
		_out(Build.tub(node, bottom, top, h - 0.1, Vector3(0, 0.1, 0), blue))
		# Rand oben, Kufen unten
		for sz in [-1.0, 1.0]:
			_out(Build.box(node, Vector3(top.x + 0.08, 0.07, 0.07), Vector3(0, h, sz * top.y * 0.5), rim))
			_out(Build.box(node, Vector3(1.9, 0.1, 0.1), Vector3(0, 0.05, sz * 0.5), rim))
			# Rippen und Griffleiste auf den Längsseiten
			for x in [-1.05, -0.35, 0.35, 1.05]:
				_out(Build.box(node, Vector3(0.05, h - 0.2, 0.03), Vector3(x * 0.92, h * 0.55, sz * (top.y * 0.5 - 0.085)), rim, false, Vector3(sz * 0.09, 0, 0)))
			_out(Build.box(node, Vector3(2.6, 0.05, 0.05), Vector3(0, h - 0.33, sz * (top.y * 0.5 - 0.05)), rim))
		for sx in [-1.0, 1.0]:
			_out(Build.box(node, Vector3(0.07, 0.07, top.y + 0.08), Vector3(sx * top.x * 0.5, h, 0), rim))
			_out(Build.cyl(node, 0.05, 0.14, Vector3(sx * (top.x * 0.5 - 0.1), h - 0.25, top.y * 0.5 + 0.03), rim, Build.AXIS_Z))
		var chips: ChipTray = list[i]
		if chips.kg > 0.001:
			# Oberfläche der Späne, so groß wie die Mulde in dieser Höhe
			var f := clampf(chips.fraction(), 0.02, 0.95)
			var size := bottom.lerp(top, f) - Vector2(0.06, 0.06)
			var chip_m := Build.mat(Color(0.6, 0.62, 0.66), 0.6, 0.2)
			_out(Build.box(node, Vector3(size.x, 0.03, size.y), Vector3(0, 0.1 + (h - 0.1) * f, 0), chip_m))
			_out(Build.sphere(node, 0.5, Vector3(0, 0.1 + (h - 0.1) * f, 0), chip_m)).scale = Vector3(size.x * 0.95, 0.3, size.y * 0.95)
		# Schild: welcher Werkstoff hierher gehört, in Sortenfarbe
		var sort := str(chips.only)
		var sign_col: Color = {"stahl": Color(0.75, 0.77, 0.8), "aluminium": Color(0.95, 0.95, 0.95), "messing": Color(0.95, 0.8, 0.3)}.get(sort, Color.WHITE)
		var title := str(ChipTray.SORT_TITLES.get(sort, "Späne")).to_upper()
		var face := -(top.y * 0.5 + 0.09)
		_out(Build.box(node, Vector3(1.5, 0.72, 0.03), Vector3(0, 0.98, face), Build.mat(sign_col, 0.6)))
		_out(Build.box(node, Vector3(1.56, 0.78, 0.015), Vector3(0, 0.98, face + 0.02), Build.mat(Color(0.05, 0.05, 0.06), 0.6)))
		var l := Build.label(node, "NUR %s-\nSPÄNE\n%d %% voll" % [title, int(chips.fraction() * 100.0)], Vector3(0, 0.98, face - 0.02), 0.0042, Color(0.04, 0.04, 0.06), 48, PI)
		l.layers = OUTDOOR_LAYER
		var hit := Build.collider(node, Vector3(top.x, h + 0.05, top.y + 0.2), Vector3(0, (h + 0.05) * 0.5, 0))
		var t := ContainerTarget.new()
		t.world = world
		t.index = i
		node.add_child(t)
		hit.set_meta("interact", t)


## Stücke mit gleichem Werkstoff und gleichen Maßen liegen auf einer Palette.
static func delivery_key(it: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s" % [it["material"], it["kind"], it.get("d", 0.0), it.get("w", 0.0), it.get("h", 0.0), it.get("l", 0.0), it.get("key", "")]


## Paletten aus der Lieferliste: je {"index": erstes Stück, "items": Stücke}.
static func delivery_groups(items: Array) -> Array:
	var order := {}
	var out := []
	for i in items.size():
		var k := delivery_key(items[i])
		if not order.has(k):
			order[k] = out.size()
			out.append({"index": i, "items": []})
		out[order[k]]["items"].append(items[i])
	return out


## Platz der i-ten Palette: im Osten des Hofs, die Wege zu beiden Toren bleiben frei.
static func delivery_pos(i: int) -> Vector3:
	var col := i % 5
	var row := (i / 5) % 5
	var stack := i / 25
	return Vector3(21.6 + col * 1.7, 0.12 + stack * 1.0, LAGER_Z + 2.6 + row * 3.4)


func show_deliveries(items: Array) -> void:
	for c in _deliveries.get_children():
		_deliveries.remove_child(c)
		c.free()
	var groups := delivery_groups(items)
	for g in groups.size():
		var node := Node3D.new()
		node.position = delivery_pos(g)
		_deliveries.add_child(node)
		_pallet(node, groups[g]["items"], int(groups[g]["index"]))


## Palette mit allen Stücken einer Sorte, in Lagen gestapelt. index = erstes Stück in der Lieferliste.
func _pallet(node: Node3D, list: Array, index: int) -> void:
	var first: Dictionary = list[0]
	var wood := Build.mat(Color(0.7, 0.58, 0.4), 0.9)
	var runner := Build.mat(Color(0.58, 0.46, 0.3), 0.9)
	var length := _shown_length(first)
	var round_bar := str(first["kind"]) == Materials.KIND_ROUND
	var w := float(first["d"] if round_bar else first["w"]) * 0.001
	var h := float(first["d"] if round_bar else first["h"]) * 0.001
	var pallet_w := 1.0
	var pallet_l := maxf(length + 0.1, 0.8)
	_out(Build.box(node, Vector3(pallet_w, 0.03, pallet_l), Vector3(0, -0.015, 0), wood))
	for x in [-0.42, 0.0, 0.42]:
		_out(Build.box(node, Vector3(0.1, 0.09, pallet_l), Vector3(x, -0.075, 0), runner))
	var gap := 0.008
	var cols := maxi(int(pallet_w / (w + gap)), 1)
	var rows := maxi(int(pallet_l / (length + gap)), 1)
	var per := cols * rows
	for i in list.size():
		var layer := i / per
		var k := i % per
		var col := k % cols
		var row := k / cols
		var at := Vector3((col - (cols - 1) * 0.5) * (w + gap), layer * (h + 0.002), (row - (rows - 1) * 0.5) * (length + gap))
		_add_item(node, list[i], at, OUTDOOR_LAYER)
	var total := (list.size() - 1) / per + 1
	var top := total * (h + 0.002)
	var hit := Build.collider(node, Vector3(pallet_w, top + 0.12, pallet_l), Vector3(0, (top - 0.12) * 0.5, 0))
	var d := Delivery.new()
	d.world = world
	d.index = index
	node.add_child(d)
	hit.set_meta("interact", d)


func show_stock(items: Array) -> void:
	for c in _stored.get_children():
		_stored.remove_child(c)
		c.free()
	for slot in capacity():
		var here := Storage.on_board(items, slot)
		if here.is_empty():
			continue
		var at := _slot_pos(slot)
		if Storage.is_bar(here[0]):
			var bars := Storage.layout_bars(here)
			for i in bars.size():
				var p: Vector2 = bars[i]
				_add_item(_stored, here[i], at + Vector3(p.x * 0.001, p.y * 0.001, 0), 1)
		else:
			var cuts := Storage.layout_cut(here)
			for i in cuts.size():
				_add_cut(here[i], cuts[i], at)
	_update_signs(items)


## Schilder: was auf welchem Boden liegt.
func _update_signs(items: Array) -> void:
	for rack in _signs:
		var lines: Array[String] = ["REGAL %d" % (rack + 1)]
		for slot in rack_slots(rack):
			var here := Storage.on_board(items, slot)
			if here.is_empty():
				continue
			lines.append("Fach %d: %s" % [slot % SLOTS_PER_RACK + 1, sign_text(here)])
		for slot in rack_slots(rack):
			if _slot_signs.has(slot):
				var here := Storage.on_board(items, slot)
				(_slot_signs[slot] as Label3D).text = "Fach %d: %s" % [slot % SLOTS_PER_RACK + 1, sign_text(here) if not here.is_empty() else "leer"]
		if lines.size() == 1:
			lines.append("leer")
		(_signs[rack] as Label3D).text = "\n".join(lines)


## Inhalt eines Bodens zusammengefasst: 3x S235 Ø60, 2x C45 Ø40
static func sign_text(here: Array) -> String:
	var counts := {}
	for it in here:
		var key := "%s %s" % [Materials.get_material(str(it["material"]))["name"], _section_text(it)]
		counts[key] = int(counts.get(key, 0)) + 1
	var parts: Array[String] = []
	for k in counts:
		parts.append("%dx %s" % [counts[k], k])
	return ", ".join(parts)


static func _section_text(it: Dictionary) -> String:
	match str(it["kind"]):
		Materials.KIND_ROUND:
			return "Ø%d" % int(it["d"])
		Materials.KIND_SQUARE:
			return "%dx%d" % [int(it["w"]), int(it["h"])]
	return "%dx%dx%d" % [int(it["l"]), int(it["w"]), int(it["h"])]


## Außerhalb der Halle gibt es keine Spiegelungen: Reines Metall bliebe dort fast schwarz.
func _item_mat(id: String) -> StandardMaterial3D:
	return Build.mat(Materials.raw_color(id).lerp(Materials.cut_color(id), 0.25), 0.55, 0.2)


## Fertigschnitt an seine Lage auf dem Boden setzen.
func _add_cut(it: Dictionary, place: Dictionary, board: Vector3) -> void:
	var l: float = float(it["w"]) if place["rot"] else float(it["l"])
	var w: float = float(it["l"]) if place["rot"] else float(it["w"])
	var h := float(it["h"]) * 0.001
	var x: float = board.x + (float(place["across"]) + w * 0.5 - Storage.BOARD_D * 0.5) * 0.001
	var z: float = board.z + (float(place["along"]) + l * 0.5 - Storage.BOARD_L * 0.5) * 0.001
	Build.box(_stored, Vector3(w * 0.001, h, l * 0.001), Vector3(x, board.y + h * 0.5, z), _item_mat(str(it["material"])))


static func _shown_length(it: Dictionary) -> float:
	return minf(float(it["l"]) * 0.001, Storage.BOARD_L * 0.001)


## Stück in Werkstofffarbe, längs in Z, liegt auf at. Gibt die Höhe zurück.
func _add_item(parent: Node3D, it: Dictionary, at: Vector3, layer: int) -> float:
	var m := _item_mat(str(it["material"]))
	var l := _shown_length(it)
	var mesh: MeshInstance3D
	var h := 0.0
	if str(it["kind"]) == Materials.KIND_ROUND:
		h = float(it["d"]) * 0.001
		mesh = Build.cyl(parent, h * 0.5, l, at + Vector3(0, h * 0.5, 0), m, Build.AXIS_Z, false, 16)
	else:
		h = float(it["h"]) * 0.001
		mesh = Build.box(parent, Vector3(float(it["w"]) * 0.001, h, l), at + Vector3(0, h * 0.5, 0), m)
	mesh.layers = layer
	return h
