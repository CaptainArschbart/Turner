class_name HUD
extends CanvasLayer
## Spiel-Oberfläche: Fadenkreuz, Hinweise, Positionsanzeige (DRO), Auftrag, Steuerungshilfe.

var lathe: Lathe
var _root: Control
var _cross: Control
var _prompt: Label
var _held: Label
var _msg: Label
var _msg_t := 0.0
var _dro_panel: PanelContainer
var _dro: Label
var _hw: Label
var _status: Label
var _job_panel: PanelContainer
var _job: Label
var _money: Label
var _help_panel: PanelContainer
var _help: Label
var _result_panel: PanelContainer
var _result: Label
var _result_t := 0.0
var _fps: Label
const MachinePanel := preload("res://scripts/ui/machine_panel.gd")

var _tool_box: VBoxContainer
var _panel: PanelContainer
var _profile: ProfileView


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.theme = UITheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_cross = ColorRect.new()
	(_cross as ColorRect).color = Color(1, 1, 1, 0.8)
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.offset_left = -2
	_cross.offset_right = 2
	_cross.offset_top = -2
	_cross.offset_bottom = 2
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cross)

	_prompt = _label(22)
	_prompt.anchor_left = 0
	_prompt.anchor_right = 1
	_prompt.anchor_top = 1
	_prompt.anchor_bottom = 1
	_prompt.offset_top = -170
	_prompt.offset_bottom = -130
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prompt)

	_held = _label(18)
	_held.anchor_left = 0
	_held.anchor_right = 1
	_held.anchor_top = 1
	_held.anchor_bottom = 1
	_held.offset_top = -130
	_held.offset_bottom = -100
	_held.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_held.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_root.add_child(_held)

	_msg = _label(24)
	_msg.anchor_left = 0.25
	_msg.anchor_right = 0.68
	_msg.offset_top = 300
	_msg.offset_bottom = 380
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_msg)

	# Positionsanzeige
	_dro_panel = PanelContainer.new()
	_dro_panel.position = Vector2(20, 20)
	_dro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dro_panel)
	var dv := VBoxContainer.new()
	_dro_panel.add_child(dv)
	var dt := _label(16)
	dt.text = "WEILER E50 HD  -  Positionsanzeige"
	dt.add_theme_color_override("font_color", UITheme.ACCENT)
	dv.add_child(dt)
	_dro = _label(26)
	_dro.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	dv.add_child(_dro)
	_hw = _label(19)
	_hw.add_theme_color_override("font_color", UITheme.ACCENT)
	dv.add_child(_hw)
	_status = _label(17)
	dv.add_child(_status)

	# Auftrag
	_job_panel = PanelContainer.new()
	_job_panel.anchor_left = 1
	_job_panel.anchor_right = 1
	_job_panel.offset_left = -470
	_job_panel.offset_right = -20
	_job_panel.offset_top = 20
	_job_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_job_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_job_panel)
	var jv := VBoxContainer.new()
	_job_panel.add_child(jv)
	_money = _label(20)
	_money.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	jv.add_child(_money)
	_job = _label(16)
	_job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job.custom_minimum_size.x = 420
	jv.add_child(_job)

	# Steuerungshilfe
	_help_panel = PanelContainer.new()
	_help_panel.anchor_top = 1
	_help_panel.anchor_bottom = 1
	_help_panel.offset_left = 20
	_help_panel.offset_top = -20
	_help_panel.offset_bottom = -20
	_help_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_help_panel)
	_help = _label(15)
	_help.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	_help_panel.add_child(_help)

	# Ergebnis
	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_panel.visible = false
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_result_panel)
	_result = _label(19)
	_result_panel.add_child(_result)

	# Unten rechts: Bedienpult, Konturansicht (wächst nach oben)
	_tool_box = VBoxContainer.new()
	_tool_box.add_theme_constant_override("separation", 4)
	_tool_box.anchor_left = 1
	_tool_box.anchor_right = 1
	_tool_box.anchor_top = 1
	_tool_box.anchor_bottom = 1
	_tool_box.offset_left = -480
	_tool_box.offset_right = -20
	_tool_box.offset_top = -20
	_tool_box.offset_bottom = -20
	_tool_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tool_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tool_box)
	_panel = MachinePanel.new()
	_panel.lathe = lathe
	_tool_box.add_child(_panel)
	_profile = ProfileView.new()
	_tool_box.add_child(_profile)

	_fps = _label(14)
	_fps.anchor_left = 0.5
	_fps.anchor_right = 0.5
	_fps.offset_top = 6
	_fps.add_theme_color_override("font_color", Color(1, 1, 0.5))
	_root.add_child(_fps)
	Settings.changed.connect(_refresh_help)
	set_operating(false)


