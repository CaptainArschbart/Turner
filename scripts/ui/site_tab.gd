class_name SiteTab
extends HBoxContainer
## Ausbau am Büro-PC: Lageplan aus Kacheln. Kachel anklicken, daneben kaufen. Es lassen sich nur
## Kacheln kaufen, die an den Bereich angrenzen.

## Spielwelt: money, free_mode, site, stock, layout, buy_tile(area, cell)
var shop: Node = null
var map: SiteMap
var selected := {}
var buy_button: Button
var _money: Label
var _info: Label
var _result: Label


## Lageplan. Werkstatt orange, Lager cyan, freie Kacheln grau, Maschinenbereiche gelb.
class SiteMap extends Control:
	const X_MIN := -38.0
	const Z_MIN := -40.0
	const SCALE := 10.0
	const ORANGE := Color(0.93, 0.6, 0.15)
	const CYAN := Color(0.2, 0.75, 0.9)
	const GREY := Color(0.35, 0.37, 0.4)
	const WHITE := Color(0.92, 0.92, 0.92)
	var tab: SiteTab

	func _ready() -> void:
		custom_minimum_size = Vector2((38.0 - X_MIN) * SCALE, (18.0 - Z_MIN) * SCALE)
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func to_map(x: float, z: float) -> Vector2:
		return Vector2((x - X_MIN) * SCALE, (z - Z_MIN) * SCALE)

	func _rect(r: Rect2) -> Rect2:
		return Rect2(to_map(r.position.x, r.position.y), r.size * SCALE)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var c := cell_at(event.position)
			if not c.is_empty():
				tab.select(c["area"], c["cell"])

	## Kachel unter einem Punkt der Karte, zuerst das Lager.
	func cell_at(p: Vector2) -> Dictionary:
		var x := p.x / SCALE + X_MIN
		var z := p.y / SCALE + Z_MIN
		if x >= Site.LAGER_X0 and z < Site.LAGER_Z:
			return {"area": "lager", "cell": Vector2i(int(floor((x - Site.LAGER_X0) / Site.L_TILE.x)), int(floor((Site.LAGER_Z - z) / Site.L_TILE.y)))}
		if x < Site.LAGER_X0:
			return {"area": "workshop", "cell": Vector2i(int(floor(x / Site.W_TILE)), int(floor(z / Site.W_TILE)))}
		return {}

	func _hatch(r: Rect2, col: Color) -> void:
		draw_rect(r, Color(col, 0.16))
		var c := Color(col, 0.28)
		var d := 9.0
		var t := d
		var span := r.size.x + r.size.y
		while t < span:
			var a := r.position + Vector2(minf(t, r.size.x), maxf(t - r.size.x, 0.0))
			var b := r.position + Vector2(maxf(t - r.size.y, 0.0), minf(t, r.size.y))
			draw_line(a, b, c, 1.0)
			t += d

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.04))
		if tab == null or tab.shop == null:
			return
		var site: Site = tab.shop.site
		# Hof
		var yard := _rect(Rect2(Site.LAGER_X0, Site.LAGER_Z, Site.YARD_X1 - Site.LAGER_X0, Site.YARD_Z1 - Site.LAGER_Z))
		draw_rect(yard, Color(0.09, 0.09, 0.1))
		draw_rect(yard, WHITE, false, 1.0)
		# Freie Kacheln
		for cz in range(Site.W_CZ.x, Site.W_CZ.y + 1):
			for cx in range(Site.W_CX_MIN, Site.W_CX_BASE):
				_free_cell("workshop", Vector2i(cx, cz), Site.w_rect(Vector2i(cx, cz)), site)
		for cz in range(0, Site.L_CZ_MAX + 1):
			for cx in range(0, Site.L_CX_MAX + 1):
				_free_cell("lager", Vector2i(cx, cz), Site.l_rect(Vector2i(cx, cz)), site)
		# Eigene Kacheln
		for cz in range(-2, 2):
			for cx in range(Site.W_CX_BASE, 3):
				_own(Site.w_rect(Vector2i(cx, cz)), ORANGE)
		for c in site.workshop_cells:
			_own(Site.w_rect(c), ORANGE)
		for c in site.lager_cells:
			_own(Site.l_rect(c), CYAN)
		for c in site.rack_cells:
			draw_rect(_rect(Site.rack_rect(c)), Color(0.2, 0.4, 0.75))
		# Maschinenbereiche
		var font := ThemeDB.fallback_font
		for id in tab.shop.layout.machines:
			var r := _rect(tab.shop.layout.area_of(id))
			draw_rect(r, Color(0.95, 0.8, 0.1, 0.22))
			draw_rect(r, Color(0.95, 0.8, 0.1), false, 2.0)
			draw_string(font, r.position + Vector2(4, 14), str(Layout.SPECS[id]["title"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 6, 11, WHITE)
		# Rolltore und Beschriftung
		var door_w := to_map(Site.LAGER_X0, Workshop.DOOR_Z)
		draw_line(door_w + Vector2(0, -RollDoor.WIDTH * 5.0), door_w + Vector2(0, RollDoor.WIDTH * 5.0), Color(0.3, 1.0, 0.4), 4.0)
		var door_l := to_map(Site.LAGER_DOOR_X, Site.LAGER_Z)
		draw_line(door_l + Vector2(-RollDoor.WIDTH * 5.0, 0), door_l + Vector2(RollDoor.WIDTH * 5.0, 0), Color(0.3, 1.0, 0.4), 4.0)
		draw_string(font, to_map(14.0, 2.0), "Hof", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WHITE)
		draw_string(font, to_map(8.6, 6.0), "Büro", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WHITE)
		draw_string(font, to_map(-11.0, 6.5), "WERKSTATT", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ORANGE)
		draw_string(font, to_map(13.0, -19.0), "LAGER", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CYAN)
		# Auswahl
		if not tab.selected.is_empty():
			var c: Vector2i = tab.selected["cell"]
			var sr := _rect(Site.w_rect(c) if tab.selected["area"] == "workshop" else Site.l_rect(c))
			draw_rect(sr, Color(1.0, 1.0, 1.0, 0.25))
			draw_rect(sr, Color.WHITE, false, 3.0)

	func _free_cell(area: String, c: Vector2i, r: Rect2, site: Site) -> void:
		if site.has_cell(area, c):
			return
		var mr := _rect(r)
		if site.can_buy(area, c):
			draw_rect(mr, Color(0.4, 0.42, 0.45, 0.25))
			draw_rect(mr, Color(0.75, 0.77, 0.8), false, 1.5)
		else:
			draw_rect(mr, GREY, false, 1.0)

	## Eigene Kachel mit Schraffur, Linien und weißen Stützen an den Ecken wie auf dem Plan.
	func _own(r: Rect2, col: Color) -> void:
		var mr := _rect(r)
		_hatch(mr, col)
		draw_rect(mr, col, false, 1.5)
		for p in [mr.position, mr.position + Vector2(mr.size.x, 0), mr.position + Vector2(0, mr.size.y), mr.end]:
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), WHITE)


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	map = SiteMap.new()
	map.tab = self
	add_child(map)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 340
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 10)
	add_child(side)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 16)
	_money.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	side.add_child(_money)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 15)
	side.add_child(_info)
	buy_button = UITheme.button("Kachel wählen", buy, 300)
	buy_button.custom_minimum_size.y = 44
	buy_button.disabled = true
	side.add_child(buy_button)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.add_theme_font_size_override("font_size", 15)
	side.add_child(_result)
	var legend := Label.new()
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_theme_font_size_override("font_size", 14)
	legend.add_theme_color_override("font_color", UITheme.MUTED)
	legend.text = "Orange: Werkstatt, je Kachel 4 x 4 m\nCyan: Lager, je Kachel 6 x 7,6 m mit Platz für ein Regal (blau, 6 Fächer)\nHell umrandet: kann gekauft werden, grenzt an den Bereich\nGelb: Maschinenbereiche\nGrün: Rolltore"
	side.add_child(legend)
	refresh()


