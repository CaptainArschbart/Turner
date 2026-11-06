class_name Materials
extends RefCounted
## Werkstoffe und Schnittdaten nach den PDFs in "Schnittdaten".
##
## Aus den Tabellen übernommen:
## - Werkstoffe, Werkstoff-Nr. und Fräsgruppen A-F (Schnittdaten.pdf S. 5)
## - Schaftfräser HSSE unbeschichtet: vc und fz je Gruppe (S. 6, Schruppfräser 4 Z)
## - Messerkopf: vc und fz von VHM-HSC Schruppfräser (S. 8), die PDFs nennen keine Messerköpfe
## - Spiralbohrer HSS TiN: vc und Vorschub je Kategorie (S. 13, Bohrer Ø9,5-12,95)
## - Hartmetall-vc je Werkstoff (S. 1), daraus das Verhältnis zu S235 fürs Drehen
## - Dichte, Spanform, Wärme- und Verschleißverhalten (Werkstoffübersicht)
##
## Keine Tabellenwerte, sondern für das Spiel festgelegt: Preise (price), die Faktoren ap und heat
## (aus den Beschreibungen der Werkstoffübersicht abgeleitet), Dichte von Kupfer, Bronze, Titan, Guss.
## Fürs Drehen enthalten die PDFs keine Tabelle: 120-320 m/min für S235 (bisheriger Spielwert) mal
## dem Verhältnis oben.

const DEFAULT := "S235"
const KERF := 3.0                # Schnittbreite der Säge (mm)
const BAR_LENGTHS := [1000.0, 2000.0]   # Stangenmaterial gibt es 1 m oder 2 m lang
const BAR_LEN := 2000.0          # voreingestellt
const ROUND_SURCHARGE := 1.15    # Rundstangen kosten je kg mehr als Vierkant, sonst wären sie bei gleichem Maß viel billiger
const CUT_SURCHARGE := 1.6       # Fertigschnitt kostet mehr je kg
const CUT_FEE := 8.0             # und einen festen Betrag je Stück
const WEAR_LIFE := 1800.0        # Standzeit einer Schneide in s bei optimalen Werten in Baustahl

## Stange oder Fertigschnitt
const KIND_ROUND := "round"
const KIND_SQUARE := "square"
const KIND_CUT := "cut"
const KIND_TITLES := {"round": "Rundmaterial", "square": "Vierkantmaterial", "cut": "Fertigschnitt"}

## Schaftfräser HSSE unbeschichtet (S. 6): vc von-bis
const MILL_VC := {"A": [25.0, 30.0], "B": [20.0, 25.0], "C": [10.0, 16.0], "D": [3.0, 12.0], "E": [40.0, 70.0], "F": [200.0, 300.0]}
## fz je Fräser-Ø 6, 8, 10, 12, 16 (S. 6, Schruppfräser 4 Z)
const MILL_FZ_D := [6.0, 8.0, 10.0, 12.0, 16.0]
const MILL_FZ := {
	"A": [0.006, 0.009, 0.015, 0.019, 0.027], "B": [0.005, 0.008, 0.013, 0.018, 0.024],
	"C": [0.006, 0.009, 0.014, 0.019, 0.024], "D": [0.006, 0.010, 0.015, 0.019, 0.027],
	"E": [0.013, 0.023, 0.034, 0.038, 0.045], "F": [0.007, 0.014, 0.019, 0.028, 0.037],
}
## Messerkopf (S. 8, Schruppfräser): vc und fz bei Ø20
const FACE_VC := {"A": 170.0, "B": 130.0, "C": 120.0, "D": 76.0, "E": 65.0, "F": 300.0}
const FACE_FZ := {"A": 0.11, "B": 0.11, "C": 0.07, "D": 0.07, "E": 0.07, "F": 0.15}
## Bezugswerte, mit denen die Werkzeuge in mill_tools.gd für S235 ausgelegt sind
const REF_VC := Vector2(120.0, 320.0)
const REF_HM := 115.0
const REF_DRILL_F := 0.15

