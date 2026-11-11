class_name CncMill
extends Mill
## CNC-Fräsmaschine (Bearbeitungszentrum) mit Kabinentür, Bedienpult, Werkzeugmagazin und NC-Kanal.
## Basis ist Mill (Werkstück als Höhenkarte, Zerspanung, Verschleiß, Prüfung, Spänewanne, KSS).
## Modell: CncMillModel (models/cncmill.glb). Koordinaten wie bei Mill: tool_x/y/z in mm, Ursprung vordere linke Ecke
## der Rohteil-Oberseite, X rechts, Y nach hinten, Z = 0 rohe Oberseite, gesteuerter Punkt = Werkzeugspitze.
## Der Ursprung der Maschine liegt auf der Spindelachse am Boden. +Z (lokal) ist die Bedienerseite.
##
## Öffentliche Schnittstelle (zusätzlich zu Mill)
##  Konstanten  POCKETS (24 Magazinplätze), SCREEN_UI (768 x 600 logische Pixel des Pult-Bildschirms), BOOT_TIME,
##              FOOT (Grundfläche lokal als Rect2: x/z inkl. Pult und Förderer), STAND_WORK / STAND_PULT (Standplätze lokal)
##  Ein/Aus     powered, booting, is_ready(), power_on(instant := false), power_off(), power_hint(); Signal power_changed(on)
##              Ohne Strom: keine Bewegung (move_tool wirkungslos), Spindel/NC gesperrt, Bildschirm dunkel
##  Tür         door_closed(), door_open_ok(), set_door(closed: bool, instant := false) -> bool, toggle_door();
##              Signal door_changed(closed). Geht nicht auf bei drehender Spindel, laufendem Programm oder Werkzeugwechsel.
##              clamp_blocked() -> String: Fehlertext, solange das Teil nicht ein-/ausgespannt werden darf (Tür zu), "" = erlaubt
##  Bezugspunkt datum: Vector3, pos() (Programmkoordinaten = Maschine - Bezugspunkt), machine_pos(), set_datum(axis, value),
##              limits() -> {"min", "max"} Verfahrbereich in Programmkoordinaten
##  Spindel     set_rpm(v), set_feed(v) stufenlos (rpm_set, feed_set), toggle_spindle(), toggle_coolant()
##  Magazin     magazine: Array[String] (Index i = Platz T(i+1), "" = frei), tool_t (T-Nummer in der Spindel, 0 = leer),
##              magazine_set(t, id) -> bool, magazine_clear(t), pocket_of(id) -> int (T oder 0), free_pocket() -> int,
##              magazine_tools() -> Dictionary (T -> Werkzeug), has_tool(id) (Spindel oder Magazin),
##              tool_change(t) -> String ("" = Wechsel gestartet, sonst Fehlertext), changing (läuft gerade),
##              change_progress() -> float 0..1, Signal tool_changed(t)
##              Per Hand (Linksklick am Spindelwerkzeug, Tür offen) belegt das Werkzeug den Platz der aktiven T-Nummer,
##              sonst den ersten freien; Herausnehmen von Hand oder Bruch (tool_lost) gibt den Platz frei.
##  NC          channel: MillChannel (state, nc_start, nc_stop, reset, line, ops, ...), programs: Array aus
##              {"name", "lines": Array[String]}, prog_sel (Index in programs, -1 = keins), selected_program(),
##              program(name), save_program(name, lines), delete_program(name), nc_start(), nc_stop(), nc_reset(),
##              mdi(line) -> bool (einzelner Klartext-Satz), nc_context() (Kontext für MillNc.compile)
##  Pult        screen: TncScreen (Steuerung), screen_vp (SubViewport), screen_pixel(mouse), push_screen_event(ev, px),
##              typing(), set_view("panel"), toggle_panel_view(), in_panel_view(), interact(p, panel := false),
##              Signal view_changed(panel)
##  Zustand     get_state()/set_state(): zusätzlich Magazin, tool_t, Bezugspunkt, Programme, prog_sel, Tür, powered.
##              Nach dem Laden läuft kein Programm.

signal door_changed(closed: bool)
signal power_changed(on: bool)
signal tool_changed(t: int)
signal view_changed(panel: bool)

const POCKETS := CncMillModel.POCKETS
const SCREEN_UI := Vector2(768, 600)
const SCREEN_SCALE := 2.0
const BOOT_TIME := 3.0
const DOOR_TIME := 1.3
const DOOR_LAYER := CncMillModel.DOOR_LAYER
const OFS := CncMillModel.OFS
const NOSE_CHG := CncMillModel.NOSE_Y + OFS.y          # Spindelnase beim Werkzeugwechsel (m über Boden)
const HEAD_TOP_NOSE := 2.14                             # höchste Lage der Spindelnase (m)
const MAG_TOOL_LEN := 0.22                              # Werkzeuge im Magazin werden auf diese Länge begrenzt (m)
const CNC_X_TRAVEL := 500.0
const CNC_Y_TRAVEL := 240.0
const CNC_Z_MAX := 380.0
const CNC_Z_MIN := -100.0
const TC_Y_HOLD := -0.03                                # Wechslerarm beim Greifen (m relativ zur Ruhelage)
const TC_Y_PULL := -0.09                                # Werkzeug herausgezogen
const GRIP_UP := 0.06                                   # Kegelende über Unterkante des Greifers
const SHUTTLE := Vector3(0.405, 0.0, 0.025)             # Weg des Wechslers zur Spindel (Modell, m)
const FOOT := Rect2(-2.6, -1.25, 4.95, 3.45)            # lokal: x -2.6 .. 2.35, z -1.25 .. 2.2
const STAND_WORK := Vector3(0.25, 0.0, 1.8)
const STAND_PULT := Vector3(0.78, 0.0, 1.95)
const PULT_YAW := -1.0384                               # Blickrichtung zum Bildschirm (rad)
const TC_PHASES := [["a", 0.9], ["b", 0.4], ["c", 0.6], ["d", 0.3], ["e", 0.7], ["f", 0.3], ["g", 0.6], ["h", 0.4], ["i", 0.4]]

var powered := false
var booting := 0.0
var door_t := 1.0                       # 1 = Tür zu, 0 = ganz offen
var _door_goal := 1.0
var datum := Vector3.ZERO
var magazine: Array[String] = []
var tool_t := 0
var changing := false
var channel: MillChannel
var programs: Array = []
var prog_sel := -1
var screen: Control
var screen_vp: SubViewport
var _model: CncMillModel
var _mp: Dictionary = {}
var _screen_mi: MeshInstance3D
var _screen_size := Vector2(0.484, 0.379)
var _screen_drag := false
var _vp_idle_t := 0.0             # bis zum nächsten Bild des Bildschirms, solange niemand die Maschine bedient
var _panel_view := false
var _pre_panel: Array = []
var _boot_overlay: Control
var _boot_info: Control
var _boot_bar: ProgressBar
var _pocket_nodes: Array = []
var _pocket_ids: Array[String] = []
var _internal := false
var _tc: Dictionary = {}
var _cabin_box := AABB()
var _door_body: StaticBody3D
var _handle_body: StaticBody3D
var _handle_box := AABB()
var _zones: Array = []
var _lamp_light: SpotLight3D
var _disk_angle := 0.0
var _arm_theta := 0.0
var _arm_x := 0.0
var _arm_y := 0.0


