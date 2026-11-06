class_name Skills
extends RefCounted
## Skilltree der Werkstatt: Erfahrung aus erfolgreichen Aufträgen gibt Skillpunkte, Skillpunkte schalten
## Maschinen, Werkstoffgruppen und Upgrades frei. Werkzeuge haben je Maschine einen eigenen Baum, der erst
## mit der Maschine erscheint. Kaufen lässt sich am Anfang nur Hartmetall, HSS erst nach dem Skill.
##
## Knoten: tree, branch, title, desc, cost, req (Voraussetzungen), at (Spalte, Zeile im Baum).
## start = von Anfang an da. auto = kommt mit der Voraussetzung, kostet nichts.
## soon = die Maschine gibt es noch nicht, darum noch nicht freischaltbar.

const XP_FIRST := 200             # Erfahrung für den ersten Skillpunkt
const XP_STEP := 100              # jeder weitere kostet so viel mehr

const TREES := [
	{"id": "general", "title": "Allgemein", "needs": ""},
	{"id": "lathe_tools", "title": "Drehmaschine: Drehwerkzeuge", "needs": "lathe_conv"},
	{"id": "mill_tools", "title": "Fräsmaschine: Fräswerkzeuge", "needs": "mill_conv"},
	{"id": "drill_tools", "title": "Standbohrmaschine: Bohrer", "needs": "drill"},
	{"id": "wheel_tools", "title": "Schleifmaschinen: Schleifscheiben", "needs": "flat_grinder", "or": "round_grinder"},
]
const BRANCHES := {"Maschinen": 0, "Werkstoffe": 5, "Upgrades": 10}

