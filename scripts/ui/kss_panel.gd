class_name KssPanel
extends Control
## "Der Chemiemeister": Kühlschmierstoff-Tank auffüllen. Zwei Ventile (Wasser, Konzentrat),
## Füllstandsanzeige und Refraktometer. Die Welt kümmert sich um Mausmodus und Spielersperre.
## Der Tank wird nur über seine öffentliche Schnittstelle benutzt (KssTank, scripts/machine/kss_tank.gd).

signal closed

const WATER := 0
const CONC := 1
## Durchfluss je Sekunde bei voll geöffnetem Hahn
const FLOW_WATER := 6.0
const FLOW_CONC := 0.5
const FINE_FACTOR := 0.25
## Hahn auf: Sekunden bis voller Durchfluss (Feinjustage); zu geht schneller
const RAMP_UP := 0.4
const RAMP_DOWN := 0.15
const GAUGE_MAX := 12.0
const CAPACITY_FALLBACK := 60.0
# Zustände wie KssTank.State
const S_NEUTRAL := 0
const S_OPTIMAL := 1
const S_THIN := 2
const S_THICK := 3

var tank  # KssTank (untypisiert, damit das Panel auch ohne die Maschinen-Datei lädt)
var title_text := ""
## Feindosieren erzwingen (sonst Shift-Taste)
var fine := false

var _built := false
var _want: Array[bool] = [false, false]
var _level: Array[float] = [0.0, 0.0]
var _needle := 0.0
var _t := 0.0
var _locked := false
var _banner_state := -1
var _money_timer := 0.0

var _machine_label: Label
var _state_label: Label
var _tank_view: Control
var _gauge_view: Control
var _stats: Label
var _digital: Label
var _hint: Label
var _warn: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label
var _btn: Array[Button] = [null, null]


func setup(p_tank, p_title: String) -> void:
	if tank != null and tank.has_signal("changed") and tank.changed.is_connected(_on_changed):
		tank.changed.disconnect(_on_changed)
		tank.evaluated.disconnect(_on_evaluated)
	tank = p_tank
	title_text = p_title
	_build()
	_want = [false, false]
	_level = [0.0, 0.0]
	_banner_state = -1
	_banner.visible = false
	_money_timer = 0.0
	_warn.text = ""
	_machine_label.text = title_text
	if tank != null:
		tank.changed.connect(_on_changed)
		tank.evaluated.connect(_on_evaluated)
		_needle = float(tank.concentration())
	_refresh()


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.025, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.window_style())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(900, 0)
	panel.add_child(v)

	var head := UITheme.window_head("Der Chemiemeister – KSS auffüllen", "Kühlschmierstoff")
	v.add_child(head["box"])
	_machine_label = head["crumb"]

	_state_label = UITheme.note("", 16, UITheme.TEXT)
	v.add_child(_state_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)

	# Tankbild
	_tank_view = Control.new()
	_tank_view.custom_minimum_size = Vector2(190, 300)
	_tank_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tank_view.draw.connect(_draw_tank)
	row.add_child(UITheme.card(_tank_view))

	# Refraktometer
	var gbox := VBoxContainer.new()
	gbox.add_theme_constant_override("separation", 6)
	_gauge_view = Control.new()
	_gauge_view.custom_minimum_size = Vector2(340, 250)
	_gauge_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_view.draw.connect(_draw_gauge)
	gbox.add_child(UITheme.section("Refraktometer"))
	gbox.add_child(_gauge_view)
	_digital = Label.new()
	_digital.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_digital.add_theme_font_override("font", UITheme.font(600, 1))
	_digital.add_theme_font_size_override("font_size", 30)
	_digital.add_theme_color_override("font_color", UITheme.VALUE)
	gbox.add_child(_digital)
	var gcard := UITheme.card(gbox)
	gcard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gcard)

	# Ventile
	var valves := VBoxContainer.new()
	valves.add_theme_constant_override("separation", 10)
	valves.custom_minimum_size = Vector2(230, 0)
	valves.add_child(UITheme.section("Ventile"))
	_btn[WATER] = _valve_button("Wasser  [W]", WATER)
	_btn[CONC] = _valve_button("Konzentrat  [K]", CONC)
	valves.add_child(_btn[WATER])
	valves.add_child(_btn[CONC])
	valves.add_child(UITheme.note("Gedrückt halten zum Fließen.\nShift: Feindosierung (¼ Durchfluss).\nWasser 6 L/s, Konzentrat 0,5 L/s.", 13))
	row.add_child(valves)

	_stats = UITheme.note("", 16, UITheme.TEXT)
	v.add_child(UITheme.card(_stats))

	_warn = Label.new()
	_warn.add_theme_font_size_override("font_size", 15)
	_warn.add_theme_color_override("font_color", UITheme.BAD)
	v.add_child(_warn)

	_hint = UITheme.note("", 15, UITheme.WARN)
	v.add_child(_hint)

	# Ergebnisbanner
	_banner = PanelContainer.new()
	_banner.visible = false
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 2)
	_banner.add_child(bv)
	_banner_title = Label.new()
	_banner_title.add_theme_font_override("font", UITheme.font(600, 1))
	_banner_title.add_theme_font_size_override("font_size", 24)
	bv.add_child(_banner_title)
	_banner_text = Label.new()
	_banner_text.add_theme_font_size_override("font_size", 17)
	bv.add_child(_banner_text)
	v.add_child(_banner)

	v.add_child(UITheme.note("Ziel 6–7 %: Konzentration = Konzentrat ÷ Gesamtvolumen × 100", 14))
	v.add_child(HSeparator.new())
	var done := UITheme.primary(UITheme.button("Fertig", close, 220))
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(done)
	v.add_child(UITheme.key_hint("W / K halten  ·  Shift fein  ·  Esc / %s  ·  fertig" % _interact_key()))


