class_name MillJobs
extends RefCounted
## Fräsaufträge. Rohteil size = [Länge X, Breite Y, Höhe]. Koordinaten ab der vorderen linken Ecke
## der Rohteil-Oberseite: X nach rechts, Y nach hinten, Z = 0 auf der rohen Oberseite (Tiefen negativ).
## Merkmalstypen:
##   area - Fläche x0..x1, y0..y1 auf Höhe z
##   hole - Bohrung Ø d bei cx, cy bis Tiefe z, around = Höhe der Fläche um die Bohrung
## rest = Höhe aller Flächen, die zu keinem Merkmal gehören.

static var _all: Array = []

const LIST := [
	{
		"title": "Fräsauftrag 1: Planfräsen",
		"desc": "Oberseite um 2 mm abplanen. Tipp: Messerkopf, außerhalb des Rohteils auf Tiefe gehen, dann erst einfahren.",
		"size": [100.0, 60.0, 40.0], "reward": 150, "material": "S235",
		"grind": {"type": "flat", "surface": "Oberseite X 0-100, Y 0-60", "area": [0.0, 100.0, 0.0, 60.0], "rz": 2.5, "reward": 110},
		"features": [{"type": "area", "x0": 0.0, "x1": 100.0, "y0": 0.0, "y1": 60.0, "z": -2.0, "tol": 0.2}],
	},
	{
		"title": "Fräsauftrag 2: Absatz",
		"desc": "Absatz an der Vorderkante fräsen. Tipp: Schaftfräser Ø16, von außen einfahren.",
		"size": [100.0, 60.0, 40.0], "reward": 220, "material": "S235", "rest": 0.0,
		"features": [{"type": "area", "x0": 0.0, "x1": 100.0, "y0": 0.0, "y1": 20.0, "z": -8.0, "tol": 0.2}],
	},
	{
		"title": "Fräsauftrag 3: Längsnut",
		"desc": "Durchgehende Nut, 10 mm breit und 6 mm tief. Tipp: Schaftfräser Ø10, Y = 30.",
		"size": [100.0, 60.0, 40.0], "reward": 260, "material": "C45", "rest": 0.0,
		"features": [{"type": "area", "x0": 0.0, "x1": 100.0, "y0": 25.0, "y1": 35.0, "z": -6.0, "tol": 0.2}],
	},
	{
		"title": "Fräsauftrag 4: Rechtecktasche",
		"desc": "Tasche 50 x 30 mm, 10 mm tief. Tipp: Schaftfräser Ø12, mit kleinem Vorschub eintauchen.",
		"size": [100.0, 60.0, 40.0], "reward": 340, "material": "AW-6082", "rest": 0.0,
		"features": [{"type": "area", "x0": 25.0, "x1": 75.0, "y0": 15.0, "y1": 45.0, "z": -10.0, "tol": 0.2}],
	},
	{
		"title": "Fräsauftrag 5: Bohrbild",
		"desc": "Zwei Bohrungen Ø10, 25 mm tief. Tipp: Spiralbohrer, seitlich nur außerhalb des Materials verfahren.",
		"size": [100.0, 60.0, 40.0], "reward": 280, "material": "CuZn39Pb3", "rest": 0.0,
		"features": [
			{"type": "hole", "cx": 25.0, "cy": 30.0, "d": 10.0, "z": -25.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 75.0, "cy": 30.0, "d": 10.0, "z": -25.0, "tol": 0.3, "around": 0.0},
		],
	},
	{
		"title": "Fräsauftrag 6: Deckplatte",
		"desc": "Oberseite 1 mm planen, Tasche fräsen und zwei Bohrungen setzen. Reihenfolge selbst wählen.",
		"size": [120.0, 80.0, 40.0], "reward": 620, "material": "1.4301", "rest": -1.0,
		"grind": {"type": "flat", "surface": "Dichtfläche der Oberseite außerhalb der Tasche", "area": [0.0, 120.0, 0.0, 80.0], "rz": 1.6, "reward": 200},
		"features": [
			{"type": "area", "x0": 35.0, "x1": 85.0, "y0": 20.0, "y1": 60.0, "z": -9.0, "tol": 0.15},
			{"type": "hole", "cx": 15.0, "cy": 40.0, "d": 10.0, "z": -20.0, "tol": 0.3, "around": -1.0},
			{"type": "hole", "cx": 105.0, "cy": 40.0, "d": 10.0, "z": -20.0, "tol": 0.3, "around": -1.0},
		],
	},
	{
		"title": "Fräsauftrag 7: Anschlagleiste",
		"desc": "Oberseite 1 mm abplanen. Tipp: Messerkopf oder großer Schaftfräser, in Bahnen fräsen.",
		"size": [100.0, 40.0, 30.0], "reward": 180, "material": "S235",
		"features": [{"type": "area", "x0": 0.0, "x1": 100.0, "y0": 0.0, "y1": 40.0, "z": -1.0, "tol": 0.2}],
	},
	{
		"title": "Fräsauftrag 8: Querplatte",
		"desc": "Quernut 20 mm breit und 5 mm tief, mittig bei X 60. Tipp: Schaftfräser Ø20, von außen einfahren.",
		"size": [120.0, 60.0, 30.0], "reward": 240, "material": "S235", "rest": 0.0,
		"features": [{"type": "area", "x0": 50.0, "x1": 70.0, "y0": 0.0, "y1": 60.0, "z": -5.0, "tol": 0.2}],
	},
	{
		"title": "Fräsauftrag 9: Stufenblock",
		"desc": "Zwei Absätze: vorne 5 mm tief, hinten 10 mm tief, jeweils 20 mm breit. Die Mitte bleibt stehen.",
		"size": [100.0, 60.0, 40.0], "reward": 290, "material": "S235", "rest": 0.0,
		"features": [
			{"type": "area", "x0": 0.0, "x1": 100.0, "y0": 0.0, "y1": 20.0, "z": -5.0, "tol": 0.2},
			{"type": "area", "x0": 0.0, "x1": 100.0, "y0": 40.0, "y1": 60.0, "z": -10.0, "tol": 0.2},
		],
	},
	{
		"title": "Fräsauftrag 10: Lochplatte",
		"desc": "Vier Bohrungen Ø8, 15 mm tief. Tipp: Spiralbohrer Ø8, seitlich nur außerhalb des Materials verfahren.",
		"size": [100.0, 60.0, 30.0], "reward": 320, "material": "C45", "rest": 0.0,
		"features": [
			{"type": "hole", "cx": 15.0, "cy": 15.0, "d": 8.0, "z": -15.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 85.0, "cy": 15.0, "d": 8.0, "z": -15.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 15.0, "cy": 45.0, "d": 8.0, "z": -15.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 85.0, "cy": 45.0, "d": 8.0, "z": -15.0, "tol": 0.3, "around": 0.0},
		],
	},
	{
		"title": "Fräsauftrag 11: Führungsleiste",
		"desc": "Beidseitig einen Absatz 10 mm breit und 10 mm tief fräsen, die Leiste bleibt in der Mitte stehen.",
		"size": [120.0, 40.0, 40.0], "reward": 360, "material": "AW-6082", "rest": 0.0,
		"features": [
			{"type": "area", "x0": 0.0, "x1": 120.0, "y0": 0.0, "y1": 10.0, "z": -10.0, "tol": 0.15},
			{"type": "area", "x0": 0.0, "x1": 120.0, "y0": 30.0, "y1": 40.0, "z": -10.0, "tol": 0.15},
		],
	},
	{
		"title": "Fräsauftrag 12: Aufnahmeplatte",
		"desc": "Tasche 40 x 40 mm, 8 mm tief, dazu zwei Bohrungen Ø10. Vergütungsstahl: mit Kühlung und kleinem Vorschub.",
		"size": [100.0, 80.0, 30.0], "reward": 580, "material": "42CrMo4", "rest": 0.0,
		"features": [
			{"type": "area", "x0": 30.0, "x1": 70.0, "y0": 20.0, "y1": 60.0, "z": -8.0, "tol": 0.15},
			{"type": "hole", "cx": 12.0, "cy": 40.0, "d": 10.0, "z": -20.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 88.0, "cy": 40.0, "d": 10.0, "z": -20.0, "tol": 0.3, "around": 0.0},
		],
	},
]


