class_name UITheme
extends RefCounted
## Einheitliches dunkles Industrie-Theme für alle Menüs.

const ACCENT := Color("e8892b")
const TEXT := Color(0.92, 0.93, 0.94)
const MUTED := Color(0.62, 0.65, 0.68)

static var _cached: Theme


static func build() -> Theme:
	if _cached:
		return _cached
	var t := Theme.new()
	t.default_font_size = 18

	var normal := sb(Color(0.15, 0.16, 0.18, 0.96), Color(0.30, 0.32, 0.35), 1)
	var hover := sb(Color(0.21, 0.22, 0.25, 0.98), ACCENT, 2)
	var pressed := sb(ACCENT.darkened(0.25), ACCENT, 2)
	var disabled := sb(Color(0.11, 0.11, 0.12, 0.8), Color(0.2, 0.2, 0.2), 1)
	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, sb(Color(0, 0, 0, 0), ACCENT.lightened(0.2), 1))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(0.45, 0.45, 0.45))

	var panel := sb(Color(0.07, 0.08, 0.09, 0.93), Color(0.24, 0.26, 0.29), 1, 10)
	panel.content_margin_left = 22
	panel.content_margin_right = 22
	panel.content_margin_top = 18
	panel.content_margin_bottom = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	t.set_stylebox("panel", "TabContainer", sb(Color(0.10, 0.11, 0.12, 0.9), Color(0.24, 0.26, 0.29), 1, 6))
	t.set_stylebox("tab_selected", "TabContainer", sb(Color(0.20, 0.21, 0.24), ACCENT, 2, 6))
	t.set_stylebox("tab_unselected", "TabContainer", sb(Color(0.12, 0.13, 0.14), Color(0.25, 0.26, 0.28), 1, 6))
	t.set_stylebox("tab_hovered", "TabContainer", sb(Color(0.18, 0.19, 0.21), Color(0.4, 0.4, 0.42), 1, 6))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", MUTED)

	t.set_stylebox("normal", "LineEdit", sb(Color(0.05, 0.05, 0.06), Color(0.3, 0.32, 0.35), 1))
	t.set_stylebox("focus", "LineEdit", sb(Color(0.05, 0.05, 0.06), ACCENT, 2))
	t.set_color("font_color", "LineEdit", TEXT)

	var track := sb(Color(0.05, 0.05, 0.06), Color(0.3, 0.3, 0.32), 1, 4)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := sb(ACCENT.darkened(0.1), ACCENT, 0, 4)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PopupMenu", sb(Color(0.1, 0.11, 0.12), Color(0.3, 0.32, 0.35), 1))
	t.set_stylebox("hover", "PopupMenu", sb(ACCENT.darkened(0.3), ACCENT, 0))
	_cached = t
	return t


# ======================================================================= Menü-Stil
# Haupt-, Pause-, Einstellungs- und Speicherplatzmenü: Anthrazit, Weiß, Weiler-Blau.

const BLUE := Color("1f4fc4")         # Weiler-Blau, für dunkle Flächen aufgehellt
const BLUE_HI := Color("5d8dff")
const BLUE_DEEP := Color(0.06, 0.18, 0.58)
const ANTHRACITE := Color(0.075, 0.083, 0.098)
const WHITE := Color(0.95, 0.96, 0.97)
const SOFT := Color(0.66, 0.70, 0.76)

static var _menu_cached: Theme
static var _fonts := {}


