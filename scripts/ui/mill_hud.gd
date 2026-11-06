class_name MillHUD
extends CanvasLayer
## Bedienoberfläche der Fräsmaschine: Positionsanzeige, Werkzeuge, Bedienfeld, Auftrag mit Draufsicht.

var mill: Mill
var job: Dictionary = {}
var _root: Control
var _dro: Label
var _status: Label
var _money: Label
var _job: Label
var _help: Label
var _top: TopView
var _op_nodes: Array[Control] = []
var _lever_box: PanelContainer
var _lever_info: Label
var _axis_btn: Button
var _operating := false
var _levers := false


## Draufsicht auf das Rohteil: Sollmaße des Auftrags und Werkzeugposition.
class TopView extends Control:
	const SCALE := 3.0
	const SHADER := """
shader_type canvas_item;
uniform float depth_mm = 40.0;
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float d = pow(clamp(-t.r / depth_mm, 0.0, 1.0), 0.45);
	vec3 raw = vec3(0.3, 0.32, 0.35);
	vec3 cut = mix(vec3(0.72, 0.8, 0.86), vec3(0.08, 0.2, 0.42), d);
	COLOR = vec4(mix(raw, cut, step(0.5, t.g)), 1.0);
}
"""
	var mill: Mill
	var job: Dictionary = {}
	var part: TextureRect

	func _ready() -> void:
		custom_minimum_size = Vector2(420, 250)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		# Zeigt die Höhenkarte des Rohteils: bearbeitete Flächen hell, je tiefer desto dunkler blau
		part = TextureRect.new()
		part.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		part.flip_v = true
		part.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		m.shader = sh
		part.material = m
		part.show_behind_parent = true
		add_child(part)

	func _process(_delta: float) -> void:
		if mill == null or not is_visible_in_tree():
			return
		part.position = _origin() + Vector2(0.0, -mill.block_w) * SCALE
		part.size = Vector2(mill.block_l, mill.block_w) * SCALE
		part.texture = mill.height_texture()
		(part.material as ShaderMaterial).set_shader_parameter("depth_mm", mill.block_h)
		queue_redraw()

	func _origin() -> Vector2:
		return Vector2(size.x * 0.5 - mill.block_l * SCALE * 0.5, size.y * 0.5 + mill.block_w * SCALE * 0.5)

	func _draw() -> void:
		if mill == null:
			return
		var o := _origin()
		var pt := func(x: float, y: float) -> Vector2: return o + Vector2(x, -y) * SCALE
		var want := Color(UITheme.ACCENT, 0.9)
		for f in job.get("features", []):
			if str(f["type"]) == "hole":
				draw_arc(pt.call(float(f["cx"]), float(f["cy"])), float(f["d"]) * 0.5 * SCALE, 0.0, TAU, 32, want, 2.0)
			else:
				draw_rect(Rect2(pt.call(float(f["x0"]), float(f["y1"])), Vector2(float(f["x1"]) - float(f["x0"]), float(f["y1"]) - float(f["y0"])) * SCALE), want, false, 2.0)
		if not mill.tool_near_part():
			return
		var c: Vector2 = pt.call(mill.tool_x, mill.tool_y)
		draw_arc(c, mill.tool_radius() * SCALE, 0.0, TAU, 48, Color(0.55, 0.95, 1.0), 2.0)
		draw_line(c - Vector2(6, 0), c + Vector2(6, 0), Color(0.55, 0.95, 1.0), 1.0)
		draw_line(c - Vector2(0, 6), c + Vector2(0, 6), Color(0.55, 0.95, 1.0), 1.0)


