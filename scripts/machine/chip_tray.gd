class_name ChipTray
extends RefCounted
## Späne, nach Werkstoffgruppe getrennt gezählt, damit der Recyclingwert stimmt. Dieselbe Klasse dient
## für die Spänewanne der Maschine, den Spänebehälter und den Container. Gemischt wird nicht: Nur
## verschiedene Stahlarten dürfen zusammen liegen, sonst gilt je Spänesorte ein eigener Behälter.

const CAPACITY := 15.0            # kg in der Spänewanne
const RATE := 0.05                # kg je Sekunde im Schnitt, die Wanne ist nach 5 Minuten Schnitt voll
const RECYCLE := 0.8              # Anteil des Materialpreises je kg
## Spänesorte je Werkstoffgruppe. Für jede Sorte steht ein Container im Hof. Kupfer und Bronze gehen zum
## Messing (Kupferlegierungen), Guss und Titan zum Stahl.
const SORTS := {
	"baustahl": "stahl", "automatenstahl": "stahl", "einsatzstahl": "stahl", "verguetungsstahl": "stahl",
	"werkzeugstahl": "stahl", "edelstahl": "stahl", "gusseisen": "stahl", "titan": "stahl",
	"aluminium": "aluminium", "messing": "messing", "kupfer": "messing", "bronze": "messing",
}
const SORT_TITLES := {"stahl": "Stahl", "aluminium": "Aluminium", "messing": "Messing"}

var capacity := CAPACITY
var only := ""                    # Container: nimmt nur diese Sorte
var kg := 0.0
var by: Dictionary = {}           # Gruppen-id -> kg


func _init(cap := CAPACITY, only_sort := "") -> void:
	capacity = cap
	only = only_sort


## Spänesorte des Inhalts, leer = leer.
func sort() -> String:
	if is_empty():
		return ""
	for g in by:
		if float(by[g]) > 0.0:
			return str(SORTS.get(g, "stahl"))
	return ""


## Dürfen Späne dieser Sorte hierher?
func takes(sort_id: String) -> bool:
	return (only == "" or only == sort_id) and (is_empty() or sort() == sort_id)


func is_full() -> bool:
	return kg >= capacity - 0.001


func is_empty() -> bool:
	return kg <= 0.001


func fraction() -> float:
	return clampf(kg / maxf(capacity, 0.001), 0.0, 1.0)


## Späne einer Gruppe dazu. Gibt zurück, was hineingepasst hat.
func add(group: String, amount: float) -> float:
	if not takes(str(SORTS.get(group, "stahl"))):
		return 0.0
	var fit := minf(amount, maxf(capacity - kg, 0.0))
	if fit <= 0.0:
		return 0.0
	by[group] = float(by.get(group, 0.0)) + fit
	kg += fit
	return fit


## So viel wie möglich aus other herausnehmen. Andere Sorten bleiben, wo sie sind.
func take_from(other: ChipTray) -> float:
	if other.is_empty() or not takes(other.sort()):
		return 0.0
	var room := maxf(capacity - kg, 0.0)
	var part := minf(room, other.kg)
	if part <= 0.0:
		return 0.0
	var share := part / other.kg
	for g in other.by.keys():
		var move: float = float(other.by[g]) * share
		by[g] = float(by.get(g, 0.0)) + move
		other.by[g] = float(other.by[g]) - move
		if float(other.by[g]) <= 0.0001:
			other.by.erase(g)
	kg += part
	other.kg = maxf(other.kg - part, 0.0)
	if other.kg <= 0.0001:
		other.clear()
	return part


func clear() -> void:
	kg = 0.0
	by.clear()


## Wert beim Recycling in EUR.
func value(factor := 1.0) -> int:
	var eur := 0.0
	for g in by:
		eur += float(by[g]) * _group_price(str(g)) * RECYCLE
	return int(round(eur * factor))


static func _group_price(id: String) -> float:
	for g in Materials.GROUPS:
		if str(g["id"]) == id:
			return float(g["price"])
	return 1.0


func to_state() -> Dictionary:
	return {"kg": kg, "by": by.duplicate()}


func load_state(d) -> void:
	clear()
	if not d is Dictionary:
		return
	kg = float(d.get("kg", 0.0))
	var b = d.get("by", {})
	if b is Dictionary:
		for g in b:
			by[str(g)] = float(b[g])
