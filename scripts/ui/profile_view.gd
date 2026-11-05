class_name ProfileView
extends Control
## Halbschnitt-Ansicht: aktuelles Werkstück, Soll-Kontur des Auftrags und Schneidplatte.

var lathe: Lathe
var job: Dictionary = {}

const BG := Color(0.03, 0.04, 0.05, 0.9)
const PART := Color(0.62, 0.66, 0.72)
const RAW := Color(0.36, 0.37, 0.4)
const TARGET := Color(1.0, 0.55, 0.15)
const TOOL := Color(0.95, 0.8, 0.3)
const JAW := Color(0.25, 0.26, 0.28)


func _ready() -> void:
	custom_minimum_size = Vector2(460, 160)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if lathe == null or lathe.profile.is_empty():
		return
	var r_max := lathe.stock_d * 0.5 + 12.0
	var z0 := -14.0
	var z1 := lathe.stock_len + 16.0
	var pad := 12.0
	var sc := minf((size.x - pad * 2.0) / (z1 - z0), (size.y - pad * 2.0) / r_max)
	var base := Vector2(pad, size.y - pad)
	var P := func(z: float, r: float) -> Vector2: return base + Vector2((z - z0) * sc, -r * sc)

	# Mittellinie
	var a: Vector2 = P.call(z0, 0.0)
	var b: Vector2 = P.call(z1, 0.0)
	var x := a.x
	while x < b.x:
		draw_line(Vector2(x, a.y), Vector2(minf(x + 10.0, b.x), a.y), Color(1, 1, 1, 0.35), 1.0)
		x += 16.0
	# Spannbacken
	var jr := lathe.stock_d * 0.5
	draw_rect(Rect2(P.call(-10.0, jr + 10.0), Vector2(10.0 * sc, 10.0 * sc)), JAW)

	# Rohteil-Umriss
	draw_rect(Rect2(P.call(0.0, lathe.stock_d * 0.5), Vector2(lathe.stock_len * sc, lathe.stock_d * 0.5 * sc)), RAW, false, 1.0)

	# Werkstück als gefülltes Halbprofil (Streifen)
	var n := lathe.profile.size()
	var i := 0
	while i < n:
		var r := lathe.profile[i]
		var j := i
		while j + 1 < n and absf(lathe.profile[j + 1] - r) < 0.01:
			j += 1
		if r > 0.0:
			var tl: Vector2 = P.call(i * Lathe.SEG, r)
			draw_rect(Rect2(tl, Vector2((j + 1 - i) * Lathe.SEG * sc + 0.6, r * sc)), PART)
		i = j + 1

	# Soll-Kontur
	for f in job.get("features", []):
		match str(f.get("type", "dia")):
			"dia":
				var rr := float(f["d"]) * 0.5
				draw_line(P.call(float(f["z0"]), rr), P.call(float(f["z1"]), rr), TARGET, 2.0)
			"chamfer":
				var c := float(f["size"])
				var rd := float(f["d"]) * 0.5
				var ze := float(f["z"])
				draw_line(P.call(ze - c, rd), P.call(ze, rd - c), TARGET, 2.0)
			"point":
				var pp: Vector2 = P.call(float(f["z"]), float(f["d"]) * 0.5)
				draw_circle(pp, 3.5, TARGET)
	if job.has("length"):
		var l := float(job["length"])
		draw_line(P.call(l, 0.0), P.call(l, lathe.stock_d * 0.5 + 4.0), TARGET, 1.5)

	# Schneidplatte an aktueller Position
	var t := lathe.tool()
	var poly: PackedVector2Array = t["poly"]
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(P.call(lathe.tool_z + p.x, lathe.tool_x + p.y))
	if Geometry2D.triangulate_polygon(pts).size() > 0:
		draw_colored_polygon(pts, Color(TOOL, 0.85))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.2, 0.15, 0.05), 1.0)
	draw_circle(P.call(lathe.tool_z, lathe.tool_x), 2.5, Color(1, 0.2, 0.2))

	var font := get_theme_default_font()
	draw_string(font, Vector2(10, 18), "Kontur (Halbschnitt)   Orange = Soll   Rot = Bezugspunkt", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
