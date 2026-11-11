class_name NcPlot
extends Control
## 2D-Ansicht der Zyklensteuerung (Halbschnitt über der Drehachse, Z nach rechts, X nach oben):
## Futter, Werkstück (Ist-Material oder vorausberechnetes Material), Konturen, Verfahrwege
## (Eilgang gestrichelt rot, Vorschub grün) und die Schneide an ihrer aktuellen Lage.

var lathe: Lathe
var prof := PackedFloat32Array()          # leer = Ist-Material der Maschine
var bore := PackedFloat32Array()          # Bohrung zu prof (leer: bei Ist-Material die der Maschine)
var polys: Array = []                      # Konturen (PackedVector2Array in Programm-z, r)
var hi_poly := PackedVector2Array()        # hervorgehobene Kontur (Programm-z)
var hi_point := Vector2(NAN, NAN)          # hervorgehobener Konturpunkt (Programm-z, r)
var moves: Array = []                      # [z, x, eilgang, ...] in Maschinen-z (ab Backe)
var done_moves := 0                        # bereits gefahrene Züge (dunkler)
var start_pos := Vector2(NAN, NAN)         # Lage vor dem ersten Zug
var show_tool := true
var title := ""

var _s := 1.0
var _o := Vector2.ZERO
var _z0 := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _profile() -> PackedFloat32Array:
	if not prof.is_empty():
		return prof
	return lathe.profile if lathe else PackedFloat32Array()


func _bore() -> PackedFloat32Array:
	if not prof.is_empty():
		return bore
	return lathe.bore if lathe else PackedFloat32Array()


func _p(z: float, r: float) -> Vector2:
	return Vector2(_o.x + (z - _z0) * _s, _o.y - r * _s)


## Werkstücknullpunkt (Programm-Z 0) in Maschinen-z.
func _zo() -> float:
	return lathe.wcs_z if lathe else 0.0


