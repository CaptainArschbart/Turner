class_name Site
extends Node3D
## Gelände aus Kacheln: Werkstatt (Grundhalle, wächst nach Westen) und Lager (wächst nach Norden und
## Osten), jeweils mit Rolltor zum Hof. Wände, Böden und Dächer entstehen aus den gekauften Kacheln.
##
## Lageplan (Z nach unten):  Werkstatt-Kachel 4 x 4 m, Grundhalle X -12..12, Z -8..8
##                           Lager-Kachel 6 x 7,6 m mit Platz für ein Regal, Grund X 12..24, Z -8..-23,2
##                           Hof X 12..34, Z -8..12

const OUTDOOR_LAYER := 2          # Sonne und Himmel treffen nur diese Ebene, nicht das Halleninnere
const GOODS_LAYER := 3            # Lieferpaletten: von Sonne und Hallenlicht beleuchtet, sie stehen auch drinnen
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
const PALLET_TOP := 0.22          # Ladefläche der Europalette (models: EUR-Pallet) über dem Boden
const LAGER_H := 5.5
const YARD_X1 := 34.0
const YARD_Z1 := 12.0
const WORKSHOP_DOOR_X := 12.15
const LAGER_DOOR_X := 18.0
const GATE_X := 23.0               # Hoftor im Südzaun, mitten auf der Zufahrt zur Straße
const GATE_W := 9.8                # Torgruppe aus models/fence.glb: Führungsfeld, zwei Flügel, Führungsfeld (9,80 m)
# Kacheln, die man kaufen kann
const W_CX_MIN := -9
const W_CX_BASE := -3             # westlichste Spalte der Grundhalle
const W_CZ := Vector2i(-5, 3)
const L_CX_MAX := 3
const L_CZ_MAX := 3
const W_PRICE := [500, 100]       # erste Kachel, Aufschlag je weiterer
const L_PRICE := [400, 100]
const LAGER_BASE: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
const FENCE_GREEN := Color(0.2, 0.31, 0.24)       # RAL 6005 Moosgrün, wie übliche Stabgitterzäune
const SIGN_ANTHRACITE := Color(0.15, 0.17, 0.2)
const SIGN_BLUE := Color(0.06, 0.3, 0.62)
const SIGN_ORANGE := Color(0.95, 0.45, 0.08)
const RACK_BLUE := Color(0.1, 0.25, 0.52)
const RACK_ORANGE := Color(0.95, 0.42, 0.06)

var world: Node
var door_workshop: RollDoor
var door_lager: RollDoor
var gate: YardGate              # Hoftor: Gelände verlassen, Supermarkt oder nach Hause
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
var sun: DirectionalLight3D     # Sonne bzw. Mond über dem Hof, DayCycle bewegt sie


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
	var asphalt := HallTex.asphalt(Color(0.36, 0.36, 0.37), Vector2.ZERO, 0.3)
	var yellow := Build.mat(Color(0.95, 0.75, 0.05), 0.6)
	var fence := HallTex.powder(FENCE_GREEN, 0.12)
	var wall := Build.mat(Color(0.78, 0.8, 0.8), 0.9)
	var cx := LAGER_X0 + w * 0.5
	var cz := LAGER_Z + d * 0.5
	_out(Build.box(self, Vector3(w, 0.2, d), Vector3(cx, -0.1, cz), asphalt, true))
	# Zaun rund um den Hof
	_fence(Vector3(0.1, 2.6, d), Vector3(YARD_X1, 1.3, cz), fence)
	# Südzaun mit Aussparung für das Hoftor an der Zufahrt
	var g0 := GATE_X - GATE_W * 0.5
	var g1 := GATE_X + GATE_W * 0.5
	_fence(Vector3(g0 - LAGER_X0, 2.6, 0.1), Vector3((LAGER_X0 + g0) * 0.5, 1.3, YARD_Z1), fence)
	_fence(Vector3(YARD_X1 - g1, 2.6, 0.1), Vector3((g1 + YARD_X1) * 0.5, 1.3, YARD_Z1), fence)
	gate = YardGate.new()
	gate.width = GATE_W
	gate.world = world
	gate.position = Vector3(GATE_X, 0, YARD_Z1)
	add_child(gate)
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
	_facade_sign("WERKSTATT", Vector3(x + 0.01, 5.55, Workshop.DOOR_Z), PI / 2, Vector2(4.6, 0.9))
	# Wareneingang vor dem Lagertor
	_out(Build.box(self, Vector3(9.0, 0.004, 0.1), Vector3(LAGER_DOOR_X, 0.003, LAGER_Z + 0.4), yellow))
	_facade_sign("WARENEINGANG", Vector3(LAGER_DOOR_X + 3.9, 2.2, LAGER_Z + 0.17), 0.0, Vector2(1.9, 0.42), SIGN_BLUE)
	# Hofstrahler an Werkstatt und Lager, nachts an (DayCycle)
	var flood := [
		[Vector3(x + 0.25, 5.7, Workshop.DOOR_Z - 4.4), Vector3(20.0, 0.0, -2.0)],
		[Vector3(x + 0.25, 5.7, Workshop.DOOR_Z + 4.0), Vector3(22.0, 0.0, 9.0)],
		[Vector3(LAGER_X0 + 1.6, 4.9, LAGER_Z + 0.35), Vector3(16.0, 0.0, 0.0)],
		[Vector3(LAGER_X0 + 10.6, 4.9, LAGER_Z + 0.35), Vector3(27.0, 0.0, 0.0)],
	]
	var housing := Build.mat(Color(0.18, 0.19, 0.2), 0.5, 0.5)
	for f in flood:
		var at: Vector3 = f[0]
		var aim: Vector3 = f[1]
		var fixture := Node3D.new()
		add_child(fixture)
		fixture.look_at_from_position(at, aim, Vector3.UP)
		_out(Build.box(fixture, Vector3(0.36, 0.26, 0.12), Vector3(0, 0, 0.02), housing))
		var face := Build.box(fixture, Vector3(0.3, 0.2, 0.01), Vector3(0, 0, -0.045), Build.emissive(Color(1.0, 0.95, 0.85), 0.2))
		_out(face)
		face.add_to_group("night_glow")
		face.set_meta("energy", 8.0)
		Surroundings.night_spot(self, at + (aim - at).normalized() * 0.1, aim, Color(1.0, 0.95, 0.88), 6.0, 24.0, 75.0)
	# Tageslicht nur für die Außenebene, sie scheint nicht durch das Hallendach
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.7, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_cull_mask = OUTDOOR_LAYER
	add_child(sun)


