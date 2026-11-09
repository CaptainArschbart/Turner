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
	_money = UITheme.money_label()
	_money.visible = false            # die Kasse steht in der Kopfzeile des PCs
	add_child(_money)
	add_child(UITheme.section("Spänecontainer im Hof"))
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	add_child(list)
	_result = UITheme.note("", 15, UITheme.TEXT)
	add_child(_result)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sp)
	add_child(UITheme.section("So geht's"))
	var steps := GridContainer.new()
	steps.columns = 2
	steps.add_theme_constant_override("h_separation", 12)
	steps.add_theme_constant_override("v_separation", 4)
	add_child(steps)
	for s in [["1", "Spänebehälter in der Werkstatt aufstellen. Die E50 füllt ihre Spänekiste über den Späneförderer."],
			["2", "Volle Behälter sind zu schwer zum Tragen, sie kommen in den passenden Container im Hof. Sorten nicht mischen, nur Stahlarten untereinander."],
			["3", "Ein voller Container wird hier abgeholt und bezahlt."]]:
		var n := UITheme.title(s[0], 15)
		n.add_theme_color_override("font_color", UITheme.ACCENT)
		steps.add_child(n)
		var t := UITheme.note(s[1], 14)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		steps.add_child(t)
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
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 18)
		var row := UITheme.card(h, 0.0, chips.is_full())
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		h.add_child(col)
		var top := HBoxContainer.new()
		col.add_child(top)
		var l := UITheme.title("Container %s" % ChipTray.SORT_TITLES[chips.only], 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(l)
		top.add_child(UITheme.note("%d von %d kg  ·  %d %%" % [int(chips.kg), int(chips.capacity), int(chips.fraction() * 100.0)], 14, UITheme.TEXT))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		bar.value = chips.fraction() * 100.0
		col.add_child(bar)
		col.add_child(UITheme.note("Wert beim Recycling: %d EUR" % int(shop.container_value(i)), 13))
		var b := UITheme.small_button("Abholen lassen" if chips.is_full() else "Noch nicht voll", _collect.bind(i), 200)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = not chips.is_full()
		if chips.is_full():
			UITheme.primary(b)
		h.add_child(b)
		buttons.append(b)
		list.add_child(row)


func _collect(i: int) -> void:
	var pay: int = shop.collect_container(i)
	_result.text = "Container abgeholt: %d EUR für recyceltes Material." % pay
	_result.add_theme_color_override("font_color", UITheme.GOOD)
	refresh()
