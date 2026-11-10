class_name LatheModel
extends RefCounted
## Bindet die Blender-Modelle aus models/lathe.glb in die Drehmaschine ein:
## Futter mit 3 Backen, Schnellwechsel-Werkzeughalter (Schrupp-, Schlicht-, 45°-Fasen- und Stechmeißel),
## mitlaufende Spitze und - im E50-Modell - die ganze Maschine: Verkleidung, Bett mit Führungsbahnen,
## Bett-, Plan- und Oberschlitten, Haupttür mit Bedienpult, Futterschutz und Späneförderer.
##
## Modell-Koordinaten (nach _normalize, wie im ersten Blender-Export): Spindelachse = Z durch den
## Ursprung, Werkstück liegt Richtung -Z, Werkzeuge zeigen in -X.
## Spiel-Koordinaten (Lathe): Spindelachse = +X (weg vom Futter), Bedienerseite/radial = +Z.
## -> Drehung -90° um Y, danach Skalierung. Im E50-Modell gilt ein Maßstab für alles (Maschine, Futter,
## Werkzeugkopf): die Spindelachse liegt auf Spitzenhöhe REF_AXIS_H. Futtermaße und Werkzeuggröße
## gibt das Modell an Lathe weiter (chuck_r_mm, chuck_depth_mm, tool_scale). Nur die mitlaufende
## Spitze behält ihre Länge (sie steckt im prozeduralen Reitstock).

const PATH := "res://models/lathe.glb"
const SCALE := 0.032          # m pro Modelleinheit im Werkzeugkopf (Halter-Koordinaten)
## Werkzeugkopf samt Haltern und Platten zusätzlich vergrößert (um die Schneide), damit die
## Werkzeuge im Spiel gut erkennbar sind. Korrekturen und Kollisionen folgen dieser Größe.
const TOOL_SCALE := 1.35
const CHUCK_D := 0.3          # altes Modell: Futterkörper Ø 300 mm
const REF_AXIS_H := 1.17      # m Spitzenhöhe der konventionellen Maschinen (Maßstab für Futter und Werkzeugkopf dort)
## E50-Modell: fester Maßstab (m pro Blender-Einheit). Die Spitzenhöhe der CNC-Maschine folgt aus dem
## Modell (e50_axis_h): wird das Modell in Blender vergrößert, wächst die Maschine im Spiel mit -
## samt Futter und Werkzeugkopf. Die konventionellen Maschinen nehmen nur Futter und Werkzeugkopf aus
## dem Modell und skalieren sie weiter auf ihre Spitzenhöhe REF_AXIS_H.
const E50_SCALE := 1.17 / 7.2345   # Spitzenhöhe 1,17 m bei 7,2345 Einheiten in der ersten E50-Fassung
const CENTER_LEN := 0.1444    # mitlaufende Spitze: Spitze bis Ende des Kegelschafts (m)
## Werkzeug-ID -> Halter im Modell (Objektnamen: neues Modell zuerst, dann altes). rot = Drehung des Werkzeughalters (Indexieren), damit der Halter zum Werkstück zeigt.
const TOOLS := {
	"T1": {"holder": ["toolspanner", "Werkzeughalter"], "insert": ["insert", "Cube_007"], "rot": 0.0},
	"T3": {"holder": ["toolspanner2", "Werkzeughalter_001"], "insert": ["insert_001", "Cube_011"], "rot": PI},
	# 45°-Fasenmeißel: quadratische Platte über Eck, Spitze zeigt zur Drehachse (ref "center")
	"T5": {"holder": ["toolspanner3"], "insert": ["Cube"], "rot": 0.0, "ref": "center"},
	# Stechschwert im Blockhalter (sword_holder): Stechplatte sword_insert auf dem Schwert sword, Ecke zum Futter
	"T6": {"holder": ["toolspanner4"], "insert": ["sword_insert", "Cube_003"], "rot": 0.0},
}

## E50-Teile (nur im neuen Modell). Feste Teile hängen an der Maschine, die Schlittengruppen an
## Bett- bzw. Planschlitten, die Türen an eigenen Knoten, die die Maschine verschiebt.
const STATIC_PARTS := ["machine_body", "rails", "machine_door_roller_rail", "machine_spindle_body",
	"chuck_protector_rail_long", "chuck_protector_rail_short", "ballspindle_protector",
	"chip_conveyor_sheet", "chip_conveyor_sheet_001", "lamp_body", "lamp_body_001", "lamp", "lamp_001"]
## Leuchtende Teile der Signallampen (an der Verkleidung; lamp_002 sitzt an der Haupttür)
const LAMP_PARTS := ["lamp", "lamp_001", "lamp_002"]
const CARRIAGE_PARTS := ["z_axis", "z_axis_scale", "z_axis_wheel", "settings_table_with_knobs",
	"spindle_starter", "spindle_starter_base"]
const CROSS_PARTS := ["x_axis", "x_axis_scale", "x_axis_wheel"]
const TOP_PARTS := ["uppder_z_axis", "upper_z_axis_scale", "upper_z_axis_wheel"]
const SPARE_PARTS := ["parallel_shim_001", "parallel_shim"]   # liegen nur im Modell herum
## Farben für Teile ohne Material im Modell
const PART_COLORS := {
	"machine_body": Color(0.90, 0.91, 0.91), "settings_table_with_knobs": Color(0.06, 0.18, 0.58),
	"z_axis": Color(0.70, 0.72, 0.74), "x_axis": Color(0.62, 0.64, 0.66), "uppder_z_axis": Color(0.56, 0.58, 0.6),
	"ballspindle_protector": Color(0.74, 0.75, 0.76), "chip_conveyor": Color(0.33, 0.35, 0.37),
	"chip_conveyor_sheet": Color(0.74, 0.75, 0.76), "chip_conveyor_sheet_001": Color(0.74, 0.75, 0.76),
	"machine_spindle_body": Color(0.72, 0.73, 0.75),
}
const ROOF_Y := 1.6           # m bei Spitzenhöhe REF_AXIS_H: Dreiecke der Verkleidung darüber bilden das Dach (eigene Sichtebene)

