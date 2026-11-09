class_name Layout
extends RefCounted
## Stellplan der Werkstatt: wo Maschinen und Werkbänke stehen und ob ein neuer Platz erlaubt ist.
## Lage = Vector2(x, z) in Metern, rot = Vierteldrehungen. Der Maschinenbereich ist die gelbe Markierung,
## er gehört zur Maschine und wandert mit. Werkbänke stehen im Bereich ihrer Maschine.

const BENCH_SIZE := Vector2(1.8, 0.7)
const BENCH_BIG_SIZE := Vector2(2.6, 0.8)
const BENCH_PRICE := 100
const BENCH_BIG_PRICE := 260
const CRATE_REACH := 1.2          # so weit darf eine Kiste von der Werkbank weg stehen
const CRATES_BENCH := 2           # Kisten neben einer Werkbank
const CRATES_BIG := 4             # neben einer großen Werkbank
## area = Maschinenbereich, foot = die Maschine selbst, beide lokal zur Maschine.
## Konventionelle Maschinen außer der Drehmaschine sind etwas größer.
const MACHINE_SCALE := 1.12
const SCALED := ["saw", "mill", "drill", "flat_grinder", "round_grinder"]
const SPECS := {
	"lathe": {"title": "Drehmaschine konventionell", "price": 0, "area": Rect2(-1.9, -1.4, 4.8, 4.9), "foot": Rect2(-1.7, -1.0, 4.4, 2.3), "pos": Vector2(0.0, -2.0)},
	"saw": {"title": "Bandsäge mit Rollbahn", "price": 0, "area": Rect2(-2.6, -1.2, 5.2, 3.2), "foot": Rect2(-2.5, -0.7, 5.0, 1.5), "pos": Vector2(-7.0, -5.0)},
	"mill": {"title": "Fräsmaschine", "price": 2400, "area": Rect2(-1.9, -1.6, 3.8, 4.7), "foot": Rect2(-1.1, -0.7, 2.2, 1.4), "pos": Vector2(6.85, -3.1)},
	"cnc_lathe": {"title": "CNC-Drehmaschine", "price": 14000, "area": Rect2(-1.9, -1.4, 6.7, 4.9), "foot": Rect2(-1.45, -1.1, 6.1, 2.5)},
	"round_grinder": {"title": "Rundschleifmaschine", "price": 12000, "area": Rect2(-2.2, -1.8, 5.4, 5.2), "foot": Rect2(-2.0, -1.2, 5.0, 2.6)},
	"flat_grinder": {"title": "Flachschleifmaschine", "price": 9000, "area": Rect2(-2.0, -1.7, 4.0, 4.3), "foot": Rect2(-1.5, -1.0, 3.0, 1.7)},
	"drill": {"title": "Standbohrmaschine", "price": 1500, "area": Rect2(-1.4, -1.2, 3.0, 3.6), "foot": Rect2(-0.6, -0.7, 1.2, 1.3)},
	"edm": {"title": "Erodiermaschine", "price": 25000, "area": Rect2(-2.2, -1.9, 4.4, 4.5), "foot": Rect2(-1.2, -1.1, 2.4, 2.2)},
}
## Maschinen mit Werkzeugen auf der Werkbank
const BENCH_MACHINES := ["lathe", "cnc_lathe", "mill", "drill", "flat_grinder", "round_grinder"]
const DEFAULT_BENCH := {"lathe": [0.6, 0.35, 2], "mill": [6.85, -0.95, 2]}
## Frei bleiben der Weg zum Rolltor und der Platz vor der Bürotür. x, z, Breite, Tiefe.
const OBSTACLES := [
	Rect2(9.0, 1.15, 3.0, 4.5), Rect2(6.4, 6.4, 2.3, 1.6),
	Rect2(2.4, 7.55, 2.0, 0.45),     # Durchgang zum Qualitätsmanagement
]