## Fassadenschild: Alu-Verbundplatte in Anthrazit (oder Farbe) mit Kantenprofil, farbigem Akzentstreifen links
## und weißer Schrift in der Menüschrift. Vorderseite zeigt nach lokal +Z, rot_y dreht es an die Wand.
func _facade_sign(text: String, pos: Vector3, rot_y: float, size: Vector2, panel := SIGN_ANTHRACITE) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	add_child(n)
	var edge := Build.mat(Color(0.72, 0.74, 0.76), 0.35, 0.8)
	Build.box(n, Vector3(size.x, size.y, 0.04), Vector3(0, 0, 0.02), Build.mat(panel, 0.4, 0.3))
	for e in [-1.0, 1.0]:
		Build.box(n, Vector3(size.x + 0.03, 0.015, 0.05), Vector3(0, e * size.y * 0.5, 0.025), edge)
		Build.box(n, Vector3(0.015, size.y + 0.03, 0.05), Vector3(e * size.x * 0.5, 0, 0.025), edge)
	var accent := size.y * 0.22
	Build.box(n, Vector3(accent, size.y - 0.05, 0.004), Vector3(-size.x * 0.5 + accent * 0.5 + 0.05, 0, 0.042), Build.mat(SIGN_ORANGE if panel != SIGN_ANTHRACITE else SIGN_BLUE.lightened(0.15), 0.4))
	var font_px := 128
	var l := Build.label(n, text, Vector3(accent * 0.5 + 0.03, -size.y * 0.02, 0.045), size.y * 0.46 / font_px, Color(0.97, 0.97, 0.96), font_px)
	l.font = UITheme.font(700, 4)
	l.shaded = true
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = OUTDOOR_LAYER


## Zaun aus dem Modell models/fence.glb (Maschendrahtfeld), sonst Stabgitter aus Bauteilen.
## Die Kollision ist eine glatte Wand.
func _fence(size: Vector3, pos: Vector3, m: Material) -> void:
	Build.collider(self, size, pos)
	var along_x := size.x > size.z
	var half := Vector3(size.x * 0.5, 0, 0) if along_x else Vector3(0, 0, size.z * 0.5)
	if fence_run(self, Vector3(pos.x, 0, pos.z) - half, Vector3(pos.x, 0, pos.z) + half):
		return
	var length := size.x if along_x else size.z
	var dir := Vector3.RIGHT if along_x else Vector3.BACK
	var mesh := HallTex.fence_mesh(FENCE_GREEN.lightened(0.05))
	var panel_h := size.y - 0.15
	_out(Build.box(self, Vector3(length, panel_h, 0.008) if along_x else Vector3(0.008, panel_h, length), Vector3(pos.x, 0.08 + panel_h * 0.5, pos.z), mesh))
	var n := maxi(int(length / 2.5), 1)
	var foot := Build.mat(Color(0.45, 0.46, 0.46), 0.8)
	for i in n + 1:
		var at := pos + dir * (-length * 0.5 + i * length / n)
		_out(Build.box(self, Vector3(0.06, size.y, 0.06), at, m))
		_out(Build.box(self, Vector3(0.08, 0.02, 0.08), Vector3(at.x, size.y + 0.01, at.z), m))
		_out(Build.box(self, Vector3(0.16, 0.012, 0.16), Vector3(at.x, 0.006, at.z), foot))
		# Klemmhalter, mit denen die Felder am Pfosten hängen
		for y in [0.4, size.y * 0.5, size.y - 0.3]:
			_out(Build.box(self, Vector3(0.09, 0.05, 0.035) if along_x else Vector3(0.035, 0.05, 0.09), Vector3(at.x, y, at.z), m))


const FENCE_MODEL := "res://models/fence.glb"
## Teile im Modell (Namen aus Blender). Alles liegt dort entlang Z; beim Laden wird es so gedreht,
## dass die Länge entlang X liegt. PLAYER_SIZE_IGNORE im Modell ist nur der Größenvergleich.
const FENCE_NODE := "Cube_003"                        # einzelnes Zaunfeld
const GATE_NODES: Array[String] = ["Cube_015", "Cube_018"]   # die beiden Torflügel
## Torgruppe in Modell-Reihenfolge: Zaunfeld mit silbernen Führungen, Flügel, Flügel, Zaunfeld mit Führungen
const GATE_UNIT: Array[String] = ["Cube_007", "Cube_015", "Cube_018", "Cube_012"]
static var _fence_scene: Node                          # instanziertes Modell, nur zum Auslesen
static var _pieces: Dictionary = {}                   # Name -> {"mesh", "xf", "box"}


