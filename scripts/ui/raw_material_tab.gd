class_name RawMaterialTab
extends VBoxContainer
## Rohmaterial am Büro-PC: Stangenmaterial (Rund, Vierkant) und Fertigschnitt, darin je ein Tab pro
## Materialgruppe mit den Werkstoffen. Dazu das Lager, aus dem Material an die Maschinen geht.
## Stangen sind immer 3 m lang, einstellbar ist nur der Querschnitt. Fertigschnitt hat freie Maße.

const CUT_MIN := StockView.CUT_MIN
const FIELD_MAX := 2000.0

## Spielwelt: money, stock, order_material(spec), load_stock(index, length)
var shop: Node = null
var kinds: TabContainer
var pages: Dictionary = {}        # Art -> Bestellseite
var _money: Label
var _needs: Label


## Bestellseite einer Materialart: links Gruppen und Werkstoffe, rechts Foto und Bestellung.
class OrderPage extends HBoxContainer:
	var owner_tab: RawMaterialTab
	var kind := ""
	var mat_id := Materials.DEFAULT
	var groups: TabContainer
	var fields: Dictionary = {}
	var qty: SpinBox
	var buttons: Dictionary = {}
	var _pick := ButtonGroup.new()
	var _photo: TextureRect
	var _name: Label
	var _info: Label
	var _price: Label
	var _result: Label
	var order_button: Button

	func _ready() -> void:
		add_theme_constant_override("separation", 12)
		groups = TabContainer.new()
		groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		groups.add_theme_font_size_override("font_size", 14)
		groups.tab_changed.connect(_on_group_changed)
		add_child(groups)
		for g in Materials.GROUPS:
			groups.add_child(_group_page(g))
			groups.set_tab_title(groups.get_tab_count() - 1, g["title"])
		add_child(_order_panel())
		select(Materials.DEFAULT)

	func _group_page(g: Dictionary) -> Control:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)
		for m in g["list"]:
			var id := str(m["id"])
			var nr := str(m["nr"])
			var b := Button.new()
			b.text = str(m["name"]) if nr == "-" else "%s\n%s" % [m["name"], nr]
			b.toggle_mode = true
			b.button_group = _pick
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(220, 58)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(select.bind(id))
			grid.add_child(b)
			buttons[id] = b
		return scroll

	func _order_panel() -> Control:
		var v := VBoxContainer.new()
		v.custom_minimum_size.x = 400
		v.add_theme_constant_override("separation", 6)
		_photo = TextureRect.new()
		_photo.custom_minimum_size = Vector2(400, 150)
		_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(_photo)
		_name = Label.new()
		_name.add_theme_font_size_override("font_size", 20)
		_name.add_theme_color_override("font_color", UITheme.ACCENT)
		v.add_child(_name)
		_info = Label.new()
		_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info.add_theme_font_size_override("font_size", 14)
		_info.add_theme_color_override("font_color", UITheme.MUTED)
		v.add_child(_info)
		var form := GridContainer.new()
		form.columns = 2
		form.add_theme_constant_override("h_separation", 12)
		form.add_theme_constant_override("v_separation", 4)
		v.add_child(form)
		match kind:
			Materials.KIND_ROUND:
				_field(form, "d", "Durchmesser (mm)", 40.0)
				_fixed(form)
			Materials.KIND_SQUARE:
				_field(form, "w", "Breite (mm)", 60.0)
				_field(form, "h", "Höhe (mm)", 40.0)
				_fixed(form)
			_:
				_field(form, "l", "Länge (mm)", 100.0)
				_field(form, "w", "Breite (mm)", 60.0)
				_field(form, "h", "Höhe (mm)", 40.0)
		qty = _spin(1.0, 99.0, 1.0)
		form.add_child(_form_label("Stückzahl"))
		form.add_child(qty)
		_price = Label.new()
		_price.add_theme_font_size_override("font_size", 16)
		v.add_child(_price)
		order_button = UITheme.button("Bestellen", order, 200)
		order_button.custom_minimum_size.y = 40
		v.add_child(order_button)
		_result = Label.new()
		_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_result.add_theme_font_size_override("font_size", 14)
		v.add_child(_result)
		return v

	func _form_label(t: String) -> Label:
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", 15)
		return l

	func _spin(lo: float, hi: float, value: float) -> SpinBox:
		var s := SpinBox.new()
		s.min_value = lo
		s.max_value = hi
		s.step = 1.0
		s.value = value
		s.update_on_text_changed = true
		s.custom_minimum_size.x = 150
		s.value_changed.connect(func(_x: float): refresh())
		return s

	func _field(form: GridContainer, key: String, title: String, value: float) -> void:
		var s := _spin(1.0, FIELD_MAX, value)
		fields[key] = s
		form.add_child(_form_label(title))
		form.add_child(s)

	func _fixed(form: GridContainer) -> void:
		form.add_child(_form_label("Länge"))
		var l := _form_label("3000 mm (Stange)")
		l.add_theme_color_override("font_color", UITheme.MUTED)
		form.add_child(l)

	func material_id() -> String:
		return mat_id

	func _on_group_changed(i: int) -> void:
		# Beim Wechsel der Gruppe den ersten Werkstoff anbieten, außer er ist schon gewählt
		var g: Dictionary = Materials.GROUPS[i]
		if str(Materials.group_of(mat_id)["id"]) != str(g["id"]):
			select(str(g["list"][0]["id"]))

	func select(id: String) -> void:
		mat_id = id
		var g := Materials.group_of(id)
		var gi := Materials.GROUPS.find(g)
		if groups.current_tab != gi:
			groups.current_tab = gi
		(buttons[id] as Button).button_pressed = true
		_show_photo()
		_name.text = Materials.label(id)
		var drill := Materials.mill_data(id, MillTools.by_id("B10"), 1000.0)
		var endm := Materials.mill_data(id, MillTools.TOOLS[2], 1000.0)
		_info.text = "%s\nISO %s, Fräsgruppe %s, Dichte %.2f g/cm³\nvc Schaftfräser %d-%d, Bohrer %d-%d m/min" % [
			g["text"], g["iso"], Materials.mill_group(id), float(g["dens"]),
			int(Materials.MILL_VC[Materials.mill_group(id)][0]), int(endm["vmax"]), int(float(g["drill_vc"]) * 0.7), int(drill["vmax"])]
		refresh()

	func _show_photo() -> void:
		var p := Materials.photo(mat_id, kind)
		var tex := load(str(p["path"])) as Texture2D
		if tex and float(p["crop"]) < 1.0:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(0, 0, tex.get_width(), tex.get_height() * float(p["crop"]))
			tex = at
		_photo.texture = tex
		_photo.modulate = p["tint"]

	func spec() -> Dictionary:
		var s := {"material": mat_id, "kind": kind, "qty": int(qty.value)}
		match kind:
			Materials.KIND_ROUND:
				s.merge({"d": fields["d"].value, "w": 0.0, "h": 0.0, "l": Materials.BAR_LEN})
			Materials.KIND_SQUARE:
				s.merge({"d": 0.0, "w": fields["w"].value, "h": fields["h"].value, "l": Materials.BAR_LEN})
			_:
				s.merge({"d": 0.0, "w": fields["w"].value, "h": fields["h"].value, "l": fields["l"].value})
		return s

	func total() -> int:
		var s := spec()
		return Materials.price(mat_id, kind, s["d"], s["w"], s["h"], s["l"]) * int(s["qty"])

	## Gesperrte Werkstoffgruppen lassen sich nicht wählen.
	func apply_locks(skills: Skills) -> void:
		for i in Materials.GROUPS.size():
			groups.set_tab_disabled(i, not skills.has("mat_%s" % Materials.GROUPS[i]["id"]))
		if not skills.has(Skills.material_node(mat_id)):
			select(Materials.DEFAULT)

	func refresh() -> void:
		if _price == null:
			return
		var s := spec()
		var kg := Materials.weight_kg(mat_id, kind, s["d"], s["w"], s["h"], s["l"]) * int(s["qty"])
		var free: bool = owner_tab != null and owner_tab.shop != null and owner_tab.shop.free_mode
		_price.text = "%.1f kg   |   Preis: %s" % [kg, "gratis (Testmodus)" if free else "%d EUR" % total()]
		if owner_tab and owner_tab.shop:
			order_button.disabled = not free and total() > int(owner_tab.shop.money)

	func order() -> void:
		if owner_tab == null or owner_tab.shop == null:
			return
		var err: String = owner_tab.shop.order_material(spec())
		_result.text = "Bestellt: steht vor dem Lager-Rolltor. Mit Linksklick aufheben und in ein Regalfach legen." if err == "" else err
		_result.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if err == "" else Color(1.0, 0.45, 0.35))
		owner_tab.refresh()


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 16)
	_money.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_money)
	_needs = Label.new()
	_needs.add_theme_font_size_override("font_size", 14)
	left.add_child(_needs)
	head.add_child(left)
	head.add_child(UITheme.button("Für Drehauftrag wählen", pick_for_job.bind("lathe"), 240))
	head.add_child(UITheme.button("Für Fräsauftrag wählen", pick_for_job.bind("mill"), 240))
	kinds = TabContainer.new()
	kinds.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(kinds)

	var bars := TabContainer.new()
	bars.add_child(_page(Materials.KIND_ROUND))
	bars.set_tab_title(0, "Rundmaterial")
	bars.add_child(_page(Materials.KIND_SQUARE))
	bars.set_tab_title(1, "Vierkantmaterial")
	kinds.add_child(bars)
	kinds.set_tab_title(0, "Stangenmaterial")
	kinds.add_child(_page(Materials.KIND_CUT))
	kinds.set_tab_title(1, "Fertigschnitt Material")
	refresh()


