class_name ToolSlotDialog
extends CanvasLayer
## Fenster am Werkzeughalter der Drehmaschine: zeigt alle Plätze. Je Platz das Werkzeug aus der Hand
## einspannen, mit freier Hand herausnehmen, gegen das in der Hand tauschen oder einschwenken.

## Spielwelt: player, hud
var world: Node
var machine: Node
var _held_label: Label
var _rows: VBoxContainer
var _error: Label
var _pitch := 0.0
var _shown := ""                  # Stand, den die Zeilen zeigen


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
	v.custom_minimum_size = Vector2(620, 0)
	panel.add_child(v)
	var title := UITheme.title("Werkzeughalter")
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(title)
	_held_label = UITheme.note("", 15)
	v.add_child(_held_label)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	v.add_child(_rows)
	_error = Label.new()
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.add_theme_font_size_override("font_size", 15)
	_error.add_theme_color_override("font_color", UITheme.BAD)
	v.add_child(_error)
	v.add_child(UITheme.button("Schließen", close, 200))


func open(m: Node) -> void:
	var player: Node = world.player
	if visible or player.operating != null:
		return
	machine = m
	_error.text = ""
	_fill()
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


## Zeilen neu aufbauen: je Platz Werkzeug, Aktion und Einschwenken.
func _fill() -> void:
	_shown = _state()
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var held: Dictionary = world.player.held
	_held_label.text = "In der Hand: nichts" if held.is_empty() else "In der Hand: %s" % held["name"]
	for s in machine.SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_rows.add_child(row)
		var id := str(machine.holder[s])
		var l := Label.new()
		l.text = "Platz %d: %s" % [s + 1, "leer" if id == "" else machine.tool_name(id)]
		if s == machine.active_slot:
			l.text += "  (eingeschwenkt)"
			l.add_theme_color_override("font_color", UITheme.ACCENT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var act: String = machine.slot_action_label(s, held)
		var b := UITheme.small_button(act if act != "" else "-", do_slot.bind(s), 150)
		b.disabled = act == ""
		row.add_child(b)
		var sw := UITheme.small_button("Einschwenken", swing.bind(s), 150)
		sw.disabled = id == "" or s == machine.active_slot
		row.add_child(sw)


## Werkzeug in Platz s einspannen, herausnehmen oder tauschen.
func do_slot(s: int) -> void:
	_error.text = ""
	if not machine.slot_action(s, world.player):
		_error.text = _last_warning()
	_fill()


## Platz s einschwenken.
func swing(s: int) -> void:
	_error.text = ""
	if not machine.index_slot(s):
		_error.text = _last_warning()
	_fill()


func _last_warning() -> String:
	var w = machine.get("_last_msg")
	return str(w) if w != null and str(w) != "" else "Geht gerade nicht."


## Halterbestückung, eingeschwenkter Platz und Hand, damit sich das Fenster nach dem Einschwenken nachzieht.
func _state() -> String:
	return "%s|%d|%s" % [str(machine.holder), machine.active_slot, str(world.player.held.get("id", ""))]


func _process(_delta: float) -> void:
	if visible and _state() != _shown:
		_fill()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()