var jaws: Array[Node3D] = []
var _jaw_dir: Array[Vector2] = []
var _jaw_p0: Array[Vector2] = []   # Backenknoten im Modell (Futter-Koordinaten, Achse = Ursprung)
var _jaw_r0: Array[float] = []     # Abstand der Backen-Spannfläche von der Achse im Modell
var _chuck_s := SCALE         # m pro Modelleinheit am Futter
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
var _rt: Basis                # Werkzeugkopf: Drehung und Maßstab (SCALE · TOOL_SCALE)
var _axis_y0 := 0.0           # Spitzenhöhe im Modell über dem Boden (nur E50)
var _kh := 1.0                # Spitzenhöhe im Spiel / REF_AXIS_H (Höhen, die mit der Maschine wachsen)
var model_scale := 0.0        # m pro Modelleinheit im E50-Modell (0 = altes Modell, feste Maße)
var tool_scale := TOOL_SCALE  # Werkzeugkopf: Vergrößerung gegenüber SCALE (E50: aus dem Modell)
var chuck_r_mm := CHUCK_D * 500.0
var chuck_depth_mm := 146.0
var _jaw_front := 0.0         # Backenstirn im Modell (z)
var _post_bottom := 0.0       # Unterkante des Werkzeugkopfs (Halter-Koordinaten)
var _max_tip_y := -INF        # höchste Schneide aller Halter (Halter-Koordinaten)
var _tip_target := NAN        # Schneidenhöhe = Drehmitte bei Kopf auf Modellhöhe (Halter-Koordinaten, nur E50)
## Lage und Maße der E50-Teile in Maschinenkoordinaten (leer ohne E50-Modell), siehe _build_machine
var mach := {}


static func available() -> bool:
	return ResourceLoader.exists(PATH)


## Spitzenhöhe (m) der CNC-Maschine aus dem E50-Modell: Höhe der Futtermitte über dem Boden mal
## E50_SCALE. Liest nur die Knotenlagen der Szene (ohne sie zu instanziieren). 0 ohne E50-Modell.
static func e50_axis_h() -> float:
	if not available():
		return 0.0
	var ps := load(PATH) as PackedScene
	if ps == null:
		return 0.0
	var st := ps.get_state()
	var xf := {}                  # Knotenpfad -> Lage relativ zur Wurzel
	var chuck := ""
	var chuck_c := Vector3.ZERO     # Mitte des Futterkörper-Meshs (Mesh-Koordinaten)
	var body := false
	for i in st.get_node_count():
		var path := str(st.get_node_path(i))
		var parent := str(st.get_node_path(i, true))
		var t := Transform3D.IDENTITY
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) == &"transform":
				t = st.get_node_property_value(i, p)
		xf[path] = (xf[parent] as Transform3D) * t if xf.has(parent) and i > 0 else (t if i > 0 else Transform3D.IDENTITY)
		var nm := str(st.get_node_name(i))
		if nm == "chuck_main_body":
			chuck = path
			for p in st.get_node_property_count(i):
				if st.get_node_property_name(i, p) == &"mesh" and st.get_node_property_value(i, p) is Mesh:
					chuck_c = (st.get_node_property_value(i, p) as Mesh).get_aabb().get_center()
		elif nm == "machine_body":
			body = true
	if chuck == "" or not body:
		return 0.0
	# Drehachse = Mitte des Futterkörpers (nicht der Objekt-Ursprung, der in Blender versetzt sein kann)
	return ((xf[chuck] as Transform3D) * chuck_c).y * E50_SCALE


func _init() -> void:
	_rs = Basis(Vector3.UP, -PI / 2.0)
	_rt = _rs * Basis.from_scale(Vector3.ONE * SCALE * tool_scale)