const NODES := {
	# Maschinen: erst konventionell, später CNC
	"lathe_conv": {"tree": "general", "branch": "Maschinen", "title": "Drehmaschine\nkonventionell", "cost": 0, "req": [], "at": Vector2i(0, 0), "start": true,
		"desc": "Von Hand über Handräder und Vorschub bedient. Von Anfang an frei, gekauft wird sie am PC im Shop."},
	"lathe_cnc": {"tree": "general", "branch": "Maschinen", "title": "Drehmaschine\nCNC", "cost": 3, "req": ["lathe_conv"], "at": Vector2i(1, 0),
		"desc": "Die CNC-Drehmaschine kann am PC gekauft werden: Bedienpult mit Zyklen und NC-Programmen."},
	"mill_conv": {"tree": "general", "branch": "Maschinen", "title": "Fräsmaschine\nkonventionell", "cost": 1, "req": ["lathe_conv"], "at": Vector2i(1, 1),
		"desc": "Die Fräsmaschine kann am PC gekauft werden, Fräsaufträge werden möglich. Dazu kommt der Baum für Fräswerkzeuge."},
	"mill_cnc": {"tree": "general", "branch": "Maschinen", "title": "Fräsmaschine\nCNC", "cost": 4, "req": ["mill_conv", "lathe_cnc"], "at": Vector2i(2, 1), "soon": true,
		"desc": "Programmgesteuertes Fräsen. Diese Maschine gibt es noch nicht im Spiel."},
	"drill": {"tree": "general", "branch": "Maschinen", "title": "Standbohr-\nmaschine", "cost": 1, "req": ["lathe_conv"], "at": Vector2i(1, 2),
		"desc": "Die Standbohrmaschine kann am PC gekauft werden. Bohraufträge werden möglich, dazu kommt der Baum für Bohrer."},
	"round_grinder": {"tree": "general", "branch": "Maschinen", "title": "Rundschleif-\nmaschine", "cost": 2, "req": ["lathe_conv"], "at": Vector2i(1, 3),
		"desc": "Die Rundschleifmaschine kann am PC gekauft werden. Aufträge verlangen dann geschliffene Rundflächen."},
	"flat_grinder": {"tree": "general", "branch": "Maschinen", "title": "Flachschleif-\nmaschine", "cost": 2, "req": ["mill_conv"], "at": Vector2i(2, 2),
		"desc": "Die Flachschleifmaschine kann am PC gekauft werden. Aufträge verlangen dann geschliffene ebene Flächen."},
	"edm": {"tree": "general", "branch": "Maschinen", "title": "Erodier-\nmaschine", "cost": 4, "req": ["flat_grinder"], "at": Vector2i(3, 2),
		"desc": "Die Erodiermaschine kann am PC gekauft werden."},
	# Werkstoffgruppen: mat_ + Gruppen-id aus Materials
	"mat_baustahl": {"tree": "general", "branch": "Werkstoffe", "title": "Baustahl", "cost": 0, "req": [], "at": Vector2i(0, 5), "start": true,
		"desc": "Gut zerspanbar. Von Anfang an verfügbar."},
	"mat_automatenstahl": {"tree": "general", "branch": "Werkstoffe", "title": "Automatenstahl", "cost": 1, "req": ["mat_baustahl"], "at": Vector2i(1, 5),
		"desc": "Sehr gut zerspanbar, kurze Späne. Material und Aufträge werden verfügbar."},
	"mat_einsatzstahl": {"tree": "general", "branch": "Werkstoffe", "title": "Einsatzstahl", "cost": 1, "req": ["mat_baustahl"], "at": Vector2i(1, 6),
		"desc": "Weich und zäh. Material und Aufträge werden verfügbar."},
	"mat_gusseisen": {"tree": "general", "branch": "Werkstoffe", "title": "Gusseisen", "cost": 1, "req": ["mat_baustahl"], "at": Vector2i(1, 7),
		"desc": "Bröckeliger Span, meist trocken bearbeitet. Material und Aufträge werden verfügbar."},
	"mat_aluminium": {"tree": "general", "branch": "Werkstoffe", "title": "Aluminium", "cost": 1, "req": ["mat_baustahl"], "at": Vector2i(1, 8),
		"desc": "Geringe Schnittkräfte, klebt ohne Kühlung. Material und Aufträge werden verfügbar."},
	"mat_verguetungsstahl": {"tree": "general", "branch": "Werkstoffe", "title": "Vergütungsstahl", "cost": 2, "req": ["mat_einsatzstahl"], "at": Vector2i(2, 6),
		"desc": "Fester als Baustahl, mehr Verschleiß. Material und Aufträge werden verfügbar."},
	"mat_edelstahl": {"tree": "general", "branch": "Werkstoffe", "title": "Edelstahl", "cost": 3, "req": ["mat_verguetungsstahl"], "at": Vector2i(3, 5),
		"desc": "Leitet Wärme schlecht, verfestigt sich. Material und Aufträge werden verfügbar."},
	"mat_werkzeugstahl": {"tree": "general", "branch": "Werkstoffe", "title": "Werkzeugstahl", "cost": 3, "req": ["mat_verguetungsstahl"], "at": Vector2i(3, 6),
		"desc": "Hart und verschleißend. Material und Aufträge werden verfügbar."},
	"mat_titan": {"tree": "general", "branch": "Werkstoffe", "title": "Titan", "cost": 5, "req": ["mat_edelstahl"], "at": Vector2i(4, 5),
		"desc": "Schwer zerspanbar, viel Hitze an der Schneide. Material und Aufträge werden verfügbar."},
	"mat_messing": {"tree": "general", "branch": "Werkstoffe", "title": "Messing", "cost": 2, "req": ["mat_aluminium"], "at": Vector2i(2, 8),
		"desc": "Kurze Späne, gute Oberflächen. Material und Aufträge werden verfügbar."},
	"mat_kupfer": {"tree": "general", "branch": "Werkstoffe", "title": "Kupfer", "cost": 2, "req": ["mat_messing"], "at": Vector2i(3, 8),
		"desc": "Weich und zäh, schmiert ohne Kühlung. Material und Aufträge werden verfügbar."},
	"mat_bronze": {"tree": "general", "branch": "Werkstoffe", "title": "Bronze", "cost": 2, "req": ["mat_kupfer"], "at": Vector2i(4, 8),
		"desc": "Zinnbronze gut, Aluminiumbronze deutlich zäher. Material und Aufträge werden verfügbar."},
	# Upgrades
	"bench_big": {"tree": "general", "branch": "Upgrades", "title": "Große Werkbank", "cost": 1, "req": [], "at": Vector2i(0, 10),
		"desc": "Eine größere Werkbank kann am PC gekauft werden. Neben ihr haben 4 statt 2 Kisten Platz."},
	"crate_m": {"tree": "general", "branch": "Upgrades", "title": "Mittlere Kisten", "cost": 1, "req": [], "at": Vector2i(1, 10),
		"desc": "Mittlere Kisten können am PC gekauft werden: 600 x 400 x 300 mm, bis 12 Teile."},
	"crate_l": {"tree": "general", "branch": "Upgrades", "title": "Große Kisten", "cost": 2, "req": ["crate_m"], "at": Vector2i(2, 10),
		"desc": "Große Kisten können am PC gekauft werden: 1000 x 600 x 400 mm, bis 24 Teile."},
	"coolant_1": {"tree": "general", "branch": "Upgrades", "title": "Besseres\nKühlmittel", "cost": 1, "req": [], "at": Vector2i(0, 11),
		"desc": "Mit Kühlung erhitzt sich die Schneide um ein Drittel langsamer."},
	"coolant_2": {"tree": "general", "branch": "Upgrades", "title": "Hochleistungs-\nKühlmittel", "cost": 2, "req": ["coolant_1"], "at": Vector2i(1, 11),
		"desc": "Mit Kühlung erhitzt sich die Schneide nur noch halb so schnell wie mit dem besseren Kühlmittel."},
	"tray_big": {"tree": "general", "branch": "Upgrades", "title": "Große\nSpänewannen", "cost": 1, "req": [], "at": Vector2i(0, 12),
		"desc": "Die Spänewannen aller Maschinen fassen doppelt so viel."},
	"recycling": {"tree": "general", "branch": "Upgrades", "title": "Recycling-\nvertrag", "cost": 2, "req": ["tray_big"], "at": Vector2i(1, 12),
		"desc": "Volle Spänecontainer bringen 50 % mehr Geld."},
	"bin_l": {"tree": "general", "branch": "Upgrades", "title": "Großer Späne-\nbehälter", "cost": 1, "req": ["tray_big"], "at": Vector2i(1, 13),
		"desc": "Große Spänebehälter können am PC gekauft werden: 60 statt 25 kg."},
	# Drehwerkzeuge
	"lathe_hm": {"tree": "lathe_tools", "branch": "Schneidstoffe", "title": "Hartmetall", "cost": 0, "req": ["lathe_conv"], "at": Vector2i(0, 0), "auto": true,
		"desc": "Alle Drehwerkzeuge lassen sich mit Hartmetall-Wendeplatten kaufen. Kommt mit der Maschine."},
	"lathe_hss": {"tree": "lathe_tools", "branch": "Schneidstoffe", "title": "HSS", "cost": 1, "req": ["lathe_hm"], "at": Vector2i(1, 0),
		"desc": "HSS-Drehmeißel lassen sich kaufen: halber Preis und feinere Oberfläche, aber sie werden deutlich schneller heiß und verschleißen schneller."},
	"lathe_coat_heat": {"tree": "lathe_tools", "branch": "Veredelung", "title": "Beschichtung\nHitzeschutz", "cost": 2, "req": ["lathe_hm"], "at": Vector2i(1, 1),
		"desc": "Alle Drehwerkzeuge werden 30 % langsamer heiß."},
	"lathe_coat_wear": {"tree": "lathe_tools", "branch": "Veredelung", "title": "Beschichtung\nVerschleißschutz", "cost": 2, "req": ["lathe_hm"], "at": Vector2i(1, 2),
		"desc": "Alle Drehwerkzeuge verschleißen 40 % langsamer."},
	"lathe_rebate": {"tree": "lathe_tools", "branch": "Veredelung", "title": "Großabnehmer", "cost": 1, "req": ["lathe_hss"], "at": Vector2i(2, 0),
		"desc": "Drehwerkzeuge kosten beim Kauf 30 % weniger."},
	# Schleifscheiben
	"wheel_korund": {"tree": "wheel_tools", "branch": "Schleifmittel", "title": "Korund", "cost": 0, "req": ["flat_grinder"], "at": Vector2i(0, 0), "start": true,
		"desc": "Korundscheiben in verschiedenen Breiten. Nutzen sich schnell ab und werden unrund, dann am Abziehwerkzeug abziehen."},
	"wheel_cbn": {"tree": "wheel_tools", "branch": "Schleifmittel", "title": "CBN", "cost": 2, "req": ["wheel_korund"], "at": Vector2i(1, 0),
		"desc": "CBN-Scheiben (kubisches Bornitrid) lassen sich kaufen: halten viel länger, bleiben lange gerade und schleifen feiner."},
	"wheel_diamond": {"tree": "wheel_tools", "branch": "Schleifmittel", "title": "Diamant", "cost": 3, "req": ["wheel_cbn"], "at": Vector2i(2, 0),
		"desc": "Diamantscheiben lassen sich kaufen. Nur sie schneiden Keramik und bringen besondere Kundenaufträge. Stahl ruiniert sie schnell."},
	# Bohrer
	"drill_hm": {"tree": "drill_tools", "branch": "Schneidstoffe", "title": "Hartmetall", "cost": 0, "req": ["drill"], "at": Vector2i(0, 0), "auto": true,
		"desc": "Alle Bohrer lassen sich aus Hartmetall kaufen. Kommt mit der Maschine."},
	"drill_hss": {"tree": "drill_tools", "branch": "Schneidstoffe", "title": "HSS", "cost": 1, "req": ["drill_hm"], "at": Vector2i(1, 0),
		"desc": "HSS-Bohrer lassen sich kaufen: halber Preis und 25 % mehr Vorschub, aber sie werden deutlich schneller heiß und verschleißen schneller."},
	"drill_coat_heat": {"tree": "drill_tools", "branch": "Veredelung", "title": "Beschichtung\nHitzeschutz", "cost": 2, "req": ["drill_hm"], "at": Vector2i(1, 1),
		"desc": "Alle Bohrer werden 30 % langsamer heiß."},
	"drill_coat_wear": {"tree": "drill_tools", "branch": "Veredelung", "title": "Beschichtung\nVerschleißschutz", "cost": 2, "req": ["drill_hm"], "at": Vector2i(1, 2),
		"desc": "Alle Bohrer verschleißen 40 % langsamer."},
	"drill_rebate": {"tree": "drill_tools", "branch": "Veredelung", "title": "Großabnehmer", "cost": 1, "req": ["drill_hss"], "at": Vector2i(2, 0),
		"desc": "Bohrer kosten beim Kauf 30 % weniger."},
	# Fräswerkzeuge
	"mill_hm": {"tree": "mill_tools", "branch": "Schneidstoffe", "title": "Hartmetall", "cost": 0, "req": ["mill_conv"], "at": Vector2i(0, 0), "auto": true,
		"desc": "Alle Fräswerkzeuge lassen sich aus Hartmetall kaufen. Kommt mit der Maschine."},
	"mill_hss": {"tree": "mill_tools", "branch": "Schneidstoffe", "title": "HSS", "cost": 1, "req": ["mill_hm"], "at": Vector2i(1, 0),
		"desc": "HSS-Fräser lassen sich kaufen: halber Preis und 25 % mehr Vorschub je Schneide, aber sie werden deutlich schneller heiß und verschleißen schneller."},
	"mill_coat_heat": {"tree": "mill_tools", "branch": "Veredelung", "title": "Beschichtung\nHitzeschutz", "cost": 2, "req": ["mill_hm"], "at": Vector2i(1, 1),
		"desc": "Alle Fräswerkzeuge werden 30 % langsamer heiß."},
	"mill_coat_wear": {"tree": "mill_tools", "branch": "Veredelung", "title": "Beschichtung\nVerschleißschutz", "cost": 2, "req": ["mill_hm"], "at": Vector2i(1, 2),
		"desc": "Alle Fräswerkzeuge verschleißen 40 % langsamer."},
	"mill_rebate": {"tree": "mill_tools", "branch": "Veredelung", "title": "Großabnehmer", "cost": 1, "req": ["mill_hss"], "at": Vector2i(2, 0),
		"desc": "Fräswerkzeuge kosten beim Kauf 30 % weniger."},
}