## raw/cut = Oberfläche roh und bearbeitet. mill = Fräsgruppe A-F, einzelne Werkstoffe können abweichen.
## hm = Hartmetall-vc von-bis (S. 1), turn = Drehfaktor für Gruppen ohne Hartmetallwert.
## drill_vc, drill_f: S. 13. dens: g/cm³. price: EUR/kg. chip: Spanlänge. dry_ok: Kühlung nicht nötig.
## stick: klebt an der Schneide. harden: verfestigt sich. finish: Faktor auf die Rautiefe.
const GROUPS := [
	{"id": "baustahl", "title": "Baustahl", "iso": "P", "mill": "A", "img": "stahl",
		"raw": [0.25, 0.27, 0.30], "cut": [0.80, 0.82, 0.85], "dens": 7.85, "price": 1.2,
		"drill_vc": 43.0, "drill_f": 0.15, "ap": 1.0, "heat": 1.0, "chip": 1.0, "finish": 1.0,
		"text": "Zerspanbarkeit gut bis mittel, Spanbildung meist gut kontrollierbar. Mit Kühlung arbeiten.",
		"list": [
			{"id": "S235", "name": "S235 (St 37)", "nr": "1.0037", "hm": [100.0, 130.0]},
			{"id": "St42", "name": "St 42", "nr": "1.0042", "hm": [100.0, 130.0]},
			{"id": "E295", "name": "E295 (St 50-2)", "nr": "1.0050", "hm": [90.0, 120.0]},
			{"id": "S355", "name": "S355 (St 52)", "nr": "-", "hm": [90.0, 120.0]},
			{"id": "E335", "name": "E335 (St 60-2)", "nr": "1.0060", "hm": [90.0, 120.0]},
		]},
	{"id": "automatenstahl", "title": "Automatenstahl", "iso": "P", "mill": "A", "img": "stahl",
		"raw": [0.46, 0.48, 0.51], "cut": [0.82, 0.84, 0.86], "dens": 7.85, "price": 1.4,
		"drill_vc": 61.0, "drill_f": 0.18, "ap": 1.1, "heat": 0.9, "chip": 0.6, "finish": 0.9,
		"text": "Sehr gut zerspanbar, kurze Späne und gute Oberflächen.",
		"list": [
			{"id": "9S20", "name": "9S20", "nr": "1.0711", "hm": [100.0, 160.0]},
			{"id": "9SMnPb28", "name": "9SMnPb28", "nr": "1.0718", "hm": [100.0, 160.0]},
			{"id": "9SMnPb36", "name": "9SMnPb36", "nr": "1.0737", "hm": [100.0, 160.0]},
			{"id": "35S20", "name": "35S20", "nr": "1.0726", "hm": [100.0, 160.0]},
			{"id": "45S20", "name": "45S20", "nr": "1.0727", "hm": [100.0, 160.0]},
		]},
	{"id": "einsatzstahl", "title": "Einsatzstahl", "iso": "P", "mill": "A", "img": "stahl",
		"raw": [0.28, 0.29, 0.32], "cut": [0.80, 0.81, 0.83], "dens": 7.85, "price": 1.6,
		"drill_vc": 49.0, "drill_f": 0.15, "ap": 0.9, "heat": 1.1, "chip": 1.2, "finish": 1.0,
		"text": "Weich und zäh. Die legierten Sorten brauchen weniger vc als Baustahl.",
		"list": [
			{"id": "C10", "name": "C10", "nr": "1.0301", "hm": [110.0, 140.0]},
			{"id": "C15", "name": "C15", "nr": "1.0401", "hm": [110.0, 140.0]},
			{"id": "16MnCr5", "name": "16MnCr5", "nr": "1.7131", "mill": "B", "hm": [80.0, 100.0]},
			{"id": "20CrMo5", "name": "20CrMo5", "nr": "1.7264", "mill": "B", "hm": [80.0, 100.0]},
			{"id": "21NiCrMo2", "name": "21NiCrMo2", "nr": "1.6523", "mill": "B", "hm": [70.0, 90.0]},
		]},
	{"id": "verguetungsstahl", "title": "Vergütungsstahl", "iso": "P", "mill": "A", "img": "stahl",
		"raw": [0.30, 0.31, 0.33], "cut": [0.78, 0.79, 0.81], "dens": 7.85, "price": 1.8,
		"drill_vc": 46.0, "drill_f": 0.13, "ap": 0.85, "heat": 1.2, "chip": 1.0, "finish": 1.0,
		"text": "Fester als Baustahl, Schnittkräfte und Verschleiß steigen mit der Härte.",
		"list": [
			{"id": "C35", "name": "C35", "nr": "1.0501", "hm": [90.0, 120.0]},
			{"id": "C45", "name": "C45", "nr": "1.0503", "hm": [90.0, 120.0]},
			{"id": "C60", "name": "C60", "nr": "1.0601", "hm": [90.0, 120.0]},
			{"id": "42CrMo4", "name": "42CrMo4", "nr": "1.7225", "mill": "B", "hm": [70.0, 90.0]},
			{"id": "34CrNiMo6", "name": "34CrNiMo6", "nr": "1.6582", "mill": "C", "hm": [70.0, 90.0]},
		]},
	{"id": "werkzeugstahl", "title": "Werkzeugstahl", "iso": "P", "mill": "B", "img": "stahl",
		"raw": [0.36, 0.37, 0.39], "cut": [0.76, 0.77, 0.79], "dens": 7.85, "price": 5.0,
		"drill_vc": 24.0, "drill_f": 0.10, "ap": 0.6, "heat": 1.4, "chip": 0.9, "finish": 1.0,
		"text": "Hart und verschleißend. Kleine Zustellung und niedrige Schnittgeschwindigkeit.",
		"list": [
			{"id": "C45W", "name": "C45W", "nr": "1.1730", "mill": "A", "hm": [90.0, 120.0]},
			{"id": "90MnCrV8", "name": "90MnCrV8", "nr": "1.2842", "hm": [45.0, 55.0]},
			{"id": "X40CrMoV5-1", "name": "X40CrMoV5-1", "nr": "1.2344", "hm": [30.0, 45.0]},
			{"id": "X155CrVMo12-1", "name": "X155CrVMo12-1", "nr": "1.2379", "mill": "C", "hm": [40.0, 50.0]},
			{"id": "X210Cr12", "name": "X210Cr12", "nr": "1.2080", "mill": "C", "hm": [40.0, 50.0]},
		]},
	{"id": "edelstahl", "title": "Edelstahl", "iso": "M", "mill": "C", "img": "edelstahl",
		"raw": [0.60, 0.61, 0.62], "cut": [0.86, 0.86, 0.85], "dens": 7.9, "price": 4.5,
		"drill_vc": 23.0, "drill_f": 0.08, "ap": 0.7, "heat": 1.7, "chip": 2.0, "finish": 1.1, "harden": true,
		"text": "Mittel bis schwierig. Leitet Wärme schlecht, verfestigt bei zu kleinem Vorschub, lange zähe Späne.",
		"list": [
			{"id": "1.4301", "name": "X5CrNi18-10", "nr": "1.4301", "hm": [40.0, 50.0]},
			{"id": "1.4404", "name": "X2CrNiMo17-12-2", "nr": "1.4404", "hm": [40.0, 50.0]},
			{"id": "1.4541", "name": "X6CrNiTi18-10", "nr": "1.4541", "hm": [40.0, 50.0]},
			{"id": "1.4571", "name": "X6CrNiMoTi17-12-2", "nr": "1.4571", "hm": [40.0, 50.0]},
			{"id": "1.4021", "name": "X20Cr13", "nr": "1.4021", "mill": "B", "hm": [40.0, 50.0]},
		]},
	{"id": "gusseisen", "title": "Gusseisen", "iso": "K", "mill": "A", "img": "stahl",
		"raw": [0.20, 0.20, 0.21], "cut": [0.55, 0.55, 0.56], "dens": 7.2, "price": 1.5,
		"drill_vc": 46.0, "drill_f": 0.15, "ap": 0.9, "heat": 1.0, "chip": 0.3, "finish": 1.2, "dry_ok": true,
		"text": "Kurzer, bröckeliger Span. Wird meist trocken bearbeitet.",
		"list": [
			{"id": "GG20", "name": "Gg 20", "nr": "-", "hm": [60.0, 80.0]},
			{"id": "GG25", "name": "Gg 25", "nr": "-", "hm": [60.0, 80.0]},
			{"id": "GG30", "name": "Gg 30", "nr": "-", "mill": "B", "hm": [60.0, 80.0]},
			{"id": "GG40", "name": "Gg 40", "nr": "-", "mill": "B", "hm": [55.0, 75.0]},
		]},
	{"id": "aluminium", "title": "Aluminium", "iso": "N", "mill": "F", "img": "aluminium",
		"raw": [0.74, 0.75, 0.75], "cut": [0.90, 0.91, 0.92], "dens": 2.7, "price": 4.0, "turn": 9.0,
		"drill_vc": 183.0, "drill_f": 0.20, "ap": 1.2, "heat": 0.5, "chip": 1.6, "finish": 0.8, "stick": true,
		"text": "Gut bis sehr gut. Geringe Schnittkräfte, aber weiche Sorten kleben ohne Kühlung an der Schneide.",
		"list": [
			{"id": "AW-6060", "name": "EN AW-6060", "nr": "-"},
			{"id": "AW-6061", "name": "EN AW-6061", "nr": "-"},
			{"id": "AW-6082", "name": "EN AW-6082", "nr": "-"},
			{"id": "AW-7075", "name": "EN AW-7075", "nr": "-"},
			{"id": "AlMg3", "name": "AlMg3", "nr": "3.3535"},
			{"id": "AlMg4.5Mn", "name": "AlMg4,5Mn", "nr": "3.3547"},
			{"id": "Al99.8", "name": "Al 99,8", "nr": "3.0285"},
		]},
	{"id": "messing", "title": "Messing", "iso": "N", "mill": "E", "img": "messing",
		"raw": [0.62, 0.50, 0.24], "cut": [0.90, 0.75, 0.38], "dens": 8.45, "price": 7.0, "turn": 2.0,
		"drill_vc": 91.0, "drill_f": 0.18, "ap": 1.2, "heat": 0.6, "chip": 0.4, "finish": 0.75, "dry_ok": true,
		"text": "Sehr gut. Kurze, gut brechende Späne, geringe Schnittkräfte, gute Oberflächen, auch trocken.",
		"list": [
			{"id": "CuZn37", "name": "CuZn37", "nr": "-"},
			{"id": "CuZn39Pb3", "name": "CuZn39Pb3", "nr": "-"},
			{"id": "CuZn40", "name": "CuZn40", "nr": "2.0360"},
			{"id": "CuZn40Pb2", "name": "CuZn40Pb2", "nr": "2.0402"},
		]},
	{"id": "kupfer", "title": "Kupfer", "iso": "N", "mill": "E", "img": "messing",
		"raw": [0.60, 0.33, 0.20], "cut": [0.88, 0.52, 0.36], "dens": 8.9, "price": 9.0, "turn": 1.5,
		"drill_vc": 40.0, "drill_f": 0.05, "ap": 1.0, "heat": 0.6, "chip": 1.6, "finish": 1.0, "stick": true,
		"text": "Weich und zäh, schmiert ohne Kühlung. Bohren nur mit kleinem Vorschub.",
		"list": [
			{"id": "E-Cu", "name": "KE-Cu", "nr": "2.0050"},
			{"id": "CuSi2Mn", "name": "CuSi2Mn", "nr": "-"},
		]},
	{"id": "bronze", "title": "Bronze", "iso": "N", "mill": "E", "img": "messing",
		"raw": [0.52, 0.38, 0.20], "cut": [0.78, 0.60, 0.35], "dens": 8.8, "price": 11.0, "turn": 1.5,
		"drill_vc": 52.0, "drill_f": 0.15, "ap": 0.9, "heat": 0.8, "chip": 0.7, "finish": 0.9,
		"text": "Zinnbronze gut zerspanbar, Aluminiumbronze deutlich zäher.",
		"list": [
			{"id": "CuSn6", "name": "CuSn6", "nr": "2.1020"},
			{"id": "CuSn8", "name": "CuSn8", "nr": "2.1030"},
			{"id": "CuAl8", "name": "CuAl8", "nr": "2.0920"},
			{"id": "CuAl10Fe", "name": "CuAl10Fe", "nr": "2.0940"},
		]},
	{"id": "titan", "title": "Titan", "iso": "S", "mill": "D", "img": "edelstahl",
		"raw": [0.42, 0.42, 0.44], "cut": [0.70, 0.70, 0.70], "dens": 4.5, "price": 28.0, "turn": 0.27,
		"drill_vc": 11.0, "drill_f": 0.08, "ap": 0.5, "heat": 2.2, "chip": 1.4, "finish": 1.2,
		"text": "Schwer zerspanbar. Sehr wenig Schnittgeschwindigkeit, viel Hitze an der Schneide.",
		"list": [
			{"id": "Ti1", "name": "Ti 1", "nr": "3.7025"},
			{"id": "TiAl6V4", "name": "TiAl6V4", "nr": "3.7164"},
		]},
]

