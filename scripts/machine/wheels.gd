class_name Wheels
extends RefCounted
## Schleifscheiben der Flach- und Rundschleifmaschine: Korund, CBN und Diamant in verschiedenen Breiten.
## Korund nutzt sich schnell ab und wird unrund, dann muss sie am Abziehwerkzeug abgezogen werden. Das macht
## sie wieder gerade, kostet aber etwas Scheibe. CBN und Diamant halten viel länger. Keramik schneidet nur
## Diamant, Stahl dagegen ruiniert eine Diamantscheibe schnell.

const TYPES := {
	"korund": {"title": "Korundscheibe", "letter": "K", "skill": "", "price": 1.0, "wear": 1.0, "dull": 1.0, "finish": 1.0, "color": Color(0.72, 0.68, 0.6)},
	"cbn": {"title": "CBN-Scheibe", "letter": "C", "skill": "wheel_cbn", "price": 6.0, "wear": 0.15, "dull": 0.1, "finish": 0.8, "color": Color(0.32, 0.26, 0.2)},
	"diamant": {"title": "Diamantscheibe", "letter": "D", "skill": "wheel_diamond", "price": 10.0, "wear": 0.1, "dull": 0.1, "finish": 0.7, "color": Color(0.2, 0.22, 0.26)},
}
const WIDTHS := {"flat_grinder": [13.0, 25.0, 40.0], "round_grinder": [20.0, 30.0, 50.0]}
const DIAMETER := {"flat_grinder": 200.0, "round_grinder": 300.0}
const LIFE := 900.0               # Lebensdauer einer Korundscheibe in s Schleifzeit
const TRUE_TIME := 120.0          # so lange bleibt sie gerade
const DRESS_COST := 0.05          # Abziehen kostet diesen Anteil der Scheibe
const ON_STEEL := 8.0             # Diamant auf Stahl verschleißt so viel schneller
const HARD_HEAT := 1.4            # ab dieser Hitze-Kennzahl gilt ein Werkstoff als hart


## Alle Scheiben einer Maschine.
static func list(machine: String) -> Array:
	var out := []
	for type_id in TYPES:
		for w in WIDTHS[machine]:
			out.append(make(machine, type_id, w))
	return out


static func make(machine: String, type_id: String, width: float) -> Dictionary:
	var t: Dictionary = TYPES[type_id]
	var d: float = DIAMETER[machine]
	return {"id": "%s%d" % [t["letter"], int(width)], "name": "%s Ø%d x %d mm" % [t["title"], int(d), int(width)],
		"kind": "wheel", "type": type_id, "d": width, "wheel_d": d, "z": 1, "ap_max": 0.05, "fz_max": 3.0,
		"price": int(round((25.0 + width * 1.5) * float(t["price"])))}


static func by_id(machine: String, id: String) -> Dictionary:
	for w in list(machine):
		if w["id"] == id:
			return w
	return list(machine)[1]


## Faktor auf den Verschleiß einer Scheibe an diesem Werkstoff.
static func wear_factor(type_id: String, material: String, ceramic: bool) -> float:
	var f := float(TYPES[type_id]["wear"])
	if ceramic:
		return f
	if type_id == "diamant":
		return f * ON_STEEL
	if type_id == "korund" and float(Materials.group_of(material)["heat"]) >= HARD_HEAT:
		return f * 2.5
	return f


## Schneidet diese Scheibe den Werkstoff überhaupt? Keramik nur mit Diamant.
static func cuts(type_id: String, ceramic: bool) -> bool:
	return type_id == "diamant" or not ceramic


## Scheibe im Einsatz: nutzt sich ab und wird unrund. Gibt true zurück, wenn sie verbraucht ist.
static func use(store: ToolStore, id: String, type_id: String, material: String, ceramic: bool, delta: float) -> bool:
	if not store.has(id):
		return false
	var k := wear_factor(type_id, material, ceramic)
	store.add_dull(id, float(TYPES[type_id]["dull"]) * delta / TRUE_TIME)
	return store.add_wear(id, k * delta / LIFE) >= 1.0


## Abziehen: wieder gerade, kostet etwas Scheibe. Gibt true zurück, wenn sie damit verbraucht ist.
static func dress(store: ToolStore, id: String) -> bool:
	store.set_dull(id, 0.0)
	return store.add_wear(id, DRESS_COST) >= 1.0


## Faktor auf die Rautiefe durch Art und Zustand: Eine unrunde Scheibe schleift bis dreimal so rau.
static func finish(type_id: String, dull: float) -> float:
	return float(TYPES[type_id]["finish"]) * (1.0 + clampf(dull, 0.0, 1.0) * 2.0)