## Baut alles ein. Gibt false zurück, falls das Modell fehlt (dann bleibt die prozedurale Maschine).
## parts (optional, nur CNC-Maschine): {"machine", "carriage", "door", "guard", "periphery"} -
## Knoten, unter die die E50-Teile gehängt werden. Ergebnis dann in mach.
func build(spindle_pivot: Node3D, cross_slide: Node3D, tailstock: Node3D, axis_h: float, slide_top: float, parts := {}) -> bool:
	if not available():
		return false
	var ps := load(PATH) as PackedScene
	if ps == null:
		return false
	var root := ps.instantiate() as Node3D
	var e50 := root.find_child("machine_body", true, false) != null
	if e50:
		_normalize(root)
		if parts.has("machine"):
			model_scale = E50_SCALE           # axis_h = e50_axis_h()
		else:
			model_scale = REF_AXIS_H / maxf(_axis_y0, 0.001)
		_kh = axis_h / REF_AXIS_H
	var dark := Build.mat(Color(0.08, 0.08, 0.09), 0.5, 0.8)
	_fix_materials(root, dark)

	# ---- Futter + Backen (drehen mit der Spindel). Maßstab: Futterkörper Ø CHUCK_D
	var body_name := _pick(root, ["chuck_main_body", "Cylinder"])
	var body := root.find_child(body_name, true, false) as MeshInstance3D
	var bmn := Vector3.ZERO
	var bmx := Vector3.ZERO
	if body:
		var bb := _bounds(_verts(body, root))
		bmn = bb.position
		bmx = bb.end
		if model_scale > 0.0:
			_chuck_s = model_scale
		elif bmx.x - bmn.x > 0.0001:
			_chuck_s = CHUCK_D / (bmx.x - bmn.x)
		chuck_r_mm = (bmx.x - bmn.x) * 0.5 * _chuck_s * 1000.0
	var jaw_names: Array = _pick_set(root, [["Jaw1", "Jaw2", "Jaw3"], ["Cube_001", "Cube_002", "Cube_003"]])
	var jaw_front := INF
	for n in jaw_names:
		var j := root.find_child(n, true, false) as MeshInstance3D
		if j:
			for v in _verts(j, root):
				jaw_front = minf(jaw_front, v.z)
	if jaw_front == INF:
		jaw_front = 0.0
	_jaw_front = jaw_front
	if body:
		chuck_depth_mm = (bmx.z - jaw_front) * _chuck_s * 1000.0   # Futterrückseite hinter der Backenstirn
	var chuck_ad := _adapter(spindle_pivot, Transform3D(_rs * Basis.from_scale(Vector3.ONE * _chuck_s), Vector3(jaw_front * _chuck_s, 0, 0)))
	# Backen zuerst lösen: im neuen Modell hängen sie am Futterkörper
	for n in jaw_names:
		var j := _take(root, n, chuck_ad)
		if j:
			jaws.append(j)
			# Richtung und Spannfläche aus der Backengeometrie (die Objekt-Ursprünge der Backen liegen
			# im Modell nicht symmetrisch zur Achse, die Backen selbst schon)
			var jv := _verts(j, chuck_ad)
			var jc := Vector2.ZERO
			for v in jv:
				jc += Vector2(v.x, v.y)
			var dir := (jc / maxf(jv.size(), 1)).normalized()
			var r0 := INF
			for v in jv:
				r0 = minf(r0, Vector2(v.x, v.y).dot(dir))
			_jaw_dir.append(dir)
			_jaw_p0.append(Vector2(j.position.x, j.position.y))
			_jaw_r0.append(r0 if r0 != INF else 0.0)
	_take(root, body_name, chuck_ad)

	# ---- Mitlaufende Spitze im Reitstock (Spitze zeigt zum Futter)
	var tip_z := -INF
	var back_z := INF
	var cmn := Vector3.INF
	var cmx := -Vector3.INF
	var center_names: Array = _pick_set(root, [["live_center", "live_center_body_and_cone"], ["Cone", "Cylinder_011"]])
	for n in center_names:
		var c := root.find_child(n, true, false) as MeshInstance3D
		if c:
			for v in _verts(c, root):
				tip_z = maxf(tip_z, v.z)
				back_z = minf(back_z, v.z)
				cmn = cmn.min(v)
				cmx = cmx.max(v)
	# E50 mit eigenem Reitstock im Modell: die Spitze bleibt in dessen Pinole (siehe _build_tailstock)
	var model_ts := e50 and parts.has("tailstock") and root.find_child("tailstock_body", true, false) != null
	if tip_z > -INF and tip_z - back_z > 0.0001 and not model_ts:
		var cs := CENTER_LEN / (tip_z - back_z)
		var cc := (cmn + cmx) * 0.5                            # Spitzenachse (x, y) im Modell
		var back_x := -0.3                                     # Ende steckt in der Pinole
		var tip_x := back_x - CENTER_LEN
		var ts_ad := _adapter(tailstock, Transform3D(_rs * Basis.from_scale(Vector3.ONE * cs),
			Vector3(tip_x + tip_z * cs, axis_h - cc.y * cs, -cc.x * cs)))
		for n in center_names:
			_take(root, n, ts_ad)

	# ---- Schnellwechsel-Werkzeughalter auf dem Planschlitten
	_post = root.find_child(_pick(root, ["toolholder", "WerkzeughalterHalter"]), true, false) as Node3D
	var post_xf := Transform3D.IDENTITY
	var bmin := Vector3.INF
	if _post:
		var lever := root.find_child(_pick(root, ["tool_lever", "Cylinder_006"]), true, false) as Node3D
		post_xf = _rel(_post, root)
		if model_scale > 0.0:
			# Werkzeugkopf im Modellmaßstab (Halter-Koordinaten = Mesh-Koordinaten des Kopfs)
			tool_scale = post_xf.basis.get_scale().x * model_scale / SCALE
			_rt = _rs * Basis.from_scale(Vector3.ONE * SCALE * tool_scale)
			# Kopf bleibt auf seiner Modellhöhe: Spindelachse in Halter-Koordinaten
			_tip_target = -post_xf.origin.y / post_xf.basis.get_scale().y
		var pmi := _post as MeshInstance3D
		if pmi and pmi.mesh:
			_post_bottom = INF
			for sfc in pmi.mesh.get_surface_count():
				for v in pmi.mesh.surface_get_arrays(sfc)[Mesh.ARRAY_VERTEX]:
					_post_bottom = minf(_post_bottom, v.y)
		var lever_xf := _rel(lever, root) if lever else Transform3D.IDENTITY
		_detach(_post)
		# Halter-Koordinaten = Koordinaten des Kopf-Meshs (ohne die Knotenskalierung im Modell)
		_post.transform = Transform3D.IDENTITY
		_post_root = Node3D.new()
		cross_slide.add_child(_post_root)
		var post_ad := _adapter(_post_root, Transform3D(_rt, Vector3.ZERO))
		post_ad.add_child(_post)
		if lever:
			# Spannhebel dreht beim Indexieren nicht mit
			_detach(lever)
			post_ad.add_child(lever)
			lever.transform = post_xf.affine_inverse() * lever_xf
			_lever = lever
			_lever_xf = lever.transform
		for id in TOOLS:
			var d: Dictionary = TOOLS[id]
			var rot: float = d["rot"]
			var h := _post.find_child(_pick(_post, d["holder"]), true, false) as Node3D
			if h and not _on_post(h):
				# Halter hängt im Modell unter dem Kopf, liegt aber daneben (in Blender geparentet) -> aufsetzen
				_mount_loose(h, post_xf)
				rot = 0.0
			elif h == null:
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
				_max_tip_y = maxf(_max_tip_y, float((_holders[id]["tip"] as Vector3).y))
		var h1 := _post.find_child(_pick(_post, TOOLS["T1"]["holder"]), true, false) as MeshInstance3D
		if h1:
			var hb := _bounds(_verts(h1, _post))
			_slot_z = (hb.position.z + hb.end.z) * 0.5
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
					var g := _rt * (v - tip) * 1000.0
					gmn = gmn.min(g)
					gmx = gmx.max(g)
				_shank_cz = (smn.z + smx.z) * 0.5
				shank_box = AABB(gmn, gmx - gmn)
		var pm := _post as MeshInstance3D
		var bmax := -Vector3.INF
		if pm:
			for v in _verts(pm, _post):
				bmin = bmin.min(v)
				bmax = bmax.max(v)
		set_layout(["T1", "", "T3", ""], 0, axis_h)
		var with_slides := e50 and parts.has("machine")
		if pm and not with_slides:
			# Unterbau (Oberschlitten) bis unter den Halter
			var bottom := _post_root.position.y + bmin.y * SCALE * tool_scale
			var h := bottom - slide_top
			if h > 0.001:
				var size := Vector3((bmax.z - bmin.z), 0, (bmax.x - bmin.x)) * SCALE * tool_scale * 1.1
				size.y = h
				Build.box(_post_root, size, Vector3(0, slide_top + h * 0.5 - _post_root.position.y, 0),
					Build.mat(Color(0.40, 0.19, 0.14), 0.6))   # oxidrot grundiert wie an der E50 HD
		shank_end_mm = _post_root.position.z * 1000.0

	if e50 and parts.has("machine"):
		var post_bottom := _post_root.position.y + bmin.y * SCALE * tool_scale if _post_root and bmin != Vector3.INF else axis_h - 0.05
		_build_machine(root, parts, spindle_pivot, cross_slide, axis_h, post_xf, post_bottom)
	root.free()
	return true