func select(area: String, cell: Vector2i) -> void:
	selected = {"area": area, "cell": cell}
	_result.text = ""
	refresh()


func buy() -> void:
	if selected.is_empty():
		return
	var err: String = shop.buy_tile(selected["area"], selected["cell"])
	_result.text = "Gekauft." if err == "" else err
	_result.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if err == "" else Color(1.0, 0.45, 0.35))
	if err == "":
		selected = {}
	refresh()


func refresh() -> void:
	if _money == null:
		return
	_money.text = "Werkstattkasse: %d EUR" % (int(shop.money) if shop else 0)
	if shop == null:
		return
	var site: Site = shop.site
	var w_area := Workshop.W * Workshop.D + site.workshop_cells.size() * Site.W_TILE * Site.W_TILE
	var text := "Werkstatt: %d m²\nLager: %d Regale, belegt %d von %d Fächern" % [int(w_area), site.rack_cells.size(), Storage.used_slots(shop.stock), site.capacity()]
	buy_button.disabled = true
	buy_button.text = "Kachel wählen"
	if not selected.is_empty():
		var area: String = selected["area"]
		var cell: Vector2i = selected["cell"]
		var name_a := "Werkstatt" if area == "workshop" else "Lager"
		if site.has_cell(area, cell):
			text += "\n\n%s: gehört schon dazu." % name_a
		elif not site.can_buy(area, cell):
			text += "\n\n%s: Diese Kachel grenzt nicht an den Bereich." % name_a
		else:
			var cost: int = site.tile_price(area)
			text += "\n\n%s: neue Kachel" % name_a
			buy_button.text = "Kaufen: gratis (Testmodus)" if shop.free_mode else "Kaufen: %d EUR" % cost
			buy_button.disabled = not shop.free_mode and cost > int(shop.money)
	_info.text = text
	map.queue_redraw()
