class_name LatheTools
extends RefCounted
## Werkzeugbibliothek. Jede Schneidplatte ist ein 2D-Polygon in der (dz, dx)-Ebene [mm]:
##   dz = axial (+ = weg vom Futter), dx = radial (+ = nach außen).
## Der Bezugspunkt (0,0) ist der Punkt, auf den sich die Positionsanzeige bezieht.
## Die untere Hüllkurve des Polygons ist die schneidende Kontur: Alles Material oberhalb
## davon wird abgetragen – also schneiden auch schräge Kanten (Fasen, Kopierdrehen, Radien).

const ENV_RES := 0.05

## Werkzeuge mit ihrer Plattenform (shape):
##   ["rhombus", Hauptschneide °, Nebenschneide °, Kantenlänge mm, gespiegelt]  Wendeplatte, Spitze unten
##   ["blade", Breite mm, Länge mm]                                             Stechplatte
##   ["radius", Radius mm]                                                      Vollradius-Platte
##   ["bore", Hauptschneide °, Nebenschneide °, Kantenlänge mm]                 Bohrstangenplatte, Spitze oben
##   ["drill", Durchmesser mm, Länge mm]                                        Spiralbohrer
##   ["thread_out"] / ["thread_in"]                                             Gewindeplatte 60° außen / innen
## Bohrstange, Bohrer und Gewindeplatten haben immer ihr echtes Maß: Sie müssen in die Bohrung passen
## bzw. das Gewindeprofil schneiden.
## Die Kantenlänge ist das Nennmaß. An der Maschine ist die Platte so groß, wie man sie dort sieht
## (sized mit dem Maßstab der Maschine), Winkel und Eckenradius bleiben dabei gleich. Stech- und
## Radiusplatte behalten ihre Maße, weil Einstichbreite und Radius zum Auftrag gehören.
const SPECS := [
	{"id": "T1", "sl": 3, "ext": 0.0, "name": "Schruppmeißel rechts", "short": "Schrupp R",
		"desc": "CNMG 80°, Einstellwinkel 95°, r 0,8 - Längsdrehen Richtung Futter, Plandrehen",
		"shape": ["rhombus", 85.0, 5.0, 12.0, false], "nose": 0.8, "ref": "left",
		"max_dz": 4.0, "max_dx": 4.0, "feed_dir": -1, "color": Color(0.85, 0.68, 0.25)},
	{"id": "T2", "sl": 4, "ext": 4.0, "name": "Schruppmeißel links", "short": "Schrupp L",
		"desc": "CNMG 80°, links, Einstellwinkel 95°, r 0,8 - Längsdrehen vom Futter weg, Rückwärtsplanen",
		"shape": ["rhombus", 85.0, 5.0, 12.0, true], "nose": 0.8, "ref": "right",
		"max_dz": 4.0, "max_dx": 4.0, "feed_dir": 1, "color": Color(0.85, 0.68, 0.25)},
	{"id": "T3", "sl": 3, "ext": 0.0, "name": "Schlichtmeißel 55°", "short": "Schlicht 55°",
		"desc": "DNMG 55°, Einstellwinkel 93°, r 0,4 - Schlichten und Kopierdrehen (Freiwinkel 32°)",
		"shape": ["rhombus", 87.0, 32.0, 11.0, false], "nose": 0.4, "ref": "left",
		"max_dz": 1.5, "max_dx": 1.5, "feed_dir": -1, "color": Color(0.75, 0.75, 0.8)},
	{"id": "T4", "sl": 3, "ext": 6.5, "name": "Kopiermeißel 35°", "short": "Kopier 35°",
		"desc": "VNMG 35°, Einstellwinkel 93°, r 0,4 - Hinterschnitte, steile Konturen (Freiwinkel 52°)",
		"shape": ["rhombus", 87.0, 52.0, 11.0, false], "nose": 0.4, "ref": "left",
		"max_dz": 1.0, "max_dx": 1.0, "feed_dir": -1, "color": Color(0.35, 0.35, 0.4)},
	{"id": "T5", "sl": 8, "ext": 0.0, "name": "Fasenmeißel 45°", "short": "Fase 45°",
		"desc": "SNMG quadratisch, 45° angestellt, r 0,8 - Fasen links und rechts über die ganze Schneidkante, Längs- und Plandrehen",
		"shape": ["rhombus", 135.0, 45.0, 12.0, false], "nose": 0.8, "ref": "center",
		"max_dz": 3.0, "max_dx": 3.0, "feed_dir": -1, "color": Color(0.85, 0.68, 0.25)},
	{"id": "T6", "sl": 3, "ext": 0.0, "name": "Stechmeißel 4 mm", "short": "Stech 4",
		"desc": "Stechschwert mit Einstech-/Abstechplatte 4 mm, r 0,2 - nur radial einstechen, seitlich max. 0,3 mm",
		"shape": ["blade", 4.0, 22.0], "nose": 0.2, "ref": "left",
		"max_dz": 0.3, "max_dx": 4.0, "feed_dir": -1, "color": Color(0.3, 0.32, 0.36)},
	{"id": "T7", "sl": 8, "ext": 3.5, "name": "Radiusmeißel R3", "short": "Radius R3",
		"desc": "Vollradius-Platte R3 - Radiusnuten, Hohlkehlen, sehr gute Oberfläche",
		"shape": ["radius", 3.0], "nose": 3.0, "ref": "center",
		"max_dz": 2.0, "max_dx": 2.0, "feed_dir": -1, "color": Color(0.85, 0.68, 0.25)},
	{"id": "T8", "sl": 2, "ext": 0.0, "name": "Bohrstange innen 55°", "short": "Bohrst. innen",
		"desc": "Bohrstange Ø12 mit DCMT 55°, r 0,4 - Innendrehen ab Bohrung Ø16, Ausspindeln zum Futter hin",
		"shape": ["bore", 87.0, 32.0, 6.0], "nose": 0.4, "ref": "left",
		"bar": Rect2(3.0, -14.5, 80.0, 12.0), "kind": "bore",
		"max_dz": 1.5, "max_dx": 1.5, "feed_dir": -1, "color": Color(0.75, 0.75, 0.8)},
	{"id": "T9", "sl": 7, "ext": 0.0, "name": "Spiralbohrer Ø20", "short": "Bohrer Ø20",
		"desc": "HSS-Spiralbohrer Ø20, Spitzenwinkel 118° - Bohren in der Drehmitte (X 0), Bohrtiefe bis 80 mm",
		"shape": ["drill", 20.0, 90.0], "nose": 0.0, "ref": "center", "kind": "drill", "dia": 20.0,
		"max_dz": 0.0, "max_dx": 0.0, "feed_dir": -1, "color": Color(0.55, 0.57, 0.62)},
	{"id": "T10", "sl": 8, "ext": 0.0, "name": "Gewindemeißel außen 60°", "short": "Gewinde außen",
		"desc": "Gewindedrehplatte 60° (metrisch), r 0,1 - Außengewinde, radiale Zustellung je Schnitt max. 0,5 mm",
		"shape": ["thread_out"], "nose": 0.1, "ref": "center", "kind": "thread_out",
		"max_dz": 0.5, "max_dx": 0.5, "feed_dir": -1, "color": Color(0.85, 0.68, 0.25)},
	{"id": "T11", "sl": 6, "ext": 0.0, "name": "Gewindemeißel innen 60°", "short": "Gewinde innen",
		"desc": "Gewindebohrstange Ø12 mit 60°-Platte, r 0,1 - Innengewinde ab Kernloch Ø16, je Schnitt max. 0,5 mm",
		"shape": ["thread_in"], "nose": 0.1, "ref": "center", "kind": "thread_in", "bar": Rect2(-2.0, -14.5, 80.0, 11.5),
		"max_dz": 0.5, "max_dx": 0.5, "feed_dir": -1, "color": Color(0.75, 0.75, 0.8)},
]

