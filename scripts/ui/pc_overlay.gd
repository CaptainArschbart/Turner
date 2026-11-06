class_name PCOverlay
extends CanvasLayer
## Oberfläche des Büro-PCs: Beim Öffnen zeigt er den Desktop mit den Programmen. Der Shop verkauft
## Maschinen, Werkzeuge, Rohmaterial, Gebäude und Einkauf. Dazu kommen die Aufträge, der Skilltree, die
## Maschinenübersicht, das Ansehen, das Lager und die Entsorgung. Oben lässt sich der Tag beenden.

signal closed

const CARD_W := 372.0
const TOOLS_TAB := "Maschinenwerkzeuge"
const SIZE := Vector2(CARD_W * 3.0 + 80.0, 640)

var tabs: TabContainer            # Reiter im Shop
var overview_tabs: TabContainer   # Reiter in der Maschinenübersicht
var machines_tab: ShopTab
var tool_tab: ToolShopTab
var raw: RawMaterialTab
var site_tab: SiteTab
var shop_tab: ShopTab
var jobs_tab: JobsTab
var waste_tab: WasteTab
var skill_app: SkillTreeApp
var reputation_app: ReputationApp
var dev_app: DevApp
var dev_win: Control
var dev_icon: Button
var day_app: DayApp
var day_win: Control
var desktop: Control
var shop_win: Control
var skill_win: Control
var jobs_win: Control
var overview_win: Control
var reputation_win: Control
var stock_view: StockView
var stock_win: Control
var waste_win: Control
var program := ""                 # "", "shop", "jobs", "skills", "overview", "reputation", "stock" oder "waste"
var world: Node = null
var _title: Label
var _back: Button


