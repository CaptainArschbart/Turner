class_name MillHUD
extends CanvasLayer
## Bedienoberfläche der Fräsmaschine. Konventionell, darum im Normalfall nur Achsen und Draufsicht.
## Links Alt (halten) klappt alle Werte und den Auftrag auf, rechts Alt öffnet Tasten und Bedienknöpfe.

var mill: Mill
var job: Dictionary = {}
var _root: Control
var _dro: Label
var _status: Label
var _alert: Label
var _details: VBoxContainer
var _job: Label
var _dro_panel: PanelContainer
var _chip: PanelContainer
var _overlay: ControlsOverlay
var _top: TopView
var _op_nodes: Array[Control] = []
var _lever_box: PanelContainer
var _lever_info: Label
var _axis_btn: Button
var _target_panel: PanelContainer
var _targets: Label
var _operating := false
var _levers := false


## Draufsicht auf das Rohteil: Sollmaße des Auftrags und Werkzeugposition.
class TopView extends Control:
	const SCALE := 3.0
	const SHADER := """
shader_type canvas_item;
uniform float depth_mm = 40.0;
uniform vec3 raw_col = vec3(0.3, 0.32, 0.35);
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float d = pow(clamp(-t.r / depth_mm, 0.0, 1.0), 0.45);
	vec3 raw = raw_col;
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
		part.visible = mill.has_part
		part.position = _origin() + Vector2(0.0, -mill.block_w) * SCALE
		part.size = Vector2(mill.block_l, mill.block_w) * SCALE
		part.texture = mill.height_texture()
		(part.material as ShaderMaterial).set_shader_parameter("depth_mm", mill.block_h)
		(part.material as ShaderMaterial).set_shader_parameter("raw_col", mill.raw_color())
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

	# Oben links: Positionsanzeige, Details klappen darunter auf
	_dro_panel = PanelContainer.new()
	_dro_panel.position = Vector2(20, 20)
	_dro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dro_panel)
	var dv := VBoxContainer.new()
	_dro_panel.add_child(dv)
	_dro = Label.new()
	_dro.add_theme_font_size_override("font_size", 26)
	_dro.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	dv.add_child(_dro)
	_alert = Label.new()
	_alert.text = "!!! NOT-HALT AKTIV !!!"
	_alert.add_theme_font_size_override("font_size", 18)
	_alert.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_alert.visible = false
	dv.add_child(_alert)
	_details = VBoxContainer.new()
	_details.visible = false
	dv.add_child(_details)
	_details.add_child(HSeparator.new())
	var dt := Label.new()
	dt.text = mill.machine_title() if mill else MachineCatalog.MILL_NAME
	dt.add_theme_font_size_override("font_size", 16)
	dt.add_theme_color_override("font_color", UITheme.ACCENT)
	_details.add_child(dt)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_details.add_child(_status)
	_details.add_child(HSeparator.new())
	_job = Label.new()
	_job.add_theme_font_size_override("font_size", 15)
	_job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job.custom_minimum_size.x = 460
	_details.add_child(_job)

	# Oben rechts: Draufsicht
	var top_bg := ColorRect.new()
	top_bg.color = Color(0.08, 0.09, 0.1, 0.85)
	top_bg.anchor_left = 1
	top_bg.anchor_right = 1
	top_bg.offset_left = -450
	top_bg.offset_right = -20
	top_bg.offset_top = 20
	top_bg.offset_bottom = 270
	top_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top_bg)
	var top_title := Label.new()
	top_title.text = "Draufsicht   Orange = Soll   Blau = Werkzeug"
	top_title.position = Vector2(10, 4)
	top_title.add_theme_font_size_override("font_size", 13)
	top_title.add_theme_color_override("font_color", UITheme.MUTED)
	top_bg.add_child(top_title)
	_top = TopView.new()
	_top.anchor_left = 1
	_top.anchor_right = 1
	_top.offset_left = -450
	_top.offset_right = -20
	_top.offset_top = 20
	_top.offset_bottom = 270
	_root.add_child(_top)
	_target_panel = PanelContainer.new()
	_target_panel.anchor_left = 1
	_target_panel.anchor_right = 1
	_target_panel.offset_left = -450
	_target_panel.offset_right = -20
	_target_panel.offset_top = 274
	_target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_target_panel)
	_targets = Label.new()
	_targets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_targets.add_theme_font_size_override("font_size", 15)
	_target_panel.add_child(_targets)

	# Unten rechts: nur ein Hinweis, die volle Übersicht öffnet rechts Alt
	_chip = ControlsOverlay.make_chip()
	ControlsOverlay.set_chip_text(_chip, "Alt links  Details     Alt rechts  Tasten und Bedienung")
	_root.add_child(_chip)
	_overlay = ControlsOverlay.new()
	_root.add_child(_overlay)
	var controls := GridContainer.new()
	controls.columns = 4
	controls.add_theme_constant_override("h_separation", 6)
	controls.add_theme_constant_override("v_separation", 6)
	controls.add_child(_button("Spindel", func(): mill.toggle_spindle()))
	controls.add_child(_button("Not-Halt", func(): mill.toggle_estop()))
	controls.add_child(_button("Kühlung", func(): mill.toggle_coolant()))
	_axis_btn = _button("Achse", func(): mill.cycle_hw_axis())
	controls.add_child(_axis_btn)
	controls.add_child(_button("Vorschub +", func(): mill.feed_selected(1)))
	controls.add_child(_button("Vorschub -", func(): mill.feed_selected(-1)))
	controls.add_child(_button("Rohteil", func(): mill.request_new_part()))
	controls.add_child(_button("Abgeben", func(): mill.request_submit()))
	_overlay.add_extra("Bedienknöpfe", controls)
	_op_nodes = [_dro_panel, top_bg, _top, _chip, _target_panel]

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
	Settings.changed.connect(_refresh_pages)
	_refresh_pages()


func _button(text: String, cb: Callable) -> Button:
	var b := UITheme.button(text, cb, 96)
	b.custom_minimum_size.y = 36
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	return b


func set_job(j: Dictionary, grind := false) -> void:
	job = j
	_top.job = j
	_job.text = MillJobs.describe(j, grind)
	_targets.text = HUD.target_text(j, grind)


## Kein Fräsauftrag angenommen: keine Sollmaße, nur der Hinweis.
func set_no_job(text := "Kein Fräsauftrag angenommen. Aufträge gibt es am PC im Büro.") -> void:
	job = {}
	_top.job = {}
	_job.text = text
	_targets.text = HUD.target_text({})


func set_operating(on: bool) -> void:
	_operating = on
	_top.mill = mill
	_details.visible = false
	_overlay.set_open(false)
	_apply_mode()


func set_levers_open(on: bool) -> void:
	_levers = on
	_apply_mode()


func _apply_mode() -> void:
	visible = _operating or _levers
	for n in _op_nodes:
		n.visible = _operating
	_lever_box.visible = _levers
	_chip.visible = _operating and not _overlay.visible


func _input(event: InputEvent) -> void:
	if not _operating:
		return
	var side := ControlsOverlay.alt_side(event)
	if side == ControlsOverlay.LEFT:
		_details.visible = event.pressed
	elif side == ControlsOverlay.RIGHT and event.pressed:
		_overlay.set_open(not _overlay.visible)
		_apply_mode()


func _notification(what: int) -> void:
	# Alt-Tab: das Loslassen kommt nicht mehr an
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _details:
		_details.visible = false


func _refresh_pages() -> void:
	var b := func(a: String) -> String: return Settings.binding_text(a)
	_overlay.set_pages([
		{"title": "Verfahren", "rows": [
			[b.call("lathe_z_minus"), "Tisch X-"],
			[b.call("lathe_z_plus"), "Tisch X+"],
			[b.call("lathe_x_out"), "Kreuzschlitten Y-"],
			[b.call("lathe_x_in"), "Kreuzschlitten Y+"],
			[b.call("mill_z_down"), "%s senken (Z-)" % mill.head_title()],
			[b.call("mill_z_up"), "%s heben (Z+)" % mill.head_title()],
			[b.call("lathe_rapid"), "10-fach verfahren (halten)"],
			["Mausrad", "Handrad drehen"],
			[b.call("hw_axis"), "Handrad-Achse X / Y / Z"],
			[b.call("hw_step"), "Handrad-Schritt 0,001 / 0,01 / 0,1 mm"],
		]},
		{"title": "Spindel", "rows": [
			[b.call("spindle_toggle"), "Spindel Start / Stopp"],
			[b.call("auto_feed"), "Auto-Vorschub an / aus"],
			[b.call("coolant"), "Kühlung an / aus, auch während der Bearbeitung"],
			[b.call("interact"), "Am Bedienfeld an der Säule: Drehzahl, Vorschub und Stufen I / II einstellen"],
		]},
		{"title": "Werkzeug", "rows": [
			["Linksklick", "An der Werkbank nehmen oder zurücklegen, an der Spindel einsetzen (Werkbank am PC kaufen)"],
			[b.call("interact"), "Maschine verlassen, um zur Werkbank zu gehen"],
		]},
		{"title": "Ansicht", "rows": [
			["Rechte Maus", "Kamera drehen"],
			["Rechte Maus + Rad", "Zoomen"],
			["Mittlere Maus", "Kamera verschieben"],
			[b.call("cam_top"), "Draufsicht"],
			[b.call("cam_front"), "Vorderansicht"],
			[b.call("cam_reset"), "Standardansicht"],
		]},
		{"title": "Sonstiges", "rows": [
			[b.call("emergency_stop"), "Not-Halt / quittieren"],
			["Linksklick", "Material aus den Händen einspannen, von außerhalb der Maschine"],
			[b.call("new_workpiece"), "Rohteil anfordern: Hinweis, im Testmodus gratis"],
			[b.call("submit_part"), "Teil prüfen und abgeben"],
			[b.call("show_drawing"), "Werkstückzeichnung ein / aus"],
			[b.call("interact"), "Maschine verlassen"],
			["Alt links", "Alle Werte und Auftrag anzeigen (halten)"],
			["^", "Testmodus an / aus: alles gratis"],
		]},
	])


func _process(_delta: float) -> void:
	if not visible or mill == null:
		return
	if _levers:
		_lever_info.text = "Drehzahl %d /min (Stufe %s)    |    Vorschub %d mm/min (Stufe %s)\nGriff mit linker Maustaste ziehen, auf die Skala klicken oder Taste I/II drücken (nur bei stehender Spindel)    |    %s  Verlassen" % [
			int(mill.rpm_set), ["I", "II"][mill.dial_stage(0)], int(mill.feed_set), ["I", "II"][mill.dial_stage(1)], Settings.binding_text("interact")]
		return
	_axis_btn.text = "Achse: %s" % ["X", "Y", "Z"][mill.hw_axis]
	var mark := func(axis: int) -> String: return "»" if mill.hw_axis == axis else " "
	_dro.text = "%sX %9.3f mm\n%sY %9.3f mm\n%sZ %9.3f mm" % [mark.call(0), mill.tool_x, mark.call(1), mill.tool_y, mark.call(2), mill.tool_z]
	_alert.visible = mill.estop
	var t := mill.tool()
	var vc := mill.cutting_speed()
	var cd := mill.cut_data()
	var auto := "aus"
	if mill.auto_axis >= 0:
		auto = "%s%s" % [["X", "Y", "Z"][mill.auto_axis], "+" if mill.auto_sign > 0 else "-"]
	var lines: Array[String] = [
		"Werkstoff  %s  (%s)" % [Materials.label(mill.material), Materials.group_of(mill.material)["title"]],
		"T  %s  (%d Schneiden, Schnitttiefe max. %.1f mm)" % [t["name"], int(t["z"]), float(cd["ap_max"])] if mill.has_cutter() else "T  Spindel ist leer",
		"S  %d /min  (Soll %d)   Spindel: %s" % [int(round(mill.spindle_speed)), int(mill.rpm_set), "LÄUFT" if mill.spindle_speed > 5.0 else "steht"],
		"F  %d mm/min   fz %.3f mm (Richtwert %.3f, max. %.3f)   Auto: %s" % [int(mill.feed_set), mill.feed_per_tooth(), float(cd["fz_rec"]), float(cd["fz_max"]), auto],
		"vc %d m/min %s  Soll %d-%d   KSS: %s" % [int(vc), _vc_hint(vc), int(cd["vmin"]), int(cd["vmax"]), "EIN" if mill.coolant else "aus"],
		"Schneide: %d %% Hitze, %d %% Verschleiß   Spänewanne: %d %%" % [int(mill.tool_heat * 100.0), int(mill.tool_wear() * 100.0), int(mill.tray.fraction() * 100.0)],
		"Handrad: %s   Schritt %s / Raste" % [mill.axis_name(mill.hw_axis), Settings.handwheel_step_name()],
		"Letzte Schnitttiefe: %.2f mm" % mill.last_ap,
	]
	if mill.grinder_type != "" and mill.tool_stock != null:
		lines.append("Scheibe %d %% unrund    Abziehwerkzeug: X %d  Y %d  bis Z %d anfahren" % [
			int(mill.tool_stock.dull(str(t["id"])) * 100.0), int(mill.dresser_x()), int(mill.block_w * 0.5), int(mill.DRESS_Z)])
	_status.text = "\n".join(lines)
	_dro_panel.reset_size()


func _vc_hint(vc: float) -> String:
	if vc < 1.0:
		return ""
	var cd := mill.cut_data()
	if vc < float(cd["vmin"]):
		return "(zu niedrig)"
	if vc > float(cd["vmax"]):
		return "(zu hoch)"
	return "(gut)"
