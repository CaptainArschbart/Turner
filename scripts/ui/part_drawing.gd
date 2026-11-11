class_name PartDrawing
extends Control
## Technische Zeichnung eines Auftrags. Drehteile als Seitenansicht mit Durchmessern und Längen, Frästeile in
## Draufsicht, Vorderansicht und Seitenansicht. Rechts stehen alle Zielmaße als Liste.

const PAPER := Color(0.96, 0.95, 0.9)
const INK := Color(0.1, 0.11, 0.14)
const THIN := Color(0.2, 0.24, 0.32)
const FILL := Color(0.84, 0.86, 0.88)
const CUT := Color(0.98, 0.78, 0.5)
const SIDE_W := 300.0             # Spalte mit Zielmaßen
const FONT := 15
const SMALL := 13

var job: Dictionary = {}
var printed := false              # Ausdruck für ein Blatt in der Welt: ohne Tastenhinweis


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_rect(Rect2(Vector2(8, 8), size - Vector2(16, 16)), INK, false, 2.0)
	if job.is_empty():
		return
	_text(Vector2(24, 36), str(job["title"]), 20)
	_text(Vector2(24, 58), "Werkstoff: %s    Maße in mm" % Materials.label(str(job.get("material", Materials.DEFAULT))), SMALL)
	if not printed:
		var key: String = Settings.binding_text("show_drawing")
		_text(Vector2(size.x - SIDE_W + 8, 36), "[%s] oder Esc" % key, SMALL)
	var area := Rect2(24, 76, size.x - SIDE_W - 48, size.y - 100)
	if job.has("stock_d"):
		_draw_turned(area)
	else:
		_draw_milled(area)
	_draw_list()


func _draw_list() -> void:
	var x := size.x - SIDE_W
	draw_line(Vector2(x - 8, 8), Vector2(x - 8, size.y - 8), INK, 2.0)
	_text(Vector2(x + 8, 76), "Zielmaße", 18)
	var y := 104.0
	for line in JobBoard.target_lines(job, job.has("grind")):
		for part in _wrap(str(line), 36):
			_text(Vector2(x + 8, y), part, SMALL)
			y += 20.0
	y += 8.0
	if job.has("stock_d"):
		_text(Vector2(x + 8, y), "Rohteil: Ø%d x %d" % [int(job["stock_d"]), int(job["stock_len"])], SMALL)
		y += 20.0
		_text(Vector2(x + 8, y), "Z ab Backen-Stirnfläche", SMALL)
	else:
		var s: Array = job["size"]
		_text(Vector2(x + 8, y), "Rohteil: %d x %d x %d" % [int(s[0]), int(s[1]), int(s[2])], SMALL)
		y += 20.0
		_text(Vector2(x + 8, y), "X, Y ab vorderer linker Ecke", SMALL)
		y += 20.0
		_text(Vector2(x + 8, y), "Z = 0 auf der rohen Oberseite", SMALL)


static func _wrap(t: String, width: int) -> Array:
	var out := []
	var line := ""
	for word in t.split(" "):
		if line != "" and line.length() + word.length() + 1 > width:
			out.append(line)
			line = word
		else:
			line = word if line == "" else "%s %s" % [line, word]
	if line != "":
		out.append(line)
	return out


# ------------------------------------------------------------ Drehteil