func _ready() -> void:
	layer = 6
	visible = false
	_root = Control.new()
	_root.theme = UITheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Oben links: Positionsanzeige
	var dro_panel := PanelContainer.new()
	dro_panel.position = Vector2(20, 20)
	dro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dro_panel)
	var dv := VBoxContainer.new()
	dro_panel.add_child(dv)
	var dt := Label.new()
	dt.text = "%s  -  Positionsanzeige" % MachineCatalog.MILL_NAME
	dt.add_theme_font_size_override("font_size", 16)
	dt.add_theme_color_override("font_color", UITheme.ACCENT)
	dv.add_child(dt)
	_dro = Label.new()
	_dro.add_theme_font_size_override("font_size", 26)
	_dro.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	dv.add_child(_dro)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	dv.add_child(_status)

	# Rechts oben: Auftrag und Draufsicht
	var right := VBoxContainer.new()
	right.anchor_left = 1
	right.anchor_right = 1
	right.offset_left = -470
	right.offset_right = -20
	right.offset_top = 20
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 6)
	_root.add_child(right)
	var job_panel := PanelContainer.new()
	job_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(job_panel)
	var jv := VBoxContainer.new()
	job_panel.add_child(jv)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 18)
	_money.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	jv.add_child(_money)
	_job = Label.new()
	_job.add_theme_font_size_override("font_size", 15)
	_job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job.custom_minimum_size.x = 400
	jv.add_child(_job)
	_top = TopView.new()
	right.add_child(_top)

	# Unten rechts: Bedienfeld
	var panel := PanelContainer.new()
	panel.anchor_left = 1
	panel.anchor_right = 1
	panel.anchor_top = 1
	panel.anchor_bottom = 1
	panel.offset_left = -470
	panel.offset_right = -20
	panel.offset_top = -20
	panel.offset_bottom = -20
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	panel.add_child(pv)
	var controls := GridContainer.new()
	controls.columns = 4
	controls.add_theme_constant_override("h_separation", 4)
	controls.add_theme_constant_override("v_separation", 4)
	pv.add_child(controls)
	controls.add_child(_button("Spindel", func(): mill.toggle_spindle()))
	controls.add_child(_button("Not-Halt", func(): mill.toggle_estop()))
	controls.add_child(_button("Kühlung", func(): mill.toggle_coolant()))
	_axis_btn = _button("Achse", func(): mill.cycle_hw_axis())
	controls.add_child(_axis_btn)
	controls.add_child(_button("Vorschub +", func(): mill.feed_selected(1)))
	controls.add_child(_button("Vorschub -", func(): mill.feed_selected(-1)))
	controls.add_child(_button("Rohteil", func(): mill.request_new_part()))
	controls.add_child(_button("Abgeben", func(): mill.request_submit()))

	# Unten links: Steuerungshilfe
	var help_panel := PanelContainer.new()
	help_panel.anchor_top = 1
	help_panel.anchor_bottom = 1
	help_panel.offset_left = 20
	help_panel.offset_top = -20
	help_panel.offset_bottom = -20
	help_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(help_panel)
	_help = Label.new()
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	help_panel.add_child(_help)
	_op_nodes = [dro_panel, right, panel, help_panel]

	# Hebelfeld: eigene kleine Anzeige, unten in der Mitte
	_lever_box = PanelContainer.new()
	_lever_box.anchor_left = 0.5
	_lever_box.anchor_right = 0.5
	_lever_box.anchor_top = 1
	_lever_box.anchor_bottom = 1
	_lever_box.offset_top = -20
	_lever_box.offset_bottom = -20
	_lever_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lever_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lever_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lever_box)
	_lever_info = Label.new()
	_lever_info.add_theme_font_size_override("font_size", 16)
	_lever_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lever_box.add_child(_lever_info)
	Settings.changed.connect(_refresh_help)
	_refresh_help()


func _button(text: String, cb: Callable) -> Button:
	var b := UITheme.button(text, cb, 96)
	b.custom_minimum_size.y = 36
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	return b


func set_job(j: Dictionary) -> void:
	job = j
	_top.job = j
	_job.text = MillJobs.describe(j)


func set_money(money: int, parts: int) -> void:
	_money.text = "Kontostand: %d EUR    |    Gefertigte Teile: %d" % [money, parts]


func set_operating(on: bool) -> void:
	_operating = on
	_top.mill = mill
	_apply_mode()


func set_levers_open(on: bool) -> void:
	_levers = on
	_apply_mode()


func _apply_mode() -> void:
	visible = _operating or _levers
	for n in _op_nodes:
		n.visible = _operating
	_lever_box.visible = _levers


