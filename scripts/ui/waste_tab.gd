class_name WasteTab
extends VBoxContainer
## Entsorgung am Büro-PC: Füllstand der Spänecontainer im Hof. Abholen lassen geht erst, wenn einer voll ist,
## dann bringt das recycelte Material Geld.

## Spielwelt: containers, collect_container(i), container_value(i)
var shop: Node = null
var list: VBoxContainer
var buttons: Array[Button] = []
var _money: Label
var _result: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 16)
	_money.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	add_child(_money)
	var hint := Label.new()
	hint.text = "Späne: Spänebehälter aufnehmen, an der Maschine die Wanne hineinleeren, im Hof in den passenden Container kippen. Sorten werden nicht gemischt, nur Stahlarten untereinander. Ein voller Container wird abgeholt und bezahlt."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", UITheme.MUTED)
	add_child(hint)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	add_child(list)
	_result = Label.new()
	_result.add_theme_font_size_override("font_size", 15)
	add_child(_result)
	refresh()


func refresh() -> void:
	if list == null or shop == null:
		return
	_money.text = "Werkstattkasse: %d EUR" % int(shop.money)
	for c in list.get_children():
		list.remove_child(c)
		c.free()
	buttons.clear()
	for i in shop.containers.size():
		var chips: ChipTray = shop.containers[i]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UITheme.sb(Color(0.1, 0.11, 0.12), Color(0.24, 0.26, 0.29)))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 16)
		l.text = "Container %s: %d von %d kg (%d %%)   Wert beim Recycling: %d EUR" % [
			ChipTray.SORT_TITLES[chips.only], int(chips.kg), int(chips.capacity), int(chips.fraction() * 100.0), int(shop.container_value(i))]
		h.add_child(l)
		var b := UITheme.button("Abholen lassen" if chips.is_full() else "Noch nicht voll", _collect.bind(i), 220)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not chips.is_full()
		h.add_child(b)
		buttons.append(b)
		list.add_child(row)


func _collect(i: int) -> void:
	var pay: int = shop.collect_container(i)
	_result.text = "Container abgeholt: %d EUR für recyceltes Material." % pay
	_result.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	refresh()