func _init() -> void:
	MACHINE_ID = "cnc_mill"
	tool_family = "mill"
	top_y = CncMillModel.TABLE_TOP + OFS.y + 0.11
	table_y = CncMillModel.TABLE_TOP + OFS.y
	vise_l = 0.2
	x_travel = CNC_X_TRAVEL
	y_travel = CNC_Y_TRAVEL
	z_max = CNC_Z_MAX
	z_min = CNC_Z_MIN
	op_stand = STAND_WORK
	rpm_set = 1000.0
	feed_set = 300.0
	magazine.resize(POCKETS)
	magazine.fill("")
	_pocket_ids.resize(POCKETS)
	_pocket_ids.fill("")
	_pocket_nodes.resize(POCKETS)
	channel = MillChannel.new(self)


# ======================================================================= Aufbau

func _build_model() -> Dictionary:
	_model = CncMillModel.new()
	_mp = _model.build(self)
	var table: Node3D = _mp["table"]
	var vise := Node3D.new()
	vise.name = "Schraubstock"
	table.add_child(vise)
	var dark := Build.mat(Color(0.10, 0.11, 0.13), 0.5, 0.4)
	var steel := Build.mat(Color(0.62, 0.64, 0.68), 0.35, 0.8)
	Build.box(vise, Vector3(0.20, 0.034, 0.34), Vector3(0, 0.017, 0.0), dark)
	Build.box(vise, Vector3(0.18, 0.012, 0.05), Vector3(0, 0.04, 0.17 + 0.02), steel)
	Build.cyl(vise, 0.012, 0.16, Vector3(0, 0.045, 0.25), steel, Build.AXIS_Z, false, 12)
	Build.cyl(vise, 0.008, 0.10, Vector3(0, 0.045, 0.34), steel, Build.AXIS_X, false, 10)
	# Hilfsknoten für Mills Gerüst: Handräder, Anzeige, Lampe gibt es hier nicht als Bauteile
	var screen_lbl := Label3D.new()
	var led := MeshInstance3D.new()
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0.45, 2.45, 0.7) - OFS
	lamp.look_at_from_position(lamp.position, Vector3(0.0, 1.45, 0.0) - OFS, Vector3.UP)
	lamp.light_energy = 0.9
	lamp.spot_range = 2.6
	lamp.spot_angle = 65.0
	lamp.light_color = Color(1.0, 0.97, 0.92)
	lamp.visible = false
	(_mp["mroot"] as Node3D).add_child(lamp)
	_lamp_light = lamp
	return {"saddle": _mp["saddle"], "table": table, "vise": vise, "head": _mp["head"], "spindle": _mp["spindle"],
		"hw_x": Node3D.new(), "hw_y": Node3D.new(), "hw_z": Node3D.new(), "screen": screen_lbl, "led": led, "lamp": lamp,
		"panel": Node3D.new(), "dials": []}


func rpm_dial() -> Array:
	return [[100, 500, 1000, 2000, 3000, 5000], [200, 800, 1500, 2500, 4000, 10000]]


func feed_dial() -> Array:
	return [[10, 50, 100, 300, 600, 1000], [20, 100, 200, 500, 800, 2000]]


func machine_title() -> String:
	return "CNC-Fräsmaschine"


func head_title() -> String:
	return "Fräskopf"


func default_tool_index() -> int:
	return 0


func _ready() -> void:
	super()
	# Mills Platzhalter-Knoten (Hebel-Station, Anzeige, LED) hängen nicht im Baum, nur das Pult zählt hier
	_cabin_box = AABB(Vector3(-1.26, -0.03, -1.18) + OFS, Vector3(2.81, 2.62, 2.48)).grow(-0.03)
	_build_pult_ui()
	_build_screen()
	clear_spindle()
	tool_t = 0
	_load_samples()
	_place_door()
	_apply_power()
	_sync_axes()
	_update_limits()
	_disk_pose(0.0)
	_arm_pose()


func _load_samples() -> void:
	if not programs.is_empty():
		return
	for s in MillNc.samples():
		programs.append({"name": str(s["name"]), "lines": (s["lines"] as Array).duplicate()})
	prog_sel = 0 if not programs.is_empty() else -1


## Kollisionskörper: Kabine, Sockel, Tür (nur zu), Griff, Pult, Förderer.
func _build_colliders() -> void:
	var boxes := [
		# linke Kabinenseite samt festem Frontblech
		[Vector3(-1.26, 0.0, -1.18), Vector3(-0.25, 2.6, 1.15)],
		# Rückseite mit Säule und Magazin
		[Vector3(-0.25, 0.0, -1.18), Vector3(1.55, 3.1, -0.3)],
		# rechte Seite und festes Frontblech rechts der Tür
		[Vector3(1.05, 0.0, -0.3), Vector3(1.55, 2.6, 1.3)],
		# Sockel unter dem Arbeitsraum
		[Vector3(-0.25, 0.0, -0.3), Vector3(1.05, 1.1, 1.15)],
		# Späneförderer links
		[Vector3(-2.45, 0.0, -0.27), Vector3(-1.26, 1.0, 0.23)],
	]
	for b in boxes:
		var lo: Vector3 = (b[0] as Vector3) + OFS
		var hi: Vector3 = (b[1] as Vector3) + OFS
		Build.collider(self, hi - lo, (lo + hi) * 0.5).set_meta("interact", self)
	# Tür: fährt mit
	var dlo := Vector3(-0.26, 0.0, 1.15) + OFS
	var dhi := Vector3(1.05, 2.6, 1.30) + OFS
	_door_body = Build.collider(self, dhi - dlo, (dlo + dhi) * 0.5)
	_door_body.set_meta("interact", DoorTarget.make(self, false))
	var hb := _mp["handle"] as AABB
	_handle_box = AABB(hb.position + OFS - Vector3(0.03, 0.03, 0.0), hb.size + Vector3(0.06, 0.06, 0.04))
	_handle_body = Build.collider(self, _handle_box.size, _handle_box.get_center())
	_handle_body.set_meta("interact", DoorTarget.make(self, true))


