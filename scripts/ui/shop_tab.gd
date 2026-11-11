class_name ShopTab
extends VBoxContainer
## Einkauf am Büro-PC, in zwei Tabs: Maschinen (machines = true) und alles andere, also Werkbänke, Regale,
## Kisten und Spänebehälter. Gekauftes wird im Baumodus aufgestellt. Was noch gesperrt ist, schaltet der
## Skilltree frei.

## Spielwelt: money, free_mode, inventory, layout, company, buy_equipment(id), equipment_price(id)
const MACHINE_TEXT := {
	"lathe": "Die erste Maschine der Werkstatt. Handräder, Drehknöpfe für Drehzahl und Vorschub. Bringt Drehaufträge.",
	"saw": "Sägt Stangen auf Länge, einmal gratis. Ganze Stangen passen in keine Maschine: Hier den Abschnitt absägen.",
	"cnc_lathe": "Bedienpult mit Zyklen und NC-Programmen. Bringt Drehaufträge.",
	"mill": "Handräder, Drehknöpfe für Drehzahl und Vorschub. Bringt Fräsaufträge.",
	"cnc_mill": "Bearbeitungszentrum mit Kabine, 24-fach-Werkzeugwechsler und Klartext-Programmen. Bringt Fräsaufträge.",
	"drill": "Kreuztisch und Pinole, nimmt Spiralbohrer auf. Bringt Bohraufträge.",
	"round_grinder": "Schleift Rundflächen an Drehteilen, Aufträge verlangen sie dann. Scheiben einzeln kaufen.",
	"flat_grinder": "Schleift ebene Flächen an Frästeilen, Aufträge verlangen sie dann. Scheiben einzeln kaufen.",
}
var shop: Node = null
var machines := false
var buttons: Dictionary = {}
var _money: Label
var _info: Dictionary = {}
var _result: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_money = UITheme.money_label()
	_money.visible = false            # die Kasse steht in der Kopfzeile des PCs
	add_child(_money)
	add_child(UITheme.note("Maschinen der Werkstatt. Gekauftes wird im Baumodus (Taste B) aufgestellt." if machines
		else "Ausstattung für Werkstatt und Lager. Gekauftes wird im Baumodus (Taste B) aufgestellt."))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	if machines:
		for id in Layout.SPECS:
			if Layout.SPECS[id].has("price"):
				var text := "Lässt sich aufstellen und bringt Aufträge, ist aber noch nicht bedienbar." if id == "edm" else str(MACHINE_TEXT.get(id, "Bedienbar. Bringt Aufträge."))
				grid.add_child(_card(id, Layout.SPECS[id]["title"], text))
	else:
		_fill_items(grid)
	_result = UITheme.note("", 15, UITheme.TEXT)
	add_child(_result)
	refresh()


func _fill_items(grid: GridContainer) -> void:
	grid.add_child(_card("bench", "Werkbank", "36 Halterungen für die Werkzeuge einer Maschine. Steht im gelben Maschinenbereich, neben ihr haben 2 Kisten Platz."))
	grid.add_child(_card("bench_big", "Große Werkbank", "2,6 m lang, 54 Halterungen. Neben ihr haben 4 Kisten Platz."))
	grid.add_child(_card("rack", "Lagerregal", "6 Fächer für Stangen und Fertigschnitte. Jede Lagerkachel hat Platz für eines."))
	for id in Crate.SIZES:
		var c: Dictionary = Crate.SIZES[id]
		grid.add_child(_card(id, c["title"], "Für Fertigschnitte und abgesägte Teile, neben der Werkbank. Innen %d x %d x %d mm, bis %d Teile." % [int(c["l"]), int(c["w"]), int(c["h"]), int(c["max"])]))
	for id in ChipBin.SIZES:
		grid.add_child(_card(id, ChipBin.SIZES[id]["title"], "Trägt die Späne von der Spänewanne zum Container im Hof. Fasst %d kg." % int(ChipBin.SIZES[id]["kg"])))
	for id in Shelf.SIZES:
		if not Shelf.in_shop(id):
			continue
		var f: Vector2 = Shelf.SIZES[id]["foot"]
		var text := str(Shelf.SIZES[id].get("text", "Steckregal mit sechs OSB-Böden, steht frei in der Werkstatt."))
		grid.add_child(_card(id, Shelf.SIZES[id]["title"], "%s %d x %d cm, %.1f m hoch." % [text, int(f.x * 100), int(f.y * 100), float(Shelf.SIZES[id]["height"])]))


func _card(id: String, title: String, text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var card := UITheme.card(v, 370)
	v.add_child(UITheme.title(title, 20))
	var d := UITheme.note(text, 14)
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	v.add_child(HSeparator.new())
	var info := UITheme.note("", 14, UITheme.TEXT)
	v.add_child(info)
	_info[id] = info
	var b := UITheme.primary(UITheme.small_button("Kaufen", _buy.bind(id), 200))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(b)
	buttons[id] = b
	return card


func _buy(id: String) -> void:
	var err: String = shop.buy_equipment(id)
	_result.text = "Gekauft. Mit Taste B aufstellen." if err == "" else err
	_result.add_theme_color_override("font_color", UITheme.GOOD if err == "" else UITheme.BAD)
	refresh()


func refresh() -> void:
	if _money == null:
		return
	_money.text = "Werkstattkasse: %d EUR" % (int(shop.money) if shop else 0)
	if shop == null:
		return
	for id in buttons:
		var waiting := int(shop.inventory.get(id, 0))
		var cost: int = shop.equipment_price(id)
		var machine: bool = Layout.SPECS.has(id)
		var owned: bool = machine and (waiting > 0 or shop.layout.machines.has(id))
		var skill := str(Skills.EQUIPMENT.get(id, ""))
		var locked: bool = skill != "" and not shop.company.skills.has(skill)
		var b: Button = buttons[id]
		if locked:
			_info[id].text = "Im Skilltree freischalten: %s" % Skills.title_of(skill)
		else:
			_info[id].text = "Nicht aufgestellt: %d" % waiting if waiting > 0 else ("Steht in der Werkstatt" if owned else "Verfügbar")
		_info[id].add_theme_color_override("font_color", UITheme.WARN if locked else (UITheme.GOOD if owned or waiting > 0 else UITheme.MUTED))
		if locked:
			b.text = "Gesperrt"
		elif owned:
			b.text = "Schon gekauft"
		else:
			if cost == 0:
				b.text = "Gratis mitnehmen"
			else:
				b.text = "Kaufen: gratis (Testmodus)" if shop.free_mode else "Kaufen: %d EUR" % cost
		b.disabled = locked or owned or (not shop.free_mode and cost > int(shop.money))
