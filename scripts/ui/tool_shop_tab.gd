class_name ToolShopTab
extends HBoxContainer
## Werkzeuge kaufen am Büro-PC: links die Maschine, rechts oben die Unterkategorien, darunter die Werkzeuge.
## Jedes gibt es als Hartmetall, als HSS erst nach dem Skill, von jedem bis zu 5 Stück. Ein gekauftes Werkzeug
## liegt auf der Werkbank der Maschine.

const MACHINES := [
	{"id": "lathe", "title": "Drehmaschine"},
	{"id": "cnc_lathe", "title": "CNC-Drehmaschine"},
	{"id": "mill", "title": "Fräsmaschine"},
	{"id": "drill", "title": "Standbohrmaschine"},
	{"id": "flat_grinder", "title": "Flachschleifmaschine"},
	{"id": "round_grinder", "title": "Rundschleifmaschine"},
]
## Unterkategorien der Drehwerkzeuge
const LATHE_CATEGORIES := [
	{"title": "Schruppen", "ids": ["T1", "T2"]},
	{"title": "Schlichten und Kopieren", "ids": ["T3", "T4"]},
	{"title": "Fasen und Radien", "ids": ["T5", "T7"]},
	{"title": "Stechen", "ids": ["T6"]},
]

## Spielwelt: money, free_mode, company, tool_price(machine, id, grade), buy_tool(machine, id, grade)
var shop: Node = null
var machine := "lathe"
var category := 0                 # gewählte Unterkategorie
var categories: Array = []        # der gewählten Maschine, je {"title", "ids"}
var rows: Dictionary = {}         # Werkzeug-id -> {"box": Zeile, "status": Label, "hm": Button, "hss": Button}
var category_buttons: Array[Button] = []
var _cat_bar: HBoxContainer
var _money: Label
var _lock: Label
var _list: VBoxContainer
var _result: Label
var _group := ButtonGroup.new()
var _machine_buttons: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	for m in MACHINES:
		var b := UITheme.button(m["title"], select_machine.bind(m["id"]), 220)
		b.toggle_mode = true
		b.button_group = _group
		b.focus_mode = Control.FOCUS_NONE
		left.add_child(b)
		_machine_buttons[m["id"]] = b
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 16)
	_money.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	right.add_child(_money)
	_lock = Label.new()
	_lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lock.add_theme_font_size_override("font_size", 14)
	_lock.add_theme_color_override("font_color", Color(0.95, 0.7, 0.35))
	right.add_child(_lock)
	_cat_bar = HBoxContainer.new()
	_cat_bar.add_theme_constant_override("separation", 6)
	right.add_child(_cat_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.add_theme_font_size_override("font_size", 15)
	right.add_child(_result)
	select_machine("lathe")


func select_machine(id: String) -> void:
	machine = id
	_machine_buttons[id].button_pressed = true
	for c in _list.get_children():
		_list.remove_child(c)
		c.free()
	rows.clear()
	if id == "lathe" or id == "cnc_lathe":
		for t in LatheTools.all():
			_row(str(t["id"]), "%s %s" % [t["id"], t["name"]])
	elif Wheels.WIDTHS.has(id):
		for t in Wheels.list(id):
			_row(str(t["id"]), str(t["name"]))
	else:
		var kinds: Array = ["drill"] if id == "drill" else ["end_mill", "drill", "face_mill"]
		for kind in kinds:
			for t in MillTools.of_kind(kind):
				_row(str(t["id"]), str(t["name"]))
	_build_categories()
	refresh()


## Unterkategorien einer Maschine: Art des Werkzeugs, bei den Bohrern die Größe.
static func categories_of(id: String) -> Array:
	if id == "lathe" or id == "cnc_lathe":
		return LATHE_CATEGORIES
	if Wheels.WIDTHS.has(id):
		var out := []
		for type_id in Wheels.TYPES:
			var ids := []
			for w in Wheels.list(id):
				if w["type"] == type_id:
					ids.append(w["id"])
			out.append({"title": str(Wheels.TYPES[type_id]["title"]).replace("scheibe", "").replace("-Scheibe", "").trim_suffix("-"), "ids": ids})
		return out
	if id == "drill":
		return [_drills("Klein bis Ø8", 0.0, 8.0), _drills("Mittel Ø10 bis 16", 8.5, 16.0), _drills("Groß ab Ø18", 16.5, 999.0)]
	return [_of_kind("Schaftfräser", "end_mill"), _of_kind("Spiralbohrer", "drill"), _of_kind("Messerköpfe", "face_mill")]


static func _of_kind(title: String, kind: String) -> Dictionary:
	var ids := []
	for t in MillTools.of_kind(kind):
		ids.append(t["id"])
	return {"title": title, "ids": ids}


static func _drills(title: String, lo: float, hi: float) -> Dictionary:
	var ids := []
	for t in MillTools.of_kind("drill"):
		if float(t["d"]) >= lo and float(t["d"]) <= hi:
			ids.append(t["id"])
	return {"title": title, "ids": ids}


func _build_categories() -> void:
	for c in _cat_bar.get_children():
		_cat_bar.remove_child(c)
		c.free()
	category_buttons.clear()
	categories = categories_of(machine)
	var group := ButtonGroup.new()
	for i in categories.size():
		var b := UITheme.button(str(categories[i]["title"]), select_category.bind(i), 160)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 36
		b.add_theme_font_size_override("font_size", 15)
		_cat_bar.add_child(b)
		category_buttons.append(b)
	select_category(0)


## Nur die Werkzeuge dieser Unterkategorie zeigen.
func select_category(i: int) -> void:
	category = clampi(i, 0, categories.size() - 1)
	category_buttons[category].button_pressed = true
	var ids: Array = categories[category]["ids"]
	for id in rows:
		rows[id]["box"].visible = ids.has(id)


func _row(id: String, title: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_list.add_child(h)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	h.add_child(col)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 16)
	col.add_child(l)
	var s := Label.new()
	s.add_theme_font_size_override("font_size", 13)
	col.add_child(s)
	var row := {"status": s, "box": h}
	for g in ToolStore.GRADE_TITLES:
		var b := UITheme.button("", buy.bind(id, g), 210)
		b.custom_minimum_size.y = 38
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		h.add_child(b)
		row[g] = b
	rows[id] = row


func buy(id: String, grade: String) -> void:
	var err: String = shop.buy_tool(machine, id, grade)
	_result.text = "Gekauft: liegt auf der Werkbank der Maschine." if err == "" else err
	_result.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if err == "" else Color(1.0, 0.45, 0.35))
	refresh()