## Ein Teil aus dem Modell: Mesh, Lage im Modell (Länge entlang X gedreht) und Maße danach. Leer, wenn es fehlt.
static func _piece(node_name: String) -> Dictionary:
	if _pieces.has(node_name):
		return _pieces[node_name]
	if _fence_scene == null:
		if not ResourceLoader.exists(FENCE_MODEL):
			return {}
		var ps := load(FENCE_MODEL) as PackedScene
		if ps == null:
			return {}
		_fence_scene = ps.instantiate()
	var out := {}
	var mi := _fence_scene.find_child(node_name, true, false) as MeshInstance3D
	if mi != null and mi.mesh != null:
		var xf := mi.transform
		var n := mi.get_parent()
		while n != null and n != _fence_scene:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		# Im Modell zeigt die Länge nach +Z: um +90° drehen, dann zeigt sie nach +X
		var box := xf * mi.mesh.get_aabb()
		if box.size.z > box.size.x:
			xf = Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO) * xf
		out = {"mesh": mi.mesh, "xf": xf, "box": xf * mi.mesh.get_aabb()}
	_pieces[node_name] = out
	return out


## Teil als MeshInstance3D: entlang X auf die Länge `length` gestreckt, Anfang bei x0 = 0, mittig in Z.
## box: Bezugsmaße (für das Tor die beider Flügel zusammen). height > 0 staucht auf diese Höhe.
static func _place_piece(parent: Node3D, p: Dictionary, box: AABB, at: Transform3D, length: float, height := 0.0) -> MeshInstance3D:
	var sx := length / box.size.x
	var sy := height / box.end.y if height > 0.0 else 1.0
	var zc := box.position.z + box.size.z * 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = p["mesh"]
	mi.transform = at * Transform3D(Basis.from_scale(Vector3(sx, sy, 1)), Vector3(-box.position.x * sx, 0, -zc)) * p["xf"]
	mi.layers = OUTDOOR_LAYER
	parent.add_child(mi)
	return mi


## Zaunfelder aus dem Modell von a nach b (am Boden) aneinanderreihen, jedes Feld leicht gestreckt oder
## gestaucht, damit die Strecke genau aufgeht; height > 0 staucht auf diese Höhe. Sichtbar nur für die
## Außenebene. false, wenn das Modell fehlt.
static func fence_run(parent: Node3D, a: Vector3, b: Vector3, height := 0.0) -> bool:
	var p := _piece(FENCE_NODE)
	if p.is_empty():
		return false
	var run := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := run.length()
	if length < 0.05:
		return true
	var box: AABB = p["box"]
	var n := maxi(int(round(length / box.size.x)), 1)
	var basis := Basis(Vector3.UP, atan2(-run.z, run.x))   # Modell-X zeigt entlang der Strecke
	for i in n:
		_place_piece(parent, p, box, Transform3D(basis, a + run * (float(i) / n)), length / n, height)
	return true


## Torgruppe aus dem Modell genau so, wie sie dort zueinander liegt: Führungsfeld, zwei Flügel,
## Führungsfeld. Mittig um den Ursprung von parent entlang X, auf `width` gebracht; die Zaunlinie (Mitte
## eines normalen Feldes) liegt bei z = 0, die Flügel hängen wie im Modell vor den Führungen.
## Gibt die Maße der Flügel in parent zurück, leer (size 0), wenn das Modell fehlt.
static func gate_model(parent: Node3D, width: float) -> AABB:
	var line := _piece(FENCE_NODE)
	if line.is_empty():
		return AABB()
	var parts := []
	var box := AABB()
	for node_name in GATE_UNIT:
		var p := _piece(node_name)
		if p.is_empty():
			return AABB()
		box = p["box"] if parts.is_empty() else box.merge(p["box"])
		parts.append(p)
	var line_box: AABB = line["box"]
	var zc := line_box.position.z + line_box.size.z * 0.5
	var sx := width / box.size.x
	var at := Transform3D(Basis.from_scale(Vector3(sx, 1, 1)), Vector3(-width * 0.5 - box.position.x * sx, 0, -zc))
	var leaves := AABB()
	for i in parts.size():
		var p: Dictionary = parts[i]
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.transform = at * p["xf"]
		mi.layers = OUTDOOR_LAYER
		parent.add_child(mi)
		if GATE_NODES.has(GATE_UNIT[i]):
			var b: AABB = at * (p["box"] as AABB)
			leaves = b if leaves.size == Vector3.ZERO else leaves.merge(b)
	return leaves


## Südwand der zwei Grundkacheln mit Toröffnung, innen und außen getrennt beleuchtet.
func _build_lager_front() -> void:
	var wall := HallTex.wall()
	var clad := Build.mat(Color(0.78, 0.8, 0.8), 0.9)
	var x1 := LAGER_X0 + L_TILE.x * 2.0
	var dx0 := LAGER_DOOR_X - RollDoor.WIDTH * 0.5
	var dx1 := LAGER_DOOR_X + RollDoor.WIDTH * 0.5
	for t in [[LAGER_X0, dx0], [dx1, x1]]:
		var len_x: float = t[1] - t[0]
		var cx: float = (t[0] + t[1]) * 0.5
		Build.box(self, Vector3(len_x, LAGER_H, 0.3), Vector3(cx, LAGER_H * 0.5, LAGER_Z), wall, true)
		_out(Build.box(self, Vector3(len_x, LAGER_H, 0.02), Vector3(cx, LAGER_H * 0.5, LAGER_Z + 0.16), clad))
		_wall_base(self, Vector3(len_x, 0, 0), Vector3(cx, 0, LAGER_Z - 0.15), Vector3.FORWARD)
	var top := LAGER_H - RollDoor.HEIGHT
	Build.box(self, Vector3(RollDoor.WIDTH, top, 0.3), Vector3(LAGER_DOOR_X, RollDoor.HEIGHT + top * 0.5, LAGER_Z), wall)
	_out(Build.box(self, Vector3(RollDoor.WIDTH, top, 0.02), Vector3(LAGER_DOOR_X, RollDoor.HEIGHT + top * 0.5, LAGER_Z + 0.16), clad))
	_facade_sign("LAGER", Vector3(LAGER_DOOR_X, 5.0, LAGER_Z + 0.17), 0.0, Vector2(2.8, 0.66))


