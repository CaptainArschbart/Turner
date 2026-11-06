class_name RackMenu
extends CanvasLayer
## Menü am Lagerregal: Linksklick auf ein Regal zeigt alles Material im Lager, wie am PC.

## Spielwelt: player, stock, deliveries, site, load_stock(index, length)
var world: Node
var view: StockView
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
	v.custom_minimum_size = Vector2(1120, 520)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UITheme.title("Lagerbestand")
	t.add_theme_color_override("font_color", UITheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UITheme.button("Schließen", close, 180))
	view = StockView.new()
	view.shop = world
	view.can_take = true
	view.taken.connect(close)
	v.add_child(view)


func open() -> void:
	if visible or world.player.operating != null:
		return
	view.refresh()
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
	if not visible:
		return
	# Beim Eintippen eines Abschnitts schließt die Interaktionstaste das Menü nicht
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if event.is_action_pressed("pause") or (not typing and (event.is_action_pressed("interact") or event.is_action_pressed("job_menu"))):
		get_viewport().set_input_as_handled()
		close()