## Knöpfe am Pult (Ein, Not-Halt) und die Klickfläche des Pults.
func _build_pult_ui() -> void:
	var mroot: Node3D = _mp["mroot"]
	var sxf: Transform3D = _mp["screen_xf"]
	_screen_size = _mp["screen_size"]
	var ui := Node3D.new()
	ui.name = "PultKnoepfe"
	ui.transform = sxf
	mroot.add_child(ui)
	var green := Build.mat(Color(0.1, 0.55, 0.2), 0.4)
	var red := Build.mat(Color(0.8, 0.08, 0.06), 0.35)
	var base := Build.mat(Color(0.05, 0.05, 0.06), 0.6)
	var hx := _screen_size.x * 0.5
	var gp := Vector3(-hx - 0.042, 0.055, 0.0)
	var rp := Vector3(-hx - 0.042, -0.015, 0.0)
	Build.box(ui, Vector3(0.085, 0.145, 0.012), Vector3(-hx - 0.0425 - 0.004, 0.02, -0.004), Build.mat(Color(0.08, 0.08, 0.1), 0.5))
	var g := Build.cyl(ui, 0.020, 0.024, gp + Vector3(0, 0, 0.012), green, Build.AXIS_Z, false, 20)
	Build.cyl(ui, 0.026, 0.008, gp + Vector3(0, 0, 0.004), base, Build.AXIS_Z, false, 20)
	Build.cyl(ui, 0.026, 0.008, rp + Vector3(0, 0, 0.004), base, Build.AXIS_Z, false, 20)
	Build.cyl(ui, 0.022, 0.030, rp + Vector3(0, 0, 0.018), red, Build.AXIS_Z, false, 20)
	g.name = "Einschalter"
	# Klickflächen in Maschinenkoordinaten (Mittelpunkt, Halbmaß)
	for z in [["power", gp], ["estop", rp]]:
		var c := (sxf * (z[1] as Vector3)) + OFS
		_zones.append({"name": z[0], "box": AABB(c - Vector3.ONE * 0.04, Vector3.ONE * 0.08)})
		var body := Build.collider(self, Vector3(0.07, 0.07, 0.07), c)
		body.set_meta("interact", PultTarget.make(self, str(z[0])))
	# Pult: Monitor und Tastatur. Die Klickfläche spart die Knopfleiste links aus, sonst fängt sie den
	# Blick auf den grünen Knopf ab und der Ein-Knopf wäre nicht erreichbar.
	var pc := (sxf * Vector3(0.02, -0.1, 0.05)) + OFS
	var body_p := Build.collider(self, Vector3(_screen_size.x, 0.62, 0.3), pc)
	body_p.rotation.y = atan2(sxf.basis.z.x, sxf.basis.z.z)
	body_p.set_meta("interact", PultTarget.make(self, "pult"))
	_zones.append({"name": "pult", "box": AABB(pc - Vector3(0.3, 0.3, 0.3), Vector3(0.6, 0.6, 0.6))})


func _build_screen() -> void:
	screen_vp = SubViewport.new()
	screen_vp.size = Vector2i(SCREEN_UI * SCREEN_SCALE)
	screen_vp.transparent_bg = false
	screen_vp.gui_embed_subwindows = true
	screen_vp.handle_input_locally = true
	screen_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(screen_vp)
	screen = load("res://scripts/ui/tnc_screen.gd").new()
	screen.set("mill", self)
	screen.size = SCREEN_UI
	screen.scale = Vector2.ONE * SCREEN_SCALE
	screen_vp.add_child(screen)
	_build_boot_overlay()
	var quad := QuadMesh.new()
	quad.size = _screen_size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = screen_vp.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material = m
	_screen_mi = MeshInstance3D.new()
	_screen_mi.mesh = quad
	_screen_mi.name = "Bildschirm"
	var sxf: Transform3D = _mp["screen_xf"]
	_screen_mi.transform = Transform3D(sxf.basis, sxf.origin + sxf.basis.z * 0.0015)
	_screen_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_mp["mroot"] as Node3D).add_child(_screen_mi)


