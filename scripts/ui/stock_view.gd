class_name StockView
extends VBoxContainer
## Liste des eingelagerten Materials. Am Regal lässt es sich herausnehmen, am PC nur ansehen.

const CUT_MIN := 20.0

## Spielwelt: stock, deliveries, site, load_stock(index, length)
var shop: Node = null
var list: VBoxContainer
var info: Label
var can_take := false

signal taken


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	info = UITheme.note("", 15, UITheme.TEXT)
	add_child(info)
	# Spaltenköpfe der Liste
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	for c in [["Anzahl", 70.0], ["Werkstoff und Abmessung", -1.0], ["Platz", 220.0]]:
		var l := Label.new()
		l.text = str(c[0]).to_upper()
		l.theme_type_variation = "Section"
		if float(c[1]) < 0.0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size.x = float(c[1])
		head.add_child(l)
	if can_take:
		var gap := Control.new()
		gap.custom_minimum_size.x = 130
		head.add_child(gap)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	add_child(UITheme.note("Rundmaterial gehört an die Drehmaschine, Vierkant und Fertigschnitt an die Fräsmaschine. "
		+ "Stangen vorher an der Bandsäge absägen, dann mit Linksklick an der Maschine einspannen.", 13))


func refresh() -> void:
	if list == null:
		return
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var stock: Array = shop.stock if shop else []
	info.text = ""
	info.add_theme_color_override("font_color", UITheme.TEXT)
	if shop:
		info.text = "Belegt: %d von %d Fächern, je %d x %d x %d mm" % [
			Storage.used_slots(stock), shop.site.capacity(), int(Storage.BOARD_L), int(Storage.BOARD_D), int(Storage.BOARD_H)]
		if not shop.deliveries.is_empty():
			info.text += "     ·     %d Lieferungen stehen noch vor dem Lager-Rolltor" % shop.deliveries.size()
	if stock.is_empty():
		list.add_child(UITheme.note("Das Lager ist leer.", 15))
	# Gleiche Stücke auf demselben Platz stehen in einer Zeile
	var rows := {}
	for i in stock.size():
		var it: Dictionary = stock[i]
		var key := "%s|%s|%s|%s|%s|%s|%s" % [it["material"], it["kind"], it["d"], it["w"], it["h"], it["l"], it.get("slot", -1)]
		if rows.has(key):
			rows[key]["count"] += 1
		else:
			rows[key] = {"index": i, "count": 1}
	for k in rows:
		list.add_child(_row(rows[k]["index"], stock[rows[k]["index"]], rows[k]["count"]))


func _row(i: int, item: Dictionary, count: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var card := UITheme.card(box)
	var st := card.get_theme_stylebox("panel") as StyleBoxFlat
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	var n := UITheme.title("%d x" % count, 16)
	n.custom_minimum_size.x = 70
	n.add_theme_color_override("font_color", UITheme.ACCENT)
	box.add_child(n)
	var l := Label.new()
	l.text = "%s   %s" % [Materials.label(str(item["material"])), RawMaterialTab.describe(item)]
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 16)
	box.add_child(l)
	var place := UITheme.note(Site.slot_name(int(item.get("slot", -1))), 14)
	place.autowrap_mode = TextServer.AUTOWRAP_OFF
	place.custom_minimum_size.x = 220
	box.add_child(place)
	if can_take:
		var b := UITheme.small_button("Nehmen", _take.bind(i), 120)
		b.custom_minimum_size.y = 32
		box.add_child(b)
	return card


## Stück aus dem Regal in die Hände nehmen, das Menü schließt dann.
func _take(i: int) -> void:
	var err: String = shop.take_from_stock(i)
	if err != "":
		info.text = err
		info.add_theme_color_override("font_color", UITheme.BAD)
		return
	refresh()
	taken.emit()