# ------------------------------------------------------------ E50-Maschine

## Verkleidung, Bett, Schlitten, Türen und Späneförderer einhängen. Die Maschine wird so skaliert, dass
## die Spindelachse auf axis_h liegt; die Spindelnase (Flansch) liegt an der Futterrückseite.
## Die Schlitten stehen relativ zum Werkzeugkopf wie im Modell und fahren mit ihm.
func _build_machine(root: Node3D, parts: Dictionary, spindle_pivot: Node3D, cross_slide: Node3D, axis_h: float,
		post_xf: Transform3D, post_bottom: float) -> void:
	var m := model_scale
	# Modell (x, y, z) -> Spiel (-(z - Backenstirn)·m, y·m + axis_h, x·m): alles im selben Maßstab wie das Futter
	var mxf := Transform3D(_rs * Basis.from_scale(Vector3.ONE * m), Vector3(_jaw_front * m, axis_h, 0))
	# Rundes Teil hinten auf der Spindelbohrung: dreht mit der Spindel
	if root.find_child("spindle_bore_cap", true, false):
		var cap_ad := _adapter(spindle_pivot, Transform3D(mxf.basis, Vector3(mxf.origin.x, 0, 0)))
		cap_ad.name = "Spindelende"
		_take(root, "spindle_bore_cap", cap_ad)
	mach = {"scale": m}
	var machine := parts["machine"] as Node3D
	var mach_ad := _adapter(machine, mxf)
	mach_ad.name = "E50"
	for n in SPARE_PARTS:
		var s := root.find_child(n, true, false)
		if s:
			s.get_parent().remove_child(s)
			s.free()
	var bed_top := 0.0
	for n in STATIC_PARTS:
		var p := _take(root, n, mach_ad)
		if p and n == "rails":
			var rb := _bounds(_xf_verts(p, mach_ad, mxf))
			bed_top = rb.end.y
			mach["rails"] = rb
	mach["bed_top"] = bed_top
	if parts.has("tailstock") and root.find_child("tailstock_body", true, false):
		_build_tailstock(root, parts["tailstock"], mxf)
	var body := mach_ad.find_child("machine_body", false, false) as MeshInstance3D
	if body:
		mach["body"] = _bounds(_xf_verts(body, mach_ad, mxf))
		mach["roof"] = _split_roof(body, mach_ad, mxf, ROOF_Y * _kh)
	if parts.has("periphery"):
		var conv_ad := _adapter(parts["periphery"], mxf)
		var conv := _take(root, "chip_conveyor", conv_ad)
		if conv:
			mach["conveyor"] = _bounds(_xf_verts(conv, conv_ad, mxf))

	# Schlitten: Lage relativ zum Werkzeugkopf wie im Modell
	var post_game := mxf * post_xf.origin
	var off := Vector3.ZERO
	if _post_root:
		off = Vector3(_post_root.position.x - post_game.x, 0, _post_root.position.z - post_game.z)
	if parts.has("carriage"):
		var car_xf := Transform3D(Basis.IDENTITY, Vector3(off.x, 0, 0)) * mxf
		var car_ad := _adapter(parts["carriage"], car_xf)
		car_ad.name = "Bettschlitten"
		var cb := AABB()
		var first := true
		for n in CARRIAGE_PARTS:
			var p := _take(root, n, car_ad)
			if p:
				var b := _bounds(_xf_verts(p, car_ad, car_xf))
				cb = b if first else cb.merge(b)
				first = false
		mach["carriage"] = cb                               # relativ zum Bettschlitten-Knoten
	var cross_xf := Transform3D(Basis.IDENTITY, off) * mxf
	var cross_ad := _adapter(cross_slide, cross_xf)
	cross_ad.name = "Planschlitten"
	for n in CROSS_PARTS:
		_take(root, n, cross_ad)
	# Oberschlitten: trägt den Werkzeugkopf. Die Halter sind per Höhenverstellung auf Spitzenhöhe
	# gestellt, der Kopf sitzt dadurch etwas anders als im Modell -> Oberschlitten um denselben Betrag
	var top := root.find_child(TOP_PARTS[0], true, false) as MeshInstance3D
	var lower := Transform3D.IDENTITY
	if top:
		var tb := _bounds(_xf_verts(top, root, cross_xf))
		lower = Transform3D(Basis.IDENTITY, Vector3(0, post_bottom - tb.end.y, 0))
	var top_ad := _adapter(cross_slide, lower * cross_xf)
	top_ad.name = "Oberschlitten"
	for n in TOP_PARTS:
		_take(root, n, top_ad)

	# Haupttür mit Griff und Bedienpult: offen ganz links (vor dem Spindelkasten)
	var door := root.find_child("main_door", true, false) as MeshInstance3D
	var body_box: AABB = mach.get("body", AABB())
	if door and parts.has("door"):
		var db := _bounds(_xf_verts(door, root, mxf))
		var open_dx := body_box.position.x + 0.005 - db.position.x
		var door_xf := Transform3D(Basis.IDENTITY, Vector3(open_dx, 0, 0)) * mxf
		var door_ad := _adapter(parts["door"], door_xf)
		door_ad.name = "Haupttuer"
		var glass := AABB()
		var dmi := door
		for s in dmi.mesh.get_surface_count():
			var mat := dmi.mesh.surface_get_material(s)
			if mat and mat.resource_name == "glass":
				glass = _bounds(_xf_verts(dmi, root, door_xf, s))
		var handle := door.find_child("handle", true, false) as MeshInstance3D
		var panel := door.find_child("panel", true, false) as MeshInstance3D
		var hb := _bounds(_xf_verts(handle, root, door_xf)) if handle else AABB()
		var pv := _xf_verts(panel, root, door_xf) if panel else PackedVector3Array()
		_take(root, "main_door", door_ad)
		var full := _bounds(_xf_verts(door, door_ad, door_xf))
		mach["door"] = full
		mach["door_frame"] = db.size
		mach["glass"] = glass if glass.size != Vector3.ZERO else full
		mach["handle"] = hb
		mach["door_mesh"] = door
		if not pv.is_empty():
			mach["pult"] = _pult_face(pv)
		mach["panel_mesh"] = panel
		mach["handle_mesh"] = handle

	# Futterschutz: Schiebetür auf zwei Schienen, im Modell zu (deckt das Futter ab), öffnet nach links
	var guard := root.find_child("chuck_protector_door", true, false) as MeshInstance3D
	if guard and parts.has("guard"):
		var guard_ad := _adapter(parts["guard"], mxf)
		guard_ad.name = "Futterschutz"
		_take(root, "chuck_protector_door", guard_ad)
		var gb := _bounds(_xf_verts(guard, guard_ad, mxf))
		mach["guard"] = gb
		var rail_x := gb.position.x
		for n in ["chuck_protector_rail_long", "chuck_protector_rail_short"]:
			var r := mach_ad.find_child(n, false, false) as MeshInstance3D
			if r:
				rail_x = minf(rail_x, _bounds(_xf_verts(r, mach_ad, mxf)).position.x)
		mach["guard_travel"] = maxf(gb.position.x - rail_x, 0.0)
		mach["guard_mesh"] = guard

	# Signallampen: leuchten, solange die Maschine eingeschaltet ist (schaltet Lathe)
	var lamps: Array[MeshInstance3D] = []
	for n in LAMP_PARTS:
		var l := mach_ad.find_child(n, true, false) as MeshInstance3D
		if l == null and mach.has("door_mesh"):
			l = door.find_child(n, true, false) as MeshInstance3D
		if l:
			lamps.append(l)
	# Röhren und Gehäuse werfen keinen Schatten: das Dach lässt die Sonne durch (Bedienkamera), sonst
	# zeichnen sich die Gehäuse als Balken an der Rückwand ab
	for n in LAMP_PARTS + ["lamp_body", "lamp_body_001", "lamp_body_002"]:
		var g := mach_ad.find_child(n, true, false) as GeometryInstance3D
		if g == null and mach.has("door_mesh"):
			g = door.find_child(n, true, false) as GeometryInstance3D
		if g:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mach["lamps"] = lamps


