class_name CncMillModel
extends RefCounted
## Modell der CNC-Fräsmaschine (Bearbeitungszentrum) aus models/cncmill.glb.
## Das Modell hat keine sprechenden Namen: Alle Teile heißen CNC_Machine_with_Doors_mesh<N>, die Gruppen
## (Y-Schlitten, Tisch, Fräskopf, Magazin, Wechsler, Tür, Kabine) stehen hier als Nummernlisten.
## Modellkoordinaten (m): Bedienerseite +Z, Y oben, Spindelachse bei x = AXIS_X, z = AXIS_Z.
## Die Maschine selbst steht mit OFS verschoben: Spindelachse im Ursprung, Füße auf dem Boden.
## Alle beweglichen Gruppen hängen als Knoten unter mroot (Modellkoordinaten, Ursprung = Modellursprung) und werden
## von CncMill bewegt.

const PATH := "res://models/cncmill.glb"
const PREFIX := "CNC_Machine_with_Doors_mesh"
const OFS := Vector3(-0.145, 0.13, -0.06)    # Modell -> Maschine
const AXIS_X := 0.145
const AXIS_Z := 0.06
const NOSE_Y := 1.83                         # Spindelnase im Modell (Wechselhöhe)
const TABLE_TOP := 1.31                      # Tischfläche
const TABLE_ORIGIN_X := 0.195                # Punkt des Tisches, der bei mittlerem Verfahrweg unter der Spindel steht
const TABLE_ORIGIN_Z := -0.06                # ... in Y (Schlittenversatz in der Mitte: SADDLE_MID)
const SADDLE_MID := 0.12                     # Schlitten steht in der Mitte des Y-Wegs so weit vor dem Modellzustand
const TABLE_MID := -0.05                     # dito Tisch in X
const DOOR_TRAVEL := 0.95                    # Tür fährt so weit nach links
const DISK_Y := 2.20                         # Achse der Magazinscheibe (Y, Z)
const DISK_Z := -0.005
const DISK_R := 0.28                         # Kreis der Aufnahmen
const HOLD_X := -0.955                       # Aufnahmen: Kegelende der Halter
const POCKETS := 24
const ARM_PIVOT := Vector3(-0.495, 1.80, 0.035)
const ARM_HALF := 0.235
const DOOR_LAYER := 1 << 2                   # Sichtebene von Kabine und Tür (Bedienkamera blendet sie von innen aus)

const SADDLE := [121, 15, 16, 18, 24, 112, 119, 115, 114, 66, 67, 71, 109, 130, 68, 17, 22, 113, 69, 70, 118]
const TABLE := [105, 108]
const HEAD := [124, 173, 174, 7, 51]
const DISK := [35, 120, 185, 182, 89]
const ARM := [43, 98, 90, 39, 34, 40, 45, 36, 42]
const DOOR := [72, 77, 110, 83, 80, 78]
const SHELL := [106, 76, 132, 101, 85, 74, 135, 75]
const GLASS := [78]
const PULT := 88

## Innere Materialien sind im Modell fast schwarz (Albedo 0,02): Namen der dunklen Flächen -> sichtbares Dunkelgrau.
const DARK_NAMES := ["M_02___Default", "M_02___Defaultasd", "M_02___Defaultasda", "M_02___Defaultasdaasd"]
const INNER_COLOR := Color(0.20, 0.22, 0.25)
const CAST_COLOR := Color(0.26, 0.28, 0.31)

var scene: Node3D
var mroot: Node3D
var meshes: Dictionary = {}                  # N -> MeshInstance3D
var parts: Dictionary = {}


## Baut das Modell unter root und gibt die Knoten zurück. root muss nicht im Baum hängen.
func build(root: Node3D) -> Dictionary:
	scene = (load(PATH) as PackedScene).instantiate() as Node3D
	mroot = Node3D.new()
	mroot.name = "Modell"
	mroot.position = OFS
	root.add_child(mroot)
	mroot.add_child(scene)
	for n in scene.find_children(PREFIX + "*", "MeshInstance3D", true, false):
		meshes[int(str(n.name).substr(PREFIX.length()))] = n
	# Lagen der Teile im Modell merken, bevor sie umgehängt werden
	var rel := {}
	for k in meshes:
		rel[k] = _rel(meshes[k], scene)

	var saddle := _pivot("Y-Schlitten", Vector3.ZERO)
	var table := _pivot("Tisch", Vector3(TABLE_ORIGIN_X, TABLE_TOP, TABLE_ORIGIN_Z), saddle)
	var head := _pivot("Fraeskopf", Vector3(AXIS_X, NOSE_Y, AXIS_Z))
	var disk := _pivot("Magazinscheibe", Vector3(0.0, DISK_Y, DISK_Z))
	var arm := _pivot("Wechsler", ARM_PIVOT)
	var arm_rot := _pivot("Wechslerarm", Vector3.ZERO, arm)
	var door := _pivot("Tuer", Vector3.ZERO)
	_take(SADDLE, saddle, rel, Vector3.ZERO)
	_take(TABLE, table, rel, table.position)
	_take(HEAD, head, rel, head.position)
	_take(DISK, disk, rel, disk.position)
	_take(ARM, arm_rot, rel, arm.position)
	_take(DOOR, door, rel, Vector3.ZERO)
	parts = {"mroot": mroot, "scene": scene, "saddle": saddle, "table": table, "head": head, "disk": disk,
		"arm": arm, "arm_rot": arm_rot, "door": door}

	_fix_materials()
	for k in SHELL + DOOR:
		(meshes[k] as MeshInstance3D).layers = DOOR_LAYER
	_find_screen()
	_find_handle()

	# Spindel und Aufnahmen
	var spindle := Node3D.new()
	spindle.name = "Spindel"
	head.add_child(spindle)
	parts["spindle"] = spindle
	var anchors: Array[Node3D] = []
	for i in POCKETS:
		var a := Node3D.new()
		var phi := i * TAU / POCKETS
		a.name = "Aufnahme%d" % (i + 1)
		a.position = Vector3(HOLD_X, -DISK_R * cos(phi), DISK_R * sin(phi))
		a.basis = Basis(Vector3.BACK, -PI / 2.0)          # Werkzeug-Y -> +X: die Schneide zeigt nach außen (-X)
		disk.add_child(a)
		anchors.append(a)
	parts["anchors"] = anchors
	var grip_a := Node3D.new()
	grip_a.position = Vector3(0, 0, ARM_HALF)
	arm_rot.add_child(grip_a)
	var grip_b := Node3D.new()
	grip_b.position = Vector3(0, 0, -ARM_HALF)
	arm_rot.add_child(grip_b)
	parts["grip_a"] = grip_a
	parts["grip_b"] = grip_b
	parts["shell"] = SHELL.map(func(k): return meshes[k]) + DOOR.map(func(k): return meshes[k])
	return parts


