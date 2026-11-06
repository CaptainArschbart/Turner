class_name CncScreen
extends Control
## Bedienoberfläche am Pult der Maschine, an SINUMERIK Operate / ShopTurn angelehnt:
## Kopfzeile mit Bereich, Kanalzustand, Schutztür und Meldung; rechts acht vertikale Softkeys
## (Funktionen der Seite), unten acht horizontale Softkeys (Bereiche, rechts davon Seitenfunktionen).
## Bereiche: Maschine (JOG / AUTO), Programm (Arbeitsplan mit Zyklenmasken und Konturrechner,
## Simulation), Programm-Manager, Werkzeuge, Meldungen.
## Eingabefelder bekommen Tastaturfokus; Lathe._input leitet dann die Tasten hierher weiter.

const W := 640.0
const H := 560.0
const SK_W := 82.0
const HDR_H := 42.0
const HSK_H := 30.0
const BODY := Rect2(4.0, HDR_H + 2.0, W - SK_W - 10.0, H - HDR_H - HSK_H - 8.0)

# Dunkles, flaches Design (an aktuelle Steuerungsoberflächen angelehnt): Anthrazit-Flächen,
# abgerundete Kacheln, ein blauer Akzent für Auswahl und aktive Tasten.
const C_BG := Color(0.065, 0.075, 0.09)
const C_HDR := Color(0.04, 0.05, 0.06)
const C_WIN := Color(0.115, 0.13, 0.155)
const C_LINE := Color(0.20, 0.23, 0.27)
const C_TITLE := Color(0.62, 0.78, 1.0)
const C_TXT := Color(0.90, 0.92, 0.95)
const C_MUT := Color(0.55, 0.60, 0.67)
const C_SEL := Color(0.17, 0.50, 0.96)
const C_KEY := Color(0.165, 0.185, 0.215)
const C_FIELD := Color(0.075, 0.085, 0.10)
const C_OK := Color(0.33, 0.86, 0.48)
const C_WARN := Color(1.0, 0.72, 0.26)
const C_ERR := Color(1.0, 0.38, 0.32)

const FORMS := {
	"head": [
		["sc", "SC", "Sicherheitsabst.", "mm", "num"],
		["xt", "XT", "Wechselpunkt X", "Ø mm", "num"],
		["zt", "ZT", "Wechselpunkt Z", "mm", "num"],
		["smax", "S max", "Drehzahlbegrenzung", "1/min", "num"],
		["kss", "KSS", "Kühlschmierstoff", "", ["aus", "ein"]],
	],
	"cut": [
		["mode", "", "Bearbeitung", "", NcCam.MODES],
		["dir", "", "Richtung", "", ["längs", "plan"]],
		["t", "T", "Werkzeug", "", "tool"],
		["f", "F", "Vorschub", "mm/U", "num"],
		["v", "V", "Schnittgeschw.", "m/min", "num"],
		["z0", "Z0", "Startpunkt Z", "mm", "num"],
		["x1", "X1", "Zieldurchmesser", "Ø mm", "num"],
		["z1", "Z1", "Endpunkt Z", "mm", "num"],
		["d", "D", "Zustellung", "mm", "num", "rough"],
		["ux", "UX", "Aufmaß X", "Ø mm", "num", "rough"],
		["uz", "UZ", "Aufmaß Z", "mm", "num", "rough"],
	],
	"stock": [
		["contour", "", "Kontur", "", "contour"],
		["mode", "", "Bearbeitung", "", NcCam.MODES],
		["dir", "", "Richtung", "", ["längs", "plan"]],
		["t", "T", "Werkzeug", "", "tool"],
		["f", "F", "Vorschub", "mm/U", "num"],
		["v", "V", "Schnittgeschw.", "m/min", "num"],
		["d", "D", "Zustellung", "mm", "num", "rough"],
		["ux", "UX", "Aufmaß X", "Ø mm", "num", "rough"],
		["uz", "UZ", "Aufmaß Z", "mm", "num", "rough"],
	],
}
const FORM_TITLES := {"head": "Programmkopf", "cut": "Abspanen (Rechteck)", "stock": "Konturabspanen"}

var lathe: Lathe
var page := "jog"
var vsk: Array[Button] = []
var hsk: Array[Button] = []
var _vsk_cb: Array = []
var _hsk_cb: Array = []
var _pages := {}
var _hdr_area: Label
var _hdr_mid: Label
var _hdr_door: Label
var _hdr_msg: Label
var _log: Array = []
var _tick := 0.0
var _machine_page := "jog"

var _jog_pos: Label
var _jog_mks: Label
var _jog_info: Label
var _auto_title: Label
var _auto_list: ItemList
var _auto_info: Label
var _auto_plot: NcPlot
var _auto_rows := -1
var _pm_list: ItemList
var _pm_name: LineEdit
var open_prog := ""
var _ed_title: Label
var _ed_list: ItemList
var _ed_plot: NcPlot
var _form_title: Label
var _form_grid: GridContainer
var _form_help: Control
var _form_blk: Dictionary = {}
var _form_idx := -1              # Satz, der geändert wird (-1 = neu einfügen bei _form_ins)
var _form_ins := -1
var _ct: Dictionary = {}
var _ct_idx := -1
var _ct_ins := -1
var _ct_sel := 0
var _ct_list: ItemList
var _ct_grid: GridContainer
var _ct_plot: NcPlot
var _sim_plot: NcPlot
var _sim_info: Label
var _tl_opts: Array[OptionButton] = []
var _tl_btns: Array[Button] = []
var _tl_lbl: Array[Label] = []
var _tl_info: Label
var _msg_list: ItemList


func _ready() -> void:
	theme = _theme()
	size = Vector2(W, H)
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_header()
	_build_softkeys()
	_pages["jog"] = _build_jog()
	_pages["auto"] = _build_auto()
	_pages["pm"] = _build_pm()
	_pages["edit"] = _build_edit()
	_pages["form"] = _build_form()
	_pages["contour"] = _build_contour()
	_pages["sim"] = _build_sim()
	_pages["tools"] = _build_tools()
	_pages["msgs"] = _build_msgs()
	for k in _pages:
		add_child(_pages[k])
	if lathe:
		lathe.message.connect(_on_message)
		open_prog = lathe.prog_sel
	show_page("jog")


# ======================================================================= Theme / Bausteine

static func _sb(bg: Color, border: Color, w := 1, radius := 5) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	s.anti_aliasing = true
	return s


