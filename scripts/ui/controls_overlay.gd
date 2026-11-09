class_name ControlsOverlay
extends PanelContainer
## Tastenübersicht, unten rechts, öffnet und schließt mit der rechten Alt-Taste. Jede Kategorie ist
## ein Tab: untereinander die Tasten, daneben was sie bewirken. Dazu können Tabs mit Bedienelementen
## der Maschine kommen. Von Dreh- und Fräs-HUD gemeinsam genutzt.

const LEFT := 1
const RIGHT := 2
const MARGIN := -20.0
const WIDTH := 640.0

var tabs: TabContainer
var _key_pages: Array[Control] = []
var _extras: Array[Dictionary] = []


## Welche Alt-Taste das Ereignis betrifft: LEFT, RIGHT oder 0.
static func alt_side(event: InputEvent) -> int:
	if not event is InputEventKey or event.echo:
		return 0
	if event.keycode != KEY_ALT and event.physical_keycode != KEY_ALT:
		return 0
	return RIGHT if event.location == KEY_LOCATION_RIGHT else LEFT


## Kleiner Hinweis unten rechts, solange die Übersicht zu ist.
static func make_chip() -> PanelContainer:
	var chip := PanelContainer.new()
	var box := UITheme.sb(Color(UITheme.ANTHRACITE, 0.72), Color(1, 1, 1, 0.08), 1, 3)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	chip.add_theme_stylebox_override("panel", box)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UITheme.MUTED)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(l)
	dock_bottom_right(chip)
	return chip


## Unten rechts verankern. Erneut aufrufen, damit das Feld nach einer Änderung passend schrumpft.
static func dock_bottom_right(c: Control) -> void:
	c.anchor_left = 1
	c.anchor_right = 1
	c.anchor_top = 1
	c.anchor_bottom = 1
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_left = MARGIN
	c.offset_right = MARGIN
	c.offset_top = MARGIN
	c.offset_bottom = MARGIN


static func set_chip_text(chip: PanelContainer, text: String) -> void:
	(chip.get_child(0) as Label).text = text
	dock_bottom_right(chip)


func _ready() -> void:
	visible = false
	custom_minimum_size.x = WIDTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var title := Label.new()
	title.text = "TASTEN UND BEDIENUNG   ·   ALT RECHTS SCHLIESST"
	title.theme_type_variation = "Section"
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(title)
	tabs = TabContainer.new()
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	tabs.add_theme_font_size_override("font_size", 14)
	# Gleiche Höhe in jedem Tab, damit die Reiter beim Wechsel nicht springen
	tabs.use_hidden_tabs_for_min_size = true
	v.add_child(tabs)
	dock_bottom_right(self)


## Tab mit Bedienelementen, bleibt beim Neuaufbau erhalten und steht hinter den Tastenlisten.
func add_extra(title: String, control: Control) -> void:
	_extras.append({"title": title, "control": control})


## pages = [{"title": String, "rows": [[Taste, Wirkung], ...]}, ...]
## only: nur der Zusatz-Tab mit diesem Titel.
func set_pages(pages: Array, with_extras := true, only := "") -> void:
	var prev := tabs.current_tab
	for p in _key_pages:
		tabs.remove_child(p)
		p.free()
	_key_pages.clear()
	for e in _extras:
		if e["control"].get_parent() == tabs:
			tabs.remove_child(e["control"])
	for page in pages:
		var grid := _key_grid(page["rows"])
		tabs.add_child(grid)
		tabs.set_tab_title(tabs.get_tab_count() - 1, page["title"])
		_key_pages.append(grid)
	if with_extras:
		for e in _extras:
			if only != "" and e["title"] != only:
				continue
			tabs.add_child(e["control"])
			tabs.set_tab_title(tabs.get_tab_count() - 1, e["title"])
	tabs.current_tab = clampi(prev, 0, tabs.get_tab_count() - 1)
	dock_bottom_right(self)


func set_open(on: bool) -> void:
	visible = on
	if on:
		dock_bottom_right(self)


func _key_grid(rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	var cap := UITheme.sb(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.16), 1, 3)
	cap.content_margin_left = 8
	cap.content_margin_right = 8
	cap.content_margin_top = 2
	cap.content_margin_bottom = 2
	for r in rows:
		var key := Label.new()
		key.text = str(r[0])
		key.custom_minimum_size.x = 150
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		key.add_theme_font_size_override("font_size", 15)
		key.add_theme_color_override("font_color", Color.WHITE)
		key.add_theme_stylebox_override("normal", cap)
		grid.add_child(key)
		var text := Label.new()
		text.text = str(r[1])
		text.custom_minimum_size.x = WIDTH - 230.0
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("font_size", 15)
		grid.add_child(text)
	return grid
