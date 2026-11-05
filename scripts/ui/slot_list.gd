class_name SlotList
extends VBoxContainer
## Liste der Speicherplätze. mode = "new" oder "load".

signal chosen(slot: int)

var mode := "load"
var _confirm: ConfirmationDialog
var _pending_action: Callable


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_confirm = ConfirmationDialog.new()
	_confirm.ok_button_text = "Ja"
	_confirm.cancel_button_text = "Abbrechen"
	_confirm.title = "Bestätigen"
	_confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm.confirmed.connect(func(): if _pending_action.is_valid(): _pending_action.call())
	add_child(_confirm)
	refresh()


func refresh() -> void:
	for c in get_children():
		if c != _confirm:
			remove_child(c)
			c.queue_free()
	for i in SaveManager.SLOT_COUNT:
		var d := SaveManager.read_slot(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.custom_minimum_size.x = 420
		if d.is_empty():
			info.text = "Platz %d  -  leer" % (i + 1)
			info.add_theme_color_override("font_color", UITheme.MUTED)
		else:
			info.text = "Platz %d  -  %s\n%s   |   Spielzeit %s   |   %d EUR   |   %d Teile" % [
				i + 1, str(d.get("name", "Werkstatt")), str(d.get("saved_at", "")).replace("T", " "),
				SaveManager.format_time(float(d.get("play_time", 0))), int(d.get("money", 0)), int(d.get("parts", 0))]
		row.add_child(info)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 44)
		if mode == "new":
			b.text = "Neu starten" if d.is_empty() else "Überschreiben"
			b.pressed.connect(func():
				if d.is_empty():
					chosen.emit(i)
				else:
					_ask("Speicherplatz %d überschreiben?" % (i + 1), func(): chosen.emit(i)))
		else:
			b.text = "Laden"
			b.disabled = d.is_empty()
			b.pressed.connect(func(): chosen.emit(i))
		row.add_child(b)
		var del := Button.new()
		del.text = "Löschen"
		del.custom_minimum_size = Vector2(110, 44)
		del.disabled = d.is_empty()
		del.pressed.connect(func(): _ask("Speicherplatz %d wirklich löschen?" % (i + 1), func():
			SaveManager.delete_slot(i)
			refresh()))
		row.add_child(del)
		add_child(row)


func _ask(text: String, action: Callable) -> void:
	_pending_action = action
	_confirm.dialog_text = text
	_confirm.popup_centered()
