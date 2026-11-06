class_name JobGen
extends RefCounted
## Zusätzliche Aufträge aus dem Zufall. Der Startwert ist fest: Jeder Auftrag behält in jedem Spielstand
## dieselbe Nummer und dieselben Maße, gespeichert wird nur die Nummer. Welche davon am PC angeboten werden,
## wechselt mit dem Tag. Freigeschaltet werden sie wie alle anderen über Maschine und Werkstoff.
## Neue Aufträge kommen hinten dazu: Eine höhere Anzahl ändert die vorhandenen nicht.

const SEED := 20261106
const LATHE_COUNT := 68
const MILL_COUNT := 68
const DRILL_COUNT := 32
const LATHE_MATERIALS := ["S235", "S235", "S235", "S235", "9S20", "C45", "C45", "AW-6082", "CuZn39Pb3", "42CrMo4", "1.4301"]
const MILL_MATERIALS := ["S235", "S235", "S235", "9S20", "C45", "AW-6082", "CuZn39Pb3", "42CrMo4"]
const LATHE_NAMES := ["Welle", "Bolzen", "Achse", "Zapfen", "Stufenbolzen", "Führungsbolzen", "Distanzstück", "Antriebswelle", "Passbolzen", "Lagerzapfen"]
const MILL_NAMES := ["Grundplatte", "Halteplatte", "Führungsblock", "Anschlagleiste", "Spannpratze", "Lagerbock", "Deckel", "Klemmstück", "Montageplatte", "Stützblock"]
const DRILL_NAMES := ["Lochplatte", "Lochleiste", "Flansch", "Winkelstück", "Trägerplatte", "Befestigungsleiste"]
const MILL_SIZES := [[100.0, 60.0, 40.0], [120.0, 60.0, 30.0], [100.0, 80.0, 30.0], [120.0, 40.0, 40.0], [80.0, 60.0, 30.0]]
const DRILL_SIZES := [[120.0, 80.0, 20.0], [150.0, 40.0, 25.0], [100.0, 60.0, 20.0]]


static func _pick(rng: RandomNumberGenerator, list: Array):
	return list[rng.randi_range(0, list.size() - 1)]


## Vergütung auf volle zehn Euro.
static func _reward(base: float) -> int:
	return int(ceil(base / 10.0)) * 10


