class_name DevApp
extends VBoxContainer
## Entwicklerprogramm am Büro-PC, nur im Testmodus zu sehen: alle Aufträge, die es gibt, je Maschine ein Tab,
## zum Prüfen vor dem Release.

## Spielwelt: company, drawing
var shop: Node = null
var cards := 0
var tabs: TabContainer
var _head: Label
var _built := false


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_head = UITheme.title("Alle Aufträge", 22)
	_head.add_theme_color_override("font_color", UITheme.ACCENT)
	add_child(_head)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 14)
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	add_child(tabs)


## Aufgebaut wird erst beim ersten Öffnen, es sind viele Karten.
func refresh() -> void:
	if tabs == null or shop == null or not is_visible_in_tree():
		return
	if not _built:
		_built = true
		_build()
	_update_locks()


## Aufträge nach der Maschine sortieren, an der sie gefertigt werden.
static func by_machine() -> Dictionary:
	var out := {}
	for k in JobBoard.all_keys():
		var m := JobBoard.machine_of(str(k))
		if not out.has(m):
			out[m] = []
		out[m].append(str(k))
	return out


func _build() -> void:
	var groups := by_machine()
	for m in groups:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		tabs.set_tab_title(tabs.get_tab_count() - 1, "%s (%d)" % [str(Layout.SPECS[m]["title"]).replace(" konventionell", ""), groups[m].size()])
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)
		for k in groups[m]:
			list.add_child(_card(k, JobBoard.job_of(k)))
			cards += 1
	_head.text = "Alle Aufträge: %d" % cards


func _card(key: String, job: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.sb(Color(0.1, 0.11, 0.12), Color(0.24, 0.26, 0.29)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	var text: String = Jobs.describe(job, true) if job.has("stock_d") else MillJobs.describe(job, true)
	l.text = "%s\nTipp: %s" % [text, str(job.get("desc", "-")).replace("Tipp: ", "")]
	h.add_child(l)
	var v := VBoxContainer.new()
	h.add_child(v)
	var state := Label.new()
	state.name = "Status"
	state.set_meta("key", key)
	state.add_theme_font_size_override("font_size", 13)
	state.custom_minimum_size.x = 220
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(state)
	var b := UITheme.button("Zeichnung", _show_drawing.bind(job), 180)
	b.custom_minimum_size.y = 34
	b.focus_mode = Control.FOCUS_NONE
	v.add_child(b)
	return card


## Zeigt für jeden Auftrag, ob er gerade freigeschaltet wäre.
func _update_locks() -> void:
	for s in tabs.find_children("Status", "Label", true, false):
		var reason: String = JobBoard.lock_reason(str(s.get_meta("key")), shop.company)
		s.text = "Frei" if reason == "" else reason
		s.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if reason == "" else Color(0.95, 0.7, 0.35))


func _show_drawing(job: Dictionary) -> void:
	shop.drawing.show_job(job)