func _build_boot_overlay() -> void:
	_boot_overlay = ColorRect.new()
	(_boot_overlay as ColorRect).color = Color(0.0, 0.0, 0.0)
	_boot_overlay.size = SCREEN_UI
	_boot_overlay.scale = Vector2.ONE * SCREEN_SCALE
	screen_vp.add_child(_boot_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boot_overlay.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(SCREEN_UI.x * 0.5, 0)
	center.add_child(v)
	_boot_info = v
	var logo := Label.new()
	logo.text = "TNC 640"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_font_size_override("font_size", 40)
	logo.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	v.add_child(logo)
	var l := Label.new()
	l.text = "Steuerung startet ..."
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	v.add_child(l)
	_boot_bar = ProgressBar.new()
	_boot_bar.max_value = 1.0
	_boot_bar.show_percentage = false
	_boot_bar.custom_minimum_size = Vector2(0, 10)
	v.add_child(_boot_bar)


# ======================================================================= Ein / Aus

func is_ready() -> bool:
	return powered and booting <= 0.0


func power_hint() -> String:
	if powered:
		return "%s fährt hoch ..." % machine_title()
	return "%s ist aus - grüner Knopf am Bedienpult: [%s] hochfahren" % [machine_title(), Settings.binding_text("interact")]


func power_on(instant := false) -> void:
	if powered:
		return
	powered = true
	booting = 0.0 if instant else BOOT_TIME
	_apply_power()
	power_changed.emit(true)
	if not instant:
		_info("%s fährt hoch ..." % machine_title())


func power_off() -> void:
	if not powered:
		return
	if changing:
		_tc_finish()
	stop_operating()
	channel.reset()
	spindle_on = false
	coolant = false
	auto_axis = -1
	estop = false
	powered = false
	booting = 0.0
	_apply_power()
	power_changed.emit(false)
	_info("%s heruntergefahren." % machine_title())


func _apply_power() -> void:
	if _lamp_light:
		_lamp_light.visible = powered
	if screen_vp == null:
		return
	var up := is_ready()
	screen.visible = up
	screen.process_mode = Node.PROCESS_MODE_INHERIT if up else Node.PROCESS_MODE_DISABLED
	_boot_overlay.visible = not up
	_boot_info.visible = powered and not up
	_boot_bar.value = 0.0
	screen_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _update_screen(delta: float) -> void:
	if screen_vp == null or not powered:
		return
	if booting > 0.0:
		_boot_bar.value = 1.0 - booting / BOOT_TIME
		screen_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	if operating or _panel_view:
		screen_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	# Niemand bedient die Maschine: ein Bild alle 0,25 s reicht für den Blick im Vorbeigehen
	_vp_idle_t -= delta
	if _vp_idle_t <= 0.0:
		_vp_idle_t = 0.25
		screen_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


# ======================================================================= Tür

func door_closed() -> bool:
	return _door_goal >= 1.0 and door_t >= 0.999


## Tür ganz offen (Werkstück spannen, Werkzeug von Hand setzen)?
func door_open_ok() -> bool:
	return _door_goal <= 0.0 and door_t <= 0.001


## Sperre für Teilwechsel (einspannen, ausspannen, abgeben, neues Rohteil): Tür muss offen sein und es
## darf kein Programm mehr anstehen. Im NC-Halt bleibt nur das Umspannen (_clamp_gate) erlaubt.
func clamp_blocked() -> String:
	if channel != null and channel.busy():
		return "Programm ist noch aktiv: erst mit RESET (Interner Stopp) am Pult beenden."
	if changing:
		return "Werkzeugwechsel läuft noch."
	return _clamp_gate()


func request_new_part() -> void:
	var why := clamp_blocked()
	if why != "":
		_warn(why)
		return
	super()


func request_submit() -> void:
	var why := clamp_blocked()
	if why != "":
		_warn(why)
		return
	super()


func _clamp_gate() -> String:
	return "" if door_open_ok() else "Erst die Kabinentür öffnen."


## Tür zu/auf. instant: ohne Fahrt (Laden, Tests). Gibt false zurück, wenn die Verriegelung das Öffnen verhindert.
func set_door(closed: bool, instant := false) -> bool:
	if not closed:
		if spindle_on or spindle_speed > 5.0:
			_warn("Kabinentür gesperrt: Spindel dreht noch.")
			return false
		if channel.state == "run":
			_warn("Kabinentür gesperrt: Programm läuft - erst NC-Stopp.")
			return false
		if changing:
			_warn("Kabinentür gesperrt: Werkzeugwechsel läuft.")
			return false
	elif changing:
		return false
	var was := door_closed()
	_door_goal = 1.0 if closed else 0.0
	if instant:
		door_t = _door_goal
		_place_door()
	if was != door_closed() or not instant:
		door_changed.emit(closed)
	return true


func toggle_door() -> void:
	set_door(_door_goal <= 0.0)


func _door_step(delta: float) -> void:
	if not is_equal_approx(door_t, _door_goal):
		door_t = move_toward(door_t, _door_goal, delta / DOOR_TIME)
		_place_door()


func _place_door() -> void:
	if _mp.is_empty():
		return
	var off := -CncMillModel.DOOR_TRAVEL * (1.0 - door_t)
	(_mp["door"] as Node3D).position.x = off
	if _door_body:
		var dlo := Vector3(-0.26, 0.0, 1.15) + OFS
		var dhi := Vector3(1.05, 2.6, 1.30) + OFS
		_door_body.position = (dlo + dhi) * 0.5 + Vector3(off, 0, 0)
	if _handle_body:
		_handle_body.position = _handle_box.get_center() + Vector3(off, 0, 0)


# ======================================================================= Bezugspunkt und Achsen

func pos() -> Vector3:
	return Vector3(tool_x, tool_y, tool_z) - datum


func machine_pos() -> Vector3:
	return Vector3(tool_x, tool_y, tool_z)


## Anzeige der Achse (0 X, 1 Y, 2 Z) auf value setzen: Der Bezugspunkt liegt dann an der aktuellen Lage.
func set_datum(axis: int, value: float) -> void:
	if channel != null and channel.busy():
		return      # ein laufendes Programm rechnet mit dem Bezugspunkt vom Start
	datum[axis] = machine_pos()[axis] - value


func limits() -> Dictionary:
	var lo := Vector3(block_l * 0.5 - x_travel * 0.5, block_w * 0.5 - y_travel * 0.5, z_min) - datum
	var hi := Vector3(block_l * 0.5 + x_travel * 0.5, block_w * 0.5 + y_travel * 0.5, z_max) - datum
	return {"min": lo, "max": hi}


func new_workpiece(length: float, width: float, height: float) -> void:
	datum = Vector3.ZERO
	super(length, width, height)


func move_tool(dx: float, dy: float, dz: float, speed: float) -> void:
	if not is_ready():
		return
	super(dx, dy, dz, speed)


## Obere Grenze der Z-Achse hängt von der Werkzeuglänge ab: Die Spindelnase darf nicht über das Ende der Führung.
func _update_limits() -> void:
	z_max = minf(CNC_Z_MAX, (HEAD_TOP_NOSE - top_y) * 1000.0 - MillTools.tool_length(tool()))


## Tischweg, Schlittenweg und Kopfhöhe in den Modellknoten (Modellkoordinaten, m).
func _sync_axes() -> void:
	if _mp.is_empty():
		return
	(_mp["saddle"] as Node3D).position.z = CncMillModel.SADDLE_MID + (tool_y - block_w * 0.5) * 0.001
	(_mp["table"] as Node3D).position.x = CncMillModel.TABLE_ORIGIN_X + CncMillModel.TABLE_MID - (tool_x - block_l * 0.5) * 0.001
	var nose := top_y + (tool_z + MillTools.tool_length(tool())) * 0.001
	head.position.y = nose - OFS.y
	var tip_y := top_y + tool_z * 0.001
	chips.position = Vector3(0, tip_y + 0.002, 0)
	coolant_fx.position = Vector3(-0.05, tip_y + 0.08, 0.05)


func chip_position() -> Vector3:
	var x := randf_range(-0.8, 1.0)
	var z := randf_range(-1.0, -0.45) if randf() < 0.6 else randf_range(0.5, 0.85)
	return Vector3(x, 0.83 + randf() * 0.006, z)


# ======================================================================= Spindel, Vorschub

func set_rpm(v: float) -> void:
	rpm_set = clampf(v, 10.0, MillNc.S_MAX)


func set_feed(v: float) -> void:
	feed_set = clampf(v, 1.0, 20000.0)


func _manual_ok() -> bool:
	return is_ready() and not channel.busy() and not changing and not typing()


func toggle_spindle() -> void:
	if not is_ready():
		_warn(power_hint())
		return
	if not spindle_on:
		if not door_closed():
			_warn("Spindel gesperrt: Kabinentür offen.")
			return
		if changing:
			_warn("Spindel gesperrt: Werkzeugwechsel läuft.")
			return
		if spindle_empty:
			_warn("Spindel gesperrt: kein Werkzeug eingesetzt.")
			return
	elif channel.state == "run":
		_warn("Programm läuft - erst NC-Stopp.")
		return
	super()


func _handwheel_turn(notches: float) -> void:
	if _panel_view:
		return
	if not _manual_ok():
		if channel.busy():
			_warn("Automatikbetrieb - erst RESET am Pult.")
		return
	super(notches)


## Wird am Pult gerade in ein Eingabefeld geschrieben?
func typing() -> bool:
	return screen_vp != null and screen_vp.gui_get_focus_owner() is LineEdit


# ======================================================================= Magazin

func pocket_of(id: String) -> int:
	if id == "":
		return 0
	for i in POCKETS:
		if magazine[i] == id:
			return i + 1
	return 0


func free_pocket() -> int:
	for i in POCKETS:
		if magazine[i] == "":
			return i + 1
	return 0


## Werkzeug id auf Platz T (1..POCKETS) legen (Test, Laden, Voreinstellung). Ein Werkzeug gibt es nur einmal im Magazin.
func magazine_set(t: int, id: String) -> bool:
	if changing or t < 1 or t > POCKETS or tool_index(id) < 0:
		return false
	var p := pocket_of(id)
	if p > 0 and p != t:
		return false
	if t == tool_t and not spindle_empty:
		return false
	magazine[t - 1] = id
	_refresh_pockets()
	return true


func magazine_clear(t: int) -> void:
	if changing or t < 1 or t > POCKETS or (t == tool_t and not spindle_empty):
		return
	magazine[t - 1] = ""
	_refresh_pockets()


## T-Nummer -> Werkzeug-Dictionary (MillTools.TOOLS) aller bestückten Plätze, auch des Spindelwerkzeugs.
func magazine_tools() -> Dictionary:
	var out := {}
	for i in POCKETS:
		if magazine[i] != "":
			out[i + 1] = MillTools.by_id(magazine[i])
	return out


func has_tool(id: String) -> bool:
	return pocket_of(id) > 0 or super(id)


func nc_context() -> Dictionary:
	return {"tools": magazine_tools(), "pos": pos(), "t": tool_t if not spindle_empty else 0, "s": rpm_set, "limits": limits()}


func hand_prompt(held: Dictionary) -> String:
	if not door_open_ok() and (not held.is_empty() or not spindle_empty):
		return "Kabinentür öffnen, um das Spindelwerkzeug zu wechseln"
	return super(held)


func _hand_gate() -> String:
	if changing:
		return "Werkzeugwechsel läuft."
	if channel.busy():
		return "Programm läuft - erst RESET."
	if not door_open_ok():
		return "Erst die Kabinentür öffnen, dann das Werkzeug von Hand wechseln."
	return ""


func hand_click(p: Node) -> void:
	var why := _hand_gate()
	if why != "":
		_warn(why)
		return
	super(p)


func select_tool(i: int, silent := false) -> void:
	if _internal:
		super(i, silent)
		return
	i = clampi(i, 0, MillTools.TOOLS.size() - 1)
	var id := str(MillTools.TOOLS[i]["id"])
	var at := pocket_of(id)
	var slot := tool_t
	if at > 0 and tool_t > 0 and at != tool_t:
		_warn("%s steckt schon im Magazin (T%d)." % [tool_name(id), at])
		return
	if slot == 0:
		slot = at if at > 0 else free_pocket()
		if slot == 0:
			_warn("Magazin voll: erst ein Werkzeug herausnehmen.")
			return
	super(i, silent)
	if spindle_empty or tool_idx != i:
		return
	magazine[slot - 1] = id
	tool_t = slot
	_update_limits()
	_refresh_pockets()
	tool_changed.emit(tool_t)


## Spindel leeren (von Hand entnommen, Bruch): gibt den Platz der aktiven T-Nummer frei.
func clear_spindle() -> void:
	if tool_t > 0:
		magazine[tool_t - 1] = ""
		tool_t = 0
	super()
	_refresh_pockets()
	if is_inside_tree():
		tool_changed.emit(0)


## Anzeige der Werkzeuge in den Aufnahmen der Scheibe.
func _refresh_pockets() -> void:
	if _mp.is_empty():
		return
	var anchors: Array = _mp["anchors"]
	for i in POCKETS:
		var id := magazine[i]
		var want := id != "" and not (i + 1 == tool_t and not spindle_empty)
		if _pocket_ids[i] != id:
			if _pocket_nodes[i] != null:
				(_pocket_nodes[i] as Node).queue_free()
				_pocket_nodes[i] = null
			_pocket_ids[i] = id
			if id != "":
				var n := make_tool_model(id)
				(anchors[i] as Node3D).add_child(n)
				_pocket_nodes[i] = n
				n.transform = _pocket_xf(id, 1.0)
		if _pocket_nodes[i] != null:
			(_pocket_nodes[i] as Node3D).visible = want


func _tool_len(id: String) -> float:
	return MillTools.tool_length(MillTools.by_id(id)) * 0.001


## Darstellung im Magazin: Länge begrenzt, Maßstab s = 1 ist die volle Größe.
func _mag_scale(id: String) -> float:
	return minf(1.0, MAG_TOOL_LEN / maxf(_tool_len(id), 0.001))


## Lage eines Werkzeugmodells (Schneide = Ursprung) relativ zu seinem Kegelende-Rahmen. k = 1: Magazinmaßstab.
func _pocket_xf(id: String, k: float) -> Transform3D:
	var s := lerpf(1.0, _mag_scale(id), k)
	return _mount_xf(id, s)


func _mount_xf(id: String, s: float) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * 0.001 * s), Vector3(0, -_tool_len(id) * s, 0))


