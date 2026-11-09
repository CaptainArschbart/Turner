class_name BandSaw
extends Node3D
## Bandsäge mit Rollbahn. Die Stange liegt auf der Rollbahn, das Band trennt an x = 0, der Längenanschlag
## auf der rechten Bahn gibt das Maß vor. Der Abschnitt bleibt liegen, bis er mit der Hand abgeholt wird.
## Lokal: x entlang der Stange, Bedienseite bei +z.

const ROLL_TOP := 0.88            # Oberkante der Rollen
const ROLL_R := 0.035
const TABLE_END := 2.15           # Ende der Rollbahn
const MAX_SECTION := 230.0        # größter Querschnitt in mm
const MAX_LEN := 1000.0           # längster Abschnitt, bis dahin reicht der Anschlag
const CUT_RATE := 300.0           # mm² je Sekunde in Baustahl
const MIN_TIME := 2.0
const ARM_REST := -0.62           # hochgeschwenkter Sägebügel
const ARM_LIFT := 1.2             # rad je Sekunde beim Hochfahren
const BLADE_SPEED := 1500.0

## Spielwelt: player, hud, _tray_conflict(machine, material), saw_suggestion(item)
var world: Node
var tool_stock = null             # ohne Werkzeuge
var tray := ChipTray.new()
var spindle_speed := 0.0
var bar: Dictionary = {}
var piece: Dictionary = {}
var length_mm := 160.0
var cutting := false
var progress := 0.0
var panel: SawPanel

var _duration := 1.0
var _arm: Node3D
var _stop: Node3D
var _jaw: Node3D
var _stock_node: Node3D
var _chips: MeshInstance3D
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	_build()
	panel = SawPanel.new()
	panel.saw = self
	add_child(panel)
	refresh_stock()
	refresh_tray()


func get_machine() -> Node:
	return self


func has_bar() -> bool:
	return not bar.is_empty()


func has_piece() -> bool:
	return not piece.is_empty()


func get_prompt() -> String:
	var key: String = Settings.binding_text("interact")
	if cutting:
		return "Sägt: %d %%    |    [%s] Stoppen" % [int(progress * 100.0), key]
	if has_piece():
		return "[Linksklick] Abschnitt %d mm nehmen" % int(piece["l"])
	if has_bar():
		return "[%s] Länge einstellen und sägen    |    [Linksklick] Stange nehmen" % key
	return "Bandsäge: Stange in die Hände nehmen und mit Linksklick auflegen"


## Text, wenn der Spieler etwas in den Händen hält.
func carry_prompt(item: Dictionary) -> String:
	if cutting:
		return "Sägt: %d %%" % int(progress * 100.0)
	if has_bar() or has_piece():
		return "Bandsäge belegt: Erst abräumen, dafür die Hände frei machen"
	return "[Linksklick] Auf die Rollbahn legen    |    %s" % RawMaterialTab.describe(item)


func interact(_p: Node) -> void:
	if cutting:
		stop_cut()
	elif has_bar() and not has_piece():
		panel.open()
	elif has_piece():
		world.hud.show_message("Erst den Abschnitt von der Rollbahn nehmen.", Color(1, 0.75, 0.2))
	else:
		world.hud.show_message("Keine Stange auf der Rollbahn.", Color(1, 0.75, 0.2))


func click(_p: Node) -> void:
	world.saw_click(self)


## Stange auflegen.
func load_bar(item: Dictionary) -> void:
	bar = item
	length_mm = minf(length_mm, _longest())
	refresh_stock()


func take_piece() -> Dictionary:
	var out := piece
	piece = {}
	refresh_stock()
	return out


func take_bar() -> Dictionary:
	var out := bar
	bar = {}
	refresh_stock()
	return out


## Längster Abschnitt von der aufgelegten Stange.
func _longest() -> float:
	return minf(MAX_LEN, float(bar.get("l", MAX_LEN)))


func set_length(mm: float) -> void:
	if cutting:
		return
	length_mm = mm
	refresh_stock()


