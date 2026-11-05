class_name Jobs
extends RefCounted
## Fertigungsaufträge. Z-Maße ab Backen-Stirnfläche (wie die Positionsanzeige).
## Merkmalstypen:
##   dia     - Durchmesser d zwischen z0 und z1 (margin = Prüfabstand zu den Enden)
##   chamfer - Fase size x 45° an der rechten Kante eines Durchmessers d bei Z = z
##   point   - Durchmesser d an genau einer Stelle z (z.B. Nutgrund)
## rz = maximal zulässige gemittelte Rautiefe auf allen Durchmessern (µm).

const LIST := [
	{
		"title": "Auftrag 1: Rundmaterial überdrehen",
		"desc": "Außendurchmesser auf Ø56 abdrehen. Tipp: T1 Schruppmeißel, Längsvorschub (T).",
		"stock_d": 60.0, "stock_len": 160.0, "length": 160.0, "reward": 120,
		"features": [{"type": "dia", "z0": 10.0, "z1": 160.0, "d": 56.0, "tol": 0.3}],
	},
	{
		"title": "Auftrag 2: Plandrehen und Absatz",
		"desc": "Stirnseite auf Länge 150 plandrehen (Planvorschub G), dann Absatz drehen.",
		"stock_d": 60.0, "stock_len": 160.0, "length": 150.0, "reward": 200,
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 90.0, "d": 58.0, "tol": 0.3},
			{"type": "dia", "z0": 90.0, "z1": 150.0, "d": 50.0, "tol": 0.3},
		],
	},
	{
		"title": "Auftrag 3: Stufenwelle mit Endfase",
		"desc": "Drei Stufen, am Ende Fase 1 x 45°. Tipp: Fase mit T5 Fasenmeißel.",
		"stock_d": 60.0, "stock_len": 180.0, "length": 170.0, "reward": 340,
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 90.0, "d": 56.0, "tol": 0.2},
			{"type": "dia", "z0": 90.0, "z1": 140.0, "d": 45.0, "tol": 0.2},
			{"type": "dia", "z0": 140.0, "z1": 170.0, "d": 30.0, "tol": 0.2, "margin": 2.0},
			{"type": "chamfer", "z": 170.0, "d": 30.0, "size": 1.0},
		],
	},
	{
		"title": "Auftrag 4: Bolzen mit Einstich",
		"desc": "Einstich 6 mm breit auf Ø30. Tipp: T6 Stechmeißel, zweimal radial einstechen.",
		"stock_d": 50.0, "stock_len": 140.0, "length": 130.0, "reward": 380,
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 70.0, "d": 40.0, "tol": 0.25},
			{"type": "dia", "z0": 70.0, "z1": 76.0, "d": 30.0, "tol": 0.3},
			{"type": "dia", "z0": 76.0, "z1": 130.0, "d": 40.0, "tol": 0.25},
		],
	},
	{
		"title": "Auftrag 5: Achse mit Fasen",
		"desc": "Absatz Ø44 / Ø30 mit Fasen an der Schulter und am Ende.",
		"stock_d": 50.0, "stock_len": 120.0, "length": 110.0, "reward": 420,
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 70.0, "d": 44.0, "tol": 0.2, "margin": 2.5},
			{"type": "dia", "z0": 70.0, "z1": 110.0, "d": 30.0, "tol": 0.2, "margin": 2.5},
			{"type": "chamfer", "z": 70.0, "d": 44.0, "size": 1.0},
			{"type": "chamfer", "z": 110.0, "d": 30.0, "size": 1.5},
		],
	},
	{
		"title": "Auftrag 6: Welle mit Radiusnut",
		"desc": "Ø38 überdrehen, Radiusnut R3 mit Nutgrund Ø32 bei Z 55. Tipp: T7 Radiusmeißel.",
		"stock_d": 40.0, "stock_len": 110.0, "length": 100.0, "reward": 450,
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 51.0, "d": 38.0, "tol": 0.2},
			{"type": "point", "z": 55.0, "d": 32.0, "tol": 0.2},
			{"type": "dia", "z0": 59.0, "z1": 100.0, "d": 38.0, "tol": 0.2},
		],
	},
	{
		"title": "Auftrag 7: Präzisionswelle",
		"desc": "Enge Toleranz und Oberfläche Rz <= 6,3 µm. Tipp: zum Schluss mit Auto-Vorschub schlichten.",
		"stock_d": 40.0, "stock_len": 150.0, "length": 140.0, "reward": 600, "rz": 6.3,
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 60.0, "d": 36.0, "tol": 0.1},
			{"type": "dia", "z0": 60.0, "z1": 110.0, "d": 30.0, "tol": 0.1},
			{"type": "dia", "z0": 110.0, "z1": 140.0, "d": 20.0, "tol": 0.1, "margin": 2.0},
			{"type": "chamfer", "z": 140.0, "d": 20.0, "size": 1.0},
		],
	},
]


static func get_job(i: int) -> Dictionary:
	return LIST[posmod(i, LIST.size())]


static func describe(job: Dictionary) -> String:
	var t := "%s\n%s\n" % [job["title"], job["desc"]]
	t += "\nRohteil: Ø%d x %d mm" % [int(job["stock_d"]), int(job["stock_len"])]
	if job.has("length"):
		t += "    Gesamtlänge: %d mm" % int(job["length"])
	for f in job["features"]:
		match str(f.get("type", "dia")):
			"dia":
				t += "\n  Z %3d - %3d :  Ø%.1f  +/-%.2f" % [int(f["z0"]), int(f["z1"]), float(f["d"]), float(f.get("tol", 0.3))]
			"chamfer":
				t += "\n  Fase %.1f x 45° an Z %d (Ø%d)" % [float(f["size"]), int(f["z"]), int(f["d"])]
			"point":
				t += "\n  Nutgrund Z %.0f :  Ø%.1f" % [float(f["z"]), float(f["d"])]
	if job.has("rz"):
		t += "\n  Oberfläche: Rz <= %.1f µm" % float(job["rz"])
	t += "\nVergütung: bis %d EUR" % int(job["reward"])
	return t