func _valve_button(text: String, which: int) -> Button:
	var b := UITheme.button(text, func() -> void: pass, 220)
	b.custom_minimum_size.y = 64
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 19)
	b.button_down.connect(set_valve.bind(which, true))
	b.button_up.connect(set_valve.bind(which, false))
	b.mouse_exited.connect(set_valve.bind(which, false))
	return b


## Ventil auf (gedrückt halten) oder zu.
func set_valve(which: int, on: bool) -> void:
	_want[which] = on and not _locked


func is_locked() -> bool:
	return _locked


func close() -> void:
	_want = [false, false]
	_level = [0.0, 0.0]
	closed.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()
		return
	if event is InputEventKey and not event.echo:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_W or k.keycode == KEY_W:
			set_valve(WATER, k.pressed)
			get_viewport().set_input_as_handled()
		elif k.physical_keycode == KEY_K or k.keycode == KEY_K:
			set_valve(CONC, k.pressed)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if tank == null:
		return
	_t += delta
	_flow(delta)
	_needle = lerpf(_needle, float(tank.concentration()), 1.0 - exp(-8.0 * delta))
	if _money_timer > 0.0:
		_money_timer -= delta
		if _money_timer <= 0.0:
			_warn.text = ""
	_tank_view.queue_redraw()
	_gauge_view.queue_redraw()
	_digital.text = _fmt(_needle, 1) + " %"


## Hähne aufdrehen/zudrehen und Flüssigkeit in den Tank geben.
func _flow(delta: float) -> void:
	if tank == null:
		return
	var shift := fine or Input.is_key_pressed(KEY_SHIFT)
	var factor := FINE_FACTOR if shift else 1.0
	if _locked or tank.is_full():
		_want = [false, false]
	for i in 2:
		var target := 1.0 if _want[i] else 0.0
		var rate := (1.0 / RAMP_UP) if target > _level[i] else (1.0 / RAMP_DOWN)
		_level[i] = move_toward(_level[i], target, rate * delta)
	var w := FLOW_WATER * _level[WATER] * factor * delta
	if w > 0.0:
		tank.add_water(w)
	var c := FLOW_CONC * _level[CONC] * factor * delta
	if c > 0.0 and not tank.is_full():
		var got: float = tank.add_concentrate(c)
		if got <= 0.0 and not tank.is_full():
			_warn.text = "Kein Geld für Konzentrat"
			_money_timer = 2.0
			_want[CONC] = false


func _on_changed() -> void:
	_refresh()


func _on_evaluated(state: int) -> void:
	_lock()
	_banner_state = state
	_show_banner(state)
	_refresh()


func _lock() -> void:
	_locked = true
	_want = [false, false]