## Schnittdauer in Sekunden für den Querschnitt, harte Werkstoffe brauchen länger.
static func cut_time(item: Dictionary) -> float:
	var area := section_area(item)
	return maxf(area / (CUT_RATE * clampf(Materials.turn_factor(str(item["material"])), 0.4, 2.0)), MIN_TIME)


static func section_area(item: Dictionary) -> float:
	if str(item["kind"]) == Materials.KIND_ROUND:
		return PI * float(item["d"]) * float(item["d"]) * 0.25
	return float(item["w"]) * float(item["h"])


## Sägen starten. Fehlertext, leer = läuft.
func start_cut(mm: float) -> String:
	if cutting:
		return "Die Säge läuft schon."
	if not has_bar():
		return "Keine Stange auf der Rollbahn."
	if has_piece():
		return "Erst den Abschnitt von der Rollbahn nehmen."
	if mm < RawMaterialTab.CUT_MIN or mm > MAX_LEN:
		return "Abschnitt: %d bis %d mm." % [int(RawMaterialTab.CUT_MIN), int(MAX_LEN)]
	if mm >= float(bar["l"]):
		return "Die Stange ist nur noch %d mm lang." % int(bar["l"])
	var section := float(bar["d"]) if str(bar["kind"]) == Materials.KIND_ROUND else maxf(float(bar["w"]), float(bar["h"]))
	if section > MAX_SECTION:
		return "Der Querschnitt ist zu groß: höchstens %d mm." % int(MAX_SECTION)
	var mix: String = world._tray_conflict(self, str(bar["material"]))
	if mix != "":
		return mix
	length_mm = mm
	_duration = cut_time(bar)
	progress = 0.0
	cutting = true
	spindle_speed = BLADE_SPEED
	refresh_stock()
	return ""


## Schnitt abbrechen. Das Band ist noch nicht durch, die Stange bleibt ganz.
func stop_cut() -> void:
	cutting = false
	progress = 0.0
	spindle_speed = 0.0
	_show_running()


func _process(delta: float) -> void:
	if cutting:
		progress = minf(progress + delta / _duration, 1.0)
		_arm.rotation.x = lerpf(ARM_REST, 0.0, progress)
		_show_running()
		if progress >= 1.0:
			_finish()
	elif _arm != null and _arm.rotation.x > ARM_REST:
		_arm.rotation.x = maxf(_arm.rotation.x - ARM_LIFT * delta, ARM_REST)


func _finish() -> void:
	cutting = false
	progress = 0.0
	spindle_speed = 0.0
	_show_running()
	var id := str(bar["material"])
	var chips := Materials.weight_kg(id, str(bar["kind"]), float(bar.get("d", 0.0)), float(bar.get("w", 0.0)), float(bar.get("h", 0.0)), Materials.KERF)
	tray.add(str(Materials.group_of(id)["id"]), chips)
	refresh_tray()
	piece = Materials.cut_off(bar, length_mm)
	var text := "Abgesägt: %d mm. Mit Linksklick von der Rollbahn nehmen." % int(length_mm)
	if float(bar["l"]) < RawMaterialTab.CUT_MIN:
		bar = {}
		text += " Der Rest war zu kurz und ist Schrott."
	refresh_stock()
	if world != null and world.hud != null:
		world.hud.show_message(text, Color(0.7, 0.95, 1.0))


func refresh_tray() -> void:
	if _chips == null:
		return
	var f := tray.fraction()
	_chips.visible = f > 0.0
	_chips.scale.y = maxf(f, 0.02)
	_chips.position.y = 0.05 + 0.05 * f


func _show_running() -> void:
	if _lamp_mat != null:
		_lamp_mat.emission_energy_multiplier = 2.5 if cutting else 0.15


# ------------------------------------------------------------ Stange zeichnen

