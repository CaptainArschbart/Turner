class_name Whiteboard
extends Node3D
## Whiteboard an der Wand des Meisterbüros. Darauf steht der Tagesbericht: Tag und Uhrzeit, ob der Tag läuft,
## die Zahlen von heute, die offenen Aufträge und der Vortag. Per Interaktion öffnet es die Großansicht, in der
## sich der Tag starten und beenden lässt. Die beschriebene Fläche zeigt nach +Z, Mitte im Ursprung.

signal using_changed(on: bool)

const SIZE := Vector2(1.8, 1.1)
const STAND := Vector3(0.0, 0.0, 1.25)
const RED := Color(0.75, 0.1, 0.08)
const BLUE := Color(0.08, 0.2, 0.6)
const BLACK := Color(0.1, 0.11, 0.13)
const GREEN := Color(0.05, 0.45, 0.15)
const MAX_JOBS := 6

## Spielwelt: day, day_started, day_over, day_stats, last_day_stats, accepted, clock_text(), start_day(), next_day()
var shop: Node = null
var overlay: DayBoardOverlay
var player: Node = null
var _clock: Label3D
var _state: Label3D
var _today: Label3D
var _jobs: Label3D
var _last: Label3D
static var _marker: Font


## Krakelige Handschrift wie mit dem Whiteboard-Marker geschrieben. Die Systemschrift von Windows, sonst die Standardschrift.
static func marker_font() -> Font:
	if _marker == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Ink Free", "Segoe Print", "Comic Sans MS", "Chalkboard", "Comic Neue"])
		sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_marker = sf
	return _marker


func _ready() -> void:
	_build()
	var hit := Build.collider(self, Vector3(SIZE.x, SIZE.y, 0.08), Vector3(0, 0, -0.02))
	hit.set_meta("interact", self)
	overlay = DayBoardOverlay.new()
	overlay.closed.connect(stop_using)
	add_child(overlay)
	refresh()


func _build() -> void:
	var w := SIZE.x
	var h := SIZE.y
	var alu := Build.mat(Color(0.78, 0.8, 0.82), 0.3, 0.8)
	var grey := Build.mat(Color(0.35, 0.37, 0.4), 0.5, 0.3)
	Build.box(self, Vector3(w, h, 0.02), Vector3(0, 0, -0.012), Build.mat(Color(0.97, 0.98, 0.97), 0.15))
	# Aluminiumrahmen mit Eckkappen
	for y in [-h * 0.5, h * 0.5]:
		Build.box(self, Vector3(w + 0.06, 0.035, 0.035), Vector3(0, y, -0.006), alu)
	for x in [-w * 0.5, w * 0.5]:
		Build.box(self, Vector3(0.035, h + 0.06, 0.035), Vector3(x, 0, -0.006), alu)
		for y in [-h * 0.5, h * 0.5]:
			Build.box(self, Vector3(0.05, 0.05, 0.04), Vector3(x, y, -0.005), grey)
	# Stiftablage mit Markern und Schwamm
	Build.box(self, Vector3(w * 0.6, 0.015, 0.08), Vector3(0, -h * 0.5 - 0.04, 0.03), alu)
	Build.box(self, Vector3(w * 0.6, 0.03, 0.01), Vector3(0, -h * 0.5 - 0.03, 0.07), alu)
	var caps := [RED, BLUE, BLACK, GREEN]
	for i in 4:
		var x := -0.36 + i * 0.09
		Build.cyl(self, 0.009, 0.13, Vector3(x, -h * 0.5 - 0.022, 0.035), Build.mat(Color(0.92, 0.92, 0.9), 0.5), Build.AXIS_X, false, 10)
		Build.cyl(self, 0.01, 0.03, Vector3(x + 0.075, -h * 0.5 - 0.022, 0.035), Build.mat(caps[i], 0.5), Build.AXIS_X, false, 10)
	Build.box(self, Vector3(0.13, 0.03, 0.05), Vector3(0.3, -h * 0.5 - 0.018, 0.035), Build.mat(Color(0.2, 0.3, 0.55), 0.8))
	Build.box(self, Vector3(0.13, 0.012, 0.05), Vector3(0.3, -h * 0.5 - 0.038, 0.035), Build.mat(Color(0.25, 0.25, 0.25), 0.9))
	# Magnete und ein angehefteter Zettel oben rechts
	Build.box(self, Vector3(0.2, 0.26, 0.002), Vector3(0.72, 0.36, 0.0), Build.mat(Color(0.98, 0.93, 0.45), 0.9), false, Vector3(0, 0, 0.06))
	Build.cyl(self, 0.018, 0.012, Vector3(0.72, 0.47, 0.006), Build.mat(Color(0.85, 0.15, 0.1), 0.4), Build.AXIS_Z, false, 12)
	var note := Build.label(self, "Späne\nabholen\nlassen!", Vector3(0.72, 0.34, 0.003), 0.0016, BLACK, 34)
	note.rotation.z = 0.06
	note.font = marker_font()
	for m in [[-0.84, 0.48, Color(0.1, 0.4, 0.8)], [0.84, -0.48, Color(0.2, 0.6, 0.2)]]:
		Build.cyl(self, 0.016, 0.012, Vector3(m[0], m[1], 0.006), Build.mat(m[2], 0.4), Build.AXIS_Z, false, 12)
	# Überschrift mit Strich, darunter zwei Spalten wie von Hand geschrieben
	_text("TAGESBERICHT", Vector3(-0.82, 0.5, 0.002), RED, 34, 0.0026)
	Build.box(self, Vector3(0.7, 0.006, 0.001), Vector3(-0.47, 0.38, 0.0015), Build.mat(RED, 0.6), false, Vector3(0, 0, 0.01))
	_clock = _text("", Vector3(0.02, 0.5, 0.002), BLUE, 36, 0.0024)
	_state = _text("", Vector3(-0.82, 0.33, 0.002), BLACK, 32, 0.0022)
	_today = _text("", Vector3(-0.82, 0.18, 0.002), BLUE, 32, 0.0021)
	_jobs = _text("", Vector3(0.0, 0.18, 0.002), BLACK, 32, 0.0021)
	_last = _text("", Vector3(-0.82, -0.36, 0.002), GREEN, 32, 0.0021)
	# Trennstrich zwischen den Spalten
	Build.box(self, Vector3(0.005, 0.5, 0.001), Vector3(-0.04, -0.06, 0.0015), Build.mat(BLACK, 0.6), false, Vector3(0, 0, -0.02))