func set_job_data(job: Dictionary) -> void:
	_profile.job = job


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func set_prompt(t: String) -> void:
	_prompt.text = t


func set_held(t: String) -> void:
	_held.text = t


func show_message(t: String, c := Color.WHITE) -> void:
	_msg.text = t
	_msg.add_theme_color_override("font_color", c)
	_msg_t = 3.0


func set_job(text: String) -> void:
	_job.text = text


func set_money(money: int, parts: int) -> void:
	_money.text = "Kontostand: %d EUR    |    Gefertigte Teile: %d" % [money, parts]


func show_result(text: String) -> void:
	_result.text = text
	_result_panel.visible = true
	_result_t = 9.0
	await get_tree().process_frame
	_result_panel.reset_size()
	_result_panel.position = (_root.size - _result_panel.size) / 2.0


var _operating := false
var _pult_help := false


func set_operating(on: bool) -> void:
	_operating = on
	_pult_help = false
	_dro_panel.visible = on
	_cross.visible = not on
	_tool_box.visible = on
	_profile.lathe = lathe
	_refresh_help()


## An einer anderen Maschine (eigene Oberfläche): nur Hinweise und Ergebnisse bleiben sichtbar.
func set_other_machine(on: bool) -> void:
	_cross.visible = not on
	_job_panel.visible = not on
	_help_panel.visible = not on


func _refresh_help() -> void:
	var b := func(a: String) -> String: return Settings.binding_text(a)
	if _operating and _pult_help:
		_help.text = "PULT   Maus: Softkeys und Felder anklicken, Zahlen tippen (Enter übernimmt, Esc bricht ab)
%s  zurück zur Maschine   |   %s  Schutztür   |   %s  Not-Halt   |   %s  Verlassen" % [
			b.call("cam_panel"), b.call("door_toggle"), b.call("emergency_stop"), b.call("interact")]
	elif _operating:
		_help.text = "\n".join([
			"VERFAHREN   %s%s%s%s  Schlitten im eingestellten Vorschub  (%s = 10-fach)" % [b.call("lathe_x_in"), b.call("lathe_z_minus"), b.call("lathe_x_out"), b.call("lathe_z_plus"), b.call("lathe_rapid")],
			"HANDRAD     Mausrad   |   %s  Achse X/Z   |   %s  Schritt 0,001/0,01/0,1" % [b.call("hw_axis"), b.call("hw_step")],
			"SPINDEL     %s  Start/Stopp   |   %s/%s  Drehzahl   |   %s  Kühlung" % [b.call("spindle_toggle"), b.call("rpm_up"), b.call("rpm_down"), b.call("coolant")],
			"VORSCHUB    %s  Auto an/aus (Handrad-Achse), Richtung am Pult   |   %s/%s  mm/U" % [b.call("auto_feed"), b.call("feed_up"), b.call("feed_down")],
			"PULT        Maus: Fenster rechts unten oder Bildschirm am Maschinenpult (%s) - dort Zyklen / NC-Programme" % b.call("cam_panel"),
			"TÜR         Schwarzen Griff mit linker Maus ziehen oder %s   (Zyklusstart nur bei geschlossener Tür)" % b.call("door_toggle"),
			"KAMERA      Rechte Maus  Drehen (+ Rad = Zoom)   |   Mittlere Maus  Verschieben   |   %s/%s/%s  Ansichten" % [b.call("cam_top"), b.call("cam_front"), b.call("cam_reset")],
			"WERKZEUGE   Werkbank: Linksklick nimmt, am Halterkopf Linksklick setzt ein (vorher %s verlassen)" % b.call("interact"),
			"SONST       1-4  Halterplatz einschwenken   |   %s  Not-Halt   |   %s  Rohteil   |   %s  Abgeben   |   %s  Verlassen" % [b.call("emergency_stop"), b.call("new_workpiece"), b.call("submit_part"), b.call("interact")],
		])
	else:
		_help.text = "%s%s%s%s  Bewegen    %s  Rennen    %s  Ducken    %s  Springen\n%s  Interagieren    %s  Kamera 1./3. Person    %s  Menü" % [
			b.call("move_forward"), b.call("move_left"), b.call("move_back"), b.call("move_right"),
			b.call("sprint"), b.call("crouch"), b.call("jump"), b.call("interact"), b.call("toggle_view"), b.call("pause")]


