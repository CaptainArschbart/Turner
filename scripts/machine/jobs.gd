class_name Jobs
extends RefCounted
## Fertigungsaufträge. Z-Maße ab Backen-Stirnfläche (wie die Positionsanzeige).
## Merkmalstypen:
##   dia     - Durchmesser d zwischen z0 und z1 (margin = Prüfabstand zu den Enden)
##   chamfer - Fase size x 45° an der rechten Kante eines Durchmessers d bei Z = z
##   point   - Durchmesser d an genau einer Stelle z (z.B. Nutgrund)
## rz = maximal zulässige gemittelte Rautiefe auf allen Durchmessern (µm).

static var _all: Array = []

const LIST := [
	{
		"title": "Auftrag 1: Rundmaterial überdrehen",
		"desc": "Außendurchmesser auf einer Länge von 150 mm auf Ø56 abdrehen (Z 10 bis 160), die ersten 10 mm stecken im Futter. Fertiglänge 160 mm. Tipp: T1 Schruppmeißel, Auto-Vorschub.",
		"stock_d": 60.0, "stock_len": 160.0, "length": 160.0, "reward": 180, "material": "S235",
		"features": [{"type": "dia", "z0": 10.0, "z1": 160.0, "d": 56.0, "tol": 0.3}],
	},
	{
		"title": "Auftrag 2: Plandrehen und Absatz",
		"desc": "Stirnseite auf Länge 150 plandrehen (Planvorschub G), dann Absatz drehen.",
		"stock_d": 60.0, "stock_len": 160.0, "length": 150.0, "reward": 200, "material": "S235",
		"grind": {"type": "round", "surface": "Ø58 von Z 10 bis 90", "z0": 10.0, "z1": 90.0, "rz": 2.5, "reward": 90},
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 90.0, "d": 58.0, "tol": 0.3},
			{"type": "dia", "z0": 90.0, "z1": 150.0, "d": 50.0, "tol": 0.3},
		],
	},
	{
		"title": "Auftrag 3: Stufenwelle mit Endfase",
		"desc": "Drei Stufen, am Ende Fase 1 x 45°. Tipp: Fase mit T5 Fasenmeißel.",
		"stock_d": 60.0, "stock_len": 180.0, "length": 170.0, "reward": 340, "material": "C45",
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
		"stock_d": 50.0, "stock_len": 140.0, "length": 130.0, "reward": 380, "material": "9S20",
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 70.0, "d": 40.0, "tol": 0.25},
			{"type": "dia", "z0": 70.0, "z1": 76.0, "d": 30.0, "tol": 0.3},
			{"type": "dia", "z0": 76.0, "z1": 130.0, "d": 40.0, "tol": 0.25},
		],
	},
	{
		"title": "Auftrag 5: Achse mit Fasen",
		"desc": "Absatz Ø44 / Ø30 mit Fasen an der Schulter und am Ende.",
		"stock_d": 50.0, "stock_len": 120.0, "length": 110.0, "reward": 420, "material": "AW-6082",
		"grind": {"type": "round", "surface": "Ø44 von Z 10 bis 70", "z0": 10.0, "z1": 70.0, "rz": 2.5, "reward": 120},
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
		"stock_d": 40.0, "stock_len": 110.0, "length": 100.0, "reward": 450, "material": "CuZn39Pb3",
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 51.0, "d": 38.0, "tol": 0.2},
			{"type": "point", "z": 55.0, "d": 32.0, "tol": 0.2},
			{"type": "dia", "z0": 59.0, "z1": 100.0, "d": 38.0, "tol": 0.2},
		],
	},
	{
		"title": "Auftrag 7: Präzisionswelle",
		"desc": "Enge Toleranz und Oberfläche Rz <= 6,3 µm. Tipp: zum Schluss mit Auto-Vorschub schlichten.",
		"stock_d": 40.0, "stock_len": 150.0, "length": 140.0, "reward": 600, "material": "42CrMo4", "rz": 6.3,
		"grind": {"type": "round", "surface": "Lagersitz Ø30 von Z 60 bis 110", "z0": 60.0, "z1": 110.0, "rz": 1.6, "reward": 180},
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 60.0, "d": 36.0, "tol": 0.1},
			{"type": "dia", "z0": 60.0, "z1": 110.0, "d": 30.0, "tol": 0.1},
			{"type": "dia", "z0": 110.0, "z1": 140.0, "d": 20.0, "tol": 0.1, "margin": 2.0},
			{"type": "chamfer", "z": 140.0, "d": 20.0, "size": 1.0},
		],
	},
	{
		"title": "Auftrag 8: Distanzbolzen",
		"desc": "Ø36 auf einer Länge von 90 mm drehen, Fertiglänge 100 mm. Tipp: T1 Schruppmeißel, zum Schluss mit kleinem Vorschub auf Maß.",
		"stock_d": 40.0, "stock_len": 100.0, "length": 100.0, "reward": 190, "material": "S235",
		"features": [{"type": "dia", "z0": 10.0, "z1": 100.0, "d": 36.0, "tol": 0.3}],
	},
	{
		"title": "Auftrag 9: Absatzbolzen",
		"desc": "Stirnseite auf Fertiglänge 110 mm plandrehen, dann Ø46 auf 50 mm und Ø36 auf 50 mm Länge drehen.",
		"stock_d": 50.0, "stock_len": 120.0, "length": 110.0, "reward": 240, "material": "S235",
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 60.0, "d": 46.0, "tol": 0.3},
			{"type": "dia", "z0": 60.0, "z1": 110.0, "d": 36.0, "tol": 0.3},
		],
	},
	{
		"title": "Auftrag 10: Zapfenwelle",
		"desc": "Drei Stufen, Fertiglänge 130 mm. Automatenstahl gibt kurze Späne, die Drehzahl darf höher sein.",
		"stock_d": 40.0, "stock_len": 140.0, "length": 130.0, "reward": 300, "material": "9S20",
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 70.0, "d": 36.0, "tol": 0.25},
			{"type": "dia", "z0": 70.0, "z1": 110.0, "d": 28.0, "tol": 0.25},
			{"type": "dia", "z0": 110.0, "z1": 130.0, "d": 20.0, "tol": 0.25},
		],
	},
	{
		"title": "Auftrag 11: Führungsbolzen mit Fase",
		"desc": "Ø45 auf 70 mm, Ø35 auf 40 mm, am Ende Fase 1 x 45°. Fertiglänge 120 mm. Tipp: Fase mit T5 Fasenmeißel.",
		"stock_d": 50.0, "stock_len": 130.0, "length": 120.0, "reward": 360, "material": "C45",
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 80.0, "d": 45.0, "tol": 0.2},
			{"type": "dia", "z0": 80.0, "z1": 120.0, "d": 35.0, "tol": 0.2, "margin": 2.0},
			{"type": "chamfer", "z": 120.0, "d": 35.0, "size": 1.0},
		],
	},
	{
		"title": "Auftrag 12: Aluminiumzapfen",
		"desc": "Ø55 auf 60 mm, Ø40 auf 40 mm. Fertiglänge 110 mm. Aluminium verträgt hohe Schnittgeschwindigkeit, aber nur mit Kühlung.",
		"stock_d": 60.0, "stock_len": 120.0, "length": 110.0, "reward": 360, "material": "AW-6082",
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 70.0, "d": 55.0, "tol": 0.2},
			{"type": "dia", "z0": 70.0, "z1": 110.0, "d": 40.0, "tol": 0.2},
		],
	},
	{
		"title": "Auftrag 13: Edelstahlachse",
		"desc": "Ø36 auf 40 mm, Ø28 auf 30 mm. Fertiglänge 80 mm. Edelstahl leitet Wärme schlecht: langsam und mit Kühlung.",
		"stock_d": 40.0, "stock_len": 90.0, "length": 80.0, "reward": 520, "material": "1.4301",
		"features": [
			{"type": "dia", "z0": 10.0, "z1": 50.0, "d": 36.0, "tol": 0.15},
			{"type": "dia", "z0": 50.0, "z1": 80.0, "d": 28.0, "tol": 0.15},
		],
	},
]


