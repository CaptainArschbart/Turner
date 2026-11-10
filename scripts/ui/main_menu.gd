extends Control
## Hauptmenü: filmische Nahaufnahme einer Zerspanung im Hintergrund (MenuBackdrop),
## links Wortmarke und Menüeinträge, rechts die Unterfenster (Speicherplätze, Einstellungen).

var _main_box: VBoxContainer
var _menu_col: Control
var _right: CenterContainer
var _slots_panel: PanelContainer
var _slot_list: SlotList
var _name_edit: LineEdit
var _slot_title: Label
var _settings: SettingsMenu
var _backdrop: MenuBackdrop
var _buttons: Array[Button] = []
var _fade: ColorRect
var _lang_panel: PanelContainer
var _lang_list: VBoxContainer
var _lang_button: Button


func _ready() -> void:
	theme = UITheme.menu()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_background()
	_build_ui()
	_intro()


func _build_background() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	svc.add_child(sv)
	_backdrop = MenuBackdrop.new()
	sv.add_child(_backdrop)
	_backdrop.camera.make_current()

	# Lesbarkeit links, Vignette rundum, leichter Boden-Verlauf
	add_child(_gradient_rect([Color(0.012, 0.016, 0.024, 0.92), Color(0.012, 0.016, 0.024, 0.55),
		Color(0.012, 0.016, 0.024, 0.0)], [0.0, 0.3, 0.62], Vector2(0, 0), Vector2(1, 0)))
	add_child(_gradient_rect([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.7)], [0.0, 0.55, 1.0],
		Vector2(0.5, 0.5), Vector2(1.08, 1.08), true))
	add_child(_gradient_rect([Color(0, 0, 0, 0.0), Color(0.01, 0.015, 0.03, 0.6)], [0.7, 1.0],
		Vector2(0, 0), Vector2(0, 1)))


func _gradient_rect(cols: Array, offs: Array, from: Vector2, to: Vector2, radial := false) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols)
	g.offsets = PackedFloat32Array(offs)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 512
	gt.height = 512
	gt.fill = GradientTexture2D.FILL_RADIAL if radial else GradientTexture2D.FILL_LINEAR
	gt.fill_from = from
	gt.fill_to = to
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _build_ui() -> void:
	# ---- linke Spalte
	var margin := MarginContainer.new()
	margin.anchor_bottom = 1.0
	margin.offset_right = 620
	margin.add_theme_constant_override("margin_left", 104)
	margin.add_theme_constant_override("margin_top", 92)
	margin.add_theme_constant_override("margin_bottom", 64)
	add_child(margin)
	_menu_col = margin
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 0)
	margin.add_child(_main_box)

	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 18)
	_main_box.add_child(brand)
	var bar := ColorRect.new()
	bar.color = UITheme.BLUE_HI
	bar.custom_minimum_size = Vector2(56, 5)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brand.add_child(bar)
	var t := Label.new()
	t.text = "TURNER"
	t.add_theme_font_override("font", UITheme.font(700, 12))
	t.add_theme_font_size_override("font_size", 112)
	t.add_theme_color_override("font_color", Color.WHITE)
	t.add_theme_constant_override("shadow_offset_y", 4)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	brand.add_child(t)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_box.add_child(spacer)

	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", 4)
	_main_box.add_child(items)
	if SaveManager.any_save():
		var slot := SaveManager.latest_slot()
		var d := SaveManager.read_slot(slot)
		var sub := "%s  ·  Spielzeit %s" % [str(d.get("name", "Werkstatt")), SaveManager.format_time(float(d.get("play_time", 0)))]
		var cont := UITheme.menu_button("Fortsetzen", func(): GameState.load_game(slot), sub)
		for l in cont.find_children("*", "Label", true, false):
			if l.text == sub:
				l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Name des Spielstands
		_buttons.append(cont)
	_buttons.append(UITheme.menu_button("Neues Spiel", func(): _show_slots("new")))
	_buttons.append(UITheme.menu_button("Spiel laden", func(): _show_slots("load")))
	_buttons.append(UITheme.menu_button("Einstellungen", _show_settings))
	_lang_button = UITheme.menu_button("Sprache", _show_languages, Dialects.display_name(Settings.language()))
	_lang_sub().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_buttons.append(_lang_button)
	_buttons.append(UITheme.menu_button("Beenden", func(): get_tree().quit()))
	for b in _buttons:
		items.add_child(b)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 56
	_main_box.add_child(spacer2)
	var ver := Label.new()
	ver.text = "v0.1   ·   Godot %s" % Engine.get_version_info()["string"]
	ver.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ver.add_theme_font_override("font", UITheme.font(400, 1))
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.32))
	ver.add_theme_font_size_override("font_size", 13)
	_main_box.add_child(ver)

	# ---- rechte Seite: Unterfenster
	_right = CenterContainer.new()
	_right.anchor_left = 0.0
	_right.anchor_right = 1.0
	_right.anchor_bottom = 1.0
	_right.offset_left = 600
	_right.offset_right = -24
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right)

	_slots_panel = PanelContainer.new()
	_slots_panel.visible = false
	_right.add_child(_slots_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	_slots_panel.add_child(v)
	var head := UITheme.heading("Spiel laden")
	_slot_title = head.get_child(1)
	v.add_child(head)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name des Spielstands"
	_name_edit.text = "Meine Werkstatt"
	_name_edit.custom_minimum_size.y = 44
	v.add_child(_name_edit)
	_slot_list = SlotList.new()
	_slot_list.chosen.connect(_on_slot_chosen)
	v.add_child(_slot_list)
	var back := UITheme.button("Zurück", _close_panels, 180)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(back)

	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.closed.connect(_close_panels)
	_right.add_child(_settings)

	_lang_panel = PanelContainer.new()
	_lang_panel.visible = false
	_right.add_child(_lang_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 16)
	_lang_panel.add_child(lv)
	lv.add_child(UITheme.heading("Sprache"))
	_lang_list = VBoxContainer.new()
	_lang_list.add_theme_constant_override("separation", 2)
	lv.add_child(_lang_list)
	var lback := UITheme.button("Zurück", _close_panels, 180)
	lback.size_flags_horizontal = Control.SIZE_SHRINK_END
	lv.add_child(lback)

	_fade = ColorRect.new()
	_fade.color = Color(0.01, 0.012, 0.018)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


## Einblenden: Bild aus Schwarz, dann Wortmarke und Einträge nacheinander.
func _intro() -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_fade, "color:a", 0.0, 1.6)
	tw.tween_callback(func(): _fade.visible = false)
	UITheme.reveal(_main_box.get_child(0), 0.35, 0.9)
	for i in _buttons.size():
		UITheme.reveal(_buttons[i], 0.6 + i * 0.08, 0.5)
	UITheme.reveal(_main_box.get_child(_main_box.get_child_count() - 1), 1.1, 0.8)
	if not _buttons.is_empty():
		_buttons[0].grab_focus.call_deferred()