## Aktive Taste: Akzentfläche mit hellem Rand oben (wie eine leuchtende Taste).
static func _sb_active() -> StyleBoxFlat:
	var s := _sb(C_SEL, C_SEL.lightened(0.35), 0)
	s.border_width_top = 2
	return s


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 12
	var key := _sb(C_KEY, C_KEY, 0)
	var key_h := _sb(C_KEY.lightened(0.08), C_SEL, 1)
	var key_p := _sb_active()
	var key_d := _sb(Color(0.095, 0.105, 0.125), Color(0, 0, 0, 0), 0)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, key)
		t.set_stylebox("hover", type, key_h)
		t.set_stylebox("pressed", type, key_p)
		t.set_stylebox("hover_pressed", type, key_p)
		t.set_stylebox("disabled", type, key_d)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, C_TXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(0.36, 0.39, 0.44))
	t.set_color("arrow_color", "OptionButton", C_MUT)
	t.set_color("font_color", "Label", C_TXT)
	t.set_stylebox("normal", "LineEdit", _sb(C_FIELD, C_LINE, 1))
	t.set_stylebox("focus", "LineEdit", _sb(C_FIELD, C_SEL, 2))
	t.set_stylebox("read_only", "LineEdit", _sb(Color(0.10, 0.11, 0.13), Color(0, 0, 0, 0), 0))
	t.set_color("font_color", "LineEdit", C_TXT)
	t.set_color("caret_color", "LineEdit", C_TITLE)
	t.set_color("selection_color", "LineEdit", Color(C_SEL, 0.55))
	t.set_color("font_uneditable_color", "LineEdit", Color(0.42, 0.46, 0.52))
	t.set_color("font_placeholder_color", "LineEdit", Color(0.42, 0.46, 0.52))
	t.set_stylebox("panel", "ItemList", _sb(C_FIELD, C_LINE, 1, 6))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", _sb(Color(C_SEL, 0.85), C_SEL, 0, 4))
	t.set_stylebox("selected_focus", "ItemList", _sb(Color(C_SEL, 0.85), C_SEL, 0, 4))
	t.set_stylebox("hovered", "ItemList", _sb(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("hovered_selected", "ItemList", _sb(C_SEL.lightened(0.1), C_SEL, 0, 4))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", C_TXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)
	t.set_color("guide_color", "ItemList", Color(1, 1, 1, 0.04))
	t.set_constant("v_separation", "ItemList", 4)
	var pm := _sb(Color(0.14, 0.16, 0.19), C_LINE, 1, 6)
	pm.shadow_color = Color(0, 0, 0, 0.5)
	pm.shadow_size = 6
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", _sb(C_SEL, C_SEL, 0, 4))
	t.set_color("font_color", "PopupMenu", C_TXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "Panel", _sb(C_WIN, C_LINE, 1, 8))
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber", sb_type, _sb(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber_highlight", sb_type, _sb(Color(1, 1, 1, 0.26), Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber_pressed", sb_type, _sb(C_SEL, Color(0, 0, 0, 0), 0, 3))
	return t


func _label(text: String, fs := 12, col := C_TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


## Fenster mit Titelleiste; gibt die Inhaltsfläche zurück.
func _win(parent: Control, r: Rect2, title: String) -> Control:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(p)
	var mark := ColorRect.new()
	mark.color = C_SEL
	mark.position = Vector2(8, 6)
	mark.size = Vector2(3, 11)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(mark)
	var tb := ColorRect.new()
	tb.color = C_LINE
	tb.position = Vector2(8, 20)
	tb.size = Vector2(r.size.x - 16, 1)
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tb)
	var tl := _label(title, 10, C_TITLE)
	tl.uppercase = true
	tl.position = Vector2(16, 3)
	tl.name = "Title"
	p.add_child(tl)
	var c := Control.new()
	c.position = Vector2(6, 25)
	c.size = r.size - Vector2(12, 31)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(c)
	return c


func _win_title(content: Control, text: String) -> void:
	(content.get_parent().get_node("Title") as Label).text = text


func _list(parent: Control, r: Rect2) -> ItemList:
	var l := ItemList.new()
	l.position = r.position
	l.size = r.size
	l.focus_mode = Control.FOCUS_NONE
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)
	return l


func _page() -> Control:
	var c := Control.new()
	c.position = BODY.position
	c.size = BODY.size
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.visible = false
	return c


func _plot(parent: Control, r: Rect2) -> NcPlot:
	var p := NcPlot.new()
	p.lathe = lathe
	p.position = r.position
	p.size = r.size
	parent.add_child(p)
	return p


func _num(text: String, fallback: float) -> float:
	var s := text.strip_edges().replace(",", ".")
	return float(s) if s.is_valid_float() else fallback


# ======================================================================= Rahmen

func _build_header() -> void:
	var hb := ColorRect.new()
	hb.color = C_HDR
	hb.size = Vector2(W, 22)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)
	var acc := ColorRect.new()
	acc.color = C_SEL
	acc.position = Vector2(0, 21)
	acc.size = Vector2(W, 1)
	acc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(acc)
	var dot := ColorRect.new()
	dot.color = C_SEL
	dot.position = Vector2(6, 6)
	dot.size = Vector2(10, 10)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)
	_hdr_area = _label("", 13, Color.WHITE)
	_hdr_area.position = Vector2(22, 2)
	add_child(_hdr_area)
	_hdr_mid = _label("", 12, C_MUT)
	_hdr_mid.position = Vector2(150, 3)
	add_child(_hdr_mid)
	_hdr_door = _label("", 12, Color.WHITE)
	_hdr_door.position = Vector2(W - 130, 3)
	_hdr_door.size = Vector2(124, 16)
	_hdr_door.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_hdr_door)
	var mb := ColorRect.new()
	mb.color = Color(0.09, 0.10, 0.12)
	mb.position = Vector2(0, 22)
	mb.size = Vector2(W, 19)
	mb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mb)
	_hdr_msg = _label("", 12, C_TXT)
	_hdr_msg.position = Vector2(8, 23)
	_hdr_msg.size = Vector2(W - 12, 17)
	_hdr_msg.clip_text = true
	add_child(_hdr_msg)


func _build_softkeys() -> void:
	var x := W - SK_W - 2.0
	var h := (BODY.size.y - 7.0 * 3.0) / 8.0
	for i in 8:
		var idx := i
		var b := _button("", func(): _press(true, idx))
		b.position = Vector2(x, BODY.position.y + i * (h + 3.0))
		b.size = Vector2(SK_W, h)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 11)
		add_child(b)
		vsk.append(b)
		_vsk_cb.append(Callable())
	var w := (W - 4.0 - 7.0 * 3.0) / 8.0
	for i in 8:
		var idx := i
		var b := _button("", func(): _press(false, idx))
		b.position = Vector2(2.0 + i * (w + 3.0), H - HSK_H - 2.0)
		b.size = Vector2(w, HSK_H)
		b.add_theme_font_size_override("font_size", 11)
		b.clip_text = true
		add_child(b)
		hsk.append(b)
		_hsk_cb.append(Callable())


func _press(vertical: bool, i: int) -> void:
	var cb: Callable = (_vsk_cb if vertical else _hsk_cb)[i]
	if cb.is_valid():
		cb.call()
	_refresh()


func _apply_keys(keys: Array[Button], cbs: Array, defs: Array) -> void:
	for i in keys.size():
		var d: Array = defs[i] if i < defs.size() and defs[i] != null else []
		var b := keys[i]
		if d.is_empty():
			b.text = ""
			b.disabled = true
			cbs[i] = Callable()
			b.remove_theme_stylebox_override("normal")
			continue
		b.text = str(d[0])
		b.disabled = d.size() > 3 and bool(d[3])
		cbs[i] = d[1]
		if d.size() > 2 and bool(d[2]):
			b.add_theme_stylebox_override("normal", _sb_active())
		else:
			b.remove_theme_stylebox_override("normal")


func show_page(p: String) -> void:
	if not _pages.has(p):
		return
	if get_viewport():
		get_viewport().gui_release_focus()
	page = p
	if p == "jog" or p == "auto":
		_machine_page = p
	for k in _pages:
		_pages[k].visible = k == p
	match p:
		"pm":
			_fill_pm()
		"edit":
			_fill_edit()
		"sim":
			_run_sim()
		"tools":
			_fill_tools()
		"msgs":
			_fill_msgs()
	_refresh()


func _area() -> String:
	match page:
		"jog", "auto":
			return "machine"
		"edit", "form", "contour", "sim":
			return "prog"
	return page