## Betonsockel mit Abschlussprofil an der Innenseite einer Wand, wie in der Werkstatt. length: Wandlänge in x
## (oder z, wenn inward entlang x zeigt), face: Mitte der Innenfläche auf dem Boden, inward: Richtung in den Raum.
func _wall_base(parent: Node3D, length: Vector3, face: Vector3, inward: Vector3) -> void:
	var l := maxf(length.x, length.z)
	var along_x := absf(inward.z) > 0.5
	var low := Vector3(l, 1.2, 0.04) if along_x else Vector3(0.04, 1.2, l)
	Build.box(parent, low, face + inward * 0.02 + Vector3(0, 0.6, 0), HallTex.concrete())
	var trim := Vector3(l, 0.05, 0.07) if along_x else Vector3(0.07, 0.05, l)
	Build.box(parent, trim, face + inward * 0.035 + Vector3(0, 1.225, 0), Build.mat(Color(0.2, 0.22, 0.24), 0.45, 0.6))


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


## Liegt die Fläche ganz im Lager?
func in_lager(r: Rect2) -> bool:
	for p in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end, r.get_center()]:
		var q: Vector2 = p.clamp(r.position, r.end - Vector2(0.001, 0.001))
		if not lager_cells.has(l_cell_at(q)):
			return false
	return true


## Liegt die Fläche ganz im Hof, mit Abstand zu Zaun und Gebäudewänden?
func in_yard(r: Rect2) -> bool:
	return Rect2(LAGER_X0 + 0.4, LAGER_Z + 0.4, YARD_X1 - LAGER_X0 - 0.8, YARD_Z1 - LAGER_Z - 0.8).encloses(r)


## Überschneidet die Fläche ein Lagerregal?
func blocked_by_rack(r: Rect2) -> bool:
	for c in rack_cells:
		if r.intersects(rack_rect(c)):
			return true
	return false


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
	# Boden, Decke und Dachträger wie in der Grundhalle: Die Träger laufen in Z über die Kachelmitte
	Build.box(_tiles, Vector3(W_TILE, 0.4, W_TILE), Vector3(ctr.x, -0.2, ctr.y), HallTex.floor_world(), true)
	Build.box(_tiles, Vector3(W_TILE, 0.3, W_TILE), Vector3(ctr.x, h + 0.15, ctr.y), HallTex.ceiling())
	Build.box(_tiles, Vector3(0.25, 0.5, W_TILE), Vector3(ctr.x, h - 0.25, ctr.y), Build.mat(Color(0.20, 0.28, 0.36), 0.55, 0.3))
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not has_cell("workshop", c + d):
			_workshop_wall(c, d)
	# Hallenleuchte zwischen zwei Trägern wie in der Grundhalle: an der Kachelkante zum Nachbarn hin, damit
	# die Seile weder an der Wand noch am Träger hängen. Ohne Nachbarn in X hängt sie längs neben dem Träger.
	var lx := ctr.x + 1.0
	var yaw := PI / 2.0
	if has_cell("workshop", c + Vector2i.RIGHT):
		lx = r.end.x
		yaw = 0.0
	elif has_cell("workshop", c + Vector2i.LEFT):
		lx = r.position.x
		yaw = 0.0
	var low := Props.ceiling_lamp(_tiles, lx, h, ctr.y, yaw)
	_light(Vector3(lx, low - 0.3, ctr.y), 0.9, 9.0)