var machines: Dictionary = {}     # id -> {"pos": Vector2, "rot": int}
var benches: Dictionary = {}      # Maschinen-id -> {"pos": Vector2, "rot": int, "big": bool}
var crates: Array = []            # je {"size", "pos": Vector2, "rot", "bench": Maschinen-id, "items": []}
var bins: Array = []              # je {"size", "pos": Vector2, "rot", "chips": ChipTray, "out": bool, "machine": Spänekiste unter dem Förderer dieser Maschine (fehlt sonst)}
var shelves: Array = []           # je {"size", "pos": Vector2, "rot", "stack", "load"}, Holzregale und Ausstattung; stack: Paletten übereinander, load: Paletten auf der Gabel eines abgestellten Hubwagens
var site: Node = null             # Gelände: in_workshop(rect)


## Rechteck rect lokal, gedreht um rot Vierteldrehungen und verschoben nach pos.
static func rect_at(rect: Rect2, pos: Vector2, rot: int) -> Rect2:
	var out := Rect2(_turn(rect.position, rot) + pos, Vector2.ZERO)
	out = out.expand(_turn(rect.end, rot) + pos)
	return out


## Wie Node3D.rotation.y: lokal (x, z) nach Welt.
static func _turn(p: Vector2, rot: int) -> Vector2:
	match posmod(rot, 4):
		1:
			return Vector2(p.y, -p.x)
		2:
			return Vector2(-p.x, -p.y)
		3:
			return Vector2(-p.y, p.x)
	return p


static func bench_rect(pos: Vector2, rot: int, big := false) -> Rect2:
	var s := BENCH_BIG_SIZE if big else BENCH_SIZE
	return rect_at(Rect2(-s * 0.5, s), pos, rot)


static func crate_rect(id: String, pos: Vector2, rot: int) -> Rect2:
	var s := Crate.outer(id)
	return rect_at(Rect2(-s * 0.5, s), pos, rot)


static func bin_rect(pos: Vector2, rot: int, size_id := "bin_s") -> Rect2:
	var f := ChipBin.foot(size_id)
	return rect_at(Rect2(-f * 0.5, f), pos, rot)


static func shelf_rect(id: String, pos: Vector2, rot: int, load_n := 0, cross := false) -> Rect2:
	if id == "pallet_jack":
		return rect_at(Shelf.jack_rect(load_n, cross), pos, rot)
	var f := Shelf.foot(id)
	return rect_at(Rect2(-f * 0.5, f), pos, rot)


func bench_area(id: String) -> Rect2:
	var b: Dictionary = benches[id]
	return bench_rect(b["pos"], b["rot"], bool(b.get("big", false)))


func area_of(id: String) -> Rect2:
	var m: Dictionary = machines[id]
	return rect_at(SPECS[id]["area"], m["pos"], m["rot"])


func foot_of(id: String) -> Rect2:
	var m: Dictionary = machines[id]
	return rect_at(SPECS[id]["foot"], m["pos"], m["rot"])


## Fehlertext, wenn die Maschine dort nicht stehen darf. Leer = erlaubt.
func check_machine(id: String, pos: Vector2, rot: int) -> String:
	var area := rect_at(SPECS[id]["area"], pos, rot)
	if site and not site.in_workshop(area):
		return "Der Maschinenbereich muss ganz in der Werkstatt liegen."
	for other in machines:
		if other != id and area.grow(-0.001).intersects(area_of(other)):
			return "Der Maschinenbereich überschneidet sich mit %s." % SPECS[other]["title"]
	for o in OBSTACLES:
		if area.grow(-0.001).intersects(o):
			return "Dort steht schon etwas."
	var foot := rect_at(SPECS[id]["foot"], pos, rot).grow(-0.001)
	for b in bins:
		# Die eigene Spänekiste unter dem Förderer wandert mit der Maschine
		if str(b.get("machine", "")) == id:
			continue
		if foot.intersects(bin_rect(b["pos"], b["rot"], b["size"])):
			return "Dort steht ein Spänebehälter."
	for s in shelves:
		if foot.intersects(shelf_rect(s["size"], s["pos"], s["rot"], int(s.get("load", 0)), bool(s.get("cross", false)))):
			return "Dort steht ein Regal."
	return ""