func _refresh() -> void:
	if lathe == null:
		return
	var ar := _area()
	var hdefs: Array = [
		["Maschine", func(): show_page(_machine_page), ar == "machine"],
		["Programm", func(): _open_editor(), ar == "prog"],
		["Programme", func(): show_page("pm"), ar == "pm"],
		["Werkzeuge", func(): show_page("tools"), ar == "tools"],
		["Meldungen", func(): show_page("msgs"), ar == "msgs"],
		null, null, null,
	]
	var vdefs: Array = []
	match page:
		"jog":
			vdefs = _keys_jog()
			hdefs[6] = ["Z0 an\nStirnfläche", func(): lathe.set_wcs_face()]
			hdefs[7] = ["Z0 an\nSchneide", func(): lathe.set_wcs_tool()]
		"auto":
			vdefs = _keys_auto()
		"pm":
			vdefs = _keys_pm()
		"edit":
			vdefs = _keys_edit()
			hdefs[6] = ["Simulation", func(): show_page("sim")]
			hdefs[7] = ["Anwählen", func(): _select_prog(open_prog)]
		"form":
			vdefs = [["Über-\nnehmen", func(): _form_accept()], ["Abbrechen", func(): show_page("edit")]]
		"contour":
			vdefs = _keys_contour()
		"sim":
			vdefs = [["Neu\nberechnen", func(): _run_sim()], null, null, null, null, null, null, ["Zurück", func(): show_page("edit")]]
			hdefs[7] = ["Anwählen", func(): _select_prog(open_prog)]
		"msgs":
			vdefs = [["Liste\nlöschen", func(): _clear_log()]]
	_apply_keys(vsk, _vsk_cb, vdefs)
	_apply_keys(hsk, _hsk_cb, hdefs)


# ======================================================================= Laufende Anzeige

func _process(delta: float) -> void:
	if lathe == null or not is_visible_in_tree():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.1
	var names := {"jog": "Maschine  JOG", "auto": "Maschine  AUTO", "pm": "Programm-Manager",
		"edit": "Programm", "form": "Programm", "contour": "Programm  Kontur", "sim": "Programm  Simulation",
		"tools": "Werkzeuge", "msgs": "Meldungen"}
	_hdr_area.text = names.get(page, page)
	var nc := lathe.nc
	var ch := "Kanal: Reset"
	if nc.state != "idle":
		ch = "%s  -  %s" % [nc.prog.get("name", ""), nc.state_text()]
	elif lathe.prog_sel != "":
		ch = "%s angewählt  -  Reset" % lathe.prog_sel
	if lathe.estop:
		ch = "NOT-HALT"
	_hdr_mid.text = ch
	_hdr_mid.position.x = maxf(150.0, _hdr_area.position.x + _hdr_area.get_minimum_size().x + 24.0)
	if lathe.door_closed():
		_hdr_door.text = "Schutztür ZU"
		_hdr_door.add_theme_color_override("font_color", C_OK)
	else:
		_hdr_door.text = "Schutztür AUF" if lathe.door_t < 0.001 and not lathe._door_closing else "Schutztür fährt"
		_hdr_door.add_theme_color_override("font_color", C_WARN)
	match page:
		"jog":
			_update_jog()
		"auto":
			_update_auto()
		"tools":
			_update_tools()
	_refresh()


func _on_message(text: String, col: Color) -> void:
	_hdr_msg.text = text
	var c := C_TXT
	if col.r > 0.95 and col.g < 0.5:
		c = C_ERR
	elif col.r > 0.95 and col.g < 0.85:
		c = C_WARN
	_hdr_msg.add_theme_color_override("font_color", c)
	var t := Time.get_time_dict_from_system()
	_log.append(["%02d:%02d:%02d  %s" % [t["hour"], t["minute"], t["second"], text], c])
	if _log.size() > 200:
		_log.pop_front()
	if page == "msgs":
		_fill_msgs()


# ======================================================================= Maschine JOG

func _build_jog() -> Control:
	var pg := _page()
	var w := BODY.size.x
	var c := _win(pg, Rect2(0, 0, w, 132), "Position WKS (Schneide)")
	for k in 2:
		var tile := Panel.new()
		tile.add_theme_stylebox_override("panel", _sb(C_FIELD, C_LINE, 1, 6))
		tile.position = Vector2(0, k * 50)
		tile.size = Vector2(290, 46)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(tile)
		var ax := _label(["X Ø", "Z"][k], 20, C_TITLE)
		ax.position = Vector2(12, 8)
		tile.add_child(ax)
	_jog_pos = _label("", 30)
	_jog_pos.position = Vector2(60, -3)
	_jog_pos.size = Vector2(220, 100)
	_jog_pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_jog_pos.add_theme_constant_override("line_spacing", 9)
	c.add_child(_jog_pos)
	_jog_mks = _label("", 11, C_MUT)
	_jog_mks.position = Vector2(306, 6)
	c.add_child(_jog_mks)
	var c2 := _win(pg, Rect2(0, 136, w, 196), "T, F, S")
	_jog_info = _label("", 13)
	_jog_info.position = Vector2(6, 2)
	c2.add_child(_jog_info)
	var c3 := _win(pg, Rect2(0, 336, w, BODY.size.y - 336), "Hinweis")
	var hint := _label("", 12, C_MUT)
	hint.text = ("Handbetrieb: Schlitten mit %s%s%s%s bzw. Handrad (Mausrad) verfahren.\n" +
		"Zyklen: Bereich Programm - Kontur anlegen, Abspanen längs / plan einfügen,\n" +
		"Simulation prüfen, Anwählen. In AUTO mit NC-START abarbeiten.\n" +
		"Zyklusstart nur bei geschlossener Schutztür (Taste %s).\n" +
		"Nullpunkt W (Z0) an der Stirnfläche - zum Futter hin ist Z negativ.") % [
		Settings.binding_text("lathe_x_in"), Settings.binding_text("lathe_z_minus"),
		Settings.binding_text("lathe_x_out"), Settings.binding_text("lathe_z_plus"),
		Settings.binding_text("door_toggle")]
	hint.position = Vector2(6, 4)
	c3.add_child(hint)
	return pg


func _keys_jog() -> Array:
	var run := lathe.spindle_on and not lathe.estop
	return [
		["Spindel\nSTOPP" if run else "Spindel\nSTART", func(): lathe.toggle_spindle(), run],
		["KSS\n%s" % ("EIN" if lathe.coolant else "aus"), func(): lathe.coolant = not lathe.coolant, lathe.coolant],
		["G96\n%s" % ("EIN" if lathe.css else "aus"), func(): lathe.set_css(not lathe.css), lathe.css],
		["vc +" if lathe.css else "S +", func(): lathe.step_rpm(1)],
		["vc -" if lathe.css else "S -", func(): lathe.step_rpm(-1)],
		["F +", func(): lathe.step_feed(1)],
		["F -", func(): lathe.step_feed(-1)],
		["AUTO", func(): show_page("auto")],
	]


func _update_jog() -> void:
	_jog_pos.text = "%.3f\n%.3f" % [lathe.tool_x * 2.0, lathe.tool_z - lathe.wcs_z]
	var mk := lathe.machine_pos()
	_jog_mks.text = "MKS Bezugspunkt F\nX Ø %.3f   Z %.3f\nNullpunkt W: Z0 = %.3f ab Backe\nHandrad: %s, %s / Raste" % [mk.y * 2.0, mk.x, lathe.wcs_z,
		"X" if lathe.hw_axis == 0 else "Z", Settings.handwheel_step_name()]
	var t := lathe.tool()
	var sp := "läuft" if lathe.spindle_speed > 5.0 else "steht"
	_jog_info.text = "\n".join([
		"T   %s D1   %s   (Platz %d)" % [t["id"], t["name"], lathe.active_slot + 1],
		"F   %.2f mm/U      Ist %.0f mm/min" % [lathe.feed(), lathe.feed() * lathe.spindle_speed],
		"S   Soll %d /min   Ist %d /min   (%s)" % [int(round(lathe.rpm())), int(round(lathe.spindle_speed)), sp],
		"G96 %s   vc %d m/min   S max %d /min" % ["EIN" if lathe.css else "aus", int(lathe.vc_set), int(lathe.rpm_limit)],
		"KSS %s      Not-Halt %s" % ["EIN" if lathe.coolant else "aus", "AKTIV" if lathe.estop else "-"],
		"Rz letzter Schnitt %.1f µm" % lathe.last_rz,
	])


# ======================================================================= Maschine AUTO

