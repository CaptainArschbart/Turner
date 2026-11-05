extends Node
## Szenenwechsel und Übergabe von Spielständen an die Welt.

const WORLD := "res://scenes/world.tscn"
const MENU := "res://scenes/main_menu.tscn"

var current_slot := 0
var pending: Dictionary = {}


func new_game(slot: int, save_name: String) -> void:
	current_slot = slot
	pending = {"name": save_name, "money": 0, "job": 0, "parts": 0, "play_time": 0.0}
	SaveManager.write_slot(slot, pending.duplicate())
	_go(WORLD)


func load_game(slot: int) -> void:
	var d := SaveManager.read_slot(slot)
	if d.is_empty():
		return
	current_slot = slot
	pending = d
	_go(WORLD)


func to_main_menu() -> void:
	pending = {}
	_go(MENU)


func _go(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(path)