func _workshop_wall(c: Vector2i, d: Vector2i) -> void:
	var r := w_rect(c)
	var ctr := r.get_center()
	var h := Workshop.H
	var along_x := d.y != 0
	var size := Vector3(W_TILE, h, 0.3) if along_x else Vector3(0.3, h, W_TILE)
	var at := Vector3(ctr.x + d.x * (W_TILE * 0.5 + 0.15), h * 0.5, ctr.y + d.y * (W_TILE * 0.5 + 0.15))
	Build.box(_tiles, size, at, HallTex.wall(), true)
	var low := Vector3(W_TILE, 1.2, 0.04) if along_x else Vector3(0.04, 1.2, W_TILE)
	var low_at := Vector3(ctr.x + d.x * (W_TILE * 0.5 - 0.02), 0.6, ctr.y + d.y * (W_TILE * 0.5 - 0.02))
	Build.box(_tiles, low, low_at, HallTex.concrete())
	var trim := Vector3(W_TILE, 0.05, 0.07) if along_x else Vector3(0.07, 0.05, W_TILE)
	var trim_at := Vector3(ctr.x + d.x * (W_TILE * 0.5 - 0.035), 1.225, ctr.y + d.y * (W_TILE * 0.5 - 0.035))
	Build.box(_tiles, trim, trim_at, Build.mat(Color(0.2, 0.22, 0.24), 0.45, 0.6))


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
	Build.box(_tiles, Vector3(r.size.x, 0.2, r.size.y), Vector3(ctr.x, -0.1, ctr.y), HallTex.screed(), true)
	Build.box(_tiles, Vector3(r.size.x, 0.2, r.size.y), Vector3(ctr.x, LAGER_H + 0.1, ctr.y), HallTex.ceiling())
	# Dachträger quer über die Kachelmitte
	Build.box(_tiles, Vector3(r.size.x, 0.45, 0.22), Vector3(ctr.x, LAGER_H - 0.225, ctr.y), Build.mat(Color(0.20, 0.28, 0.36), 0.55, 0.3))
	var wall := HallTex.wall()
	if not has_cell("lager", c + Vector2i.LEFT):
		Build.box(_tiles, Vector3(0.3, LAGER_H, r.size.y), Vector3(r.position.x - 0.15, LAGER_H * 0.5, ctr.y), wall, true)
		_wall_base(_tiles, Vector3(0, 0, r.size.y), Vector3(r.position.x, 0, ctr.y), Vector3.RIGHT)
	if not has_cell("lager", c + Vector2i.RIGHT):
		Build.box(_tiles, Vector3(0.3, LAGER_H, r.size.y), Vector3(r.end.x + 0.15, LAGER_H * 0.5, ctr.y), wall, true)
		_wall_base(_tiles, Vector3(0, 0, r.size.y), Vector3(r.end.x, 0, ctr.y), Vector3.LEFT)
	# Reihen wachsen nach Norden: Vector2i.DOWN (Reihe + 1) ist die Nordseite
	if not has_cell("lager", c + Vector2i.DOWN):
		Build.box(_tiles, Vector3(r.size.x, LAGER_H, 0.3), Vector3(ctr.x, LAGER_H * 0.5, r.position.y), wall, true)
		_wall_base(_tiles, Vector3(r.size.x, 0, 0), Vector3(ctr.x, 0, r.position.y + 0.15), Vector3.BACK)
	# Südseite der Grundkacheln ist die feste Torwand
	if c.y == 0 and c.x >= 2:
		Build.box(_tiles, Vector3(r.size.x, LAGER_H, 0.3), Vector3(ctr.x, LAGER_H * 0.5, LAGER_Z), wall, true)
		_out(Build.box(_tiles, Vector3(r.size.x, LAGER_H, 0.02), Vector3(ctr.x, LAGER_H * 0.5, LAGER_Z + 0.16), Build.mat(Color(0.78, 0.8, 0.8), 0.9)))
		_wall_base(_tiles, Vector3(r.size.x, 0, 0), Vector3(ctr.x, 0, LAGER_Z - 0.15), Vector3.FORWARD)
	elif c.y > 0 and not has_cell("lager", c + Vector2i.UP):
		Build.box(_tiles, Vector3(r.size.x, LAGER_H, 0.3), Vector3(ctr.x, LAGER_H * 0.5, r.end.y), wall, true)
		_wall_base(_tiles, Vector3(r.size.x, 0, 0), Vector3(ctr.x, 0, r.end.y - 0.15), Vector3.FORWARD)
	# Zwei Hallenleuchten je Kachel, längs in X über dem Gang, beidseits des Trägers
	var low := LAGER_H
	for dz in [-1.9, 1.9]:
		low = Props.ceiling_lamp(_tiles, ctr.x, LAGER_H, ctr.y + dz)
	_light(Vector3(ctr.x, low - 0.4, ctr.y), 1.6, 10.0)


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
	var up := HallTex.upright(RACK_BLUE)
	var brace := Build.mat(RACK_BLUE, 0.45, 0.3)
	var beam := HallTex.powder(RACK_ORANGE, 0.06)
	var clip := Build.mat(Color(0.12, 0.13, 0.15), 0.5, 0.4)
	var depth := Storage.BOARD_D * 0.001
	var bay := Storage.BOARD_L * 0.001 + RACK_POST
	var length := bay * 2.0
	var post_x := depth * 0.5 + RACK_POST * 0.5
	var top_h := 3.6
	# Drei Stützrahmen: je zwei gelochte Stützen mit Fußplatte, verbunden durch Riegel und Diagonalen
	for dz in [-bay, 0.0, bay]:
		for dx in [-post_x, post_x]:
			Build.box(_tiles, Vector3(RACK_POST, top_h, RACK_POST), pos + Vector3(dx, top_h * 0.5, dz), up)
			Build.box(_tiles, Vector3(0.14, 0.01, 0.14), pos + Vector3(dx, 0.005, dz), clip)
			Build.box(_tiles, Vector3(RACK_POST + 0.006, 0.012, RACK_POST + 0.006), pos + Vector3(dx, top_h, dz), clip)
		var span := post_x * 2.0 - RACK_POST
		for y in [0.12, top_h - 0.1]:
			Build.box(_tiles, Vector3(span, 0.03, 0.025), pos + Vector3(0, y, dz), brace)
		var y0 := 0.12
		var flip := 1.0
		while y0 < top_h - 0.2:
			var y1 := minf(y0 + 0.62, top_h - 0.1)
			var dy := y1 - y0
			var seg := sqrt(span * span + dy * dy)
			Build.box(_tiles, Vector3(0.025, seg, 0.022), pos + Vector3(0, (y0 + y1) * 0.5, dz), brace, false, Vector3(0, 0, flip * atan2(span, dy)))
			y0 = y1
			flip = -flip
	# Böden aus Spanplatte auf Stufentraversen mit Einhängehaken an den Stützen
	var board := _chipboard()
	for y in [BOARD_Y0, BOARD_Y0 + BOARD_STEP, BOARD_Y0 + BOARD_STEP * 2.0]:
		Build.box(_tiles, Vector3(depth, 0.022, length - 0.02), pos + Vector3(0, y - 0.011, 0), board)
		for dx in [-post_x, post_x]:
			Build.box(_tiles, Vector3(0.05, 0.11, length - RACK_POST), pos + Vector3(dx, y - 0.055, 0), beam)
			for dz in [-bay, 0.0, bay]:
				for e in [-1.0, 1.0]:
					if absf(dz + e * RACK_POST) > bay:
						continue
					Build.box(_tiles, Vector3(0.056, 0.13, 0.03), pos + Vector3(dx, y - 0.06, dz + e * (RACK_POST * 0.5 + 0.015)), clip)
	# Anfahrschutz in Gelb-Schwarz an den Stützen zum Gang
	var guard := Build.mat(Color(0.95, 0.75, 0.05), 0.5)
	var black := Build.mat(Color(0.07, 0.07, 0.08), 0.6)
	for dz in [-bay, bay]:
		var g := pos + Vector3(aisle * (post_x + 0.075), 0, dz)
		Build.box(_tiles, Vector3(0.07, 0.4, 0.13), g + Vector3(0, 0.2, 0), guard)
		for k in 2:
			Build.box(_tiles, Vector3(0.072, 0.06, 0.132), g + Vector3(0, 0.12 + k * 0.16, 0), black)
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
		# Fachetikett im Klemmhalter an der Traverse zur Gangseite: blaues Feld mit der Nummer, daneben der Inhalt
		var face := aisle * (post_x + 0.025)
		var at := pos + Vector3(face, BOARD_Y0 + BOARD_STEP * shelf - 0.055, side * bay)
		var tdir := Vector3(0, 0, -aisle)          # Leserichtung der Schrift vom Gang aus
		var card_l := 0.86
		var card_h := 0.075
		Build.box(_tiles, Vector3(0.004, card_h + 0.012, card_l + 0.01), at + Vector3(aisle * 0.002, 0, 0), Build.mat(Color(0.2, 0.21, 0.23), 0.5, 0.3))
		Build.box(_tiles, Vector3(0.002, card_h, card_l), at + Vector3(aisle * 0.005, 0, 0), _label_paper())
		var left := at - tdir * (card_l * 0.5)
		var num_at := left + tdir * (card_h * 0.5 + 0.004) + Vector3(aisle * 0.0065, 0, 0)
		Build.box(_tiles, Vector3(0.001, card_h - 0.008, card_h - 0.008), num_at, Build.mat(SIGN_BLUE, 0.5))
		var num := Build.label(_tiles, str(n + 1), num_at + Vector3(aisle * 0.003, -0.002, 0), 0.0011, Color.WHITE, 48, PI / 2 * aisle)
		num.font = UITheme.font(700)
		var plate := Build.label(_tiles, "leer", left + tdir * (card_h + 0.03) + Vector3(aisle * 0.009, 0, 0), 0.0009, Color(0.55, 0.57, 0.6), 36, PI / 2 * aisle)
		plate.font = UITheme.font(500)
		plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_slot_signs[target.slot] = plate
	# Belegungstafel an der Stirnseite zum Quergang: Kopf mit der Regalnummer, darunter die Fächer
	var end_z := pos.z + bay + RACK_POST * 0.5 + 0.012
	var board_w := depth + 0.06
	var sign_c := Vector3(pos.x, 2.05, end_z)
	Build.box(_tiles, Vector3(board_w + 0.03, 1.13, 0.012), sign_c, Build.mat(Color(0.2, 0.21, 0.23), 0.5, 0.3))
	Build.box(_tiles, Vector3(board_w, 0.24, 0.004), sign_c + Vector3(0, 0.43, 0.008), Build.mat(SIGN_ANTHRACITE, 0.45, 0.2))
	Build.box(_tiles, Vector3(0.05, 0.24, 0.004), sign_c + Vector3(-board_w * 0.5 + 0.025, 0.43, 0.009), Build.mat(RACK_ORANGE, 0.5))
	var head := Build.label(_tiles, "REGAL %d" % (rack + 1), sign_c + Vector3(0.02, 0.425, 0.0115), 0.0012, Color.WHITE, 96)
	head.font = UITheme.font(700, 3)
	Build.box(_tiles, Vector3(board_w, 0.84, 0.004), sign_c + Vector3(0, -0.11, 0.008), _label_paper())
	var label := Build.label(_tiles, "", sign_c + Vector3(-board_w * 0.5 + 0.05, 0.27, 0.0115), 0.0009, Color(0.08, 0.09, 0.11), 40)
	label.font = UITheme.font(500)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.line_spacing = 10.0
	# Lange Einträge brechen um, statt über die Tafel zu laufen
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = (board_w - 0.1) / label.pixel_size
	_signs[rack] = label