func _build_auto() -> Control:
	var pg := _page()
	var w := BODY.size.x
	var c := _win(pg, Rect2(0, 0, w, 136), "Programm")
	_auto_title = c.get_parent().get_node("Title")
	_auto_list = _list(c, Rect2(0, 0, c.size.x, c.size.y))
	var c2 := _win(pg, Rect2(0, 140, 196, BODY.size.y - 140), "Status")
	_auto_info = _label("", 12)
	_auto_info.position = Vector2(2, 0)
	c2.add_child(_auto_info)
	var c3 := _win(pg, Rect2(200, 140, w - 200, BODY.size.y - 140), "Mitzeichnen")
	_auto_plot = _plot(c3, Rect2(0, 0, c3.size.x, c3.size.y))
	return pg


func _keys_auto() -> Array:
	var nc := lathe.nc
	return [
		["NC-START", func(): nc.nc_start(prog_by_name(lathe.prog_sel)), nc.state == "run"],
		["NC-STOPP", func(): nc.nc_stop(), nc.state == "hold"],
		["RESET", func(): nc.reset()],
		["Override\n+10 %", func(): nc.set_override(nc.override + 0.1)],
		["Override\n-10 %", func(): nc.set_override(nc.override - 0.1)],
		["Programm\nwählen", func(): show_page("pm")],
		null,
		["JOG", func(): show_page("jog")],
	]


func _update_auto() -> void:
	var nc := lathe.nc
	var p: Dictionary = nc.prog if nc.state != "idle" else prog_by_name(lathe.prog_sel)
	_auto_title.text = "Programm: %s" % p.get("name", "- nicht angewählt -")
	var blocks: Array = p.get("blocks", [])
	if _auto_rows != blocks.size() + 1 or _auto_list.item_count != blocks.size() + 1:
		_auto_list.clear()
		for i in blocks.size():
			_auto_list.add_item("N%d   %s" % [(i + 1) * 10, NcCam.summary(blocks[i])])
		_auto_list.add_item("N%d   Programmende" % ((blocks.size() + 1) * 10))
		_auto_rows = blocks.size() + 1
	else:
		for i in blocks.size():
			_auto_list.set_item_text(i, "N%d   %s" % [(i + 1) * 10, NcCam.summary(blocks[i])])
	if nc.block >= 0 and nc.block < _auto_list.item_count:
		if not _auto_list.is_selected(nc.block):
			_auto_list.select(nc.block)
			_auto_list.ensure_current_is_visible()
	elif nc.state == "done":
		_auto_list.select(_auto_list.item_count - 1)
	else:
		_auto_list.deselect_all()
	var t := lathe.tool()
	var rw := nc.remaining()
	var lines := [
		"Zustand: %s" % nc.state_text(),
		"Satz: %s" % ("N%d" % ((nc.block + 1) * 10) if nc.block >= 0 else "-"),
		"",
		"X Ø %9.3f" % (lathe.tool_x * 2.0),
		"Z    %9.3f" % (lathe.tool_z - lathe.wcs_z),
		"Restweg Z %.3f  X %.3f" % [rw.x, rw.y * 2.0],
		"",
		"T  %s  %s" % [t["id"], t["short"]],
		"F  %.2f mm/U" % lathe.feed(),
		"S  %d /min" % int(round(lathe.spindle_speed)),
		"vc %d m/min" % int(lathe.cutting_speed()),
		"Override %d %%" % int(round(nc.override * 100.0)),
		"KSS %s" % ("EIN" if lathe.coolant else "aus"),
		"Laufzeit %d:%02d" % [int(nc.run_time) / 60, int(nc.run_time) % 60],
	]
	if nc.alarm != "":
		lines.append("")
		lines.append("ALARM:")
		lines.append(nc.alarm)
	_auto_info.text = "\n".join(lines)
	_auto_info.add_theme_color_override("font_color", C_ERR if nc.state == "error" else C_TXT)
	_auto_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auto_info.size.x = 186
	_auto_plot.moves = nc.moves if nc.busy() else []
	_auto_plot.done_moves = nc.move_i
	_auto_plot.hi_poly = nc.poly if nc.busy() else PackedVector2Array()
	var polys: Array = []
	for b in blocks:
		if str(b["type"]) == "contour":
			polys.append(NcCam.contour_points(b))
	_auto_plot.polys = polys
	_auto_plot.queue_redraw()


# ======================================================================= Programm-Manager

func prog_by_name(n: String) -> Dictionary:
	for p in lathe.programs:
		if str(p["name"]) == n:
			return p
	return {}


func _clean_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges().to_upper().replace(" ", "_"):
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_":
			out += ch
	return out.substr(0, 24)


func _build_pm() -> Control:
	var pg := _page()
	var w := BODY.size.x
	var c := _win(pg, Rect2(0, 0, w, BODY.size.y - 64), "Programme (Teileprogramme der Maschine)")
	_pm_list = _list(c, Rect2(0, 0, c.size.x, c.size.y))
	_pm_list.item_activated.connect(func(_i): _pm_open())
	var c2 := _win(pg, Rect2(0, BODY.size.y - 60, w, 60), "Name für Neu / Umbenennen")
	_pm_name = LineEdit.new()
	_pm_name.position = Vector2(0, 0)
	_pm_name.size = Vector2(240, 28)
	_pm_name.placeholder_text = "z. B. WELLE_01"
	_pm_name.text_submitted.connect(func(_t): _pm_name.release_focus())
	c2.add_child(_pm_name)
	var l := _label("A-Z, 0-9 und _  -  Doppelklick öffnet", 11, C_MUT)
	l.position = Vector2(250, 6)
	c2.add_child(l)
	return pg


func _fill_pm() -> void:
	var sel := _pm_list.get_selected_items()
	var keep := str(lathe.programs[sel[0]]["name"]) if not sel.is_empty() and sel[0] < lathe.programs.size() else lathe.prog_sel
	_pm_list.clear()
	for p in lathe.programs:
		var tags := ""
		if str(p["name"]) == lathe.prog_sel:
			tags = "   [angewählt]"
		_pm_list.add_item("%-26s %2d Sätze%s" % [p["name"], p["blocks"].size(), tags])
	for i in lathe.programs.size():
		if str(lathe.programs[i]["name"]) == keep:
			_pm_list.select(i)


func _pm_sel_prog() -> Dictionary:
	var s := _pm_list.get_selected_items()
	if s.is_empty() or s[0] >= lathe.programs.size():
		lathe._warn("Erst ein Programm in der Liste auswählen.")
		return {}
	return lathe.programs[s[0]]


func _keys_pm() -> Array:
	return [
		["Neu", func(): _pm_new()],
		["Öffnen", func(): _pm_open()],
		["Anwählen", func(): _pm_select()],
		["Kopieren", func(): _pm_copy()],
		["Umbe-\nnennen", func(): _pm_rename()],
		["Löschen", func(): _pm_delete()],
		null, null,
	]


func _unique(base: String) -> String:
	var n := base if base != "" else "PROG"
	if prog_by_name(n).is_empty() and base != "":
		return n
	var i := 1
	while not prog_by_name("%s%d" % [n, i]).is_empty():
		i += 1
	return "%s%d" % [n, i]


func _pm_select() -> void:
	var p := _pm_sel_prog()
	if not p.is_empty():
		_select_prog(str(p["name"]))


func _pm_new() -> void:
	var n := _unique(_clean_name(_pm_name.text))
	lathe.programs.append(NcCam.new_program(n))
	_pm_name.text = ""
	open_prog = n
	lathe._info("Programm %s angelegt." % n)
	_fill_pm()
	_open_editor()


func _pm_open() -> void:
	var p := _pm_sel_prog()
	if p.is_empty():
		return
	open_prog = str(p["name"])
	_open_editor()


func _pm_copy() -> void:
	var p := _pm_sel_prog()
	if p.is_empty():
		return
	var cp := p.duplicate(true)
	cp["name"] = _unique(str(p["name"]) + "_K")
	lathe.programs.append(cp)
	_fill_pm()