## Obere Kontur als Punkte (z, r), von der Spannseite bis zum Ende.
static func turned_contour(j: Dictionary) -> PackedVector2Array:
	var length := float(j.get("length", j["stock_len"]))
	var dias := []
	for f in j["features"]:
		if str(f.get("type", "dia")) == "dia":
			dias.append(f)
	dias.sort_custom(func(a, b): return float(a["z0"]) < float(b["z0"]))
	var pts := PackedVector2Array()
	var stock_r := float(j["stock_d"]) * 0.5
	var z := 0.0
	var r := stock_r
	pts.append(Vector2(0.0, 0.0))
	pts.append(Vector2(0.0, r))
	for f in dias:
		var z0 := float(f["z0"])
		var z1 := float(f["z1"])
		var rr := float(f["d"]) * 0.5
		if z0 > z + 0.001:
			# Lücke: Nutgrund, sonst bleibt der bisherige Durchmesser
			for g in j["features"]:
				if str(g.get("type", "")) == "point" and float(g["z"]) > z and float(g["z"]) < z0:
					pts.append(Vector2(z, r))
					pts.append(Vector2(float(g["z"]), float(g["d"]) * 0.5))
					pts.append(Vector2(z0, r))
			pts.append(Vector2(z0, r))
		pts.append(Vector2(z0, rr))
		var c := _chamfer_at(j, z1, float(f["d"]))
		if c > 0.0:
			pts.append(Vector2(z1 - c, rr))
			pts.append(Vector2(z1, rr - c))
		else:
			pts.append(Vector2(z1, rr))
		z = z1
		r = rr
	if z < length - 0.001:
		pts.append(Vector2(length, r))
	pts.append(Vector2(length, 0.0))
	return pts


static func _chamfer_at(j: Dictionary, z: float, d: float) -> float:
	for f in j["features"]:
		if str(f.get("type", "")) == "chamfer" and absf(float(f["z"]) - z) < 0.01 and absf(float(f["d"]) - d) < 0.01:
			return float(f["size"])
	return 0.0


