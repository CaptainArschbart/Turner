class_name PCOverlay
extends CanvasLayer
## Oberfläche des Büro-PCs: Übersicht der Maschinenarten und Handwerkzeuge.

signal closed

const CARD_W := 372.0

var tabs: TabContainer


func _ready() -> void:
	layer = 15
	visible = false

	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UITheme.title("Werkstatt-PC: Maschinenübersicht")
	t.add_theme_color_override("font_color", UITheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UITheme.button("PC verlassen", close, 180))

	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(CARD_W * 3.0 + 80.0, 640)
	v.add_child(tabs)
	_add_tab("Maschinen", _machine_cards())
	_add_tab("Handwerkzeuge", _tool_cards())


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func _add_tab(tab_name: String, cards: Array[Control]) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for c in cards:
		grid.add_child(c)


func _machine_cards() -> Array[Control]:
	var cards: Array[Control] = []
	for m in MachineCatalog.MACHINES:
		var box := VBoxContainer.new()
		box.add_child(UITheme.title(m["title"], 22))
		box.add_child(_text(m["desc"]))
		if m.has("subs"):
			for s in m["subs"]:
				box.add_child(_sub_card(s))
		else:
			box.add_child(_status(""))
		cards.append(_card(box))
	return cards


func _tool_cards() -> Array[Control]:
	var cards: Array[Control] = []
	for h in MachineCatalog.HAND_TOOLS:
		var box := VBoxContainer.new()
		box.add_child(UITheme.title(h["title"], 22))
		box.add_child(_text(h["desc"]))
		box.add_child(_status(""))
		cards.append(_card(box))
	return cards


func _sub_card(s: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var l := UITheme.title(s["title"], 18)
	l.add_theme_color_override("font_color", UITheme.ACCENT)
	box.add_child(l)
	box.add_child(_text(s["desc"]))
	box.add_child(_status(str(s.get("owned", ""))))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.sb(Color(0.13, 0.14, 0.16), Color(0.28, 0.3, 0.33)))
	card.add_child(box)
	return card


func _card(content: Control) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_W
	card.add_theme_stylebox_override("panel", UITheme.sb(Color(0.1, 0.11, 0.12), Color(0.24, 0.26, 0.29)))
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)
	return card


func _text(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", UITheme.MUTED)
	return l


func _status(owned: String) -> Label:
	var l := Label.new()
	l.text = "In der Werkstatt: %s" % owned if owned != "" else "Noch nicht verfügbar"
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if owned != "" else Color(0.45, 0.47, 0.5))
	return l
