class_name DayBoardOverlay
extends CanvasLayer
## Großansicht des Whiteboards im Meisterbüro: der Tagesbericht mit dem Knopf, der den Tag startet oder beendet.

signal closed

const SIZE := Vector2(820, 470)
const INK := Color(0.12, 0.16, 0.26)      # Marker auf dem Whiteboard

var day_app: DayApp


func _ready() -> void:
	layer = 15
	visible = false
	var root := Control.new()
	# Eigene Kopie des Themes, damit die dunkle Schrift nur hier gilt
	var theme: Theme = UITheme.build().duplicate()
	theme.set_color("font_color", "Label", INK)
	theme.set_font("font", "Label", Whiteboard.marker_font())
	theme.set_font("font", "Heading", Whiteboard.marker_font())
	theme.set_color("font_color", "Heading", INK)
	# Knöpfe auf der hellen Tafel: dunkle Magnettasten statt der durchscheinenden Menüknöpfe
	theme.set_stylebox("normal", "Button", UITheme.sb(Color(0.14, 0.18, 0.28), Color(0.14, 0.18, 0.28), 1, 3))
	theme.set_stylebox("hover", "Button", UITheme.sb(UITheme.BLUE, UITheme.BLUE_HI, 1, 3))
	theme.set_stylebox("pressed", "Button", UITheme.sb(UITheme.BLUE_DEEP, UITheme.BLUE_HI, 1, 3))
	root.theme = theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	# Weiße Tafel im Aluminiumrahmen
	var panel := PanelContainer.new()
	var board := UITheme.sb(Color(0.96, 0.97, 0.96), Color(0.68, 0.7, 0.72), 12, 6)
	board.content_margin_left = 36
	board.content_margin_right = 36
	board.content_margin_top = 26
	board.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", board)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UITheme.title("Tagesbericht", 32)
	t.add_theme_color_override("font_color", Color(0.75, 0.12, 0.1))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UITheme.button("Zurück", close, 160))
	day_app = DayApp.new()
	day_app.custom_minimum_size = SIZE
	v.add_child(day_app)


func open() -> void:
	visible = true
	day_app.refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
