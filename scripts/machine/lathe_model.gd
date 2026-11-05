class_name LatheModel
extends RefCounted
## Bindet die Blender-Modelle aus models/lathe.glb in die Drehmaschine ein:
## Futter mit 3 Backen, Schnellwechsel-Werkzeughalter (Schrupp-, Schlicht-, 45°-Fasen- und Stechmeißel) und mitlaufende Spitze.
##
## Modell-Koordinaten (Blender-Export): Spindelachse = Z, Werkstück liegt Richtung -Z, Werkzeuge zeigen in -X.
## Spiel-Koordinaten (Lathe): Spindelachse = +X (weg vom Futter), Bedienerseite/radial = +Z.
## -> Drehung -90° um Y, danach Skalierung SCALE.

const PATH := "res://models/lathe.glb"
const SCALE := 0.032          # m pro Blender-Einheit (Futter Ø 300 mm)
## Werkzeug-ID -> Halter im Modell (Objektnamen: neues Modell zuerst, dann altes). rot = Drehung des Werkzeughalters (Indexieren), damit der Halter zum Werkstück zeigt.
const TOOLS := {
	"T1": {"holder": ["toolspanner", "Werkzeughalter"], "insert": ["insert", "Cube_007"], "rot": 0.0},
	"T3": {"holder": ["toolspanner2", "Werkzeughalter_001"], "insert": ["insert_001", "Cube_011"], "rot": PI},
	# 45°-Fasenmeißel: quadratische Platte über Eck, Spitze zeigt zur Drehachse (ref "center")
	"T5": {"holder": ["toolspanner3"], "insert": ["Cube"], "rot": 0.0, "ref": "center"},
	# Stechschwert im Blockhalter (sword_holder): Stechplatte sword_insert auf dem Schwert sword, Ecke zum Futter
	"T6": {"holder": ["toolspanner4"], "insert": ["sword_insert", "Cube_003"], "rot": 0.0},
}

var jaws: Array[Node3D] = []
var _jaw_dir: Array[Vector2] = []
var _post_root: Node3D
var _post: Node3D
var _holders := {}            # Werkzeug-ID -> {node, rot, tip}
var _slot_z := 0.0            # Mitte des (leeren) Halterplatzes im Halter-Koordinatensystem
var shank_end_mm := 175.0     # bis hierhin reicht der Schaft prozeduraler Werkzeuge
## Schaft (Plattenhalter) des T1-Halters in mm relativ zur T1-Schneide, Spielachsen
## (x = axial, y = hoch, z = radial). Leer, wenn das Modell keinen eigenen Schaft hat.
var shank_box := AABB()
var _shank_cz := 0.0          # Schaftmitte (Modell-z) im Halter-Koordinatensystem
var _lever: Node3D
var _lever_xf := Transform3D.IDENTITY
var _rs: Basis


static func available() -> bool:
	return ResourceLoader.exists(PATH)


func _init() -> void:
	_rs = Basis(Vector3.UP, -PI / 2.0) * Basis.from_scale(Vector3.ONE * SCALE)