func refresh_stock() -> void:
	if _stock_node == null:
		return
	for c in _stock_node.get_children():
		_stock_node.remove_child(c)
		c.free()
	_stop.position.x = length_mm * 0.001
	var half := 0.05
	if has_bar():
		half = _half_width(bar)
		# Solange kein Abschnitt liegt, ist die Stange bis an den Anschlag vorgeschoben
		var end := -0.0015 if has_piece() else minf(length_mm, float(bar["l"])) * 0.001
		var total := minf(float(bar["l"]) * 0.001, end + TABLE_END)
		_draw_piece(bar, end - total, end)
	if has_piece():
		half = _half_width(piece)
		_draw_piece(piece, 0.0015, float(piece["l"]) * 0.001)
	_jaw.position.z = half + 0.015


static func _half_width(item: Dictionary) -> float:
	var w := float(item["d"]) if str(item["kind"]) == Materials.KIND_ROUND else float(item["w"])
	return w * 0.0005


func _draw_piece(item: Dictionary, x0: float, x1: float) -> void:
	var m := Build.mat(Materials.raw_color(str(item["material"])), 0.55, 0.4)
	var at := Vector3((x0 + x1) * 0.5, 0.0, 0.0)
	if str(item["kind"]) == Materials.KIND_ROUND:
		var r := float(item["d"]) * 0.0005
		at.y = ROLL_TOP + r
		Build.cyl(_stock_node, r, x1 - x0, at, m, Build.AXIS_X, false, 20)
	else:
		var h := float(item["h"]) * 0.001
		at.y = ROLL_TOP + h * 0.5
		Build.box(_stock_node, Vector3(x1 - x0, h, float(item["w"]) * 0.001), at, m)


# ------------------------------------------------------------ Speichern

func get_state() -> Dictionary:
	return {"bar": bar, "piece": piece, "len": length_mm, "tray": tray.to_state()}


func set_state(d: Dictionary) -> void:
	cutting = false
	progress = 0.0
	spindle_speed = 0.0
	var b = d.get("bar", {})
	bar = b.duplicate() if b is Dictionary else {}
	var p = d.get("piece", {})
	piece = p.duplicate() if p is Dictionary else {}
	length_mm = float(d.get("len", length_mm))
	tray.load_state(d.get("tray", {}))
	refresh_stock()
	refresh_tray()


# ------------------------------------------------------------ Modell nach dem Foto