func refresh() -> void:
	if _money == null or shop == null:
		return
	_money.text = "Werkstattkasse: %d EUR" % int(shop.money)
	var sk: Skills = shop.company.skills
	var unlocked := sk.has(Skills.machine_skill(machine))
	var hss_ok := sk.has("%s_hss" % Skills.tool_family(machine))
	var wheels := Wheels.WIDTHS.has(machine)
	_lock.text = ""
	if not unlocked:
		_lock.text = "Im Skilltree freischalten: %s" % Skills.title_of(Skills.machine_skill(machine))
	elif wheels:
		_lock.text = "CBN- und Diamantscheiben gibt es nach den Skills im Skilltree. Korund wird unrund und muss abgezogen werden."
	elif not hss_ok:
		_lock.text = "HSS-Werkzeuge gibt es nach dem Skill HSS im Skilltree."
	var store: ToolStore = shop.company.tools[machine]
	for id in rows:
		var row: Dictionary = rows[id]
		var n: int = store.count(id)
		var have: bool = n > 0
		var full: bool = n >= ToolStore.MAX_COPIES
		(row["status"] as Label).text = "%d von %d Stück%s" % [n, ToolStore.MAX_COPIES, ": %s" % store.info(id) if store.has(id) else ""] if have else "Nicht vorhanden"
		(row["status"] as Label).add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if have else UITheme.MUTED)
		if wheels:
			var wheel: Dictionary = Wheels.by_id(machine, id)
			var need := str(Wheels.TYPES[wheel["type"]]["skill"])
			var price: int = 0 if shop.free_mode else shop.tool_price(machine, id, "hm")
			var bt: Button = row["hm"]
			bt.text = "Kaufen: %s" % ("gratis" if shop.free_mode else "%d EUR" % price)
			bt.disabled = full or not unlocked or (need != "" and not sk.has(need)) or price > int(shop.money)
			row["hss"].visible = false
			continue
		for g in ToolStore.GRADE_TITLES:
			var b: Button = row[g]
			var cost: int = 0 if shop.free_mode else shop.tool_price(machine, id, g)
			b.text = "%s: %s" % [ToolStore.GRADE_TITLES[g], "gratis" if shop.free_mode else "%d EUR" % cost]
			b.disabled = full or not unlocked or (g == "hss" and not hss_ok) or cost > int(shop.money)
