class_name TncScreen
extends Control
## Steuerung am Pult der CNC-Fräsmaschine (CncMill), im Aufbau an eine HEIDENHAIN-Klartextsteuerung (TNC 640 / 620)
## angelehnt: Kopfzeile mit Maschinen-Betriebsart links und Programmier-Betriebsart rechts, darunter die Meldezeile
## (Fehler rot, CE quittiert, Klick klappt die Meldungsliste auf), Hauptfläche, Dialog-/Eingabezeile, acht Softkeys
## mit Umschaltpfeilen, die Tasten der Betriebsarten und eine Maschinen-Bedienleiste (NC-Start/-Stopp, Spindel, KSS,
## Tür, Override-Regler).
## Betriebsarten (show_mode): manual (Manueller Betrieb), mdi (Positionieren mit Handeingabe), single / auto
## (Programmlauf Einzelsatz / Satzfolge), edit (Programmieren, dazu PGM MGT als pgm), test (Programm-Test),
## tools (Werkzeugtabelle TOOL.T, gehört zum Manuellen Betrieb).
## Aufbau: Alle Seiten liegen fertig im Baum und werden nur ein-/ausgeblendet. Listen werden nur neu gefüllt, wenn
## sich der Inhalt ändert; Zahlen und Zustände aktualisiert ein Takt von etwa 10 pro Sekunde. Die Satzdialoge
## stehen in TncDialog, die Grafik des Programm-Tests in TncPlot. Die Steuerung ruft nur die öffentliche Schnittstelle
## von CncMill / MillChannel auf. Eingabefelder (LineEdit) bekommen Tastaturfokus, CncMill leitet die Tasten dann hierher.

const SK_N := 8
const BAR_H := 74.0
const KEY_H := 46.0

# Farben: helles Grau-Blau wie bei der Klartextsteuerung, dunkles Bedienfeld darunter
const C_BG := Color(0.83, 0.86, 0.90)
const C_WIN := Color(0.97, 0.975, 0.985)
const C_LINE := Color(0.50, 0.57, 0.66)
const C_HDR := Color(0.15, 0.22, 0.32)
const C_HDR_ON := Color(0.08, 0.38, 0.70)
const C_HDR_OFF := Color(0.34, 0.41, 0.50)
const C_TXT := Color(0.06, 0.09, 0.14)
const C_MUT := Color(0.36, 0.42, 0.50)
const C_SEL := Color(0.12, 0.40, 0.72)
const C_RUN := Color(1.0, 0.84, 0.28)
const C_OK := Color(0.06, 0.48, 0.20)
const C_WARN := Color(0.80, 0.45, 0.0)
const C_ERR := Color(0.78, 0.08, 0.08)
const C_PANEL := Color(0.13, 0.16, 0.21)
const C_KEY := Color(0.92, 0.93, 0.95)
const C_KEY_LINE := Color(0.40, 0.46, 0.55)

const CYCLE_KEYS := {200: "200\nBOHREN", 233: "233 PLAN-\nFRÄSEN", 251: "251 RECHT-\nECKTASCHE", 252: "252 KREIS-\nTASCHE", 253: "253 NUTEN-\nFRÄSEN"}

static var _mono: Font

var mill: CncMill:
	set(v):
		if mill != null and mill.message.is_connected(_on_message):
			mill.message.disconnect(_on_message)
			mill.power_changed.disconnect(_on_power)
		mill = v
		if mill != null:
			mill.message.connect(_on_message)
			mill.power_changed.connect(_on_power)
var mode := "manual"                   # aktuelle Seite: manual mdi run edit pgm test tools
var pos_view := 0                      # Positionsanzeige: 0 IST, 1 REF, 2 RESTW

var _built := false
var _pending := ""
var _t := 0.0
var _log: Array = []                   # [Text, Klasse, Uhrzeit], neueste zuerst
var _msg := ""
var _msg_cls := "info"
var _power_msg := false
var _spin_dir := 3
var _right := "edit"                   # zuletzt benutzte Programmier-Betriebsart (edit oder test)

# Rahmen
var _hdr_l: PanelContainer
var _hdr_r: PanelContainer
var _hdr_l_lbl: Label
var _hdr_r_lbl: Label
var _chips: Dictionary = {}
var _msg_bar: PanelContainer
var _msg_icon: Label
var _msg_lbl: Label
var _msg_ce: Button
var _msg_list: ItemList
var _msg_list_panel: PanelContainer
var _body: Panel
var _holder: Control
var _pages: Dictionary = {}
var _bar: PanelContainer
var _bar_prompt: Label
var _bar_edit: LineEdit
var _bar_prev: Label
var _sk_btns: Array[Button] = []
var _sk_prev: Button
var _sk_next: Button
var _mode_btns: Dictionary = {}
var _b_start: Button
var _b_stop: Button
var _b_spin: Button
var _b_kss: Button
var _b_door: Button
var _ovr_f: Ovr
var _ovr_r: Ovr

# Softkeys
var _sub := ""                         # Untermenü der Softkeys ("m", "datum", "cycl", "del")
var _row := 0
var _rows: Array = []
var _sk_sig := ""

# Eingabezeile
var _bar_mode := "none"                # none, input, dlg, text, mdi
var _bar_cb := Callable()
var _dlg: TncDialog
var _dlg_edit := -1                    # Zeilenindex, wenn ein vorhandener Satz im Dialog geändert wird
var _dlg_target := "edit"              # edit oder mdi

# Seite Manuell
var _pos_tabs: Array[Button] = []
var _man_val: Array[Label] = []
var _man_sub: Array[Label] = []
var _man_info: Array[Label] = []
var _stat: Dictionary = {}
var _man_hint: Label

# Seite MDI
var _mdi_text := ""
var _mdi_hist: Array[String] = []
var _mdi_list: ItemList
var _mdi_pos: Label
var _mdi_info: Label
var _hist_sig := ""

# Seite Programmlauf
var _run_title: Label
var _run_list: ItemList
var _run_sig := ""
var _run_cur := -2
var _run_stat: Array[Label] = []
var _run_bar: ProgressBar
var _run_state: Label

# Seite Editor
var _prog := ""
var _lines: Array[String] = []
var _cursor := 0
var _perr: Dictionary = {}
var _goto_line := -1
var _ed_title: Label
var _ed_list: ItemList
var _ed_info: Label

# Seite PGM MGT
var _pgm_list: ItemList
var _pgm_sel := 0
var _pgm_info: Label
var _pgm_sig := ""

# Seite Programm-Test
var _test_sig := ""
var _test_res: Dictionary = {}
var _test_title: Label
var _test_sum: Label
var _test_verdict: Label
var _test_errs: ItemList
var _plot: TncPlot
var _section: TncPlot.Section

# Seite Werkzeugtabelle
var _tl_list: ItemList
var _tl_sig := ""
var _tl_sel := 0
var _tl_hint: Label


# ======================================================================= Fremde Bausteine

## Override-Regler der Maschinen-Bedienleiste (Mausklick, Ziehen, Rad).
class Ovr extends Control:
	signal changed(v: float)
	var title := ""
	var value := 1.0
	var vmax := 1.5
	var step := 0.05
	var font: Font
	var _drag := false

	func _init() -> void:
		custom_minimum_size = Vector2(120, 44)
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func set_value(v: float) -> void:
		if not is_equal_approx(v, value):
			value = v
			queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			if mb.pressed:
				_pick(mb.position.x)
		elif mb != null and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_apply(value + (step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -step))
		elif ev is InputEventMouseMotion and _drag:
			_pick((ev as InputEventMouseMotion).position.x)

	func _pick(x: float) -> void:
		_apply(clampf((x - 8.0) / maxf(size.x - 16.0, 1.0), 0.0, 1.0) * vmax)

	func _apply(v: float) -> void:
		v = clampf(snappedf(v, step), 0.0, vmax)
		if not is_equal_approx(v, value):
			value = v
			changed.emit(v)
			queue_redraw()

	func _draw() -> void:
		var f: Font = font if font != null else ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.20, 0.24, 0.30))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.52, 0.62), false, 1.0)
		draw_string(f, Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.78, 0.84, 0.92))
		draw_string(f, Vector2(0, 16), "%d %%" % int(round(value * 100.0)), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, 14, Color.WHITE)
		var tr := Rect2(8, 24, size.x - 16, 12)
		draw_rect(tr, Color(0.07, 0.09, 0.12))
		var w := tr.size.x * clampf(value / vmax, 0.0, 1.0)
		draw_rect(Rect2(tr.position, Vector2(w, tr.size.y)), Color(0.20, 0.62, 0.34) if value <= 1.0 else Color(0.85, 0.55, 0.12))
		var m100 := tr.position.x + tr.size.x * clampf(1.0 / vmax, 0.0, 1.0)
		draw_line(Vector2(m100, tr.position.y - 2), Vector2(m100, tr.end.y + 2), Color(0.9, 0.9, 0.95), 1.0)
		draw_rect(Rect2(tr.position.x + w - 3, tr.position.y - 3, 6, tr.size.y + 6), Color(0.92, 0.94, 0.98))


# ======================================================================= Schriften, Stile, Theme

static func _font_mono() -> Font:
	if _mono == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono", "Liberation Mono", "Courier New"])
		sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		sf.hinting = TextServer.HINTING_LIGHT
		_mono = sf
	return _mono


