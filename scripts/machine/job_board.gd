class_name JobBoard
extends RefCounted
## Welche Aufträge gerade offen sind, nach Maschinenart. Aufträge gibt es nur für Maschinen, die die
## Werkstatt besitzt. Eigene Schleifaufträge entstehen nicht von selbst, sondern nur aus einem Auftrag,
## der eine geschliffene Fläche verlangt ("grind" in Jobs und MillJobs), und erst wenn die passende
## Schleifmaschine da ist. Ebene Fläche = Flachschleifen, Rundfläche = Rundschleifen.

const CATEGORIES := [
	{"id": "lathe", "title": "Drehaufträge", "machine": "Drehmaschine"},
	{"id": "mill", "title": "Fräsaufträge", "machine": "Fräsmaschine"},
	{"id": "round_grinder", "title": "Rundschleifaufträge", "machine": "Rundschleifmaschine"},
	{"id": "flat_grinder", "title": "Flachschleifaufträge", "machine": "Flachschleifmaschine"},
	{"id": "drill", "title": "Bohraufträge", "machine": "Standbohrmaschine"},
	{"id": "edm", "title": "Erodieraufträge", "machine": "Erodiermaschine"},
]
## Art der geschliffenen Fläche -> Maschine
const GRINDERS := {"round": "round_grinder", "flat": "flat_grinder"}
const GRIND_NAMES := {"round": "Rundfläche", "flat": "ebene Fläche"}
const MACHINE_NAMES := {"lathe": "Drehauftrag", "mill": "Fräsauftrag", "drill": "Bohrauftrag", "ceramic": "Kundenauftrag"}
## Maschinenarten mit eigenen Aufträgen
const JOB_MACHINES := ["lathe", "mill", "drill"]
const MAX_PER_MACHINE := 2
const MAX_TOTAL := 9


## Auftrag als Schlüssel "lathe:2". Den speichern die Liste der angenommenen Aufträge und die Anzeige.
static func key(machine: String, index: int) -> String:
	return "%s:%d" % [machine, posmod(index, list_of(machine).size())]


static func list_of(machine: String) -> Array:
	match machine:
		"lathe":
			return Jobs.all()
		"drill":
			return DrillJobs.all()
		"ceramic":
			return CeramicJobs.LIST
	return MillJobs.all()


static func key_machine(k: String) -> String:
	return k.get_slice(":", 0)


static func key_index(k: String) -> int:
	return int(k.get_slice(":", 1))


static func job_of(k: String) -> Dictionary:
	var list := list_of(key_machine(k))
	return list[posmod(key_index(k), list.size())]


## Zielmaße eines Auftrags als Zeilen. grind: auch die geschliffene Fläche nennen.
static func target_lines(job: Dictionary, grind := false) -> Array:
	var out: Array = Jobs.target_lines(job) if job.has("stock_d") else MillJobs.target_lines(job)
	if grind and job.has("grind"):
		out.append(grind_line(job))
	return out.map(func(t) -> String: return str(t).replace(".", ","))


static func describe_key(k: String, company: Company) -> String:
	var job := job_of(k)
	if job.has("stock_d"):
		return Jobs.describe(job, grind_active(job, company))
	return MillJobs.describe(job, grind_active(job, company))


## Maschine, an der dieser Auftrag zählt: Kundenaufträge bei ihrer Schleifmaschine.
static func machine_of(k: String) -> String:
	if key_machine(k) == "ceramic":
		return str(GRINDERS[job_of(k)["grind"]["type"]])
	return key_machine(k)


## Frist in Tagen ab dem Annehmen. Schwierigere Aufträge haben etwas länger.
static func days_for(k: String) -> int:
	var job := job_of(k)
	if job.has("days"):
		return int(job["days"])
	return 2 + posmod(key_index(k), 4)