func _fit(pr: PackedFloat32Array) -> void:
	var zmax := pr.size() * Lathe.SEG
	var rmax := 0.0
	for r in pr:
		rmax = maxf(rmax, r)
	for pl in polys + [hi_poly]:
		for q in pl:
			zmax = maxf(zmax, q.x + _zo())
			rmax = maxf(rmax, q.y)
	for m in moves:
		zmax = maxf(zmax, minf(float(m[0]), pr.size() * Lathe.SEG + 40.0))
		rmax = maxf(rmax, minf(float(m[1]), rmax + 20.0))
	_z0 = -22.0
	var zr := zmax + 12.0 - _z0
	var rr := rmax + 12.0
	_s = minf((size.x - 10.0) / zr, (size.y - 22.0) / rr)
	_o = Vector2(6.0, size.y - 8.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.075, 0.085, 0.10))
	# feines Raster
	var gc := Color(1, 1, 1, 0.035)
	var gx := 0.0
	while gx < size.x:
		draw_line(Vector2(gx, 0), Vector2(gx, size.y), gc, 1.0)
		gx += 20.0
	var gy := size.y
	while gy > 0.0:
		draw_line(Vector2(0, gy), Vector2(size.x, gy), gc, 1.0)
		gy -= 20.0
	var pr := _profile()
	if pr.is_empty():
		return
	_fit(pr)
	var seg := Lathe.SEG
	# Futter mit Backe
	var r0 := pr[0] if pr.size() > 0 else 20.0
	draw_rect(Rect2(_p(-20.0, r0 + 14.0), Vector2(20.0 * _s, (r0 + 14.0) * _s)), Color(0.27, 0.29, 0.33))
	draw_rect(Rect2(_p(-8.0, r0 + 9.0), Vector2(8.0 * _s, 9.0 * _s)), Color(0.19, 0.2, 0.23))
	# Werkstück
	var pts := PackedVector2Array([_p(0.0, 0.0)])
	var i := 0
	while i < pr.size():
		var r := pr[i]
		var j := i
		while j + 1 < pr.size() and absf(pr[j + 1] - r) < 0.005:
			j += 1
		pts.append(_p(i * seg, r))
		pts.append(_p((j + 1) * seg, r))
		i = j + 1
	pts.append(_p(pr.size() * seg, 0.0))
	if pts.size() >= 3:
		draw_colored_polygon(pts, Color(0.36, 0.39, 0.44))
		draw_polyline(pts, Color(0.62, 0.66, 0.72), 1.0)
	# Bohrung: Halbschnitt bis zur Bohrungswand freistellen (Rechtecke je Stufe)
	var bo := _bore()
	if bo.size() == pr.size():
		var k := 0
		while k < bo.size():
			var b := bo[k]
			var j := k
			while j + 1 < bo.size() and absf(bo[j + 1] - b) < 0.005:
				j += 1
			if b > 0.05:
				var a := _p(k * seg, b)
				var e := _p((j + 1) * seg, 0.0)
				draw_rect(Rect2(a, e - a), Color(0.075, 0.085, 0.10))
				draw_line(a, Vector2(e.x, a.y), Color(0.62, 0.66, 0.72), 1.0)
			k = j + 1
	# Drehachse
	draw_dashed_line(_p(_z0, 0.0), _p(_z0 + (size.x - 12.0) / _s, 0.0), Color(0.5, 0.54, 0.6), 1.0, 6.0)
	# Konturen
	for pl in polys:
		_poly(pl, Color(0.35, 0.6, 1.0), 1.5)
	if hi_poly.size() >= 2:
		_poly(hi_poly, Color(0.55, 0.8, 1.0), 2.5)
	if not is_nan(hi_point.x):
		draw_circle(_p(hi_point.x + _zo(), hi_point.y), 4.0, Color(1.0, 0.65, 0.2))
	# Werkstücknullpunkt W an Z0 auf der Drehachse
	var w0 := _p(_zo(), 0.0)
	var wc := Color(1.0, 0.85, 0.3)
	draw_arc(w0, 6.0, 0.0, TAU, 20, wc, 1.5)
	draw_line(w0 + Vector2(-9, 0), w0 + Vector2(9, 0), wc, 1.0)
	draw_line(w0 + Vector2(0, -9), w0 + Vector2(0, 9), wc, 1.0)
	draw_string(get_theme_default_font(), w0 + Vector2(-4, -11), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, wc)
	# Verfahrwege
	var last := start_pos
	for k in moves.size():
		var m: Array = moves[k]
		var q := Vector2(float(m[0]), float(m[1]))
		if not is_nan(last.x):
			var a := _p(last.x, last.y)
			var b := _p(q.x, q.y)
			var dim := k < done_moves
			if bool(m[2]):
				draw_dashed_line(a, b, Color(1.0, 0.38, 0.32, 0.35 if dim else 0.9), 1.0, 4.0)
			else:
				draw_line(a, b, Color(0.35, 0.9, 0.5, 0.35 if dim else 0.95), 1.2)
		last = q
	# Schneide
	if show_tool and lathe:
		var t := lathe.tool()
		if t.has("bar"):
			var bar: Rect2 = t["bar"]
			var b0 := _p(lathe.tool_z + bar.position.x, lathe.tool_x + bar.end.y)
			var b1 := _p(lathe.tool_z + bar.end.x, lathe.tool_x + bar.position.y)
			draw_rect(Rect2(b0, b1 - b0), Color(0.42, 0.44, 0.5))
		var poly: PackedVector2Array = t["poly"]
		var tp := PackedVector2Array()
		for v in poly:
			tp.append(_p(lathe.tool_z + v.x, lathe.tool_x + v.y))
		draw_colored_polygon(tp, Color(0.95, 0.7, 0.1))
		draw_polyline(tp + PackedVector2Array([tp[0]]), Color(1.0, 0.9, 0.6), 1.0)
	if title != "":
		draw_string(get_theme_default_font(), Vector2(6, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.78, 1.0))
	# Maßstab
	var mm := 10.0 if _s > 2.0 else 50.0
	var y := 14.0
	var x1 := size.x - 8.0
	draw_line(Vector2(x1 - mm * _s, y), Vector2(x1, y), Color(0.6, 0.64, 0.7), 1.0)
	draw_string(get_theme_default_font(), Vector2(x1 - mm * _s - 34.0, y + 4.0), "%d mm" % int(mm), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.64, 0.7))


func _poly(pl: PackedVector2Array, c: Color, w: float) -> void:
	if pl.size() < 2:
		return
	var out := PackedVector2Array()
	for q in pl:
		out.append(_p(q.x + _zo(), q.y))
	draw_polyline(out, c, w)