func _build() -> void:
	var blue := Build.mat(Color(0.27, 0.46, 0.72), 0.5, 0.15)
	var blue_light := Build.mat(Color(0.42, 0.6, 0.84), 0.5, 0.1)
	var zinc := Build.mat(Color(0.74, 0.76, 0.78), 0.3, 1.0)
	var black := Build.mat(Color(0.07, 0.07, 0.08), 0.55)
	var grey := Build.mat(Color(0.86, 0.87, 0.86), 0.45, 0.1)
	var dark_steel := Build.mat(Color(0.25, 0.26, 0.28), 0.4, 0.8)
	var yellow := Build.mat(Color(0.95, 0.75, 0.05), 0.5)

	# Unterbau: oben breit, darunter schräg eingezogen
	Build.box(self, Vector3(0.84, 0.28, 0.84), Vector3(0, 0.7, 0), blue)
	Build.box(self, Vector3(0.84, 0.46, 0.56), Vector3(0, 0.33, -0.14), blue_light)
	Build.box(self, Vector3(0.84, 0.03, 0.5), Vector3(0, 0.34, 0.2), blue, false, Vector3(1.06, 0, 0))
	for x in [-0.36, 0.36]:
		for z in [-0.36, 0.36]:
			_leg(self, Vector3(x, 0, z), 0.55, blue, zinc)
	# Grundplatte und Auflage über dem Unterbau
	Build.box(self, Vector3(0.68, 0.03, 0.74), Vector3(0, 0.845, 0), blue)
	# Spänewanne unter dem Unterbau
	Build.box(self, Vector3(0.5, 0.12, 0.4), Vector3(0.14, 0.06, 0.34), dark_steel)
	_chips = Build.box(self, Vector3(0.46, 0.1, 0.36), Vector3(0.14, 0.1, 0.34), Build.mat(Color(0.55, 0.56, 0.58), 0.7, 0.6))

	# Rollbahn links und rechts
	_table(-TABLE_END, -0.36, blue, zinc)
	_table(0.36, TABLE_END, blue, zinc)

	# Bedienpult vorne links
	Build.box(self, Vector3(0.5, 0.26, 0.26), Vector3(-0.22, 0.73, 0.55), blue)
	var face := Build.box(self, Vector3(0.46, 0.22, 0.012), Vector3(-0.22, 0.75, 0.685), grey)
	face.rotation.x = -0.25
	Build.cyl(self, 0.024, 0.016, Vector3(-0.08, 0.77, 0.7), yellow, Build.AXIS_Z)
	Build.cyl(self, 0.016, 0.03, Vector3(-0.08, 0.77, 0.71), Build.emissive(Color(0.9, 0.08, 0.05), 0.5), Build.AXIS_Z)
	Build.cyl(self, 0.013, 0.03, Vector3(-0.2, 0.77, 0.7), black, Build.AXIS_Z)
	Build.cyl(self, 0.013, 0.03, Vector3(-0.3, 0.77, 0.7), black, Build.AXIS_Z)
	_lamp_mat = Build.emissive(Color(0.15, 0.9, 0.25), 0.15)
	Build.cyl(self, 0.01, 0.02, Vector3(-0.38, 0.77, 0.695), _lamp_mat, Build.AXIS_Z)

	# Schraubstock: fester Backen hinten, beweglicher vorne, Spindel und Handrad
	Build.box(self, Vector3(0.12, 0.14, 0.03), Vector3(-0.09, 0.95, -0.2), dark_steel)
	Build.box(self, Vector3(0.12, 0.2, 0.05), Vector3(-0.09, 0.96, -0.24), blue)
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, 0, 0.065)
	add_child(_jaw)
	Build.box(_jaw, Vector3(0.12, 0.14, 0.03), Vector3(-0.09, 0.95, 0.0), dark_steel)
	Build.cyl(self, 0.012, 0.42, Vector3(-0.09, 0.93, 0.32), zinc, Build.AXIS_Z)
	Build.cyl(self, 0.085, 0.022, Vector3(-0.09, 0.93, 0.53), black, Build.AXIS_Z)
	Build.cyl(self, 0.011, 0.07, Vector3(-0.15, 0.93, 0.565), black, Build.AXIS_Z)

	# Längenanschlag: Stange an der hinteren Schiene, Reiter fährt auf das eingestellte Maß
	Build.cyl(self, 0.01, TABLE_END - 0.05, Vector3((TABLE_END + 0.05) * 0.5, 0.96, -0.31), black, Build.AXIS_X)
	_stop = Node3D.new()
	add_child(_stop)
	Build.box(_stop, Vector3(0.05, 0.06, 0.06), Vector3(0.025, 0.96, -0.31), black)
	Build.box(_stop, Vector3(0.012, 0.09, 0.3), Vector3(0.0, 0.955, -0.14), black)
	Build.cyl(_stop, 0.012, 0.06, Vector3(0.05, 1.0, -0.31), black)

	_build_arm(grey, black, dark_steel, zinc, yellow)

	var hit := Build.collider(self, Vector3(4.4, 1.4, 1.3), Vector3(0, 0.7, 0.05))
	hit.set_meta("interact", self)
	_stock_node = Node3D.new()
	add_child(_stock_node)