# ======================================================================= Werkzeugwechsel

func change_progress() -> float:
	if not changing:
		return 0.0
	var total := 0.0
	var done := 0.0
	for ph in TC_PHASES:
		total += float(ph[1])
	var cur := str(_tc["phase"])
	for ph in TC_PHASES:
		if str(ph[0]) == cur:
			done += float(_tc["t"])
			break
		done += float(ph[1])
	return clampf(done / total, 0.0, 1.0)


## Werkzeug T in die Spindel holen (0 = nur das Spindelwerkzeug ablegen). Fehlertext, "" = Wechsel läuft.
func tool_change(t: int) -> String:
	var err := ""
	if not is_ready():
		err = "Werkzeugwechsel nicht möglich: Steuerung ist aus."
	elif estop:
		err = "Werkzeugwechsel nicht möglich: Not-Halt aktiv."
	elif changing:
		err = "Werkzeugwechsel läuft schon."
	elif t < 0 or t > POCKETS:
		err = "T%d gibt es nicht (Magazin hat %d Plätze)." % [t, POCKETS]
	elif t > 0 and magazine[t - 1] == "":
		err = "T%d ist nicht bestückt." % t
	elif spindle_on or spindle_speed > 5.0:
		err = "Werkzeugwechsel nur bei stehender Spindel."
	elif not door_closed():
		err = "Werkzeugwechsel nur bei geschlossener Kabinentür."
	if err != "":
		_warn(err)
		return err
	if t == tool_t and not spindle_empty:
		return ""
	if t == 0 and spindle_empty:
		return ""
	auto_axis = -1
	changing = true
	var old_id := "" if spindle_empty else str(tool()["id"])
	var new_id := "" if t == 0 else magazine[t - 1]
	_tc = {"t_new": t, "t_old": tool_t if not spindle_empty else 0, "id_new": new_id, "id_old": old_id,
		"phase": "z", "t": 0.0, "n_new": null, "n_old": null, "th0": _disk_angle, "th_new": _disk_angle,
		"th_old": _disk_angle, "z_goal": (NOSE_CHG - top_y) * 1000.0 - MillTools.tool_length(tool())}
	if t > 0:
		_tc["th_new"] = _angle_of(t, _disk_angle)
	if _tc["t_old"] > 0:
		_tc["th_old"] = _angle_of(int(_tc["t_old"]), float(_tc["th_new"]))
	return ""


## Scheibenwinkel, mit dem Platz t unten steht (kürzester Weg von cur aus).
func _angle_of(t: int, cur: float) -> float:
	var target := (t - 1) * TAU / POCKETS
	return cur + wrapf(target - cur, -PI, PI)


func _tc_step(delta: float) -> void:
	if not changing:
		return
	if estop:
		_tc_finish()
		return
	var phase := str(_tc["phase"])
	if phase == "z":
		var dz := float(_tc["z_goal"]) - tool_z
		var step := MillNc.RAPID / 60.0 * delta
		if absf(dz) <= step:
			tool_z = float(_tc["z_goal"])
			_sync_axes()
			_tc["phase"] = "a"
			_tc["t"] = 0.0
			_tc_enter("a")
		else:
			move_tool(0.0, 0.0, signf(dz) * step, step / delta)
			if absf(float(_tc["z_goal"]) - tool_z) >= absf(dz) - 0.0001:
				# Z kommt nicht weiter (Anschlag): Wechsel abbrechen
				_tc_finish()
		return
	var dur := 0.0
	for ph in TC_PHASES:
		if str(ph[0]) == phase:
			dur = float(ph[1])
	_tc["t"] = float(_tc["t"]) + delta
	var u := clampf(float(_tc["t"]) / dur, 0.0, 1.0)
	_tc_pose(phase, u * u * (3.0 - 2.0 * u))
	if u >= 1.0:
		_tc_leave(phase)
		var idx := -1
		for k in TC_PHASES.size():
			if str(TC_PHASES[k][0]) == phase:
				idx = k
		if idx + 1 >= TC_PHASES.size():
			_tc_finish()
		else:
			var nxt := str(TC_PHASES[idx + 1][0])
			_tc["phase"] = nxt
			_tc["t"] = 0.0
			_tc_enter(nxt)


