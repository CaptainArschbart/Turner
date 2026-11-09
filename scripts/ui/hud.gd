class_name HUD
extends CanvasLayer
## Spiel-Oberfläche: Fadenkreuz, Hinweise, Auftrag. An der CNC-Drehmaschine knapp gehalten: Achsen und die
## NC-Werte S, F, KSS, T. An der konventionellen wie an der Fräse nur die Achsen. Links Alt (halten) klappt
## alles Weitere auf, rechts Alt öffnet die Tasten. Oben rechts stehen Konturansicht und Zielmaße.

var lathe: Lathe
var _root: Control
var _cross: Control
var _prompt: Label
var _held: Label
var _msg: Label
var _msg_t := 0.0
var _dro_panel: PanelContainer
var _dro: Label
var _main: Label
var _alert: Label
var _details: VBoxContainer
var _hw: Label
var _status: Label
var _detail_job: Label
var _job_panel: PanelContainer
var _job: Label
var _money: Label
var _xp: Label
var _chip: PanelContainer
var _overlay: ControlsOverlay
var _result_panel: PanelContainer
var _result: Label
var _result_t := 0.0
var _fps: Label
const MachinePanel := preload("res://scripts/ui/machine_panel.gd")

var _panel: PanelContainer
var _profile: ProfileView
var _lever_box: PanelContainer
var _lever_info: Label
var _lever_lathe: Lathe = null
var _clock: Label
var _machine_title: Label
var _target_panel: PanelContainer
var _targets: Label
const CravingGauge := preload("res://scripts/ui/craving_gauge.gd")
var cigarette: Cigarette          # Sucht-Meter: Wert kommt von der Zigarette des Spielers
var _gauge: Control
var _withdrawal: ColorRect        # Entzug: Bildrand verschwimmt und pulsiert rötlich
var _withdrawal_amt := 0.0
const WITHDRAWAL_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
uniform float pulse = 0.0;
void fragment() {
	vec2 d = SCREEN_UV - vec2(0.5);
	float edge = smoothstep(0.18, 0.75, length(d * vec2(1.3, 1.0)));
	vec3 col = textureLod(screen_tex, SCREEN_UV, edge * 3.5 * amount).rgb;
	float grey = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(grey), 0.45 * amount);
	col = mix(col, col * vec3(0.55, 0.22, 0.2), edge * amount * (0.55 + 0.25 * pulse));
	COLOR = vec4(col, 1.0);
}
"""


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
	_held.add_theme_color_override("font_color", UITheme.WARN)
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
	_dro = _label(26)
	_dro.add_theme_color_override("font_color", UITheme.VALUE)
	dv.add_child(_dro)
	_main = _label(18)
	dv.add_child(_main)
	_alert = _alert_label()
	dv.add_child(_alert)
	# Aufgeklappt, solange links Alt gehalten wird
	_details = VBoxContainer.new()
	_details.visible = false
	dv.add_child(_details)
	_details.add_child(HSeparator.new())
	_machine_title = _label(14)
	_machine_title.text = "DREHMASCHINE"
	_machine_title.add_theme_font_override("font", UITheme.font(600, 2))
	_machine_title.add_theme_color_override("font_color", UITheme.ACCENT)
	_details.add_child(_machine_title)
	_hw = _label(17)
	_hw.add_theme_color_override("font_color", UITheme.VALUE)
	_details.add_child(_hw)
	_status = _label(16)
	_details.add_child(_status)
	_details.add_child(HSeparator.new())
	_detail_job = _label(15)
	_detail_job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_job.custom_minimum_size.x = 460
	_details.add_child(_detail_job)

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
	jv.add_theme_constant_override("separation", 4)
	_job_panel.add_child(jv)
	_money = _label(19)
	_money.add_theme_font_override("font", UITheme.font(500, 1))
	_money.add_theme_color_override("font_color", UITheme.MONEY)
	jv.add_child(_money)
	_xp = _label(15)
	_xp.add_theme_color_override("font_color", UITheme.VALUE)
	jv.add_child(_xp)
	var jsep := HSeparator.new()
	jsep.add_theme_constant_override("separation", 6)
	jv.add_child(jsep)
	_job = _label(16)
	_job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job.custom_minimum_size.x = 420
	jv.add_child(_job)

	# Unten rechts: nur ein Hinweis, die volle Übersicht öffnet rechts Alt
	_chip = ControlsOverlay.make_chip()
	_root.add_child(_chip)

	# Ergebnis
	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_panel.visible = false
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_theme_stylebox_override("panel", UITheme.window_style())
	_root.add_child(_result_panel)
	_result = _label(19)
	_result_panel.add_child(_result)

	# Oben rechts: Konturansicht, an derselben Stelle wie die Draufsicht der Fräsmaschine
	_profile = ProfileView.new()
	_profile.anchor_left = 1
	_profile.anchor_right = 1
	_profile.offset_left = -480
	_profile.offset_right = -20
	_profile.offset_top = 20
	_profile.offset_bottom = 180
	_root.add_child(_profile)
	_target_panel = PanelContainer.new()
	_target_panel.anchor_left = 1
	_target_panel.anchor_right = 1
	_target_panel.offset_left = -480
	_target_panel.offset_right = -20
	_target_panel.offset_top = 184
	_target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_target_panel)
	_targets = _label(15)
	_targets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_panel.add_child(_targets)

	# Tastenübersicht mit dem Bedienpult als eigenem Tab
	_overlay = ControlsOverlay.new()
	_root.add_child(_overlay)
	_panel = MachinePanel.new()
	_panel.lathe = lathe
	_overlay.add_extra("Bedienpult", _panel)
	_overlay.add_extra("Bedienknöpfe", _conv_buttons())


	# Bedienfeld der konventionellen Drehmaschine: eigene kleine Anzeige, unten in der Mitte
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
	_lever_box.visible = false
	_root.add_child(_lever_box)
	_lever_info = _label(16)
	_lever_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lever_box.add_child(_lever_info)

	_clock = _label(17)
	_clock.add_theme_font_override("font", UITheme.font(500, 2))
	_clock.anchor_left = 0
	_clock.anchor_right = 1
	_clock.offset_top = 56
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_clock)

	_fps = _label(14)
	_fps.anchor_left = 0.5
	_fps.anchor_right = 0.5
	_fps.offset_top = 6
	_fps.add_theme_color_override("font_color", Color(1, 1, 0.5))
	_root.add_child(_fps)

	# Entzug: liegt unter allen Anzeigen, nur sichtbar, solange er wirkt
	_withdrawal = ColorRect.new()
	_withdrawal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_withdrawal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = WITHDRAWAL_SHADER
	_withdrawal.material = sm
	_withdrawal.visible = false
	_root.add_child(_withdrawal)
	_root.move_child(_withdrawal, 0)
	# Sucht-Meter unten links
	_gauge = CravingGauge.new()
	_gauge.anchor_top = 1
	_gauge.anchor_bottom = 1
	_gauge.offset_left = 20
	_gauge.offset_top = -20 - CravingGauge.H
	_gauge.offset_right = 20 + CravingGauge.W
	_gauge.offset_bottom = -20
	_root.add_child(_gauge)
	Settings.changed.connect(_refresh_pages)
	set_operating(false)


## Anzeigen gelten ab jetzt für diese Drehmaschine.
func use_lathe(m: Lathe) -> void:
	lathe = m
	_panel.lathe = m


## Station am Bedienfeld einer Drehmaschine.
func set_levers(m: Lathe, on: bool) -> void:
	_lever_lathe = m if on else null
	_lever_box.visible = on
	set_other_machine(on)


## Knöpfe der konventionellen Drehmaschine, dieselben wie an der Fräse.
func _conv_buttons() -> Control:
	var controls := GridContainer.new()
	controls.columns = 4
	controls.add_theme_constant_override("h_separation", 6)
	controls.add_theme_constant_override("v_separation", 6)
	controls.add_child(_button("Spindel", func(): lathe.toggle_spindle()))
	controls.add_child(_button("Not-Halt", func(): lathe.toggle_estop()))
	controls.add_child(_button("Kühlung", func(): lathe.coolant = not lathe.coolant))
	controls.add_child(_button("Achse", func(): lathe.hw_axis = 1 - lathe.hw_axis))
	controls.add_child(_button("Auto-Vorschub", func():
		if lathe.auto_feed or lathe.auto_feed_x:
			lathe.set_auto_feed(-1)
		else:
			lathe.set_auto_feed(0 if lathe.hw_axis == 0 else 1)))
	controls.add_child(_button("Rohteil", func(): lathe.request_new_part()))
	controls.add_child(_button("Abgeben", func(): lathe.request_submit()))
	return controls


func _button(text: String, cb: Callable) -> Button:
	var b := UITheme.button(text, cb, 96)
	b.custom_minimum_size.y = 36
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	return b


## Auftrag der Maschine: Sollkontur und Zielmaße oben rechts. grind: auch die Schleiffläche nennen.
func set_job_data(job: Dictionary, grind := false) -> void:
	_profile.job = job
	_targets.text = target_text(job, grind)


## Text des Felds mit den Zielmaßen.
static func target_text(job: Dictionary, grind := false) -> String:
	var key: String = Settings.binding_text("show_drawing")
	if job.is_empty():
		return "Zielmaße: kein Auftrag"
	return "Zielmaße    [%s] Zeichnung\n%s" % [key, "\n".join(PackedStringArray(JobBoard.target_lines(job, grind)))]


func _alert_label() -> Label:
	var l := _label(18)
	l.text = "!!! NOT-HALT AKTIV !!!"
	l.add_theme_color_override("font_color", UITheme.BAD)
	l.visible = false
	return l


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


## text = Auftrag oben rechts, detail = Auftrag der Drehmaschine für die aufgeklappten Details.
func set_job(text: String, detail := "") -> void:
	_job.text = text
	_detail_job.text = detail if detail != "" else text


func set_clock(text: String, closed: bool) -> void:
	_clock.text = text
	_clock.add_theme_color_override("font_color", UITheme.WARN if closed else UITheme.TEXT)


func set_skill_info(text: String) -> void:
	_xp.text = text


func set_money(money: int, parts: int) -> void:
	_money.text = "Werkstattkasse: %d EUR    |    Gefertigte Teile: %d" % [money, parts]


## Text an die laufende Meldung anhängen, damit beide zu lesen sind.
func append_message(t: String) -> void:
	_msg.text = t if _msg_t <= 0.0 else "%s\n%s" % [_msg.text, t]
	_msg_t = 5.0


func show_result(text: String) -> void:
	_result.text = text
	_result_panel.visible = true
	_result_t = 9.0
	await get_tree().process_frame
	_result_panel.reset_size()
	_result_panel.position = (_root.size - _result_panel.size) / 2.0


var _operating := false
var _other := false
var _pult_help := false


func set_operating(on: bool) -> void:
	_operating = on
	_pult_help = false
	_set_details(false)
	_overlay.set_open(false)
	_dro_panel.visible = on
	_profile.visible = on
	_target_panel.visible = on
	_profile.lathe = lathe
	if lathe:
		_machine_title.text = lathe.machine_title().to_upper() if lathe.conventional else "DREHMASCHINE"
		_main.visible = not lathe.conventional
		_hw.visible = not lathe.conventional
	_apply_mode()
	_refresh_pages()


## An einer anderen Maschine (eigene Oberfläche): nur Hinweise und Ergebnisse bleiben sichtbar.
func set_other_machine(on: bool) -> void:
	_other = on
	_overlay.set_open(false)
	_apply_mode()


## Der Testmodus zeigt sich nur im Debug-Menü und in der Kopfzeile am PC, nicht als Hinweis im Bild.
func set_free_mode(_on: bool) -> void:
	pass


func _apply_mode() -> void:
	var busy := _operating or _other
	_cross.visible = not busy
	_job_panel.visible = not busy
	_chip.visible = not _other and not _overlay.visible


func _set_details(on: bool) -> void:
	_details.visible = on


func _input(event: InputEvent) -> void:
	if not visible or _other:
		return
	var side := ControlsOverlay.alt_side(event)
	if side == ControlsOverlay.LEFT:
		_set_details(_operating and event.pressed)
	elif side == ControlsOverlay.RIGHT and event.pressed:
		_overlay.set_open(not _overlay.visible)
		_apply_mode()


func _notification(what: int) -> void:
	# Alt-Tab: das Loslassen kommt nicht mehr an
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _details:
		_set_details(false)


func _refresh_pages() -> void:
	var b := func(a: String) -> String: return Settings.binding_text(a)
	var pages: Array
	if _operating and _pult_help:
		pages = [{"title": "Pult", "rows": [
			["Maus", "Softkeys und Felder anklicken"],
			["Ziffern", "Werte tippen, Enter übernimmt, Esc bricht ab"],
			[b.call("cam_panel"), "Zurück zur Maschine"],
			[b.call("door_toggle"), "Schutztür auf / zu"],
			[b.call("emergency_stop"), "Not-Halt / quittieren"],
			[b.call("interact"), "Maschine verlassen"],
		]}]
	elif _operating:
		pages = [
			{"title": "Verfahren", "rows": [
				[b.call("lathe_x_in"), "Planschlitten zustellen (X-)"],
				[b.call("lathe_x_out"), "Planschlitten zurück (X+)"],
				[b.call("lathe_z_minus"), "Bettschlitten zum Futter (Z-)"],
				[b.call("lathe_z_plus"), "Bettschlitten weg vom Futter (Z+)"],
				[b.call("lathe_rapid"), "10-fach verfahren (halten)"],
				["Mausrad", "Handrad drehen"],
				[b.call("hw_axis"), "Handrad-Achse X / Z"],
				[b.call("hw_step"), "Handrad-Schritt 0,001 / 0,01 / 0,1 mm"],
			]},
			{"title": "Spindel", "rows": [
				[b.call("spindle_toggle"), "Spindel Start / Stopp"],
				[b.call("rpm_up"), "Drehzahl erhöhen"],
				[b.call("rpm_down"), "Drehzahl verringern"],
				[b.call("auto_feed"), "Auto-Vorschub an / aus (Handrad-Achse)"],
				[b.call("feed_up"), "Vorschub erhöhen"],
				[b.call("feed_down"), "Vorschub verringern"],
				[b.call("coolant"), "Kühlung an / aus"],
			] if not _is_conv() else [
				[b.call("spindle_toggle"), "Spindel Start / Stopp"],
				[b.call("auto_feed"), "Auto-Vorschub an / aus (Handrad-Achse)"],
				[b.call("coolant"), "Kühlung an / aus"],
				[b.call("interact"), "Am Bedienfeld am Spindelkasten: Drehzahl, Vorschub und Stufen I / II einstellen"],
			]},
			{"title": "Werkzeug", "rows": [
				["1 - 4", "Halterplatz einschwenken"],
				["Linksklick", "An der Werkbank nehmen oder zurücklegen, am Halterkopf einsetzen"],
				[b.call("interact"), "Maschine verlassen, um zur Werkbank zu gehen"],
			]},
			{"title": "Ansicht", "rows": [
				["Rechte Maus", "Kamera drehen"],
				["Rechte Maus + Rad", "Zoomen"],
				["Mittlere Maus", "Kamera verschieben"],
				[b.call("cam_top"), "Draufsicht"],
				[b.call("cam_front"), "Vorderansicht"],
				[b.call("cam_reset"), "Standardansicht"],
				[b.call("cam_panel"), "Bedienpult mit Zyklen und NC-Programmen" if not _is_conv() else "Nur an der CNC-Drehmaschine: Bedienpult"],
			]},
			{"title": "Sonstiges", "rows": [
				[b.call("door_toggle"), "Schutztür auf / zu - Linksklick auf die Tür: rastet am Schlitten ein, Linksklick auf den schwarzen Hebel: lösen" if not _is_conv() else "Nur an der CNC-Drehmaschine: Schutztür"],
				[b.call("emergency_stop"), "Not-Halt / quittieren"],
				["Linksklick", "Einspannen und Spanntiefe angeben, von außerhalb der Maschine"],
				["Rechtsklick", "Teil umgedreht einspannen, von außerhalb der Maschine"],
				[b.call("new_workpiece"), "Rohteil anfordern: Hinweis, im Testmodus gratis"],
				[b.call("submit_part"), "Teil prüfen und abgeben"],
				[b.call("show_drawing"), "Werkstückzeichnung ein / aus"],
				[b.call("smoke"), "Zigarette anzünden / ausmachen"],
				[b.call("interact"), "Maschine verlassen"],
				["Alt links", "Alle Werte und Auftrag anzeigen (halten)"],
				["^", "Debug-Menü: Testmodus, Noclip, Zeit, Geld"],
			]},
		]
	else:
		pages = [{"title": "Bewegung", "rows": [
			[b.call("move_forward"), "Vorwärts"],
			[b.call("move_back"), "Rückwärts"],
			[b.call("move_left"), "Nach links"],
			[b.call("move_right"), "Nach rechts"],
			[b.call("sprint"), "Rennen"],
			[b.call("crouch"), "Ducken"],
			[b.call("jump"), "Springen"],
			[b.call("interact"), "Interagieren"],
			["Linksklick", "Werkzeug oder Material aufnehmen, ablegen, einsetzen; Lagerregal ansehen"],
			[b.call("drop"), "Getragenes fallen lassen (mit Linksklick wieder aufheben)"],
			[b.call("toggle_view"), "Kamera 1. / 3. Person"],
			[b.call("job_menu"), "Angenommene Aufträge, einen oben rechts anzeigen"],
			[b.call("show_drawing"), "Werkstückzeichnung des gewählten Auftrags"],
			[b.call("smoke"), "Zigarette anzünden / ausmachen (Hände bleiben frei)"],
			[b.call("build_menu"), "Baumodus: anvisieren und E nehmen, Linksklick abstellen"],
			[b.call("pause"), "Menü"],
			["^", "Debug-Menü: Testmodus, Noclip, Zeit, Geld"],
		]}]
	_overlay.set_pages(pages, _operating and not _pult_help, "Bedienknöpfe" if _is_conv() else "Bedienpult")
	ControlsOverlay.set_chip_text(_chip, "Alt links  Details     Alt rechts  Tasten und Bedienung" if _operating and not _pult_help else ("Alt rechts  Tasten" if _operating else "Tab  Aufträge     B  Baumodus     Alt rechts  Tasten"))


func _is_conv() -> bool:
	return lathe != null and lathe.conventional


func _process(delta: float) -> void:
	if _lever_lathe:
		var unit := ("%.2f" % _lever_lathe.feed_set).replace(".", ",")
		_lever_info.text = "Drehzahl %d /min (Stufe %s)    |    Vorschub %s mm/U (Stufe %s)\nGriff mit linker Maustaste ziehen, auf die Skala klicken oder Taste I/II drücken (nur bei stehender Spindel)    |    %s  Verlassen" % [
			int(_lever_lathe.rpm_set), ["I", "II"][_lever_lathe.dial_stage(0)], unit, ["I", "II"][_lever_lathe.dial_stage(1)], Settings.binding_text("interact")]
	if _msg_t > 0.0:
		_msg_t -= delta
		_msg.modulate.a = clampf(_msg_t, 0.0, 1.0)
	if _result_t > 0.0:
		_result_t -= delta
		if _result_t <= 0.0:
			_result_panel.visible = false
	_update_craving(delta)
	_fps.visible = bool(Settings.graphics["show_fps"])
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	# Pultansicht: Dreh-Anzeigen ausblenden, der Bildschirm am Pult ist die Bedienung
	var pult := _operating and lathe != null and lathe.in_panel_view()
	if _operating:
		_dro_panel.visible = not pult
		_profile.visible = not pult
		_target_panel.visible = not pult
		if pult != _pult_help:
			_pult_help = pult
			_overlay.set_open(false)
			_apply_mode()
			_refresh_pages()
	if _operating and lathe:
		var mx := "»" if lathe.hw_axis == 0 else " "
		var mz := "»" if lathe.hw_axis == 1 else " "
		_dro.text = "%sX  Ø %9.3f mm\n%sZ    %9.3f mm" % [mx, lathe.tool_x * 2.0, mz, lathe.tool_z]
		_hw.text = "Handrad:  %s   Schritt %s / Raste" % ["X" if lathe.hw_axis == 0 else "Z", Settings.handwheel_step_name()]
		var vc := lathe.cutting_speed()
		var spindle := "LÄUFT" if lathe.spindle_speed > 5.0 else "steht"
		var parts: Array[String] = []
		var t := lathe.tool()
		_main.text = "S    %d /min\nF    %s mm/U\nKSS  %s\nT    Platz %d: %s" % [
			int(round(lathe.rpm())), ("%.2f" % lathe.feed()).replace(".", ","), ("EIN" if lathe.coolant else "aus") + lathe.kss_suffix(),
			lathe.active_slot + 1, "%s %s" % [t["id"], t["name"]] if lathe.has_cutter() else "leer"]
		_alert.visible = lathe.estop
		var feed_txt := "längs" if lathe.auto_feed else ("plan" if lathe.auto_feed_x else "aus")
		var td := lathe.tool_data(t)
		var mk := lathe.machine_pos()
		parts.append("Korr. L1 %.3f  L2 %.3f  R %.1f  SL %d   MKS (F): X Ø %.3f  Z %.3f" % [
			td["l1"], td["l2"], td["r"], td["sl"], mk.y * 2.0, mk.x])
		parts.append("Ist %d /min%s   Spindel: %s" % [int(round(lathe.spindle_speed)), "  (G96)" if lathe.css else "", spindle])
		parts.append("Auto-Vorschub: %s" % feed_txt)
		var win := lathe.vc_window()
		parts.append("vc %d m/min %s  Soll %d-%d" % [int(vc), _vc_hint(vc), int(win.x), int(win.y)])
		parts.append("Werkstoff  %s  (%s)" % [Materials.label(lathe.material), Materials.group_of(lathe.material)["title"]])
		parts.append("Schneide: %d %% Hitze, %d %% Verschleiß   Spänewanne: %d %%" % [int(lathe.tool_heat * 100.0), int(lathe.tool_wear() * 100.0), int(lathe.tray.fraction() * 100.0)])
		parts.append("Rz letzter Schnitt: %.1f µm%s" % [lathe.last_rz, ("  - " + lathe.last_rz_hint) if lathe.last_rz_hint != "" else ""])
		var nc_txt := "Hand"
		if lathe.nc.state != "idle":
			nc_txt = "AUTO %s: %s" % [lathe.nc.prog.get("name", ""), lathe.nc.state_text()]
		if lathe.grinder_type != "" and lathe.tool_stock != null:
			parts.append("Scheibe %d %% unrund    Abziehwerkzeug: Z %d, bis X Ø %d anfahren" % [
				int(lathe.tool_stock.dull(str(t["id"])) * 100.0), int(lathe.DRESS_Z), int(lathe.DRESS_X * 2.0)])
		elif lathe.conventional:
			parts.append("Steuerung: von Hand")
		else:
			parts.append("Tür: %s   Steuerung: %s" % ["ZU" if lathe.door_closed() else ("AUF" if lathe.door_t < 0.001 and not lathe._door_closing else "fährt"), nc_txt])
		_status.text = "\n".join(_conv_lines(t, vc) if lathe.conventional else parts)
		_dro_panel.reset_size()


## Details der konventionellen Maschine, aufgebaut wie an der Fräse.
func _conv_lines(t: Dictionary, vc: float) -> Array[String]:
	var win := lathe.vc_window()
	var auto := "längs" if lathe.auto_feed else ("plan" if lathe.auto_feed_x else "aus")
	var lines: Array[String] = [
		"Werkstoff  %s  (%s)" % [Materials.label(lathe.material), Materials.group_of(lathe.material)["title"]],
		"T  Platz %d: %s %s" % [lathe.active_slot + 1, t["id"], t["name"]] if lathe.has_cutter() else "T  Halter ist leer",
		"S  %d /min  (Soll %d)   Spindel: %s" % [int(round(lathe.spindle_speed)), int(lathe.rpm_set), "LÄUFT" if lathe.spindle_speed > 5.0 else "steht"],
		"F  %s mm/U   Auto: %s" % [("%.2f" % lathe.feed_set).replace(".", ","), auto],
		"vc %d m/min %s  Soll %d-%d   KSS: %s" % [int(vc), _vc_hint(vc), int(win.x), int(win.y), ("EIN" if lathe.coolant else "aus") + lathe.kss_suffix()],
		"Schneide: %d %% Hitze, %d %% Verschleiß   Spänewanne: %d %%" % [int(lathe.tool_heat * 100.0), int(lathe.tool_wear() * 100.0), int(lathe.tray.fraction() * 100.0)],
		"Handrad: %s   Schritt %s / Raste" % [lathe.hw_axis_name(), Settings.handwheel_step_name()],
		"Spanntiefe: %d mm%s" % [int(lathe.clamp_depth), ", umgedreht" if lathe.flipped else ""],
		"Rz letzter Schnitt: %.1f µm%s" % [lathe.last_rz, ("  - " + lathe.last_rz_hint) if lathe.last_rz_hint != "" else ""],
	]
	if lathe.grinder_type != "" and lathe.tool_stock != null:
		lines.append("Scheibe %d %% unrund    Abziehwerkzeug: Z %d, bis X Ø %d anfahren" % [
			int(lathe.tool_stock.dull(str(t["id"])) * 100.0), int(lathe.DRESS_Z), int(lathe.DRESS_X * 2.0)])
	return lines


func _vc_hint(vc: float) -> String:
	if vc < 1.0:
		return ""
	var win := lathe.vc_window()
	if vc < win.x:
		return "(zu niedrig)"
	if vc > win.y:
		return "(zu hoch)"
	return "(gut)"


## Sucht-Meter nachführen und im Entzug den Bildrand verschwimmen lassen.
func _update_craving(delta: float) -> void:
	_gauge.visible = cigarette != null
	if cigarette == null:
		_withdrawal.visible = false
		return
	_gauge.value = cigarette.need
	_gauge.craving = cigarette.craving
	_gauge.lit = cigarette.lit
	_withdrawal_amt = move_toward(_withdrawal_amt, 1.0 if cigarette.craving else 0.0, delta * 0.5)
	_withdrawal.visible = _withdrawal_amt > 0.001
	if _withdrawal.visible:
		var sm := _withdrawal.material as ShaderMaterial
		sm.set_shader_parameter("amount", _withdrawal_amt)
		sm.set_shader_parameter("pulse", sin(Time.get_ticks_msec() * 0.004))