func _refresh() -> void:
	if tank == null or not _built:
		return
	if tank.is_full():
		_lock()
	else:
		_locked = false
	for b in _btn:
		b.disabled = _locked
	var cap := _cap()
	var vol: float = tank.volume()
	_stats.text = "Wasser %s L   ·   Konzentrat %s L   ·   Gesamt %s von %s L (%d %%)   ·   Konzentration %s %%" % [
		_fmt(tank.water, 1), _fmt(tank.concentrate, 2), _fmt(vol, 1), _fmt(cap, 0),
		int(round(float(tank.fill_fraction()) * 100.0)), _fmt(tank.concentration(), 1)]
	_state_label.text = "Aktueller Zustand: " + _title(int(tank.state))
	_hint.text = "Tank ist voll – erst bei Verbrauch nachfüllen" if tank.is_full() and _banner_state < 0 else ""
	if _banner_state >= 0:
		_show_banner(_banner_state)
	_digital.text = _fmt(_needle, 1) + " %"


func _show_banner(state: int) -> void:
	var col := UITheme.MUTED
	var txt := "Im Rahmen, kein Bonus"
	match state:
		S_OPTIMAL:
			col = UITheme.GOOD
			txt = "Normaler Werkzeugverschleiß, +10 % Bearbeitungsgeschwindigkeit"
		S_THIN:
			col = UITheme.BAD
			txt = "Doppelter Werkzeugverschleiß!"
		S_THICK:
			col = Color(1.0, 0.6, 0.22)
			txt = "Verschwendung kostet extra, KSS schäumt!"
	var st := UITheme.sb(Color(col, 0.16), col, 2, 4)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	_banner.add_theme_stylebox_override("panel", st)
	_banner_title.text = _title(state)
	_banner_title.add_theme_color_override("font_color", col)
	_banner_text.text = txt
	_banner_text.add_theme_color_override("font_color", UITheme.TEXT)
	_banner.visible = true


func banner_text() -> String:
	return _banner_title.text + " | " + _banner_text.text if _banner.visible else ""


func _title(s: int) -> String:
	if tank != null and tank.get_script() != null and tank.get_script().has_method("state_title"):
		return str(tank.get_script().state_title(s))
	return ["Neutral", "Optimal", "Zu dünn", "Zu dick"][clampi(s, 0, 3)]


func _cap() -> float:
	if tank != null and tank.get_script() != null:
		var consts: Dictionary = tank.get_script().get_script_constant_map()
		if consts.has("CAPACITY"):
			return float(consts["CAPACITY"])
	return CAPACITY_FALLBACK


func _fmt(x: float, dec: int) -> String:
	return (("%." + str(dec) + "f") % x).replace(".", ",") if dec > 0 else str(int(round(x)))


## Flüssigkeitsfarbe: zu dünn wässrig-klar, Zielbereich milchig-weiß, zu dick gelblich-cremig.
func liquid_color(conc: float) -> Color:
	var clear := Color(0.55, 0.76, 0.92, 0.55)
	var thin := Color(0.78, 0.88, 0.95, 0.75)
	var milk := Color(0.95, 0.96, 0.97, 0.95)
	var cream := Color(0.96, 0.88, 0.58, 0.97)
	if conc < 4.0:
		return clear.lerp(thin, conc / 4.0)
	if conc < 6.0:
		return thin.lerp(milk, (conc - 4.0) / 2.0)
	if conc <= 7.0:
		return milk
	if conc < 9.0:
		return milk.lerp(cream, (conc - 7.0) / 2.0)
	return cream