func _draw_turned(area: Rect2) -> void:
	var length := float(job.get("length", job["stock_len"]))
	var stock_d := float(job["stock_d"])
	var margin_x := 40.0
	var sc := minf((area.size.x - margin_x * 2.0) / length, (area.size.y - 260.0) / stock_d)
	var o := Vector2(area.position.x + margin_x + (area.size.x - margin_x * 2.0 - length * sc) * 0.5, area.position.y + 120.0 + stock_d * 0.5 * sc)
	var P := func(z: float, r: float) -> Vector2: return o + Vector2(z * sc, -r * sc)
	var top := turned_contour(job)
	# Fläche und Umriss
	var poly := PackedVector2Array()
	for p in top:
		poly.append(P.call(p.x, p.y))
	for i in range(top.size() - 1, -1, -1):
		poly.append(P.call(top[i].x, -top[i].y))
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.size() > 0:
		draw_colored_polygon(poly, FILL)
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, INK, 2.0, true)
	# Mittellinie, strichpunktiert
	var x: float = o.x - 24.0
	var x_end: float = o.x + length * sc + 24.0
	while x < x_end:
		draw_line(Vector2(x, o.y), Vector2(minf(x + 16.0, x_end), o.y), THIN, 1.0)
		draw_line(Vector2(minf(x + 20.0, x_end), o.y), Vector2(minf(x + 22.0, x_end), o.y), THIN, 1.0)
		x += 26.0
	# Stufenkanten
	for p in top:
		if p.y > 0.01:
			draw_line(P.call(p.x, p.y), P.call(p.x, -p.y), Color(THIN, 0.35), 1.0)
	var bottom_y: float = o.y + stock_d * 0.5 * sc + 12.0
	var row := 0
	var last_end := -1.0
	for f in _dias():
		var z0 := float(f["z0"])
		var z1 := float(f["z1"])
		var d := float(f["d"])
		# Durchmesser: Maßlinie quer durch das Teil, Text darüber
		var mid := (z0 + z1) * 0.5
		var a: Vector2 = P.call(mid, d * 0.5)
		var b: Vector2 = P.call(mid, -d * 0.5)
		_dim_vertical(a, b)
		var label := "Ø%s ±%s" % [_num(d), _num(float(f.get("tol", 0.3)))]
		var stagger := 0.0 if row % 2 == 0 else 20.0
		_centered(Vector2(a.x, o.y - stock_d * 0.5 * sc - 14.0 - stagger), label, FONT)
		draw_line(a, Vector2(a.x, o.y - stock_d * 0.5 * sc - 10.0 - stagger), Color(THIN, 0.5), 1.0)
		# Länge der Stufe
		_dim_horizontal(P.call(z0, -d * 0.5), P.call(z1, -d * 0.5), bottom_y + 18.0 + (row % 2) * 26.0, "%s" % _num(z1 - z0))
		last_end = z1
		row += 1
	# Spannbereich und Gesamtlänge
	var first := float(_dias()[0]["z0"]) if not _dias().is_empty() else 0.0
	if first > 0.0:
		_dim_horizontal(P.call(0.0, -stock_d * 0.5), P.call(first, -stock_d * 0.5), bottom_y + 18.0, _num(first))
		_centered(P.call(first * 0.5, 0.0) + Vector2(0, -6), "Spann-", SMALL)
		_centered(P.call(first * 0.5, 0.0) + Vector2(0, 10), "bereich", SMALL)
	_dim_horizontal(P.call(0.0, -stock_d * 0.5), P.call(length, -stock_d * 0.5), bottom_y + 80.0, "Gesamtlänge %s" % _num(length))
	# Fasen und Nutgrund
	for f in job["features"]:
		match str(f.get("type", "dia")):
			"chamfer":
				var at: Vector2 = P.call(float(f["z"]), float(f["d"]) * 0.5)
				_text(at + Vector2(6, -6), "%s x 45°" % _num(float(f["size"])), SMALL)
			"point":
				var at: Vector2 = P.call(float(f["z"]), float(f["d"]) * 0.5)
				draw_circle(at, 3.0, INK)
				_centered(at + Vector2(0, 18), "Ø%s" % _num(float(f["d"])), SMALL)
			"bore":
				# Bohrung: verdeckte Kanten gestrichelt, Maß in der Mitte
				var rb := float(f["d"]) * 0.5
				var b0: Vector2 = P.call(float(f["z0"]), rb)
				var b1: Vector2 = P.call(float(f["z1"]), rb)
				var b2: Vector2 = P.call(float(f["z0"]), -rb)
				var b3: Vector2 = P.call(float(f["z1"]), -rb)
				draw_dashed_line(b0, b1, INK, 1.2, 5.0)
				draw_dashed_line(b2, b3, INK, 1.2, 5.0)
				draw_dashed_line(b0, b2, INK, 1.2, 5.0)
				_centered((b0 + b3) * 0.5 + Vector2(0, -4), "Ø%s" % _num(float(f["d"])), SMALL)
			"thread":
				# Gewinde: Kernlinie dünn, Bezeichnung M d x P
				var inner := bool(f.get("inner", false))
				var rn := float(f["d"]) * 0.5
				var rk := rn - float(f["p"]) * (0.5413 if inner else 0.6134)
				var rl := rk if not inner else rn
				for sgn in [1.0, -1.0]:
					draw_line(P.call(float(f["z0"]), rl * sgn), P.call(float(f["z1"]), rl * sgn), THIN, 1.0)
				var tag: Vector2 = P.call((float(f["z0"]) + float(f["z1"])) * 0.5, rn)
				_centered(tag + Vector2(0, -8 if not inner else 14), "M%s x %s%s" % [_num(float(f["d"])), _num(float(f["p"])), " innen" if inner else ""], SMALL)
	if job.has("rz"):
		_text(Vector2(area.position.x + 8.0, area.end.y - 8.0), "Oberfläche Rz %s µm" % _num(float(job["rz"])), FONT)


func _dias() -> Array:
	var out := []
	for f in job["features"]:
		if str(f.get("type", "dia")) == "dia":
			out.append(f)
	out.sort_custom(func(a, b): return float(a["z0"]) < float(b["z0"]))
	return out


# ------------------------------------------------------------ Frästeil