func _pm_rename() -> void:
	var p := _pm_sel_prog()
	if p.is_empty():
		return
	var n := _clean_name(_pm_name.text)
	if n == "":
		lathe._warn("Neuen Namen unten eingeben.")
		return
	if not prog_by_name(n).is_empty():
		lathe._warn("Programm %s gibt es schon." % n)
		return
	if lathe.nc.busy() and str(lathe.nc.prog.get("name", "")) == str(p["name"]):
		lathe._warn("Programm läuft - erst RESET.")
		return
	if lathe.prog_sel == str(p["name"]):
		lathe.prog_sel = n
	if open_prog == str(p["name"]):
		open_prog = n
	p["name"] = n
	_pm_name.text = ""
	_fill_pm()


func _pm_delete() -> void:
	var p := _pm_sel_prog()
	if p.is_empty():
		return
	if lathe.nc.busy() and str(lathe.nc.prog.get("name", "")) == str(p["name"]):
		lathe._warn("Programm läuft - erst RESET.")
		return
	lathe.programs.erase(p)
	if lathe.prog_sel == str(p["name"]):
		lathe.prog_sel = ""
	if open_prog == str(p["name"]):
		open_prog = ""
	lathe._info("Programm %s gelöscht." % p["name"])
	_fill_pm()


func _select_prog(n: String) -> void:
	if prog_by_name(n).is_empty():
		lathe._warn("Kein Programm geöffnet.")
		return
	if lathe.nc.busy():
		lathe._warn("Programm läuft - erst RESET.")
		return
	lathe.prog_sel = n
	lathe.nc.reset()
	lathe._info("Programm %s angewählt - NC-START in AUTO." % n)
	_auto_rows = -1
	show_page("auto")


# ======================================================================= Programm (Arbeitsplan)

func _build_edit() -> Control:
	var pg := _page()
	var w := BODY.size.x
	var c := _win(pg, Rect2(0, 0, w, 214), "Arbeitsplan")
	_ed_title = c.get_parent().get_node("Title")
	_ed_list = _list(c, Rect2(0, 0, c.size.x, c.size.y))
	_ed_list.item_selected.connect(func(_i): _ed_plot_update())
	_ed_list.item_activated.connect(func(_i): _ed_change())
	var c2 := _win(pg, Rect2(0, 218, w, BODY.size.y - 218), "Grafik (Ist-Material, Konturen)")
	_ed_plot = _plot(c2, Rect2(0, 0, c2.size.x, c2.size.y))
	_ed_plot.show_tool = false
	return pg


func _open_editor() -> void:
	if prog_by_name(open_prog).is_empty():
		if not prog_by_name(lathe.prog_sel).is_empty():
			open_prog = lathe.prog_sel
		elif not lathe.programs.is_empty():
			open_prog = str(lathe.programs[0]["name"])
		else:
			show_page("pm")
			lathe._warn("Kein Programm vorhanden - im Programm-Manager Neu anlegen.")
			return
	show_page("edit")


func _ed_sel() -> int:
	var s := _ed_list.get_selected_items()
	return s[0] if not s.is_empty() else -1


func _fill_edit(sel := -1) -> void:
	var p := prog_by_name(open_prog)
	if sel < 0:
		sel = maxi(_ed_sel(), 0)
	_ed_list.clear()
	if p.is_empty():
		_ed_title.text = "Arbeitsplan - kein Programm geöffnet"
		return
	_ed_title.text = "Arbeitsplan %s%s" % [p["name"], "   (angewählt)" if lathe.prog_sel == str(p["name"]) else ""]
	var blocks: Array = p["blocks"]
	for i in blocks.size():
		_ed_list.add_item("N%d   %s" % [(i + 1) * 10, NcCam.summary(blocks[i])])
	_ed_list.add_item("N%d   Programmende" % ((blocks.size() + 1) * 10))
	_ed_list.select(clampi(sel, 0, _ed_list.item_count - 1))
	_ed_list.ensure_current_is_visible()
	_ed_plot_update()


func _ed_plot_update() -> void:
	var p := prog_by_name(open_prog)
	var polys: Array = []
	_ed_plot.hi_poly = PackedVector2Array()
	var i := _ed_sel()
	var hi_name := ""
	if i >= 0 and i < p.get("blocks", []).size():
		var b: Dictionary = p["blocks"][i]
		if str(b["type"]) == "contour":
			hi_name = str(b["name"])
		elif str(b["type"]) == "stock":
			hi_name = str(b["contour"])
	for b in p.get("blocks", []):
		if str(b["type"]) == "contour":
			if str(b["name"]) == hi_name:
				_ed_plot.hi_poly = NcCam.contour_points(b)
			else:
				polys.append(NcCam.contour_points(b))
	_ed_plot.polys = polys
	_ed_plot.queue_redraw()


func _keys_edit() -> Array:
	return [
		["Ändern", func(): _ed_change()],
		["Abspanen\n(Rechteck)", func(): _ed_new("cut")],
		["Kontur\nneu", func(): _ed_new("contour")],
		["Kontur\nabspanen", func(): _ed_new("stock")],
		["Satz\nlöschen", func(): _ed_delete()],
		["Satz\nnach oben", func(): _ed_move(-1)],
		["Satz\nnach unten", func(): _ed_move(1)],
		["Anwählen", func(): _select_prog(open_prog)],
	]


func _ed_change() -> void:
	var p := prog_by_name(open_prog)
	var i := _ed_sel()
	if p.is_empty() or i < 0 or i >= p["blocks"].size():
		lathe._warn("Einen Satz auswählen (Programmende lässt sich nicht ändern).")
		return
	var b: Dictionary = p["blocks"][i]
	if str(b["type"]) == "contour":
		_open_contour(b.duplicate(true), i, -1)
	else:
		_open_form(b.duplicate(true), i, -1)


func _ed_new(type: String) -> void:
	var p := prog_by_name(open_prog)
	if p.is_empty():
		return
	var ins := clampi(_ed_sel() + 1, 1, p["blocks"].size())
	var b := NcCam.new_block(type, p)
	if type == "stock" and str(b["contour"]) == "":
		lathe._warn("Erst eine Kontur anlegen (Softkey Kontur neu).")
		return
	if type == "contour":
		_open_contour(b, -1, ins)
	else:
		_open_form(b, -1, ins)


func _ed_delete() -> void:
	var p := prog_by_name(open_prog)
	var i := _ed_sel()
	if p.is_empty() or i < 0 or i >= p["blocks"].size():
		return
	if str(p["blocks"][i]["type"]) == "head":
		lathe._warn("Der Programmkopf bleibt im Programm.")
		return
	p["blocks"].remove_at(i)
	_fill_edit(i)


func _ed_move(d: int) -> void:
	var p := prog_by_name(open_prog)
	var i := _ed_sel()
	if p.is_empty() or i < 1 or i >= p["blocks"].size():
		return
	var j := i + d
	if j < 1 or j >= p["blocks"].size():
		return
	var b = p["blocks"][i]
	p["blocks"][i] = p["blocks"][j]
	p["blocks"][j] = b
	_fill_edit(j)


# ======================================================================= Zyklusmaske

func _build_form() -> Control:
	var pg := _page()
	var w := BODY.size.x
	var c := _win(pg, Rect2(0, 0, 330, BODY.size.y), "")
	_form_title = c.get_parent().get_node("Title")
	_form_grid = GridContainer.new()
	_form_grid.columns = 3
	_form_grid.add_theme_constant_override("h_separation", 6)
	_form_grid.add_theme_constant_override("v_separation", 5)
	_form_grid.position = Vector2(2, 4)
	c.add_child(_form_grid)
	var c2 := _win(pg, Rect2(334, 0, w - 334, BODY.size.y), "Hilfebild")
	_form_help = Control.new()
	_form_help.size = c2.size
	_form_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form_help.draw.connect(_draw_help)
	c2.add_child(_form_help)
	return pg


func _open_form(b: Dictionary, idx: int, ins: int) -> void:
	_form_blk = b
	_form_idx = idx
	_form_ins = ins
	show_page("form")
	_fill_form()