## Schrift der Menüs: Bahnschrift (DIN-artig, unter Windows vorhanden), sonst Segoe UI / Standard.
static func font(weight := 400, spacing := 0) -> Font:
	var key := "%d_%d" % [weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Helvetica Neue", "Arial"])
	sf.font_weight = weight
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.hinting = TextServer.HINTING_LIGHT
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


static func menu() -> Theme:
	if _menu_cached:
		return _menu_cached
	var t := Theme.new()
	t.default_font = font(400)
	t.default_font_size = 18

	var normal := sb(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.10), 1, 3)
	var hover := sb(Color(BLUE, 0.28), BLUE_HI, 1, 3)
	var pressed := sb(BLUE, BLUE_HI, 1, 3)
	var disabled := sb(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.05), 1, 3)
	var focus := sb(Color(0, 0, 0, 0), Color(BLUE_HI, 0.9), 2, 3)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, WHITE)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.28))
	# CheckButton als schlichter Schalter ohne Rahmen
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckButton", sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3))

	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())

	var tab_panel := sb(Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.07), 1, 3)
	t.set_stylebox("panel", "TabContainer", tab_panel)
	var tab_sel := sb(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 0)
	tab_sel.border_width_bottom = 3
	tab_sel.border_color = BLUE_HI
	tab_sel.content_margin_left = 22
	tab_sel.content_margin_right = 22
	tab_sel.content_margin_top = 10
	tab_sel.content_margin_bottom = 10
	var tab_un := tab_sel.duplicate() as StyleBoxFlat
	tab_un.bg_color = Color(0, 0, 0, 0)
	tab_un.border_color = Color(1, 1, 1, 0.08)
	tab_un.border_width_bottom = 1
	var tab_hov := tab_un.duplicate() as StyleBoxFlat
	tab_hov.bg_color = Color(1, 1, 1, 0.04)
	tab_hov.border_color = Color(BLUE_HI, 0.5)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hov)
	t.set_stylebox("tab_focus", "TabContainer", focus)
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", SOFT)
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	t.set_font("font", "TabContainer", font(500, 1))

	var le := sb(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.12), 1, 3)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", sb(Color(0, 0, 0, 0.35), BLUE_HI, 2, 3))
	t.set_color("font_color", "LineEdit", WHITE)
	t.set_color("caret_color", "LineEdit", BLUE_HI)
	t.set_color("selection_color", "LineEdit", Color(BLUE, 0.6))
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.3))

	var track := sb(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	var fill := sb(BLUE_HI, Color(0, 0, 0, 0), 0, 2)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _dot(16, Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _dot(18, Color.WHITE))

	var sbar := sb(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 3)
	t.set_stylebox("scroll", "VScrollBar", sbar)
	var grab := sb(Color(1, 1, 1, 0.18), Color(0, 0, 0, 0), 0, 3)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb(Color(BLUE_HI, 0.7), Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", sb(BLUE_HI, Color(0, 0, 0, 0), 0, 3))

	t.set_color("font_color", "Label", WHITE)
	var pop := sb(Color(0.1, 0.11, 0.13, 0.98), Color(1, 1, 1, 0.1), 1, 3)
	pop.shadow_color = Color(0, 0, 0, 0.5)
	pop.shadow_size = 12
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("hover", "PopupMenu", sb(Color(BLUE, 0.7), Color(0, 0, 0, 0), 0, 2))
	t.set_color("font_color", "PopupMenu", WHITE)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	var win := panel_style()
	win.expand_margin_top = 34
	win.content_margin_top = 10
	t.set_stylebox("embedded_border", "Window", win)
	t.set_stylebox("embedded_unfocused_border", "Window", win)
	t.set_color("title_color", "Window", WHITE)
	t.set_stylebox("panel", "AcceptDialog", sb(ANTHRACITE, Color(0, 0, 0, 0), 0, 0))
	_menu_cached = t
	return t


## Glasartige Anthrazit-Fläche mit blauer Oberkante und weichem Schatten.
static func panel_style(top_accent := true) -> StyleBoxFlat:
	var p := sb(Color(ANTHRACITE, 0.92), Color(1, 1, 1, 0.07), 1, 4)
	if top_accent:
		p.border_color = BLUE_HI
		p.set_border_width_all(0)
		p.border_width_top = 3
	p.shadow_color = Color(0, 0, 0, 0.45)
	p.shadow_size = 28
	p.shadow_offset = Vector2(0, 8)
	p.content_margin_left = 30
	p.content_margin_right = 30
	p.content_margin_top = 26
	p.content_margin_bottom = 26
	return p


## Überschrift im Menüstil: kleine blaue Marke + Bahnschrift.
static func heading(text: String, size := 30) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.color = BLUE_HI
	bar.custom_minimum_size = Vector2(34, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(bar)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(600, 1))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(l)
	return v


## Großer, flacher Menüeintrag: Text links, blaue Marke und Aufhellung bei Hover/Fokus
## (weich eingeblendet), optional eine kleine zweite Zeile.
static func menu_button(text: String, cb: Callable, sub := "", min_w := 380.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(min_w, 58 if sub == "" else 70)
	b.focus_mode = Control.FOCUS_ALL
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.pressed.connect(cb)

	var glow := TextureRect.new()                       # Aufhellung von links nach rechts
	var g := Gradient.new()
	g.set_color(0, Color(BLUE, 0.55))
	g.set_color(1, Color(BLUE, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate.a = 0.0
	b.add_child(glow)
	var bar := ColorRect.new()
	bar.color = BLUE_HI
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_bottom = 1.0
	bar.offset_right = 4
	bar.scale = Vector2(1, 0)
	b.add_child(bar)
	b.resized.connect(func(): bar.pivot_offset = Vector2(0, b.size.y * 0.5))

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 22
	b.add_child(col)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(500, 1))
	l.add_theme_font_size_override("font_size", 25)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	col.add_child(l)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.add_theme_font_override("font", font(350))
		s.add_theme_font_size_override("font_size", 14)
		s.add_theme_color_override("font_color", SOFT)
		s.clip_text = true
		col.add_child(s)

	var state := {"tw": null}
	var set_hot := func(on: bool) -> void:
		if state["tw"]:
			(state["tw"] as Tween).kill()
		var tw := b.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(glow, "modulate:a", 1.0 if on else 0.0, 0.22)
		tw.tween_property(bar, "scale:y", 1.0 if on else 0.0, 0.22)
		tw.tween_property(col, "offset_left", 34.0 if on else 22.0, 0.22)
		tw.tween_property(l, "theme_override_colors/font_color", Color.WHITE if on else Color(1, 1, 1, 0.82), 0.22)
		state["tw"] = tw
	var refresh := func() -> void:
		set_hot.call(b.is_hovered() or b.has_focus())
	b.mouse_entered.connect(func(): set_hot.call(true))
	b.mouse_exited.connect(func(): set_hot.call(b.has_focus()))
	b.focus_entered.connect(func(): set_hot.call(true))
	b.focus_exited.connect(func(): set_hot.call(b.is_hovered()))
	b.button_down.connect(func(): glow.modulate.a = 1.6)
	b.set_meta("refresh", refresh)
	return b


## Weiches Einblenden (Deckkraft), optional verzögert. Läuft auch im Pausezustand.
static func reveal(c: CanvasItem, delay := 0.0, dur := 0.45) -> Tween:
	c.modulate.a = 0.0
	var tw := c.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(c, "modulate:a", 1.0, dur).set_delay(delay)
	return tw


static func _dot(d: int, c: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(c, clampf(r - dist, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func sb(bg: Color, border: Color, bw := 1, radius := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func title(text: String, size := 30) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


static func button(text: String, cb: Callable, min_w := 300.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 46)
	b.pressed.connect(cb)
	return b