func _tc_enter(phase: String) -> void:
	match phase:
		"b":
			var t := int(_tc["t_new"])
			if t > 0:
				var n := _pocket_nodes[t - 1] as Node3D
				if n != null:
					n.get_parent().remove_child(n)
					(_mp["mroot"] as Node3D).add_child(n)
					n.visible = true
					_tc["n_new"] = n
		"d":
			if not spindle_empty and _tool_node != null:
				# altes Werkzeug aus der Spindel in den Greifer A nehmen
				spindle.remove_child(_tool_node)
				(_mp["grip_a"] as Node3D).add_child(_tool_node)
				_tool_node.transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -_tool_len(str(_tc["id_old"])) + GRIP_UP, 0))
				_tc["n_old"] = _tool_node
				_tool_node = null
				spindle_empty = true
		"h":
			var n_old := _tc["n_old"] as Node3D
			if n_old != null:
				n_old.get_parent().remove_child(n_old)
				(_mp["mroot"] as Node3D).add_child(n_old)
				n_old.transform = _grip_tool_xf("b", str(_tc["id_old"]), 1.0)


func _tc_leave(phase: String) -> void:
	match phase:
		"b":
			var n := _tc["n_new"] as Node3D
			if n != null:
				n.get_parent().remove_child(n)
				(_mp["grip_b"] as Node3D).add_child(n)
				n.transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -_tool_len(str(_tc["id_new"])) + GRIP_UP, 0))
		"e":
			# Neues Werkzeug (war in B) ist jetzt bei A, das alte bei B: Greifer tauschen die Besitzer
			pass
		"f":
			_tc_install_new()
		"h":
			var n_old := _tc["n_old"] as Node3D
			if n_old != null:
				n_old.queue_free()
				_tc["n_old"] = null


## Neues Werkzeug in die Spindel setzen, Bestandsführung nachziehen.
func _tc_install_new() -> void:
	var t := int(_tc["t_new"])
	var n := _tc["n_new"] as Node3D
	if n != null:
		n.get_parent().remove_child(n)
		var anchors: Array = _mp["anchors"]
		(anchors[t - 1] as Node3D).add_child(n)
		n.transform = _pocket_xf(str(_tc["id_new"]), 1.0)
		n.visible = false
		_tc["n_new"] = null
	if t > 0:
		_internal = true
		select_tool(tool_index(str(_tc["id_new"])), true)
		_internal = false
	tool_t = t
	if t == 0:
		spindle_empty = true
	_update_limits()
	var z_goal := (NOSE_CHG - top_y) * 1000.0 - MillTools.tool_length(tool())
	tool_z = minf(z_goal, z_max)
	_sync_axes()
	_tc["installed"] = true


## Wechsel beenden (normal oder durch Abbruch): Zustand in sich stimmig machen.
func _tc_finish() -> void:
	if not changing:
		return
	if not _tc.get("installed", false):
		# Abbruch vor dem Einsetzen: gilt als vollständig getauscht, das ist der einfachste stimmige Zustand
		var n_new := _tc.get("n_new") as Node3D
		if n_new != null and n_new.get_parent() != null and not _tc.get("installed", false):
			n_new.get_parent().remove_child(n_new)
			var anchors: Array = _mp["anchors"]
			(anchors[int(_tc["t_new"]) - 1] as Node3D).add_child(n_new)
			n_new.transform = _pocket_xf(str(_tc["id_new"]), 1.0)
			_tc["n_new"] = null
		_tc_install_new()
	var n_old := _tc.get("n_old") as Node3D
	if n_old != null:
		n_old.queue_free()
	_tc = {}
	changing = false
	_arm_x = 0.0
	_arm_y = 0.0
	_arm_theta = 0.0
	_arm_pose()
	_refresh_pockets()
	tool_changed.emit(tool_t)


## Ablauf je Phase: u = 0..1 (geglättet).
func _tc_pose(phase: String, u: float) -> void:
	var t_new := int(_tc["t_new"])
	match phase:
		"a":
			_disk_pose(lerpf(float(_tc["th0"]), float(_tc["th_new"]), u))
			_arm_theta = lerpf(0.0, PI / 2.0, u)
		"b":
			var n := _tc["n_new"] as Node3D
			if n != null:
				var id := str(_tc["id_new"])
				var a := _pocket_world_xf(t_new, id, 1.0)
				var b := _grip_tool_xf("b", id, 1.0)
				n.transform = a.interpolate_with(b, u)
		"c":
			_arm_x = u
			_arm_y = lerpf(0.0, TC_Y_HOLD, u)
		"d":
			_arm_y = lerpf(TC_Y_HOLD, TC_Y_PULL, u)
		"e":
			_arm_theta = lerpf(PI / 2.0, PI * 3.0 / 2.0, u)
		"f":
			_arm_y = lerpf(TC_Y_PULL, TC_Y_HOLD, u)
		"g":
			_arm_x = 1.0 - u
			_arm_y = lerpf(TC_Y_HOLD, 0.0, u)
			_disk_pose(lerpf(float(_tc["th_new"]), float(_tc["th_old"]), u))
		"h":
			var n_old := _tc["n_old"] as Node3D
			if n_old != null:
				var id_old := str(_tc["id_old"])
				var a2 := _grip_tool_xf("b", id_old, 1.0)
				var b2 := _pocket_world_xf(int(_tc["t_old"]), id_old, 1.0)
				n_old.transform = a2.interpolate_with(b2, u)
		"i":
			_arm_theta = lerpf(PI * 3.0 / 2.0, TAU, u)
	_arm_pose()


func _disk_pose(angle: float) -> void:
	_disk_angle = angle
	if not _mp.is_empty():
		(_mp["disk"] as Node3D).rotation.x = angle


func _arm_pose() -> void:
	if _mp.is_empty():
		return
	var arm: Node3D = _mp["arm"]
	arm.position = CncMillModel.ARM_PIVOT + Vector3(SHUTTLE.x * _arm_x, _arm_y, SHUTTLE.z * _arm_x)
	(_mp["arm_rot"] as Node3D).rotation.y = _arm_theta


## Lage des Greifers (Modellkoordinaten): g = "a" oder "b".
func _grip_xf(g: String) -> Transform3D:
	var arm: Node3D = _mp["arm"]
	var rot: Node3D = _mp["arm_rot"]
	var grip: Node3D = _mp["grip_a" if g == "a" else "grip_b"]
	return arm.transform * rot.transform * grip.transform


## Lage eines vom Greifer gehaltenen Werkzeugs (Schneide = Ursprung, Modellkoordinaten); k = 1: Magazinmaßstab/Vollmaß.
func _grip_tool_xf(g: String, id: String, k: float) -> Transform3D:
	var gx := _grip_xf(g)
	return gx * Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -_tool_len(id) + GRIP_UP, 0))


## Lage des Werkzeugs im Magazin (Modellkoordinaten): k = 1 Magazinmaßstab, 0 volle Größe (beim Übergang).
func _pocket_world_xf(t: int, id: String, k: float) -> Transform3D:
	var disk: Node3D = _mp["disk"]
	var anchors: Array = _mp["anchors"]
	return disk.transform * (anchors[t - 1] as Node3D).transform * _pocket_xf(id, k)


