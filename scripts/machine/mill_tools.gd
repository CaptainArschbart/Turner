class_name MillTools
extends RefCounted
## Fräswerkzeuge als prozedurale 3D-Modelle. Modelliert in mm (die Wurzel skaliert auf Meter),
## Werkzeugachse = Y, Schneide bei y = 0, Schaft nach oben.

const SEGS := 72
const RINGS := 48
const STEEL := Color(0.72, 0.74, 0.77)
const DARK := Color(0.07, 0.07, 0.08)
const GOLD := Color(0.8, 0.6, 0.2)
const COATING := Color(0.15, 0.15, 0.19)

## Werkzeuge an der Fräsmaschine. kind: end_mill, face_mill, drill. d = Schneidkreis, z = Schneidenzahl,
## ap_max = größte Schnitttiefe, fz_max = größter Vorschub je Schneide (mm).
const TOOLS := [
	{"id": "F6", "name": "Schaftfräser Ø6", "kind": "end_mill", "d": 6.0, "total": 57.0, "flute": 13.0, "z": 4, "ap_max": 13.0, "fz_max": 0.04},
	{"id": "F8", "name": "Schaftfräser Ø8", "kind": "end_mill", "d": 8.0, "total": 63.0, "flute": 19.0, "z": 4, "ap_max": 19.0, "fz_max": 0.05},
	{"id": "F10", "name": "Schaftfräser Ø10", "kind": "end_mill", "d": 10.0, "total": 72.0, "flute": 22.0, "z": 4, "ap_max": 22.0, "fz_max": 0.06},
	{"id": "F12", "name": "Schaftfräser Ø12", "kind": "end_mill", "d": 12.0, "total": 83.0, "flute": 26.0, "z": 4, "ap_max": 26.0, "fz_max": 0.08},
	{"id": "F16", "name": "Schaftfräser Ø16", "kind": "end_mill", "d": 16.0, "total": 92.0, "flute": 32.0, "z": 4, "ap_max": 32.0, "fz_max": 0.1},
	{"id": "MK63", "name": "Messerkopf Ø63", "kind": "face_mill", "d": 63.0, "z": 7, "ap_max": 6.0, "fz_max": 0.25},
	{"id": "B10", "name": "Spiralbohrer Ø10", "kind": "drill", "d": 10.0, "z": 2, "ap_max": 87.0, "fz_max": 0.25},
]

static var _flute_cache: Dictionary = {}


static func build(id: String) -> Node3D:
	var root := Node3D.new()
	if id == "mill_machine":
		MillModel.build(root)
		return root
	root.scale = Vector3.ONE * 0.001
	match id:
		"end_mills":
			_end_mill_set(root)
		"face_mill":
			_face_mill(root, true)
		"face_mill_arbor":
			_face_mill_arbor(root)
		"inserts":
			_insert_set(root)
		"drill":
			_drill(root)
		"holders":
			_holder_set(root)
		_:
			push_error("Unbekanntes Fräswerkzeug: %s" % id)
	return root


## Abstand Schneide bis Spindelnase mit eingesetzter Aufnahme (mm).
static func tool_length(t: Dictionary) -> float:
	match str(t["kind"]):
		"face_mill":
			return 69.0
		"drill":
			return 209.0
	return float(t["total"]) - 15.0 + 47.0