## Darf dieser Auftrag überhaupt angeboten werden? Maschine und Werkstoff müssen freigeschaltet sein.
static func unlocked(k: String, company: Company) -> bool:
	var machine := key_machine(k)
	if machine == "ceramic":
		var grinder := machine_of(k)
		return company.skills.has("wheel_diamond") and company.owns(grinder)
	if not company.skills.has(Skills.machine_skill(machine)):
		return false
	return company.skills.has(Skills.material_node(str(job_of(k).get("material", Materials.DEFAULT))))


## Alle Aufträge, die es gibt, zuerst die der Drehmaschine.
static func all_keys() -> Array:
	var out := []
	for m in JOB_MACHINES + ["ceramic"]:
		for i in list_of(m).size():
			out.append(key(m, i))
	return out


## Erfahrung für einen erfolgreich abgegebenen Auftrag.
static func xp_for(job: Dictionary) -> int:
	return int(job["reward"])


## Grund, warum dieser Auftrag nicht angenommen werden kann. Leer = geht.
static func lock_reason(k: String, company: Company) -> String:
	var machine := key_machine(k)
	var skill := Skills.machine_skill(machine)
	if not company.skills.has(skill):
		return "Im Skilltree freischalten: %s" % Skills.title_of(skill)
	if machine == "ceramic":
		var grinder := machine_of(k)
		return "" if company.owns(grinder) else "Erst kaufen und aufstellen: %s." % Layout.SPECS[grinder]["title"]
	if not company.owns_kind(machine):
		return "Erst kaufen und aufstellen: %s." % Layout.SPECS[machine]["title"]
	var mat := str(job_of(k).get("material", Materials.DEFAULT))
	var node := Skills.material_node(mat)
	if not company.skills.has(node):
		return "Im Skilltree freischalten: %s" % Skills.title_of(node)
	return ""


## Verlangt dieser Auftrag gerade eine geschliffene Fläche? Ohne Schleifmaschine nie.
static func grind_active(job: Dictionary, company: Company) -> bool:
	return job.has("grind") and company.owns(str(GRINDERS[job["grind"]["type"]]))


## Zeile für den Auftragstext.
static func grind_line(job: Dictionary) -> String:
	var g: Dictionary = job["grind"]
	return "Geschliffen (%s): %s, Rz <= %.1f µm" % [GRIND_NAMES[g["type"]], g["surface"], float(g["rz"])]


## Offene Aufträge einer Kategorie: je {"title", "text"}. lathe_job und mill_job sind die laufenden Aufträge.
static func entries(category: String, lathe_job: Dictionary, mill_job: Dictionary, company: Company) -> Array:
	if not company.owns_kind(category):
		return []
	match category:
		"lathe":
			return [{"title": lathe_job["title"], "text": Jobs.describe(lathe_job, grind_active(lathe_job, company))}]
		"mill":
			return [{"title": mill_job["title"], "text": MillJobs.describe(mill_job, grind_active(mill_job, company))}]
		"round_grinder", "flat_grinder":
			return grind_entries(category, [lathe_job, mill_job], company)
	return []


## Schleifaufträge einer Kategorie aus den genannten Aufträgen.
static func grind_entries(category: String, jobs: Array, company: Company) -> Array:
	var list := []
	if not company.owns(category):
		return list
	for job in jobs:
		if grind_active(job, company) and str(GRINDERS[job["grind"]["type"]]) == category:
			list.append(_grind_entry(job))
	return list


static func _grind_entry(job: Dictionary) -> Dictionary:
	var g: Dictionary = job["grind"]
	var title := "Schleifen zu %s" % job["title"]
	var text := "%s\n%s nach dem Vorbearbeiten fertig schleifen.\n\nWerkstoff: %s\n  %s\nVergütung: bis %d EUR" % [
		title, str(GRIND_NAMES[g["type"]]).capitalize(), Materials.label(str(job.get("material", Materials.DEFAULT))),
		grind_line(job), int(g["reward"])]
	return {"title": title, "text": text}
