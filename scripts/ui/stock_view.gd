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
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", UITheme.MUTED)
	add_child(info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)


func refresh() -> void:
	if list == null:
		return
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var stock: Array = shop.stock if shop else []
	info.text = "Rundmaterial gehört an die Drehmaschine, Vierkant und Fertigschnitt an die Fräsmaschine. Stangen vorher an der Bandsäge absägen, dann mit Linksklick an der Maschine einspannen."
	if shop:
		info.text += "\nBelegt: %d von %d Fächern, je %d x %d x %d mm." % [
			Storage.used_slots(stock), shop.site.capacity(), int(Storage.BOARD_L), int(Storage.BOARD_D), int(Storage.BOARD_H)]
		if not shop.deliveries.is_empty():
			info.text += "\n%d Lieferungen stehen noch vor dem Lager-Rolltor." % shop.deliveries.size()
	if stock.is_empty():
		var l := Label.new()
		l.text = "Das Lager ist leer."
		list.add_child(l)
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
	var l := Label.new()
	l.text = "%d x  %s  %s" % [count, Materials.label(str(item["material"])), RawMaterialTab.describe(item)]
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 16)
	box.add_child(l)
	var place := Label.new()
	place.text = Site.slot_name(int(item.get("slot", -1)))
	place.add_theme_font_size_override("font_size", 14)
	place.add_theme_color_override("font_color", UITheme.MUTED)
	box.add_child(place)
	if can_take:
		box.add_child(UITheme.button("Nehmen", _take.bind(i), 160))
	return box


## Stück aus dem Regal in die Hände nehmen, das Menü schließt dann.
func _take(i: int) -> void:
	var err: String = shop.take_from_stock(i)
	if err != "":
		info.text = err
		return
	refresh()
	taken.emit()