## Was man erst kaufen darf, wenn der Skill freigeschaltet ist.
const EQUIPMENT := {
	"lathe": "lathe_conv", "cnc_lathe": "lathe_cnc", "mill": "mill_conv", "drill": "drill", "round_grinder": "round_grinder", "flat_grinder": "flat_grinder",
	"edm": "edm", "bench_big": "bench_big",
	"crate_m": "crate_m", "crate_l": "crate_l", "bin_l": "bin_l",
}
const COOLANT := {"": 0.4, "coolant_1": 0.27, "coolant_2": 0.13}

var xp := 0
var spent := 0
var unlocked: Dictionary = {}


static func material_node(material_id: String) -> String:
	return "mat_%s" % Materials.group_of(material_id)["id"]


## Name ohne Zeilenumbruch und Trennstrich.
static func title_of(id: String) -> String:
	return str(NODES[id]["title"]).replace("-\n", "").replace("\n", " ")


## Skillpunkte, die bis zu dieser Erfahrung verdient sind.
static func points_for(amount: int) -> int:
	var n := 0
	var need := XP_FIRST
	var left := amount
	while left >= need:
		left -= need
		need += XP_STEP
		n += 1
	return n


## Erfahrung seit dem letzten Skillpunkt und was der nächste kostet.
func progress() -> Vector2i:
	var need := XP_FIRST
	var left := xp
	while left >= need:
		left -= need
		need += XP_STEP
	return Vector2i(left, need)


