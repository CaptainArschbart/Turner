class_name TncPlot
extends Control
## Grafik des Programm-Tests der Steuerung (TncScreen): Draufsicht auf das Rohteil mit dem Abtrag aus
## MillNc.simulate als Tiefenfarben (grau = unberührt, hell- bis dunkelblau = flach bis tief) und darüber die
## Werkzeugbahn (Vorschub gelb durchgezogen, Eilgang rot gestrichelt). Rechts die Tiefenlegende.
## Das Bild der Höhenkarte und die Bahn werden nur in set_result() berechnet, _draw zeichnet nur noch.
## Dazu TncPlot.Section: Seitenansicht (Schnitt durch die tiefste Stelle).

const C_BG := Color(0.09, 0.11, 0.15)
const C_RAW := Color(0.60, 0.64, 0.70)
const C_FEED := Color(1.0, 0.86, 0.22)
const C_RAPID := Color(1.0, 0.46, 0.36)
const C_TXT := Color(0.86, 0.90, 0.95)
const C_MUT := Color(0.58, 0.64, 0.72)
const MAX_SEGS := 60000

var show_feed := true:
	set(v):
		show_feed = v
		queue_redraw()
var show_rapid := true:
	set(v):
		show_rapid = v
		queue_redraw()
var font: Font
var has_data := false
var info := ""                 # Textzeile unten links (z. B. Rohteilmaße)
var _tex: ImageTexture
var _size := Vector3(100, 60, 40)
var _feed := PackedVector2Array()
var _rapid := PackedVector2Array()
var _plunge := PackedVector2Array()
var _segs := 0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Farbe für Abtrag t = Tiefe / Rohteilhöhe (0 = flach, 1 = ganz durch).
static func depth_color(t: float) -> Color:
	return Color(0.62, 0.86, 1.0).lerp(Color(0.05, 0.16, 0.52), pow(clampf(t, 0.0, 1.0), 0.55))


func clear() -> void:
	has_data = false
	_tex = null
	_feed = PackedVector2Array()
	_rapid = PackedVector2Array()
	_plunge = PackedVector2Array()
	_segs = 0
	queue_redraw()


## size = Rohteil (L, B, H), hmap = Ergebnis von MillNc.simulate, ops = Schrittliste, shift = Verschiebung
## Programmkoordinaten -> Rohteilkoordinaten (Rohteil-Ecke, Oberkante), die von den Bahnpunkten abgezogen wird.
func set_result(blk: Vector3, hmap: Dictionary, ops: Array, shift: Vector3) -> void:
	_size = blk
	var nx := int(hmap["nx"])
	var ny := int(hmap["ny"])
	var h: PackedFloat32Array = hmap["h"]
	var img := Image.create(nx, ny, false, Image.FORMAT_RGB8)
	var depth := maxf(blk.z, 0.001)
	for j in ny:
		for i in nx:
			var v := h[j * nx + i]
			img.set_pixel(i, ny - 1 - j, C_RAW if v > -0.001 else depth_color(-v / depth))
	_tex = ImageTexture.create_from_image(img)
	_feed = PackedVector2Array()
	_rapid = PackedVector2Array()
	_plunge = PackedVector2Array()
	var p := Vector3.ZERO
	var have := false
	var n_mv := 0
	for op in ops:
		if str(op["op"]) == "mv":
			n_mv += 1
	var stride := maxi(1, int(ceil(float(n_mv) / float(MAX_SEGS))))
	var k := 0
	for op in ops:
		if str(op["op"]) != "mv":
			continue
		var to: Vector3 = (op["to"] as Vector3) - shift
		if have:
			var a := Vector2(p.x, p.y)
			var b := Vector2(to.x, to.y)
			if a.distance_to(b) > 0.02:
				k += 1
				if bool(op["rapid"]):
					_rapid.append(a)
					_rapid.append(b)
				elif k % stride == 0:
					_feed.append(a)
					_feed.append(b)
			elif not bool(op["rapid"]) and to.z < p.z - 0.01:
				_plunge.append(b)
		p = to
		have = true
	_segs = floori(float(_feed.size() + _rapid.size()) * 0.5)
	has_data = true
	queue_redraw()


func _fnt() -> Font:
	return font if font != null else ThemeDB.fallback_font