static var _tools: Array = []
static var _sized := {}      # "T1@2.1000" -> Werkzeug mit Platte in diesem Maßstab


## Die Werkzeuge im Nennmaß (für Listen, Namen und den Werkzeughandel).
static func all() -> Array:
	if _tools.is_empty():
		for sp in SPECS:
			_tools.append(sized(str(sp["id"]), 1.0))
	return _tools


## Werkzeug id mit einer um k vergrößerten Platte. Stech- und Radiusplatte bleiben im Nennmaß.
static func sized(id: String, k: float) -> Dictionary:
	var i := index_of(id)
	if i < 0:
		return {}
	var sp: Dictionary = SPECS[i]
	if not scalable(id):
		k = 1.0
	var key := "%s@%.4f" % [id, k]
	if not _sized.has(key):
		var t: Dictionary = sp.duplicate(true)
		t["poly"] = shape_poly(sp["shape"], float(sp["nose"]), k)
		t["scale"] = k
		if kind(t) in ["bore", "drill", "thread_in"]:
			_finalize_inner(t)
		else:
			_finalize(t)
		_sized[key] = t
	return _sized[key]


## false für Platten, deren Maß zum Auftrag gehört (Einstichbreite, Radius).
static func scalable(id: String) -> bool:
	var i := index_of(id)
	return i >= 0 and str(SPECS[i]["shape"][0]) == "rhombus"