## Spanplatte für die Regalböden aus der Holztextur des Modells (Weltkoordinaten, damit die Box-UVs passen).
static func _chipboard() -> StandardMaterial3D:
	if not _chip_mat:
		_chip_mat = StandardMaterial3D.new()
		_chip_mat.albedo_texture = load("res://models/non_machine_parts_oriented_strand_board_diff_1k.jpg")
		_chip_mat.albedo_color = Color(0.95, 0.9, 0.85)
		_chip_mat.roughness = 0.8
		_chip_mat.uv1_triplanar = true
		_chip_mat.uv1_world_triplanar = true
		_chip_mat.uv1_scale = Vector3(0.8, 0.8, 0.8)
		_chip_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _chip_mat


static var _chip_mat: StandardMaterial3D


static func _label_paper() -> StandardMaterial3D:
	if not _paper_mat:
		_paper_mat = Build.mat(Color(0.96, 0.96, 0.94), 0.7)
	return _paper_mat


static var _paper_mat: StandardMaterial3D


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
	@warning_ignore("integer_division")
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
	var blue := HallTex.powder(Color(0.1, 0.27, 0.62), 0.3).duplicate() as StandardMaterial3D
	blue.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rim := HallTex.powder(Color(0.08, 0.22, 0.52), 0.25)
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
		# Sortenkennung wie auf dem Wertstoffhof: Emailleschild in Sortenfarbe mit dem Werkstoffkürzel, an den
		# Rand gehängt. Füllstand und Name stehen im Hinweis beim Anvisieren.
		var sort := str(chips.only)
		var sign_col: Color = {"stahl": Color(0.62, 0.65, 0.7), "aluminium": Color(0.86, 0.87, 0.88), "messing": Color(0.86, 0.68, 0.22)}.get(sort, Color.WHITE)
		var symbol: String = {"stahl": "Fe", "aluminium": "Al", "messing": "CuZn"}.get(sort, "♻")
		var face := -(top.y * 0.5 + 0.055)
		var sy := h - 0.25
		_out(Build.box(node, Vector3(0.62, 0.42, 0.012), Vector3(0, sy, face), Build.mat(Color(0.96, 0.96, 0.94), 0.35, 0.1)))
		_out(Build.box(node, Vector3(0.56, 0.36, 0.004), Vector3(0, sy, face - 0.008), Build.mat(sign_col, 0.35, 0.3)))
		for hx in [-0.22, 0.22]:
			_out(Build.box(node, Vector3(0.03, 0.12, 0.02), Vector3(hx, h - 0.03, face + 0.02), rim))
		var l := Build.label(node, symbol, Vector3(0, sy - 0.01, face - 0.011), 0.0022, Color(0.1, 0.11, 0.13), 96, PI)
		l.font = UITheme.font(700)
		l.layers = OUTDOOR_LAYER
		var hit := Build.collider(node, Vector3(top.x, h + 0.05, top.y + 0.2), Vector3(0, (h + 0.05) * 0.5, 0))
		var t := ContainerTarget.new()
		t.world = world
		t.index = i
		node.add_child(t)
		hit.set_meta("interact", t)


