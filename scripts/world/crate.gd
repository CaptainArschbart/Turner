class_name Crate
extends Node3D
## Kiste neben der Werkbank für Fertigschnitte und abgesägte Teile. Stangen gehören ins Regal.
## l, w, h = Innenmaße in mm, max = höchste Stückzahl. Die Teile liegen in Lagen übereinander.

const WALL := 0.02
const SIZES := {
	"crate_s": {"title": "Kleine Kiste", "price": 40, "l": 400.0, "w": 300.0, "h": 200.0, "max": 6},
	"crate_m": {"title": "Mittlere Kiste", "price": 90, "l": 600.0, "w": 400.0, "h": 300.0, "max": 12},
	"crate_l": {"title": "Große Kiste", "price": 180, "l": 1000.0, "w": 600.0, "h": 400.0, "max": 24},
}

## Spielwelt: crate_prompt(index), crate_click(index)
var world: Node
var index := 0
var size_id := "crate_s"
var items: Array = []
var _content: Node3D


## Darf das Stück überhaupt in eine Kiste? Fertigschnitte, abgesägte und ausgespannte Teile ja, Stangen nein.
static func accepts(item: Dictionary) -> bool:
	return str(item.get("kind", "")) in [Materials.KIND_CUT, "part"] or bool(item.get("sawn", false))


## Rundes Stück: Rundmaterial oder ein gedrehtes Teil.
static func is_round(it: Dictionary) -> bool:
	if str(it.get("kind", "")) == "part":
		return str(it.get("shape", "")) == "round"
	return str(it.get("kind", "")) == Materials.KIND_ROUND


## Außenmaß in Metern (Länge, Breite).
static func outer(id: String) -> Vector2:
	var s: Dictionary = SIZES[id]
	return Vector2(float(s["l"]) * 0.001 + WALL * 2.0, float(s["w"]) * 0.001 + WALL * 2.0)


static func _footprint(it: Dictionary) -> Dictionary:
	if is_round(it):
		return {"l": float(it["l"]), "w": float(it["d"]), "h": float(it["d"])}
	return {"l": float(it["l"]), "w": float(it["w"]), "h": float(it["h"])}


## Lage aller Stücke: je {"along", "across", "y", "rot"} in mm ab der Ecke. Leer = passt nicht.
static func layout(id: String, list: Array) -> Array:
	var s: Dictionary = SIZES[id]
	if list.size() > int(s["max"]):
		return []
	var layers: Array = []   # je {"items": [Index], "h": Höhe}
	for i in list.size():
		var foot := _footprint(list[i])
		var done := false
		for k in layers.size():
			var layer: Dictionary = layers[k]
			var taller: float = maxf(float(layer["h"]), float(foot["h"]))
			if _stack_height(layers) - float(layer["h"]) + taller > float(s["h"]) + 0.001:
				continue
			if _layer_fits(layer["items"], i, list, s):
				layer["items"].append(i)
				layer["h"] = taller
				done = true
				break
		if done:
			continue
		if _stack_height(layers) + float(foot["h"]) > float(s["h"]) + 0.001 or not _layer_fits([], i, list, s):
			return []
		layers.append({"items": [i], "h": float(foot["h"])})
	var out: Array = []
	out.resize(list.size())
	var y := 0.0
	for layer in layers:
		var feet: Array = []
		for i in layer["items"]:
			feet.append(_footprint(list[i]))
		var places: Array = Storage.layout_cut(feet, float(s["l"]), float(s["w"]), float(s["h"]))
		for k in places.size():
			var p: Dictionary = places[k]
			p["y"] = y
			out[layer["items"][k]] = p
		y += float(layer["h"])
	return out


static func _stack_height(layers: Array) -> float:
	var h := 0.0
	for layer in layers:
		h += float(layer["h"])
	return h


static func _layer_fits(indices: Array, extra: int, list: Array, s: Dictionary) -> bool:
	var feet: Array = []
	for i in indices:
		feet.append(_footprint(list[i]))
	feet.append(_footprint(list[extra]))
	return not Storage.layout_cut(feet, float(s["l"]), float(s["w"]), float(s["h"])).is_empty()


## Passt das Stück noch dazu?
static func fits(id: String, list: Array, item: Dictionary) -> bool:
	var all := list.duplicate()
	all.append(item)
	return not layout(id, all).is_empty()


func _ready() -> void:
	var s: Dictionary = SIZES[size_id]
	var l := float(s["l"]) * 0.001
	var w := float(s["w"]) * 0.001
	var h := float(s["h"]) * 0.001
	var wood := Build.mat(Color(0.62, 0.46, 0.28), 0.85)
	var dark := Build.mat(Color(0.45, 0.32, 0.18), 0.85)
	Build.box(self, Vector3(l + WALL * 2.0, 0.02, w + WALL * 2.0), Vector3(0, 0.05, 0), dark)
	# Füße, damit man die Kiste greifen kann
	for sx in [-1.0, 1.0]:
		Build.box(self, Vector3(0.06, 0.04, w), Vector3(sx * (l * 0.5 - 0.03), 0.02, 0), dark)
	for sz in [-1.0, 1.0]:
		Build.box(self, Vector3(l + WALL * 2.0, h, WALL), Vector3(0, 0.06 + h * 0.5, sz * (w * 0.5 + WALL * 0.5)), wood)
	for sx in [-1.0, 1.0]:
		Build.box(self, Vector3(WALL, h, w), Vector3(sx * (l * 0.5 + WALL * 0.5), 0.06 + h * 0.5, 0), wood)
	var hit := Build.collider(self, Vector3(l + WALL * 2.0, h + 0.06, w + WALL * 2.0), Vector3(0, (h + 0.06) * 0.5, 0))
	hit.set_meta("interact", self)
	_content = Node3D.new()
	add_child(_content)
	refresh()


## Inhalt neu zeichnen.
func refresh() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		_content.remove_child(c)
		c.free()
	var s: Dictionary = SIZES[size_id]
	var places := layout(size_id, items)
	for i in places.size():
		var p: Dictionary = places[i]
		var it: Dictionary = items[i]
		var foot := _footprint(it)
		var pl: float = float(foot["w"]) if p["rot"] else float(foot["l"])
		var pw: float = float(foot["l"]) if p["rot"] else float(foot["w"])
		var ph: float = float(foot["h"])
		var at := Vector3((float(p["along"]) + pl * 0.5 - float(s["l"]) * 0.5) * 0.001, 0.06 + (float(p["y"]) + ph * 0.5) * 0.001,
			(float(p["across"]) + pw * 0.5 - float(s["w"]) * 0.5) * 0.001)
		var id := str(it["material"])
		var m := Build.mat(Materials.raw_color(id).lerp(Materials.cut_color(id), 0.25), 0.55, 0.2)
		# Bearbeitete Teile glänzen blank
		if str(it.get("kind", "")) == "part":
			m = Build.mat(Materials.cut_color(id), 0.3, 0.6)
		if is_round(it):
			var axis: int = Build.AXIS_Z if p["rot"] else Build.AXIS_X
			Build.cyl(_content, float(it["d"]) * 0.0005, float(it["l"]) * 0.001, at, m, axis, false, 16)
		else:
			Build.box(_content, Vector3(pl * 0.001, ph * 0.001, pw * 0.001), at, m)


func get_prompt() -> String:
	return world.crate_prompt(index)


func interact(_p: Node) -> void:
	pass


func click(_p: Node) -> void:
	world.crate_click(index)
