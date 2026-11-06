class_name DrillJobs
extends RefCounted
## Bohraufträge für die Standbohrmaschine, gleicher Aufbau wie MillJobs. Rohteil size = [Länge X, Breite Y,
## Höhe], Bohrungen von der rohen Oberseite (Z = 0) aus. Die Oberseite bleibt unbearbeitet.

const LIST := [
	{
		"title": "Bohrauftrag 1: Lochplatte",
		"desc": "Vier Bohrungen Ø8 an den Ecken. Tipp: Bohrer Ø8, außerhalb des Materials positionieren, dann erst senken.",
		"size": [120.0, 80.0, 20.0], "reward": 170, "material": "S235", "rest": 0.0,
		"features": [
			{"type": "hole", "cx": 20.0, "cy": 20.0, "d": 8.0, "z": -15.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 100.0, "cy": 20.0, "d": 8.0, "z": -15.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 20.0, "cy": 60.0, "d": 8.0, "z": -15.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 100.0, "cy": 60.0, "d": 8.0, "z": -15.0, "tol": 0.3, "around": 0.0},
		],
	},
	{
		"title": "Bohrauftrag 2: Halteleiste",
		"desc": "Drei Bohrungen Ø10 in einer Reihe. Tipp: Der Bohrer verträgt keine seitliche Bewegung im Material.",
		"size": [150.0, 40.0, 25.0], "reward": 210, "material": "9S20", "rest": 0.0,
		"features": [
			{"type": "hole", "cx": 25.0, "cy": 20.0, "d": 10.0, "z": -18.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 75.0, "cy": 20.0, "d": 10.0, "z": -18.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 125.0, "cy": 20.0, "d": 10.0, "z": -18.0, "tol": 0.3, "around": 0.0},
		],
	},
	{
		"title": "Bohrauftrag 3: Flanschplatte",
		"desc": "Große Mittelbohrung Ø16, zwei Befestigungsbohrungen Ø6. Reihenfolge und Werkzeugwechsel selbst planen.",
		"size": [120.0, 80.0, 30.0], "reward": 320, "material": "C45", "rest": 0.0,
		"features": [
			{"type": "hole", "cx": 60.0, "cy": 40.0, "d": 16.0, "z": -22.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 20.0, "cy": 40.0, "d": 6.0, "z": -15.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 100.0, "cy": 40.0, "d": 6.0, "z": -15.0, "tol": 0.3, "around": 0.0},
		],
	},
	{
		"title": "Bohrauftrag 4: Aluminiumdeckel",
		"desc": "Vier Bohrungen Ø5 im Lochbild. Aluminium klebt ohne Kühlung am Bohrer.",
		"size": [100.0, 100.0, 15.0], "reward": 260, "material": "AW-6082", "rest": 0.0,
		"features": [
			{"type": "hole", "cx": 25.0, "cy": 25.0, "d": 5.0, "z": -10.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 75.0, "cy": 25.0, "d": 5.0, "z": -10.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 25.0, "cy": 75.0, "d": 5.0, "z": -10.0, "tol": 0.3, "around": 0.0},
			{"type": "hole", "cx": 75.0, "cy": 75.0, "d": 5.0, "z": -10.0, "tol": 0.3, "around": 0.0},
		],
	},
]


static func get_job(i: int) -> Dictionary:
	return LIST[posmod(i, LIST.size())]