## Baut alles ein. Gibt false zurück, falls das Modell fehlt (dann bleibt die prozedurale Maschine).
func build(spindle_pivot: Node3D, cross_slide: Node3D, tailstock: Node3D, axis_h: float, slide_top: float) -> bool:
	if not available():
		return false
	var ps := load(PATH) as PackedScene
	if ps == null:
		return false
	var root := ps.instantiate() as Node3D
	var dark := Build.mat(Color(0.08, 0.08, 0.09), 0.5, 0.8)
	_fix_materials(root, dark)

	# ---- Futter + Backen (drehen mit der Spindel)
	var jaw_names: Array = _pick_set(root, [["Jaw1", "Jaw2", "Jaw3"], ["Cube_001", "Cube_002", "Cube_003"]])
	var jaw_front := INF
	for n in jaw_names:
		var j := root.find_child(n, true, false) as MeshInstance3D
		if j:
			for v in _verts(j, root):
				jaw_front = minf(jaw_front, v.z)
	if jaw_front == INF:
		jaw_front = 0.0
	var chuck_ad := _adapter(spindle_pivot, Transform3D(_rs, Vector3(jaw_front * SCALE, 0, 0)))
	_take(root, _pick(root, ["chuck_main_body", "Cylinder"]), chuck_ad)
	for n in jaw_names:
		var j := _take(root, n, chuck_ad)
		if j:
			jaws.append(j)
			_jaw_dir.append(Vector2(j.position.x, j.position.y).normalized())

	# ---- Mitlaufende Spitze im Reitstock (Spitze zeigt zum Futter)
	var tip_z := -INF
	var back_z := INF
	var center_names: Array = _pick_set(root, [["live_center", "live_center_body_and_cone"], ["Cone", "Cylinder_011"]])
	for n in center_names:
		var c := root.find_child(n, true, false) as MeshInstance3D
		if c:
			for v in _verts(c, root):
				tip_z = maxf(tip_z, v.z)
				back_z = minf(back_z, v.z)
	if tip_z > -INF:
		var length := (tip_z - back_z) * SCALE
		var back_x := -0.3                       # Ende steckt in der Pinole
		var tip_x := back_x - length
		var ts_ad := _adapter(tailstock, Transform3D(_rs, Vector3(tip_x + tip_z * SCALE, axis_h, 0)))
		for n in center_names:
			_take(root, n, ts_ad)

	# ---- Schnellwechsel-Werkzeughalter auf dem Planschlitten
	_post = root.find_child(_pick(root, ["toolholder", "WerkzeughalterHalter"]), true, false) as Node3D
	if _post:
		var lever := root.find_child(_pick(root, ["tool_lever", "Cylinder_006"]), true, false) as Node3D
		var post_xf := _rel(_post, root)
		var lever_xf := _rel(lever, root) if lever else Transform3D.IDENTITY
		_detach(_post)
		_post.transform = Transform3D(post_xf.basis, Vector3.ZERO)
		_post_root = Node3D.new()
		cross_slide.add_child(_post_root)
		var post_ad := _adapter(_post_root, Transform3D(_rs, Vector3.ZERO))
		post_ad.add_child(_post)
		if lever:
			# Spannhebel dreht beim Indexieren nicht mit
			_detach(lever)
			post_ad.add_child(lever)
			lever.transform = Transform3D(post_xf.basis, Vector3.ZERO) * (post_xf.affine_inverse() * lever_xf)
			_lever = lever
			_lever_xf = lever.transform
		for id in TOOLS:
			var d: Dictionary = TOOLS[id]
			var rot: float = d["rot"]
			var h := _post.find_child(_pick(_post, d["holder"]), true, false) as Node3D
			if h == null:
				# Neues Modell: Halter liegen einzeln neben dem Kopf -> auf den Kopf setzen
				h = root.find_child(_pick(root, d["holder"]), true, false) as Node3D
				if h:
					_mount_loose(h, post_xf)
					rot = 0.0
			var ins: MeshInstance3D = null
			if h:
				ins = h.find_child(_pick(h, d["insert"]), true, false) as MeshInstance3D
			if h and ins:
				# direktes Kind des Halters, das die Platte trägt (Plattenhalter/Schaft)
				var sh: Node = ins
				while sh.get_parent() != null and sh.get_parent() != h:
					sh = sh.get_parent()
				_holders[id] = {"node": h, "rot": rot, "tip": _tip(ins, rot, str(d.get("ref", "chuck"))), "xf": h.transform,
					"shank": str(sh.name) if sh.get_parent() == h else ""}
		var h1 := _post.find_child(_pick(_post, TOOLS["T1"]["holder"]), true, false) as MeshInstance3D
		if h1:
			var mn := Vector3.INF
			var mx := -Vector3.INF
			for v in _verts(h1, _post):
				mn = mn.min(v)
				mx = mx.max(v)
			_slot_z = (mn.z + mx.z) * 0.5
			_shank_cz = _slot_z
		if _holders.has("T1"):
			var sn := (_holders["T1"]["node"] as Node).find_child(str(_holders["T1"]["shank"]), false, false) as MeshInstance3D
			if sn and sn.mesh and not sn.find_children("*", "MeshInstance3D", true, false).is_empty():
				var tip: Vector3 = _holders["T1"]["tip"]
				var smn := Vector3.INF
				var smx := -Vector3.INF
				var gmn := Vector3.INF
				var gmx := -Vector3.INF
				for v in _verts(sn, _post):
					smn = smn.min(v)
					smx = smx.max(v)
					var g := _rs * (v - tip) * 1000.0
					gmn = gmn.min(g)
					gmx = gmx.max(g)
				_shank_cz = (smn.z + smx.z) * 0.5
				shank_box = AABB(gmn, gmx - gmn)
		# Unterbau (Oberschlitten) bis unter den Halter
		var pm := _post as MeshInstance3D
		var bmin := Vector3.INF
		var bmax := -Vector3.INF
		if pm:
			for v in _verts(pm, _post):
				bmin = bmin.min(v)
				bmax = bmax.max(v)
		set_layout(["T1", "", "T3", ""], 0, axis_h)
		if pm:
			var bottom := _post_root.position.y + bmin.y * SCALE
			var h := bottom - slide_top
			if h > 0.001:
				var size := Vector3((bmax.z - bmin.z), 0, (bmax.x - bmin.x)) * SCALE * 1.1
				size.y = h
				Build.box(_post_root, size, Vector3(0, slide_top + h * 0.5 - _post_root.position.y, 0),
					Build.mat(Color(0.20, 0.22, 0.24), 0.55))
		shank_end_mm = _post_root.position.z * 1000.0
	root.free()
	return true