## Wo würde die Werkbank hingehören? Maschine, in deren Bereich sie ganz liegt. Leer = in keinem.
func bench_machine_at(pos: Vector2, rot: int, big := false) -> String:
	var r := bench_rect(pos, rot, big)
	for id in machines:
		if area_of(id).grow(0.001).encloses(r):
			return id
	return ""


## Fehlertext für eine Werkbank an diesem Platz. moving = Maschine der gerade umgestellten Werkbank.
func check_bench(pos: Vector2, rot: int, moving := "", big := false) -> String:
	var id := bench_machine_at(pos, rot, big)
	if id == "":
		return "Werkbänke stehen in einem gelben Maschinenbereich."
	if not BENCH_MACHINES.has(id):
		return "%s hat noch keine Werkzeuge für eine Werkbank." % SPECS[id]["title"]
	if benches.has(id) and id != moving:
		return "%s hat schon eine Werkbank." % SPECS[id]["title"]
	if bench_rect(pos, rot, big).grow(-0.001).intersects(foot_of(id)):
		return "Die Werkbank steht zu dicht an der Maschine."
	if _blocked_by_stands(bench_rect(pos, rot, big), -1, -1):
		return "Dort steht schon etwas."
	return ""


## Kisten, die zur Werkbank dieser Maschine gehören.
func crates_of(id: String, except := -1) -> int:
	var n := 0
	for i in crates.size():
		if i != except and crates[i]["bench"] == id:
			n += 1
	return n


func crate_limit(id: String) -> int:
	return CRATES_BIG if bool(benches[id].get("big", false)) else CRATES_BENCH


## Werkbank neben dieser Stelle: Die Kiste liegt im selben Maschinenbereich in Reichweite. Leer = keine.
func crate_bench_at(size_id: String, pos: Vector2, rot: int) -> String:
	var r := crate_rect(size_id, pos, rot)
	for id in benches:
		if machines.has(id) and area_of(id).grow(0.001).encloses(r) and bench_area(id).grow(CRATE_REACH).intersects(r):
			return id
	return ""


## Steht die Kiste ganz auf der Platte der Werkbank bench_id?
func crate_on_top(size_id: String, pos: Vector2, rot: int, bench_id: String) -> bool:
	if not benches.has(bench_id):
		return false
	return bench_area(bench_id).grow(-0.02).encloses(crate_rect(size_id, pos, rot))


## Steht diese Kiste aus crates auf ihrer Werkbank?
func crate_is_on_top(c: Dictionary) -> bool:
	return crate_on_top(c["size"], c["pos"], c["rot"], str(c["bench"]))


## Kisten am Boden neben der Werkbank. Auf der Platte zählen sie nicht mit, dort begrenzt nur der Platz.
func floor_crates_of(id: String, except := -1) -> int:
	var n := 0
	for i in crates.size():
		if i != except and crates[i]["bench"] == id and not crate_is_on_top(crates[i]):
			n += 1
	return n


## Fehlertext für eine Kiste an diesem Platz. moving = Nummer der umgestellten Kiste, sonst -1.
## Kisten stehen neben der Werkbank am Boden oder ganz auf ihrer Platte.
func check_crate(size_id: String, pos: Vector2, rot: int, moving := -1) -> String:
	var id := crate_bench_at(size_id, pos, rot)
	if id == "":
		return "Kisten stehen neben oder auf einer Werkbank im gelben Maschinenbereich."
	var r := crate_rect(size_id, pos, rot).grow(-0.001)
	var top := crate_on_top(size_id, pos, rot, id)
	if r.intersects(foot_of(id)) or (not top and r.intersects(bench_area(id))):
		return "Dort steht schon etwas. Auf die Werkbank nur, wenn die Kiste ganz auf der Platte steht."
	if _blocked_by_stands(r, moving, -1):
		return "Dort steht schon etwas."
	if not top and floor_crates_of(id, moving) >= crate_limit(id):
		return "Neben dieser Werkbank stehen schon %d Kisten. Weitere passen noch auf die Platte." % crate_limit(id)
	return ""


