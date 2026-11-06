class_name PCOverlay
extends CanvasLayer
## Oberfläche des Büro-PCs: Übersicht der Maschinenarten und Handwerkzeuge.

signal closed

const CARD_W := 372.0
const TOOL_CARD_W := 284.0
const TOOLS_TAB := "Maschinenwerkzeuge"
## Beim ersten Öffnen zeigen: Fräsmaschinen
const START_MACHINE := 1

var tabs: TabContainer
var _machine_group := ButtonGroup.new()
var _machine_buttons: Array[Button] = []
var _tool_grid: GridContainer
var _no_tools: Label
var _machine := -1


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
	_add_machine_tools_tab()
	tabs.tab_changed.connect(_on_tab_changed)


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


func _add_machine_tools_tab() -> void:
	var h := HBoxContainer.new()
	h.name = TOOLS_TAB
	h.add_theme_constant_override("separation", 12)
	tabs.add_child(h)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	h.add_child(list)
	for i in MachineCatalog.MACHINES.size():
		var b := UITheme.button(MachineCatalog.MACHINES[i]["title"], select_machine.bind(i), 240)
		b.toggle_mode = true
		b.button_group = _machine_group
		list.add_child(b)
		_machine_buttons.append(b)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	h.add_child(right)
	_no_tools = _text("Für diese Kategorie sind noch keine Werkzeuge angelegt.")
	right.add_child(_no_tools)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_tool_grid = GridContainer.new()
	_tool_grid.columns = 3
	_tool_grid.add_theme_constant_override("h_separation", 10)
	_tool_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_tool_grid)


## Die 3D-Vorschauen entstehen erst, wenn der Tab zum ersten Mal geöffnet wird.
func _on_tab_changed(i: int) -> void:
	if tabs.get_tab_control(i).name == TOOLS_TAB and _machine < 0:
		select_machine(START_MACHINE)


func select_machine(i: int) -> void:
	_machine = i
	_machine_buttons[i].button_pressed = true
	for c in _tool_grid.get_children():
		_tool_grid.remove_child(c)
		c.queue_free()
	var m: Dictionary = MachineCatalog.MACHINES[i]
	var list := _tools_of(m)
	_no_tools.visible = list.is_empty()
	var owner_name := str(m.get("tool_owner", ""))
	for t in list:
		_tool_grid.add_child(_machine_tool_card(t, owner_name))


func _tools_of(entry: Dictionary) -> Array:
	if entry.get("lathe_tools", false):
		var list := []
		for t in LatheTools.all():
			list.append({"title": "%s %s" % [t["id"], t["name"]], "desc": t["desc"]})
		return list
	return entry.get("tools", [])


func _machine_tool_card(t: Dictionary, owner_name: String) -> Control:
	var box := VBoxContainer.new()
	if t.has("model"):
		var preview := ToolPreview.new()
		preview.model_id = t["model"]
		box.add_child(preview)
	var title := UITheme.title(t["title"], 19)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	box.add_child(_text(t["desc"]))
	box.add_child(_status(owner_name))
	var card := _card(box)
	card.custom_minimum_size.x = TOOL_CARD_W
	return card


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
	if s.has("model"):
		var preview := ToolPreview.new()
		preview.model_id = s["model"]
		box.add_child(preview)
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
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if owned != "" else Color(0.45, 0.47, 0.5))
	return l