## Stufenteil mit 1 bis 3 Durchmessern, die zum Ende kleiner werden. first = Nummer des ersten Auftrags.
static func lathe(first: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var out := []
	for n in LATHE_COUNT:
		var mat: String = _pick(rng, LATHE_MATERIALS)
		var stock_d: float = _pick(rng, [30.0, 40.0, 50.0, 60.0])
		var length := float(rng.randi_range(8, 18) * 10)
		var facing := rng.randf() < 0.4
		var stock_len := length + (10.0 if facing else 0.0)
		var steps := rng.randi_range(1, 3)
		var tol: float = _pick(rng, [0.3, 0.25, 0.2])
		var features := []
		var z := 10.0
		var d := stock_d
		var left := length - 10.0
		for s in steps:
			d -= float(rng.randi_range(1, 3)) * 2.0 + (0.0 if s == 0 else 2.0)
			var z1 := length if s == steps - 1 else z + roundf(left * rng.randf_range(0.3, 0.55) / 5.0) * 5.0
			features.append({"type": "dia", "z0": z, "z1": z1, "d": d, "tol": tol})
			left -= z1 - z
			z = z1
		var chamfer := rng.randf() < 0.35
		if chamfer:
			features[-1]["margin"] = 2.0
			features.append({"type": "chamfer", "z": length, "d": d, "size": 1.0})
		var tip := "Stufen von außen nach innen drehen."
		if facing:
			tip = "Erst die Stirnseite auf Fertiglänge plandrehen. " + tip
		if chamfer:
			tip += " Fase mit T5 Fasenmeißel."
		out.append({
			"title": "Auftrag %d: %s" % [first + n, _pick(rng, LATHE_NAMES)], "desc": tip,
			"stock_d": stock_d, "stock_len": stock_len, "length": length, "material": mat,
			"reward": _reward(180.0 + steps * 60.0 + float(Materials.price(mat, Materials.KIND_ROUND, stock_d, 0.0, 0.0, Materials.BAR_LEN))),
			"features": features,
		})
	return out


static func mill(first: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var out := []
	for n in MILL_COUNT:
		var mat: String = _pick(rng, MILL_MATERIALS)
		var s: Array = _pick(rng, MILL_SIZES)
		var l := float(s[0])
		var w := float(s[1])
		var tol := 0.2
		var features := []
		var tip := ""
		var job := {}
		match rng.randi_range(0, 4):
			0:
				features = [{"type": "area", "x0": 0.0, "x1": l, "y0": 0.0, "y1": w, "z": -float(rng.randi_range(1, 3)), "tol": tol}]
				tip = "Messerkopf, außerhalb des Rohteils auf Tiefe gehen."
			1:
				features = [{"type": "area", "x0": 0.0, "x1": l, "y0": 0.0, "y1": roundf(w / 3.0 / 5.0) * 5.0, "z": -float(rng.randi_range(4, 10)), "tol": tol}]
				job["rest"] = 0.0
				tip = "Großer Schaftfräser, von außen einfahren."
			2:
				var slot: float = _pick(rng, [10.0, 12.0, 16.0])
				var cy := roundf(w * 0.5)
				features = [{"type": "area", "x0": 0.0, "x1": l, "y0": cy - slot * 0.5, "y1": cy + slot * 0.5, "z": -float(rng.randi_range(4, 8)), "tol": tol}]
				job["rest"] = 0.0
				tip = "Schaftfräser Ø%d, durchgehend fräsen." % int(slot)
			3:
				features = [{"type": "area", "x0": roundf(l * 0.25), "x1": roundf(l * 0.75), "y0": roundf(w * 0.25), "y1": roundf(w * 0.75), "z": -float(rng.randi_range(5, 10)), "tol": tol}]
				job["rest"] = 0.0
				tip = "Schaftfräser, mit kleinem Vorschub eintauchen."
			_:
				features = _holes(rng, l, w, -float(rng.randi_range(10, 20)), [6.0, 8.0, 10.0, 12.0])
				job["rest"] = 0.0
				tip = "Spiralbohrer, seitlich nur außerhalb des Materials verfahren."
		job.merge({
			"title": "Fräsauftrag %d: %s" % [first + n, _pick(rng, MILL_NAMES)], "desc": tip, "size": s, "material": mat,
			"reward": _reward(220.0 + features.size() * 50.0 + float(Materials.price(mat, Materials.KIND_CUT, 0.0, w, float(s[2]), l))),
			"features": features,
		})
		out.append(job)
	return out


static func drill(first: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 2
	var out := []
	for n in DRILL_COUNT:
		var mat: String = _pick(rng, MILL_MATERIALS)
		var s: Array = _pick(rng, DRILL_SIZES)
		var features := _holes(rng, float(s[0]), float(s[1]), -(float(s[2]) - 5.0), [6.0, 8.0, 10.0, 12.0, 14.0, 16.0])
		out.append({
			"title": "Bohrauftrag %d: %s" % [first + n, _pick(rng, DRILL_NAMES)], "size": s, "material": mat, "rest": 0.0,
			"desc": "Außerhalb des Materials positionieren, dann erst senken.",
			"reward": _reward(180.0 + features.size() * 30.0 + float(Materials.price(mat, Materials.KIND_CUT, 0.0, float(s[1]), float(s[2]), float(s[0])))),
			"features": features,
		})
	return out


## 2 bis 4 gleiche Bohrungen in einer Reihe oder an den Ecken, mit Abstand zum Rand.
static func _holes(rng: RandomNumberGenerator, l: float, w: float, z: float, sizes: Array) -> Array:
	var d: float = _pick(rng, sizes)
	var margin := 15.0
	var spots := []
	match rng.randi_range(0, 2):
		0:
			spots = [[margin, w * 0.5], [l - margin, w * 0.5]]
		1:
			spots = [[margin, w * 0.5], [l * 0.5, w * 0.5], [l - margin, w * 0.5]]
		_:
			spots = [[margin, margin], [l - margin, margin], [margin, w - margin], [l - margin, w - margin]]
	var out := []
	for p in spots:
		out.append({"type": "hole", "cx": float(p[0]), "cy": float(p[1]), "d": d, "z": z, "tol": 0.3, "around": 0.0})
	return out