## Werkzeug samt Aufnahme, so wie es in der Spindel sitzt: Schneide bei y = 0.
static func assembly(t: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * 0.001
	match str(t["kind"]):
		"face_mill":
			_face_mill(root, false)
			var arbor := Node3D.new()
			arbor.position.y = 31.0
			root.add_child(arbor)
			_face_mill_arbor(arbor)
		"drill":
			_drill(root)
			_drill_chuck(root, Vector3(0, 108.0, 0))
			_steep_taper(root, 190.0)
		_:
			end_mill(root, t["d"], t["total"], t["flute"])
			_collet_chuck(root, Vector3(0, float(t["total"]) - 15.0, 0))
	return root


# ------------------------------------------------------------ Werkzeuge

static func end_mill(parent: Node3D, d: float, total: float, flute: float, x := 0.0) -> void:
	var r := d * 0.5
	var turns := flute * tan(deg_to_rad(40.0)) / (PI * d)
	_add(parent, _flutes(r, flute, 4, turns, 0.62, 0.3, COATING, COATING.lightened(0.15)), _vertex_mat(0.28, 0.9), Vector3(x, 0, 0))
	var shank := PackedVector2Array([Vector2(r * 0.96, flute), Vector2(r * 0.96, flute * 1.12), Vector2(r, flute * 1.14),
		Vector2(r, total - d * 0.08), Vector2(r * 0.92, total), Vector2(0, total)])
	_add(parent, _revolve(shank), _steel(), Vector3(x, 0, 0))
	# Spannfläche am Schaft
	Build.box(parent, Vector3(d * 0.55, d * 0.85, 0.2), Vector3(x, total - d * 1.3, r - 0.05), Build.mat(STEEL.lightened(0.3), 0.5, 0.4))


static func _end_mill_set(root: Node3D) -> void:
	var x := 0.0
	for s in [[6.0, 57.0, 13.0], [8.0, 63.0, 19.0], [10.0, 72.0, 22.0], [12.0, 83.0, 26.0], [16.0, 92.0, 32.0]]:
		x += float(s[0]) * 0.5
		end_mill(root, s[0], s[1], s[2], x)
		x += float(s[0]) * 0.5 + 7.0


## show_face: Schneidseite nach oben drehen (Vorschau), sonst nach unten wie in der Spindel.
static func _face_mill(root: Node3D, show_face: bool) -> void:
	var body := Node3D.new()
	if show_face:
		body.rotation.x = PI
	root.add_child(body)
	var c := Color(0.09, 0.09, 0.1)
	var dark := Build.mat(c, 0.55, 0.35)
	var r := 29.5
	var bore := 19.5
	_add(body, _flutes(r, 26.0, 7, 0.04, 0.78, 0.35, c, c, 0.0, bore / r), _vertex_mat(0.55, 0.35))
	_add(body, _revolve(PackedVector2Array([Vector2(0, 18), Vector2(bore, 18), Vector2(bore, 0)])), dark)
	_add(body, _revolve(PackedVector2Array([Vector2(r, 26), Vector2(r, 30), Vector2(24, 38), Vector2(24, 50), Vector2(0, 50)])), dark)
	# Mitnehmernuten
	for a in [0.0, PI]:
		Build.box(body, Vector3(8, 6, 3), Vector3(cos(a) * 23.2, 47.5, sin(a) * 23.2), Build.mat(DARK, 0.8), false, Vector3(0, -a + PI / 2, 0))
	# Wendeplatten sitzen an der Spanlücke
	var plate := _plate(10.0, 10.0, 3.5, 2.0)
	var gold := _vertex_mat(0.35, 0.8)
	for k in 7:
		var a := TAU * k / 7.0
		var radial := Vector3(cos(a), 0, sin(a))
		var mi := _add(body, plate, gold)
		var basis := Basis(radial, Vector3.UP, radial.cross(Vector3.UP))
		# Außenkante der Platte auf dem Schneidkreis Ø63, leicht unter der Stirnfläche
		mi.transform = Transform3D(basis, radial * 26.5 + Vector3(0, 3.5, 0))


static func _face_mill_arbor(root: Node3D) -> void:
	var y0 := 19.0
	_add(root, _revolve(PackedVector2Array([Vector2(0, 0), Vector2(11, 0), Vector2(11, y0)])), _steel())
	_steep_taper(root, y0)
	var black := Build.mat(DARK, 0.5, 0.3)
	# Kreuzförmige Klemmschraube und Mitnehmersteine
	Build.box(root, Vector3(27, 7, 8), Vector3(0, -3.5, 0), black)
	Build.box(root, Vector3(8, 7, 27), Vector3(0, -3.5, 0), black)
	for x in [-14.0, 14.0]:
		Build.box(root, Vector3(7, 10, 13), Vector3(x, y0 - 4.0, 0), Build.mat(STEEL.darkened(0.25), 0.4, 0.7))
	Build.cyl(root, 4.0, 2.0, Vector3(31.6, y0 + 2.5, 0), black, Build.AXIS_X)


static func _insert_set(root: Node3D) -> void:
	var plate := _plate(17.0, 9.5, 3.5, 2.6)
	var gold := _vertex_mat(0.35, 0.8)
	for i in 6:
		var mi := _add(root, plate, gold)
		mi.rotation = Vector3(-PI / 2, 0, -0.5)
		mi.position = Vector3((i % 3 - 1) * 23.0, 0, (i / 3 - 0.5) * 18.0)


static func _drill(root: Node3D) -> void:
	var d := 10.0
	var total := 133.0
	var flute := 87.0
	var black := Color(0.06, 0.06, 0.07)
	var turns := flute * tan(deg_to_rad(30.0)) / (PI * d)
	_add(root, _flutes(d * 0.5, flute, 2, turns, 0.42, 0.55, black, GOLD, d * 0.3), _vertex_mat(0.35, 0.8))
	_add(root, _revolve(PackedVector2Array([Vector2(d * 0.48, flute), Vector2(d * 0.5, flute * 1.03), Vector2(d * 0.5, total - 0.5),
		Vector2(d * 0.44, total), Vector2(0, total)])), Build.mat(black, 0.35, 0.6))
	Build.box(root, Vector3(d * 0.6, d * 1.5, 0.2), Vector3(0, total - d * 1.1, d * 0.5 - 0.05), Build.mat(GOLD, 0.4, 0.7))


static func _holder_set(root: Node3D) -> void:
	_collet_chuck(root, Vector3(-30, 0, 0))
	_drill_chuck(root, Vector3(50, 0, 0))
	_collet(root, Vector3(-85, 0, 0))
	_collet(root, Vector3(-125, 0, 0))


static func _collet_chuck(parent: Node3D, pos: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	# Spannmutter
	_add(holder, _revolve(PackedVector2Array([Vector2(0, 9), Vector2(9, 9), Vector2(9, 0), Vector2(22, 0), Vector2(25, 3),
		Vector2(25, 24), Vector2(23, 28), Vector2(0, 28)])), Build.mat(DARK, 0.35, 0.5))
	for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		Build.box(holder, Vector3(6, 7, 2), Vector3(cos(a) * 24.5, 14, sin(a) * 24.5), Build.mat(STEEL.darkened(0.2), 0.4, 0.7), false, Vector3(0, -a + PI / 2, 0))
	_steep_taper(holder, 28.0)


static func _drill_chuck(parent: Node3D, pos: Vector3) -> void:
	var chuck := Node3D.new()
	chuck.position = pos
	parent.add_child(chuck)
	_add(chuck, _revolve(PackedVector2Array([Vector2(0, 8), Vector2(3.5, 8), Vector2(9, 0), Vector2(17, 0), Vector2(20, 4),
		Vector2(20, 18), Vector2(0, 18)])), _steel())
	_add(chuck, _revolve(PackedVector2Array([Vector2(20, 18), Vector2(25, 22), Vector2(25, 58), Vector2(21, 64),
		Vector2(14, 66), Vector2(14, 82), Vector2(12, 84), Vector2(0, 84)])), Build.mat(DARK, 0.5, 0.3))
	# Spannbacken
	for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var mi := Build.box(chuck, Vector3(5, 2, 2), Vector3(cos(a) * 3.5, 6, sin(a) * 3.5), _steel(), false, Vector3(0, -a, 0))
		mi.name = "Backe"


static func _collet(parent: Node3D, pos: Vector3) -> void:
	var collet := Node3D.new()
	collet.position = pos
	parent.add_child(collet)
	_add(collet, _revolve(PackedVector2Array([Vector2(6, 0), Vector2(12, 0), Vector2(16.5, 8), Vector2(16.5, 11),
		Vector2(11.5, 38), Vector2(6, 38), Vector2(6, 0)])), _steel())
	# Schlitze abwechselnd von beiden Enden
	for k in 8:
		var a := TAU * k / 8.0
		var y := 12.0 if k % 2 == 0 else 26.0
		Build.box(collet, Vector3(4, 24, 0.9), Vector3(cos(a) * (14.2 if k % 2 == 0 else 12.6), y, sin(a) * (14.2 if k % 2 == 0 else 12.6)),
			Build.mat(DARK, 0.8), false, Vector3(0, -a, 0))


## Steilkegel mit Greiferrille und Anzugsbolzen. y0 = Unterkante des Bunds.
static func _steep_taper(parent: Node3D, y0: float) -> void:
	var profile := PackedVector2Array()
	for p in [Vector2(0, 0), Vector2(31.5, 0), Vector2(31.5, 5), Vector2(27, 8), Vector2(27, 13), Vector2(31.5, 16), Vector2(31.5, 19),
			Vector2(22.2, 21), Vector2(12.65, 89), Vector2(8.5, 91), Vector2(0, 91)]:
		profile.append(p + Vector2(0, y0))
	_add(parent, _revolve(profile), _steel())
	var stud := PackedVector2Array()
	for p in [Vector2(7, 91), Vector2(7, 100), Vector2(9.5, 103), Vector2(9.5, 108), Vector2(0, 108)]:
		stud.append(p + Vector2(0, y0))
	_add(parent, _revolve(stud), Build.mat(Color(0.12, 0.35, 0.6), 0.4, 0.5))


# ------------------------------------------------------------ Geometrie

static func _steel() -> StandardMaterial3D:
	return Build.mat(STEEL, 0.3, 0.9)


static func _vertex_mat(rough: float, metal: float) -> StandardMaterial3D:
	var m := Build.mat(Color.WHITE, rough, metal)
	m.vertex_color_use_as_albedo = true
	return m


static func _add(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _ring(r: float, y: float, a: float) -> Vector3:
	return Vector3(r * cos(a), y, r * sin(a))


## Rotationskörper aus einem Profil (r, y). Außen von unten nach oben durchlaufen,
## damit die Flächen nach außen zeigen. Jedes Profilstück bekommt eine harte Kante.
static func _revolve(profile: PackedVector2Array, segs := SEGS) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in profile.size() - 1:
		st.set_smooth_group(s)
		var p0 := profile[s]
		var p1 := profile[s + 1]
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var v0 := _ring(p0.x, p0.y, a0)
			var v1 := _ring(p0.x, p0.y, a1)
			var v2 := _ring(p1.x, p1.y, a1)
			var v3 := _ring(p1.x, p1.y, a0)
			if p0.x > 0.0:
				for v in [v0, v1, v2]:
					st.add_vertex(v)
			if p1.x > 0.0:
				for v in [v0, v2, v3]:
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Schneidenteil mit wendelförmigen Spannuten. Tiefe Nuten erhalten c_flute, die Stege c_land.
## tip > 0 spitzt das untere Ende kegelig an, cap_r ist der Innenradius der Stirnfläche (Anteil von r).
static func _flutes(r: float, length: float, flutes: int, turns: float, core: float, land: float,
		c_land: Color, c_flute: Color, tip := 0.0, cap_r := 0.0) -> ArrayMesh:
	var key := str([r, length, flutes, turns, core, land, c_land, c_flute, tip, cap_r])
	if _flute_cache.has(key):
		return _flute_cache[key]
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	for j in RINGS + 1:
		var y := length * j / RINGS
		for i in SEGS:
			var a := TAU * i / SEGS
			var u := fposmod(flutes * (a / TAU - turns * y / length), 1.0)
			var depth := 0.0
			if u >= land:
				depth = sin(PI * pow((u - land) / (1.0 - land), 0.7))
			# Die Nut läuft zum Schaft hin aus
			depth *= 1.0 - smoothstep(length * 0.82, length, y)
			var rr := r * (1.0 - (1.0 - core) * depth)
			if tip > 0.0:
				rr *= lerpf(0.12, 1.0, clampf(y / tip, 0.0, 1.0))
			pos.append(_ring(rr, y, a))
			col.append(c_land.lerp(c_flute, smoothstep(0.05, 0.25, depth)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for j in RINGS:
		for i in SEGS:
			var n := (i + 1) % SEGS
			var a0 := j * SEGS + i
			var b0 := j * SEGS + n
			var b1 := (j + 1) * SEGS + n
			var a1 := (j + 1) * SEGS + i
			for k in [a0, b0, b1, a0, b1, a1]:
				st.set_color(col[k])
				st.add_vertex(pos[k])
	# Stirnfläche
	st.set_smooth_group(1)
	st.set_color(c_land)
	for i in SEGS:
		var n := (i + 1) % SEGS
		var i0 := _ring(r * cap_r, 0.0, TAU * i / SEGS)
		var i1 := _ring(r * cap_r, 0.0, TAU * n / SEGS)
		for v in [i0, i1, pos[n], i0, pos[n], pos[i]]:
			st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	_flute_cache[key] = mesh
	return mesh


## Wendeplatte: abgerundetes Parallelogramm mit Bohrung, Dicke in Z, nach unten verjüngt.
static func _plate(w: float, h: float, t: float, hole: float) -> ArrayMesh:
	var n := 48
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := func(i: int, z: float, s: float) -> Vector3:
		var a := TAU * i / n
		var c := cos(a)
		var d := sin(a)
		var x := signf(c) * pow(absf(c), 1.0 / 3.0) * w * 0.5
		var y := signf(d) * pow(absf(d), 1.0 / 3.0) * h * 0.5
		return Vector3((x + y * 0.3) * s, y * s, z)
	var circle := func(i: int, z: float) -> Vector3:
		var a := TAU * i / n
		return Vector3(cos(a) * hole, sin(a) * hole, z)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
	var gold := GOLD
	var hole_c := DARK
	var top := t * 0.5
	for i in n:
		var k := i + 1
		st.set_color(gold)
		st.set_smooth_group(0)
		quad.call(circle.call(i, top), circle.call(k, top), outline.call(k, top, 1.0), outline.call(i, top, 1.0))
		st.set_smooth_group(1)
		quad.call(outline.call(i, -top, 0.86), outline.call(k, -top, 0.86), circle.call(k, -top), circle.call(i, -top))
		st.set_smooth_group(2)
		quad.call(outline.call(i, top, 1.0), outline.call(k, top, 1.0), outline.call(k, -top, 0.86), outline.call(i, -top, 0.86))
		st.set_color(hole_c)
		st.set_smooth_group(3)
		quad.call(circle.call(i, -top), circle.call(k, -top), circle.call(k, top), circle.call(i, top))
	st.generate_normals()
	return st.commit()
