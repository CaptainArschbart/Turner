class_name ReputationApp
extends VBoxContainer
## Programm Ansehen am Büro-PC: Stand, Wirkung auf die Vergütung, laufende Fristen und was zuletzt passiert ist.

## Spielwelt: company, day, deadlines
var shop: Node = null
var _value: Label
var _bar: ProgressBar
var _effect: Label
var _due: VBoxContainer
var _log: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	# Stand: große Zahl, Balken, Wirkung auf die Vergütung
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	add_child(UITheme.card(top, 0.0, true))
	_value = UITheme.title("", 28)
	top.add_child(_value)
	_bar = ProgressBar.new()
	_bar.max_value = 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	top.add_child(_bar)
	_effect = UITheme.note("", 16, UITheme.TEXT)
	top.add_child(_effect)
	top.add_child(UITheme.note("Erfolgreich abgeschlossene Aufträge erhöhen das Ansehen, verpasste Fristen und Ausschuss senken es.", 13))
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 14)
	add_child(h)
	_due = _column(h, "Laufende Fristen")
	_log = _column(h, "Zuletzt")
	refresh()


func _column(parent: Control, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var card := UITheme.card(v)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	v.add_child(UITheme.section(title))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list


func _line(list: Control, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	list.add_child(l)


func refresh() -> void:
	if _value == null or shop == null:
		return
	var co: Company = shop.company
	_value.text = "Ansehen: %d von 100 (%s)" % [int(co.reputation), co.reputation_title()]
	_bar.value = co.reputation
	_effect.text = "Aufträge bringen gerade %d %% der normalen Vergütung." % int(round(co.pay_factor() * 100.0))
	for list in [_due, _log]:
		for c in list.get_children():
			list.remove_child(c)
			c.free()
	if shop.deadlines.is_empty():
		_line(_due, "Keine laufenden Aufträge.", UITheme.MUTED)
	for key in shop.deadlines:
		var left := int(shop.deadlines[key]) - int(shop.day)
		var col := Color(1.0, 0.5, 0.4) if left <= 0 else (Color(0.95, 0.8, 0.4) if left == 1 else UITheme.TEXT)
		_line(_due, "%s: %s" % [JobBoard.job_of(str(key))["title"], JobsTab.days_text(left)], col)
	if co.rep_log.is_empty():
		_line(_log, "Noch nichts.", UITheme.MUTED)
	for i in range(co.rep_log.size() - 1, -1, -1):
		var e: Dictionary = co.rep_log[i]
		var d := int(e["change"])
		_line(_log, "Tag %d: %+d  %s" % [int(e["day"]), d, str(e["text"])], UITheme.GOOD if d > 0 else Color(1.0, 0.5, 0.4))