static func shape_poly(shape: Array, nose: float, k := 1.0) -> PackedVector2Array:
	match str(shape[0]):
		"rhombus":
			var p := round_corner(rhombus(float(shape[1]), float(shape[2]), float(shape[3]) * k), 0, nose)
			return mirror(p) if bool(shape[4]) else p
		"blade":
			var w := float(shape[1])
			var h := float(shape[2])
			return round_corner(round_corner(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), 1, nose), 0, nose)
		"bore":
			return round_corner(flip(rhombus(float(shape[1]), float(shape[2]), float(shape[3]))), 3, nose)
		"drill":
			return drill_poly(float(shape[1]), float(shape[2]))
		"thread_out":
			return round_corner(PackedVector2Array([Vector2(0, 0), Vector2(2.6, 4.5), Vector2(2.6, 9.0), Vector2(-2.6, 9.0), Vector2(-2.6, 4.5)]), 0, nose)
		"thread_in":
			return round_corner(PackedVector2Array([Vector2(0, 0), Vector2(-1.73, -3.0), Vector2(1.73, -3.0)]), 0, nose)
	return _radius_poly(float(shape[1]))


static func count() -> int:
	return SPECS.size()


static func get_tool(i: int) -> Dictionary:
	return all()[clampi(i, 0, count() - 1)]


## Index des Werkzeugs mit dieser ID, -1 wenn unbekannt.
static func index_of(id: String) -> int:
	for i in SPECS.size():
		if str(SPECS[i]["id"]) == id:
			return i
	return -1


# ------------------------------------------------------------ Geometrie

## Rhombische Platte: Spitze im Ursprung, Hauptschneide unter main_deg, Nebenschneide unter minor_deg (zu +dz).
static func rhombus(main_deg: float, minor_deg: float, edge: float) -> PackedVector2Array:
	var m := Vector2(cos(deg_to_rad(main_deg)), sin(deg_to_rad(main_deg))) * edge
	var n := Vector2(cos(deg_to_rad(minor_deg)), sin(deg_to_rad(minor_deg))) * edge
	return PackedVector2Array([Vector2.ZERO, n, n + m, m])


## Art des Werkzeugs: "" Außendrehen, "bore" Innendrehen, "drill" Bohren in der Drehmitte,
## "thread_out" / "thread_in" Gewindedrehen außen / innen.
static func kind(t: Dictionary) -> String:
	return str(t.get("kind", ""))


## Arbeitet das Werkzeug in einer Bohrung (Schneide zeigt nach außen)?
static func is_inner(t: Dictionary) -> bool:
	return kind(t) in ["bore", "thread_in"]


static func is_thread(t: Dictionary) -> bool:
	return kind(t) in ["thread_out", "thread_in"]


