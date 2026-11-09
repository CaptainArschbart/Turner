class_name Props
extends RefCounted
## Einrichtung aus models/non_machine_parts.glb (Schreibtisch mit Stuhl, Kübelpflanze, Spänekiste, zwei
## Holzregale, Hallenleuchte) und models/transport_items.glb (Europalette, Gasflasche, Sackkarre, Hubwagen). make(key) liefert ein Teil als eigenen Knoten: auf dem Boden stehend (y = 0),
## mittig über dem Ursprung, die Vorderseite zeigt nach +Z.

const PATH := "res://models/non_machine_parts.glb"
const TRANSPORT := "res://models/transport_items.glb"
## Teil -> Objekt(e) im Modell. path: andere Modelldatei als PATH. scale: Faktor auf die Größe im Modell, yaw: Drehung um die Hochachse,
## anchor: nur dieses Objekt bestimmt die Mitte (sonst alle).
const PARTS := {
	# Tischplatte auf 0,78 m (im Modell 1,12 m)
	"desk": {"node": "Office Desk & Chair", "scale": 0.7, "yaw": 0.0, "anchor": "Desk_Wood"},
	"plant": {"node": "Modular plant", "scale": 0.75, "yaw": 0.0},
	"chip_box": {"node": "spänekiste", "scale": 1.0, "yaw": 0.0},
	"ceiling_lamp": {"node": "Light - 2", "scale": 1.0, "yaw": 0.0},
	"pallet": {"path": TRANSPORT, "node": "EUR-Pallet", "scale": 1.0, "yaw": 0.0},
	"gas_bottle": {"path": TRANSPORT, "node": "Bottle", "scale": 1.0, "yaw": 0.0},
	"hand_truck": {"path": TRANSPORT, "node": "hand_truck", "scale": 1.0, "yaw": 0.0},
	# Hubwagen: im Export die Gruppe "Empty" (Gabel, Deichsel, Räder)
	"pallet_jack": {"path": TRANSPORT, "node": "Empty", "scale": 1.0, "yaw": 0.0},
	"shelf_wide":{"nodes": ["Cube.003", "Cube.004"], "scale": 0.75, "yaw": 0.0},
	"shelf_narrow": {"nodes": ["Cube.005", "Cube.006"], "scale": 0.75, "yaw": 0.0},
}
## Materialien, deren Farbe in Blender prozedural ist und den Export nicht übersteht: [Farbe, Rauheit, Metall]
const MATERIALS := {
	"Desk_Black": [Color(0.08, 0.08, 0.09), 0.55, 0.0],
	"Desk_Light": [Color(0.55, 0.56, 0.58), 0.4, 0.6],
	"Desk_Rubber": [Color(0.05, 0.05, 0.05), 0.95, 0.0],
	"Seat_Fabric": [Color(0.13, 0.17, 0.26), 0.95, 0.0],
	"used_anthrazit": [Color(0.17, 0.18, 0.19), 0.85, 0.2],
	"Procedural Dirt": [Color(0.2, 0.14, 0.08), 0.95, 0.0],
	"Procedrual Cement wall": [Color(0.52, 0.52, 0.5), 0.9, 0.0],
	"Material.010": [Color(0.33, 0.42, 0.17), 0.8, 0.0],
	"Backen_geschliffen": [Color(0.13, 0.13, 0.14), 0.5, 0.4],
	# Gasflasche
	"Scratched Rusty Red Metall": [Color(0.52, 0.09, 0.07), 0.45, 0.35],
	"Scratched Rusty Metal": [Color(0.42, 0.42, 0.43), 0.45, 0.8],
	"Scratched Rusty Brass": [Color(0.72, 0.56, 0.26), 0.35, 0.85],
}

static var _scenes: Dictionary = {}     # Pfad -> PackedScene


## Teil als neuer Knoten (noch ohne Eltern). fit: auf genau diese Größe (Breite, Höhe, Tiefe) bringen.
static func make(key: String, fit := Vector3.ZERO) -> Node3D:
	var spec: Dictionary = PARTS[key]
	var path := str(spec.get("path", PATH))
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var src: Node = (_scenes[path] as PackedScene).instantiate()
	var holder := Node3D.new()
	holder.name = key
	var inner := Node3D.new()
	holder.add_child(inner)
	var names: Array = spec.get("nodes", [spec.get("node", "")])
	for nm in names:
		var n := src.find_child(_godot_name(nm), true, false) as Node3D
		if n == null:
			push_warning("%s: Objekt '%s' fehlt" % [path.get_file(), nm])
			continue
		var xf := _rel(n, src)
		n.get_parent().remove_child(n)
		_own(n)
		inner.add_child(n)
		n.transform = xf
	src.free()
	_fix_materials(inner, spec.get("blank", []))
	if key == "plant":
		_grow_plant(inner)
	inner.basis = Basis(Vector3.UP, float(spec.get("yaw", 0.0))).scaled(Vector3.ONE * float(spec.get("scale", 1.0)))
	if fit != Vector3.ZERO:
		var size := bounds(holder).size
		inner.basis = Basis.from_scale(Vector3(fit.x / size.x, fit.y / size.y, fit.z / size.z)) * inner.basis
	# Auf den Boden stellen und mittig ausrichten
	var box := bounds(holder)
	var c := box.get_center()
	if spec.has("anchor"):
		var a := holder.find_child(_godot_name(spec["anchor"]), true, false) as Node3D
		if a:
			c = bounds(holder, a).get_center()
	inner.position -= Vector3(c.x, box.position.y, c.z)
	return holder


