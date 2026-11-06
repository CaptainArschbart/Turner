class_name JobMenu
extends CanvasLayer
## Auftragsmenü auf der Tab-Taste: je Maschinenart ein Reiter mit den angenommenen Aufträgen. Hier wählt
## man, welcher oben rechts steht. Angenommen wird am PC. Öffnet nur, solange man nicht an einer Maschine
## oder am PC arbeitet.

## Spielwelt: player, company, accepted, tracked, select_job(key), job_status_of(key)
var world: Node
var tabs: TabContainer
var pages: Dictionary = {}
var _money: Label
var _pitch := 0.0


func _ready() -> void:
	layer = 14
	visible = false
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UITheme.title("Aufträge")
	t.add_theme_color_override("font_color", UITheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 18)
	_money.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	head.add_child(_money)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(1120, 520)
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	tabs.add_theme_font_size_override("font_size", 15)
	v.add_child(tabs)
	for c in JobBoard.CATEGORIES:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		tabs.set_tab_title(tabs.get_tab_count() - 1, c["title"])
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 10)
		scroll.add_child(list)
		pages[c["id"]] = list
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", UITheme.MUTED)
	hint.text = "Tab oder Esc schließt"
	v.add_child(hint)


func can_open() -> bool:
	return world.player.operating == null and not world.get_tree().paused and not world.build_menu.active


func open() -> void:
	if visible or not can_open():
		return
	refresh()
	visible = true
	_pitch = world.player.pitch
	world.player.start_operating(self, world.player.global_position, world.player.yaw)


func close() -> void:
	if not visible:
		return
	visible = false
	world.player.stop_operating()
	world.player.pitch = _pitch


func _input(event: InputEvent) -> void:
	if visible:
		if event.is_action_pressed("job_menu") or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			close()
	elif event.is_action_pressed("job_menu") and can_open():
		get_viewport().set_input_as_handled()
		open()


## Aufträge neu aufbauen.
func refresh() -> void:
	_money.text = "Werkstattkasse: %d EUR" % int(world.money)
	for c in JobBoard.CATEGORIES:
		var list: VBoxContainer = pages[c["id"]]
		for k in list.get_children():
			list.remove_child(k)
			k.free()
		var id := str(c["id"])
		var keys := _keys_of(id)
		if JobBoard.JOB_MACHINES.has(id):
			if keys.is_empty():
				list.add_child(_empty(c))
			for k in keys:
				var due := "Frist: %s\n" % JobsTab.days_text(int(world.deadlines.get(k, world.day)) - int(world.day))
				list.add_child(_card({"text": JobBoard.describe_key(k, world.company)}, due + world.job_status_of(k), k))
			continue
		var jobs := []
		for k in world.accepted + world.grind_jobs:
			jobs.append(JobBoard.job_of(str(k)))
		var found: Array = JobBoard.grind_entries(id, jobs, world.company)
		if found.is_empty():
			list.add_child(_empty(c))
		for e in found:
			list.add_child(_card(e, "", ""))


func _keys_of(machine: String) -> Array:
	var out := []
	for k in world.accepted:
		if JobBoard.key_machine(str(k)) == machine:
			out.append(str(k))
	return out


func _empty(c: Dictionary) -> Control:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UITheme.MUTED)
	if not world.company.owns_kind(str(c["id"])):
		l.text = "Die Werkstatt besitzt noch keine %s. Aufträge gibt es erst, wenn sie vorhanden ist." % c["machine"]
	elif JobBoard.JOB_MACHINES.has(str(c["id"])):
		l.text = "Kein Auftrag angenommen. Aufträge gibt es am PC im Büro."
	elif str(c["id"]) in ["round_grinder", "flat_grinder"]:
		l.text = "Gerade verlangt kein Auftrag eine solche geschliffene Fläche."
	else:
		l.text = "Zurzeit keine Aufträge."
	return l


## key = Auftrag, der sich oben rechts anzeigen lässt, leer bei abgeleiteten Schleifaufträgen.
func _card(entry: Dictionary, status: String, key: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.sb(Color(0.1, 0.11, 0.12), Color(0.24, 0.26, 0.29)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var l := Label.new()
	l.text = str(entry["text"])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 16)
	v.add_child(l)
	if status != "":
		var s := Label.new()
		s.text = status
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.add_theme_font_size_override("font_size", 15)
		s.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
		v.add_child(s)
	if key != "":
		var shown: bool = world.tracked == key
		var b := UITheme.button("Steht oben rechts" if shown else "Oben rechts anzeigen", select.bind(key), 260)
		b.custom_minimum_size.y = 38
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = shown
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(b)
	return card


func select(key: String) -> void:
	world.select_job(key)
	refresh()
