class_name MillJobs
extends RefCounted
## Fräsaufträge. Rohteil size = [Länge X, Breite Y, Höhe]. Koordinaten ab der vorderen linken Ecke
## der Rohteil-Oberseite: X nach rechts, Y nach hinten, Z = 0 auf der rohen Oberseite (Tiefen negativ).
## Merkmalstypen:
##   area - Fläche x0..x1, y0..y1 auf Höhe z
##   hole - Bohrung Ø d bei cx, cy bis Tiefe z, around = Höhe der Fläche um die Bohrung
## rest = Höhe aller Flächen, die zu keinem Merkmal gehören.

const LIST := [
	{
		"title": "Fräsauftrag 1: Planfräsen",
		"desc": "Oberseite um 2 mm abplanen. Tipp: Messerkopf, außerhalb des Rohteils auf Tiefe gehen, dann erst einfahren.",
		"size": [100.0, 60.0, 40.0], "reward": 150,
		"features": [{"type": "area", "x0": 0.0, "x1": 100.0, "y0": 0.0, "y1": 60.0, "z": -2.0, "tol": 0.2}],
	},
	{
		"title": "Fräsauftrag 2: Absatz",
		"desc": "Absatz an der Vorderkante fräsen. Tipp: Schaftfräser Ø16, von außen einfahren.",
		"size": [100.0, 60.0, 40.0], "reward": 220, "rest": 0.0,
		"features": [{"type": "area", "x0": 0.0, "x1": 100.0, "y0": 0.0, "y1": 20.0, "z": -8.0, "tol": 0.2}],
	},
	{
		"title": "Fräsauftrag 3: Längsnut",
		"desc": "Durchgehende Nut, 10 mm breit und 6 mm tief. Tipp: Schaftfräser Ø10, Y = 30.",
		"size": [100.0, 60.0, 40.0], "reward": 260, "rest": 0.0,
		"features": [{"type": "area", "x0": 0.0, "x1": 100.0, "y0": 25.0, "y1": 35.0, "z": -6.0, "tol": 0.2}],
	},
	{
		"title": "Fräsauftrag 4: Rechtecktasche",
		"desc": "Tasche 50 x 30 mm, 10 mm tief. Tipp: Schaftfräser Ø12, mit kleinem Vorschub eintauchen.",
		"size": [100.0, 60.0, 40.0], "reward": 340, "rest": 0.0,
		"features": [{"type": "area", "x0": 25.0, "x1": 75.0, "y0": 15.0, "y1": 45.0, "z": -10.0, "tol": 0.2}],
	},
	{
		"title": "Fräsauftrag 5: Bohrbild",
		"desc": "Zwei Bohrungen Ø10, 25 mm tief. Tipp: Spiralbohrer, seitlich nur außerhalb des Materials verfahren.",
		"size": [100.0, 60.0, 40.0], "reward": 280, "rest": 0.0,
		"features": [
			{"type": "hole", "cx": 25.0, "cy": 30.0, "d": 10.0, "z": -25.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 75.0, "cy": 30.0, "d": 10.0, "z": -25.0, "tol": 0.3, "around": 0.0},
		],
	},
	{
		"title": "Fräsauftrag 6: Deckplatte",
		"desc": "Oberseite 1 mm planen, Tasche fräsen und zwei Bohrungen setzen. Reihenfolge selbst wählen.",
		"size": [120.0, 80.0, 40.0], "reward": 620, "rest": -1.0,
		"features": [
			{"type": "area", "x0": 35.0, "x1": 85.0, "y0": 20.0, "y1": 60.0, "z": -9.0, "tol": 0.15},
			{"type": "hole", "cx": 15.0, "cy": 40.0, "d": 10.0, "z": -20.0, "tol": 0.3, "around": -1.0},
			{"type": "hole", "cx": 105.0, "cy": 40.0, "d": 10.0, "z": -20.0, "tol": 0.3, "around": -1.0},
		],
	},
]


static func get_job(i: int) -> Dictionary:
	return LIST[posmod(i, LIST.size())]


static func describe(job: Dictionary) -> String:
	var s: Array = job["size"]
	var t := "%s\n%s\n" % [job["title"], job["desc"]]
	t += "\nRohteil: %d x %d x %d mm" % [int(s[0]), int(s[1]), int(s[2])]
	for f in job["features"]:
		if str(f["type"]) == "hole":
			t += "\n  Bohrung Ø%d  bei X %d  Y %d :  Z %.1f" % [int(f["d"]), int(f["cx"]), int(f["cy"]), float(f["z"])]
		else:
			t += "\n  X %d-%d  Y %d-%d :  Z %.1f  +/-%.2f" % [int(f["x0"]), int(f["x1"]), int(f["y0"]), int(f["y1"]), float(f["z"]), float(f["tol"])]
	if job.has("rest"):
		t += "\n  Übrige Fläche:  Z %.1f" % float(job["rest"])
	t += "\nVergütung: bis %d EUR" % int(job["reward"])
	return t