func _process(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= delta
		_msg.modulate.a = clampf(_msg_t, 0.0, 1.0)
	if _result_t > 0.0:
		_result_t -= delta
		if _result_t <= 0.0:
			_result_panel.visible = false
	_fps.visible = bool(Settings.graphics["show_fps"])
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	# Pultansicht: Dreh-Anzeigen ausblenden, der Bildschirm am Pult ist die Bedienung
	var pult := _operating and lathe != null and lathe.in_panel_view()
	if _operating:
		_dro_panel.visible = not pult
		_tool_box.visible = not pult
		if pult != _pult_help:
			_pult_help = pult
			_refresh_help()
	if _operating and lathe:
		var mx := "»" if lathe.hw_axis == 0 else " "
		var mz := "»" if lathe.hw_axis == 1 else " "
		_dro.text = "%sX  Ø %9.3f mm\n%sZ    %9.3f mm" % [mx, lathe.tool_x * 2.0, mz, lathe.tool_z]
		_hw.text = "Handrad:  %s   Schritt %s / Raste" % ["X" if lathe.hw_axis == 0 else "Z", Settings.handwheel_step_name()]
		var vc := lathe.cutting_speed()
		var spindle := "LÄUFT" if lathe.spindle_speed > 5.0 else "steht"
		var parts: Array[String] = []
		var t := lathe.tool()
		var feed_txt := "längs" if lathe.auto_feed else ("plan" if lathe.auto_feed_x else "aus")
		parts.append("T  Platz %d: %s D1 %s" % [lathe.active_slot + 1, t["id"], t["name"]])
		var td := lathe.tool_data(t)
		var mk := lathe.machine_pos()
		parts.append("Korr. L1 %.3f  L2 %.3f  R %.1f  SL %d   MKS (F): X Ø %.3f  Z %.3f" % [
			td["l1"], td["l2"], td["r"], td["sl"], mk.y * 2.0, mk.x])
		parts.append("S  %d /min  (Soll %d%s)   Spindel: %s" % [int(round(lathe.spindle_speed)), int(round(lathe.rpm())), ", G96" if lathe.css else "", spindle])
		parts.append("F  %.2f mm/U   Auto-Vorschub: %s" % [lathe.feed(), feed_txt])
		parts.append("vc %d m/min %s   KSS: %s" % [int(vc), _vc_hint(vc), "EIN" if lathe.coolant else "aus"])
		parts.append("Rz letzter Schnitt: %.1f µm%s" % [lathe.last_rz, ("  - " + lathe.last_rz_hint) if lathe.last_rz_hint != "" else ""])
		var nc_txt := "Hand"
		if lathe.nc.state != "idle":
			nc_txt = "AUTO %s: %s" % [lathe.nc.prog.get("name", ""), lathe.nc.state_text()]
		parts.append("Tür: %s   Steuerung: %s" % ["ZU" if lathe.door_closed() else ("AUF" if lathe.door_t < 0.001 else "fährt"), nc_txt])
		if lathe.estop:
			parts.append("!!! NOT-HALT AKTIV !!!")
		_status.text = "\n".join(parts)


func _vc_hint(vc: float) -> String:
	if vc < 1.0:
		return ""
	if vc < 80.0:
		return "(zu niedrig)"
	if vc > 320.0:
		return "(zu hoch)"
	return "(gut)"