func _fill_form() -> void:
	for ch in _form_grid.get_children():
		_form_grid.remove_child(ch)
		ch.queue_free()
	var type := str(_form_blk["type"])
	_form_title.text = "%s%s" % [FORM_TITLES.get(type, type), "  (neu)" if _form_idx < 0 else ""]
	var finish := int(_form_blk.get("mode", 0)) == 1
	for f in FORMS[type]:
		var key: String = f[0]
		var off: bool = f.size() > 5 and f[5] == "rough" and finish
		var l := _label(("%s  %s" % [f[1], f[2]]).strip_edges(), 12, C_MUT if off else C_TXT)
		l.custom_minimum_size.x = 140
		l.clip_text = true
		_form_grid.add_child(l)
		var kind = f[4]
		if kind is Array:
			var opts: Array = kind
			var b := _button(str(opts[int(_form_blk[key])]), func():
				_form_blk[key] = (int(_form_blk[key]) + 1) % opts.size()
				_fill_form())
			b.custom_minimum_size = Vector2(84, 24)
			_form_grid.add_child(b)
		elif kind == "tool" or kind == "contour":
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			ob.custom_minimum_size = Vector2(84, 24)
			ob.fit_to_longest_item = false
			ob.clip_text = true
			ob.add_theme_font_size_override("font_size", 12)
			ob.get_popup().add_theme_font_size_override("font_size", 12)
			var ids: Array = []
			if kind == "tool":
				for i in LatheTools.count():
					var t := LatheTools.get_tool(i)
					var slot: int = lathe.holder.find(str(t["id"]))
					ob.add_item("%s %s%s" % [t["id"], t["short"], "" if slot >= 0 else " (nicht im Halter)"])
					ids.append(str(t["id"]))
			else:
				for bl in prog_by_name(open_prog).get("blocks", []):
					if str(bl["type"]) == "contour":
						ob.add_item(str(bl["name"]))
						ids.append(str(bl["name"]))
			ob.select(maxi(ids.find(str(_form_blk[key])), 0) if not ids.is_empty() else -1)
			ob.item_selected.connect(func(i): _form_pick(key, ids[i]))
			_form_grid.add_child(ob)
		else:
			var le := LineEdit.new()
			le.text = NcCam.fmt(float(_form_blk[key]))
			le.custom_minimum_size = Vector2(84, 24)
			le.editable = not off
			le.select_all_on_focus = true
			le.text_submitted.connect(func(t): _form_set(key, le, t); le.release_focus())
			le.focus_exited.connect(func(): _form_set(key, le, le.text))
			_form_grid.add_child(le)
		_form_grid.add_child(_label(f[3], 11, C_MUT))
	if _form_blk.has("t"):
		var t := LatheTools.get_tool(maxi(LatheTools.index_of(str(_form_blk["t"])), 0))
		var info := _label("%s: D max. %s mm, r %s mm" % [t["id"], NcCam.fmt(t["max_dz"]), NcCam.fmt(t["nose"])], 11, C_MUT)
		_form_grid.add_child(Control.new())
		_form_grid.add_child(Control.new())
		_form_grid.add_child(Control.new())
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = 140
		_form_grid.add_child(info)
	_form_help.queue_redraw()


func _form_pick(key: String, v: String) -> void:
	_form_blk[key] = v
	_form_help.queue_redraw()


func _form_set(key: String, le: LineEdit, t: String) -> void:
	if _form_blk.is_empty() or not _form_blk.has(key):
		return
	_form_blk[key] = _num(t, float(_form_blk[key]))
	le.text = NcCam.fmt(float(_form_blk[key]))
	_form_help.queue_redraw()


func _form_accept() -> void:
	if get_viewport():
		get_viewport().gui_release_focus()     # offenes Eingabefeld übernehmen
	var p := prog_by_name(open_prog)
	if p.is_empty():
		show_page("pm")
		return
	var b := _form_blk
	if NcCam.is_machining(b):
		var ti := LatheTools.index_of(str(b["t"]))
		var err := NcCam.check_block(b, LatheTools.get_tool(maxi(ti, 0)))
		if ti < 0:
			err = "Werkzeug wählen."
		if str(b["type"]) == "stock" and NcCam.find_contour(p, str(b["contour"])).is_empty():
			err = "Kontur wählen."
		if err != "":
			lathe._warn(err)
			return
	var at := _form_idx
	if at >= 0:
		p["blocks"][at] = b.duplicate(true)
	else:
		at = clampi(_form_ins, 1, p["blocks"].size())
		p["blocks"].insert(at, b.duplicate(true))
	show_page("edit")
	_fill_edit(at)


