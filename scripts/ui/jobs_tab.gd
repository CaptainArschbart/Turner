class_name JobsTab
extends HBoxContainer
## Aufträge am Büro-PC: links die Angebote, rechts was angenommen ist. Angenommen wird nur hier von Hand,
## auf der Taste Tab wählt man dann aus, welcher Auftrag oben rechts steht.

## Spielwelt: accepted, tracked, company, accept_job(key), return_job(key)
var shop: Node = null
var offers: VBoxContainer
var taken: VBoxContainer
var _result: Label


func _ready() -> void:
	add_theme_constant_override("separation", 20)
	offers = _column("Angebote")
	var line := VSeparator.new()
	line.add_theme_stylebox_override("separator", _vline())
	add_child(line)
	taken = _column("Angenommen")
	refresh()


func _vline() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.vertical = true
	s.color = Color(1, 1, 1, 0.08)
	return s


func _column(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(UITheme.section(title))
	if title == "Angebote":
		_result = _small("", UITheme.BAD)
		v.add_child(_result)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list


func _small(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	return l


## Kurzfassung für die Liste. factor = Wirkung des Ansehens, frist = Text zur Frist.
static func summary(key: String, factor := 1.0, frist := "") -> String:
	var job := JobBoard.job_of(key)
	var part: String
	if job.has("stock_d"):
		part = "Rund Ø%d x %d mm" % [int(job["stock_d"]), int(job["stock_len"])]
	else:
		var s: Array = job["size"]
		part = "%d x %d x %d mm" % [int(s[0]), int(s[1]), int(s[2])]
	var text := "%s\nWerkstoff: %s   %s: %s\n%s\nVergütung: bis %d EUR   Erfahrung: %d" % [
		job["title"], Materials.label(str(job["material"])), "Kundenteil" if JobBoard.key_machine(key) == "ceramic" else "Rohteil", part,
		"\n".join(PackedStringArray(JobBoard.target_lines(job))), int(round(float(job["reward"]) * factor)), JobBoard.xp_for(job)]
	return text if frist == "" else "%s\n%s" % [text, frist]


## Text zur verbleibenden Zeit.
static func days_text(left: int) -> String:
	if left <= 0:
		return "Frist endet heute"
	if left == 1:
		return "noch 1 Tag"
	return "noch %d Tage" % left


func _card(key: String, frist := "") -> PanelContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var card := UITheme.card(v)
	# Kopf: Titel des Auftrags, rechts die Frist. Darunter Werkstoff, Rohteil, Ziele und Vergütung.
	var lines := summary(key, shop.company.pay_factor() if shop else 1.0).split("\n")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var t := UITheme.title(lines[0], 17)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if frist != "":
		var f := UITheme.note(frist, 13, UITheme.WARN if frist.contains("heute") else UITheme.VALUE)
		f.autowrap_mode = TextServer.AUTOWRAP_OFF
		f.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(f)
	lines.remove_at(0)
	v.add_child(UITheme.note("\n".join(lines), 14, Color(UITheme.TEXT, 0.85)))
	var row := HBoxContainer.new()
	row.name = "Knoepfe"
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(_button("Zeichnung", show_drawing.bind(key)))
	return card


func _button(text: String, cb: Callable) -> Button:
	return UITheme.small_button(text, cb, 170)


func show_drawing(key: String) -> void:
	shop.drawing.toggle_job(JobBoard.job_of(key))


func refresh() -> void:
	if offers == null:
		return
	_clear(offers)
	_clear(taken)
	if shop == null:
		return
	var shown: Array = shop.offers()
	if shown.is_empty():
		offers.add_child(_small("Zurzeit keine Angebote. Neue kommen mit dem nächsten Tag.", UITheme.MUTED))
	for key in shown:
		var reason: String = shop.accept_error(key)
		var card := _card(key, "Frist: %d Tage ab Annahme" % JobBoard.days_for(key))
		var v: VBoxContainer = card.get_child(0)
		var b := UITheme.primary(_button("Annehmen", accept.bind(key)))
		b.disabled = reason != ""
		var row: HBoxContainer = v.get_node("Knoepfe")
		row.add_child(b)
		row.move_child(b, 0)
		if reason != "":
			v.add_child(_small(reason, UITheme.WARN))
		offers.add_child(card)
	if shop.accepted.is_empty() and shop.grind_jobs.is_empty():
		taken.add_child(_small("Noch kein Auftrag angenommen.", UITheme.MUTED))
	for key in shop.grind_jobs:
		var card := _card(key, "Wartet aufs Schleifen, %s" % days_text(int(shop.deadlines.get(key, shop.day)) - int(shop.day)))
		taken.add_child(card)
	for key in shop.accepted:
		var card := _card(key, "Frist: %s" % days_text(int(shop.deadlines.get(key, shop.day)) - int(shop.day)))
		var v: VBoxContainer = card.get_child(0)
		var row: HBoxContainer = v.get_node("Knoepfe")
		var b := _button("Zurückgeben", return_job.bind(key))
		row.add_child(b)
		row.move_child(b, 0)
		taken.add_child(card)
	taken.add_child(_small("Taste %s außerhalb des PCs: wählen, welcher Auftrag oben rechts steht." % Settings.binding_text("job_menu"), UITheme.MUTED))


func accept(key: String) -> void:
	_result.text = shop.accept_job(key)
	refresh()


func return_job(key: String) -> void:
	shop.return_job(key)
	refresh()


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.free()
