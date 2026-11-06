class_name CeramicJobs
extends RefCounted
## Besondere Kundenaufträge: Der Kunde liefert ein Teil mit Keramikbeschichtung mit, es steht nach dem
## Annehmen im Hof. Geschliffen werden kann es nur mit einer Diamantscheibe. Eigenes Material braucht es
## hier nicht. Aufbau wie MillJobs (Flachschleifen) oder Jobs (Rundschleifen), reward = ganzer Auftrag.

const LIST := [
	{
		"title": "Kundenauftrag: Dichtplatte",
		"desc": "Keramikbeschichtete Dichtplatte vom Kunden, die Oberseite 0,1 mm abschleifen. Teil wird mitgeliefert, nur mit Diamantscheibe.",
		"size": [120.0, 80.0, 20.0], "reward": 950, "material": "1.4301", "days": 4,
		"grind": {"type": "flat", "ceramic": true, "surface": "Keramikschicht der Oberseite", "area": [0.0, 120.0, 0.0, 80.0], "rz": 1.0, "reward": 950},
		"features": [{"type": "area", "x0": 0.0, "x1": 120.0, "y0": 0.0, "y1": 80.0, "z": -0.1, "tol": 0.06}],
	},
	{
		"title": "Kundenauftrag: Verschleißleiste",
		"desc": "Keramikbeschichtete Leiste vom Kunden, die Oberseite 0,05 mm abschleifen. Teil wird mitgeliefert, nur mit Diamantscheibe.",
		"size": [150.0, 40.0, 25.0], "reward": 780, "material": "42CrMo4", "days": 3,
		"grind": {"type": "flat", "ceramic": true, "surface": "Keramikschicht der Oberseite", "area": [0.0, 150.0, 0.0, 40.0], "rz": 1.6, "reward": 780},
		"features": [{"type": "area", "x0": 0.0, "x1": 150.0, "y0": 0.0, "y1": 40.0, "z": -0.05, "tol": 0.04}],
	},
	{
		"title": "Kundenauftrag: Pumpenwelle",
		"desc": "Welle mit Keramiksitz vom Kunden, den Sitz auf Ø39,8 schleifen. Teil wird mitgeliefert, nur mit Diamantscheibe.",
		"stock_d": 40.0, "stock_len": 150.0, "reward": 1100, "material": "1.4301", "days": 5,
		"grind": {"type": "round", "ceramic": true, "surface": "Keramiksitz Ø39,8 von Z 40 bis 110", "z0": 40.0, "z1": 110.0, "rz": 1.0, "reward": 1100},
		"features": [{"type": "dia", "z0": 40.0, "z1": 110.0, "d": 39.8, "tol": 0.06}],
	},
]


static func get_job(i: int) -> Dictionary:
	return LIST[posmod(i, LIST.size())]


## Das mitgelieferte Teil, wie es in der Hand und an der Schleifmaschine geführt wird.
static func part_of(job: Dictionary) -> Dictionary:
	if job["grind"]["type"] == "round":
		return {"stock_d": job["stock_d"], "stock_len": job["stock_len"], "material": job["material"], "ceramic": true}
	return {"size": job["size"], "material": job["material"], "ceramic": true}


## Maße für den Stellplatz im Hof.
static func delivery_of(key: String, job: Dictionary) -> Dictionary:
	var item := {"kind": "semi", "key": key, "type": job["grind"]["type"], "title": job["title"], "part": part_of(job),
		"material": job["material"], "d": 0.0}
	if job["grind"]["type"] == "round":
		item.merge({"l": job["stock_len"], "w": job["stock_d"], "h": job["stock_d"]})
	else:
		item.merge({"l": job["size"][0], "w": job["size"][1], "h": job["size"][2]})
	return item