## Reitstock aus dem E50-Modell unter slide (verschiebt Lathe längs des Betts): Körper fest, die Pinole
## mit der mitlaufenden Spitze auf eigenem Knoten (fährt in -X aus), das große Handrad dreht um die
## Pinolenachse, der Klemmhebel (im Modell Teil des Körpers) um seine Querwelle. Ergebnis in mach["ts"].
func _build_tailstock(root: Node3D, slide: Node3D, mxf: Transform3D) -> void:
	var ts_ad := _adapter(slide, mxf)
	ts_ad.name = "Reitstock"
	var body := _take(root, "tailstock_body", ts_ad) as MeshInstance3D
	var shaft := _pick(root, ["Cylinder_013", "Cylinder.013"])
	if root.find_child(shaft, true, false):
		_take(root, shaft, ts_ad)
	var ts := {}
	if body:
		ts["box"] = _bounds(_xf_verts(body, ts_ad, mxf))
	# Pinole samt Spitze (hängt im Modell an der Pinole)
	var quill := Node3D.new()
	quill.name = "Pinole"
	slide.add_child(quill)
	var q_ad := _adapter(quill, mxf)
	var pin := _take(root, "tailstock", q_ad)
	var axis := Vector3.ZERO
	if pin:
		axis = mxf * _rel(pin, q_ad).origin      # Pinolenachse (y, z) im Reitstock
		var meshes: Array = pin.find_children("*", "MeshInstance3D", true, false)
		if pin is MeshInstance3D:
			meshes.append(pin)
		var qb := AABB()
		for i in meshes.size():
			var b := _bounds(_xf_verts(meshes[i] as MeshInstance3D, q_ad, mxf))
			qb = b if i == 0 else qb.merge(b)
		ts["tip_x"] = qb.position.x
		ts["quill_box"] = qb                      # Pinole mit Spitze, eingefahren
	ts["quill"] = quill
	# Großes Handrad: dreht um die Pinolenachse (Spiel-X)
	var crank := root.find_child("tailstock_crank", true, false) as MeshInstance3D
	if crank:
		var cb := _bounds(_xf_verts(crank, root, mxf))
		var piv := Node3D.new()
		piv.name = "Handrad"
		piv.position = Vector3(cb.get_center().x, axis.y, axis.z)
		slide.add_child(piv)
		_take(root, "tailstock_crank", _adapter(piv, Transform3D(Basis.IDENTITY, -piv.position) * mxf))
		ts["crank"] = piv
	# Klemmhebel: Metallbügel und sein schwarzer Griff vorne oben aus dem Körper lösen
	if body and body.mesh:
		var parts := _split_mesh(body.mesh, func(mat: String, c: Vector3) -> bool:
			return mat.begins_with("metal_polished") or (mat.begins_with("plastic_black") and c.z < 0.0))
		if parts[1] != null:
			body.mesh = parts[0]
			var lever := MeshInstance3D.new()
			lever.name = "Klemmhebel"
			lever.mesh = parts[1]
			var lxf := mxf * body.transform           # gleiche Lage wie der Körper
			var lv := PackedVector3Array()
			for s in lever.mesh.get_surface_count():
				for v in lever.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					lv.append(lxf * v)
			var lb := _bounds(lv)
			# Drehpunkt: Mitte des untersten Viertels (Querwelle im Körper)
			var low := PackedVector3Array()
			for v in lv:
				if v.y < lb.position.y + lb.size.y * 0.25:
					low.append(v)
			var pc := _bounds(low).get_center()
			var lpiv := Node3D.new()
			lpiv.name = "Klemmhebel"
			lpiv.position = Vector3(pc.x, pc.y, 0.0)
			slide.add_child(lpiv)
			var l_ad := _adapter(lpiv, Transform3D(Basis.IDENTITY, -lpiv.position) * mxf)
			l_ad.add_child(lever)
			lever.transform = body.transform
			ts["lever"] = lpiv
	mach["ts"] = ts