func _draw_milled(area: Rect2) -> void:
	var s: Array = job["size"]
	var l := float(s[0])
	var w := float(s[1])
	var h := float(s[2])
	# Platz: Draufsicht oben, Vorderansicht darunter, Seitenansicht (so breit wie das Teil tief) rechts daneben
	var sc := minf((area.size.x - 140.0) / (l + w), (area.size.y - 150.0) / (w + h))
	var origin := Vector2(area.position.x + 60.0, area.position.y + 40.0 + w * sc)
	_top_view(origin, sc, l, w)
	_front_view(Vector2(origin.x, origin.y + 44.0), sc, l, h, true)
	_front_view(Vector2(origin.x + l * sc + 60.0, origin.y + 44.0), sc, w, h, false)
	# Maße des Rohteils
	_dim_horizontal(origin + Vector2(0, -w * sc), origin + Vector2(l * sc, -w * sc), origin.y - w * sc - 18.0, _num(l))
	_dim_side(origin, origin + Vector2(0, -w * sc), origin.x - 22.0, _num(w))
	_dim_side(Vector2(origin.x, origin.y + 44.0 + h * sc), Vector2(origin.x, origin.y + 44.0), origin.x - 22.0, _num(h))
	if job.has("rest"):
		_text(Vector2(area.position.x + 8.0, area.end.y - 8.0), "Übrige Fläche Z %s" % _num(float(job["rest"])), SMALL)


func _top_view(o: Vector2, sc: float, l: float, w: float) -> void:
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, -y) * sc
	draw_rect(Rect2(P.call(0.0, w), Vector2(l, w) * sc), FILL)
	for f in job["features"]:
		if str(f["type"]) == "area":
			var r := Rect2(P.call(float(f["x0"]), float(f["y1"])), Vector2(float(f["x1"]) - float(f["x0"]), float(f["y1"]) - float(f["y0"])) * sc)
			draw_rect(r, CUT)
			draw_rect(r, INK, false, 1.5)
			_centered(r.get_center() + Vector2(0, 5), "Z %s" % _num(float(f["z"])), SMALL)
			# Lage der Fläche, wenn sie nicht bis an den Rand geht
			if float(f["x0"]) > 0.0:
				_text(P.call(float(f["x0"]), float(f["y0"])) + Vector2(2, -3), "X%s" % _num(float(f["x0"])), SMALL)
			if float(f["y0"]) > 0.0:
				_text(P.call(float(f["x0"]), float(f["y0"])) + Vector2(2, 14), "Y%s" % _num(float(f["y0"])), SMALL)
	draw_rect(Rect2(P.call(0.0, w), Vector2(l, w) * sc), INK, false, 2.0)
	for f in job["features"]:
		if str(f["type"]) == "hole":
			var c: Vector2 = P.call(float(f["cx"]), float(f["cy"]))
			var r := float(f["d"]) * 0.5 * sc
			draw_circle(c, r, Color(1, 1, 1))
			draw_arc(c, r, 0.0, TAU, 40, INK, 1.5, true)
			draw_line(c - Vector2(r + 5.0, 0), c + Vector2(r + 5.0, 0), THIN, 1.0)
			draw_line(c - Vector2(0, r + 5.0), c + Vector2(0, r + 5.0), THIN, 1.0)
			_text(c + Vector2(r + 3.0, -r - 3.0), "Ø%s T%s" % [_num(float(f["d"])), _num(-float(f["z"]))], SMALL)
			_text(c + Vector2(r + 3.0, r + 14.0), "X%s Y%s" % [_num(float(f["cx"])), _num(float(f["cy"]))], SMALL)