static func _sb(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 3, mx := 6, my := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	return s


func _key_style(t: Theme, type: String, base: String, bg: Color, border: Color, txt: Color, hover: Color, press: Color, size := 13) -> void:
	t.add_type(type)
	t.set_type_variation(type, base)
	t.set_stylebox("normal", type, _sb(bg, border, 1, 4, 2, 2))
	t.set_stylebox("hover", type, _sb(hover, border, 1, 4, 2, 2))
	t.set_stylebox("pressed", type, _sb(press, border, 1, 4, 2, 2))
	t.set_stylebox("hover_pressed", type, _sb(press, border, 1, 4, 2, 2))
	t.set_stylebox("disabled", type, _sb(bg.darkened(0.12), border.darkened(0.25), 1, 4, 2, 2))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, txt)
	t.set_color("font_hover_color", type, txt)
	t.set_color("font_pressed_color", type, txt)
	t.set_color("font_hover_pressed_color", type, txt)
	t.set_color("font_disabled_color", type, txt.lerp(bg, 0.6))
	t.set_font_size("font_size", type, size)
	t.set_font("font", type, UITheme.font(650))
	t.set_constant("line_spacing", type, -2)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = UITheme.font(500)
	t.default_font_size = 15
	t.set_color("font_color", "Label", C_TXT)
	t.set_font_size("font_size", "Label", 15)
	t.set_stylebox("panel", "PanelContainer", _sb(C_WIN, C_LINE, 1, 3, 6, 4))
	# Softkeys: helle Tasten mit dunkler Schrift
	_key_style(t, "SoftKey", "Button", C_KEY, C_KEY_LINE, C_TXT, Color(0.98, 0.99, 1.0), Color(0.55, 0.75, 0.95), 13)
	_key_style(t, "SoftKeyOn", "Button", Color(0.56, 0.78, 0.96), C_SEL, C_TXT, Color(0.66, 0.84, 0.98), Color(0.45, 0.68, 0.92), 13)
	_key_style(t, "ModeKey", "Button", Color(0.27, 0.32, 0.40), Color(0.52, 0.58, 0.68), Color.WHITE, Color(0.36, 0.42, 0.52), C_SEL, 13)
	_key_style(t, "ModeKeyOn", "Button", C_SEL, Color(0.70, 0.84, 1.0), Color.WHITE, C_SEL.lightened(0.08), C_SEL, 13)
	_key_style(t, "StartKey", "Button", Color(0.10, 0.52, 0.22), Color(0.45, 0.85, 0.55), Color.WHITE, Color(0.14, 0.62, 0.28), Color(0.07, 0.40, 0.17), 16)
	_key_style(t, "StopKey", "Button", Color(0.70, 0.10, 0.10), Color(0.95, 0.50, 0.45), Color.WHITE, Color(0.82, 0.14, 0.14), Color(0.55, 0.06, 0.06), 16)
	_key_style(t, "PanelKey", "Button", Color(0.27, 0.32, 0.40), Color(0.52, 0.58, 0.68), Color.WHITE, Color(0.36, 0.42, 0.52), C_SEL, 13)
	_key_style(t, "PanelKeyOn", "Button", Color(0.92, 0.72, 0.18), Color(1.0, 0.90, 0.55), C_TXT, Color(0.96, 0.78, 0.26), Color(0.85, 0.62, 0.10), 13)
	_key_style(t, "TabKey", "Button", Color(0.72, 0.77, 0.84), C_LINE, C_TXT, Color(0.80, 0.85, 0.92), C_SEL, 14)
	_key_style(t, "TabKeyOn", "Button", C_HDR_ON, Color(0.70, 0.84, 1.0), Color.WHITE, C_HDR_ON.lightened(0.08), C_HDR_ON, 14)
	_key_style(t, "CeKey", "Button", Color(0.90, 0.91, 0.94), C_KEY_LINE, C_TXT, Color.WHITE, Color(0.75, 0.80, 0.9), 15)
	# Eingabefeld
	var mono := _font_mono()
	t.set_font("font", "LineEdit", mono)
	t.set_font_size("font_size", "LineEdit", 18)
	t.set_stylebox("normal", "LineEdit", _sb(Color.WHITE, C_LINE, 1, 2, 6, 3))
	t.set_stylebox("focus", "LineEdit", _sb(Color.WHITE, C_SEL, 2, 2, 6, 3))
	t.set_stylebox("read_only", "LineEdit", _sb(Color(0.88, 0.89, 0.91), C_LINE, 1, 2, 6, 3))
	t.set_color("font_color", "LineEdit", C_TXT)
	t.set_color("font_uneditable_color", "LineEdit", C_MUT)
	t.set_color("caret_color", "LineEdit", C_SEL)
	t.set_color("selection_color", "LineEdit", Color(C_SEL, 0.35))
	# Listen: Sätze in Festschrift
	t.set_font("font", "ItemList", mono)
	t.set_font_size("font_size", "ItemList", 16)
	t.set_stylebox("panel", "ItemList", _sb(C_WIN, C_LINE, 1, 2, 2, 2))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var sel_bg := Color(0.66, 0.80, 0.96)
	t.set_stylebox("selected", "ItemList", _sb(sel_bg, C_SEL, 1, 1))
	t.set_stylebox("selected_focus", "ItemList", _sb(sel_bg, C_SEL, 1, 1))
	t.set_stylebox("hovered", "ItemList", _sb(Color(C_SEL, 0.10), Color(0, 0, 0, 0), 0, 1))
	t.set_stylebox("hovered_selected", "ItemList", _sb(sel_bg, C_SEL, 1, 1))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", C_TXT)
	t.set_color("font_selected_color", "ItemList", C_TXT)
	# Programmlauf: der aktuelle Satz leuchtet gelb
	t.add_type("RunList")
	t.set_type_variation("RunList", "ItemList")
	t.set_stylebox("selected", "RunList", _sb(C_RUN, Color(0.75, 0.55, 0.0), 1, 1))
	t.set_stylebox("selected_focus", "RunList", _sb(C_RUN, Color(0.75, 0.55, 0.0), 1, 1))
	t.set_stylebox("hovered_selected", "RunList", _sb(C_RUN, Color(0.75, 0.55, 0.0), 1, 1))
	t.set_color("font_selected_color", "RunList", C_TXT)
	t.set_color("font_hovered_color", "ItemList", C_TXT)
	t.set_color("guide_color", "ItemList", Color(0, 0, 0, 0.05))
	t.set_constant("v_separation", "ItemList", 3)
	t.set_constant("h_separation", "ItemList", 0)
	for sbt in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sbt, _sb(Color(0.78, 0.81, 0.86), Color(0, 0, 0, 0), 0, 2, 0, 0))
		t.set_stylebox("grabber", sbt, _sb(Color(0.40, 0.47, 0.58), Color(0, 0, 0, 0), 0, 2, 0, 0))
		t.set_stylebox("grabber_highlight", sbt, _sb(C_SEL, Color(0, 0, 0, 0), 0, 2, 0, 0))
		t.set_stylebox("grabber_pressed", sbt, _sb(C_SEL, Color(0, 0, 0, 0), 0, 2, 0, 0))
	t.set_stylebox("background", "ProgressBar", _sb(Color(0.78, 0.81, 0.86), C_LINE, 1, 2, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _sb(Color(0.16, 0.60, 0.32), Color(0, 0, 0, 0), 0, 2, 0, 0))
	return t


func _lbl(text: String, fsize := 15, color := C_TXT, mono := false, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	if mono:
		l.add_theme_font_override("font", _font_mono())
	elif bold:
		l.add_theme_font_override("font", UITheme.font(700))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _btn(text: String, variation: String, cb: Callable, min_w := 0.0, min_h := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.pressed.connect(cb)
	return b


func _vbox(sep := 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _hbox(sep := 4) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _expand(c: Control, h := true, v := false) -> Control:
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


func _panel(color := C_WIN, border := C_LINE, mx := 8, my := 5) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(color, border, 1, 3, mx, my))
	return p


## Seitenwurzel: füllt den Platz über der Eingabezeile.
func _page() -> MarginContainer:
	var p := MarginContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		p.add_theme_constant_override("margin_" + s, 5)
	p.visible = false
	_holder.add_child(p)
	return p


func _list() -> ItemList:
	var l := ItemList.new()
	l.select_mode = ItemList.SELECT_SINGLE
	l.allow_reselect = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.auto_height = false
	return l


# ======================================================================= Aufbau

func _ready() -> void:
	if size.x < 16.0 or size.y < 16.0:
		size = Vector2(768, 600)
	theme = _make_theme()
	clip_contents = true
	var bg := ColorRect.new()
	bg.color = C_PANEL
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 3)
	add_child(root)
	root.add_child(_build_header())
	root.add_child(_build_msg_bar())
	_body = Panel.new()
	_body.add_theme_stylebox_override("panel", _sb(C_BG, C_LINE, 1, 0))
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size.y = 200
	root.add_child(_body)
	_holder = Control.new()
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.offset_left = 1
	_holder.offset_top = 1
	_holder.offset_right = -1
	_holder.offset_bottom = -1
	_body.add_child(_holder)
	_build_bar()
	_pages["manual"] = _build_manual()
	_pages["mdi"] = _build_mdi()
	_pages["run"] = _build_run()
	_pages["edit"] = _build_edit()
	_pages["pgm"] = _build_pgm()
	_pages["test"] = _build_test()
	_pages["tools"] = _build_tools()
	_build_msg_list()
	root.add_child(_build_softkeys())
	root.add_child(_build_mode_row())
	root.add_child(_build_machine_row())
	_built = true
	var first := _pending if _pending != "" else "manual"
	_pending = ""
	_power_msg = true
	show_mode(first)
	_tick()


func _build_header() -> Control:
	var h := _hbox(3)
	h.custom_minimum_size.y = 28
	_hdr_l = PanelContainer.new()
	_hdr_l.custom_minimum_size.x = 236
	_hdr_l_lbl = _lbl("Manueller Betrieb", 16, Color.WHITE, false, true)
	_hdr_l.add_child(_hdr_l_lbl)
	h.add_child(_hdr_l)
	_hdr_r = PanelContainer.new()
	_hdr_r.custom_minimum_size.x = 168
	_hdr_r_lbl = _lbl("Programmieren", 16, Color.WHITE, false, true)
	_hdr_r.add_child(_hdr_r_lbl)
	h.add_child(_hdr_r)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	for k in ["estop", "door", "chan"]:
		var c := PanelContainer.new()
		var l := _lbl("", 13, Color.WHITE, false, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(l)
		c.custom_minimum_size.x = 76
		h.add_child(c)
		_chips[k] = {"panel": c, "lbl": l, "sig": ""}
	_hdr_apply()
	return h


func _chip(key: String, text: String, bg: Color) -> void:
	var c: Dictionary = _chips[key]
	var sig := text + str(bg)
	if c["sig"] == sig:
		return
	c["sig"] = sig
	(c["lbl"] as Label).text = text
	(c["panel"] as PanelContainer).add_theme_stylebox_override("panel", _sb(bg, bg.darkened(0.3), 1, 3, 4, 3))


func _hdr_apply() -> void:
	var left_on := mode in ["manual", "mdi", "run", "tools"]
	_hdr_l.add_theme_stylebox_override("panel", _sb(C_HDR_ON if left_on else C_HDR_OFF, C_HDR, 1, 3, 8, 3))
	_hdr_r.add_theme_stylebox_override("panel", _sb(C_HDR_OFF if left_on else C_HDR_ON, C_HDR, 1, 3, 8, 3))
	match mode:
		"mdi":
			_hdr_l_lbl.text = "Positionieren mit Handeingabe"
		"run":
			_hdr_l_lbl.text = "Programmlauf Einzelsatz" if mill != null and mill.channel.single_block else "Programmlauf Satzfolge"
		_:
			_hdr_l_lbl.text = "Manueller Betrieb"
	_hdr_r_lbl.text = "Programm-Test" if _right == "test" else "Programmieren"


func _build_msg_bar() -> Control:
	_msg_bar = PanelContainer.new()
	_msg_bar.custom_minimum_size.y = 38
	_msg_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_msg_bar.gui_input.connect(_on_msg_input)
	var h := _hbox(6)
	_msg_bar.add_child(h)
	_msg_icon = _lbl("i", 18, Color.WHITE, false, true)
	_msg_icon.custom_minimum_size.x = 24
	_msg_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_msg_icon)
	_msg_lbl = _lbl("", 14)
	_msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg_lbl.max_lines_visible = 2
	_msg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_msg_lbl)
	_msg_ce = _btn("CE", "CeKey", _ce, 44, 28)
	_msg_ce.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_msg_ce)
	_msg_apply(true)
	return _msg_bar


func _build_msg_list() -> void:
	_msg_list_panel = _panel(C_WIN, C_SEL, 4, 4)
	_msg_list_panel.visible = false
	_msg_list_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_msg_list_panel.offset_left = 4
	_msg_list_panel.offset_right = -4
	_msg_list_panel.offset_top = 2
	_msg_list_panel.custom_minimum_size.y = 250
	var v := _vbox(3)
	_msg_list_panel.add_child(v)
	v.add_child(_lbl("MELDUNGEN   (Klick auf die Meldezeile schließt)", 13, C_MUT, false, true))
	_msg_list = _list()
	_msg_list.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_msg_list)
	_body.add_child(_msg_list_panel)


func _build_bar() -> void:
	_bar = _panel(Color(0.93, 0.95, 0.98), C_SEL, 8, 4)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_left = 4
	_bar.offset_right = -4
	_bar.offset_bottom = -4
	_bar.offset_top = -BAR_H
	_bar.visible = false
	var v := _vbox(3)
	_bar.add_child(v)
	_bar_prompt = _lbl("", 14, C_SEL, false, true)
	_bar_prompt.clip_text = true
	v.add_child(_bar_prompt)
	var h := _hbox(8)
	v.add_child(h)
	_bar_edit = LineEdit.new()
	_bar_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar_edit.custom_minimum_size.y = 32
	_bar_edit.select_all_on_focus = false
	_bar_edit.context_menu_enabled = false
	_bar_edit.virtual_keyboard_enabled = false
	_bar_edit.text_submitted.connect(_bar_submit)
	_bar_edit.text_changed.connect(_bar_changed)
	h.add_child(_bar_edit)
	_bar_prev = _lbl("", 15, C_MUT, true)
	_bar_prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar_prev.clip_text = true
	_bar_prev.custom_minimum_size.x = 250
	h.add_child(_bar_prev)
	_body.add_child(_bar)


