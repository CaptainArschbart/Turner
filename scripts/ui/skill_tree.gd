class_name SkillTreeApp
extends HBoxContainer
## Programm Skilltree am Büro-PC. Reiter Allgemein mit Maschinen, Werkstoffen und Upgrades, dazu je
## Maschine ein Reiter für deren Werkzeuge, der erst mit der Maschine erscheint.

const CELL := Vector2(168, 66)
const NODE := Vector2(150, 52)
const HEAD := 26.0

## Spielwelt: company, free_mode, unlock_skill(id)
var shop: Node = null
var trees: TabContainer
var canvases: Dictionary = {}
var selected := ""
var _points: Label
var _bar: ProgressBar
var _name: Label
var _desc: Label
var _state: Label
var _unlock: Button


## Ein Baum: Knöpfe auf festen Plätzen, Verbindungen dahinter.
class Canvas extends Control:
	var app: SkillTreeApp
	var tree_id := ""
	var buttons: Dictionary = {}

	func _ready() -> void:
		var rows := 0
		var cols := 0
		for id in Skills.NODES:
			var n: Dictionary = Skills.NODES[id]
			if n["tree"] != tree_id:
				continue
			rows = maxi(rows, n["at"].y + 1)
			cols = maxi(cols, n["at"].x + 1)
			var b := Button.new()
			b.text = str(n["title"])
			b.size = NODE
			b.position = cell_pos(n["at"])
			b.focus_mode = Control.FOCUS_NONE
			b.clip_text = true
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(app.select.bind(id))
			add_child(b)
			buttons[id] = b
		custom_minimum_size = Vector2(cols * CELL.x + 12.0, rows * CELL.y + HEAD * 3.0)
		if tree_id == "general":
			for branch in Skills.BRANCHES:
				var l := UITheme.title(branch, 16)
				l.add_theme_color_override("font_color", UITheme.ACCENT)
				l.position = Vector2(4, cell_pos(Vector2i(0, int(Skills.BRANCHES[branch]))).y - HEAD)
				add_child(l)

	## Oberkante: Die Überschriften der Zweige rücken alles darunter ein wenig nach unten.
	func cell_pos(at: Vector2i) -> Vector2:
		var heads := 1.0
		if tree_id == "general":
			heads = 0.0
			for branch in Skills.BRANCHES:
				if at.y >= int(Skills.BRANCHES[branch]):
					heads += 1.0
		return Vector2(at.x * CELL.x + 6.0, at.y * CELL.y + heads * HEAD)

	func _draw() -> void:
		if app.shop == null:
			return
		var sk: Skills = app.shop.company.skills
		for id in buttons:
			var n: Dictionary = Skills.NODES[id]
			for r in n["req"]:
				if not buttons.has(r):
					continue
				var a: Vector2 = buttons[r].position + Vector2(NODE.x, NODE.y * 0.5)
				var b: Vector2 = buttons[id].position + Vector2(0, NODE.y * 0.5)
				var col := Color(0.4, 0.85, 0.45) if sk.has(id) else (UITheme.ACCENT if sk.has(str(r)) else Color(0.32, 0.34, 0.37))
				var mid := (a.x + b.x) * 0.5
				draw_polyline(PackedVector2Array([a, Vector2(mid, a.y), Vector2(mid, b.y), b]), col, 2.0, true)


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	_points = Label.new()
	_points.add_theme_font_size_override("font_size", 16)
	_points.add_theme_color_override("font_color", Color(0.65, 0.8, 1.0))
	left.add_child(_points)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	left.add_child(_bar)
	trees = TabContainer.new()
	trees.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trees.tab_changed.connect(func(_i: int): refresh())
	left.add_child(trees)
	for t in Skills.TREES:
		var scroll := ScrollContainer.new()
		trees.add_child(scroll)
		trees.set_tab_title(trees.get_tab_count() - 1, t["title"])
		var c := Canvas.new()
		c.app = self
		c.tree_id = t["id"]
		scroll.add_child(c)
		canvases[t["id"]] = c
	add_child(_side())
	refresh()


func _side() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 280
	v.add_theme_constant_override("separation", 10)
	_name = UITheme.title("Skill wählen", 20)
	_name.add_theme_color_override("font_color", UITheme.ACCENT)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_name)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 15)
	v.add_child(_desc)
	_state = Label.new()
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state.add_theme_font_size_override("font_size", 14)
	_state.add_theme_color_override("font_color", UITheme.MUTED)
	v.add_child(_state)
	_unlock = UITheme.button("Freischalten", unlock, 260)
	_unlock.focus_mode = Control.FOCUS_NONE
	_unlock.disabled = true
	v.add_child(_unlock)
	return v


func select(id: String) -> void:
	selected = id
	refresh()


func unlock() -> void:
	if selected == "":
		return
	shop.unlock_skill(selected)
	refresh()


func refresh() -> void:
	if _points == null or shop == null:
		return
	var sk: Skills = shop.company.skills
	var prog := sk.progress()
	_points.text = "Freie Skillpunkte: %d     Erfahrung zum nächsten Punkt: %d / %d" % [sk.free_points(), prog.x, prog.y]
	if shop.free_mode:
		_points.text += "     TESTMODUS: Skills kostenlos"
	_bar.max_value = prog.y
	_bar.value = prog.x
	for i in Skills.TREES.size():
		var needs := str(Skills.TREES[i]["needs"])
		var other := str(Skills.TREES[i].get("or", ""))
		trees.set_tab_hidden(i, needs != "" and not sk.has(needs) and not (other != "" and sk.has(other)))
	for t in canvases:
		var c: Canvas = canvases[t]
		for id in c.buttons:
			_style(c.buttons[id], id, sk)
		c.queue_redraw()
	_show_selected(sk)


func _style(b: Button, id: String, sk: Skills) -> void:
	var col: Color
	if sk.has(id):
		col = Color(0.3, 0.75, 0.38)
	elif Skills.NODES[id].get("soon", false):
		col = Color(0.25, 0.26, 0.28)
	elif sk.unlock_error(id, true) == "":
		col = UITheme.ACCENT
	else:
		col = Color(0.3, 0.32, 0.35)
	var border := 3 if id == selected else 1
	var bg := Color(col, 0.22) if sk.has(id) else Color(0.12, 0.13, 0.14)
	var box := UITheme.sb(bg, Color.WHITE if id == selected else col, border)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, box)


func _show_selected(sk: Skills) -> void:
	_unlock.disabled = true
	_unlock.text = "Freischalten"
	if selected == "":
		_name.text = "Skill wählen"
		_desc.text = "Grün: freigeschaltet. Orange: als Nächstes möglich. Grau: Voraussetzung fehlt."
		_state.text = "Skillpunkte gibt es für Erfahrung aus erfolgreichen Aufträgen."
		return
	var n: Dictionary = Skills.NODES[selected]
	_name.text = Skills.title_of(selected)
	_desc.text = str(n["desc"])
	if sk.has(selected):
		_state.text = "Freigeschaltet."
		return
	var err := sk.unlock_error(selected, shop.free_mode)
	_state.text = err if err != "" else "Kann freigeschaltet werden."
	_unlock.disabled = err != ""
	_unlock.text = "Freischalten: kostenlos (Testmodus)" if shop.free_mode else "Freischalten: %d Punkte" % int(n["cost"])