## Sägebügel, drehbar um das Gelenk hinten. Band läuft unten in Querrichtung über den Stangenquerschnitt.
func _build_arm(grey: Material, black: Material, dark_steel: Material, zinc: Material, yellow: Material) -> void:
	_arm = Node3D.new()
	_arm.position = Vector3(0, 0.9, -0.42)
	_arm.rotation.x = ARM_REST
	add_child(_arm)
	# Gelenk
	Build.box(self, Vector3(0.22, 0.12, 0.12), Vector3(0, 0.88, -0.42), Build.mat(Color(0.27, 0.46, 0.72), 0.5, 0.15))
	Build.cyl(_arm, 0.035, 0.26, Vector3.ZERO, zinc, Build.AXIS_X)
	# Rücken und die beiden Radgehäuse
	Build.box(_arm, Vector3(0.11, 0.13, 0.92), Vector3(0, 0.3, 0.46), grey)
	Build.cyl(_arm, 0.17, 0.09, Vector3(0, 0.14, 0.04), grey, Build.AXIS_X)
	Build.cyl(_arm, 0.17, 0.09, Vector3(0, 0.14, 0.88), grey, Build.AXIS_X)
	# Führungsarme mit Bandführung, gelbe Schutzteile
	for z in [0.2, 0.72]:
		Build.box(_arm, Vector3(0.05, 0.26, 0.06), Vector3(0, 0.1, z), dark_steel)
		Build.box(_arm, Vector3(0.06, 0.05, 0.08), Vector3(0, -0.005, z), yellow)
	# Sägeband
	Build.box(_arm, Vector3(0.004, 0.024, 0.86), Vector3(0, -0.03, 0.46), Build.mat(Color(0.16, 0.16, 0.17), 0.35, 0.9))
	# Getriebe und Motor am hinteren Rad
	Build.box(_arm, Vector3(0.2, 0.22, 0.22), Vector3(0.14, 0.16, 0.04), Build.mat(Color(0.72, 0.74, 0.74), 0.5, 0.2))
	Build.cyl(_arm, 0.1, 0.28, Vector3(0.38, 0.16, 0.04), Build.mat(Color(0.8, 0.81, 0.81), 0.5, 0.2), Build.AXIS_X)
	Build.cyl(_arm, 0.085, 0.05, Vector3(0.55, 0.16, 0.04), Build.mat(Color(0.3, 0.31, 0.32), 0.6), Build.AXIS_X)
	# Griff und Sterngriff für die Bandspannung vorne
	Build.cyl(_arm, 0.014, 0.2, Vector3(0, 0.3, 1.0), zinc, Build.AXIS_Z)
	Build.cyl(_arm, 0.018, 0.12, Vector3(0, 0.3, 1.1), black, Build.AXIS_Z)
	for a in [0.0, PI / 2.0]:
		Build.box(_arm, Vector3(0.16, 0.02, 0.02), Vector3(0, 0.3, 1.16), black, false, Vector3(0, 0, a))
	# Hinweisschilder
	var sticker := Build.mat(Color(0.1, 0.25, 0.6), 0.5)
	for i in 3:
		Build.cyl(_arm, 0.016, 0.004, Vector3(0.057, 0.31, 0.74 + i * 0.05), sticker, Build.AXIS_X)
	Build.label(_arm, "BS 275", Vector3(0.057, 0.3, 0.42), 0.0022, Color(0.12, 0.12, 0.14), 48, PI / 2.0)


## Rollbahn von x0 bis x1 mit Seitenschienen, Rollen und zwei Beinpaaren.
func _table(x0: float, x1: float, blue: Material, zinc: Material) -> void:
	var span := x1 - x0
	var mid := (x0 + x1) * 0.5
	var y := ROLL_TOP - ROLL_R
	for z in [-0.27, 0.27]:
		Build.box(self, Vector3(span, 0.08, 0.025), Vector3(mid, y - 0.005, z), blue)
	var n := int(span / 0.27)
	for i in n:
		Build.cyl(self, ROLL_R, 0.52, Vector3(x0 + (i + 0.5) * span / n, y, 0), zinc, Build.AXIS_Z)
	for x in [x0 + 0.3, x1 - 0.2]:
		for z in [-0.25, 0.25]:
			_leg(self, Vector3(x, 0, z), y - 0.05, blue, zinc)
		Build.box(self, Vector3(0.04, 0.04, 0.5), Vector3(x, 0.32, 0), blue)


## Bein mit blauer Hülse, verzinktem Rohr und Fußteller.
func _leg(parent: Node3D, base: Vector3, top: float, blue: Material, zinc: Material) -> void:
	var split := top * 0.5
	Build.box(parent, Vector3(0.06, top - split, 0.06), base + Vector3(0, (top + split) * 0.5, 0), blue)
	Build.cyl(parent, 0.022, split, base + Vector3(0, split * 0.5, 0), zinc)
	Build.cyl(parent, 0.055, 0.012, base + Vector3(0, 0.006, 0), zinc)