## Fehlertext für einen Spänebehälter. Er steht frei in der Werkstatt, nur nicht auf anderem.
func check_bin(pos: Vector2, rot: int, moving := -1, size_id := "bin_s") -> String:
	var r := bin_rect(pos, rot, size_id)
	if site and not site.in_workshop(r):
		return "Spänebehälter stehen in der Werkstatt."
	r = r.grow(-0.001)
	for id in machines:
		if r.intersects(foot_of(id)):
			return "Dort steht schon etwas."
	for id in benches:
		if r.intersects(bench_area(id)):
			return "Dort steht schon etwas."
	for o in OBSTACLES:
		if r.intersects(o):
			return "Dort steht schon etwas."
	if _blocked_by_stands(r, -1, moving):
		return "Dort steht schon etwas."
	return ""


## Fehlertext für ein Holzregal. Es steht frei in der Werkstatt, wie ein Spänebehälter.
func check_shelf(id: String, pos: Vector2, rot: int, moving := -1, load_n := 0, cross := false) -> String:
	var r := shelf_rect(id, pos, rot, load_n, cross)
	var lager := bool(Shelf.SIZES[id].get("lager", false))
	if site and not site.in_workshop(r):
		if not lager:
			return "Regale stehen in der Werkstatt."
		if not site.in_lager(r):
			return "Steht in der Werkstatt oder im Lager."
		if site.blocked_by_rack(r.grow(-0.001)):
			return "Dort steht ein Lagerregal."
	r = r.grow(-0.001)
	for m in machines:
		if r.intersects(foot_of(m)):
			return "Dort steht schon etwas."
	for b in benches:
		if r.intersects(bench_area(b)):
			return "Dort steht schon etwas."
	for o in OBSTACLES:
		if r.intersects(o):
			return "Dort steht schon etwas."
	if _blocked_by_stands(r, -1, -1, moving):
		return "Dort steht schon etwas."
	return ""


func _blocked_by_stands(r: Rect2, skip_crate: int, skip_bin: int, skip_shelf := -1) -> bool:
	for i in shelves.size():
		if i != skip_shelf and r.intersects(shelf_rect(shelves[i]["size"], shelves[i]["pos"], shelves[i]["rot"], int(shelves[i].get("load", 0)), bool(shelves[i].get("cross", false)))):
			return true
	for i in crates.size():
		if i != skip_crate and r.intersects(crate_rect(crates[i]["size"], crates[i]["pos"], crates[i]["rot"])):
			return true
	for i in bins.size():
		if i != skip_bin and r.intersects(bin_rect(bins[i]["pos"], bins[i]["rot"], bins[i]["size"])):
			return true
	return false


func to_state() -> Dictionary:
	var ms := {}
	for id in machines:
		ms[id] = [machines[id]["pos"].x, machines[id]["pos"].y, machines[id]["rot"]]
	var bs := {}
	for id in benches:
		bs[id] = [benches[id]["pos"].x, benches[id]["pos"].y, benches[id]["rot"], bool(benches[id].get("big", false))]
	var cs := []
	for c in crates:
		cs.append({"size": c["size"], "pos": [c["pos"].x, c["pos"].y], "rot": c["rot"], "bench": c["bench"], "items": c["items"]})
	var ch := []
	for b in bins:
		var e := {"size": b["size"], "pos": [b["pos"].x, b["pos"].y], "rot": b["rot"], "chips": b["chips"].to_state(), "out": b["out"]}
		if b.has("machine"):
			e["machine"] = b["machine"]
		ch.append(e)
	var sh := []
	for s in shelves:
		sh.append({"size": s["size"], "pos": [s["pos"].x, s["pos"].y], "rot": s["rot"], "stack": int(s.get("stack", 1)), "load": int(s.get("load", 0)), "cross": bool(s.get("cross", false))})
	return {"machines": ms, "benches": bs, "crates": cs, "bins": ch, "shelves": sh, "starter_transport": true}