## Symbol eines Programms auf dem Desktop.
class ProgramIcon extends Control:
	var kind := "shop"

	func _ready() -> void:
		custom_minimum_size = Vector2(96, 96)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		if kind == "dev":
			# Spitze Klammern
			var d := Color(0.6, 0.95, 0.75)
			draw_polyline(PackedVector2Array([c + Vector2(-14, -24), c + Vector2(-36, 0), c + Vector2(-14, 24)]), d, 6.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(14, -24), c + Vector2(36, 0), c + Vector2(14, 24)]), d, 6.0, true)
			draw_line(c + Vector2(8, -28), c + Vector2(-8, 28), d, 5.0, true)
		elif kind == "day":
			# Kalenderblatt
			var page := Color(0.9, 0.92, 0.95)
			draw_rect(Rect2(c + Vector2(-34, -30), Vector2(68, 66)), page)
			draw_rect(Rect2(c + Vector2(-34, -36), Vector2(68, 16)), Color(0.85, 0.3, 0.25))
			for row in 3:
				for col in 4:
					draw_rect(Rect2(c + Vector2(-26 + col * 14, -12 + row * 14), Vector2(9, 9)), Color(0.35, 0.4, 0.48))
		elif kind == "stock":
			# Regal mit Stangen
			var s := Color(0.6, 0.7, 0.85)
			draw_rect(Rect2(c + Vector2(-38, -36), Vector2(6, 74)), s)
			draw_rect(Rect2(c + Vector2(32, -36), Vector2(6, 74)), s)
			for i in 3:
				var y := -28 + i * 26
				draw_rect(Rect2(c + Vector2(-38, y + 12), Vector2(76, 5)), Color(0.95, 0.55, 0.15))
				for k in 4:
					draw_circle(c + Vector2(-20 + k * 13, y + 6), 5.5, Color(0.8, 0.82, 0.85))
		elif kind == "waste":
			# Container mit Spänen
			var k := Color(0.55, 0.62, 0.68)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-40, -12), c + Vector2(40, -12), c + Vector2(30, 32), c + Vector2(-30, 32)]), k)
			for i in 7:
				draw_arc(c + Vector2(-27 + i * 9, -14 - (i % 2) * 5), 7.0, PI, TAU, 8, Color(0.92, 0.75, 0.3), 2.5, true)
			draw_circle(c + Vector2(-18, 36), 5.0, Color(0.2, 0.22, 0.25))
			draw_circle(c + Vector2(18, 36), 5.0, Color(0.2, 0.22, 0.25))
		elif kind == "reputation":
			# Stern
			var points := PackedVector2Array()
			for i in 10:
				var r := 40.0 if i % 2 == 0 else 17.0
				var a := -PI / 2.0 + i * TAU / 10.0
				points.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(points, Color(0.98, 0.8, 0.25))
		elif kind == "jobs":
			# Auftragszettel
			var p := Color(0.85, 0.88, 0.92)
			draw_rect(Rect2(c + Vector2(-26, -36), Vector2(52, 72)), p)
			for i in 5:
				draw_rect(Rect2(c + Vector2(-18, -26 + i * 12), Vector2(36 if i % 2 == 0 else 24, 4)), Color(0.3, 0.35, 0.42))
		elif kind == "overview":
			# Maschine: Bett mit Spindelkasten und Reitstock
			var b := Color(0.55, 0.72, 0.95)
			draw_rect(Rect2(c + Vector2(-40, 8), Vector2(80, 12)), b)
			draw_rect(Rect2(c + Vector2(-40, -24), Vector2(26, 32)), b)
			draw_rect(Rect2(c + Vector2(20, -12), Vector2(20, 20)), b)
			draw_rect(Rect2(c + Vector2(-14, -8), Vector2(34, 6)), Color(b, 0.6))
			draw_rect(Rect2(c + Vector2(-34, 20), Vector2(14, 16)), Color(b, 0.7))
			draw_rect(Rect2(c + Vector2(20, 20), Vector2(14, 16)), Color(b, 0.7))
		elif kind == "shop":
			# Einkaufswagen
			var w := Color(0.95, 0.72, 0.3)
			draw_polyline(PackedVector2Array([c + Vector2(-38, -30), c + Vector2(-24, -30), c + Vector2(-12, 16), c + Vector2(26, 16)]), w, 5.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-20, -20), c + Vector2(36, -20), c + Vector2(28, 6), c + Vector2(-13, 6)]), Color(w, 0.45))
			draw_circle(c + Vector2(-8, 28), 6.0, w)
			draw_circle(c + Vector2(22, 28), 6.0, w)
		else:
			# Baum aus Knoten
			var g := Color(0.45, 0.85, 0.55)
			var root := c + Vector2(0, 32)
			var mid := [c + Vector2(-24, 2), c + Vector2(24, 2)]
			var top := [c + Vector2(-36, -30), c + Vector2(-10, -30), c + Vector2(12, -30), c + Vector2(36, -30)]
			for i in 2:
				draw_line(root, mid[i], g, 3.0, true)
				draw_line(mid[i], top[i * 2], g, 3.0, true)
				draw_line(mid[i], top[i * 2 + 1], g, 3.0, true)
			draw_circle(root, 8.0, g)
			for p in mid + top:
				draw_circle(p, 6.5, g)


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
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	_title = UITheme.title("Werkstatt-PC")
	_title.add_theme_color_override("font_color", UITheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_back = UITheme.button("Zum Desktop", show_desktop, 180)
	head.add_child(_back)
	head.add_child(UITheme.button("PC verlassen", close, 180))

	desktop = _build_desktop()
	v.add_child(desktop)

	tabs = TabContainer.new()
	tabs.custom_minimum_size = SIZE
	shop_win = tabs
	v.add_child(tabs)
	machines_tab = ShopTab.new()
	machines_tab.machines = true
	machines_tab.name = "Maschinen"
	tabs.add_child(machines_tab)
	tool_tab = ToolShopTab.new()
	tool_tab.name = TOOLS_TAB
	tabs.add_child(tool_tab)
	raw = RawMaterialTab.new()
	raw.name = "Rohmaterial"
	tabs.add_child(raw)
	site_tab = SiteTab.new()
	site_tab.name = "Gebäude"
	tabs.add_child(site_tab)
	shop_tab = ShopTab.new()
	shop_tab.name = "Einkauf"
	tabs.add_child(shop_tab)

	dev_app = DevApp.new()
	dev_app.custom_minimum_size = SIZE
	dev_win = dev_app
	v.add_child(dev_app)

	day_app = DayApp.new()
	day_app.custom_minimum_size = SIZE
	day_win = day_app
	v.add_child(day_app)

	stock_view = StockView.new()
	stock_view.custom_minimum_size = SIZE
	stock_win = stock_view
	v.add_child(stock_view)

	waste_tab = WasteTab.new()
	waste_tab.custom_minimum_size = SIZE
	waste_win = waste_tab
	v.add_child(waste_tab)

	jobs_tab = JobsTab.new()
	jobs_tab.custom_minimum_size = SIZE
	jobs_win = jobs_tab
	v.add_child(jobs_tab)

	skill_app = SkillTreeApp.new()
	skill_app.custom_minimum_size = SIZE
	skill_win = skill_app
	v.add_child(skill_app)

	overview_tabs = TabContainer.new()
	overview_tabs.custom_minimum_size = SIZE
	overview_win = overview_tabs
	v.add_child(overview_tabs)
	_add_tab("Maschinen", _machine_cards())
	_add_tab("Handwerkzeuge", _tool_cards())

	reputation_app = ReputationApp.new()
	reputation_app.custom_minimum_size = SIZE
	reputation_win = reputation_app
	v.add_child(reputation_app)
	show_desktop()


func _build_desktop() -> Control:
	var d := PanelContainer.new()
	d.custom_minimum_size = SIZE
	d.add_theme_stylebox_override("panel", UITheme.sb(Color(0.09, 0.2, 0.3), Color(0.2, 0.32, 0.42), 1, 4))
	var h := GridContainer.new()
	h.columns = 5
	h.add_theme_constant_override("h_separation", 10)
	h.add_theme_constant_override("v_separation", 10)
	d.add_child(h)
	h.add_child(_desktop_icon("shop", "Shop", "Maschinen, Werkzeuge,\nMaterial, Gebäude"))
	h.add_child(_desktop_icon("jobs", "Aufträge", "Angebote ansehen\nund annehmen"))
	h.add_child(_desktop_icon("skills", "Skilltree", "Maschinen, Werkstoffe\nund Werkzeuge"))
	h.add_child(_desktop_icon("overview", "Maschinen", "Alle Maschinen, die es\nim Spiel gibt"))
	h.add_child(_desktop_icon("reputation", "Ansehen", "Ruf der Werkstatt,\nFristen, Vergütung"))
	dev_icon = _desktop_icon("dev", "Entwickler", "Alle Aufträge prüfen,\nnur im Testmodus")
	h.add_child(dev_icon)
	h.add_child(_desktop_icon("day", "Tagesbericht", "Tag starten und beenden,\nGewinn und Verlust"))
	h.add_child(_desktop_icon("stock", "Lager", "Was in den Regalen\nliegt und wo"))
	h.add_child(_desktop_icon("waste", "Entsorgung", "Spänecontainer im Hof\nabholen lassen"))
	return d


func _desktop_icon(kind: String, title: String, text: String) -> Button:
	var b := Button.new()
	b.name = "Programm_%s" % kind
	b.custom_minimum_size = Vector2(222, 210)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.focus_mode = Control.FOCUS_NONE
	b.flat = false
	var clear := UITheme.sb(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 1, 8)
	b.add_theme_stylebox_override("normal", clear)
	b.add_theme_stylebox_override("hover", UITheme.sb(Color(1, 1, 1, 0.14), UITheme.ACCENT, 2, 8))
	b.add_theme_stylebox_override("pressed", UITheme.sb(Color(1, 1, 1, 0.2), UITheme.ACCENT, 2, 8))
	b.pressed.connect(open_program.bind(kind))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var icon := ProgramIcon.new()
	icon.kind = kind
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	var t := UITheme.title(title, 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var s := _text(text)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(s)
	return b


func open() -> void:
	visible = true
	show_desktop()
	refresh_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	if world != null and world.drawing != null:
		world.drawing.close()
	closed.emit()


func show_desktop() -> void:
	program = ""
	if world != null and world.drawing != null:
		world.drawing.close()
	desktop.visible = true
	shop_win.visible = false
	skill_win.visible = false
	jobs_win.visible = false
	overview_win.visible = false
	reputation_win.visible = false
	stock_win.visible = false
	day_win.visible = false
	dev_win.visible = false
	waste_win.visible = false
	_back.visible = false
	_title.text = "Werkstatt-PC"


## Programm vom Desktop starten.
func open_program(kind: String) -> void:
	program = kind
	desktop.visible = false
	shop_win.visible = kind == "shop"
	skill_win.visible = kind == "skills"
	jobs_win.visible = kind == "jobs"
	overview_win.visible = kind == "overview"
	reputation_win.visible = kind == "reputation"
	stock_win.visible = kind == "stock"
	day_win.visible = kind == "day"
	dev_win.visible = kind == "dev"
	waste_win.visible = kind == "waste"
	_back.visible = true
	_title.text = {"shop": "Shop", "jobs": "Aufträge", "skills": "Skilltree", "overview": "Maschinenübersicht", "reputation": "Ansehen", "stock": "Lager", "waste": "Entsorgung", "day": "Tagesbericht", "dev": "Entwickler"}[kind]
	refresh_all()


func refresh_all() -> void:
	raw.refresh()
	stock_view.refresh()
	day_app.refresh()
	# Das Entwicklerprogramm gibt es nur im Testmodus
	var dev_on: bool = world != null and world.free_mode
	dev_icon.visible = dev_on
	if program == "dev" and not dev_on:
		show_desktop()
	dev_app.refresh()
	site_tab.refresh()
	shop_tab.refresh()
	machines_tab.refresh()
	tool_tab.refresh()
	jobs_tab.refresh()
	waste_tab.refresh()
	skill_app.refresh()
	reputation_app.refresh()


## Lagerbestand hat sich geändert.
func stock_changed() -> void:
	raw.refresh()
	stock_view.refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Beim Eintippen von Maßen schließt die Interaktionstaste den PC nicht
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if event.is_action_pressed("interact") and not typing:
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		# Esc führt aus dem Programm zurück auf den Desktop, von dort aus dem PC
		if program != "":
			show_desktop()
		else:
			close()


func _add_tab(tab_name: String, cards: Array[Control]) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overview_tabs.add_child(scroll)
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
			box.add_child(_status(str(m.get("owned", ""))))
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
	l.text = "Im Spiel: %s" % owned if owned != "" else "Noch nicht bedienbar"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if owned != "" else Color(0.45, 0.47, 0.5))
	return l