## Höchste Ladung einer Lieferpalette über der Ladefläche, in m. Was nicht mehr draufpasst, kommt auf eine weitere Palette.
const PALLET_MAX_LOAD := 1.0


## Stücke mit gleichem Werkstoff und gleichen Maßen liegen auf einer Palette, bei zu viel Ladung auf
## mehreren (Feld "pallet": 0, 1, 2 …). Jede Palette hat ihren eigenen Schlüssel.
static func delivery_key(it: Dictionary) -> String:
	var k := _sort_key(it)
	var n := int(it.get("pallet", 0))
	return k if n == 0 else "%s|#%d" % [k, n]


## Schlüssel der Sorte, ohne Palettennummer.
static func _sort_key(it: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s" % [it["material"], it["kind"], it.get("d", 0.0), it.get("w", 0.0), it.get("h", 0.0), it.get("l", 0.0), it.get("key", "")]


## Wie viele Stücke dieser Sorte auf eine Lieferpalette passen: so viele Lagen wie bis PALLET_MAX_LOAD
## Ladehöhe, je Lage wie in add_goods nebeneinander und hintereinander. Mindestens ein Stück.
static func pallet_capacity(it: Dictionary) -> int:
	var round_bar := str(it["kind"]) == Materials.KIND_ROUND
	var w := float(it["d"] if round_bar else it["w"]) * 0.001
	var h := float(it["d"] if round_bar else it["h"]) * 0.001
	var ext := delivery_extent([it])
	var gap := 0.008
	var per := maxi(int(ext.y / (w + gap)), 1) * maxi(int(ext.x / (_shown_length(it) + gap)), 1)
	var layers := maxi(int((PALLET_MAX_LOAD + 0.0001) / (h + 0.002)), 1)
	return per * layers


## Lieferliste auf Paletten verteilen: Stücke ohne Palettennummer und solche auf einer übervollen Palette
## kommen auf die erste Palette ihrer Sorte mit freiem Platz, sonst auf eine neue. Stücke, die schon richtig
## liegen, bleiben, wo sie sind. Gibt true zurück, wenn sich etwas geändert hat.
static func split_pallets(items: Array) -> bool:
	var counts := {}      # Sorte -> {Palettennummer: Stückzahl}
	var stray: Array = [] # Stücke, die neu verteilt werden
	for it in items:
		var s := _sort_key(it)
		if not counts.has(s):
			counts[s] = {}
		var c: Dictionary = counts[s]
		if not it.has("pallet"):
			stray.append(it)
			continue
		var n := int(it["pallet"])
		if int(c.get(n, 0)) >= pallet_capacity(it):
			stray.append(it)
			continue
		c[n] = int(c.get(n, 0)) + 1
	for it in stray:
		var c: Dictionary = counts[_sort_key(it)]
		var cap := pallet_capacity(it)
		var n := 0
		while int(c.get(n, 0)) >= cap:
			n += 1
		it["pallet"] = n
		c[n] = int(c.get(n, 0)) + 1
	return not stray.is_empty()


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
	var row := floori(i / 5.0) % 5
	var stack := floori(i / 25.0)
	return Vector3(21.6 + col * 1.7, PALLET_TOP + stack * 1.0, LAGER_Z + 2.6 + row * 3.4)


## Länge (lange Seite, bei Drehung 0 längs X) und Breite einer Lieferpalette samt überstehender Ladung.
static func delivery_extent(list: Array) -> Vector2:
	var f := Shelf.foot("pallet")
	return Vector2(maxf(maxf(f.x, f.y), _shown_length(list[0]) + 0.1), minf(f.x, f.y))


## Bodenfläche einer Lieferpalette mit Mitte pos und Drehung rot (wie Shelf: Vierteldrehungen).
static func delivery_rect(pos: Vector2, rot: int, ext: Vector2) -> Rect2:
	return Layout.rect_at(Rect2(-ext * 0.5, ext), pos, rot)


## Paletten der Lieferliste samt Lage. Je {"index", "items", "key", "extent", "pos": Vector3, "rot": int, "moved", "carried"}.
## spots: delivery_key -> {"pos": Vector2, "rot": int, "carried": bool} für Paletten, die mit Stapler oder Hubwagen bewegt
## wurden. Alle anderen stehen im Raster (Drehung 1: lange Seite längs Z) und überspringen belegte Plätze.
static func place_deliveries(items: Array, spots: Dictionary = {}) -> Array:
	var groups := delivery_groups(items)
	var taken: Array[Rect2] = []
	for g in groups:
		var key := delivery_key(g["items"][0])
		g["key"] = key
		g["extent"] = delivery_extent(g["items"])
		g["moved"] = spots.has(key)
		g["carried"] = false
		g["rot"] = 1
		g["pos"] = delivery_pos(0)
		if g["moved"]:
			var sp: Dictionary = spots[key]
			var p: Vector2 = sp["pos"]
			g["rot"] = posmod(int(sp["rot"]), 4)
			g["pos"] = Vector3(p.x, PALLET_TOP, p.y)
			g["carried"] = bool(sp.get("carried", false))
			if not g["carried"]:
				taken.append(delivery_rect(p, g["rot"], g["extent"]))
	var slot := 0
	for g in groups:
		if g["moved"]:
			continue
		var at := delivery_pos(slot)
		while slot < 500:
			at = delivery_pos(slot)
			slot += 1
			# Nur der Boden ist belegbar; die oberen Lagen des Rasters liegen auf den unteren Paletten
			if at.y > PALLET_TOP + 0.01:
				break
			var r := delivery_rect(Vector2(at.x, at.z), 1, g["extent"])
			var hit := false
			for t in taken:
				if r.intersects(t):
					hit = true
					break
			if not hit:
				break
		g["pos"] = at
	return groups


func show_deliveries(items: Array, spots: Dictionary = {}) -> void:
	for c in _deliveries.get_children():
		_deliveries.remove_child(c)
		c.free()
	for g in place_deliveries(items, spots):
		if g["carried"]:
			continue          # hängt gerade an Stapler oder Hubwagen
		var node := Node3D.new()
		node.position = g["pos"]
		node.rotation.y = (int(g["rot"]) - 1) * PI / 2.0
		_deliveries.add_child(node)
		_pallet(node, g["items"], int(g["index"]))


## Stücke einer Sorte in Lagen auf der Ladefläche (parent liegt auf ihr, Stücke längs Z). Gibt die Höhe der Ladung zurück.
func add_goods(parent: Node3D, list: Array, layer := GOODS_LAYER) -> float:
	var first: Dictionary = list[0]
	var length := _shown_length(first)
	var round_bar := str(first["kind"]) == Materials.KIND_ROUND
	var w := float(first["d"] if round_bar else first["w"]) * 0.001
	var h := float(first["d"] if round_bar else first["h"]) * 0.001
	var ext := delivery_extent(list)
	var pallet_w := ext.y
	var pallet_l := ext.x
	var gap := 0.008
	# Wenige Stücke liegen mittig statt am Rand der Palette
	var cols := clampi(int(pallet_w / (w + gap)), 1, list.size())
	var rows := clampi(int(pallet_l / (length + gap)), 1, ceili(list.size() / float(cols)))
	var per := cols * rows
	for i in list.size():
		var layer_i := i / per
		var k := i % per
		var col := k % cols
		var row := k / cols
		var at := Vector3((col - (cols - 1) * 0.5) * (w + gap), layer_i * (h + 0.002), (row - (rows - 1) * 0.5) * (length + gap))
		_add_item(parent, list[i], at, layer)
	var total := (list.size() - 1) / per + 1
	return total * (h + 0.002)


## Palette mit allen Stücken einer Sorte, in Lagen gestapelt. index = erstes Stück in der Lieferliste.
func _pallet(node: Node3D, list: Array, index: int) -> void:
	# Europalette aus dem Modell, lange Seite längs der Stücke (Z); node liegt auf der Ladefläche
	var model := Props.make("pallet")
	model.rotation.y = PI * 0.5
	model.position.y = -PALLET_TOP
	node.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = GOODS_LAYER
	var top := add_goods(node, list)
	var ext := delivery_extent(list)
	var d := Delivery.new()
	d.world = world
	d.index = index
	node.add_child(d)
	# Zinken und Gabel kommen von allen Seiten unter die Palette: Klötze und Deckplatte wie bei der leeren Palette
	var base := StaticBody3D.new()
	base.position.y = -PALLET_TOP
	base.rotation.y = PI * 0.5
	node.add_child(base)
	Shelf.pallet_shape(base, 1)
	base.set_meta("interact", d)
	var hit := Build.collider(node, Vector3(ext.y, top, ext.x), Vector3(0, top * 0.5, 0))
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
		var lines: Array[String] = []
		for slot in rack_slots(rack):
			var here := Storage.on_board(items, slot)
			if here.is_empty():
				continue
			lines.append("Fach %d   %s" % [slot % SLOTS_PER_RACK + 1, sign_text(here)])
		for slot in rack_slots(rack):
			if _slot_signs.has(slot):
				var here := Storage.on_board(items, slot)
				var plate := _slot_signs[slot] as Label3D
				plate.text = _fit(sign_text(here), 44) if not here.is_empty() else "leer"
				plate.modulate = Color(0.08, 0.09, 0.11) if not here.is_empty() else Color(0.55, 0.57, 0.6)
		if lines.is_empty():
			lines.append("leer")
		(_signs[rack] as Label3D).text = "\n".join(lines)


## Text fürs Fachetikett kürzen, damit er im Halter bleibt.
static func _fit(text: String, n: int) -> String:
	return text if text.length() <= n else text.substr(0, n - 1) + "…"


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