## Ansicht von vorn (along_x) oder von der Seite. Abtrag gestrichelt, die fertige Oberseite durchgezogen.
func _front_view(o: Vector2, sc: float, span: float, h: float, along_x: bool) -> void:
	draw_rect(Rect2(o, Vector2(span, h) * sc), FILL)
	draw_rect(Rect2(o, Vector2(span, h) * sc), INK, false, 2.0)
	if float(job.get("rest", 0.0)) < 0.0:
		var ry := o.y - float(job["rest"]) * sc
		draw_line(Vector2(o.x, ry), Vector2(o.x + span * sc, ry), INK, 1.5)
	for f in job["features"]:
		var a := 0.0
		var b := 0.0
		if str(f["type"]) == "hole":
			var c := float(f["cx"] if along_x else f["cy"])
			a = c - float(f["d"]) * 0.5
			b = c + float(f["d"]) * 0.5
		else:
			a = float(f["x0"] if along_x else f["y0"])
			b = float(f["x1"] if along_x else f["y1"])
		var y := o.y - float(f["z"]) * sc
		var xa := o.x + a * sc
		var xb := o.x + b * sc
		_dashed(Vector2(xa, o.y), Vector2(xa, y))
		_dashed(Vector2(xb, o.y), Vector2(xb, y))
		_dashed(Vector2(xa, y), Vector2(xb, y))
	var title := "Vorderansicht" if along_x else "Seitenansicht"
	_text(o + Vector2(0, h * sc + 18.0), title, SMALL)


# ------------------------------------------------------------ Zeichenhilfen

func _text(at: Vector2, t: String, font_size: int) -> void:
	draw_string(get_theme_default_font(), at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)


func _centered(at: Vector2, t: String, font_size: int) -> void:
	var w := get_theme_default_font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# Heller Grund, damit der Text auch über Linien lesbar bleibt
	draw_rect(Rect2(at + Vector2(-w * 0.5 - 2.0, -font_size), Vector2(w + 4.0, font_size + 4.0)), PAPER)
	_text(at - Vector2(w * 0.5, 0), t, font_size)


func _dashed(a: Vector2, b: Vector2) -> void:
	draw_dashed_line(a, b, THIN, 1.0, 5.0)


func _arrow(tip: Vector2, dir: Vector2) -> void:
	var n := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip + dir * 9.0 + n * 3.0, tip + dir * 9.0 - n * 3.0]), THIN)


func _dim_vertical(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, THIN, 1.0)
	_arrow(a, Vector2.DOWN)
	_arrow(b, Vector2.UP)


## Waagerechtes Maß bei Höhe y, mit Hilfslinien bis zu den Punkten a und b.
func _dim_horizontal(a: Vector2, b: Vector2, y: float, t: String) -> void:
	draw_line(a, Vector2(a.x, y + 4.0), Color(THIN, 0.6), 1.0)
	draw_line(b, Vector2(b.x, y + 4.0), Color(THIN, 0.6), 1.0)
	draw_line(Vector2(a.x, y), Vector2(b.x, y), THIN, 1.0)
	if absf(b.x - a.x) > 22.0:
		_arrow(Vector2(a.x, y), Vector2.RIGHT)
		_arrow(Vector2(b.x, y), Vector2.LEFT)
	_centered(Vector2((a.x + b.x) * 0.5, y - 3.0), t, SMALL)


## Senkrechtes Maß links neben dem Teil bei x, a unten, b oben.
func _dim_side(a: Vector2, b: Vector2, x: float, t: String) -> void:
	draw_line(a, Vector2(x - 4.0, a.y), Color(THIN, 0.6), 1.0)
	draw_line(b, Vector2(x - 4.0, b.y), Color(THIN, 0.6), 1.0)
	draw_line(Vector2(x, a.y), Vector2(x, b.y), THIN, 1.0)
	_arrow(Vector2(x, a.y), Vector2.UP)
	_arrow(Vector2(x, b.y), Vector2.DOWN)
	_centered(Vector2(x, (a.y + b.y) * 0.5 + 5.0), t, SMALL)


## 56 statt 56,0, sonst mit Komma.
static func _num(v: float) -> String:
	var t := ("%.2f" % v).replace(".", ",")
	return t.trim_suffix("0").trim_suffix("0").trim_suffix(",")