## Platte an der Schneide in X spiegeln (Spitze oben, für Innenwerkzeuge).
static func flip(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(poly.size() - 1, -1, -1):
		out.append(Vector2(poly[i].x, -poly[i].y))
	return out


## Spiralbohrer: Spitze im Ursprung, Schneiden unter 59° zur Achse, Körper bis length (in +dz).
static func drill_poly(dia: float, length: float) -> PackedVector2Array:
	var r := dia * 0.5
	var h := r / tan(deg_to_rad(59.0))
	return PackedVector2Array([Vector2.ZERO, Vector2(h, -r), Vector2(length, -r), Vector2(length, r), Vector2(h, r)])


static func mirror(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(poly.size() - 1, -1, -1):
		out.append(Vector2(-poly[i].x, poly[i].y))
	return out


static func round_corner(poly: PackedVector2Array, k: int, r: float, n := 8) -> PackedVector2Array:
	var cnt := poly.size()
	var c := poly[k]
	var u := (poly[(k - 1 + cnt) % cnt] - c).normalized()
	var v := (poly[(k + 1) % cnt] - c).normalized()
	var theta := acos(clampf(u.dot(v), -1.0, 1.0))
	var t := r / tan(theta * 0.5)
	var a := c + u * t
	var b := c + v * t
	var center := c + (u + v).normalized() * (r / sin(theta * 0.5))
	var a0 := (a - center).angle()
	var da := wrapf((b - center).angle() - a0, -PI, PI)
	var out := PackedVector2Array()
	for i in cnt:
		if i == k:
			for s in n + 1:
				var ang := a0 + da * float(s) / n
				out.append(center + Vector2(cos(ang), sin(ang)) * r)
		else:
			out.append(poly[i])
	return out


## Flächenschwerpunkt des Polygons.
static func centroid(poly: PackedVector2Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var w := p.cross(q)
		a += w
		c += (p + q) * w
	return c / (3.0 * a) if absf(a) > 0.000001 else (poly[0] if poly.size() > 0 else Vector2.ZERO)


## Kleinster Abstand vom Schwerpunkt zu einer Kante (Radius des größten Kreises um die Plattenmitte).
static func inradius(poly: PackedVector2Array) -> float:
	var c := centroid(poly)
	var best := INF
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		best = minf(best, c.distance_to(Geometry2D.get_closest_point_to_segment(c, p, q)))
	return best if best < INF else 0.0


## Höhe der Schneidkante: so hoch reicht die schneidende Kontur an ihrem niedrigeren Ende über die Spitze.
## Beim Fasenmeißel ist das die größte Fase, die er mit der ganzen Kante schneidet.
static func edge_height(t: Dictionary) -> float:
	var env: PackedFloat32Array = t["env"]
	return minf(env[0], env[env.size() - 1]) if env.size() > 0 else 0.0


static func _radius_poly(r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for s in 17:
		var ang := PI + PI * float(s) / 16.0
		out.append(Vector2(cos(ang), sin(ang)) * r + Vector2(0, r))
	out.append(Vector2(r, 12))
	out.append(Vector2(-r, 12))
	return out


static func _finalize(t: Dictionary) -> Dictionary:
	var poly: PackedVector2Array = t["poly"]
	var min_y := INF
	var low_x := 0.0
	for p in poly:
		if p.y < min_y:
			min_y = p.y
			low_x = p.x
	var nose: float = t["nose"]
	var ref_x := low_x
	if t["ref"] != "center":
		ref_x = INF if t["ref"] == "left" else -INF
		for p in poly:
			if p.y <= min_y + nose * 2.0 + 0.01:
				ref_x = minf(ref_x, p.x) if t["ref"] == "left" else maxf(ref_x, p.x)
	var shifted := PackedVector2Array()
	var zmin := INF
	var zmax := -INF
	var top := 0.0
	for p in poly:
		var q := p - Vector2(ref_x, min_y)
		shifted.append(q)
		zmin = minf(zmin, q.x)
		zmax = maxf(zmax, q.x)
		top = maxf(top, q.y)
	t["poly"] = shifted
	t["zmin"] = zmin
	t["zmax"] = zmax
	t["top"] = top
	# untere Hüllkurve abtasten
	var n := int(ceil((zmax - zmin) / ENV_RES)) + 1
	var env := PackedFloat32Array()
	env.resize(n)
	for k in n:
		var z := zmin + k * ENV_RES
		var best := INF
		for e in shifted.size():
			var a := shifted[e]
			var b := shifted[(e + 1) % shifted.size()]
			if z >= minf(a.x, b.x) - 0.0001 and z <= maxf(a.x, b.x) + 0.0001:
				var y := minf(a.y, b.y) if absf(b.x - a.x) < 0.000001 else lerpf(a.y, b.y, (z - a.x) / (b.x - a.x))
				best = minf(best, y)
		env[k] = best if best < INF else 1.0e6
	t["env"] = env
	return t


## Innenwerkzeuge und Bohrer: Bezugspunkt ist die oberste Ecke (Schneide zeigt nach außen) bzw.
## die Bohrerspitze. Dazu Hüllkurven unten (env) und oben (env_up) über Platte und Bohrstange
## (bar, Rect2 in dz/dx relativ zur Schneide). cut_len: bis hierhin (dz) schneidet die Platte,
## dahinter stößt nur noch die Stange an.
static func _finalize_inner(t: Dictionary) -> Dictionary:
	var poly: PackedVector2Array = t["poly"]
	var ref := Vector2.ZERO
	if str(t.get("kind", "")) != "drill":
		var max_y := -INF
		for p in poly:
			max_y = maxf(max_y, p.y)
		var nose: float = t["nose"]
		ref = Vector2(INF if t["ref"] == "left" else 0.0, max_y)
		for p in poly:
			if t["ref"] == "left":
				if p.y >= max_y - nose * 2.0 - 0.01:
					ref.x = minf(ref.x, p.x)
			elif p.y >= max_y - 0.0001:
				ref.x = p.x
	var shifted := PackedVector2Array()
	for p in poly:
		shifted.append(p - ref)
	t["poly"] = shifted
	var bar := Rect2()
	if t.has("bar"):
		bar = t["bar"]
	var zmin := INF
	var zmax := -INF
	var bottom := INF
	for p in shifted:
		zmin = minf(zmin, p.x)
		zmax = maxf(zmax, p.x)
		bottom = minf(bottom, p.y)
	var cut_len := zmax
	if bar.size.x > 0.0:
		zmin = minf(zmin, bar.position.x)
		zmax = maxf(zmax, bar.end.x)
		bottom = minf(bottom, bar.position.y)
	t["zmin"] = zmin
	t["zmax"] = zmax
	t["top"] = 0.0
	t["bottom"] = bottom
	var n := int(ceil((zmax - zmin) / ENV_RES)) + 1
	var lo := PackedFloat32Array()
	var up := PackedFloat32Array()
	lo.resize(n)
	up.resize(n)
	for k in n:
		var z := zmin + k * ENV_RES
		var a := _span_at(shifted, z)
		if bar.size.x > 0.0 and z >= bar.position.x - 0.0001 and z <= bar.end.x + 0.0001:
			if a.x == INF:
				a = Vector2(bar.position.y, bar.end.y)
			else:
				if bar.end.y > a.y and z < cut_len:
					cut_len = z
				a = Vector2(minf(a.x, bar.position.y), maxf(a.y, bar.end.y))
		lo[k] = a.x if a.x < INF else 1.0e6
		up[k] = a.y if a.x < INF else -1.0e6
	t["env"] = lo
	t["env_up"] = up
	t["cut_len"] = cut_len
	return t


## Unter- und Oberkante (x, y) des Polygons an der Stelle z, (INF, INF) wenn es dort nicht liegt.
static func _span_at(poly: PackedVector2Array, z: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for e in poly.size():
		var a := poly[e]
		var b := poly[(e + 1) % poly.size()]
		if z >= minf(a.x, b.x) - 0.0001 and z <= maxf(a.x, b.x) + 0.0001:
			if absf(b.x - a.x) < 0.000001:
				lo = minf(lo, minf(a.y, b.y))
				hi = maxf(hi, maxf(a.y, b.y))
			else:
				var y := lerpf(a.y, b.y, (z - a.x) / (b.x - a.x))
				lo = minf(lo, y)
				hi = maxf(hi, y)
	return Vector2(lo, hi) if lo < INF else Vector2(INF, INF)


## Größte Höhe der Oberkante im Bereich [lo, hi] (Innenwerkzeuge, Bohrer). -INF wenn außerhalb.
static func env_max(t: Dictionary, lo: float, hi: float) -> float:
	var zmin: float = t["zmin"]
	var zmax: float = t["zmax"]
	if hi < zmin or lo > zmax or not t.has("env_up"):
		return -INF
	var env: PackedFloat32Array = t["env_up"]
	var k0 := clampi(int(floor((maxf(lo, zmin) - zmin) / ENV_RES)), 0, env.size() - 1)
	var k1 := clampi(int(ceil((minf(hi, zmax) - zmin) / ENV_RES)), 0, env.size() - 1)
	var m := -INF
	for k in range(k0, k1 + 1):
		m = maxf(m, env[k])
	return m


## Innenwerkzeug als Außenwerkzeug im gespiegelten Raum (x' = R - x): Unterkante = -Oberkante.
## Damit rechnen die Abspanzyklen Innenkonturen wie Außenkonturen.
static func mirrored(t: Dictionary) -> Dictionary:
	var m := t.duplicate()
	var up: PackedFloat32Array = t["env_up"]
	var e := PackedFloat32Array()
	e.resize(up.size())
	for k in up.size():
		e[k] = -up[k] if up[k] > -1.0e5 else 1.0e6
	m["env"] = e
	m["kind"] = ""
	return m


## Kleinste Hüllkurvenhöhe im Bereich [lo, hi] (relativ zum Bezugspunkt). INF wenn außerhalb.
static func env_min(t: Dictionary, lo: float, hi: float) -> float:
	var zmin: float = t["zmin"]
	var zmax: float = t["zmax"]
	if hi < zmin or lo > zmax:
		return INF
	var env: PackedFloat32Array = t["env"]
	var k0 := clampi(int(floor((maxf(lo, zmin) - zmin) / ENV_RES)), 0, env.size() - 1)
	var k1 := clampi(int(ceil((minf(hi, zmax) - zmin) / ENV_RES)), 0, env.size() - 1)
	var m := INF
	for k in range(k0, k1 + 1):
		m = minf(m, env[k])
	return m


## Extrudiert das Plattenpolygon zu einem Mesh (x = dz, z = dx, Dicke in y). relief: Die Unterseite ist
## um diesen Anteil zur Plattenmitte hin kleiner (Freiwinkel der Platte), die Oberseite bleibt das Polygon.
static func extrude(poly: PackedVector2Array, y0: float, y1: float, relief := 0.0) -> ArrayMesh:
	var s := 0.001
	var low := poly
	if relief > 0.0:
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= maxf(poly.size(), 1)
		low = PackedVector2Array()
		for p in poly:
			low.append(c + (p - c) * (1.0 - relief))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		for j in 3:
			var p := poly[idx[i + j]]
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x * s, y1, p.y * s))
		for j in [2, 1, 0]:
			var p := low[idx[i + j]]
			st.set_normal(Vector3.DOWN)
			st.add_vertex(Vector3(p.x * s, y0, p.y * s))
	for e in poly.size():
		var k := (e + 1) % poly.size()
		var va0 := Vector3(low[e].x * s, y0, low[e].y * s)
		var va1 := Vector3(poly[e].x * s, y1, poly[e].y * s)
		var vb0 := Vector3(low[k].x * s, y0, low[k].y * s)
		var vb1 := Vector3(poly[k].x * s, y1, poly[k].y * s)
		var nrm := (vb0 - va0).cross(va1 - va0).normalized()
		if nrm == Vector3.ZERO:
			var d := (poly[k] - poly[e]).normalized()
			nrm = Vector3(d.y, 0, -d.x)
		for v in [va0, vb0, vb1, va0, vb1, va1]:
			st.set_normal(nrm)
			st.add_vertex(v)
	return st.commit()