## Hallenleuchte (Röhre mit Schutzgitter an zwei Seilpaaren), deren Seile bei ceiling_y an der Decke enden.
## Die Röhre bekommt das leuchtende LED-Material wie in der Grundhalle. yaw dreht die Leuchte um die Hochachse.
## Gibt die Höhe der Röhre (Unterkante) zurück, darunter gehört das Licht.
static func ceiling_lamp(parent: Node3D, x: float, ceiling_y: float, z: float, yaw := 0.0) -> float:
	var lamp := make("ceiling_lamp")
	var h := bounds(lamp).size.y
	lamp.position = Vector3(x, ceiling_y - h, z)
	lamp.rotation.y = yaw
	parent.add_child(lamp)
	if not _led:
		_led = Build.emissive(Color(1.0, 0.98, 0.94), 4.0)
	for mi in lamp.find_children("*", "MeshInstance3D", true, false):
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var mat := (mi as MeshInstance3D).mesh.surface_get_material(s)
			if mat and mat.resource_name == "emissive_light":
				(mi as MeshInstance3D).set_surface_override_material(s, _led)
	return ceiling_y - h


static var _led: StandardMaterial3D


## Umhüllender Quader aller Meshes unter part (Standard: n selbst) in den Koordinaten von n.
static func bounds(n: Node3D, part: Node3D = null) -> AABB:
	var out := AABB()
	var first := true
	var src := part if part else n
	var list: Array = src.find_children("*", "MeshInstance3D", true, false)
	if src is MeshInstance3D:
		list.append(src)
	for mi in list:
		var b: AABB = _rel(mi as Node3D, n) * (mi as MeshInstance3D).get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


## blank: [Farbe, Rauheit, Metall] für Flächen ohne oder mit namenlosem Material, leer = so lassen.
static func _fix_materials(root: Node, blank: Array = []) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var old := m.surface_get_material(s)
			var v: Array = []
			if old and MATERIALS.has(old.resource_name):
				v = MATERIALS[old.resource_name]
			elif not blank.is_empty() and (old == null or old.resource_name == ""):
				v = blank
			if not v.is_empty():
				(mi as MeshInstance3D).set_surface_override_material(s, Build.mat(v[0], v[1], v[2]))


## Die Pflanze ist in Blender ein Geometry-Nodes-Aufbau, im Export kommen nur zwei Stiele mit je einem
## Blatt an. Aus Stiel und Blatt des Modells wird hier ein voller Busch: fünf Stiele, je fünf Blätter.
static func _grow_plant(inner: Node3D) -> void:
	var plant := inner.get_child(0) as Node3D
	var stem := plant.find_child("tIGE", true, false) as MeshInstance3D
	var leaf := plant.find_child("FEUILLE", true, false) as MeshInstance3D
	if stem == null or leaf == null:
		return
	var s := stem.scale.x                       # Maßstab der Teile in der Pflanze
	var base_y := stem.position.y
	var stem_len := stem.mesh.get_aabb().size.y * s
	var leaf_mesh := leaf.mesh
	var leaf_mat := leaf.get_active_material(0)
	var stem_mat := stem.get_active_material(0)
	for nm in ["tIGE_003", "FEUILLE", "FEUILLE_003"]:
		var old := plant.find_child(nm, true, false)
		if old and old != stem:
			old.get_parent().remove_child(old)
			old.free()
	var heights := [1.0, 0.8, 0.92, 0.7, 0.86]
	var k := 0
	for i in 5:
		var a := i * TAU / 5.0 + 0.3
		var h := Vector3(cos(a), 0.0, sin(a))
		var tilt := 0.1 + 0.07 * (i % 2)
		var axis := Vector3(h.z, 0.0, -h.x)      # kippt die Hochachse in Richtung h
		var b := Basis(axis, tilt)
		var root_p := Vector3(0.0, base_y, 0.0) + h * 0.06
		var len_i: float = stem_len * heights[i]
		var st := MeshInstance3D.new()
		st.mesh = stem.mesh
		st.material_override = stem_mat
		st.transform = Transform3D(b.scaled(Vector3(s, s * heights[i], s)), root_p)
		plant.add_child(st)
		var up := b * Vector3.UP
		for j in 5:
			var f := 0.35 + j * 0.15
			var lf := MeshInstance3D.new()
			lf.mesh = leaf_mesh
			lf.material_override = leaf_mat
			var yaw := a + k * 2.4                # Goldener Winkel, damit sich die Blätter nicht decken
			k += 1
			var ls := s * (0.85 - j * 0.07)
			lf.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * ls), root_p + up * len_i * f)
			plant.add_child(lf)
	stem.free()


## Godot ersetzt beim Import "." in Objektnamen durch "_".
static func _godot_name(nm: String) -> String:
	return nm.replace(".", "_")


static func _own(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_own(c)


static func _rel(n: Node3D, root: Node) -> Transform3D:
	if n == root:
		return Transform3D.IDENTITY
	var t := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
