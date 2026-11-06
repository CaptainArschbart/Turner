class_name PauseMenu
extends CanvasLayer
## Ingame-Menü (Esc): Fortsetzen, Speichern, Laden, Einstellungen, Hauptmenü, Beenden.
## Spielbild wird weichgezeichnet und abgedunkelt, links eine Seitenleiste im Menüstil.

const SIDE_W := 440.0

var world: Node
var _root: Control
var _side: PanelContainer
var _main: VBoxContainer
var _buttons: Array[Button] = []
var _load_panel: PanelContainer
var _slot_list: SlotList
var _settings: SettingsMenu
var _status: Label
var _tw: Tween


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_root = Control.new()
	_root.theme = UITheme.menu()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Weichzeichner + Abdunkelung des Spielbilds
	var blur := ColorRect.new()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lod = 3.2;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb;
	float v = smoothstep(1.1, 0.35, length(UV - vec2(0.5)));
	c = mix(c, vec3(0.015, 0.02, 0.03), 0.55 + 0.25 * (1.0 - v));
	COLOR = vec4(c, 1.0);
}
"""
	mat.shader = sh
	blur.material = mat
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(blur)

	# Seitenleiste
	_side = PanelContainer.new()
	var ss := UITheme.panel_style(false)
	ss.set_corner_radius_all(0)
	ss.bg_color = Color(UITheme.ANTHRACITE, 0.94)
	ss.border_color = Color(1, 1, 1, 0.06)
	ss.set_border_width_all(0)
	ss.border_width_right = 1
	ss.shadow_offset = Vector2(8, 0)
	ss.content_margin_left = 64
	ss.content_margin_right = 40
	ss.content_margin_top = 80
	ss.content_margin_bottom = 48
	_side.add_theme_stylebox_override("panel", ss)
	_side.anchor_bottom = 1.0
	_side.offset_right = SIDE_W
	_root.add_child(_side)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 0)
	_side.add_child(_main)
	_main.add_child(UITheme.heading("PAUSE", 40))
	var where := Label.new()
	where.name = "Where"
	where.add_theme_font_override("font", UITheme.font(400, 1))
	where.add_theme_font_size_override("font_size", 15)
	where.add_theme_color_override("font_color", UITheme.SOFT)
	_main.add_child(where)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main.add_child(sp)
	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", 2)
	_main.add_child(items)
	_buttons.append(UITheme.menu_button("Fortsetzen", close, "", 320))
	_buttons.append(UITheme.menu_button("Spiel speichern", _save, "", 320))
	_buttons.append(UITheme.menu_button("Spiel laden", _show_load, "", 320))
	_buttons.append(UITheme.menu_button("Einstellungen", _show_settings, "", 320))
	_buttons.append(UITheme.menu_button("Hauptmenü", func(): GameState.to_main_menu(), "", 320))
	_buttons.append(UITheme.menu_button("Spiel beenden", func(): get_tree().quit(), "", 320))
	for b in _buttons:
		items.add_child(b)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main.add_child(sp2)
	_status = Label.new()
	_status.add_theme_font_override("font", UITheme.font(500, 1))
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55))
	_main.add_child(_status)
	var hint := Label.new()
	hint.text = "Esc  ·  zurück zum Spiel"
	hint.add_theme_font_override("font", UITheme.font(400, 1))
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	_main.add_child(hint)

	# Unterfenster rechts
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.offset_left = SIDE_W
	_root.add_child(center)

	_load_panel = PanelContainer.new()
	_load_panel.visible = false
	center.add_child(_load_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 16)
	_load_panel.add_child(lv)
	lv.add_child(UITheme.heading("Spiel laden"))
	_slot_list = SlotList.new()
	_slot_list.mode = "load"
	_slot_list.chosen.connect(func(slot: int): GameState.load_game(slot))
	lv.add_child(_slot_list)
	var back := UITheme.button("Zurück", _back, 180)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	lv.add_child(back)

	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.closed.connect(_back)
	center.add_child(_settings)


func open() -> void:
	visible = true
	_status.text = ""
	var where := _main.find_child("Where", false, false) as Label
	var d := SaveManager.read_slot(GameState.current_slot)
	where.text = "%s  ·  Platz %d" % [str(d.get("name", "Werkstatt")), GameState.current_slot + 1]
	_back()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Einblenden: Bild weich, Seitenleiste gleitet herein
	if _tw:
		_tw.kill()
	_root.modulate.a = 0.0
	_side.offset_left = -60.0
	_side.offset_right = SIDE_W - 60.0
	_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tw.tween_property(_root, "modulate:a", 1.0, 0.22)
	_tw.tween_property(_side, "offset_left", 0.0, 0.32)
	_tw.tween_property(_side, "offset_right", SIDE_W, 0.32)
	for i in _buttons.size():
		UITheme.reveal(_buttons[i], 0.06 + i * 0.035, 0.25)
	_buttons[0].grab_focus.call_deferred()


func close() -> void:
	visible = false
	_settings.visible = false
	get_tree().paused = false
	if world and world.has_method("restore_mouse"):
		world.restore_mouse()


func _back() -> void:
	_load_panel.visible = false
	_settings.visible = false
	_main.modulate = Color.WHITE


func _show_load() -> void:
	_slot_list.refresh()
	_settings.visible = false
	_load_panel.visible = true
	UITheme.reveal(_load_panel, 0.0, 0.25)


func _show_settings() -> void:
	_load_panel.visible = false
	_settings.open()
	UITheme.reveal(_settings, 0.0, 0.25)


func _save() -> void:
	if world and world.has_method("save_game") and world.save_game():
		_status.text = "✓  Gespeichert in Platz %d" % (GameState.current_slot + 1)
		_status.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55))
	else:
		_status.text = "Speichern fehlgeschlagen!"
		_status.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	UITheme.reveal(_status, 0.0, 0.3)


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
