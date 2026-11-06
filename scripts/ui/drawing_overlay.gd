class_name DrawingOverlay
extends CanvasLayer
## Werkstückzeichnung des aktuellen Auftrags, per Taste ein- und ausblenden. Die Maschine bleibt bedienbar.

## Spielwelt: drawing_job(), office_pc, pause_menu, player, hud
var world: Node
var drawing: PartDrawing


func _ready() -> void:
	layer = 12
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	drawing = PartDrawing.new()
	drawing.custom_minimum_size = Vector2(1120, 660)
	center.add_child(drawing)


func toggle() -> void:
	if visible:
		visible = false
		return
	var job: Dictionary = world.drawing_job()
	if job.is_empty():
		world.hud.show_message("Keine Zeichnung: Es ist kein Auftrag gewählt.", Color(1, 0.75, 0.2))
		return
	drawing.job = job
	drawing.queue_redraw()
	visible = true


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		visible = false
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("show_drawing"):
		return
	# Beim Eintippen und am Bedienpult ist die Taste ein Buchstabe
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if world.office_pc.overlay.visible or world.pause_menu.visible:
		return
	var op: Node = world.player.operating
	if op is Lathe and op.in_panel_view():
		return
	get_viewport().set_input_as_handled()
	toggle()