## Dreiecke eines Meshs aufteilen: pick(Materialname, Dreiecksmitte in Mesh-Koordinaten) -> true =
## in den zweiten Teil. Ergebnis [Rest, herausgelöst]; ein leerer Teil ist null.
static func _split_mesh(mesh: Mesh, pick: Callable) -> Array:
	var keep := ArrayMesh.new()
	var take := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var mat := mesh.surface_get_material(s)
		var nm := mat.resource_name if mat else ""
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		else:
			for i in vs.size():
				idx.append(i)
		var a := PackedInt32Array()
		var b := PackedInt32Array()
		for t in range(0, idx.size() - 2, 3):
			var c := (vs[idx[t]] + vs[idx[t + 1]] + vs[idx[t + 2]]) / 3.0
			if pick.call(nm, c):
				b.append_array([idx[t], idx[t + 1], idx[t + 2]])
			else:
				a.append_array([idx[t], idx[t + 1], idx[t + 2]])
		for pair in [[keep, a], [take, b]]:
			var dst: ArrayMesh = pair[0]
			var ids: PackedInt32Array = pair[1]
			if ids.is_empty():
				continue
			var arr2 := arr.duplicate()
			arr2[Mesh.ARRAY_INDEX] = ids
			dst.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
			dst.surface_set_material(dst.get_surface_count() - 1, mat)
	return [keep if keep.get_surface_count() > 0 else null, take if take.get_surface_count() > 0 else null]


