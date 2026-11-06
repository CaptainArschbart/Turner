class_name Storage
extends RefCounted
## Was in einen Regalplatz passt. Ein Regalplatz ist ein Lagerboden und hält nur eine Materialart:
## Rund- oder Vierkantstangen als Pyramide 5-4-3-2-1 (bis zu 15 Stück, auch verschiedene Querschnitte)
## oder Fertigschnitte, die nach ihren Maßen nebeneinander liegen.
## Maße in mm, längs = Stangenrichtung, quer = Regaltiefe.

const BOARD_L := 3000.0   # Stange ist 3 m lang und passt genau hinein
const BOARD_D := 900.0
const BOARD_H := 1000.0   # lichte Höhe bis zum nächsten Boden
const PYRAMID := 5        # unterste Reihe, jede Reihe darüber eine weniger
const ROUND_STEP := 0.866 # Rundstangen liegen in der Mulde der Reihe darunter


static func is_bar(item: Dictionary) -> bool:
	return str(item["kind"]) != Materials.KIND_CUT


## Breite einer Stange quer zum Regal.
static func bar_width(item: Dictionary) -> float:
	return float(item["d"]) if str(item["kind"]) == Materials.KIND_ROUND else float(item["w"])


static func _bar_height(item: Dictionary) -> float:
	return float(item["d"]) if str(item["kind"]) == Materials.KIND_ROUND else float(item["h"])


## Stangen in Reihen legen: unten bis zu 5, jede Reihe darüber eine weniger als die darunter.
## Gibt je Stange Vector2(x quer ab der Bodenmitte, y Unterkante) zurück, leer = passt nicht.
static func layout_bars(items: Array) -> Array:
	var rows: Array = [[]]
	var limit := PYRAMID
	var width := 0.0
	for it in items:
		var w := bar_width(it)
		if w > BOARD_D + 0.001:
			return []
		if rows[-1].size() >= limit or width + w > BOARD_D + 0.001:
			limit = rows[-1].size() - 1
			if limit < 1:
				return []
			rows.append([])
			width = 0.0
		rows[-1].append(it)
		width += w
	var out: Array = []
	var y := 0.0
	var prev: Array = []
	for row in rows:
		y += _row_step(prev, row)
		var total := 0.0
		for it in row:
			total += bar_width(it)
			if y + _bar_height(it) > BOARD_H + 0.001:
				return []
		var x := -total * 0.5
		for it in row:
			out.append(Vector2(x + bar_width(it) * 0.5, y))
			x += bar_width(it)
		prev = row
	return out


## Abstand einer Reihe zur Reihe darunter. Gleich dicke Rundstangen liegen in den Mulden.
static func _row_step(below: Array, row: Array) -> float:
	if below.is_empty():
		return 0.0
	var high := 0.0
	var same := str(below[0]["kind"]) == Materials.KIND_ROUND
	for it in below:
		high = maxf(high, _bar_height(it))
	for it in below + row:
		same = same and is_equal_approx(float(it["d"]), float(below[0]["d"]))
	return high * ROUND_STEP if same else high


## Wie viele Stangen dieses Querschnitts höchstens auf einen Boden passen.
static func bar_capacity(item: Dictionary) -> int:
	var items := []
	for i in 15:
		items.append(item)
		if layout_bars(items).is_empty():
			return i
	return 15


## Fertigschnitte in Reihen auf einem Boden der Größe l x d legen, jedes Stück auch gedreht.
## Gibt je Stück {"along", "across", "rot"} zurück oder ein leeres Array, wenn sie nicht passen.
static func layout_cut(items: Array, board_l := BOARD_L, board_d := BOARD_D, board_h := BOARD_H) -> Array:
	var rows: Array = []   # je {"across", "depth", "used"}
	var out: Array = []
	for it in items:
		var l := float(it["l"])
		var w := float(it["w"])
		if float(it["h"]) > board_h + 0.001:
			return []
		var placed := _place_in_rows(rows, l, w, board_l, board_d)
		if placed.is_empty():
			return []
		out.append(placed)
	return out


static func _place_in_rows(rows: Array, l: float, w: float, board_l: float, board_d: float) -> Dictionary:
	var eps := 0.001
	for i in rows.size():
		var row: Dictionary = rows[i]
		var last: bool = i == rows.size() - 1
		for o in [[l, w, false], [w, l, true]]:
			var ol: float = o[0]
			var ow: float = o[1]
			var fits_depth: bool = ow <= float(row["depth"]) + eps or (last and float(row["across"]) + ow <= board_d + eps)
			if float(row["used"]) + ol <= board_l + eps and fits_depth:
				var at := {"along": float(row["used"]), "across": float(row["across"]), "rot": o[2]}
				row["used"] = float(row["used"]) + ol
				row["depth"] = maxf(float(row["depth"]), ow)
				return at
	var next := 0.0
	if not rows.is_empty():
		next = float(rows[-1]["across"]) + float(rows[-1]["depth"])
	for o in [[l, w, false], [w, l, true]]:
		var ol: float = o[0]
		var ow: float = o[1]
		if ol <= board_l + eps and next + ow <= board_d + eps:
			rows.append({"across": next, "depth": ow, "used": ol})
			return {"along": 0.0, "across": next, "rot": o[2]}
	return {}


## Passt das Stück überhaupt in ein leeres Regalfach?
static func fits_empty(item: Dictionary) -> bool:
	if is_bar(item):
		return bar_capacity(item) > 0
	return not layout_cut([item]).is_empty()


## Passt das Stück zu dem, was schon auf dem Boden liegt?
static func fits_with(on_board: Array, item: Dictionary) -> bool:
	if on_board.is_empty():
		return fits_empty(item)
	if is_bar(item):
		if str(on_board[0]["kind"]) != str(item["kind"]):
			return false
		var bars := on_board.duplicate()
		bars.append(item)
		return not layout_bars(bars).is_empty()
	if is_bar(on_board[0]):
		return false
	var all := on_board.duplicate()
	all.append(item)
	return not layout_cut(all).is_empty()


## Stücke, die auf Boden slot liegen.
static func on_board(stock: Array, slot: int) -> Array:
	var out := []
	for it in stock:
		if int(it.get("slot", -1)) == slot:
			out.append(it)
	return out


## Bester Boden für item: zuerst dazulegen, dann ein leerer. -1 = alles voll.
static func find_slot(stock: Array, item: Dictionary, slots: int) -> int:
	var empty := -1
	for i in slots:
		var here := on_board(stock, i)
		if here.is_empty():
			if empty < 0:
				empty = i
			continue
		if fits_with(here, item):
			return i
	return empty if empty >= 0 and fits_empty(item) else -1


## Bester Boden in einem einzelnen Regal. -1 = dort ist kein Platz.
static func find_slot_in(stock: Array, item: Dictionary, slots: Array) -> int:
	var empty := -1
	for i in slots:
		var here := on_board(stock, i)
		if here.is_empty():
			if empty < 0:
				empty = i
		elif fits_with(here, item):
			return i
	return empty if empty >= 0 and fits_empty(item) else -1


## Belegte Böden.
static func used_slots(stock: Array) -> int:
	var seen := {}
	for it in stock:
		var s := int(it.get("slot", -1))
		if s >= 0:
			seen[s] = true
	return seen.size()


## Stücke ohne Boden einordnen, zum Beispiel aus alten Spielständen.
static func assign_missing(stock: Array, slots: int) -> void:
	for it in stock:
		if int(it.get("slot", -1)) < 0:
			it["slot"] = find_slot(stock, it, slots)