## Hilfebild der Zyklusmaske: Schema mit Rohteil, Fertigteil, Schnittaufteilung und Maßen.
func _draw_help() -> void:
	var c := _form_help
	var sz := c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), C_FIELD)
	if _form_blk.is_empty():
		return
	var f := c.get_theme_default_font()
	var type := str(_form_blk["type"])
	var ax := sz.y - 70.0
	var x0 := 30.0
	var x1 := sz.x - 14.0
	var ink := C_MUT
	var blue := Color(0.4, 0.65, 1.0)
	var green := Color(0.35, 0.9, 0.5)
	c.draw_dashed_line(Vector2(6, ax), Vector2(sz.x - 6, ax), ink, 1.0, 6.0)
	c.draw_rect(Rect2(6, ax - 120, x0 - 6, 120), Color(0.30, 0.32, 0.36))
	if type == "head":
		c.draw_rect(Rect2(x0, ax - 80, x1 - x0 - 50, 80), Color(0.26, 0.29, 0.33))
		var wp := Vector2(x1 - 20, ax - 150)
		c.draw_circle(wp, 5, Color(0.9, 0.5, 0.1))
		c.draw_string(f, wp + Vector2(-60, -10), "Wechselpunkt XT/ZT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		c.draw_dashed_line(Vector2(x0, ax - 92), Vector2(x1 - 50, ax - 92), Color(0.85, 0.15, 0.1), 1.0, 3.0)
		c.draw_string(f, Vector2(x0 + 4, ax - 96), "SC Sicherheitsabstand", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		return
	var face := int(_form_blk.get("dir", 0)) == 1
	var finish := int(_form_blk.get("mode", 0)) == 1
	# Rohteil und Fertigteil (Stufe)
	var top := ax - 110.0
	var step_z := x0 + (x1 - x0) * 0.45
	var step_r := ax - 60.0
	var end_z := x1 - 30.0
	c.draw_rect(Rect2(x0, top, x1 - x0, ax - top), Color(0.20, 0.22, 0.26))
	var part := PackedVector2Array([Vector2(x0, ax), Vector2(x0, top), Vector2(step_z, top), Vector2(step_z, step_r),
		Vector2(end_z, step_r), Vector2(end_z, ax)])
	c.draw_colored_polygon(part, Color(0.36, 0.39, 0.44))
	c.draw_polyline(part, blue, 2.0)
	# Schnittaufteilung
	if finish:
		var off := 4.0
		c.draw_polyline(PackedVector2Array([Vector2(end_z + off, ax), Vector2(end_z + off, step_r - off),
			Vector2(step_z + off, step_r - off), Vector2(step_z + off, top - off)]), green, 2.0)
	elif face:
		var zz := end_z + 30.0 - 8.0
		while zz > step_z + 6.0:
			var bottom := ax if zz > end_z else step_r
			c.draw_line(Vector2(zz, top - 6), Vector2(zz, bottom - 3), green, 1.5)
			zz -= 14.0
	else:
		var yy := top + 12.0
		while yy < ax - 2.0:
			var zl := step_z + 4.0 if yy < step_r else end_z + 4.0
			c.draw_line(Vector2(x1 + 4, yy), Vector2(zl, yy), green, 1.5)
			yy += 12.0
	# Bemaßung
	if type == "cut":
		c.draw_string(f, Vector2(end_z - 8, ax + 16), "Z0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		c.draw_string(f, Vector2(step_z - 8, ax + 16), "Z1", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		c.draw_string(f, Vector2(step_z + 10, step_r - 4), "Ø X1", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
	else:
		c.draw_string(f, Vector2(step_z + 10, step_r - 4), "Kontur", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, blue)
	var txt := "%s %s" % [NcCam.MODES[int(_form_blk["mode"])], NcCam.DIRS[int(_form_blk["dir"])]]
	c.draw_string(f, Vector2(8, 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	var expl := "Schnitte längs, D radial" if not face else "Schnitte zur Mitte, D axial"
	if finish:
		expl = "ein Schnitt entlang der Kontur"
	c.draw_string(f, Vector2(8, 32), expl, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 12, 11, C_MUT)
	if not finish:
		c.draw_string(f, Vector2(8, 46), "UX / UZ bleibt fürs Schlichten", HORIZONTAL_ALIGNMENT_LEFT, sz.x - 12, 11, C_MUT)


# ======================================================================= Konturrechner

func _build_contour() -> Control:
	var pg := _page()
	var w := BODY.size.x
	var c := _win(pg, Rect2(0, 0, 236, 236), "Kontur")
	_ct_list = _list(c, Rect2(0, 0, c.size.x, c.size.y))
	_ct_list.item_selected.connect(_ct_pick)
	var c2 := _win(pg, Rect2(0, 240, 236, BODY.size.y - 240), "Element")
	_ct_grid = GridContainer.new()
	_ct_grid.columns = 2
	_ct_grid.add_theme_constant_override("h_separation", 6)
	_ct_grid.add_theme_constant_override("v_separation", 5)
	_ct_grid.position = Vector2(2, 4)
	c2.add_child(_ct_grid)
	var c3 := _win(pg, Rect2(240, 0, w - 240, BODY.size.y), "Konturgrafik")
	_ct_plot = _plot(c3, Rect2(0, 0, c3.size.x, c3.size.y))
	_ct_plot.show_tool = false
	return pg


func _ct_pick(i: int) -> void:
	_ct_sel = i
	_fill_ct_form()
	_ct_plot_update()


func _open_contour(c: Dictionary, idx: int, ins: int) -> void:
	_ct = c
	_ct_idx = idx
	_ct_ins = ins
	_ct_sel = 0
	show_page("contour")
	_fill_ct()


func _ct_point(i: int) -> Vector2:
	if i <= 0:
		return Vector2(float(_ct["z0"]), float(_ct["x0"]))
	var e: Dictionary = _ct["els"][i - 1]
	return Vector2(float(e["z"]), float(e["x"]))


func _fill_ct() -> void:
	_ct_list.clear()
	_ct_list.add_item("Start   X%s  Z%s" % [NcCam.fmt(_ct["x0"]), NcCam.fmt(_ct["z0"])])
	for i in _ct["els"].size():
		var e: Dictionary = _ct["els"][i]
		var p := _ct_point(i)
		var kind := "Gerade schräg"
		if absf(float(e["x"]) - p.y) < 0.0005:
			kind = "Gerade Z"
		elif absf(float(e["z"]) - p.x) < 0.0005:
			kind = "Gerade X"
		var tr := ""
		if int(e["tr"]) == 1:
			tr = "  FS%s" % NcCam.fmt(e["tv"])
		elif int(e["tr"]) == 2:
			tr = "  R%s" % NcCam.fmt(e["tv"])
		_ct_list.add_item("%-14s X%s  Z%s%s" % [kind, NcCam.fmt(e["x"]), NcCam.fmt(e["z"]), tr])
	_ct_sel = clampi(_ct_sel, 0, _ct_list.item_count - 1)
	_ct_list.select(_ct_sel)
	_ct_list.ensure_current_is_visible()
	_fill_ct_form()
	_ct_plot_update()


func _fill_ct_form() -> void:
	for ch in _ct_grid.get_children():
		_ct_grid.remove_child(ch)
		ch.queue_free()
	if _ct_sel == 0:
		_ct_field("Name", "name", true)
		_ct_field("X  Start Ø", "x0")
		_ct_field("Z  Start", "z0")
		return
	_ct_field("X  Ø", "x")
	_ct_field("Z", "z")
	var e: Dictionary = _ct["els"][_ct_sel - 1]
	_ct_grid.add_child(_label("Übergang"))
	var b := _button(NcCam.TRANS[int(e["tr"])], func():
		e["tr"] = (int(e["tr"]) + 1) % 3
		if int(e["tr"]) != 0 and float(e["tv"]) <= 0.0:
			e["tv"] = 1.0
		_fill_ct())
	b.custom_minimum_size = Vector2(110, 24)
	_ct_grid.add_child(b)
	if int(e["tr"]) != 0:
		_ct_field("FS  Fase (Schenkel)" if int(e["tr"]) == 1 else "R  Radius", "tv")
	var hint := _label("Übergang zum nächsten\nElement (an diesem Punkt)", 10, C_MUT)
	_ct_grid.add_child(Control.new())
	_ct_grid.add_child(hint)


func _ct_field(title: String, key: String, text := false) -> void:
	_ct_grid.add_child(_label(title))
	var tgt: Dictionary = _ct if _ct_sel == 0 else _ct["els"][_ct_sel - 1]
	var le := LineEdit.new()
	le.text = str(tgt[key]) if text else NcCam.fmt(float(tgt[key]))
	le.custom_minimum_size = Vector2(110, 24)
	le.select_all_on_focus = true
	var apply := func(t: String):
		if text:
			var n := _clean_name(t)
			if n != "":
				tgt[key] = n
			le.text = str(tgt[key])
		else:
			tgt[key] = _num(t, float(tgt[key]))
			le.text = NcCam.fmt(float(tgt[key]))
		_ct_refresh_list()
	le.text_submitted.connect(func(t): apply.call(t); le.release_focus())
	le.focus_exited.connect(func(): apply.call(le.text))
	_ct_grid.add_child(le)


## Liste und Grafik nach einer Eingabe auffrischen, ohne das Formular neu zu bauen.
func _ct_refresh_list() -> void:
	var keep := _ct_sel
	_ct_list.clear()
	_ct_list.add_item("Start   X%s  Z%s" % [NcCam.fmt(_ct["x0"]), NcCam.fmt(_ct["z0"])])
	for i in _ct["els"].size():
		var e: Dictionary = _ct["els"][i]
		var p := _ct_point(i)
		var kind := "Gerade schräg"
		if absf(float(e["x"]) - p.y) < 0.0005:
			kind = "Gerade Z"
		elif absf(float(e["z"]) - p.x) < 0.0005:
			kind = "Gerade X"
		var tr := ""
		if int(e["tr"]) == 1:
			tr = "  FS%s" % NcCam.fmt(e["tv"])
		elif int(e["tr"]) == 2:
			tr = "  R%s" % NcCam.fmt(e["tv"])
		_ct_list.add_item("%-14s X%s  Z%s%s" % [kind, NcCam.fmt(e["x"]), NcCam.fmt(e["z"]), tr])
	_ct_list.select(keep)
	_ct_plot_update()


func _ct_plot_update() -> void:
	_ct_plot.hi_poly = NcCam.contour_points(_ct)
	var p := _ct_point(_ct_sel)
	_ct_plot.hi_point = Vector2(p.x, p.y * 0.5)
	var w := _win_title_of(_ct_plot)
	if w:
		w.text = "Konturgrafik  %s" % _ct["name"]
	_ct_plot.queue_redraw()


func _win_title_of(content_child: Control) -> Label:
	var p := content_child.get_parent().get_parent()
	return p.get_node_or_null("Title") as Label


func _keys_contour() -> Array:
	return [
		["Gerade Z\n(waagrecht)", func(): _ct_add(Vector2(-20.0, 0.0))],
		["Gerade X\n(senkrecht)", func(): _ct_add(Vector2(0.0, 10.0))],
		["Gerade\nschräg", func(): _ct_add(Vector2(-10.0, 10.0))],
		["Element\nlöschen", func(): _ct_delete()],
		null, null,
		["Über-\nnehmen", func(): _ct_accept()],
		["Abbrechen", func(): show_page("edit")],
	]


func _ct_add(d: Vector2) -> void:
	if get_viewport():
		get_viewport().gui_release_focus()
	var p := _ct_point(_ct_sel)
	var e := {"x": maxf(p.y + d.y, 0.0), "z": p.x + d.x, "tr": 0, "tv": 0.0}
	_ct["els"].insert(_ct_sel, e)
	_ct_sel += 1
	_fill_ct()


func _ct_delete() -> void:
	if _ct_sel <= 0:
		lathe._warn("Der Startpunkt bleibt - Elemente löschen.")
		return
	_ct["els"].remove_at(_ct_sel - 1)
	_ct_sel -= 1
	_fill_ct()


func _ct_accept() -> void:
	if get_viewport():
		get_viewport().gui_release_focus()
	var p := prog_by_name(open_prog)
	if p.is_empty():
		show_page("pm")
		return
	if _ct["els"].is_empty():
		lathe._warn("Kontur braucht mindestens ein Element.")
		return
	for b in p["blocks"]:
		if str(b["type"]) == "contour" and str(b["name"]) == str(_ct["name"]) and (_ct_idx < 0 or p["blocks"][_ct_idx] != b):
			lathe._warn("Kontur %s gibt es schon - anderen Namen wählen." % _ct["name"])
			return
	var at := _ct_idx
	if at >= 0:
		var old := str(p["blocks"][at]["name"])
		p["blocks"][at] = _ct.duplicate(true)
		if old != str(_ct["name"]):
			for b in p["blocks"]:
				if str(b["type"]) == "stock" and str(b["contour"]) == old:
					b["contour"] = str(_ct["name"])
	else:
		at = clampi(_ct_ins, 1, p["blocks"].size())
		p["blocks"].insert(at, _ct.duplicate(true))
	show_page("edit")
	_fill_edit(at)


# ======================================================================= Simulation

func _build_sim() -> Control:
	var pg := _page()
	var w := BODY.size.x
	var c := _win(pg, Rect2(0, 0, w, BODY.size.y - 76), "Simulation (Material von jetzt, Bahnen aller Sätze)")
	_sim_plot = _plot(c, Rect2(0, 0, c.size.x, c.size.y))
	var c2 := _win(pg, Rect2(0, BODY.size.y - 72, w, 72), "Ergebnis")
	_sim_info = _label("", 12)
	_sim_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sim_info.size = Vector2(c2.size.x - 4, c2.size.y)
	c2.add_child(_sim_info)
	return pg


func _run_sim() -> void:
	var p := prog_by_name(open_prog)
	if p.is_empty():
		_sim_info.text = "Kein Programm geöffnet."
		return
	var r := NcCam.simulate(p, lathe)
	_sim_plot.prof = r["prof"]
	_sim_plot.polys = r["polys"]
	_sim_plot.moves = r["moves"]
	_sim_plot.start_pos = Vector2(lathe.tool_z, lathe.tool_x)
	_sim_plot.show_tool = false
	_sim_plot.queue_redraw()
	var t := int(r["time"])
	var txt := "%s: %d Verfahrwege, Bearbeitungszeit ca. %d:%02d min." % [p["name"], r["moves"].size(), t / 60, t % 60]
	if not r["errs"].is_empty():
		txt += "\n" + "\n".join(r["errs"])
		_sim_info.add_theme_color_override("font_color", C_ERR)
	else:
		txt += "  Grau: Material nach dem Programm. Rot gestrichelt Eilgang, grün Vorschub."
		_sim_info.add_theme_color_override("font_color", C_TXT)
	_sim_info.text = txt


# ======================================================================= Werkzeuge

func _build_tools() -> Control:
	var pg := _page()
	var w := BODY.size.x
	var c := _win(pg, Rect2(0, 0, w, 168), "Werkzeughalter (Vierfach) - Umspannen nur bei stehender Spindel")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 5)
	grid.position = Vector2(2, 4)
	c.add_child(grid)
	for s in Lathe.SLOTS:
		var slot := s
		grid.add_child(_label("Platz %d" % (s + 1)))
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.custom_minimum_size = Vector2(150, 26)
		ob.add_theme_font_size_override("font_size", 12)
		ob.get_popup().add_theme_font_size_override("font_size", 12)
		ob.add_item("- leer -")
		for i in LatheTools.count():
			var t := LatheTools.get_tool(i)
			ob.add_item("%s %s" % [t["id"], t["short"]])
		ob.item_selected.connect(func(i):
			lathe.mount_tool(slot, "" if i == 0 else str(LatheTools.get_tool(i - 1)["id"]))
			_fill_tools())
		grid.add_child(ob)
		_tl_opts.append(ob)
		var b := _button("Einschwenken", func(): lathe.index_slot(slot))
		b.custom_minimum_size = Vector2(100, 26)
		grid.add_child(b)
		_tl_btns.append(b)
		var l := _label("", 11)
		l.custom_minimum_size.x = 250
		grid.add_child(l)
		_tl_lbl.append(l)
	var c2 := _win(pg, Rect2(0, 172, w, BODY.size.y - 172), "Werkzeugliste")
	_tl_info = _label("", 11)
	_tl_info.position = Vector2(2, 2)
	c2.add_child(_tl_info)
	return pg


func _fill_tools() -> void:
	for s in Lathe.SLOTS:
		var id := str(lathe.holder[s])
		_tl_opts[s].select(LatheTools.index_of(id) + 1 if id != "" else 0)
	_update_tools()
	var lines := ["T    Name                          r      SL   ap max   Platz"]
	for i in LatheTools.count():
		var t := LatheTools.get_tool(i)
		var slot: int = lathe.holder.find(str(t["id"]))
		lines.append("%-4s %-28s %4.1f   %d    %4.1f     %s" % [t["id"], t["name"], t["nose"], t["sl"], t["max_dz"],
			("P%d" % (slot + 1)) if slot >= 0 else "-"])
	lines.append("")
	lines.append("Zyklen arbeiten mit Rechtsmeißeln (zum Futter / zur Mitte).")
	lines.append("Schruppen: T1 (D bis 4 mm). Schlichten: T3 (r 0,4).")
	_tl_info.text = "\n".join(lines)


func _update_tools() -> void:
	for s in Lathe.SLOTS:
		var id := str(lathe.holder[s])
		var active := s == lathe.active_slot
		_tl_btns[s].text = "AKTIV" if active else "Einschwenken"
		_tl_btns[s].disabled = id == "" or active
		if id == "":
			_tl_lbl[s].text = ""
			continue
		var d := lathe.tool_data(LatheTools.get_tool(LatheTools.index_of(id)))
		var st := lathe.slot_status(s)
		_tl_lbl[s].text = "L1 %.3f  L2 %.3f  R %.1f  SL %d\n%s" % [d["l1"], d["l2"], d["r"], d["sl"], st["text"]]
		_tl_lbl[s].add_theme_color_override("font_color", [C_TXT, C_WARN, C_ERR][int(st["level"])])


# ======================================================================= Meldungen

func _build_msgs() -> Control:
	var pg := _page()
	var c := _win(pg, Rect2(0, 0, BODY.size.x, BODY.size.y), "Meldungen und Alarme")
	_msg_list = _list(c, Rect2(0, 0, c.size.x, c.size.y))
	return pg


func _clear_log() -> void:
	_log.clear()
	_fill_msgs()


func _fill_msgs() -> void:
	_msg_list.clear()
	for i in range(_log.size() - 1, -1, -1):
		var e: Array = _log[i]
		var k := _msg_list.add_item(str(e[0]))
		_msg_list.set_item_custom_fg_color(k, e[1])
