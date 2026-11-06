class_name ToolStore
extends RefCounted
## Werkzeugbestand einer Maschinenart: Von jedem Werkzeug gibt es bis zu MAX_COPIES Stück, jedes mit eigenem
## Schneidstoff und Verschleiß. items hält das Stück, das gerade benutzt wird oder als nächstes dran ist,
## spares die übrigen auf der Werkbank, placed die in den Halterungen unter der Bank. Zerstörte oder
## verschlissene Werkzeuge fallen heraus, dann rückt das nächste Stück nach.

const GRADE_TITLES := {"hm": "Hartmetall", "hss": "HSS"}
const MAX_COPIES := 5

var items: Dictionary = {}        # Werkzeug-id -> {"grade": "hm" oder "hss", "wear": 0..1, "dull": 0..1}
var spares: Dictionary = {}       # Werkzeug-id -> Array weiterer Stücke
var placed: Dictionary = {}       # Halterung -> {"id", "grade", "wear", "dull"}


func has(id: String) -> bool:
	return items.has(id)


## Alle Stücke dieses Werkzeugs, auch die in den Halterungen.
func count(id: String) -> int:
	var n := (1 if items.has(id) else 0) + spare_count(id)
	for i in placed:
		if str(placed[i]["id"]) == id:
			n += 1
	return n


func spare_count(id: String) -> int:
	return (spares[id] as Array).size() if spares.has(id) else 0


## Neu gekauft: voller Zustand, ein vorhandenes bleibt in Benutzung.
func add(id: String, grade := "hm") -> void:
	var copy := {"grade": grade, "wear": 0.0, "dull": 0.0}
	if items.has(id):
		if not spares.has(id):
			spares[id] = []
		spares[id].append(copy)
	else:
		items[id] = copy


## Das benutzte Stück ist weg, das nächste rückt nach.
func remove(id: String) -> void:
	if spare_count(id) > 0:
		items[id] = spares[id].pop_front()
		if spares[id].is_empty():
			spares.erase(id)
	else:
		items.erase(id)


func clear() -> void:
	items.clear()
	spares.clear()
	placed.clear()


## Was steckt in dieser Halterung? Leer = nichts.
func holder_id(i: int) -> String:
	return str(placed[i]["id"]) if placed.has(i) else ""


## Das benutzte Stück in die Halterung stecken.
func place(id: String, i: int) -> bool:
	if placed.has(i) or not items.has(id):
		return false
	var copy: Dictionary = items[id].duplicate()
	copy["id"] = id
	placed[i] = copy
	remove(id)
	return true


## Stück aus der Halterung nehmen, es wird zum benutzten. Das bisherige bleibt auf der Werkbank.
func take(i: int) -> String:
	if not placed.has(i):
		return ""
	var copy: Dictionary = placed[i]
	placed.erase(i)
	var id := str(copy["id"])
	copy.erase("id")
	if items.has(id):
		if not spares.has(id):
			spares[id] = []
		spares[id].append(items[id])
	items[id] = copy
	return id


func grade(id: String) -> String:
	return str(items[id]["grade"]) if items.has(id) else "hm"


func wear(id: String) -> float:
	return float(items[id]["wear"]) if items.has(id) else 0.0


## Verschleiß dazu, gibt den neuen Stand zurück.
func add_wear(id: String, amount: float) -> float:
	if not items.has(id):
		return 0.0
	var w := float(items[id]["wear"]) + amount
	items[id]["wear"] = w
	return w


## Schleifscheiben: Wie unrund sie ist, 1 = muss abgezogen werden.
func dull(id: String) -> float:
	return float(items[id].get("dull", 0.0)) if items.has(id) else 0.0


func add_dull(id: String, amount: float) -> void:
	if items.has(id):
		items[id]["dull"] = minf(dull(id) + amount, 1.0)


func set_dull(id: String, value: float) -> void:
	if items.has(id):
		items[id]["dull"] = value


## Anzeige: Hartmetall, 12 % Verschleiß
func info(id: String) -> String:
	if not items.has(id):
		return ""
	if not GRADE_TITLES.has(grade(id)):
		return "%d %% Verschleiß, %d %% unrund" % [int(wear(id) * 100.0), int(dull(id) * 100.0)]
	return "%s, %d %% Verschleiß" % [GRADE_TITLES[grade(id)], int(wear(id) * 100.0)]


func to_state() -> Dictionary:
	var out := items.duplicate(true)
	if not spares.is_empty():
		out["#spares"] = spares.duplicate(true)
	if not placed.is_empty():
		var p := {}
		for i in placed:
			p[str(i)] = placed[i].duplicate()
		out["#placed"] = p
	return out


func load_state(d) -> void:
	clear()
	if not d is Dictionary:
		return
	for id in d:
		if str(id).begins_with("#"):
			continue
		var it = d[id]
		if it is Dictionary:
			items[str(id)] = _copy(it)
	var sp = d.get("#spares", {})
	if sp is Dictionary:
		for id in sp:
			if sp[id] is Array:
				spares[str(id)] = (sp[id] as Array).map(_copy)
	var pl = d.get("#placed", {})
	if pl is Dictionary:
		for i in pl:
			var copy := _copy(pl[i])
			copy["id"] = str(pl[i].get("id", ""))
			placed[int(i)] = copy


func _copy(it: Dictionary) -> Dictionary:
	return {"grade": str(it.get("grade", "hm")), "wear": float(it.get("wear", 0.0)), "dull": float(it.get("dull", 0.0))}