## Vorhandene Fotos. Ohne eigenes Foto wird Aluminium in der Werkstofffarbe eingefärbt.
const PHOTOS := {
	"round": ["stahl", "edelstahl", "messing", "aluminium"],
	"square": ["stahl", "edelstahl", "aluminium"],
	"cut": ["stahl", "edelstahl", "aluminium"],
}
const PHOTO_PREFIX := {"round": "rund", "square": "vierkant", "cut": "platte"}
## Diese Fotos tragen unten eine Werkstoffnummer, die nicht zu jeder Sorte passt
const PHOTO_CROP := {"rund_edelstahl": 0.82, "vierkant_edelstahl": 0.82}

static var _index: Dictionary = {}
## Faktor des Kühlmittels auf die Erwärmung. Besseres Kühlmittel aus dem Skilltree senkt ihn.
static var coolant_factor := 0.4


static func _build_index() -> void:
	if not _index.is_empty():
		return
	for g in GROUPS:
		for m in g["list"]:
			_index[str(m["id"])] = {"m": m, "g": g}


static func exists(id: String) -> bool:
	_build_index()
	return _index.has(id)


static func get_material(id: String) -> Dictionary:
	_build_index()
	return _index.get(id, _index[DEFAULT])["m"]


static func group_of(id: String) -> Dictionary:
	_build_index()
	return _index.get(id, _index[DEFAULT])["g"]


