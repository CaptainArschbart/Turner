class_name Company
extends RefCounted
## Die Werkstatt als Betrieb: Kasse, Maschinenpark und Skilltree gehören allen, die in ihr arbeiten,
## und nicht einer Spielfigur. Mit mehreren Spielern teilen sich alle dieses eine Objekt.

## Maschinenarten, die Aufträge bekommen können. Ids wie in JobBoard.CATEGORIES.
const STARTING_MACHINES := []

var balance := 0
var machines: Array = STARTING_MACHINES.duplicate()
var skills := Skills.new()
var tools := {"lathe": ToolStore.new(), "cnc_lathe": ToolStore.new(), "mill": ToolStore.new(), "drill": ToolStore.new(),
	"flat_grinder": ToolStore.new(), "round_grinder": ToolStore.new()}
var reputation := 50.0            # Ansehen 0..100
var rep_log: Array = []           # je {"day", "change", "text"}


func owns(machine: String) -> bool:
	return machines.has(machine)


## Faktor auf die Vergütung: Im Mittelfeld normal, darüber bis 1,4 fach, darunter bis 0,6 fach.
func pay_factor() -> float:
	if reputation > 60.0:
		return 1.0 + (reputation - 60.0) / 100.0
	if reputation < 40.0:
		return 1.0 - (40.0 - reputation) / 100.0
	return 1.0


func reputation_title() -> String:
	if reputation >= 80.0:
		return "ausgezeichnet"
	if reputation >= 60.0:
		return "gut"
	if reputation >= 40.0:
		return "solide"
	if reputation >= 20.0:
		return "angeschlagen"
	return "schlecht"


## Ansehen ändern und vermerken.
func change_reputation(amount: float, day: int, text: String) -> void:
	reputation = clampf(reputation + amount, 0.0, 100.0)
	rep_log.append({"day": day, "change": amount, "text": text})
	if rep_log.size() > 30:
		rep_log.pop_front()


## Gibt es eine Maschine für diese Auftragsart? Drehaufträge gehen auch auf der CNC-Drehmaschine.
func owns_kind(kind: String) -> bool:
	if kind == "ceramic":
		return owns("flat_grinder") or owns("round_grinder")
	return owns(kind) or (kind == "lathe" and owns("cnc_lathe"))


func add_machine(machine: String) -> void:
	if not owns(machine):
		machines.append(machine)


## Stand aus einem Spielstand. Ohne Angabe stehen nur die Startmaschinen in der Werkstatt.
func load_state(money: int, saved_machines) -> void:
	balance = money
	machines = saved_machines.duplicate() if saved_machines is Array else STARTING_MACHINES.duplicate()
