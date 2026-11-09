extends Node
## Speicherstände als JSON in user://saves/slot_N.json

const DIR := "user://saves"
const SLOT_COUNT := 5


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func slot_path(i: int) -> String:
	return "%s/slot_%d.json" % [DIR, i]


func has_slot(i: int) -> bool:
	return FileAccess.file_exists(slot_path(i))


func any_save() -> bool:
	for i in SLOT_COUNT:
		if has_slot(i):
			return true
	return false


func latest_slot() -> int:
	var best := -1
	var best_t := ""
	for i in SLOT_COUNT:
		var d := read_slot(i)
		if d.is_empty():
			continue
		var t := str(d.get("saved_at", ""))
		if best == -1 or t > best_t:
			best = i
			best_t = t
	return best


func read_slot(i: int) -> Dictionary:
	if not has_slot(i):
		return {}
	var f := FileAccess.open(slot_path(i), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		return d
	return {}


func write_slot(i: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	data["saved_at"] = Time.get_datetime_string_from_system(false, true)
	var f := FileAccess.open(slot_path(i), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


func delete_slot(i: int) -> void:
	if has_slot(i):
		DirAccess.remove_absolute(slot_path(i))


static func format_time(sec: float) -> String:
	var s := int(sec)
	@warning_ignore("integer_division")
	return "%d:%02d h" % [s / 3600, (s / 60) % 60]