func has_tool(id: String) -> bool:
	return _holders.has(id)


## Vierfach-Werkzeughalter bestücken und indexieren. slots = Werkzeug-ID je Platz ("" = leer),
## active = Platz, der zum Werkstück zeigt. Der Kopf dreht je Platz um 90°; die Schneidenecke des
## aktiven Werkzeugs liegt danach genau im Bezugspunkt (Planschlitten-Ursprung auf Spitzenhöhe).
func set_layout(slots: Array, active: int, axis_h: float, zc_mm := 0.0) -> void:
	if _post_root == null:
		return
	for k in _holders:
		var h: Dictionary = _holders[k]
		var s := slots.find(k)
		var n := h["node"] as Node3D
		n.visible = s >= 0
		if s >= 0:
			# Halter aus seinem Modellplatz (rot) in Platz s umsetzen
			n.transform = Transform3D(Basis(Vector3.UP, float(h["rot"]) - s * PI * 0.5), Vector3.ZERO) * (h["xf"] as Transform3D)
			# unterlegen: Schneide auf dieselbe Höhe wie T1 (der Kopf hebt sich beim Wechsel nicht)
			n.transform.origin.y += _shim(k)
	set_pose(active * PI * 0.5, post_pos(str(slots[active]), axis_h, zc_mm))


## Kopf auf Drehwinkel angle stellen (Platz k zeigt bei k·90° zum Werkstück), Drehpunkt auf pos.
## lever 0..1: Spannhebel gelöst, Kopf dabei leicht angehoben (für die Einschwenk-Animation).
func set_pose(angle: float, pos: Vector3, lever := 0.0) -> void:
	if _post_root == null:
		return
	_post.transform.basis = Basis(Vector3.UP, angle)
	_post_root.position = pos + Vector3(0, lever * LIFT, 0)
	if _lever:
		_lever.transform = Transform3D(Basis(Vector3.UP, -LEVER_ANGLE * lever), Vector3.ZERO) * _lever_xf


const LIFT := 0.002            # m, Anheben des Kopfs beim Drehen
const LEVER_ANGLE := 1.1       # rad, Spannhebel lösen