# ======================================================================= NC

func selected_program() -> Dictionary:
	return programs[prog_sel] if prog_sel >= 0 and prog_sel < programs.size() else {}


func program(prog_name: String) -> Dictionary:
	for p in programs:
		if str(p["name"]) == prog_name:
			return p
	return {}


func save_program(prog_name: String, lines: Array) -> void:
	var copy: Array[String] = []
	for l in lines:
		copy.append(str(l))
	var p := program(prog_name)
	if p.is_empty():
		programs.append({"name": prog_name, "lines": copy})
	else:
		p["lines"] = copy


func delete_program(prog_name: String) -> void:
	for i in programs.size():
		if str(programs[i]["name"]) == prog_name:
			programs.remove_at(i)
			if prog_sel >= programs.size():
				prog_sel = programs.size() - 1
			elif prog_sel > i:
				prog_sel -= 1
			return


## NC-Start mit dem angewählten Programm (bzw. Fortsetzen nach Halt).
func nc_start() -> bool:
	var p := selected_program()
	return channel.nc_start(p["lines"] if not p.is_empty() else [], str(p.get("name", "")))


func nc_stop() -> void:
	channel.nc_stop()


func nc_reset() -> void:
	channel.reset()


## Einzelner Klartext-Satz, z. B. "TOOL CALL 3 Z S2500" oder "L X+50 Y+30 FMAX".
func mdi(line: String) -> bool:
	if channel.busy():
		_warn("Programm läuft - erst RESET.")
		return false
	return channel.nc_start(["BEGIN PGM MDI MM", line, "END PGM MDI MM"], "MDI")


# ======================================================================= Ablauf

func _physics_process(delta: float) -> void:
	super(delta)
	if booting > 0.0:
		booting = maxf(booting - delta, 0.0)
		if booting <= 0.0:
			_apply_power()
	_door_step(delta)
	if not is_ready() and not estop:
		spindle_on = false
	_tc_step(delta)
	channel.step(delta)


func _process(delta: float) -> void:
	super(delta)
	_update_screen(delta)


# ======================================================================= Kamera, Ansichten

func in_panel_view() -> bool:
	return _panel_view


func screen_center() -> Vector3:
	if _screen_mi == null:
		return Vector3(1.5, 1.4, 1.5)
	return (_mp["mroot"] as Node3D).position + _screen_mi.position


func get_prompt() -> String:
	var chips := "Spänewanne %d %%" % int(tray.fraction() * 100.0)
	if not is_ready():
		return "%s    |    %s" % [power_hint(), chips]
	return "[%s] %s bedienen    |    %s" % [Settings.binding_text("interact"), machine_title(), chips]


func interact(p: Node, panel := false) -> void:
	if operating or panel_open:
		return
	if not is_ready():
		_warn(power_hint())
		return
	player = p
	operating = true
	if panel:
		p.start_operating(self, to_global(STAND_PULT), global_rotation.y + PULT_YAW)
		set_view("panel")
	else:
		p.start_operating(self, to_global(op_stand), global_rotation.y)
		set_view("reset")
	_activate_camera()
	operating_changed.emit(true)


func stop_operating() -> void:
	if operating:
		_screen_drag = false
		if screen_vp != null:
			screen_vp.gui_release_focus()      # sonst gälte typing() weiter und sperrte Tasten in der Werkstatt
		if _panel_view:
			set_view("back")
	super()


func _activate_camera() -> void:
	op_cam.fov = float(Settings.graphics["fov"]) * 0.75
	cam_dist = _dist_t
	cam_yaw = _yaw_t
	cam_pitch = _pitch_t
	cam_target = screen_center() if _panel_view else Vector3(0, top_y, 0)
	_update_camera(1.0)
	op_cam.make_current()


func _update_camera(delta: float) -> void:
	if Input.is_action_pressed("zoom_in"):
		_dist_t = maxf(_dist_t * pow(0.3, delta), CAM_MIN)
	if Input.is_action_pressed("zoom_out"):
		_dist_t = minf(_dist_t / pow(0.3, delta), CAM_MAX)
	var k := clampf(12.0 * delta, 0.0, 1.0)
	cam_dist = lerpf(cam_dist, _dist_t, k)
	cam_yaw = lerpf(cam_yaw, _yaw_t, k)
	cam_pitch = lerpf(cam_pitch, _pitch_t, k)
	var want := Vector3(0, top_y + maxf(tool_z, 0.0) * 0.0005, 0) + cam_pan
	if _panel_view:
		want = screen_center()
	cam_target = cam_target.lerp(want, clampf(8.0 * delta, 0.0, 1.0))
	var b := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	op_cam.transform = Transform3D(b, cam_target + b * Vector3(0, 0, cam_dist))
	# Kabine und Tür blenden sich aus, solange die Kamera im Arbeitsraum steht
	op_cam.set_cull_mask_value(3, not _cabin_box.has_point(op_cam.position) or _panel_view)


func set_view(view: String) -> void:
	if view == "panel":
		if not _panel_view:
			_pre_panel = [_yaw_t, _pitch_t, _dist_t, cam_pan]
		var was_panel := _panel_view
		_panel_view = true
		_yaw_t = PULT_YAW
		_pitch_t = 0.0
		var vfov := deg_to_rad(op_cam.fov if op_cam else 55.0)
		var vs := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
		var aspect := vs.x / maxf(vs.y, 1.0)
		var th := tan(vfov * 0.5)
		_dist_t = maxf((_screen_size.y + 0.05) * 0.5 / th, (_screen_size.x + 0.05) * 0.5 / (th * aspect))
		if not was_panel:
			view_changed.emit(true)
		return
	var was := _panel_view
	_panel_view = false
	if view == "back":
		if was and _pre_panel.size() == 4:
			_yaw_t = _pre_panel[0]
			_pitch_t = _pre_panel[1]
			_dist_t = _pre_panel[2]
			cam_pan = _pre_panel[3]
			_lever_view = false
		else:
			super("reset")
	else:
		super(view)
	if was:
		view_changed.emit(false)


func toggle_panel_view() -> void:
	set_view("back" if _panel_view else "panel")


# ======================================================================= Bildschirm und Klicks

## Mausposition (Fenster) -> Pixel auf dem Pult-Bildschirm, oder (-1, -1) wenn daneben.
func screen_pixel(mouse_pos: Vector2, clamp := false) -> Vector2:
	if _screen_mi == null or op_cam == null or not _screen_mi.is_inside_tree():
		return Vector2(-1, -1)
	var inv := _screen_mi.global_transform.affine_inverse()
	var o := inv * op_cam.project_ray_origin(mouse_pos)
	var d := inv.basis * op_cam.project_ray_normal(mouse_pos)
	if absf(d.z) < 1e-6:
		return Vector2(-1, -1)
	var t := -o.z / d.z
	if t <= 0.0:
		return Vector2(-1, -1)
	var p := o + d * t
	var uv := Vector2(p.x / _screen_size.x + 0.5, 0.5 - p.y / _screen_size.y)
	if clamp:
		uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
	elif uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv * Vector2(screen_vp.size)


