class_name PauseMenu
extends CanvasLayer
## Ingame-Menü (Esc): Fortsetzen, Speichern, Laden, Einstellungen, Hauptmenü, Beenden.

var world: Node
var _root: Control
var _main: PanelContainer
var _load_panel: PanelContainer
var _slot_list: SlotList
var _settings: SettingsMenu
var _status: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_root = Control.new()
	_root.theme = UITheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_main = PanelContainer.new()
	center.add_child(_main)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_main.add_child(v)
	var t := UITheme.title("Pause", 38)
	t.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(t)
	v.add_child(UITheme.button("Fortsetzen", close))
	v.add_child(UITheme.button("Spiel speichern", _save))
	v.add_child(UITheme.button("Spiel laden", _show_load))
	v.add_child(UITheme.button("Einstellungen", _show_settings))
	v.add_child(UITheme.button("Hauptmenü", func(): GameState.to_main_menu()))
	v.add_child(UITheme.button("Spiel beenden", func(): get_tree().quit()))
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	v.add_child(_status)

	_load_panel = PanelContainer.new()
	_load_panel.visible = false
	center.add_child(_load_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	_load_panel.add_child(lv)
	lv.add_child(UITheme.title("Spiel laden"))
	_slot_list = SlotList.new()
	_slot_list.mode = "load"
	_slot_list.chosen.connect(func(slot: int): GameState.load_game(slot))
	lv.add_child(_slot_list)
	lv.add_child(UITheme.button("Zurück", _back, 180))

	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.closed.connect(_back)
	center.add_child(_settings)


func open() -> void:
	visible = true
	_status.text = ""
	_back()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	_settings.visible = false
	get_tree().paused = false
	if world and world.has_method("restore_mouse"):
		world.restore_mouse()


func _back() -> void:
	_load_panel.visible = false
	_settings.visible = false
	_main.visible = true


func _show_load() -> void:
	_slot_list.refresh()
	_main.visible = false
	_load_panel.visible = true


func _show_settings() -> void:
	_main.visible = false
	_settings.open()


func _save() -> void:
	if world and world.has_method("save_game") and world.save_game():
		_status.text = "Gespeichert in Platz %d" % (GameState.current_slot + 1)
	else:
		_status.text = "Speichern fehlgeschlagen!"


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if not visible:
		open()
	elif _load_panel.visible:
		_back()
	else:
		close()
