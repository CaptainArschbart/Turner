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
	add_theme_constant_override("separation", 14)
	offers = _column("Angebote")
	taken = _column("Angenommen")
	refresh()


func _column(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var t := UITheme.title(title, 20)
	t.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(t)
	if title == "Angebote":
		_result = _small("", Color(1.0, 0.45, 0.35))
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
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.sb(Color(0.1, 0.11, 0.12), Color(0.24, 0.26, 0.29)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var l := Label.new()
	l.text = summary(key, shop.company.pay_factor() if shop else 1.0, frist)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	v.add_child(l)
	return card


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
		var b := UITheme.button("Annehmen", accept.bind(key), 180)
		b.custom_minimum_size.y = 36
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = reason != ""
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(b)
		if reason != "":
			v.add_child(_small(reason, Color(0.95, 0.7, 0.35)))
		offers.add_child(card)
	if shop.accepted.is_empty() and shop.grind_jobs.is_empty():
		taken.add_child(_small("Noch kein Auftrag angenommen.", UITheme.MUTED))
	for key in shop.grind_jobs:
		var card := _card(key, "Wartet aufs Schleifen, %s" % days_text(int(shop.deadlines.get(key, shop.day)) - int(shop.day)))
		taken.add_child(card)
	for key in shop.accepted:
		var card := _card(key, "Frist: %s" % days_text(int(shop.deadlines.get(key, shop.day)) - int(shop.day)))
		var v: VBoxContainer = card.get_child(0)
		var b := UITheme.button("Zurückgeben", return_job.bind(key), 180)
		b.custom_minimum_size.y = 36
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(b)
		taken.add_child(card)
	taken.add_child(_small("Mit der Taste Tab wählst du außerhalb des PCs aus, welcher Auftrag oben rechts steht.", UITheme.MUTED))


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