## Klemmhalter aus dem Modell (Kopie des T1-Halters ohne Plattenhalter) für ein prozedurales
## Werkzeug, dessen Schaftmitte axial bei zc_mm (relativ zur Schneide) liegt und dessen Platte
## um ext_mm weiter auskragt. Lage im
## Koordinatensystem des Werkzeugknotens, wenn das Werkzeug eingeschwenkt ist. null ohne Modell.
func make_holder(axis_h: float, zc_mm: float, ext_mm := 0.0) -> Node3D:
	if not _holders.has("T1") or shank_box.size == Vector3.ZERO:
		return null
	var c := (_holders["T1"]["node"] as Node3D).duplicate() as Node3D
	var sh := c.find_child(str(_holders["T1"]["shank"]), false, false)
	if sh:
		c.remove_child(sh)
		sh.free()
	c.visible = true
	c.transform = _holders["T1"]["xf"]
	var w := Node3D.new()
	w.name = "Klemmhalter"
	w.transform = Transform3D(_rs, post_pos("", axis_h, zc_mm, ext_mm))
	w.add_child(c)
	return w


## Lage des Halterkopfs (Drehpunkt) relativ zur Schneide, wenn Werkzeug id eingeschwenkt ist
## (Planschlitten-Achsen, m). Daraus folgt die Werkzeugkorrektur (Lathe.tool_offset).
func post_pos(id: String, axis_h: float, zc_mm := 0.0, ext_mm := 0.0) -> Vector3:
	if _holders.has(id):
		var tip: Vector3 = _holders[id]["tip"]
		tip.y += _shim(id)
		return Vector3(0, axis_h, 0) - _rs * tip
	# Prozedurales Werkzeug: freier Platz nimmt den Schaft auf
	var ref: Dictionary = _holders.get("T1", {"tip": Vector3.ZERO})
	var p := Vector3(0, axis_h, 0) - _rs * (ref["tip"] as Vector3)
	p.x = zc_mm * 0.001 + _shank_cz * SCALE
	# Auskraglänge: Platte ragt weiter heraus, der Halter sitzt um ext_mm weiter außen
	p.z += ext_mm * 0.001
	return p


func update_jaws(stock_d_mm: float) -> void:
	var r := stock_d_mm * 0.5 * 0.001 / SCALE
	for i in jaws.size():
		jaws[i].position.x = _jaw_dir[i].x * r
		jaws[i].position.y = _jaw_dir[i].y * r


# ------------------------------------------------------------ Hilfen

## Im neuen Modell liegen die Halter (toolspanner*) einzeln neben dem Kopf statt auf ihm. Halter h
## auf die +Z-Seite des Kopfs setzen (Werkzeug zeigt dann in -X, also zum Werkstück in Platz 1):
## Halterrückseite liegt an der Kopffläche neben der Schwalbenschwanz-Feder, die Feder greift in
## die Nut des Halters. Höhe wie im Modell, seitlich mittig.
func _mount_loose(h: Node3D, post_xf: Transform3D) -> void:
	# Lage im Modell (bis unter die Modellwurzel)
	var hxf := h.transform
	var p := h
	while p.get_parent() is Node3D and p.get_parent().get_parent() != null:
		p = p.get_parent() as Node3D
		hxf = p.transform * hxf
	# Kopffläche: am weitesten in +Z liegende Ecke außerhalb der Feder
	var face := -INF
	var pm := _post as MeshInstance3D
	if pm and pm.mesh:
		var max_x := 0.0
		var pv := PackedVector3Array()
		for s in pm.mesh.get_surface_count():
			for v in pm.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var w: Vector3 = post_xf.basis * v
				pv.append(w)
				max_x = maxf(max_x, absf(w.x))
		for w in pv:
			if absf(w.x) > max_x * 0.6:
				face = maxf(face, w.z)
	if face == -INF:
		face = 0.0
	# Halterrückseite (ohne Unterteile wie Plattenhalter)
	var back := INF
	var hm := h as MeshInstance3D
	if hm and hm.mesh:
		for s in hm.mesh.get_surface_count():
			for v in hm.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				back = minf(back, (hxf.basis * v).z)
	if back == INF:
		back = 0.0
	_detach(h)
	_post.add_child(h)
	var inv := post_xf.basis.inverse()
	h.transform = Transform3D(inv * hxf.basis, inv * Vector3(0.0, hxf.origin.y - post_xf.origin.y, face - back))