func _refresh_help() -> void:
	var b := func(a: String) -> String: return Settings.binding_text(a)
	_help.text = "\n".join([
		"VERFAHREN   %s/%s  X (Tisch)   |   %s/%s  Y (Kreuzschlitten)   |   %s/%s  Z (Fräskopf)   |   %s = 10-fach" % [
			b.call("lathe_z_minus"), b.call("lathe_z_plus"), b.call("lathe_x_out"), b.call("lathe_x_in"), b.call("mill_z_down"), b.call("mill_z_up"), b.call("lathe_rapid")],
		"HANDRAD     Mausrad   |   %s  Achse X/Y/Z   |   %s  Schritt 0,001/0,01/0,1" % [b.call("hw_axis"), b.call("hw_step")],
		"SPINDEL     %s  Start/Stopp   |   VORSCHUB   %s  an/aus, Knöpfe Vorschub +/- für die gewählte Achse" % [b.call("spindle_toggle"), b.call("auto_feed")],
		"KÜHLUNG     %s  an/aus, auch während der Bearbeitung" % b.call("coolant"),
		"HEBEL       Drehzahl und Vorschub: Hebelfeld rechts an der Säule, dort %s drücken" % b.call("interact"),
		"WERKZEUG  Werkbank hinter dir: Linksklick nimmt, an der Spindel Linksklick setzt ein (vorher %s verlassen)" % b.call("interact"),
		"KAMERA      Rechte Maus  Drehen (+ Rad = Zoom)   |   Mittlere Maus  Verschieben   |   %s/%s/%s  Ansichten" % [b.call("cam_top"), b.call("cam_front"), b.call("cam_reset")],
		"SONST       %s  Not-Halt   |   %s  Rohteil   |   %s  Abgeben   |   %s  Verlassen" % [b.call("emergency_stop"), b.call("new_workpiece"), b.call("submit_part"), b.call("interact")],
	])


func _process(_delta: float) -> void:
	if not visible or mill == null:
		return
	if _levers:
		_lever_info.text = "Drehzahl %d /min    |    Vorschub %d mm/min\nGriff mit linker Maustaste ziehen oder über/unter den Griff klicken (nur bei stehender Spindel)    |    %s  Verlassen" % [
			int(mill.rpm_set), int(mill.feed_set), Settings.binding_text("interact")]
		return
	_axis_btn.text = "Achse: %s" % ["X", "Y", "Z"][mill.hw_axis]
	var mark := func(axis: int) -> String: return "»" if mill.hw_axis == axis else " "
	_dro.text = "%sX %9.3f mm\n%sY %9.3f mm\n%sZ %9.3f mm" % [mark.call(0), mill.tool_x, mark.call(1), mill.tool_y, mark.call(2), mill.tool_z]
	var t := mill.tool()
	var vc := mill.cutting_speed()
	var auto := "aus"
	if mill.auto_axis >= 0:
		auto = "%s%s" % [["X", "Y", "Z"][mill.auto_axis], "+" if mill.auto_sign > 0 else "-"]
	var lines: Array[String] = [
		"T  %s  (%d Schneiden, Schnitttiefe max. %.0f mm)" % [t["name"], int(t["z"]), float(t["ap_max"])],
		"S  %d /min  (Soll %d)   Spindel: %s" % [int(round(mill.spindle_speed)), int(mill.rpm_set), "LÄUFT" if mill.spindle_speed > 5.0 else "steht"],
		"F  %d mm/min   fz %.3f mm (max. %.3f)   Auto: %s" % [int(mill.feed_set), mill.feed_per_tooth(), float(t["fz_max"]), auto],
		"vc %d m/min %s   KSS: %s" % [int(vc), _vc_hint(vc), "EIN" if mill.coolant else "aus"],
		"Handrad: %s   Schritt %s / Raste" % [mill.axis_name(mill.hw_axis), Settings.handwheel_step_name()],
		"Letzte Schnitttiefe: %.2f mm" % mill.last_ap,
	]
	if mill.estop:
		lines.append("!!! NOT-HALT AKTIV !!!")
	_status.text = "\n".join(lines)


func _vc_hint(vc: float) -> String:
	if vc < 1.0:
		return ""
	if vc < 20.0:
		return "(zu niedrig)"
	if vc > 200.0:
		return "(zu hoch)"
	return "(gut)"
