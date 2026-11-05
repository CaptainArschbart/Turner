extends PanelContainer
## Interaktives Bedienpult der Drehmaschine (Maus): Spindel, Drehzahl / konstante
## Schnittgeschwindigkeit, Vorschub, Auto-Vorschub und Bestückung des Vierfach-Werkzeughalters.
## Alle Bedienelemente nehmen keinen Tastaturfokus, damit WASD, Leertaste usw. weiter die
## Maschine steuern. Wird zweimal benutzt: im HUD (rechts unten) und als Bildschirm am
## Bedienpult der Maschine (SubViewport, siehe Lathe._build_screen).

var lathe: Lathe
## Größe (vor add_child setzen): Schriftgröße, Zeilenhöhe, Mindestbreite
var font_size := 13
var row_h := 26.0
var panel_w := 440.0
## Knopf „Blick aufs Maschinenpult“ zeigen (nur im HUD)
var view_btn := false

var _spindle_btn: Button
var _estop_btn: Button
var _kss_btn: Button
var _rpm: Dictionary
var _vc: Dictionary
var _nmax: Dictionary
var _feed: Dictionary
var _css_btn: CheckButton
var _css_rows: Array[Control] = []
var _rpm_row: Control
var _feed_btns: Array[Button] = []    # Kreuzschalter Auto-Vorschub (meta "dir" = Richtung Z, X)
var _hw_step_btns: Array[Button] = []
var _hw_axis_btns: Array[Button] = []
var _actual: Label
var _slot_opts: Array[OptionButton] = []
var _slot_btns: Array[Button] = []
var _slot_state: Array[Label] = []
var _tool_desc: Label
var _offset_tbl: Label            # Werkzeugkorrekturen der bestückten Plätze
var _status_t := 0.0
var _sb_on: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = panel_w
	_sb_on = UITheme.sb(UITheme.ACCENT.darkened(0.35), UITheme.ACCENT, 2)
	var tabs := TabContainer.new()
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	tabs.add_theme_font_size_override("font_size", font_size)
	add_child(tabs)
	tabs.add_child(_build_spindle_tab())
	tabs.add_child(_build_holder_tab())
	tabs.set_tab_title(0, "Spindel / Vorschub")
	tabs.set_tab_title(1, "Werkzeuge")


# ------------------------------------------------------------ Aufbau

