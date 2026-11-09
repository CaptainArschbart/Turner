class_name ConfirmDialog
extends CanvasLayer
## Einfache Ja/Nein-Abfrage in der Spielwelt (z. B. "Maschine wirklich herunterfahren?").
## Hält den Spieler an, solange sie offen ist; [E] oder Esc bricht ab.

var _title: Label
var _text: Label
var _yes: Button
var _player: Node
var _pitch := 0.0
var _on_yes := Callable()


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
	v.custom_minimum_size = Vector2(480, 0)
	panel.add_child(v)
	_title = UITheme.title("")
	_title.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(_title)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 15)
	v.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	_yes = UITheme.button("Ja", confirm, 200)
	buttons.add_child(_yes)
	buttons.add_child(UITheme.button("Abbrechen", close, 160))


## Abfrage öffnen. on_yes wird nur bei "Ja" aufgerufen.
func ask(player: Node, title: String, text: String, yes_text: String, on_yes: Callable) -> void:
	if visible or player == null or player.get("operating") != null:
		return
	_player = player
	_on_yes = on_yes
	_title.text = title
	_text.text = text
	_yes.text = yes_text
	visible = true
	_pitch = float(player.get("pitch"))
	player.start_operating(self, player.global_position, float(player.get("yaw")))


func close() -> void:
	if not visible:
		return
	visible = false
	if _player:
		_player.stop_operating()
		_player.pitch = _pitch


func confirm() -> void:
	var cb := _on_yes
	close()
	if cb.is_valid():
		cb.call()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()
