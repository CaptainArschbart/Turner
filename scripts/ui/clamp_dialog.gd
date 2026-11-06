class_name ClampDialog
extends CanvasLayer
## Kleines Fenster beim Einspannen: Spanntiefe angeben. Linksklick spannt normal, Rechtsklick andersherum.

const LATHE_DEPTH := 8.0          # voreingestellte Spanntiefe im Futter (mm), Aufträge lassen 10 mm frei

## Spielwelt: player, finish_clamp(machine, flip, depth), clamp_limit(machine)
var world: Node
var machine: Node
var flip := false
var spin: SpinBox
var _title: Label
var _info: Label
var _error: Label
var _pitch := 0.0


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
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(460, 0)
	panel.add_child(v)
	_title = UITheme.title("Einspannen")
	_title.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(_title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 15)
	v.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var l := Label.new()
	l.text = "Spanntiefe"
	row.add_child(l)
	spin = SpinBox.new()
	spin.step = 1.0
	spin.suffix = "mm"
	spin.custom_minimum_size.x = 170
	row.add_child(spin)
	_error = Label.new()
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.add_theme_font_size_override("font_size", 15)
	_error.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	v.add_child(_error)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	buttons.add_child(UITheme.button("Einspannen", confirm, 220))
	buttons.add_child(UITheme.button("Abbrechen", close, 180))


func open(m: Node, turned: bool) -> void:
	var player: Node = world.player
	if visible or player.operating != null:
		return
	machine = m
	flip = turned
	var limit: Vector2 = world.clamp_limit(m)
	spin.min_value = limit.x
	spin.max_value = limit.y
	var is_lathe: bool = m is Lathe
	spin.set_value_no_signal(clampf(LATHE_DEPTH if is_lathe else limit.y * 0.5, limit.x, limit.y))
	if is_lathe:
		_title.text = "Umgedreht einspannen" if flip else "Einspannen"
		_info.text = "So viele Millimeter stecken im Futter. Dort kommt der Meißel nicht hin."
		if flip:
			_info.text += " Das andere Ende zeigt nach außen, gespannt wird auf der schon gedrehten Seite."
	else:
		_title.text = "Kopfüber einspannen" if flip else "Einspannen"
		_info.text = "So viele Millimeter stecken zwischen den Backen. Tiefer lässt sich neben dem Teil nicht fräsen."
		if flip:
			_info.text += " Die Unterseite zeigt nach oben."
	_error.text = ""
	visible = true
	_pitch = player.pitch
	player.start_operating(self, player.global_position, player.yaw)


func close() -> void:
	if not visible:
		return
	visible = false
	var player: Node = world.player
	player.stop_operating()
	player.pitch = _pitch


func confirm() -> void:
	if spin.get_line_edit().has_focus():
		spin.apply()
	var keep := machine
	var depth := spin.value
	var turned := flip
	close()
	var err: String = world.finish_clamp(keep, turned, depth)
	if err != "":
		world.hud.show_message(err, Color(1, 0.75, 0.2))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if event.is_action_pressed("pause") or (not typing and event.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
		close()