func _open_panel(p: Control) -> void:
	p.visible = true
	UITheme.reveal(p, 0.0, 0.28)
	var tw := create_tween()
	tw.tween_property(_menu_col, "modulate", Color(1, 1, 1, 0.5), 0.25)


func _show_slots(mode: String) -> void:
	_settings.visible = false
	_lang_panel.visible = false
	_slot_list.mode = mode
	_slot_list.refresh()
	_slot_title.text = "Neues Spiel" if mode == "new" else "Spiel laden"
	_name_edit.visible = mode == "new"
	_open_panel(_slots_panel)


func _show_settings() -> void:
	_slots_panel.visible = false
	_lang_panel.visible = false
	_settings.open()
	_open_panel(_settings)


func _close_panels() -> void:
	_slots_panel.visible = false
	_settings.visible = false
	_lang_panel.visible = false
	var tw := create_tween()
	tw.tween_property(_menu_col, "modulate", Color.WHITE, 0.25)


## Sprachauswahl: Namen und Untertitel stehen schon in der jeweiligen Sprache, sie werden nicht übersetzt.
func _show_languages() -> void:
	_slots_panel.visible = false
	_settings.visible = false
	_fill_languages()
	_open_panel(_lang_panel)
	_focus_language.call_deferred()


func _fill_languages() -> void:
	for ch in _lang_list.get_children():
		_lang_list.remove_child(ch)
		ch.queue_free()
	for l in Dialects.LANGS:
		var code: String = l[0]
		var mark := "   ✓" if code == Settings.language() else ""
		var b := UITheme.menu_button(str(l[1]) + mark, func(): _choose_language(code), str(l[2]), 420.0)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.name = "lang_" + code
		_lang_list.add_child(b)


func _choose_language(code: String) -> void:
	Settings.set_language(code)
	_lang_sub().text = Dialects.display_name(code)
	_fill_languages()
	_focus_language.call_deferred()


func _focus_language() -> void:
	var b := _lang_list.get_node_or_null("lang_" + Settings.language()) as Control
	if b and b.is_inside_tree() and _lang_panel.visible:
		b.grab_focus()


## Untertitel des Menüeintrags "Sprache" (zeigt die aktuelle Sprache).
func _lang_sub() -> Label:
	for ch in _lang_button.get_children():
		if ch is VBoxContainer and ch.get_child_count() > 1:
			return ch.get_child(1)
	return null


func _on_slot_chosen(slot: int) -> void:
	if _slot_list.mode == "new":
		var n := _name_edit.text.strip_edges()
		GameState.new_game(slot, n if n != "" else "Werkstatt %d" % (slot + 1))
	else:
		GameState.load_game(slot)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and (_slots_panel.visible or _lang_panel.visible):
		_close_panels()
		get_viewport().set_input_as_handled()