func _screen_input(event: InputEvent) -> bool:
	if screen_vp == null or not is_ready() or not (event is InputEventMouse):
		return false
	var me := event as InputEventMouse
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		return false
	var mb := event as InputEventMouseButton
	var is_left := mb != null and mb.button_index == MOUSE_BUTTON_LEFT
	var is_wheel := mb != null and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN)
	if mb != null and not is_left and not is_wheel:
		return false
	if is_wheel and mb.ctrl_pressed:
		return false
	var px := screen_pixel(me.position, _screen_drag)
	if px.x < 0.0:
		if is_left and mb.pressed:
			screen_vp.gui_release_focus()
		return false
	if is_left:
		_screen_drag = event.is_pressed()
	push_screen_event(event, px)
	return is_left or is_wheel or _screen_drag


## Ereignis an Pixelposition px in die Steuerung geben (auch für Tests).
func push_screen_event(event: InputEvent, px: Vector2) -> void:
	var ev := event.duplicate() as InputEventMouse
	ev.position = px
	ev.global_position = px
	screen_vp.push_input(ev, true)


## Tastatur in ein Eingabefeld der Steuerung, solange dort eines bearbeitet wird.
func _input(event: InputEvent) -> void:
	if not operating or screen_vp == null or not (event is InputEventKey):
		return
	var f := screen_vp.gui_get_focus_owner()
	if not (f is LineEdit):
		return
	var k := event as InputEventKey
	if k.pressed and k.keycode == KEY_ESCAPE:
		screen_vp.gui_release_focus()
	else:
		screen_vp.push_input(event, true)
	get_viewport().set_input_as_handled()


func _mouse_ray(mouse_pos: Vector2) -> Array:
	var inv := global_transform.affine_inverse()
	return [inv * op_cam.project_ray_origin(mouse_pos), inv.basis * op_cam.project_ray_normal(mouse_pos)]


## Liegt die Maus über dem Türgriff?
func handle_hit(mouse_pos: Vector2) -> bool:
	if op_cam == null or _handle_body == null:
		return false
	var r := _mouse_ray(mouse_pos)
	var box := AABB(_handle_body.position - _handle_box.size * 0.5, _handle_box.size)
	return box.intersects_ray(r[0], r[1]) != null


func _zone_hit(zone_name: String, mouse_pos: Vector2) -> bool:
	if op_cam == null:
		return false
	var r := _mouse_ray(mouse_pos)
	for z in _zones:
		if str(z["name"]) == zone_name:
			return (z["box"] as AABB).intersects_ray(r[0], r[1]) != null
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not operating:
		return
	# Tasten gehören dem Eingabefeld der Steuerung, solange dort geschrieben wird (siehe _input)
	if event is InputEventKey and typing():
		get_viewport().set_input_as_handled()
		return
	if _screen_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mp := (event as InputEventMouseButton).position
		if handle_hit(mp):
			toggle_door()
			get_viewport().set_input_as_handled()
			return
		if _zone_hit("estop", mp):
			toggle_estop()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("cam_panel"):
		toggle_panel_view()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("door_toggle"):
		toggle_door()
		get_viewport().set_input_as_handled()
		return
	super(event)


# ======================================================================= Speichern

func get_state() -> Dictionary:
	var d := super()
	d["mag"] = Array(magazine)
	d["tool_t"] = tool_t
	d["datum"] = [datum.x, datum.y, datum.z]
	d["programs"] = programs.duplicate(true)
	d["prog_sel"] = prog_sel
	d["door"] = door_closed()
	d["powered"] = powered
	d["single_block"] = channel.single_block
	return d


func set_state(d: Dictionary) -> void:
	if changing:
		_tc_finish()
	channel.reset()
	_internal = true
	super(d)
	_internal = false
	var mag: Array = d.get("mag", [])
	for i in POCKETS:
		magazine[i] = str(mag[i]) if i < mag.size() else ""
	tool_t = int(d.get("tool_t", 0))
	if spindle_empty:
		tool_t = 0
	elif tool_t < 1 or tool_t > POCKETS or magazine[tool_t - 1] != str(tool()["id"]):
		# Alter Stand ohne Magazin: Spindelwerkzeug auf den ersten freien Platz
		var old := pocket_of(str(tool()["id"]))
		tool_t = old if old > 0 else free_pocket()
		if tool_t > 0:
			magazine[tool_t - 1] = str(tool()["id"])
	var dt: Array = d.get("datum", [0.0, 0.0, 0.0])
	datum = Vector3(float(dt[0]), float(dt[1]), float(dt[2]))
	if d.has("programs"):
		programs = (d["programs"] as Array).duplicate(true)
		prog_sel = int(d.get("prog_sel", 0 if not programs.is_empty() else -1))
	channel.single_block = bool(d.get("single_block", false))
	door_t = 1.0 if bool(d.get("door", true)) else 0.0
	_door_goal = door_t
	_place_door()
	var want_power := bool(d.get("powered", false))
	if want_power and not powered:
		power_on(true)
	elif not want_power and powered:
		power_off()
	_update_limits()
	_refresh_pockets()
	_disk_pose(_angle_of(tool_t, 0.0) if tool_t > 0 else 0.0)
	_sync_axes()


# ======================================================================= Klickziele (Strahl des Spielers)

## Tür bzw. Türgriff: Linksklick/[E] am Griff öffnet und schließt, [E] auf der Tür bedient die Maschine.
class DoorTarget extends Node:
	var mill: CncMill
	var handle := false

	static func make(m: CncMill, is_handle: bool) -> DoorTarget:
		var t := DoorTarget.new()
		t.mill = m
		t.handle = is_handle
		m.add_child(t)
		return t

	func get_machine() -> Node:
		return mill

	func get_prompt() -> String:
		var e := Settings.binding_text("interact")
		if handle:
			return "[%s] Kabinentür %s" % [e, "öffnen" if mill.door_closed() else "schließen"]
		return mill.get_prompt()

	func interact(p: Node) -> void:
		if handle:
			mill.toggle_door()
		else:
			mill.interact(p)

	func click(_p: Node) -> void:
		if handle:
			mill.toggle_door()


## Ein-Knopf, Not-Halt und Pult.
class PultTarget extends Node:
	var mill: CncMill
	var kind := "pult"

	static func make(m: CncMill, k: String) -> PultTarget:
		var t := PultTarget.new()
		t.mill = m
		t.kind = k
		m.add_child(t)
		return t

	func get_machine() -> Node:
		return mill

	func get_prompt() -> String:
		var e := Settings.binding_text("interact")
		match kind:
			"estop":
				if not mill.powered:
					return "Not-Halt - %s ist aus" % mill.machine_title()
				return "[%s] Not-Halt %s" % [e, "quittieren" if mill.estop else "betätigen"]
			"power":
				if not mill.powered:
					return mill.power_hint()
				if not mill.is_ready():
					return mill.power_hint()
				return "%s ist an    [%s] Bedienpult" % [mill.machine_title(), e]
		if not mill.is_ready():
			return mill.power_hint()
		return "[%s] Bedienpult (Steuerung)" % e

	func interact(p: Node) -> void:
		match kind:
			"estop":
				if mill.powered:
					mill.toggle_estop()
			"power":
				if not mill.powered:
					mill.power_on()
				elif mill.is_ready():
					mill.interact(p, true)
			_:
				mill.interact(p, true)
