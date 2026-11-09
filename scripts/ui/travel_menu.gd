class_name TravelMenu
extends CanvasLayer
## Reisemenü an Hoftor und Ausgangstüren: Ziel anklicken, man wird dorthin geladen (Werkstatt, Supermarkt,
## Zuhause). Welche Ziele es gibt, sagt Places für den jeweiligen Spieler.

## Spielwelt: places (Places), hud
var world: Node
var player: Node = null             # wer das Menü gerade offen hat
var _pitch := 0.0
var _head: Dictionary
var _list: VBoxContainer
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
	v.custom_minimum_size = Vector2(560, 0)
	panel.add_child(v)
	_head = UITheme.window_head("Wohin?", "Unterwegs")
	v.add_child(_head["box"])
	v.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	v.add_child(_list)
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size.x = 520
	_msg.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	v.add_child(_msg)
	v.add_child(UITheme.button("Hierbleiben", close, 520))
	v.add_child(UITheme.key_hint("Esc / %s  ·  schließen" % Settings.binding_text("interact")))


## Ziele neu aufbauen, abhängig vom Ort des Spielers.
func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if player == null:
		return
	for d in world.places.destinations(player):
		var b := UITheme.button(d["title"], go.bind(d["id"]), 520)
		b.name = d["id"]
		_list.add_child(b)


## Zu einem Ort reisen. Gibt einen Fehlertext zurück, leer = angekommen.
func go(place_id: String) -> String:
	var p := player
	close()
	var err: String = world.places.travel(p, place_id)
	if err != "":
		world.hud.show_message(err, Color(1, 0.6, 0.4))
	return err


func open_for(p: Node) -> void:
	if visible or p.operating != null:
		return
	player = p
	_msg.text = ""
	_head["crumb"].text = ("Hoftor" if p.location == Places.SITE else world.places.place(p.location).title).to_upper()
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