func _text(t: String, pos: Vector3, c: Color, font_size: int, px: float) -> Label3D:
	var l := Build.label(self, t, pos, px, c, font_size)
	l.font = marker_font()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.line_spacing = 2.0
	return l


func get_prompt() -> String:
	return "[%s] Tagesbericht am Whiteboard" % Settings.binding_text("interact")


func interact(p: Node) -> void:
	if player:
		return
	player = p
	var stand := to_global(STAND)
	stand.y = p.global_position.y
	p.start_operating(self, stand, global_rotation.y)
	p.pitch = -0.05
	overlay.open()
	using_changed.emit(true)


func stop_using() -> void:
	if not player:
		return
	player.stop_operating()
	player = null
	using_changed.emit(false)


static func _money(eur: int) -> String:
	return "%+d EUR" % eur


## Tafel neu beschriften und die Großansicht nachziehen.
func refresh() -> void:
	if overlay and overlay.day_app:
		overlay.day_app.refresh()
	if shop == null or _clock == null:
		return
	_clock.text = shop.clock_text()
	if not shop.day_started:
		_state.text = "Tag noch nicht gestartet!"
		_state.modulate = RED
	elif shop.day_over:
		_state.text = "FEIERABEND: nach Hause"
		_state.modulate = RED
	else:
		_state.text = "Der Tag läuft."
		_state.modulate = GREEN
	var s: Dictionary = shop.day_stats
	_today.text = "Heute:\n  Angenommen: %d\n  Fertig: %d\n  Ein: %d EUR\n  Aus: %d EUR\n  Ergebnis: %s" % [
		int(s.get("accepted", 0)), int(s.get("done", 0)), int(s.get("earned", 0)), int(s.get("spent", 0)), _money(DayApp.profit_of(s))]
	var lines := PackedStringArray(["Offene Aufträge:"])
	var keys: Array = shop.accepted
	for i in mini(keys.size(), MAX_JOBS):
		var title := str(JobBoard.job_of(str(keys[i])).get("title", keys[i]))
		if title.length() > 28:
			title = title.substr(0, 27) + "…"
		lines.append("  • " + title)
	if keys.is_empty():
		lines.append("  keine")
	elif keys.size() > MAX_JOBS:
		lines.append("  + %d weitere" % (keys.size() - MAX_JOBS))
	_jobs.text = "\n".join(lines)
	var last: Dictionary = shop.last_day_stats
	_last.text = "Vortag: %d fertig, %s" % [int(last.get("done", 0)), _money(DayApp.profit_of(last))] if not last.is_empty() else ""
