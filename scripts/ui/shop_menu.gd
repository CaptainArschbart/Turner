class_name ShopMenu
extends CanvasLayer
## Kasse im Supermarkt: Zigaretten aus Supermarket.GOODS kaufen, bezahlt wird aus der Kasse der Werkstatt.

## Spielwelt: money, buy_cigarettes(player, i)
var world: Node
var player: Node = null
var _pitch := 0.0
var _info: Label
var _msg: Label


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
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(640, 0)
	panel.add_child(v)
	v.add_child(UITheme.window_head("Kasse", "Supermarkt")["box"])
	v.add_child(HSeparator.new())
	_info = Label.new()
	_info.add_theme_color_override("font_color", UITheme.MUTED)
	v.add_child(_info)
	for i in Supermarket.GOODS.size():
		var g: Dictionary = Supermarket.GOODS[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		var l := Label.new()
		l.text = "%s  (%s)" % [g["title"], g["info"]]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 18)
		row.add_child(l)
		row.add_child(UITheme.button("Kaufen  %d EUR" % int(g["price"]), buy.bind(i), 200))
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size.x = 600
	v.add_child(_msg)
	v.add_child(UITheme.button("Fertig", close, 600))
	v.add_child(UITheme.key_hint("Esc / %s  ·  schließen" % Settings.binding_text("interact")))


func refresh() -> void:
	if player == null:
		return
	_info.text = "Zigaretten in der Tasche: %d   ·   Kasse: %d EUR" % [player.cigarette.stock, world.money]


func buy(i: int) -> String:
	var err: String = world.buy_cigarettes(player, i)
	_msg.text = err if err != "" else "Gekauft: %s." % Supermarket.GOODS[i]["title"]
	_msg.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if err != "" else Color(0.55, 0.9, 0.6))
	refresh()
	return err


func open_for(p: Node) -> void:
	if visible or p.operating != null:
		return
	player = p
	_msg.text = ""
	refresh()
	visible = true
	_pitch = p.pitch
	p.start_operating(self, p.global_position, p.yaw)


func close() -> void:
	if not visible:
		return
	visible = false
	player.stop_operating()
	player.pitch = _pitch
	player = null


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()