func free_points() -> int:
	return points_for(xp) - spent


func has(id: String) -> bool:
	if not NODES.has(id):
		return false
	var n: Dictionary = NODES[id]
	if n.get("start", false):
		return true
	if n.get("auto", false):
		return has(str(n["req"][0]))
	return unlocked.has(id)


## Grund, warum der Skill nicht freigeschaltet werden kann. Leer = geht.
func unlock_error(id: String, free_mode := false) -> String:
	if not NODES.has(id):
		return "Diesen Skill gibt es nicht."
	if has(id):
		return "Schon freigeschaltet."
	var n: Dictionary = NODES[id]
	if n.get("soon", false):
		return "Diese Maschine gibt es noch nicht im Spiel."
	for r in n["req"]:
		if not has(str(r)):
			return "Zuerst freischalten: %s." % title_of(str(r))
	if not free_mode and int(n["cost"]) > free_points():
		return "Nicht genug Skillpunkte: %d nötig, %d frei." % [int(n["cost"]), free_points()]
	return ""


## Freischalten. Im Testmodus kostet es keine Punkte. Gibt einen Fehlertext zurück, leer = geschafft.
func unlock(id: String, free_mode := false) -> String:
	var err := unlock_error(id, free_mode)
	if err != "":
		return err
	unlocked[id] = true
	if not free_mode:
		spent += int(NODES[id]["cost"])
	return ""