## Schneidenecke im Halter-Koordinatensystem (nach Indexieren um rot):
## am nächsten zur Drehachse (-X), davon die Ecke zum Futter hin (+Z) bzw. bei ref "center" die
## Mitte der Spitze (Fasen-/Radiusplatten), Oberkante der Platte.
func _tip(ins: MeshInstance3D, rot: float, ref := "chuck") -> Vector3:
	var b := Basis(Vector3.UP, rot)
	var vs := PackedVector3Array()
	var min_x := INF
	var top := -INF
	for v in _verts(ins, _post):
		var w := b * v
		vs.append(w)
		min_x = minf(min_x, w.x)
		top = maxf(top, w.y)
	var best_z := -INF
	var lo_z := INF
	for w in vs:
		if w.x < min_x + 0.03:
			best_z = maxf(best_z, w.z)
		if w.x < min_x + 0.01:
			lo_z = minf(lo_z, w.z)
	if ref == "center":
		# Spitze: Mitte des vordersten Bereichs (beidseitig symmetrische Platte)
		var hi_z := -INF
		for w in vs:
			if w.x < min_x + 0.01:
				hi_z = maxf(hi_z, w.z)
		return Vector3(min_x, top, (lo_z + hi_z) * 0.5)
	return Vector3(min_x, top, best_z)


func _adapter(parent: Node3D, xf: Transform3D) -> Node3D:
	var n := Node3D.new()
	n.transform = xf
	parent.add_child(n)
	return n


## Knoten aus dem Modell lösen und unter new_parent hängen (Lage relativ zum Modell-Ursprung bleibt).
func _take(root: Node, node_name: String, new_parent: Node3D) -> Node3D:
	var n := root.find_child(node_name, true, false) as Node3D
	if n == null:
		push_warning("lathe.glb: Objekt '%s' fehlt" % node_name)
		return null
	var xf := _rel(n, root)
	_detach(n)
	new_parent.add_child(n)
	n.transform = xf
	return n


static func _rel(n: Node3D, root: Node) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


static func _verts(mi: MeshInstance3D, frame: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mi.mesh == null:
		return out
	var xf := _rel(mi, frame)
	for s in mi.mesh.get_surface_count():
		for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			out.append(xf * v)
	return out


## Flächen ohne Material (z. B. Spannhebel) bekommen dunklen Stahl statt Weiß.
static func _fix_materials(n: Node, fallback: Material) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m == null or m.resource_name == "":
					mi.set_surface_override_material(s, fallback)
	for c in n.get_children():
		_fix_materials(c, fallback)


## Aus dem Modell-Baum lösen; Besitzer zurücksetzen (sonst Warnungen beim Umhängen).
static func _detach(n: Node) -> void:
	n.get_parent().remove_child(n)
	_clear_owner(n)


static func _clear_owner(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_clear_owner(c)


## Erster Objektname aus names, den es im Modell gibt (neue und alte Blender-Namen).
static func _pick(root: Node, names: Array) -> String:
	for n in names:
		if root.find_child(n, true, false):
			return n
	return str(names[0])


## Erste Namensgruppe, deren erstes Objekt im Modell vorkommt.
static func _pick_set(root: Node, sets: Array) -> Array:
	for s in sets:
		if root.find_child(s[0], true, false):
			return s
	return sets[0]


## Höhenausgleich (Modelleinheiten) für Halter id, damit seine Schneide auf T1-Höhe liegt.
func _shim(id: String) -> float:
	if not _holders.has(id) or not _holders.has("T1"):
		return 0.0
	return float((_holders["T1"]["tip"] as Vector3).y) - float((_holders[id]["tip"] as Vector3).y)
