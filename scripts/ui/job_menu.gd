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
var show_tips := false            # Tipps zu den Aufträgen, standardmäßig aus
var tips_button: Button


func _ready() -> void:
	layer = 14
	visible = false
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UITheme.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.window_style())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(UITheme.window_head("Aufträge", "Angenommen")["box"])
	_money = UITheme.money_label(18)
	_money.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_money)
	tips_button = UITheme.small_button("Tipps: aus", toggle_tips, 160)
	tips_button.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(tips_button)
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
	v.add_child(UITheme.key_hint("%s / Esc  ·  schließen          Neue Aufträge gibt es am PC im Büro" % Settings.binding_text("job_menu")))


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
	world.drawing.close()
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


func toggle_tips() -> void:
	show_tips = not show_tips
	tips_button.text = "Tipps: an" if show_tips else "Tipps: aus"
	refresh()


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
				var text := JobBoard.describe_key(k, world.company)
				if show_tips:
					text += "\nTipp: %s" % str(JobBoard.job_of(k).get("desc", "")).replace("Tipp: ", "")
				list.add_child(_card({"text": text, "job": JobBoard.job_of(k)}, due + world.job_status_of(k), k))
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
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var card := UITheme.card(v, 0.0, key != "" and world.tracked == key)
	# Erste Zeile als Titel, der Rest als Angaben darunter
	var lines := str(entry["text"]).split("\n")
	var t := UITheme.title(lines[0], 18)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	lines.remove_at(0)
	if not lines.is_empty():
		v.add_child(UITheme.note("\n".join(lines), 15, Color(UITheme.TEXT, 0.85)))
	if status != "":
		v.add_child(UITheme.note(status, 14, UITheme.WARN))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if key != "":
		var shown: bool = world.tracked == key
		var b := UITheme.small_button("✓  Steht oben rechts" if shown else "Oben rechts anzeigen", select.bind(key), 240)
		b.disabled = shown
		if not shown:
			UITheme.primary(b)
		row.add_child(b)
	if entry.has("job"):
		row.add_child(UITheme.small_button("Zeichnung", show_drawing.bind(entry["job"]), 160))
	if row.get_child_count() > 0:
		v.add_child(row)
	return card


func show_drawing(job: Dictionary) -> void:
	world.drawing.toggle_job(job)


func select(key: String) -> void:
	world.select_job(key)
	refresh()