## Bildschirmfläche des Bedienpults: die große Platte, die zur Maschine hin (+X) zeigt, oberhalb der
## schrägen Ablage. Ergebnis: Lage (Mitte, Normale nach vorn, oben entlang der Platte) und Größe.
static func _pult_face(pv: PackedVector3Array) -> Dictionary:
	var pb := _bounds(pv)
	# Plattenebene aus der oberen Hälfte bestimmen (dort gibt es nur die Platte, keine Ablage)
	var ymid := pb.position.y + pb.size.y * 0.45
	var max_x := -INF
	for v in pv:
		if v.y > ymid:
			max_x = maxf(max_x, v.x)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in pv:
		if v.y > ymid and v.x > max_x - 0.035:
			if v.y < lo.y:
				lo = v
			if v.y > hi.y:
				hi = v
	var slope := (hi.x - lo.x) / maxf(hi.y - lo.y, 0.001)        # x je m Höhe (oben nach hinten)
	# alle Ecken auf dieser Ebene (ganze Platte bis hinunter zur Ablage)
	var face := PackedVector3Array()
	for v in pv:
		if absf(v.x - (lo.x + (v.y - lo.y) * slope)) < 0.01:
			face.append(v)
	var fb := _bounds(face)
	var tilt := atan(-slope)
	var n := Vector3(cos(tilt), sin(tilt), 0.0)
	var up := Vector3(-sin(tilt), cos(tilt), 0.0)
	var cy := fb.position.y + fb.size.y * 0.5
	var c := Vector3(lo.x + (cy - lo.y) * slope, cy, fb.position.z + fb.size.z * 0.5)
	var basis := Basis(up.cross(n), up, n)
	return {"xf": Transform3D(basis, c), "size": Vector2(fb.size.z, fb.size.y / cos(tilt)), "bounds": pb}


## Dachteil der Verkleidung (Dreiecke über y_cut) in ein eigenes Mesh legen, damit die Bedienkamera
## von oben hindurchsehen kann. Gibt das Dach-MeshInstance zurück (oder null).
func _split_roof(mi: MeshInstance3D, frame: Node3D, frame_xf: Transform3D, y_cut: float) -> MeshInstance3D:
	if mi.mesh == null:
		return null
	var to_game := frame_xf * _rel(mi, frame)
	var low := ArrayMesh.new()
	var high := ArrayMesh.new()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			for i in vs.size():
				idx.append(i)
		var li := PackedInt32Array()
		var hi := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var cy := (to_game * vs[idx[t]]).y + (to_game * vs[idx[t + 1]]).y + (to_game * vs[idx[t + 2]]).y
			var dst := hi if cy / 3.0 > y_cut else li
			dst.append(idx[t])
			dst.append(idx[t + 1])
			dst.append(idx[t + 2])
		var mat := mi.get_surface_override_material(s)
		if mat == null:
			mat = mi.mesh.surface_get_material(s)
		for pair in [[low, li], [high, hi]]:
			var ids: PackedInt32Array = pair[1]
			if ids.is_empty():
				continue
			var a := arr.duplicate()
			a[Mesh.ARRAY_INDEX] = ids
			var am: ArrayMesh = pair[0]
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			am.surface_set_material(am.get_surface_count() - 1, mat)
	if high.get_surface_count() == 0:
		return null
	mi.mesh = low
	for s in low.get_surface_count():
		mi.set_surface_override_material(s, null)
	var roof := MeshInstance3D.new()
	roof.name = "machine_roof"
	roof.mesh = high
	roof.transform = mi.transform
	mi.get_parent().add_child(roof)
	return roof


## Neues Modell (Y oben, Futter zeigt nach +Z, Spindelachse irgendwo über dem Boden) in die
## Lage des ersten Exports bringen: 180° um Y drehen und die Spindelachse in den Ursprung legen.
## Spindelachse = Mitte des Futterkörpers (x, y), nicht sein Objekt-Ursprung: liegt der Ursprung in
## Blender neben der Geometrie, würde das Futter sonst um ihn kreisen (eiern).
func _normalize(root: Node3D) -> void:
	var flip := Basis(Vector3.UP, PI)
	var chuck := root.find_child("chuck_main_body", true, false) as Node3D
	var ac := _rel(chuck, root).origin if chuck else Vector3.ZERO
	if chuck is MeshInstance3D and (chuck as MeshInstance3D).mesh:
		ac = _rel(chuck, root) * (chuck as MeshInstance3D).mesh.get_aabb().get_center()
	var a := flip * ac
	_axis_y0 = a.y
	for c in root.get_children():
		if c is Node3D:
			(c as Node3D).transform = Transform3D(flip, Vector3(-a.x, -a.y, 0.0)) * (c as Node3D).transform


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
	w.transform = Transform3D(_rt, post_pos("", axis_h, zc_mm, ext_mm))
	w.add_child(c)
	return w


## Lage des Halterkopfs (Drehpunkt) relativ zur Schneide, wenn Werkzeug id eingeschwenkt ist
## (Planschlitten-Achsen, m). Daraus folgt die Werkzeugkorrektur (Lathe.tool_offset).
func post_pos(id: String, axis_h: float, zc_mm := 0.0, ext_mm := 0.0) -> Vector3:
	if _holders.has(id):
		var tip: Vector3 = _holders[id]["tip"]
		tip.y += _shim(id)
		return Vector3(0, axis_h, 0) - _rt * tip
	# Prozedurales Werkzeug: freier Platz nimmt den Schaft auf
	var ref: Dictionary = _holders.get("T1", {"tip": Vector3.ZERO})
	var p := Vector3(0, axis_h, 0) - _rt * (ref["tip"] as Vector3)
	p.x = zc_mm * 0.001 + _shank_cz * SCALE * tool_scale
	# Auskraglänge: Platte ragt weiter heraus, der Halter sitzt um ext_mm weiter außen
	p.z += ext_mm * tool_scale * 0.001
	return p