## Alles, was es vor dem Skilltree schon gab: Maschinen und Werkstoffe. Upgrades bleiben offen.
func unlock_basics() -> void:
	for id in NODES:
		var n: Dictionary = NODES[id]
		if n["tree"] == "general" and n["branch"] != "Upgrades" and not n.get("soon", false):
			unlocked[id] = true


func coolant_factor() -> float:
	if has("coolant_2"):
		return float(COOLANT["coolant_2"])
	if has("coolant_1"):
		return float(COOLANT["coolant_1"])
	return float(COOLANT[""])


func tray_capacity() -> float:
	return ChipTray.CAPACITY * (2.0 if has("tray_big") else 1.0)


func recycle_factor() -> float:
	return 1.5 if has("recycling") else 1.0


## Wirkung von Schneidstoff und Beschichtung auf ein Werkzeug: heat und wear sind Faktoren auf Erwärmung
## und Verschleiß, tough auf den erlaubten Vorschub, finish auf die Rautiefe.
func tool_mods(machine: String, grade := "hm") -> Dictionary:
	var m := {"heat": 1.0, "wear": 1.0, "tough": 1.0, "finish": 1.0}
	if grade == "hss":
		m["heat"] = 2.5
		m["wear"] = 1.4
		if machine != "lathe":
			m["tough"] = 1.25
		else:
			m["finish"] = 0.8
	if has("%s_coat_heat" % machine):
		m["heat"] = float(m["heat"]) * 0.7
	if has("%s_coat_wear" % machine):
		m["wear"] = float(m["wear"]) * 0.6
	return m


## Faktor auf den Kaufpreis eines Werkzeugs.
func tool_price_factor(machine: String, grade: String) -> float:
	return (0.5 if grade == "hss" else 1.0) * (0.7 if has("%s_rebate" % tool_family(machine)) else 1.0)


## Skill, der die Werkzeuge dieser Maschine zum Kauf freigibt.
static func machine_skill(machine: String) -> String:
	return {"lathe": "lathe_conv", "cnc_lathe": "lathe_cnc", "mill": "mill_conv", "drill": "drill",
		"flat_grinder": "flat_grinder", "round_grinder": "round_grinder", "ceramic": "wheel_diamond"}[machine]


## Werkzeugbaum einer Maschine. Beide Drehmaschinen teilen sich einen.
static func tool_family(machine: String) -> String:
	return "lathe" if machine == "cnc_lathe" else machine


func to_state() -> Dictionary:
	return {"xp": xp, "spent": spent, "unlocked": unlocked.keys()}


func load_state(d: Dictionary) -> void:
	xp = int(d.get("xp", 0))
	spent = int(d.get("spent", 0))
	unlocked = {}
	var list = d.get("unlocked", [])
	if list is Array:
		for id in list:
			unlocked[str(id)] = true
