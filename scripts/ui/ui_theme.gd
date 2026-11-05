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