func _draw_tank() -> void:
	var c := _tank_view
	var sz := c.size
	var r := Rect2(Vector2(30, 14), Vector2(sz.x - 60, sz.y - 40))
	var frac := clampf(float(tank.fill_fraction()), 0.0, 1.0) if tank != null else 0.0
	var conc := float(tank.concentration()) if tank != null else 0.0
	c.draw_rect(r, Color(0, 0, 0, 0.35))
	var h := r.size.y * frac
	var fluid := Rect2(Vector2(r.position.x, r.end.y - h), Vector2(r.size.x, h))
	if h > 0.5:
		c.draw_rect(fluid, liquid_color(conc))
		c.draw_line(fluid.position, Vector2(fluid.end.x, fluid.position.y), Color(1, 1, 1, 0.5), 2.0)
	# Strahl und Tropfen
	var top := r.position.y - 10.0
	var surface := fluid.position.y if h > 0.5 else r.end.y
	if _level[WATER] > 0.05:
		var x := r.position.x + r.size.x * 0.35
		c.draw_line(Vector2(x, top), Vector2(x, surface), Color(0.5, 0.78, 1.0, 0.8), 2.0 + 5.0 * _level[WATER])
		_drops(c, x, top, surface, Color(0.7, 0.88, 1.0, 0.9), 0.0)
	if _level[CONC] > 0.05:
		var x2 := r.position.x + r.size.x * 0.7
		c.draw_line(Vector2(x2, top), Vector2(x2, surface), Color(0.97, 0.95, 0.85, 0.95), 1.5 + 2.5 * _level[CONC])
		_drops(c, x2, top, surface, Color(1, 0.98, 0.9, 1.0), 0.37)
	# Rahmen und Skala
	c.draw_rect(r, Color(0.8, 0.86, 0.95, 0.7), false, 2.0)
	var font := UITheme.font(400, 0)
	for i in 5:
		var y := r.end.y - r.size.y * i / 4.0
		c.draw_line(Vector2(r.end.x, y), Vector2(r.end.x + 6, y), Color(1, 1, 1, 0.6), 1.5)
		c.draw_string(font, Vector2(r.end.x + 8, y + 5), "%d" % (i * 25), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
	var vol := float(tank.volume()) if tank != null else 0.0
	c.draw_string(font, Vector2(0, sz.y - 6), "%s L  ·  %d %%" % [_fmt(vol, 1), int(round(frac * 100.0))],
		HORIZONTAL_ALIGNMENT_CENTER, sz.x, 15, UITheme.TEXT)


func _drops(c: Control, x: float, top: float, bottom: float, col: Color, phase: float) -> void:
	var span := maxf(bottom - top, 1.0)
	for i in 4:
		var f := fposmod(_t * 1.6 + phase + i * 0.25, 1.0)
		c.draw_circle(Vector2(x + sin(i * 3.1 + _t * 5.0) * 4.0, top + span * f), 2.2, col)


func _draw_gauge() -> void:
	var c := _gauge_view
	var radius := minf(c.size.x * 0.44, (c.size.y - 34.0) / 1.65)
	var center := Vector2(c.size.x * 0.5, 24.0 + radius)
	c.draw_arc(center, radius + 10.0, PI * 0.72, PI * 2.28, 48, Color(0, 0, 0, 0.35), 3.0)
	c.draw_arc(center, radius + 10.0, PI * 0.72, PI * 2.28, 48, Color(0.8, 0.86, 0.95, 0.5), 2.0)
	var bands := [[0.0, 5.0, UITheme.BAD], [5.0, 6.0, UITheme.WARN], [6.0, 7.0, UITheme.GOOD], [7.0, 8.0, UITheme.WARN], [8.0, GAUGE_MAX, UITheme.BAD]]
	for b in bands:
		c.draw_arc(center, radius, _ang(b[0]), _ang(b[1]), 24, Color(b[2], 0.9), 12.0)
	var font := UITheme.font(400, 0)
	for i in 13:
		var a := _ang(float(i))
		var d := Vector2.from_angle(a)
		c.draw_line(center + d * (radius - 8.0), center + d * (radius - 18.0), Color(1, 1, 1, 0.8), 2.0)
		if i % 2 == 0:
			var p := center + d * (radius - 34.0)
			c.draw_string(font, p + Vector2(-12, 5), str(i), HORIZONTAL_ALIGNMENT_CENTER, 24, 14, UITheme.TEXT)
	# Zeiger
	var na := _ang(clampf(_needle, 0.0, GAUGE_MAX))
	var nd := Vector2.from_angle(na)
	c.draw_line(center - nd * 14.0, center + nd * (radius - 14.0), Color(0.05, 0.05, 0.06, 0.6), 6.0)
	c.draw_line(center - nd * 14.0, center + nd * (radius - 14.0), Color(1, 1, 1), 3.0)
	c.draw_circle(center, 9.0, Color(0.9, 0.92, 0.95))
	c.draw_circle(center, 4.0, Color(0.15, 0.17, 0.2))
	c.draw_string(font, Vector2(center.x - 40, center.y + radius * 0.55), "Konzentration %", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, UITheme.MUTED)


## Winkel für einen Skalenwert: 0 links unten bis 12 rechts unten über oben.
func _ang(v: float) -> float:
	return lerpf(PI * 0.8, PI * 2.2, v / GAUGE_MAX)


func needle_value() -> float:
	return _needle


func _interact_key() -> String:
	var s := get_node_or_null("/root/Settings")
	if s != null and s.has_method("binding_text"):
		return str(s.call("binding_text", "interact"))
	return "E"