## Anzeigename mit Werkstoff-Nr.
static func label(id: String) -> String:
	var m := get_material(id)
	return str(m["name"]) if str(m["nr"]) == "-" else "%s  (%s)" % [m["name"], m["nr"]]


static func raw_color(id: String) -> Color:
	var c: Array = group_of(id)["raw"]
	return Color(c[0], c[1], c[2])


static func cut_color(id: String) -> Color:
	var c: Array = group_of(id)["cut"]
	return Color(c[0], c[1], c[2])


static func mill_group(id: String) -> String:
	return str(get_material(id).get("mill", group_of(id)["mill"]))


## Kosten eines Stücks in EUR, Maße in mm.
static func price(id: String, kind: String, d: float, w: float, h: float, length: float) -> int:
	var g := group_of(id)
	var eur := weight_kg(id, kind, d, w, h, length) * float(g["price"])
	if kind == KIND_ROUND:
		eur *= ROUND_SURCHARGE
	elif kind == KIND_CUT:
		eur = eur * CUT_SURCHARGE + CUT_FEE
	return maxi(int(ceil(eur)), 1)


## Abschnitt von der Stange absägen: Die Stange wird um Abschnitt und Schnittbreite kürzer.
static func cut_off(bar: Dictionary, length: float) -> Dictionary:
	var piece := bar.duplicate()
	piece.erase("slot")
	piece["l"] = length
	piece["sawn"] = true
	bar["l"] = float(bar["l"]) - length - KERF
	return piece


