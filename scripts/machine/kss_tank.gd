class_name KssTank
extends RefCounted
## Kühlschmierstoff-Tank einer CNC-Maschine („Der Chemiemeister“): Wasser und Konzentrat werden
## nachgefüllt, bei vollem Tank wird die Mischung bewertet. Der Zustand gilt bis zur nächsten vollen
## Befüllung. Reine Logik ohne Szenenbezug, damit Tests und Panel ihn direkt benutzen können.

signal changed                            # Füllstand oder Konzentration geändert (UI-Update)
signal evaluated(state: int)              # bei Erreichen von 100 % Füllstand
signal concentrate_added(liters: float)   # für die Kosten

enum State { NEUTRAL, OPTIMAL, ZU_DUENN, ZU_DICK }

const CAPACITY := 60.0              # Liter
const TARGET_MIN := 6.0             # Prozent Konzentrat
const TARGET_MAX := 7.0
const THIN_BELOW := 5.0
const THICK_ABOVE := 8.0
const TARGET_MID := 6.5             # Sollwert für die Schaum-Strafe und den Startwert
const START_FILL := 0.7             # Startfüllung 70 %
const CONSUME_PER_MIN := 0.4        # Liter pro Minute bei laufendem Kühlmittel und drehender Spindel
const PRICE_PER_L := 4.0            # EUR pro Liter Konzentrat, Wasser ist gratis
const PENALTY_FACTOR := 2.0         # Schaum-Strafe: Überdosis × Preis × 2
const EMPTY_BELOW := 0.05           # darunter gilt der Tank als leer

var water := 0.0                    # Liter Wasser im Tank
var concentrate := 0.0              # Liter Konzentrat im Tank
var state: State = State.NEUTRAL
var added_since_eval := 0.0      # Konzentrat, das seit der letzten Bewertung zugegeben wurde
var last_fill_added := 0.0       # davon in der zuletzt bewerteten Befüllung (Basis der Schaum-Strafe)

## Optional, vom Besitzer gesetzt: Callable(liters: float) -> float, liefert die höchstens
## bezahlbare Konzentratmenge (Liter). So kappt die Welt den Zufluss, wenn das Geld fehlt.
var afford: Callable = Callable()


func _init() -> void:
	reset_default()


## Startzustand: 70 % gefüllt mit 6,5 % Konzentrat, NEUTRAL.
func reset_default() -> void:
	var total := CAPACITY * START_FILL
	concentrate = total * TARGET_MID / 100.0
	water = total - concentrate
	added_since_eval = 0.0
	last_fill_added = 0.0
	state = State.NEUTRAL
	changed.emit()


func volume() -> float:
	return water + concentrate


## Konzentrat in Prozent vom Gesamtvolumen, 0 bei leerem Tank.
func concentration() -> float:
	var v := volume()
	return concentrate / v * 100.0 if v > 0.0001 else 0.0


func fill_fraction() -> float:
	return clampf(volume() / CAPACITY, 0.0, 1.0)


func is_full() -> bool:
	return volume() >= CAPACITY - 0.0001


func is_empty() -> bool:
	return volume() < EMPTY_BELOW


func add_water(liters: float) -> float:
	var l := clampf(liters, 0.0, CAPACITY - volume())
	if l <= 0.0:
		return 0.0
	var was_full := is_full()
	water += l
	_after_fill(was_full)
	return l


func add_concentrate(liters: float) -> float:
	var l := clampf(liters, 0.0, CAPACITY - volume())
	if l > 0.0 and afford.is_valid():
		l = clampf(l, 0.0, float(afford.call(l)))
	if l <= 0.0:
		return 0.0
	var was_full := is_full()
	concentrate += l
	added_since_eval += l
	concentrate_added.emit(l)
	_after_fill(was_full)
	return l


## Verbrauch: Wasser und Konzentrat im Verhältnis der Mischung. Der Zustand bleibt.
func consume(liters: float) -> void:
	var v := volume()
	if liters <= 0.0 or v <= 0.0:
		return
	var l := minf(liters, v)
	var k := l / v
	water = maxf(water - water * k, 0.0)
	concentrate = maxf(concentrate - concentrate * k, 0.0)
	if volume() < 0.0001:
		water = 0.0
		concentrate = 0.0
	changed.emit()


func _after_fill(was_full: bool) -> void:
	changed.emit()
	if is_full() and not was_full:
		evaluate()


## Bewertung bei vollem Tank. Zwischen den Grenzen NEUTRAL („im Rahmen“, ohne Effekt).
func evaluate() -> State:
	last_fill_added = added_since_eval
	added_since_eval = 0.0
	var c := concentration()
	# Ein Hauch Toleranz gegen Gleitkommafehler an den Grenzen (6,0 / 7,0 %)
	if c >= TARGET_MIN - 0.0005 and c <= TARGET_MAX + 0.0005:
		state = State.OPTIMAL
	elif c < THIN_BELOW - 0.0005:
		state = State.ZU_DUENN
	elif c > THICK_ABOVE + 0.0005:
		state = State.ZU_DICK
	else:
		state = State.NEUTRAL
	evaluated.emit(int(state))
	changed.emit()
	return state


static func state_title(s: State) -> String:
	match s:
		State.OPTIMAL:
			return "OPTIMAL"
		State.ZU_DUENN:
			return "ZU DÜNN"
		State.ZU_DICK:
			return "ZU DICK"
	return "IM RAHMEN"


func wear_factor() -> float:
	return 2.0 if state == State.ZU_DUENN else 1.0


func speed_factor() -> float:
	return 1.10 if state == State.OPTIMAL else 1.0


func foaming() -> bool:
	return state == State.ZU_DICK


## Konzentrat über dem Sollwert (6,5 % vom Tankinhalt) in Litern.
func overdose_liters() -> float:
	return maxf(concentrate - volume() * TARGET_MID / 100.0, 0.0)


## Einmalige Strafe bei ZU_DICK: nur die in DIESER Befüllung neu zugegebene Überdosis (höchstens das
## zugegebene Konzentrat, das über dem Sollwert liegt) × Preis × 2 (EUR, unabgerundet). Wer nur
## Wasser nachfüllt, zahlt nichts; der Schaum-Zustand bleibt trotzdem, solange es zu dick ist.
func foam_penalty() -> float:
	return minf(last_fill_added, overdose_liters()) * PRICE_PER_L * PENALTY_FACTOR


## Kurzzeile für HUD und Pult, z. B. "Tank 70 % | 6,5 % | IM RAHMEN".
func status_text() -> String:
	return "Tank %d %% | %s %% | %s" % [int(round(fill_fraction() * 100.0)), ("%.1f" % concentration()).replace(".", ","), state_title(state)]


func to_state() -> Dictionary:
	return {"water": water, "concentrate": concentrate, "state": int(state), "added": added_since_eval, "last_added": last_fill_added}


func load_state(d: Dictionary) -> void:
	water = clampf(float(d.get("water", water)), 0.0, CAPACITY)
	concentrate = clampf(float(d.get("concentrate", concentrate)), 0.0, CAPACITY - water)
	state = clampi(int(d.get("state", int(state))), 0, 3) as State
	added_since_eval = maxf(float(d.get("added", 0.0)), 0.0)
	last_fill_added = maxf(float(d.get("last_added", 0.0)), 0.0)
	changed.emit()