## Feste Aufträge und die generierten dahinter.
static func all() -> Array:
	if _all.is_empty():
		_all = LIST + JobGen.mill(LIST.size() + 1)
	return _all


static func get_job(i: int) -> Dictionary:
	var list := all()
	return list[posmod(i, list.size())]


## Zielmaße als einzelne Zeilen.
static func target_lines(job: Dictionary) -> Array:
	var out := []
	for f in job["features"]:
		if str(f["type"]) == "hole":
			out.append("Bohrung Ø%d  X %d  Y %d  Tiefe %.1f" % [int(f["d"]), int(f["cx"]), int(f["cy"]), -float(f["z"])])
		else:
			out.append("X %d-%d  Y %d-%d  auf Z %.1f +/-%.2f" % [int(f["x0"]), int(f["x1"]), int(f["y0"]), int(f["y1"]), float(f["z"]), float(f["tol"])])
	if job.has("rest"):
		out.append("Übrige Fläche auf Z %.1f" % float(job["rest"]))
	return out


## grind: Die geschliffene Fläche nennen (nur wenn die Werkstatt die Schleifmaschine hat).
static func describe(job: Dictionary, grind := false) -> String:
	var s: Array = job["size"]
	var t := "%s\n" % job["title"]
	t += "\nWerkstoff: %s" % Materials.label(str(job.get("material", Materials.DEFAULT)))
	t += "\nRohteil: %d x %d x %d mm" % [int(s[0]), int(s[1]), int(s[2])]
	for f in job["features"]:
		if str(f["type"]) == "hole":
			t += "\n  Bohrung Ø%d  bei X %d  Y %d :  Z %.1f" % [int(f["d"]), int(f["cx"]), int(f["cy"]), float(f["z"])]
		else:
			t += "\n  X %d-%d  Y %d-%d :  Z %.1f  +/-%.2f" % [int(f["x0"]), int(f["x1"]), int(f["y0"]), int(f["y1"]), float(f["z"]), float(f["tol"])]
	if job.has("rest"):
		t += "\n  Übrige Fläche:  Z %.1f" % float(job["rest"])
	if grind and job.has("grind"):
		t += "\n  %s" % JobBoard.grind_line(job)
	t += "\nVergütung: bis %d EUR" % int(job["reward"])
	return t