static func weight_kg(id: String, kind: String, d: float, w: float, h: float, length: float) -> float:
	var area := PI * d * d * 0.25 if kind == KIND_ROUND else w * h
	return area * length * 0.000001 * float(group_of(id)["dens"])


# ======================================================================= Schnittdaten

## Fräsmaschine: Sollwerte für Werkzeug tool in Werkstoff id. vc_top = vc bei höchster Drehzahl.
## Ist die Maschine zu langsam, wird das untere Ende auf das Erreichbare gesenkt, damit das Werkzeug
## nicht als falsch eingestellt gilt, wenn es nicht schneller geht.
static func mill_data(id: String, tool: Dictionary, vc_top: float) -> Dictionary:
	var g := group_of(id)
	var mg := mill_group(id)
	var kind := str(tool["kind"])
	var vmin := 0.0
	var vmax := 0.0
	var fz_rec := 0.0
	var ratio := 1.0
	if kind == "drill":
		vmin = float(g["drill_vc"]) * 0.7
		vmax = float(g["drill_vc"]) * 1.2
		# Die Tabelle gilt für Ø9,5-12,95: Der Vorschub wächst mit dem Bohrerdurchmesser
		ratio = float(g["drill_f"]) / REF_DRILL_F
		fz_rec = float(g["drill_f"]) * float(tool["d"]) / 10.0
	elif kind == "face_mill":
		vmin = float(FACE_VC[mg]) * 0.7
		vmax = float(FACE_VC[mg]) * 1.15
		ratio = float(FACE_FZ[mg]) / float(FACE_FZ["A"])
		fz_rec = float(tool["fz_max"]) * ratio * 0.5
	else:
		vmin = float(MILL_VC[mg][0])
		vmax = float(MILL_VC[mg][1])
		fz_rec = _fz_table(mg, float(tool["d"]))
		ratio = fz_rec / _fz_table("A", float(tool["d"]))
	return {
		"vmin": minf(vmin, vc_top * 0.7), "vmax": vmax, "fz_rec": fz_rec,
		"fz_max": float(tool["fz_max"]) * ratio, "ap_max": float(tool["ap_max"]) * float(g["ap"]),
	}


