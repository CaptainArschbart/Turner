class_name ClampDialog
extends CanvasLayer
## Fenster beim Einspannen und für das eingespannte Teil. Mit Material in der Hand: Spanntiefe angeben und
## einspannen (Rechtsklick spannt andersherum). Mit freien Händen auf dem Teil: ausspannen, umspannen oder
## nur die Spanntiefe ändern.

const LATHE_DEPTH := 8.0          # voreingestellte Spanntiefe im Futter (mm), Aufträge lassen 10 mm frei

## Spielwelt: player, finish_clamp(machine, flip, depth), clamp_limit(machine), unclamp_part(machine)
var world: Node
var machine: Node
var flip := false
var clamped := false              # Teil sitzt schon in der Maschine, die Hände sind frei
var spin: SpinBox
var _title: Label
var _info: Label
var _error: Label
var _confirm: Button
var _turn: Button
var _out: Button
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
	v.custom_minimum_size = Vector2(520, 0)
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
	_confirm = UITheme.button("Einspannen", confirm, 200)
	buttons.add_child(_confirm)
	_turn = UITheme.button("Umspannen", turn_over, 160)
	buttons.add_child(_turn)
	_out = UITheme.button("Ausspannen", take_out, 160)
	buttons.add_child(_out)
	buttons.add_child(UITheme.button("Abbrechen", close, 140))


func open(m: Node, turned: bool) -> void:
	var player: Node = world.player
	if visible or player.operating != null:
		return
	machine = m
	flip = turned
	clamped = player.carry.is_empty() and m.get("has_part") == true
	var limit: Vector2 = world.clamp_limit(m)
	spin.min_value = limit.x
	spin.max_value = limit.y
	var is_lathe: bool = m is Lathe
	var start: float = LATHE_DEPTH if is_lathe else limit.y * 0.5
	if clamped and float(m.get("clamp_depth")) >= 0.0:
		start = float(m.get("clamp_depth"))
	spin.set_value_no_signal(clampf(start, limit.x, limit.y))
	_turn.visible = clamped
	_out.visible = clamped
	if clamped:
		_title.text = "Eingespanntes Teil"
		_confirm.text = "Umgedreht spannen" if flip else "Spanntiefe ändern"
		_info.text = "Ausspannen: Das Teil kommt in die Hände, zum Abgeben im Qualitätsmanagement oder zum Ablegen in einer Kiste.\nUmspannen: Das Teil umdrehen und mit der eingestellten Spanntiefe neu spannen."
	elif is_lathe:
		_title.text = "Umgedreht einspannen" if flip else "Einspannen"
		_confirm.text = "Einspannen"
		_info.text = "So viele Millimeter stecken im Futter. Dort kommt der Meißel nicht hin."
		if flip:
			_info.text += " Das andere Ende zeigt nach außen, gespannt wird auf der schon gedrehten Seite."
	else:
		_title.text = "Kopfüber einspannen" if flip else "Einspannen"
		_confirm.text = "Einspannen"
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


func _depth() -> float:
	if spin.get_line_edit().has_focus():
		spin.apply()
	return spin.value


## Einspannen bzw. mit der neuen Spanntiefe neu spannen, in der Lage, mit der das Fenster geöffnet wurde.
func confirm() -> void:
	_finish(flip)


## Teil umdrehen und neu spannen.
func turn_over() -> void:
	_finish(true)


func _finish(turned: bool) -> void:
	var keep := machine
	var depth := _depth()
	close()
	var err: String = world.finish_clamp(keep, turned, depth)
	if err != "":
		world.hud.show_message(err, Color(1, 0.75, 0.2))


## Teil aus der Maschine in die Hände nehmen.
func take_out() -> void:
	var keep := machine
	close()
	var err: String = world.unclamp_part(keep)
	if err != "":
		world.hud.show_message(err, Color(1, 0.75, 0.2))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if event.is_action_pressed("pause") or (not typing and event.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
		close()