func _build_softkeys() -> Control:
	var h := _hbox(3)
	h.custom_minimum_size.y = KEY_H
	_sk_prev = _btn("◄", "SoftKey", _sk_switch.bind(-1), 24)
	h.add_child(_sk_prev)
	for i in SK_N:
		var b := _btn("", "SoftKey", _sk_press.bind(i), 0, KEY_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		h.add_child(b)
		_sk_btns.append(b)
	_sk_next = _btn("►", "SoftKey", _sk_switch.bind(1), 24)
	h.add_child(_sk_next)
	return h


func _build_mode_row() -> Control:
	var h := _hbox(3)
	h.custom_minimum_size.y = 38
	var defs := [["manual", "MANUELL"], ["mdi", "MDI\nHANDEINGABE"], ["single", "EINZEL-\nSATZ"], ["auto", "SATZ-\nFOLGE"],
		["edit", "PROGRAMM-\nIEREN"], ["test", "PROGRAMM-\nTEST"], ["tools", "WERKZEUG-\nTABELLE"]]
	for d in defs:
		var b := _btn(str(d[1]), "ModeKey", _on_mode_key.bind(str(d[0])), 0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
		_mode_btns[str(d[0])] = b
	return h


func _build_machine_row() -> Control:
	var h := _hbox(3)
	h.custom_minimum_size.y = 46
	_b_start = _btn("NC-START", "StartKey", _nc_start, 98, 46)
	h.add_child(_b_start)
	_b_stop = _btn("NC-STOPP", "StopKey", _nc_stop, 98, 46)
	h.add_child(_b_stop)
	_b_spin = _btn("SPINDEL\nEIN/AUS", "PanelKey", _spin_toggle, 74, 46)
	h.add_child(_b_spin)
	_b_kss = _btn("KSS", "PanelKey", _kss_toggle, 50, 46)
	h.add_child(_b_kss)
	_b_door = _btn("TÜR", "PanelKey", _door_toggle, 64, 46)
	h.add_child(_b_door)
	_ovr_f = Ovr.new()
	_ovr_f.title = "VORSCHUB F"
	_ovr_f.vmax = 1.5
	_ovr_f.font = UITheme.font(650)
	_ovr_f.changed.connect(_on_ovr_f)
	h.add_child(_ovr_f)
	_ovr_r = Ovr.new()
	_ovr_r.title = "EILGANG"
	_ovr_r.vmax = 1.0
	_ovr_r.step = 0.05
	_ovr_r.font = UITheme.font(650)
	_ovr_r.changed.connect(_on_ovr_r)
	h.add_child(_ovr_r)
	return h


# ======================================================================= Meldungen

func _on_message(text: String, c: Color) -> void:
	_say(text, "err" if c.g < 0.5 else ("warn" if c.b < 0.5 else "info"))


func _on_power(on: bool) -> void:
	if on:
		_power_msg = true
		_msg = ""
		if _built:
			_msg_apply(true)


## Meldung an die Zeile und in die Liste.
func _say(text: String, cls := "info") -> void:
	if text == "":
		return
	if _log.is_empty() or str((_log[0] as Array)[0]) != text:
		_log.push_front([text, cls, Time.get_time_string_from_system()])
		if _log.size() > 40:
			_log.resize(40)
	_msg = text
	_msg_cls = cls
	_power_msg = false
	if _built:
		_msg_apply(true)


func _msg_apply(force := false) -> void:
	if _msg_lbl == null:
		return
	var text := _msg
	var cls := _msg_cls
	if text == "":
		cls = "info"
	if mill != null:
		if mill.estop:
			text = "NOT-HALT betätigt - Entriegeln am roten Pilzdrücker des Pults, dann Maschine neu bereit machen."
			cls = "err"
		elif mill.channel.state == "error" and mill.channel.alarm != "":
			text = "ALARM: " + mill.channel.alarm + "   (CE = Reset)"
			cls = "err"
		elif _power_msg:
			text = "Strom unterbrochen   -   CE drücken"
			cls = "warn"
	if not force and text == _msg_lbl.text and cls == str(_msg_lbl.get_meta("cls", "")):
		return
	_msg_lbl.set_meta("cls", cls)
	_msg_lbl.text = text
	var bg := Color(0.90, 0.92, 0.95)
	var fg := C_TXT
	var ic := "i"
	match cls:
		"err":
			bg = C_ERR
			fg = Color.WHITE
			ic = "!"
		"warn":
			bg = Color(0.99, 0.82, 0.32)
			ic = "!"
		_:
			if text == "":
				ic = ""
	_msg_bar.add_theme_stylebox_override("panel", _sb(bg, bg.darkened(0.3), 1, 3, 6, 3))
	_msg_lbl.add_theme_color_override("font_color", fg)
	_msg_icon.add_theme_color_override("font_color", fg)
	_msg_icon.text = ic
	_msg_ce.visible = text != ""


func _on_msg_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if _msg_list_panel.visible:
			_msg_list_panel.visible = false
			return
		_msg_list.clear()
		for e in _log:
			var a: Array = e
			var idx := _msg_list.add_item("%s  %s" % [str(a[2]), str(a[0])])
			_msg_list.set_item_custom_fg_color(idx, C_ERR if a[1] == "err" else (C_WARN if a[1] == "warn" else C_TXT))
			_msg_list.set_item_tooltip_enabled(idx, false)
		if _log.is_empty():
			_msg_list.add_item("keine Meldungen")
		_msg_list_panel.visible = true


## CE: Meldung löschen, bei Alarm den Kanal zurücksetzen.
func _ce() -> void:
	_msg_list_panel.visible = false
	_power_msg = false
	_msg = ""
	if mill != null and mill.channel.state == "error":
		mill.nc_reset()
	_msg_apply(true)


# ======================================================================= Betriebsarten

func show_mode(m: String) -> void:
	if not _built:
		_pending = m
		return
	var page := m
	match m:
		"machine", "jog", "manual":
			page = "manual"
		"auto", "satzfolge":
			page = "run"
			if mill != null:
				mill.channel.single_block = false
		"single", "einzelsatz":
			page = "run"
			if mill != null:
				mill.channel.single_block = true
		"program", "programmieren":
			page = "edit"
		"tool":
			page = "tools"
	if not _pages.has(page):
		page = "manual"
	_set_page(page)


func _on_mode_key(key: String) -> void:
	show_mode(key)


func _set_page(page: String) -> void:
	if mode == "edit":
		_ed_commit()
	_dlg = null
	_bar_cancel()
	_msg_list_panel.visible = false
	_sub = ""
	_row = 0
	mode = page
	if page == "test":
		_right = "test"
	elif page == "edit" or page == "pgm":
		_right = "edit"
	for k in _pages:
		(_pages[k] as Control).visible = (k == page)
	_page_enter(page)
	_hdr_apply()
	_bar_default()
	_sk_refresh()
	_mode_keys_apply()


func _page_enter(page: String) -> void:
	match page:
		"manual":
			_man_hint_update()
		"mdi":
			_hist_sig = ""
		"run":
			_run_sig = ""
			_run_cur = -2
		"edit":
			if not _ed_open():
				_say("Kein Programm angewählt - PGM MGT wählen oder neu anlegen.", "warn")
				mode = "pgm"
				_right = "edit"
				for k in _pages:
					(_pages[k] as Control).visible = (k == "pgm")
				_pgm_open()
		"pgm":
			_pgm_open()
		"test":
			_test_run(false)
		"tools":
			_tl_sig = ""
			_tl_sel = clampi(mill.tool_t - 1, 0, CncMill.POCKETS - 1) if mill != null and mill.tool_t > 0 else 0


func _mode_keys_apply() -> void:
	var busy := mill != null and mill.channel.single_block
	var on := {
		"manual": mode == "manual", "tools": mode == "tools", "mdi": mode == "mdi",
		"single": mode == "run" and busy, "auto": mode == "run" and not busy,
		"edit": mode == "edit" or mode == "pgm", "test": mode == "test"}
	for k in _mode_btns:
		var b: Button = _mode_btns[k]
		var want := "ModeKeyOn" if on[k] else "ModeKey"
		if b.theme_type_variation != want:
			b.theme_type_variation = want


# ======================================================================= Softkeys

func _k(t: String, cb: Callable, en := Callable(), on := Callable()) -> Dictionary:
	return {"t": t, "cb": cb, "en": en, "on": on}


func _sk_refresh() -> void:
	if not _built or mill == null:
		return
	_rows = _key_rows()
	_row = clampi(_row, 0, maxi(_rows.size() - 1, 0))
	_sk_prev.disabled = _rows.size() <= 1
	_sk_next.disabled = _rows.size() <= 1
	_sk_apply()
	_sk_sig = _sk_signature()


func _sk_signature() -> String:
	return "%s|%s|%s|%s|%s|%s" % [mode, _sub, _bar_mode, str(mill.channel.busy()), str(mill.channel.single_block), str(_dlg != null and _dlg.is_choice())]


func _sk_switch(dir: int) -> void:
	if _rows.size() <= 1:
		return
	_row = posmod(_row + dir, _rows.size())
	_sk_apply()


func _sk_apply() -> void:
	var row: Array = _rows[_row] if _row < _rows.size() else []
	for i in SK_N:
		var b := _sk_btns[i]
		if i >= row.size() or row[i] == null:
			b.text = ""
			b.disabled = true
			continue
		var k: Dictionary = row[i]
		b.text = str(k["t"])
		var en: Callable = k["en"]
		b.disabled = en.is_valid() and not bool(en.call())
		var on: Callable = k["on"]
		var want := "SoftKeyOn" if on.is_valid() and bool(on.call()) else "SoftKey"
		if b.theme_type_variation != want:
			b.theme_type_variation = want


func _sk_press(i: int) -> void:
	var row: Array = _rows[_row] if _row < _rows.size() else []
	if i >= row.size() or row[i] == null:
		return
	var cb: Callable = (row[i] as Dictionary)["cb"]
	if cb.is_valid():
		cb.call()
	_sk_refresh()


func _free() -> bool:
	return mill != null and not mill.channel.busy()


func _set_sub(s: String) -> void:
	_sub = s


func _back_sub() -> void:
	_sub = ""
	_row = 0


func _ent() -> void:
	_bar_submit(_bar_edit.text)


func _reset() -> void:
	mill.nc_reset()


func _toggle_single() -> void:
	mill.channel.single_block = not mill.channel.single_block
	_hdr_apply()
	_mode_keys_apply()


func _is_single() -> bool:
	return mill != null and mill.channel.single_block


func _toggle_feed() -> void:
	_plot.show_feed = not _plot.show_feed


func _is_feed() -> bool:
	return _plot.show_feed


func _toggle_rapid() -> void:
	_plot.show_rapid = not _plot.show_rapid


func _is_rapid() -> bool:
	return _plot.show_rapid


func _can_skip() -> bool:
	return _dlg != null and _dlg.can_skip()


func _can_back() -> bool:
	return _dlg != null and _dlg.i > 0


func _pgm_back() -> void:
	show_mode("run" if mill.channel.busy() else "manual")


func _pgm_activated(_i: int) -> void:
	_pgm_edit()


func _tl_activated(_i: int) -> void:
	_tl_change()


func _on_ovr_f(v: float) -> void:
	if mill != null:
		mill.channel.feed_ovr = v


func _on_ovr_r(v: float) -> void:
	if mill != null:
		mill.channel.rapid_ovr = v


func _back_key() -> Dictionary:
	return _k("ZURÜCK", _back_sub)


## Die Tasten der aktuellen Seite (Zeilen zu je höchstens acht Softkeys).
func _key_rows() -> Array:
	var free := Callable(self, "_free")
	if _bar_mode == "dlg" and _dlg != null:
		return [_dlg_keys()]
	if _bar_mode == "input":
		return [[_k("ENT", _ent), _k("ABBRUCH", _bar_cancel)]]
	match mode:
		"manual":
			match _sub:
				"m":
					return [[_k("M3\nSPINDEL RE", _m_func.bind(3), free), _k("M4\nSPINDEL LI", _m_func.bind(4), free),
						_k("M5\nSPINDEL HALT", _m_func.bind(5), free), _k("M8\nKSS EIN", _m_func.bind(8), free),
						_k("M9\nKSS AUS", _m_func.bind(9), free), _k("M13\nM3 + M8", _m_func.bind(13), free),
						_k("M14\nM4 + M8", _m_func.bind(14), free), _back_key()]]
				"datum":
					return [[_k("BEZUG\nX", _ask_datum.bind(0), free), _k("BEZUG\nY", _ask_datum.bind(1), free),
						_k("BEZUG\nZ", _ask_datum.bind(2), free), _k("ALLE\nAUF 0", _datum_zero, free), null, null, null, _back_key()]]
			return [[_k("M", _set_sub.bind("m")), _k("S", _ask_s, free), _k("F", _ask_f, free),
				_k("BEZUGS-\nPUNKT", _set_sub.bind("datum")), _k("WERKZEUG-\nTABELLE", show_mode.bind("tools")),
				_k("T\nWECHSELN", _ask_t, free), _k("ANZEIGE\n" + ["IST", "REF", "RESTW"][pos_view], _cycle_pos_view), null]]
		"mdi":
			if _sub == "cycl":
				return [_cycl_keys()]
			return [[_k("L", _dlg_new.bind("l"), free), _k("CC", _dlg_new.bind("cc"), free), _k("C", _dlg_new.bind("c"), free),
				_k("TOOL\nCALL", _dlg_new.bind("tool_call"), free), _k("CYCL\nDEF", _set_sub.bind("cycl"), free),
				_k("CYCL\nCALL", _dlg_new.bind("cycl_call"), free), _k("M", _dlg_new.bind("m"), free), _k("EINGABE\nLÖSCHEN", _mdi_clear, free)]]
		"run":
			return [[_k("PGM\nMGT", show_mode.bind("pgm")),
				_k("EINZELSATZ", _toggle_single, Callable(), _is_single),
				_k("INTERNER\nSTOPP", _reset),
				_k("PROGRAMM-\nTEST", show_mode.bind("test")), _k("PROGRAMM-\nIEREN", show_mode.bind("edit")), null, null, null]]
		"edit":
			if _sub == "cycl":
				return [_cycl_keys()]
			var ed := Callable(self, "_ed_free")
			return [
				[_k("L", _dlg_new.bind("l"), ed), _k("CC", _dlg_new.bind("cc"), ed), _k("C", _dlg_new.bind("c"), ed),
					_k("TOOL\nCALL", _dlg_new.bind("tool_call"), ed), _k("CYCL\nDEF", _set_sub.bind("cycl"), ed),
					_k("CYCL\nCALL", _dlg_new.bind("cycl_call"), ed), _k("M", _dlg_new.bind("m"), ed), _k("BLK\nFORM", _dlg_new.bind("blk2"), ed)],
				[_k("LBL\nSET", _dlg_new.bind("lbl"), ed), _k("LBL\nCALL", _dlg_new.bind("call_lbl"), ed), _k("STOP", _dlg_new.bind("stop"), ed),
					_k("KOMMEN-\nTAR", _dlg_new.bind("comment"), ed), _k("DIALOG\nÄNDERN", _dlg_change, ed), null, null, null],
				[_k("SATZ\nLÖSCHEN", _ed_delete, ed), _k("SATZ\nNACH OBEN", _ed_move.bind(-1), ed), _k("SATZ\nNACH UNTEN", _ed_move.bind(1), ed),
					_k("PGM\nMGT", show_mode.bind("pgm")), _k("PROGRAMM-\nTEST", show_mode.bind("test")), null, null, null]]
		"pgm":
			if _sub == "del":
				return [[_k("LÖSCHEN\nJA", _pgm_delete), _k("NEIN", _set_sub.bind("")), null, null, null, null, null, null]]
			return [[_k("ANWÄHLEN", _pgm_select, free), _k("ÖFFNEN\nEDITOR", _pgm_edit, free), _k("NEUES\nPROGRAMM", _pgm_ask_new, free),
				_k("UMBENEN-\nNEN", _pgm_ask_rename, free), _k("KOPIEREN", _pgm_ask_copy), _k("LÖSCHEN", _set_sub.bind("del"), free),
				_k("PROGRAMM-\nTEST", show_mode.bind("test")), _k("ZURÜCK", _pgm_back)]]
		"test":
			return [[_k("START", _test_run.bind(true)),
				_k("BAHN\nVORSCHUB", _toggle_feed, Callable(), _is_feed),
				_k("BAHN\nEILGANG", _toggle_rapid, Callable(), _is_rapid),
				_k("PGM\nMGT", show_mode.bind("pgm")), _k("PROGRAMM-\nIEREN", show_mode.bind("edit")),
				_k("PROGRAMM-\nLAUF", show_mode.bind("auto")), null, null]]
		"tools":
			return [[_k("EIN-\nWECHSELN", _tl_change, free), _k("SPINDEL\nLEEREN", _tl_unload, free), _k("T\nNUMMER", _ask_t, free), null, null, null,
				_k("PGM\nMGT", show_mode.bind("pgm")), _k("ZURÜCK", show_mode.bind("manual"))]]
	return [[]]


func _cycl_keys() -> Array:
	var out: Array = []
	var ed := Callable(self, "_free") if mode == "mdi" else Callable(self, "_ed_free")
	var ids: Array = MillNc.CYCLES.keys()
	ids.sort()
	for id in ids:
		out.append(_k(str(CYCLE_KEYS.get(id, "%d\n%s" % [int(id), str(MillNc.CYCLES[id]["name"])])),
			_dlg_new.bind("cycl_def", {"cycle": int(id)}), ed))
	while out.size() < SK_N - 1:
		out.append(null)
	out.append(_back_key())
	return out


func _dlg_keys() -> Array:
	var out: Array = []
	if _dlg.is_choice():
		var ch: Array = _dlg.choices()
		for i in ch.size():
			out.append(_k(str(ch[i][0]).replace(" ", "\n"), _dlg_choose.bind(i)))
	else:
		out.append(_k("ENT", _ent))
	while out.size() < 4:
		out.append(null)
	out.append_array([_k("NO ENT", _dlg_skip, _can_skip),
		_k("ZURÜCK", _dlg_back, _can_back),
		_k("ENDE", _dlg_end), _k("ABBRUCH", _dlg_abort)])
	return out


# ======================================================================= Eingabezeile

func _bar_show(on: bool) -> void:
	_bar.visible = on
	_holder.offset_bottom = -(BAR_H + 8.0) if on else -1.0


func _bar_cancel() -> void:
	if _bar_edit != null and _bar_edit.has_focus():
		_bar_edit.release_focus()
	_bar_mode = "none"
	_bar_cb = Callable()
	_bar_show(false)


## Ruhezustand der Eingabezeile je Seite: im Editor die Satzzeile, bei MDI die Eingabezeile.
func _bar_default() -> void:
	if mode == "edit":
		_bar_text_open()
	elif mode == "mdi":
		_bar_mdi_open()


## Einzelne Eingabe mit Rückfrage (ENT): cb(text) -> Fehlertext oder "".
func _ask(prompt: String, default: String, cb: Callable) -> void:
	_dlg = null
	_bar_mode = "input"
	_bar_cb = cb
	_bar_prompt.text = prompt
	_bar_edit.visible = true
	_bar_edit.editable = true
	_bar_edit.text = default
	_bar_prev.text = "Enter = ENT"
	_bar_show(true)
	_bar_edit.grab_focus()
	_bar_edit.select_all()
	_sk_refresh()


func _bar_submit(text: String) -> void:
	match _bar_mode:
		"input":
			var cb := _bar_cb
			var err: String = cb.call(text)
			if err != "":
				_say(err, "warn")
			elif _bar_cb == cb:
				_bar_cancel()
				_bar_default()
			_sk_refresh()
		"dlg":
			_dlg_after(_dlg.answer(text))
		"text":
			_ed_commit()
			_bar_edit.release_focus()
		"mdi":
			_mdi_check()
			_bar_edit.release_focus()


func _bar_changed(text: String) -> void:
	match _bar_mode:
		"text":
			_ed_live(text)
		"mdi":
			_mdi_text = text


func _bar_text_open() -> void:
	if _prog == "" or _cursor < 0 or _cursor >= _lines.size():
		_bar_cancel()
		return
	_bar_mode = "text"
	_bar_prompt.text = "SATZ %d   %s" % [_cursor, ("gesperrt - Programm läuft" if mill != null and mill.channel.busy() else "Text ändern, Enter übernimmt (Satz wird geprüft)")]
	_bar_edit.visible = true
	_bar_edit.editable = _ed_free()
	_bar_edit.text = _lines[_cursor]
	_bar_prev.text = str(_perr.get(_cursor, ""))
	_bar_prev.add_theme_color_override("font_color", C_ERR)
	_bar_show(true)


func _bar_mdi_open() -> void:
	_bar_mode = "mdi"
	_bar_prompt.text = "SATZ EINGEBEN   -   NC-START führt ihn aus   (z. B. L X+50 Y+30 FMAX)"
	_bar_edit.visible = true
	_bar_edit.editable = _free()
	_bar_edit.text = _mdi_text
	_bar_prev.text = ""
	_bar_show(true)


# ======================================================================= Satzdialog (Editor und MDI)

func _dlg_new(kind: String, extra: Dictionary = {}) -> void:
	_dlg_begin(kind, {}, extra, mode if mode == "mdi" else "edit", -1)


func _dlg_change() -> void:
	if _cursor < 0 or _cursor >= _lines.size():
		return
	var b := MillNc.parse_line(_lines[_cursor])
	var kind := TncDialog.kind_of(b)
	if kind == "" or kind == "stop":
		_say("Dieser Satz lässt sich nicht im Dialog ändern (Text direkt bearbeiten).", "warn")
		return
	_dlg_begin(kind, b, {}, "edit", _cursor)


func _dlg_begin(kind: String, base: Dictionary, extra: Dictionary, target: String, edit_idx: int) -> void:
	if target == "edit" and not _ed_free():
		_say("Programm läuft - Editor gesperrt.", "warn")
		return
	if target == "mdi" and not _free():
		_say("Programm läuft - erst INTERNER STOPP.", "warn")
		return
	var ctx := {"t": mill.tool_t if mill.tool_t > 0 else 1, "s": mill.rpm_set, "pockets": CncMill.POCKETS,
		"block": Vector3(mill.block_l, mill.block_w, mill.block_h), "name": _prog}
	ctx.merge(extra, true)
	var d := TncDialog.make(kind, base, ctx)
	_dlg_target = target
	_dlg_edit = edit_idx
	if d.steps.is_empty():
		if d.kind == "stop" or d.kind == "cycl_call":
			_dlg = d
			_dlg_done()
		else:
			_say("Dieser Satz lässt sich nicht im Dialog ändern.", "warn")
		return
	_dlg = d
	_bar_mode = "dlg"
	_dlg_show()


func _dlg_show() -> void:
	if _dlg == null:
		return
	if _dlg.finished:
		_dlg_done()
		return
	_bar_mode = "dlg"
	_bar_prompt.text = _dlg.prompt()
	_bar_edit.visible = not _dlg.is_choice()
	_bar_edit.editable = true
	_bar_edit.text = _dlg.default_text()
	_bar_prev.text = _dlg.preview() + " ◄" if _dlg.is_choice() else _dlg.preview()
	_bar_prev.add_theme_color_override("font_color", C_MUT)
	_bar_show(true)
	if _bar_edit.visible:
		_bar_edit.grab_focus()
		_bar_edit.select_all()
	elif _bar_edit.has_focus():
		_bar_edit.release_focus()
	_sk_refresh()


func _dlg_after(err: String) -> void:
	if err != "":
		_say(err, "warn")
		return
	_dlg_show()


func _dlg_choose(i: int) -> void:
	if _dlg != null and i < _dlg.choices().size():
		var val: Variant = _dlg.choices()[i][1]
		if val is String and (val == "RL" or val == "RR"):
			_say("RL/RR (Radiuskorrektur) führt diese Steuerung noch nicht aus - der Programm-Test meldet es.", "info")
		_dlg_after(_dlg.choose(i))


func _dlg_skip() -> void:
	if _dlg != null:
		_dlg_after(_dlg.skip())


func _dlg_back() -> void:
	if _dlg != null:
		_dlg.back()
		_dlg_show()


func _dlg_end() -> void:
	if _dlg != null:
		var err := _dlg.finish()
		_dlg_after(err)


func _dlg_abort() -> void:
	_dlg = null
	_bar_cancel()
	_bar_default()
	_sk_refresh()


func _dlg_done() -> void:
	var d := _dlg
	_dlg = null
	_bar_cancel()
	if d == null:
		return
	var lns := d.lines()
	if _dlg_target == "mdi":
		_mdi_text = lns[0] if not lns.is_empty() else ""
		_bar_default()
		return
	_ed_dialog_result(lns)
	_bar_default()
	_sk_refresh()


# ======================================================================= Maschinen-Bedienleiste

func _nc_start() -> void:
	if mill == null:
		return
	if mode == "mdi":
		if mill.channel.busy():
			mill.nc_start()
		else:
			_mdi_exec()
		return
	if not mill.channel.busy() and mode != "run":
		show_mode("run")
	mill.nc_start()


func _nc_stop() -> void:
	if mill != null:
		mill.nc_stop()


func _spin_toggle() -> void:
	if mill != null:
		if not mill.spindle_on:
			_spin_dir = 3
		mill.toggle_spindle()


func _kss_toggle() -> void:
	if mill != null:
		mill.toggle_coolant()


func _door_toggle() -> void:
	if mill != null:
		mill.toggle_door()


func _flag(b: Button, base: String, on: bool) -> void:
	var want := base + "On" if on else base
	if b.theme_type_variation != want:
		b.theme_type_variation = want


func _machine_update() -> void:
	var ch := mill.channel
	_b_start.disabled = false
	_flag(_b_spin, "PanelKey", mill.spindle_on)
	_flag(_b_kss, "PanelKey", mill.coolant)
	_flag(_b_door, "PanelKey", not mill.door_closed())
	_b_door.text = "TÜR\nZU" if mill.door_closed() else "TÜR\nAUF"
	_ovr_f.set_value(ch.feed_ovr)
	_ovr_r.set_value(ch.rapid_ovr)
	_b_start.text = "NC-START\nläuft" if ch.state == "run" else ("NC-START\nweiter" if ch.state == "hold" else "NC-START")
	_b_stop.disabled = false


# ======================================================================= Seite Manueller Betrieb

func _build_manual() -> Control:
	var p := _page()
	var row := _hbox(8)
	p.add_child(row)
	var left := _vbox(5)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var th := _hbox(4)
	var cap := _lbl("POSITIONSANZEIGE", 13, C_MUT, false, true)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(cap)
	for i in 3:
		var b := _btn(["IST", "REF", "RESTW"][i], "TabKey", _set_pos_view.bind(i), 66, 26)
		th.add_child(b)
		_pos_tabs.append(b)
	left.add_child(th)
	for a in 3:
		var r := _hbox(4)
		var lp := PanelContainer.new()
		lp.add_theme_stylebox_override("panel", _sb(C_HDR, C_HDR, 1, 3, 0, 0))
		lp.custom_minimum_size = Vector2(56, 54)
		var al := _lbl("XYZ"[a], 34, Color.WHITE, false, true)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lp.add_child(al)
		r.add_child(lp)
		var vp := _panel(Color.WHITE, C_LINE, 10, 0)
		vp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vp.custom_minimum_size.y = 54
		var vh := _hbox(6)
		vp.add_child(vh)
		var val := _lbl("+0.000", 36, C_TXT, true)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vh.add_child(val)
		var unit := _lbl("mm", 15, C_MUT)
		unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vh.add_child(unit)
		r.add_child(vp)
		left.add_child(r)
		_man_val.append(val)
	var ip := _panel(C_WIN, C_LINE, 10, 6)
	ip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var iv := _vbox(3)
	ip.add_child(iv)
	for i in 5:
		var l := _lbl("", 18, C_TXT, true)
		l.clip_text = true
		iv.add_child(l)
		_man_info.append(l)
	left.add_child(ip)
	var right := _vbox(5)
	right.custom_minimum_size.x = 244
	row.add_child(right)
	var sp := _panel(C_WIN, C_LINE, 10, 6)
	var sv := _vbox(4)
	sp.add_child(sv)
	sv.add_child(_lbl("STATUS", 13, C_MUT, false, true))
	for k in [["pw", "Steuerung"], ["door", "Kabinentür"], ["estop", "Not-Halt"], ["chan", "NC-Kanal"], ["spin", "Spindel"], ["kss", "Kühlmittel"], ["tc", "Wechsler"]]:
		sv.add_child(_stat_row(str(k[0]), str(k[1])))
	right.add_child(sp)
	var hp := _panel(Color(0.90, 0.93, 0.97), C_LINE, 10, 6)
	hp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_man_hint = _lbl("", 13, C_TXT)
	_man_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_man_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hp.add_child(_man_hint)
	right.add_child(hp)
	return p


func _stat_row(key: String, caption: String) -> Control:
	var h := _hbox(6)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = C_MUT
	h.add_child(dot)
	var n := _lbl(caption, 15, C_TXT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	var v := _lbl("", 15, C_TXT, false, true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	_stat[key] = {"dot": dot, "val": v, "sig": ""}
	return h


func _stat_set(key: String, text: String, color: Color) -> void:
	var e: Dictionary = _stat[key]
	var sig := text + str(color)
	if e["sig"] == sig:
		return
	e["sig"] = sig
	(e["val"] as Label).text = text
	(e["val"] as Label).add_theme_color_override("font_color", color)
	(e["dot"] as ColorRect).color = color


func _man_hint_update() -> void:
	var b := func(a: String) -> String: return Settings.binding_text(a)
	_man_hint.text = "TIPPEN  (Taste halten)\nX  %s / %s     Y  %s / %s\nZ  %s / %s     schnell  %s\n\nHANDRAD  (Arbeitsansicht)\nMausrad, Achse %s, Schritt %s\n\nNur im Manuellen Betrieb, Tür zu. Ansicht wechseln: %s" % [
		b.call("lathe_z_minus"), b.call("lathe_z_plus"), b.call("lathe_x_out"), b.call("lathe_x_in"), b.call("mill_z_down"), b.call("mill_z_up"),
		b.call("lathe_rapid"), b.call("hw_axis"), b.call("hw_step"), b.call("cam_panel")]


func _set_pos_view(i: int) -> void:
	pos_view = i
	_sk_refresh()


func _cycle_pos_view() -> void:
	pos_view = (pos_view + 1) % 3


func _man_update() -> void:
	var p := Vector3.ZERO
	match pos_view:
		0:
			p = mill.pos()
		1:
			p = mill.machine_pos()
		2:
			p = mill.channel.remaining()
	for a in 3:
		_man_val[a].text = "%+.3f" % p[a]
	for i in 3:
		_flag(_pos_tabs[i], "TabKey", pos_view == i)
	_man_info[0].text = _tool_line()
	var ch := mill.channel
	_man_info[1].text = "S %5d 1/min Soll   Ist %5d   %s" % [int(mill.rpm_set), int(mill.spindle_speed), ("M%d" % _spin_dir) if mill.spindle_on else "M5"]
	_man_info[2].text = "F %5d mm/min   Override F %d %%, Eil %d %%" % [int(mill.feed_set), int(round(ch.feed_ovr * 100.0)), int(round(ch.rapid_ovr * 100.0))]
	_man_info[3].text = "Bezugspunkt  X%+.3f Y%+.3f Z%+.3f" % [mill.datum.x, mill.datum.y, mill.datum.z]
	_man_info[4].text = "Aktiv  %s  %s" % [("M3" if mill.spindle_on else "M5"), ("M8" if mill.coolant else "M9")]
	_stat_set("pw", "bereit", C_OK)
	if mill.door_closed():
		_stat_set("door", "ZU", C_OK)
	elif mill.door_open_ok():
		_stat_set("door", "AUF", C_WARN)
	else:
		_stat_set("door", "FÄHRT", C_WARN)
	_stat_set("estop", "AKTIV" if mill.estop else "frei", C_ERR if mill.estop else C_OK)
	var cs := ch.state_text()
	_stat_set("chan", cs.substr(0, 13), C_OK if ch.state == "run" else (C_ERR if ch.state == "error" else (C_WARN if ch.state == "hold" else C_MUT)))
	_stat_set("spin", ("%d/min" % int(mill.spindle_speed)) if mill.spindle_speed > 5.0 else ("EIN" if mill.spindle_on else "steht"), C_OK if mill.spindle_on else C_MUT)
	_stat_set("kss", "EIN" if mill.coolant else "aus", C_OK if mill.coolant else C_MUT)
	_stat_set("tc", ("%d %%" % int(mill.change_progress() * 100.0)) if mill.changing else "bereit", C_WARN if mill.changing else C_MUT)


func _tool_line() -> String:
	if mill.spindle_empty or mill.tool_t <= 0:
		return "T0   Spindel ist leer"
	var td := mill.tool()
	return "T%d   %s   L %.1f" % [mill.tool_t, str(td["name"]), MillTools.tool_length(td)]


# Aktionen im Manuellen Betrieb

func _m_func(m: int) -> void:
	if not _free():
		_say("Programm läuft - erst INTERNER STOPP.", "warn")
		return
	if m == 3 or m == 4 or m == 13 or m == 14:
		_spin_dir = 4 if (m == 4 or m == 14) else 3
		if not mill.spindle_on:
			mill.toggle_spindle()
		if m >= 13 and not mill.coolant:
			mill.toggle_coolant()
	elif m == 5:
		if mill.spindle_on:
			mill.toggle_spindle()
	elif m == 8:
		if not mill.coolant:
			mill.toggle_coolant()
	elif m == 9:
		if mill.coolant:
			mill.toggle_coolant()


func _ask_s() -> void:
	_ask("S = ?   Spindeldrehzahl in 1/min (10 bis %d)" % int(MillNc.S_MAX), str(int(mill.rpm_set)), _do_s)


func _do_s(t: String) -> String:
	var v: Variant = TncDialog.parse_num(t)
	if v == null or float(v) < 10.0 or float(v) > MillNc.S_MAX:
		return "S muss zwischen 10 und %d liegen." % int(MillNc.S_MAX)
	mill.set_rpm(float(v))
	return ""


func _ask_f() -> void:
	_ask("F = ?   Vorschub in mm/min (1 bis 20000)", str(int(mill.feed_set)), _do_f)


func _do_f(t: String) -> String:
	var v: Variant = TncDialog.parse_num(t)
	if v == null or float(v) < 1.0 or float(v) > 20000.0:
		return "F muss zwischen 1 und 20000 liegen."
	mill.set_feed(float(v))
	return ""


func _ask_datum(axis: int) -> void:
	var nm := "XYZ"[axis]
	_ask("BEZUGSPUNKT %s = ?   (die Anzeige %s wird an der jetzigen Lage auf diesen Wert gesetzt)" % [nm, nm], "0", _do_datum.bind(axis))


func _do_datum(t: String, axis: int) -> String:
	var v: Variant = TncDialog.parse_num(t)
	if v == null:
		return "'%s' ist keine Zahl." % t.strip_edges()
	mill.set_datum(axis, float(v))
	_say("Bezugspunkt %s gesetzt: Anzeige %s = %s" % ["XYZ"[axis], "XYZ"[axis], MillNc.fmt(float(v))], "info")
	return ""


func _datum_zero() -> void:
	for a in 3:
		mill.set_datum(a, 0.0)
	_say("Bezugspunkt X, Y, Z auf die jetzige Lage gesetzt.", "info")


func _ask_t() -> void:
	_ask("T = ?   Werkzeug einwechseln (Platz 1 bis %d, 0 = Spindel leeren)" % CncMill.POCKETS, str(maxi(mill.tool_t, 1)), _do_t)


func _do_t(t: String) -> String:
	var v: Variant = TncDialog.parse_num(t)
	if v == null or absf(float(v) - roundf(float(v))) > 1e-6:
		return "T muss eine ganze Zahl sein."
	var err := mill.tool_change(int(roundf(float(v))))
	if err == "":
		_say("Werkzeugwechsel auf T%d läuft." % int(roundf(float(v))), "info")
	return err


# ======================================================================= Seite MDI

func _build_mdi() -> Control:
	var p := _page()
	var row := _hbox(8)
	p.add_child(row)
	var left := _vbox(5)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var pp := _panel(Color.WHITE, C_LINE, 10, 6)
	var pv := _vbox(2)
	pp.add_child(pv)
	_mdi_pos = _lbl("", 22, C_TXT, true)
	pv.add_child(_mdi_pos)
	_mdi_info = _lbl("", 15, C_MUT, true)
	pv.add_child(_mdi_info)
	left.add_child(pp)
	left.add_child(_lbl("LETZTE SÄTZE   (Klick übernimmt den Satz in die Eingabezeile)", 13, C_MUT, false, true))
	_mdi_list = _list()
	_mdi_list.item_selected.connect(_mdi_pick)
	left.add_child(_mdi_list)
	var right := _panel(Color(0.90, 0.93, 0.97), C_LINE, 10, 6)
	right.custom_minimum_size.x = 214
	var rv := _vbox(3)
	right.add_child(rv)
	rv.add_child(_lbl("BEISPIELE", 13, C_MUT, false, true))
	var ex := _lbl("TOOL CALL 2 Z S3500\nL Z+100 R0 FMAX\nL X+50 Y+30 FMAX\nL IZ-5 F200\nL X+0 Y+0 F300 M3\nM3 / M5 / M8 / M9\nCYCL DEF ...\nCYCL CALL", 14, C_TXT, true)
	rv.add_child(ex)
	var note := _lbl("Satz schreiben, dann NC-START. Die Tür muss zu sein.", 13, C_MUT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(note)
	row.add_child(right)
	return p


func _mdi_pick(i: int) -> void:
	if i >= 0 and i < _mdi_hist.size():
		_mdi_text = _mdi_hist[i]
		if _bar_mode == "mdi":
			_bar_edit.text = _mdi_text


func _mdi_clear() -> void:
	_mdi_text = ""
	if _bar_mode == "mdi":
		_bar_edit.text = ""


## Satz prüfen (Enter): Fehler in die Meldezeile.
func _mdi_check() -> bool:
	var t := _mdi_text.strip_edges()
	if t == "":
		_say("Kein Satz eingegeben.", "warn")
		return false
	var b := MillNc.parse_line(t)
	if str(b["type"]) == "error":
		_say(str(b["err"]), "err")
		return false
	if str(b["type"]) == "empty" or str(b["type"]) == "comment":
		_say("Kommentar - nichts auszuführen.", "info")
		return false
	if str(b["type"]) in ["begin", "end", "blk_form", "lbl", "call_lbl"]:
		_say("Dieser Satz ist nur im Programm sinnvoll.", "warn")
		return false
	_say("Satz in Ordnung - NC-START drücken.", "info")
	return true


func _mdi_exec() -> void:
	if not _mdi_check():
		return
	var t := MillNc.format_block(MillNc.parse_line(_mdi_text.strip_edges()))
	if t == "":
		t = _mdi_text.strip_edges()
	if mill.mdi(t):
		_mdi_text = t
		if _bar_mode == "mdi":
			_bar_edit.text = t
		if _mdi_hist.is_empty() or _mdi_hist[0] != t:
			_mdi_hist.push_front(t)
			if _mdi_hist.size() > 12:
				_mdi_hist.resize(12)
		_hist_sig = ""


func _mdi_update() -> void:
	var p := mill.pos()
	_mdi_pos.text = "X%+9.3f  Y%+9.3f  Z%+9.3f" % [p.x, p.y, p.z]
	_mdi_info.text = "%s   S %d   F %d   Kanal: %s" % [("T%d" % mill.tool_t) if mill.tool_t > 0 else "T0", int(mill.rpm_set), int(mill.feed_set), mill.channel.state_text()]
	var sig := "|".join(_mdi_hist)
	if sig != _hist_sig:
		_hist_sig = sig
		_mdi_list.clear()
		for h in _mdi_hist:
			_mdi_list.add_item(h)
		if _mdi_hist.is_empty():
			_mdi_list.add_item("noch kein Satz ausgeführt")
			_mdi_list.set_item_disabled(0, true)


# ======================================================================= Seite Programmlauf

func _build_run() -> Control:
	var p := _page()
	var row := _hbox(8)
	p.add_child(row)
	var left := _vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	_run_title = _lbl("", 15, C_TXT, false, true)
	left.add_child(_run_title)
	_run_list = _list()
	_run_list.theme_type_variation = "RunList"
	_run_list.item_selected.connect(_run_picked)
	left.add_child(_run_list)
	var sp := _panel(C_WIN, C_LINE, 10, 6)
	sp.custom_minimum_size.x = 256
	var sv := _vbox(3)
	sp.add_child(sv)
	_run_state = _lbl("", 17, C_TXT, false, true)
	_run_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_run_state.custom_minimum_size.y = 24
	sv.add_child(_run_state)
	_run_bar = ProgressBar.new()
	_run_bar.max_value = 1.0
	_run_bar.show_percentage = false
	_run_bar.custom_minimum_size.y = 12
	sv.add_child(_run_bar)
	sv.add_child(HSeparator.new())
	for i in 9:
		var l := _lbl("", 15, C_TXT, true)
		l.clip_text = true
		sv.add_child(l)
		_run_stat.append(l)
	row.add_child(sp)
	return p


func _run_picked(_i: int) -> void:
	_run_cur = -2
	_run_sync_sel()


## Programmtext, der gerade gezeigt wird: der laufende bzw. zuletzt gelaufene oder der angewählte.
func _run_lines() -> Array:
	var ch := mill.channel
	if ch.prog_name != "MDI" and not ch.lines.is_empty() and (ch.busy() or ch.state == "done" or ch.state == "error"):
		return ch.lines
	var sel := mill.selected_program()
	return sel.get("lines", []) if not sel.is_empty() else []


func _run_sync_sel() -> void:
	var ch := mill.channel
	var cur := ch.line if ch.busy() else -1
	if cur == _run_cur:
		return
	_run_cur = cur
	if cur >= 0 and cur < _run_list.item_count:
		_run_list.select(cur)
		_run_list.ensure_current_is_visible()
	else:
		_run_list.deselect_all()


func _run_update() -> void:
	var ch := mill.channel
	var lns := _run_lines()
	var sig := "%d|%d|%s" % [lns.size(), (lns as Array).hash(), str(ch.prog_name)]
	if sig != _run_sig:
		_run_sig = sig
		_run_cur = -2
		_run_list.clear()
		for i in lns.size():
			var idx := _run_list.add_item("%3d  %s" % [i, _short(str(lns[i]))])
			if str(lns[i]).strip_edges().begins_with(";"):
				_run_list.set_item_custom_fg_color(idx, C_MUT)
		if lns.is_empty():
			_run_list.add_item("Kein Programm angewählt - PGM MGT")
			_run_list.set_item_disabled(0, true)
		var sel := mill.selected_program()
		var nm := ch.prog_name if (ch.busy() or ch.state == "done" or ch.state == "error") and ch.prog_name != "MDI" else str(sel.get("name", ""))
		_run_title.text = ("PROGRAMM  %s.H    %d Sätze" % [nm, lns.size()]) if nm != "" else "PROGRAMM  -"
	_run_sync_sel()
	var txt := "RESET   -   bereit"
	var col := C_MUT
	match ch.state:
		"run":
			txt = "LÄUFT"
			col = C_OK
		"hold":
			txt = "ANGEHALTEN\n%s" % ch.hold_reason
			col = C_WARN
		"done":
			txt = "PROGRAMM BEENDET"
			col = C_OK
		"error":
			txt = "ALARM"
			col = C_ERR
	_run_state.text = txt
	_run_state.add_theme_color_override("font_color", col)
	_run_bar.value = ch.progress() if ch.state != "idle" else 0.0
	var p := mill.pos()
	var r := ch.remaining()
	_run_stat[0].text = "       IST       RESTW"
	_run_stat[1].text = "X %+9.3f %+9.3f" % [p.x, r.x]
	_run_stat[2].text = "Y %+9.3f %+9.3f" % [p.y, r.y]
	_run_stat[3].text = "Z %+9.3f %+9.3f" % [p.z, r.z]
	_run_stat[4].text = _tool_line().split("   L ")[0]
	_run_stat[5].text = "S %d (%d) 1/min" % [int(mill.rpm_set), int(mill.spindle_speed)]
	_run_stat[6].text = "F %d mm/min  %d %%" % [int(mill.feed_set), int(round(ch.feed_ovr * 100.0))]
	var s := int(ch.run_time)
	_run_stat[7].text = "Laufzeit %d:%02d" % [floori(s / 60.0), s % 60]
	_run_stat[8].text = "Satz %d    Tür %s" % [maxi(ch.line, 0), "zu" if mill.door_closed() else "AUF"]


func _short(s: String, n := 68) -> String:
	return s if s.length() <= n else s.substr(0, n - 1) + "…"


# ======================================================================= Seite Programmieren

func _build_edit() -> Control:
	var p := _page()
	var v := _vbox(4)
	p.add_child(v)
	var th := _hbox(8)
	_ed_title = _lbl("", 15, C_TXT, false, true)
	_ed_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(_ed_title)
	_ed_info = _lbl("", 14, C_MUT, false, true)
	th.add_child(_ed_info)
	v.add_child(th)
	_ed_list = _list()
	_ed_list.item_selected.connect(_ed_selected)
	v.add_child(_ed_list)
	return p


func _ed_free() -> bool:
	return mill != null and _prog != "" and not mill.channel.busy()


## Programm der Anwahl in den Editor laden. false = nichts angewählt.
func _ed_open() -> bool:
	var sel := mill.selected_program()
	if sel.is_empty():
		_prog = ""
		return false
	var nm := str(sel["name"])
	if nm != _prog:
		_cursor = 0
	_prog = nm
	_lines = []
	for l in sel["lines"]:
		_lines.append(str(l))
	if _goto_line >= 0:
		_cursor = _goto_line
		_goto_line = -1
	_cursor = clampi(_cursor, 0, maxi(_lines.size() - 1, 0))
	_ed_rebuild()
	return true


func _ed_item_text(i: int) -> String:
	return "%3d  %s" % [i, _short(_lines[i])]


func _ed_rebuild() -> void:
	_perr.clear()
	for i in _lines.size():
		var b := MillNc.parse_line(_lines[i])
		if str(b["type"]) == "error":
			_perr[i] = str(b["err"])
	_ed_list.clear()
	for i in _lines.size():
		_ed_list.add_item(_ed_item_text(i))
		_ed_color(i)
	if not _lines.is_empty():
		_cursor = clampi(_cursor, 0, _lines.size() - 1)
		_ed_list.select(_cursor)
		_ed_list.ensure_current_is_visible()
	_ed_head()


func _ed_color(i: int) -> void:
	var c := C_TXT
	if _perr.has(i):
		c = C_ERR
	elif _lines[i].strip_edges().begins_with(";"):
		c = C_MUT
	_ed_list.set_item_custom_fg_color(i, c)


func _ed_head() -> void:
	_ed_title.text = "PROGRAMMIEREN    %s.H    %d Sätze" % [_prog, _lines.size()]
	var info := ""
	if not _perr.is_empty():
		info = "%d fehlerhafte Sätze" % _perr.size()
	if mill != null and mill.channel.busy():
		info = "GESPERRT - Programm läuft"
	_ed_info.text = info
	_ed_info.add_theme_color_override("font_color", C_ERR if info != "" else C_MUT)


func _ed_selected(i: int) -> void:
	if _dlg != null:
		_cursor = i
		return
	_ed_commit()
	_cursor = i
	_bar_text_open()


func _ed_save() -> void:
	if _prog != "":
		mill.save_program(_prog, _lines)


## Text während des Tippens sofort in den Satz übernehmen (kein Datenverlust), geprüft wird bei Enter / Wechsel.
func _ed_live(text: String) -> void:
	if not _ed_free() or _cursor < 0 or _cursor >= _lines.size():
		return
	_lines[_cursor] = text
	_ed_save()


## Satz am Cursor prüfen, auf Klartext-Schreibweise bringen und Fehler markieren.
func _ed_commit() -> void:
	if _prog == "" or _cursor < 0 or _cursor >= _lines.size() or mill == null or mill.channel.busy():
		return
	var txt := _lines[_cursor]
	var b := MillNc.parse_line(txt)
	var ty := str(b["type"])
	var rebuild := false
	if ty == "error":
		_perr[_cursor] = str(b["err"])
		_say("Satz %d: %s" % [_cursor, str(b["err"])], "err")
	else:
		_perr.erase(_cursor)
		if ty != "empty":
			var norm := MillNc.format_block(b)
			if norm != "":
				txt = norm
		else:
			txt = ""
		if ty == "begin" and str(b["name"]) != _prog:
			rebuild = _ed_rename(str(b["name"]), _cursor)
			txt = _lines[_cursor]
		elif ty == "end" and str(b["name"]) != _prog:
			txt = "END PGM %s MM" % _prog
			_say("END PGM trägt den Namen des Programms (%s)." % _prog, "warn")
	_lines[_cursor] = txt
	_ed_save()
	if rebuild:
		_ed_rebuild()
	elif _cursor < _ed_list.item_count:
		_ed_list.set_item_text(_cursor, _ed_item_text(_cursor))
		_ed_color(_cursor)
		_ed_head()
	if mode == "edit" and _bar_mode == "text":
		_bar_edit.text = _lines[_cursor] if _cursor < _lines.size() else ""
		_bar_prev.text = str(_perr.get(_cursor, ""))


## BEGIN PGM umbenannt: Programm und END-Satz folgen. true = Zeilen haben sich geändert.
func _ed_rename(nn: String, at: int) -> bool:
	if mill.program(nn).is_empty():
		var pr := mill.program(_prog)
		pr["name"] = nn
		_prog = nn
		_lines = _rename_lines(_lines, nn)
		_ed_save()
		_say("Programm heißt jetzt %s.H" % nn, "info")
		return true
	_say("Ein Programm %s.H gibt es schon." % nn, "err")
	_lines[at] = "BEGIN PGM %s MM" % _prog
	return true


static func _rename_lines(src: Array, nn: String) -> Array[String]:
	var out: Array[String] = []
	for l in src:
		var b := MillNc.parse_line(str(l))
		match str(b["type"]):
			"begin":
				out.append("BEGIN PGM %s MM" % nn)
			"end":
				out.append("END PGM %s MM" % nn)
			_:
				out.append(str(l))
	return out


func _is_type(i: int, ty: String) -> bool:
	return i >= 0 and i < _lines.size() and str(MillNc.parse_line(_lines[i])["type"]) == ty


func _ed_insert_pos() -> int:
	var lo := 1 if _is_type(0, "begin") else 0
	var hi := _lines.size()
	for i in range(_lines.size() - 1, -1, -1):
		if _is_type(i, "end"):
			hi = i
			break
	return clampi(_cursor + 1, lo, hi)


func _ed_dialog_result(lns: Array[String]) -> void:
	if lns.is_empty() or _prog == "":
		return
	if _dlg_edit >= 0 and _dlg_edit < _lines.size():
		_lines[_dlg_edit] = lns[0]
		_cursor = _dlg_edit
	else:
		var at := _ed_insert_pos()
		for i in lns.size():
			_lines.insert(at + i, lns[i])
		_cursor = at + lns.size() - 1
	_ed_save()
	_ed_rebuild()
	for i in lns.size():
		var line := _cursor - lns.size() + 1 + i
		if line >= 0 and line < _lines.size():
			var b := MillNc.parse_line(_lines[line])
			if str(b["type"]) == "error":
				_say("Satz %d: %s" % [line, str(b["err"])], "err")


func _ed_delete() -> void:
	if not _ed_free() or _lines.is_empty():
		return
	if _is_type(_cursor, "begin") or _is_type(_cursor, "end"):
		_say("BEGIN PGM / END PGM bleiben stehen (Programm anlegen und umbenennen in PGM MGT).", "warn")
		return
	_lines.remove_at(_cursor)
	_cursor = clampi(_cursor, 0, maxi(_lines.size() - 1, 0))
	_ed_save()
	_ed_rebuild()
	_bar_text_open()
	_sk_refresh()


func _ed_move(dir: int) -> void:
	var to := _cursor + dir
	if not _ed_free() or to < 0 or to >= _lines.size():
		return
	for i in [_cursor, to]:
		if _is_type(i, "begin") or _is_type(i, "end"):
			_say("BEGIN PGM / END PGM lassen sich nicht verschieben.", "warn")
			return
	var tmp := _lines[_cursor]
	_lines[_cursor] = _lines[to]
	_lines[to] = tmp
	_cursor = to
	_ed_save()
	_ed_rebuild()
	_bar_text_open()


## Zeile anspringen (aus dem Programm-Test).
func goto_block(n: int) -> void:
	_goto_line = n
	show_mode("edit")


# ======================================================================= Seite PGM MGT

func _build_pgm() -> Control:
	var p := _page()
	var row := _hbox(8)
	p.add_child(row)
	var left := _vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add_child(_lbl("PROGRAMM-VERWALTUNG    (» = angewählt für Programmlauf und Test)", 15, C_TXT, false, true))
	_pgm_list = _list()
	_pgm_list.item_selected.connect(_pgm_picked)
	_pgm_list.item_activated.connect(_pgm_activated)
	left.add_child(_pgm_list)
	var right := _panel(Color(0.90, 0.93, 0.97), C_LINE, 10, 6)
	right.custom_minimum_size.x = 232
	_pgm_info = _lbl("", 14, C_TXT)
	_pgm_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pgm_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_pgm_info)
	row.add_child(right)
	return p


func _pgm_picked(i: int) -> void:
	_pgm_sel = i
	_pgm_sig = ""


func _pgm_open() -> void:
	_pgm_sel = mill.prog_sel if mill.prog_sel >= 0 else 0
	_pgm_sig = ""


func _pgm_update() -> void:
	var names: PackedStringArray = []
	for p in mill.programs:
		names.append("%s:%d" % [str(p["name"]), (p["lines"] as Array).size()])
	var sig := "%s|%d|%d|%s" % [",".join(names), mill.prog_sel, _pgm_sel, str(mill.channel.busy())]
	if sig == _pgm_sig:
		return
	_pgm_sig = sig
	_pgm_list.clear()
	for i in mill.programs.size():
		var p: Dictionary = mill.programs[i]
		_pgm_list.add_item("%s %-20s %3d Sätze" % ["»" if i == mill.prog_sel else " ", str(p["name"]) + ".H", (p["lines"] as Array).size()])
	if mill.programs.is_empty():
		_pgm_list.add_item("keine Programme - NEUES PROGRAMM")
		_pgm_list.set_item_disabled(0, true)
	_pgm_sel = clampi(_pgm_sel, 0, maxi(mill.programs.size() - 1, 0))
	if not mill.programs.is_empty():
		_pgm_list.select(_pgm_sel)
		_pgm_list.ensure_current_is_visible()
		var pr: Dictionary = mill.programs[_pgm_sel]
		var desc := ""
		for l in pr["lines"]:
			if str(l).strip_edges().begins_with(";"):
				desc = str(l).strip_edges().trim_prefix(";").strip_edges()
				break
		_pgm_info.text = "%s.H\n\n%d Sätze\n%s\n\n%s" % [str(pr["name"]), (pr["lines"] as Array).size(),
			("angewählt" if _pgm_sel == mill.prog_sel else "nicht angewählt"), desc]
	else:
		_pgm_info.text = "Noch kein Programm.\nNEUES PROGRAMM legt BEGIN PGM, Rohteil und END PGM an."


func _pgm_name() -> String:
	return str(mill.programs[_pgm_sel]["name"]) if _pgm_sel >= 0 and _pgm_sel < mill.programs.size() else ""


func _pgm_select() -> void:
	if _pgm_name() == "":
		return
	if mill.channel.busy():
		_say("Programm läuft - erst INTERNER STOPP.", "warn")
		return
	mill.prog_sel = _pgm_sel
	_run_sig = ""
	_pgm_sig = ""
	_say("%s.H angewählt." % _pgm_name(), "info")


func _pgm_edit() -> void:
	if _pgm_name() == "" or mill.channel.busy():
		return
	mill.prog_sel = _pgm_sel
	show_mode("edit")


func _pgm_ask_new() -> void:
	_ask("NEUER PROGRAMMNAME?   (Buchstaben, Ziffern, Unterstrich)", "", _pgm_do_new)


func _pgm_ask_rename() -> void:
	if _pgm_name() != "":
		_ask("NEUER NAME für %s.H ?" % _pgm_name(), _pgm_name(), _pgm_do_rename)


func _pgm_ask_copy() -> void:
	if _pgm_name() != "":
		_ask("KOPIE von %s.H heißt?" % _pgm_name(), _pgm_name() + "_2", _pgm_do_copy)


func _pgm_check_name(t: String, allow := "") -> String:
	var nn := TncDialog.clean_name(t)
	if nn == "":
		return "Programmname fehlt (Buchstaben, Ziffern, _)."
	if nn != allow and not mill.program(nn).is_empty():
		return "Ein Programm %s.H gibt es schon." % nn
	return ""


func new_program_lines(nn: String) -> Array[String]:
	var out: Array[String] = ["BEGIN PGM %s MM" % nn,
		"BLK FORM 0.1 Z X+0 Y+0 Z%s" % MillNc.fmt(-mill.block_h),
		"BLK FORM 0.2 X%s Y%s Z+0" % [MillNc.fmt(mill.block_l), MillNc.fmt(mill.block_w)],
		"END PGM %s MM" % nn]
	return out


func _pgm_do_new(t: String) -> String:
	var err := _pgm_check_name(t)
	if err != "":
		return err
	var nn := TncDialog.clean_name(t)
	mill.save_program(nn, new_program_lines(nn))
	var idx := mill.programs.size() - 1
	if not mill.channel.busy():
		mill.prog_sel = idx
	_pgm_sel = idx
	_prog = ""
	_say("%s.H angelegt." % nn, "info")
	if not mill.channel.busy():
		show_mode("edit")
	return ""


func _pgm_do_rename(t: String) -> String:
	var old := _pgm_name()
	var err := _pgm_check_name(t, old)
	if err != "":
		return err
	var nn := TncDialog.clean_name(t)
	var pr: Dictionary = mill.programs[_pgm_sel]
	pr["name"] = nn
	pr["lines"] = _rename_lines(pr["lines"], nn)
	if _prog == old:
		_prog = nn
	_pgm_sig = ""
	_say("%s.H heißt jetzt %s.H" % [old, nn], "info")
	return ""


func _pgm_do_copy(t: String) -> String:
	var err := _pgm_check_name(t)
	if err != "":
		return err
	var nn := TncDialog.clean_name(t)
	var src: Dictionary = mill.programs[_pgm_sel]
	mill.save_program(nn, _rename_lines(src["lines"], nn))
	_pgm_sel = mill.programs.size() - 1
	_pgm_sig = ""
	_say("%s.H kopiert nach %s.H" % [str(src["name"]), nn], "info")
	return ""


func _pgm_delete() -> void:
	var nm := _pgm_name()
	_sub = ""
	if nm == "" or mill.channel.busy():
		return
	mill.delete_program(nm)
	if _prog == nm:
		_prog = ""
	_pgm_sel = clampi(_pgm_sel, 0, maxi(mill.programs.size() - 1, 0))
	_pgm_sig = ""
	_run_sig = ""
	_say("%s.H gelöscht." % nm, "info")


# ======================================================================= Seite Programm-Test

func _build_test() -> Control:
	var p := _page()
	var row := _hbox(8)
	p.add_child(row)
	var left := _vbox(4)
	left.custom_minimum_size.x = 282
	row.add_child(left)
	_test_title = _lbl("", 15, C_TXT, false, true)
	left.add_child(_test_title)
	var sp := _panel(C_WIN, C_LINE, 8, 5)
	var sv := _vbox(3)
	sp.add_child(sv)
	_test_sum = _lbl("", 14, C_TXT, true)
	_test_sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(_test_sum)
	_test_verdict = _lbl("", 17, C_MUT, false, true)
	sv.add_child(_test_verdict)
	left.add_child(sp)
	left.add_child(_lbl("FEHLER   (Klick springt zum Satz)", 13, C_MUT, false, true))
	_test_errs = _list()
	_test_errs.add_theme_font_size_override("font_size", 14)
	_test_errs.max_text_lines = 3
	_test_errs.max_columns = 1
	_test_errs.same_column_width = true
	_test_errs.fixed_column_width = 266
	_test_errs.item_selected.connect(_test_err_picked)
	left.add_child(_test_errs)
	var right := _vbox(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_plot = TncPlot.new()
	_plot.font = UITheme.font(600)
	_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plot.custom_minimum_size = Vector2(200, 150)
	right.add_child(_plot)
	_section = TncPlot.Section.new()
	_section.font = UITheme.font(600)
	_section.custom_minimum_size = Vector2(200, 86)
	right.add_child(_section)
	return p


func _test_err_picked(i: int) -> void:
	if i < 0 or i >= _test_errs.item_count:
		return
	var n: Variant = _test_errs.get_item_metadata(i)
	if n is int and int(n) >= 0:
		_say(_test_errs.get_item_text(i), "err")
		goto_block(int(n))


func _test_clear(why: String) -> void:
	_test_res = {}
	_test_sig = ""
	_test_title.text = "PROGRAMM-TEST"
	_test_sum.text = why
	_test_verdict.text = ""
	_test_errs.clear()
	_plot.clear()
	_section.clear()


## Programm mit dem echten Magazin übersetzen, Abtrag rechnen und anzeigen. Nur bei Änderung oder auf START.
func _test_run(force: bool) -> void:
	var sel := mill.selected_program()
	if sel.is_empty():
		_test_clear("Kein Programm angewählt.\nPGM MGT wählen oder ein neues Programm anlegen.")
		return
	var lns: Array = sel["lines"]
	var ctx := mill.nc_context()
	# Bezugspunkt und Startlage gehen in die Übersetzung ein (Endschalter), also auch in die Signatur
	var sig := "%s|%d|%s|%s|%s|%s" % [str(sel["name"]), lns.hash(), ",".join(mill.magazine), "%d,%d,%d" % [int(mill.block_l), int(mill.block_w), int(mill.block_h)],
		str(mill.datum.snappedf(0.001)), str(mill.pos().snappedf(0.1))]
	if not force and sig == _test_sig:
		return
	_test_sig = sig
	var res := MillNc.compile(lns, ctx)
	_test_res = res
	var blk: Dictionary = res["blk"]
	var size := Vector3(mill.block_l, mill.block_w, mill.block_h)
	var shift := Vector3.ZERO
	var from_blk := not blk.is_empty()
	if from_blk:
		var mn: Vector3 = blk["min"]
		var mx: Vector3 = blk["max"]
		size = mx - mn
		shift = Vector3(mn.x, mn.y, mx.z)
	size = Vector3(maxf(size.x, 1.0), maxf(size.y, 1.0), maxf(size.z, 1.0))
	var ops: Array = res["ops"]
	if shift != Vector3.ZERO:
		var moved: Array = []
		for op in ops:
			if str(op["op"]) == "mv":
				var o: Dictionary = (op as Dictionary).duplicate()
				o["to"] = (op["to"] as Vector3) - shift
				moved.append(o)
			else:
				moved.append(op)
		ops = moved
	var cell := maxf(0.5, snappedf(sqrt(size.x * size.y / 24000.0), 0.05))
	var hmap := MillNc.simulate(ops, ctx["tools"], size, cell)
	_plot.info = "Rohteil %s x %s x %s%s" % [MillNc.fmt(size.x).trim_prefix("+"), MillNc.fmt(size.y).trim_prefix("+"),
		MillNc.fmt(size.z).trim_prefix("+"), "" if from_blk else "  (eingespanntes Teil, kein BLK FORM)"]
	_plot.set_result(size, hmap, ops, Vector3.ZERO)
	_section.set_result(size, hmap)
	var errs: Array = res["errs"]
	_test_title.text = "PROGRAMM-TEST    %s.H" % str(sel["name"])
	var secs := int(round(float(res["time"])))
	var tl: PackedStringArray = []
	var tools: Dictionary = ctx["tools"]
	for t in res["tools"]:
		var td: Variant = tools.get(int(t))
		tl.append("T%d %s" % [int(t), str((td as Dictionary).get("name", "?")) if td is Dictionary else "(nicht im Magazin)"])
	_test_sum.text = "Sätze      %d\nLaufzeit   ca. %d:%02d min\nWerkzeuge  %s" % [lns.size(), floori(secs / 60.0), secs % 60,
		"keine" if tl.is_empty() else "\n           ".join(tl)]
	_test_verdict.text = "KEINE FEHLER" if errs.is_empty() else ("%d FEHLER" % errs.size())
	_test_verdict.add_theme_color_override("font_color", C_OK if errs.is_empty() else C_ERR)
	_test_errs.clear()
	var rx := RegEx.new()
	rx.compile("^Satz (\\d+):")
	for e in errs:
		var idx := _test_errs.add_item(str(e))
		var m := rx.search(str(e))
		_test_errs.set_item_metadata(idx, int(m.get_string(1)) if m != null else -1)
		_test_errs.set_item_custom_fg_color(idx, C_ERR)
	if errs.is_empty():
		var i0 := _test_errs.add_item("Programm ist in Ordnung.")
		_test_errs.set_item_custom_fg_color(i0, C_OK)
		_test_errs.set_item_selectable(i0, false)
	if force:
		_say("Programm-Test: %s" % ("keine Fehler" if errs.is_empty() else "%d Fehler" % errs.size()), "info" if errs.is_empty() else "warn")


# ======================================================================= Seite Werkzeugtabelle

func _build_tools() -> Control:
	var p := _page()
	var v := _vbox(4)
	p.add_child(v)
	v.add_child(_lbl("WERKZEUGTABELLE    TOOL.T    Magazin mit %d Plätzen" % CncMill.POCKETS, 15, C_TXT, false, true))
	v.add_child(_lbl(_tool_row_text("  T", "NAME", "Ø", "L", "ZUSTAND"), 14, C_MUT, true))
	_tl_list = _list()
	_tl_list.item_selected.connect(_tl_picked)
	_tl_list.item_activated.connect(_tl_activated)
	v.add_child(_tl_list)
	_tl_hint = _lbl("Bestücken: Kabinentür öffnen, das Werkzeug von der Werkbank in die Spindel setzen (Linksklick). Es belegt den Platz der aktiven T-Nummer, sonst den ersten freien. Einwechseln nur bei stehender Spindel und geschlossener Tür.", 13, C_MUT)
	_tl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_tl_hint)
	return p


static func _tool_row_text(t: String, name: String, d: String, l: String, state: String) -> String:
	return "%s  %s %7s %7s  %s" % [t.rpad(5), name.rpad(18), d, l, state]


func _tl_picked(i: int) -> void:
	_tl_sel = i


func _tl_change() -> void:
	if not _free():
		return
	var err := mill.tool_change(_tl_sel + 1)
	if err == "":
		_say("Werkzeugwechsel auf T%d läuft." % (_tl_sel + 1), "info")


func _tl_unload() -> void:
	if not _free():
		return
	var err := mill.tool_change(0)
	if err == "" and not mill.spindle_empty:
		_say("Spindelwerkzeug wird ins Magazin zurückgelegt.", "info")


func _tl_update() -> void:
	var parts: PackedStringArray = []
	for i in CncMill.POCKETS:
		var id := mill.magazine[i]
		parts.append(id + ("%d" % int(mill.tool_stock.wear(id) * 100.0) if id != "" and mill.tool_stock != null else ""))
	var sig := "%s|%d|%s|%d" % [",".join(parts), mill.tool_t, str(mill.changing), _tl_sel]
	if sig == _tl_sig:
		return
	_tl_sig = sig
	_tl_list.clear()
	for i in CncMill.POCKETS:
		var id := mill.magazine[i]
		var mark := "►" if (i + 1 == mill.tool_t and not mill.spindle_empty) else " "
		var txt: String
		var col := C_TXT
		if id == "":
			txt = _tool_row_text("%s T%d" % [mark, i + 1], "---", "", "", "frei")
			col = C_MUT
		else:
			var td := MillTools.by_id(id)
			var state := "ohne Verschleißanzeige"
			if mill.tool_stock != null:
				state = mill.tool_stock.info(id) if mill.tool_stock.has(id) else "nicht vorrätig"
				var w := mill.tool_stock.wear(id)
				col = C_ERR if w > 0.85 else (C_WARN if w > 0.6 else C_TXT)
			if mark == "►":
				state += "   (Spindel)"
			txt = _tool_row_text("%s T%d" % [mark, i + 1], str(td["name"]), "%.1f" % float(td["d"]), "%.1f" % MillTools.tool_length(td), state)
		var idx := _tl_list.add_item(txt)
		_tl_list.set_item_custom_fg_color(idx, col)
	_tl_sel = clampi(_tl_sel, 0, CncMill.POCKETS - 1)
	_tl_list.select(_tl_sel)
	_tl_list.ensure_current_is_visible()


# ======================================================================= Takt

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or mill == null or not _built:
		return
	_t = 0.1
	_tick()


var _hdr_sig := ""
var _lock_sig := ""


func _tick() -> void:
	if mill == null or not _built:
		return
	_msg_apply()
	var ch := mill.channel
	var hs := mode + str(ch.single_block)
	if hs != _hdr_sig:
		_hdr_sig = hs
		_hdr_apply()
		_mode_keys_apply()
	if mill.estop:
		_chip("estop", "NOT-HALT", C_ERR)
	else:
		_chip("estop", "Not-Halt ok", Color(0.30, 0.42, 0.34))
	if mill.door_closed():
		_chip("door", "TÜR ZU", Color(0.30, 0.42, 0.34))
	elif mill.door_open_ok():
		_chip("door", "TÜR AUF", Color(0.78, 0.50, 0.10))
	else:
		_chip("door", "TÜR FÄHRT", Color(0.78, 0.50, 0.10))
	match ch.state:
		"run":
			_chip("chan", "LÄUFT", C_OK)
		"hold":
			_chip("chan", "HALT", Color(0.78, 0.50, 0.10))
		"done":
			_chip("chan", "ENDE", Color(0.30, 0.42, 0.34))
		"error":
			_chip("chan", "ALARM", C_ERR)
		_:
			_chip("chan", "RESET", Color(0.36, 0.43, 0.52))
	_machine_update()
	match mode:
		"manual":
			_man_update()
		"mdi":
			_mdi_update()
		"run":
			_run_update()
		"edit":
			_ed_head()
		"pgm":
			_pgm_update()
		"tools":
			_tl_update()
	var lock := str(ch.busy())
	if lock != _lock_sig:
		_lock_sig = lock
		if _dlg == null and _bar_mode != "input":
			_bar_default()
	if _sk_signature() != _sk_sig:
		_sk_refresh()
	else:
		_sk_apply()