static func _fz_table(mg: String, d: float) -> float:
	var row: Array = MILL_FZ[mg]
	if d <= float(MILL_FZ_D[0]):
		return float(row[0])
	for i in range(1, MILL_FZ_D.size()):
		if d <= float(MILL_FZ_D[i]):
			var k := (d - float(MILL_FZ_D[i - 1])) / (float(MILL_FZ_D[i]) - float(MILL_FZ_D[i - 1]))
			return lerpf(float(row[i - 1]), float(row[i]), k)
	return float(row[row.size() - 1])


## Drehen: Faktor gegenüber S235.
static func turn_factor(id: String) -> float:
	var m := get_material(id)
	if m.has("hm"):
		return (float(m["hm"][0]) + float(m["hm"][1])) * 0.5 / REF_HM
	return float(group_of(id).get("turn", 1.0))


## Drehen: vc-Fenster an einer Stelle, an der die Maschine höchstens vc_top erreicht.
static func turn_window(id: String, vc_top: float) -> Vector2:
	var f := turn_factor(id)
	return Vector2(minf(REF_VC.x * f, vc_top * 0.7), REF_VC.y * f)


## Parameter für Lathe.surface_rz
static func turn_params(id: String, vc_top: float) -> Dictionary:
	var g := group_of(id)
	var win := turn_window(id, vc_top)
	return {"vlow": win.x, "vhigh": win.y, "dry_ok": g.get("dry_ok", false), "stick": g.get("stick", false),
		"finish": float(g.get("finish", 1.0))}


## Verschleiß je Sekunde im Schnitt, 1 = Werkzeug hin. Mit optimalen Werten hält eine Schneide in Baustahl
## 30 Minuten Schnittzeit. vc außerhalb des Fensters, zu viel Vorschub (feed_ratio = Vorschub / Richtwert)
## und fehlende Kühlung lassen sie schneller verschleißen, harte Werkstoffe ebenso.
static func wear_rate(id: String, vc: float, vlow: float, vhigh: float, feed_ratio: float, kss: bool) -> float:
	var g := group_of(id)
	var k := 1.0
	if vc > vhigh:
		k += (vc / maxf(vhigh, 0.1) - 1.0) * 4.0
	elif vc < vlow and vc > 0.0:
		k += minf((vlow / vc - 1.0) * 1.5, 3.0)
	if feed_ratio > 1.2:
		k += (feed_ratio - 1.2) * 2.0
	if not kss and not g.get("dry_ok", false):
		k += 1.0
	return k * float(g["heat"]) / WEAR_LIFE


## Erwärmung der Schneide je Sekunde im Schnitt. over = vc / vmax, scale = Warmhärte des Schneidstoffs.
static func heat_rate(id: String, over: float, kss: bool, scale: float) -> float:
	if over <= 1.0:
		return 0.0
	return (over - 1.0) * 0.5 * float(group_of(id)["heat"]) * (coolant_factor if kss else 1.0) * scale


# ======================================================================= Fotos

## {"path", "tint", "crop"} für das Vorschaubild. crop = sichtbarer Anteil der Bildhöhe.
static func photo(id: String, kind: String) -> Dictionary:
	var g := group_of(id)
	var stem := str(g["img"])
	var tint := Color.WHITE
	# Kein eigenes Foto für diese Form oder Gruppe: Aluminium in der Werkstofffarbe
	if not (PHOTOS[kind] as Array).has(stem) or stem == "messing" and str(g["id"]) != "messing":
		if kind == KIND_ROUND and stem == "messing":
			tint = cut_color(id).lerp(Color.WHITE, 0.15) * Color(1.0, 0.95, 1.0)
		else:
			stem = "aluminium"
			tint = cut_color(id)
	elif str(g["id"]) == "titan":
		tint = Color(0.78, 0.78, 0.8)
	elif str(g["id"]) == "gusseisen":
		tint = Color(0.72, 0.72, 0.72)
	var file := "%s_%s" % [PHOTO_PREFIX[kind], stem]
	return {"path": "res://assets/rohmaterial/%s.jpg" % file, "tint": tint, "crop": float(PHOTO_CROP.get(file, 1.0))}