func update_jaws(stock_d_mm: float) -> void:
	var r := stock_d_mm * 0.5 * 0.001 / _chuck_s
	for i in jaws.size():
		# Spannfläche der Backe auf den Werkstückradius schieben
		var p := _jaw_p0[i] + _jaw_dir[i] * (r - _jaw_r0[i])
		jaws[i].position.x = p.x
		jaws[i].position.y = p.y


# ------------------------------------------------------------ Hilfen

## true, wenn Halter h (unter dem Kopf) mit seinem Ursprung am Kopf sitzt (altes Modell) und nicht
## als Ablage daneben liegt. Maß: Ursprung innerhalb der doppelten Kopfgröße.
func _on_post(h: Node3D) -> bool:
	var pm := _post as MeshInstance3D
	if pm == null or pm.mesh == null:
		return true
	var pb := pm.mesh.get_aabb()
	var hp := _rel(h, _post).origin
	return pb.grow(pb.get_longest_axis_size()).has_point(hp)


## Im neuen Modell liegen die Halter (toolspanner*) einzeln neben dem Kopf statt auf ihm. Halter h
## auf die +Z-Seite des Kopfs setzen (Werkzeug zeigt dann in -X, also zum Werkstück in Platz 1):
## Halterrückseite liegt an der Kopffläche neben der Schwalbenschwanz-Feder, die Feder greift in
## die Nut des Halters. Höhe wie im Modell, seitlich mittig.
func _mount_loose(h: Node3D, post_xf: Transform3D) -> void:
	# Lage im Modell (bis unter die Modellwurzel)
	var hxf := h.transform
	if _post.is_ancestor_of(h):
		# Halter hängt (neues Modell) unter dem Kopf, der schon in die Maschine umgehängt ist:
		# Lage relativ zum Kopf in Modellkoordinaten zurückrechnen, nicht über die Szenenkette
		hxf = post_xf * _rel(h, _post)
	else:
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
	# alle Halter sitzen am selben Schwalbenschwanz, ganz abgesenkt: Halterunterkante = Kopfunterkante.
	# Auf Spitzenhöhe stellt sie danach die Höhenverstellung (_shim).
	var hb := inv * hxf.basis
	var low := INF
	if hm and hm.mesh:
		for s in hm.mesh.get_surface_count():
			for v in hm.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				low = minf(low, (hb * v).y)
	var y := (_post_bottom - low) if low != INF else (inv * Vector3(0, hxf.origin.y - post_xf.origin.y, 0)).y
	h.transform = Transform3D(hb, Vector3(0.0, y, (inv * Vector3(0, 0, face - back)).z))


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
	var tz := best_z
	if ref == "center":
		# Spitze: Mitte des vordersten Bereichs (beidseitig symmetrische Platte)
		var hi_z := -INF
		for w in vs:
			if w.x < min_x + 0.01:
				hi_z = maxf(hi_z, w.z)
		tz = (lo_z + hi_z) * 0.5
	# Höhe der Schneide = Plattenoberkante an der Schneidenecke selbst (Platten sind im Halter
	# geneigt, ihre höchste Ecke liegt woanders). Nur Ecken an der Schneidenecke (x, z) zählen.
	var d_min := INF
	for w in vs:
		d_min = minf(d_min, Vector2(w.x - min_x, w.z - tz).length())
	var tip_y := -INF
	for w in vs:
		if Vector2(w.x - min_x, w.z - tz).length() < d_min + 0.002:
			tip_y = maxf(tip_y, w.y)
	if tip_y == -INF:
		tip_y = top
	return Vector3(min_x, tip_y, tz)


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
	if n == root:
		return Transform3D.IDENTITY
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


## Ecken von mi in Maschinenkoordinaten: frame ist der Knoten, unter dem mi (mittelbar) hängt,
## frame_xf dessen Lage in der Maschine. surface >= 0: nur diese Fläche.
static func _xf_verts(mi: MeshInstance3D, frame: Node, frame_xf: Transform3D, surface := -1) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mi == null or mi.mesh == null:
		return out
	var xf := frame_xf * _rel(mi, frame)
	for s in mi.mesh.get_surface_count():
		if surface >= 0 and s != surface:
			continue
		for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			out.append(xf * v)
	return out


static func _bounds(vs: PackedVector3Array) -> AABB:
	if vs.is_empty():
		return AABB()
	var b := AABB(vs[0], Vector3.ZERO)
	for v in vs:
		b = b.expand(v)
	return b


## Flächen ohne Material (z. B. Spannhebel) bekommen dunklen Stahl statt Weiß, E50-Teile ihre Lackfarbe.
static func _fix_materials(n: Node, fallback: Material) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			var fb := fallback
			if PART_COLORS.has(str(mi.name)):
				fb = Build.mat(PART_COLORS[str(mi.name)], 0.45, 0.2)
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m == null or m.resource_name == "":
					mi.set_surface_override_material(s, fb)
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


## Höhenverstellung (Halter-Koordinaten) für Halter id. E50-Modell: Kopf bleibt auf Modellhöhe, jeder
## Halter wird am Schwalbenschwanz so verstellt, dass seine Schneide genau auf der Drehmitte steht.
## Altes Modell: Schneide auf die Höhe der höchsten Schneide heben.
func _shim(id: String) -> float:
	if not _holders.has(id):
		return 0.0
	if not is_nan(_tip_target):
		return _tip_target - float((_holders[id]["tip"] as Vector3).y)
	if _max_tip_y == -INF:
		return 0.0
	return _max_tip_y - float((_holders[id]["tip"] as Vector3).y)