func _build_spindle_tab() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	_spindle_btn = _button("Spindel START", func(): lathe.toggle_spindle())
	_estop_btn = _button("NOT-HALT", func(): lathe.toggle_estop())
	_kss_btn = _button("KSS", func(): lathe.coolant = not lathe.coolant)
	for b in [_spindle_btn, _estop_btn, _kss_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)

	_rpm = _slider_row("Drehzahl", Lathe.RPM_MIN, Lathe.RPM_MAX, 10.0, true,
		func(x): lathe.set_rpm(x),
		func(d): lathe.set_rpm(Lathe._next_step(Lathe.RPM_STEPS, lathe.rpm_set, d)))
	_rpm_row = _rpm["row"]
	v.add_child(_rpm_row)

	_css_btn = CheckButton.new()
	_css_btn.text = "Konstante Schnittgeschwindigkeit (G96)"
	_css_btn.focus_mode = Control.FOCUS_NONE
	_css_btn.add_theme_font_size_override("font_size", font_size)
	_css_btn.toggled.connect(func(on): lathe.set_css(on))
	v.add_child(_css_btn)

	_vc = _slider_row("vc", Lathe.VC_MIN, Lathe.VC_MAX, 5.0, false,
		func(x): lathe.set_vc(x), func(d): lathe.set_vc(lathe.vc_set + 5.0 * d))
	_nmax = _slider_row("n max", Lathe.RPM_MIN, Lathe.RPM_MAX, 50.0, true,
		func(x): lathe.set_rpm_limit(x),
		func(d): lathe.set_rpm_limit(Lathe._next_step(Lathe.RPM_STEPS, lathe.rpm_limit, d)))
	for r in [_vc["row"], _nmax["row"]]:
		v.add_child(r)
		_css_rows.append(r)

	_feed = _slider_row("Vorschub", Lathe.FEED_MIN, Lathe.FEED_MAX, 0.01, false,
		func(x): lathe.set_feed(x), func(d): lathe.set_feed(lathe.feed_set + 0.01 * d))
	v.add_child(_feed["row"])

	# Auto-Vorschub als Kreuzschalter (wie ein Joystick): hoch X-, runter X+, links Z-, rechts Z+
	# (gleiche Anordnung wie W/S/A/D). Nochmal dieselbe Richtung oder Mitte = Stopp.
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	var corner := _small_label("Auto")
	corner.add_theme_color_override("font_color", UITheme.MUTED)
	var cells: Array = [corner, ["↑ X-", 0, -1], null,
		["← Z-", 1, -1], ["Stopp", -1, 0], ["Z+ →", 1, 1],
		null, ["↓ X+", 0, 1], null]
	for c in cells:
		if c == null:
			grid.add_child(Control.new())
		elif c is Control:
			grid.add_child(c)
		else:
			var axis: int = c[1]
			var sgn: int = c[2]
			var b := _button(c[0], func(): lathe.set_auto_dir(axis, sgn), _u(50))
			b.custom_minimum_size.y = row_h * 0.85
			b.set_meta("dir", Vector2i(sgn if axis == 1 else 0, sgn if axis == 0 else 0))
			grid.add_child(b)
			_feed_btns.append(b)
	fr.add_child(grid)
	# Handrad (Mausrad): Schrittweite und Achse wie der Wahlschalter am CNC-Handrad
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hl := _small_label("Handrad (Mausrad)")
	hl.add_theme_color_override("font_color", UITheme.MUTED)
	hv.add_child(hl)
	var hs := HBoxContainer.new()
	for i in Settings.HANDWHEEL_STEPS.size():
		var idx := i
		var b := _button(str(Settings.HANDWHEEL_STEPS[i]).replace(".", ","), func(): Settings.set_handwheel_step(idx))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = row_h * 0.85
		hs.add_child(b)
		_hw_step_btns.append(b)
	hv.add_child(hs)
	var ha := HBoxContainer.new()
	for i in 2:
		var axis := i
		var b := _button(["Achse X", "Achse Z"][i], func(): lathe.set_handwheel_axis(axis))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = row_h * 0.85
		ha.add_child(b)
		_hw_axis_btns.append(b)
	hv.add_child(ha)
	fr.add_child(hv)
	v.add_child(fr)

	_actual = _small_label("")
	_actual.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	v.add_child(_actual)

	var pr := HBoxContainer.new()
	var pe: Array = [["Neues Rohteil", func(): lathe.request_new_part()], ["Prüfen & abgeben", func(): lathe.request_submit()]]
	if view_btn:
		pe.append(["Pult ansehen", func(): lathe.toggle_panel_view()])
	for e in pe:
		var b := _button(e[0], e[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(b)
	v.add_child(pr)
	return v


func _build_holder_tab() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var hint := _small_label("Umspannen nur bei stehender Spindel. Gegenüber (180°) meist frei, "
		+ "der Platz daneben ragt oft über das Werkstück.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = panel_w - 24.0
	hint.add_theme_color_override("font_color", UITheme.MUTED)
	v.add_child(hint)
	for s in Lathe.SLOTS:
		var slot := s
		var row := HBoxContainer.new()
		var l := _small_label("Platz %d" % (s + 1))
		l.custom_minimum_size.x = _u(52)
		row.add_child(l)
		var opt := OptionButton.new()
		opt.focus_mode = Control.FOCUS_NONE
		opt.custom_minimum_size = Vector2(_u(150), row_h)
		opt.add_theme_font_size_override("font_size", font_size)
		opt.get_popup().add_theme_font_size_override("font_size", font_size)
		opt.add_item("- leer -")
		for i in LatheTools.count():
			var t := LatheTools.get_tool(i)
			opt.add_item("%s %s" % [t["id"], t["short"]])
		opt.item_selected.connect(func(idx): _on_mount(slot, idx))
		row.add_child(opt)
		_slot_opts.append(opt)
		var b := _button("Einschwenken", func(): lathe.index_slot(slot))
		b.custom_minimum_size.x = _u(100)
		row.add_child(b)
		_slot_btns.append(b)
		var st := _small_label("")
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		st.clip_text = true
		row.add_child(st)
		_slot_state.append(st)
		v.add_child(row)
	_tool_desc = _small_label("")
	_tool_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tool_desc.custom_minimum_size.x = panel_w - 24.0
	_tool_desc.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	v.add_child(_tool_desc)
	_offset_tbl = _small_label("")
	_offset_tbl.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	v.add_child(_offset_tbl)
	return v


func _on_mount(slot: int, idx: int) -> void:
	var id := "" if idx == 0 else str(LatheTools.get_tool(idx - 1)["id"])
	lathe.mount_tool(slot, id)
	_status_t = 0.0
	_sync_holder()


func _slider_row(title: String, lo: float, hi: float, step: float, exp_edit: bool,
		on_set: Callable, on_step: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	var l := _small_label(title)
	l.custom_minimum_size.x = _u(92)
	row.add_child(l)
	row.add_child(_button("-", func(): on_step.call(-1), row_h))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.exp_edit = exp_edit
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(x): on_set.call(x))
	row.add_child(s)
	row.add_child(_button("+", func(): on_step.call(1), row_h))
	var val := _small_label("")
	val.custom_minimum_size.x = _u(90)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return {"row": row, "slider": s, "value": val}


func _button(text: String, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = Vector2(min_w, row_h)
	b.pressed.connect(cb)
	return b


func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Breiten mit der Schriftgröße mitwachsen lassen (Bezug: Schrift 13)
func _u(w: float) -> float:
	return w * font_size / 13.0


# ------------------------------------------------------------ Anzeige

func _process(delta: float) -> void:
	if lathe == null or not is_visible_in_tree():
		return
	var running := lathe.spindle_on and not lathe.estop
	_spindle_btn.text = "Spindel STOPP" if running else "Spindel START"
	_mark(_spindle_btn, running)
	_mark(_estop_btn, lathe.estop)
	_estop_btn.text = "Not-Halt quitt." if lathe.estop else "NOT-HALT"
	_mark(_kss_btn, lathe.coolant)
	_kss_btn.text = "KSS EIN" if lathe.coolant else "KSS aus"

	_css_btn.set_pressed_no_signal(lathe.css)
	_rpm_row.visible = not lathe.css
	for r in _css_rows:
		r.visible = lathe.css
	_set_slider(_rpm, lathe.rpm_set, "%d /min" % int(lathe.rpm_set))
	_set_slider(_vc, lathe.vc_set, "%d m/min" % int(lathe.vc_set))
	_set_slider(_nmax, lathe.rpm_limit, "%d /min" % int(lathe.rpm_limit))
	_set_slider(_feed, lathe.feed_set, ("%.2f mm/U" % lathe.feed_set).replace(".", ","))
	var ad := lathe.auto_dir()
	for b in _feed_btns:
		_mark(b, b.get_meta("dir") == ad)
	var step_i := int(Settings.mouse["handwheel_step"])
	for i in _hw_step_btns.size():
		_mark(_hw_step_btns[i], i == step_i)
	for i in _hw_axis_btns.size():
		_mark(_hw_axis_btns[i], i == lathe.hw_axis)
	var vc := lathe.cutting_speed()
	var soll := "Soll %d" % int(round(lathe.rpm()))
	if lathe.css and lathe.rpm() >= lathe.rpm_limit - 0.5:
		soll += ", Begrenzung"
	_actual.text = "Ist: n %d /min (%s)   vc %d m/min" % [int(round(lathe.spindle_speed)), soll, int(vc)]

	_status_t -= delta
	if _status_t <= 0.0:
		_status_t = 0.25
		_sync_holder()


func _sync_holder() -> void:
	for s in Lathe.SLOTS:
		var id := str(lathe.holder[s])
		_slot_opts[s].select(LatheTools.index_of(id) + 1 if id != "" else 0)
		var active := s == lathe.active_slot
		_slot_btns[s].text = "AKTIV" if active else "Einschwenken"
		_slot_btns[s].disabled = id == ""
		_mark(_slot_btns[s], active)
		var st := lathe.slot_status(s)
		_slot_state[s].text = str(st["text"])
		_slot_state[s].tooltip_text = str(st["text"])
		var col: Color = [Color(0.7, 0.95, 0.7), Color(1.0, 0.75, 0.2), Color(1.0, 0.35, 0.3)][int(st["level"])]
		if id == "":
			col = UITheme.MUTED
		_slot_state[s].add_theme_color_override("font_color", col)
	var t := lathe.tool()
	_tool_desc.text = "%s %s: %s" % [t["id"], t["name"], t["desc"]]
	# Werkzeugkorrektur wie in der SINUMERIK-Werkzeugliste (L1 in X im Radius, von F zur Schneide)
	var lines: Array[String] = ["Korrektur     D   L1 (X)     L2 (Z)     R    SL"]
	for s in Lathe.SLOTS:
		var sid := str(lathe.holder[s])
		if sid == "":
			continue
		var d := lathe.tool_data(LatheTools.get_tool(LatheTools.index_of(sid)))
		lines.append("%s P%d %-3s  D%d %9.3f  %9.3f  %4.1f   %d" % ["»" if s == lathe.active_slot else " ", s + 1,
			d["t"], d["d"], d["l1"], d["l2"], d["r"], d["sl"]])
	_offset_tbl.text = "\n".join(lines)


func _set_slider(d: Dictionary, v: float, text: String) -> void:
	(d["slider"] as HSlider).set_value_no_signal(v)
	(d["value"] as Label).text = text


func _mark(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", _sb_on)
	else:
		b.remove_theme_stylebox_override("normal")
