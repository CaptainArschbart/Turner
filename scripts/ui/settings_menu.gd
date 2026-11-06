class_name SettingsMenu
extends PanelContainer
## Einstellungs-Fenster (Grafik / Audio / Tastatur / Maus). Wird im Haupt- und Pause-Menü genutzt.

signal closed

var _waiting_action := ""
var _waiting_button: Button
var _tabs: TabContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.menu()
	custom_minimum_size = Vector2(940, 640)
	_build()


func open() -> void:
	visible = true
	_build()


func close() -> void:
	_cancel_wait()
	Settings.save_settings()
	visible = false
	closed.emit()


func _build() -> void:
	var tab_idx := _tabs.current_tab if is_instance_valid(_tabs) else 0
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	root.add_child(UITheme.heading("Einstellungen"))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_build_graphics()
	_build_audio()
	_build_keys()
	_build_mouse()
	_tabs.current_tab = clampi(tab_idx, 0, _tabs.get_tab_count() - 1)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	bottom.add_child(UITheme.button("Standard wiederherstellen", func():
		Settings.reset_defaults()
		_build(), 260))
	bottom.add_child(UITheme.button("Zurück", close, 180))


# ------------------------------------------------------------ Hilfsfunktionen

func _page(page_name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = page_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	_tabs.add_child(sc)
	return v


func _row(parent: Control, label_text: String, control: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 340
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	parent.add_child(h)


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UITheme.BLUE_HI)
	l.add_theme_font_override("font", UITheme.font(600, 2))
	l.add_theme_font_size_override("font_size", 15)
	l.text = text.to_upper()
	parent.add_child(l)


func _option(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = clampi(selected, 0, items.size() - 1)
	o.item_selected.connect(cb)
	return o


func _check(val: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = val
	c.text = "An" if val else "Aus"
	c.toggled.connect(func(on: bool):
		c.text = "An" if on else "Aus"
		cb.call(on))
	return c


func _slider(minv: float, maxv: float, step: float, val: float, cb: Callable, fmt := "%d %%", mult := 100.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.custom_minimum_size.x = 80
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.text = fmt % (val * mult)
	s.value_changed.connect(func(v: float):
		l.text = fmt % (v * mult)
		cb.call(v))
	h.add_child(s)
	h.add_child(l)
	return h


# ------------------------------------------------------------ Seiten

func _build_graphics() -> void:
	var p := _page("Grafik")
	var g := Settings.graphics
	_header(p, "Anzeige")
	_row(p, "Fenstermodus", _option(Settings.WINDOW_MODES, int(g["window_mode"]),
		func(i: int): Settings.set_value("graphics", "window_mode", i)))
	var res_names: Array = []
	for r in Settings.RESOLUTIONS:
		res_names.append("%d x %d" % [r.x, r.y])
	_row(p, "Auflösung (Fenster)", _option(res_names, int(g["resolution"]),
		func(i: int): Settings.set_value("graphics", "resolution", i)))
	_row(p, "VSync", _check(bool(g["vsync"]), func(on: bool): Settings.set_value("graphics", "vsync", on)))
	var fps_names: Array = []
	var fps_sel := 0
	for i in Settings.FPS_LIMITS.size():
		var f: int = Settings.FPS_LIMITS[i]
		fps_names.append("Unbegrenzt" if f == 0 else "%d FPS" % f)
		if f == int(g["fps_limit"]):
			fps_sel = i
	_row(p, "FPS-Limit", _option(fps_names, fps_sel,
		func(i: int): Settings.set_value("graphics", "fps_limit", Settings.FPS_LIMITS[i])))
	_row(p, "FPS anzeigen", _check(bool(g["show_fps"]), func(on: bool): Settings.set_value("graphics", "show_fps", on)))

	_header(p, "Qualität")
	_row(p, "Grafikqualität (Schatten, SSAO, Reflexionen)", _option(Settings.QUALITY_NAMES, int(g["quality"]),
		func(i: int): Settings.set_value("graphics", "quality", i)))
	_row(p, "Kantenglättung", _option(Settings.MSAA_NAMES, int(g["msaa"]),
		func(i: int): Settings.set_value("graphics", "msaa", i)))
	_row(p, "Render-Skalierung", _slider(0.5, 1.0, 0.05, float(g["render_scale"]),
		func(v: float): Settings.set_value("graphics", "render_scale", v)))
	_row(p, "Sichtfeld (FOV)", _slider(60, 100, 1, float(g["fov"]),
		func(v: float): Settings.set_value("graphics", "fov", v), "%d°", 1.0))
	_row(p, "Helligkeit", _slider(0.5, 1.6, 0.05, float(g["brightness"]),
		func(v: float): Settings.set_value("graphics", "brightness", v)))
	_row(p, "Bloom (Leuchten heller Flächen, 0 % = aus)", _slider(0.0, 2.0, 0.05, float(g["bloom"]),
		func(v: float): Settings.set_value("graphics", "bloom", v)))


func _build_audio() -> void:
	var p := _page("Audio")
	var a := Settings.audio
	_row(p, "Gesamtlautstärke", _slider(0, 1, 0.01, float(a["master"]),
		func(v: float): Settings.set_value("audio", "master", v)))
	_row(p, "Maschinengeräusche", _slider(0, 1, 0.01, float(a["sfx"]),
		func(v: float): Settings.set_value("audio", "sfx", v)))
	_row(p, "Werkstatt-Atmosphäre", _slider(0, 1, 0.01, float(a["ambient"]),
		func(v: float): Settings.set_value("audio", "ambient", v)))
	_row(p, "Stummschalten", _check(bool(a["mute"]), func(on: bool): Settings.set_value("audio", "mute", on)))


func _build_keys() -> void:
	var p := _page("Tastatur")
	var hint := Label.new()
	hint.text = "Auf eine Belegung klicken und neue Taste / Maustaste drücken. Esc bricht ab."
	hint.add_theme_color_override("font_color", UITheme.MUTED)
	p.add_child(hint)
	var group := ""
	for b in Settings.BINDINGS:
		if b[2] != group:
			group = b[2]
			_header(p, group)
		var action: String = b[0]
		var btn := Button.new()
		btn.text = Settings.binding_text(action)
		btn.custom_minimum_size = Vector2(220, 38)
		btn.pressed.connect(_start_wait.bind(action, btn))
		_row(p, b[1], btn)


func _build_mouse() -> void:
	var p := _page("Maus")
	var m := Settings.mouse
	_row(p, "Mausempfindlichkeit", _slider(0.05, 1.0, 0.01, float(m["sensitivity"]),
		func(v: float): Settings.set_value("mouse", "sensitivity", v)))
	_row(p, "Y-Achse invertieren", _check(bool(m["invert_y"]),
		func(on: bool): Settings.set_value("mouse", "invert_y", on)))
	_header(p, "Handrad (Mausrad an der Drehmaschine)")
	_row(p, "Schritt pro Mausrad-Raste", _option(Settings.HANDWHEEL_NAMES, int(m["handwheel_step"]),
		func(i: int): Settings.set_value("mouse", "handwheel_step", i)))
	_row(p, "Drehrichtung umkehren", _check(bool(m["handwheel_invert"]),
		func(on: bool): Settings.set_value("mouse", "handwheel_invert", on)))
	var info := Label.new()
	info.text = "An der Drehmaschine:\n  Mausrad = Handrad der gewählten Achse (X im Durchmesser, Z in mm)\n  %s = Handrad-Achse X / Z umschalten\n  %s = Schritt umschalten (0,001 / 0,01 / 0,1 mm) - auch während der Arbeit\n  Rechte Maustaste halten = Kamera drehen, dabei Mausrad = Zoom\n  Mittlere Maustaste halten = Ansicht verschieben\n  %s / %s / %s = Draufsicht / Vorderansicht / Standard" % [
		Settings.binding_text("hw_axis"), Settings.binding_text("hw_step"),
		Settings.binding_text("cam_top"), Settings.binding_text("cam_front"), Settings.binding_text("cam_reset")]
	info.add_theme_color_override("font_color", UITheme.MUTED)
	p.add_child(info)


# ------------------------------------------------------------ Tastenbelegung

func _start_wait(action: String, btn: Button) -> void:
	_cancel_wait()
	_waiting_action = action
	_waiting_button = btn
	btn.text = "Taste drücken ..."


func _cancel_wait() -> void:
	if _waiting_action != "" and is_instance_valid(_waiting_button):
		_waiting_button.text = Settings.binding_text(_waiting_action)
	_waiting_action = ""
	_waiting_button = null


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _waiting_action == "":
		if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		return
	var accept := false
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_cancel_wait()
			get_viewport().set_input_as_handled()
			return
		accept = true
	elif event is InputEventMouseButton and event.pressed:
		accept = true
	if accept:
		Settings.set_binding(_waiting_action, event)
		_waiting_button.text = Settings.binding_text(_waiting_action)
		_waiting_action = ""
		_waiting_button = null
		get_viewport().set_input_as_handled()