## Hängt die Teile an den Knoten pivot, ohne ihre Lage im Modell zu ändern. pivot_pos = Lage des Knotens (Modell).
func _take(list: Array, pivot: Node3D, rel: Dictionary, pivot_pos: Vector3) -> void:
	for k in list:
		var mi: MeshInstance3D = meshes[k]
		mi.get_parent().remove_child(mi)
		pivot.add_child(mi)
		mi.transform = Transform3D(Basis(), -pivot_pos) * (rel[k] as Transform3D)


func _pivot(pname: String, pos: Vector3, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.name = pname
	n.position = pos
	(parent if parent != null else mroot).add_child(n)
	return n


static func _rel(n: Node3D, stop: Node) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != stop:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## Dunkles Innenleben aufhellen: Guss dunkelgrau, Kabine und Pult bleiben wie im Modell.
func _fix_materials() -> void:
	var outer: Array = SHELL + DOOR + [PULT]
	for k in meshes:
		var mi: MeshInstance3D = meshes[k]
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m == null:
				continue
			if str(m.resource_name) in DARK_NAMES and not outer.has(k):
				var d := m.duplicate() as StandardMaterial3D
				d.albedo_color = CAST_COLOR if (SADDLE + TABLE + HEAD + DISK + ARM).has(k) else INNER_COLOR
				d.roughness = 0.55
				d.metallic = 0.35
				mi.set_surface_override_material(s, d)
			elif str(m.resource_name) in ["Material__42", "Material__43"]:
				var st := m.duplicate() as StandardMaterial3D
				st.metallic = 0.7
				st.roughness = 0.35
				mi.set_surface_override_material(s, st)
	# Fenster der Tür und der Rückwand: durchsichtiges Glas statt grauer Fläche
	for k in [78, 132]:
		var mi: MeshInstance3D = meshes[k]
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m != null and str(m.resource_name).begins_with("M_06"):
				mi.set_surface_override_material(s, Build.glass(Color(0.78, 0.86, 0.92, 0.14)))


## Bildschirmfläche am Pult: die vier Ecken der Fläche mit dem Material M_14 (Texturbild des Monitors).
func _find_screen() -> void:
	var mi: MeshInstance3D = meshes[PULT]
	var xf := _rel(mi, scene)
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m == null or not str(m.resource_name).begins_with("M_14"):
			continue
		var vs: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var c := Vector3.ZERO
		for v in vs:
			var w := xf * v
			lo = lo.min(w)
			hi = hi.max(w)
			c += w
		c /= vs.size()
		var n := xf.basis * (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]
		n = Vector3(n.x, 0.0, n.z).normalized()
		var right := Vector3.UP.cross(n)
		var up := Vector3.UP
		var w_m := 0.0
		for v in vs:
			w_m = maxf(w_m, absf((xf * v - c).dot(right)))
		parts["screen_xf"] = Transform3D(Basis(right, up, n), c)         # Modellkoordinaten
		parts["screen_size"] = Vector2(w_m * 2.0, hi.y - lo.y)
		mi.set_surface_override_material(s, Build.mat(Color(0.02, 0.02, 0.03), 0.4))


## Türgriff: Dreiecke des Fensterrahmens, die vor der Tür stehen (z > 1,31).
func _find_handle() -> void:
	var mi: MeshInstance3D = meshes[110]
	var xf := _rel(mi, scene)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for s in mi.mesh.get_surface_count():
		for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = xf * v
			if w.z > 1.31:
				lo = lo.min(w)
				hi = hi.max(w)
	if lo.x == INF:
		lo = Vector3(0.95, 0.9, 1.3)
		hi = Vector3(1.04, 1.5, 1.36)
	parts["handle"] = AABB(lo, hi - lo)                                    # Modellkoordinaten, Tür zu