## Feste Aufträge und die generierten dahinter.
static func all() -> Array:
	if _all.is_empty():
		_all = LIST + JobGen.lathe(LIST.size() + 1)
	return _all


static func get_job(i: int) -> Dictionary:
	var list := all()
	return list[posmod(i, list.size())]


## Zielmaße als einzelne Zeilen.
static func target_lines(job: Dictionary) -> Array:
	var out := []
	if job.has("length"):
		out.append("Fertiglänge %d mm" % int(job["length"]))
	for f in job["features"]:
		match str(f.get("type", "dia")):
			"dia":
				out.append("Ø%.1f +/-%.2f  Länge %d  (Z %d-%d)" % [float(f["d"]), float(f.get("tol", 0.3)), int(float(f["z1"]) - float(f["z0"])), int(f["z0"]), int(f["z1"])])
			"chamfer":
				out.append("Fase %.1f x 45° an Z %d (Ø%d)" % [float(f["size"]), int(f["z"]), int(f["d"])])
			"point":
				out.append("Nutgrund Ø%.1f bei Z %d" % [float(f["d"]), int(f["z"])])
	if job.has("rz"):
		out.append("Oberfläche Rz <= %.1f µm" % float(job["rz"]))
	return out


## grind: Die geschliffene Fläche nennen (nur wenn die Werkstatt die Schleifmaschine hat).
static func describe(job: Dictionary, grind := false) -> String:
	var t := "%s\n" % job["title"]
	t += "\nWerkstoff: %s" % Materials.label(str(job.get("material", Materials.DEFAULT)))
	t += "\nRohteil: Ø%d x %d mm" % [int(job["stock_d"]), int(job["stock_len"])]
	if job.has("length"):
		t += "    Gesamtlänge: %d mm" % int(job["length"])
	for f in job["features"]:
		match str(f.get("type", "dia")):
			"dia":
				t += "\n  Z %3d - %3d (Länge %d) :  Ø%.1f  +/-%.2f" % [int(f["z0"]), int(f["z1"]), int(float(f["z1"]) - float(f["z0"])), float(f["d"]), float(f.get("tol", 0.3))]
			"chamfer":
				t += "\n  Fase %.1f x 45° an Z %d (Ø%d)" % [float(f["size"]), int(f["z"]), int(f["d"])]
			"point":
				t += "\n  Nutgrund Z %.0f :  Ø%.1f" % [float(f["z"]), float(f["d"])]
	if job.has("rz"):
		t += "\n  Oberfläche: Rz <= %.1f µm" % float(job["rz"])
	if grind and job.has("grind"):
		t += "\n  %s" % JobBoard.grind_line(job)
	t += "\nVergütung: bis %d EUR" % int(job["reward"])
	return t
