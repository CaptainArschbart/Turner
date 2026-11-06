class_name DayApp
extends VBoxContainer
## Programm Tagesbericht am Büro-PC: Zahlen des laufenden Tages und der Knopf, der den Tag startet oder beendet.

## Spielwelt: day, day_started, day_over, day_stats, last_day_stats, clock_text(), start_day(), next_day(), office_pc
var shop: Node = null
var start_button: Button
var end_button: Button
var values: Dictionary = {}
var _title: Label
var _state: Label
var _last: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_title = UITheme.title("", 28)
	_title.add_theme_color_override("font_color", UITheme.ACCENT)
	add_child(_title)
	_state = Label.new()
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state.add_theme_font_size_override("font_size", 16)
	add_child(_state)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	_row(grid, "accepted", "Angenommene Aufträge")
	_row(grid, "done", "Abgeschlossene Aufträge")
	_row(grid, "earned", "Geld eingenommen")
	_row(grid, "spent", "Geld ausgegeben")
	_row(grid, "profit", "Gewinn / Verlust")
	_last = Label.new()
	_last.add_theme_font_size_override("font_size", 15)
	_last.add_theme_color_override("font_color", UITheme.MUTED)
	add_child(_last)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	add_child(buttons)
	start_button = UITheme.button("Tag starten", _start, 280)
	start_button.custom_minimum_size.y = 52
	buttons.add_child(start_button)
	end_button = UITheme.button("Tag beenden", _end, 280)
	end_button.custom_minimum_size.y = 52
	buttons.add_child(end_button)
	refresh()


func _row(grid: GridContainer, key: String, title: String) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 20)
	grid.add_child(l)
	var v := Label.new()
	v.add_theme_font_size_override("font_size", 20)
	grid.add_child(v)
	values[key] = v


func _start() -> void:
	shop.start_day()
	shop.office_pc.overlay.refresh_all()


func _end() -> void:
	shop.next_day()
	shop.office_pc.overlay.refresh_all()


## Gewinn oder Verlust aus Einnahmen und Ausgaben.
static func profit_of(stats: Dictionary) -> int:
	return int(stats.get("earned", 0)) - int(stats.get("spent", 0))


static func _money_text(eur: int) -> String:
	return "%+d EUR" % eur


func refresh() -> void:
	if _title == null or shop == null:
		return
	_title.text = shop.clock_text()
	if not shop.day_started:
		_state.text = "Der Tag hat noch nicht begonnen. Vorher lässt sich nichts bestellen, annehmen oder bearbeiten."
	elif shop.day_over:
		_state.text = "Feierabend: Das laufende Teil lässt sich noch abgeben, dann den Tag beenden."
	else:
		_state.text = "Der Tag läuft."
	var s: Dictionary = shop.day_stats
	values["accepted"].text = str(int(s.get("accepted", 0)))
	values["done"].text = str(int(s.get("done", 0)))
	values["earned"].text = "%d EUR" % int(s.get("earned", 0))
	values["spent"].text = "%d EUR" % int(s.get("spent", 0))
	var profit := profit_of(s)
	values["profit"].text = _money_text(profit)
	values["profit"].add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if profit >= 0 else Color(1.0, 0.45, 0.35))
	var last: Dictionary = shop.last_day_stats
	_last.text = "Vortag: %d abgeschlossen, %s" % [int(last.get("done", 0)), _money_text(profit_of(last))] if not last.is_empty() else ""
	start_button.visible = not shop.day_started
	end_button.visible = shop.day_started