## Bestellseite öffnen und Material und Maße des laufenden Auftrags eintragen.
func pick_for_job(machine: String) -> void:
	if shop == null:
		return
	var sp: Dictionary = shop.job_spec(machine)
	if not shop.company.skills.has(Skills.material_node(str(sp["material"]))):
		return
	var page: OrderPage = pages[sp["kind"]]
	if sp["kind"] == Materials.KIND_ROUND:
		kinds.current_tab = 0
		(kinds.get_tab_control(0) as TabContainer).current_tab = 0
		page.fields["d"].value = sp["d"]
	else:
		kinds.current_tab = 1
		page.fields["l"].value = sp["l"]
		page.fields["w"].value = sp["w"]
		page.fields["h"].value = sp["h"]
	page.select(str(sp["material"]))


func _page(kind: String) -> OrderPage:
	var p := OrderPage.new()
	p.owner_tab = self
	p.kind = kind
	pages[kind] = p
	return p


## Werkstattkasse und Preise neu anzeigen.
func refresh() -> void:
	if _money == null:
		return
	_money.text = "Werkstattkasse: %d EUR" % (int(shop.money) if shop else 0)
	if shop and shop.free_mode:
		_money.text += "     TESTMODUS: alles gratis"
	_needs.text = shop.job_needs() if shop else ""
	for k in pages:
		pages[k].refresh()
		if shop and pages[k].is_node_ready():
			pages[k].apply_locks(shop.company.skills)


static func describe(item: Dictionary) -> String:
	match str(item["kind"]):
		"semi":
			return "Teil vom Kunden: %s" % item.get("title", "")
		Materials.KIND_ROUND:
			return "Rund Ø%d, Rest %d mm" % [int(item["d"]), int(item["l"])]
		Materials.KIND_SQUARE:
			return "Vierkant %d x %d, Rest %d mm" % [int(item["w"]), int(item["h"]), int(item["l"])]
	return "Fertigschnitt %d x %d x %d mm" % [int(item["l"]), int(item["w"]), int(item["h"])]
