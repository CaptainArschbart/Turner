class_name SawPanel
extends CanvasLayer
## Bedienung der Bandsäge: Abschnittslänge am Längenanschlag einstellen und sägen.

var saw: BandSaw
var spin: SpinBox
var info: Label
var error: Label
var job_button: Button
var _pitch := 0.0
var _suggested := 0.0


func _ready() -> void:
	layer = 14
	visible = false
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.window_style())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(560, 0)
	panel.add_child(v)
	v.add_child(UITheme.window_head("Bandsäge", "Maschine")["box"])
	v.add_child(UITheme.section("Eingelegte Stange"))
	info = UITheme.note("", 16, UITheme.TEXT)
	v.add_child(UITheme.card(info))
	v.add_child(UITheme.section("Längenanschlag"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var l := Label.new()
	l.text = "Abschnitt"
	row.add_child(l)
	spin = SpinBox.new()
	spin.min_value = RawMaterialTab.CUT_MIN
	spin.max_value = BandSaw.MAX_LEN
	spin.step = 1.0
	spin.suffix = "mm"
	spin.custom_minimum_size.x = 170
	spin.value_changed.connect(_on_length)
	row.add_child(spin)
	job_button = UITheme.button("Maß vom Auftrag", _use_job, 240)
	row.add_child(job_button)
	error = Label.new()
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.add_theme_font_size_override("font_size", 15)
	error.add_theme_color_override("font_color", UITheme.BAD)
	v.add_child(error)
	v.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	var saw_btn := UITheme.primary(UITheme.button("Sägen", start, 240))
	saw_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(saw_btn)
	buttons.add_child(UITheme.button("Schließen", close, 180))
	v.add_child(UITheme.key_hint("Esc / %s  ·  schließen" % Settings.binding_text("interact")))


func open() -> void:
	var player: Node = saw.world.player
	if visible or player.operating != null or not saw.has_bar():
		return
	var it: Dictionary = saw.bar
	info.text = "%s  %s\nDauer je Schnitt: %d s, Schnittbreite %d mm." % [Materials.label(str(it["material"])), RawMaterialTab.describe(it),
		int(ceil(BandSaw.cut_time(it))), int(Materials.KERF)]
	error.text = ""
	_suggested = saw.world.saw_suggestion(it)
	job_button.disabled = _suggested <= 0.0
	job_button.text = "Maß vom Auftrag: %d mm" % int(_suggested) if _suggested > 0.0 else "Kein passender Auftrag"
	spin.set_value_no_signal(_suggested if _suggested > 0.0 else saw.length_mm)
	saw.set_length(spin.value)
	visible = true
	_pitch = player.pitch
	player.start_operating(self, player.global_position, player.yaw)


func close() -> void:
	if not visible:
		return
	visible = false
	var player: Node = saw.world.player
	player.stop_operating()
	player.pitch = _pitch


func _on_length(mm: float) -> void:
	saw.set_length(mm)


func _use_job() -> void:
	spin.value = _suggested


## Sägen starten, das Fenster geht zu und der Spieler sieht dem Band zu.
func start() -> void:
	# Eingetippte Länge gilt auch ohne Eingabetaste
	if spin.get_line_edit().has_focus():
		spin.apply()
	var err: String = saw.start_cut(spin.value)
	error.text = err
	if err == "":
		close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Beim Eintippen der Länge schließt die Interaktionstaste das Fenster nicht
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if event.is_action_pressed("pause") or (not typing and (event.is_action_pressed("interact") or event.is_action_pressed("job_menu"))):
		get_viewport().set_input_as_handled()
		close()