## Rechteck des Rohteils auf dem Bildschirm und Maßstab (Pixel je mm).
func _rect() -> Array:
	var left := 38.0
	var right := 70.0
	var top := 22.0
	var bottom := 26.0
	var avail := Vector2(maxf(size.x - left - right, 20.0), maxf(size.y - top - bottom, 20.0))
	var s := minf(avail.x / maxf(_size.x, 1.0), avail.y / maxf(_size.y, 1.0))
	var w := _size.x * s
	var h := _size.y * s
	var r := Rect2(left + (avail.x - w) * 0.5, top + (avail.y - h) * 0.5, w, h)
	return [r, s]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	var f := _fnt()
	if not has_data:
		draw_string(f, Vector2(12, size.y * 0.5), "Noch kein Test gerechnet", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 16, C_MUT)
		return
	var rs := _rect()
	var r: Rect2 = rs[0]
	var s: float = rs[1]
	draw_string(f, Vector2(8, 16), "DRAUFSICHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_MUT)
	draw_texture_rect(_tex, r, false)
	draw_rect(r, C_TXT, false, 1.0)
	# Maße
	draw_string(f, Vector2(r.position.x, r.end.y + 17), "X0", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_MUT)
	draw_string(f, Vector2(r.end.x - 60, r.end.y + 17), "X%s" % MillNc.fmt(_size.x).trim_prefix("+"), HORIZONTAL_ALIGNMENT_RIGHT, 60, 13, C_MUT)
	draw_string(f, Vector2(r.position.x - 34, r.end.y), "Y0", HORIZONTAL_ALIGNMENT_RIGHT, 30, 13, C_MUT)
	draw_string(f, Vector2(r.position.x - 34, r.position.y + 12), "Y%s" % MillNc.fmt(_size.y).trim_prefix("+"), HORIZONTAL_ALIGNMENT_RIGHT, 30, 13, C_MUT)
	# Bahn: Koordinaten x nach rechts, y nach oben
	draw_set_transform(Vector2(r.position.x, r.end.y), 0.0, Vector2(s, -s))
	if show_rapid and _rapid.size() >= 2:
		var dashed := _rapid.size() <= 800
		if dashed:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var o := Vector2(r.position.x, r.end.y)
			for i in range(0, _rapid.size() - 1, 2):
				draw_dashed_line(o + Vector2(_rapid[i].x, -_rapid[i].y) * s, o + Vector2(_rapid[i + 1].x, -_rapid[i + 1].y) * s, C_RAPID, 1.3, 5.0)
			draw_set_transform(Vector2(r.position.x, r.end.y), 0.0, Vector2(s, -s))
		else:
			draw_multiline(_rapid, Color(C_RAPID, 0.7), 1.0 / s)
	if show_feed:
		if _feed.size() >= 2:
			draw_multiline(_feed, C_FEED, 1.6 / s)
		for pt in _plunge:
			draw_circle(pt, 2.6 / s, C_FEED)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Tiefenlegende
	var lx := size.x - 58.0
	var ly := 28.0
	var lh := maxf(size.y - 28.0 - 34.0, 20.0)
	draw_string(f, Vector2(lx - 4, 16), "TIEFE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_MUT)
	draw_rect(Rect2(lx, ly, 14, 8), C_RAW)
	var steps := 24
	for i in steps:
		var t := float(i) / float(steps - 1)
		draw_rect(Rect2(lx, ly + 10 + (lh - 10) * float(i) / steps, 14, (lh - 10) / steps + 1.0), depth_color(t))
	draw_string(f, Vector2(lx + 18, ly + 8), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_TXT)
	draw_string(f, Vector2(lx + 18, ly + lh), "-%s" % MillNc.fmt(_size.z).trim_prefix("+"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_TXT)
	if info != "":
		draw_string(f, Vector2(110, 16), info, HORIZONTAL_ALIGNMENT_LEFT, size.x - 180, 13, C_MUT)


## Seitenansicht: Schnitt durch die Reihe mit dem tiefsten Abtrag (Blick von vorn, X nach rechts).
class Section extends Control:
	var font: Font
	var has_data := false
	var _size := Vector3(100, 60, 40)
	var _prof := PackedFloat32Array()
	var _y := 0.0

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func clear() -> void:
		has_data = false
		_prof = PackedFloat32Array()
		queue_redraw()

	func set_result(blk: Vector3, hmap: Dictionary) -> void:
		_size = blk
		var nx := int(hmap["nx"])
		var cell := float(hmap["cell"])
		var h: PackedFloat32Array = hmap["h"]
		var best := 0
		var best_v := 0.0
		for idx in h.size():
			if h[idx] < best_v:
				best_v = h[idx]
				best = idx
		var row := floori(float(best) / float(nx))
		_y = (row + 0.5) * cell
		_prof = PackedFloat32Array()
		_prof.resize(nx)
		for i in nx:
			_prof[i] = h[row * nx + i]
		has_data = true
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), TncPlot.C_BG)
		var f: Font = font if font != null else ThemeDB.fallback_font
		draw_string(f, Vector2(8, 16), "SEITENANSICHT" + (("   Schnitt bei Y%s" % MillNc.fmt(snappedf(_y, 0.1)).trim_prefix("+")) if has_data else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TncPlot.C_MUT)
		if not has_data:
			return
		var left := 38.0
		var right := 70.0
		var top := 26.0
		var bottom := 8.0
		var w := maxf(size.x - left - right, 20.0)
		var hgt := maxf(size.y - top - bottom, 12.0)
		var sx := w / maxf(_size.x, 1.0)
		var sz := hgt / maxf(_size.z, 1.0)
		var x0 := left
		var ztop := top
		# Material: Rohteil bis zur Unterkante, oben die abgetragene Kontur
		var poly := PackedVector2Array()
		poly.append(Vector2(x0, ztop + hgt))
		var n := _prof.size()
		for i in n:
			var xm := x0 + (float(i) + 0.5) / float(n) * w
			poly.append(Vector2(xm, ztop + clampf(-_prof[i], 0.0, _size.z) * sz))
		poly.append(Vector2(x0 + w, ztop + hgt))
		draw_colored_polygon(poly, TncPlot.C_RAW.darkened(0.25))
		draw_polyline(poly.slice(1, poly.size() - 1), TncPlot.C_TXT, 1.5)
		draw_dashed_line(Vector2(x0, ztop), Vector2(x0 + w, ztop), TncPlot.C_MUT, 1.0, 4.0)
		draw_rect(Rect2(x0, ztop, w, hgt), TncPlot.C_MUT, false, 1.0)
		draw_string(f, Vector2(x0 - 34, ztop + 11), "Z0", HORIZONTAL_ALIGNMENT_RIGHT, 30, 13, TncPlot.C_MUT)
		draw_string(f, Vector2(x0 - 34, ztop + hgt), "-%s" % MillNc.fmt(_size.z).trim_prefix("+"), HORIZONTAL_ALIGNMENT_RIGHT, 30, 13, TncPlot.C_MUT)
