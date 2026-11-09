class_name DrawingOverlay
extends CanvasLayer
## Werkstückzeichnung des aktuellen Auftrags, per Taste ein- und ausblenden. Die Maschine bleibt bedienbar.

## Spielwelt: drawing_job(), office_pc, pause_menu, player, hud
var world: Node
var drawing: PartDrawing
var close_button: Button
var take_button: Button


func _ready() -> void:
	layer = 20
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	drawing = PartDrawing.new()
	drawing.custom_minimum_size = Vector2(1120, 660)
	center.add_child(drawing)
	# Das Blatt liegt auch über Menüs: Klicks dürfen nicht zu den verdeckten Knöpfen durchgehen
	drawing.mouse_filter = Control.MOUSE_FILTER_STOP
	close_button = UITheme.button("Schließen", close, 150)
	close_button.theme = UITheme.build()
	close_button.custom_minimum_size.y = 36
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.position = Vector2(drawing.custom_minimum_size.x - 170.0, 16.0)
	drawing.add_child(close_button)
	take_button = UITheme.button("In die Hand nehmen", take, 210)
	take_button.theme = UITheme.build()
	take_button.custom_minimum_size.y = 36
	take_button.focus_mode = Control.FOCUS_NONE
	take_button.position = Vector2(drawing.custom_minimum_size.x - 400.0, 16.0)
	drawing.add_child(take_button)


## Ausgedruckte Zeichnung in die Hand nehmen, um sie irgendwo anzupinnen.
func take() -> void:
	var job := drawing.job
	# Am PC ausgedruckt: Der Spieler steht auf und hat das Blatt in der Hand
	if world.player.operating == world.office_pc:
		world.office_pc.overlay.close()
		world.office_pc.stop_using()
	var err: String = world.take_drawing(job)
	if err != "":
		world.hud.show_message(err, Color(1, 0.75, 0.2))
		return
	close()


## Eine bestimmte Zeichnung zeigen, zum Beispiel aus dem Entwicklerprogramm.
func show_job(job: Dictionary) -> void:
	drawing.job = job
	drawing.queue_redraw()
	visible = true


func close() -> void:
	visible = false


## Knopf in den Auftragsmenüs: Zeichnung dieses Auftrags zeigen, ein zweiter Druck schließt sie.
func toggle_job(job: Dictionary) -> void:
	if visible and drawing.job == job:
		close()
	else:
		show_job(job)


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
	if visible:
		visible = false
		get_viewport().set_input_as_handled()
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
