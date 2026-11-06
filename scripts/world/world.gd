extends Node3D
## Spielwelt: Werkstatt, Maschinen, Spieler, HUD, Pause-Menü, Aufträge und Speichern. lathe und mill sind
## die konventionelle Drehmaschine und die Fräsmaschine, alle anderen Maschinen entstehen beim Aufstellen.

var player: Player
var lathe: Lathe
var mill: Mill
var office_pc: OfficePC
var bench_nodes: Dictionary = {}  # Maschinen-id -> ToolBench
var lathe_bench: ToolBench:
	get:
		return bench_nodes.get("lathe", null)
var mill_bench: ToolBench:
	get:
		return bench_nodes.get("mill", null)
var cnc_lathe: Lathe:
	get:
		return extra_machines.get("cnc_lathe", null)
var hud: HUD
var mill_hud: MillHUD
var mill_huds: Dictionary = {}    # Maschinen-id -> MillHUD der Bohr- und Flachschleifmaschine
var pause_menu: PauseMenu
var env: Environment
var probe: ReflectionProbe
var _lights: Dictionary = {}
var _ambient: AudioStreamPlayer
var _amb_pb: AudioStreamGeneratorPlayback
var _amb_lp := 0.0
var _amb_ph := 0.0

var save_name := "Werkstatt"
var company := Company.new()      # Kasse und Maschinenpark gehören der Werkstatt, nicht der Spielfigur
var money: int:
	get:
		return company.balance
	set(v):
		# Der Tagesbericht zählt jede Bewegung der Kasse
		if v > company.balance:
			day_stats["earned"] = int(day_stats.get("earned", 0)) + v - company.balance
		else:
			day_stats["spent"] = int(day_stats.get("spent", 0)) + company.balance - v
		company.balance = v
var day_started := true           # Jeder Tag muss am PC im Programm Tagesbericht gestartet werden
var day_stats: Dictionary = {}    # {"accepted", "done", "earned", "spent"} des laufenden Tages
var last_day_stats: Dictionary = {}
var job_index := 0
var mill_job_index := 0
var drill_job_index := 0
var parts := 0
var day := 1                      # laufender Tag
var day_time := 0.0               # s seit Tagesbeginn
var day_over := false             # Feierabend: Nichts annehmen und nichts kaufen, bis der Tag beendet wird
var deadlines: Dictionary = {}    # Auftrag -> letzter Tag
var _clock_t := 0.0
const DAY_SECONDS := 1200.0       # ein Arbeitstag dauert 20 Minuten
const REP_DONE := 2.0             # Ansehen für einen erfolgreichen Auftrag
const REP_LATE := -8.0            # Ansehen für eine verpasste Frist
const REP_SCRAP := -3.0           # Ansehen für Ausschuss beim Schleifen
var play_time := 0.0
var stock: Array = []             # bestelltes Rohmaterial im Lager
var free_mode := false            # Testmodus: alles gratis, wird nicht gespeichert
var deliveries: Array = []        # bestellt, steht noch vor dem Lagertor
var site: Site
var job_menu: JobMenu
var rack_menu: RackMenu
var build_menu: BuildMenu
var layout := Layout.new()        # Stellplan: Maschinen, Bereiche, Werkbänke
var inventory: Dictionary = {}    # gekauft, aber noch nicht aufgestellt
var extra_machines: Dictionary = {}
var drawing: DrawingOverlay
var clamp_dialog: ClampDialog
const STARTER_MACHINES := ["lathe", "saw"]
const STARTER_TOOLS := ["T1", "T3", "T5"]     # Schruppen, Schlichten, Fasen
const STARTER_RACK := Vector2(14.0, -12.0)
const STARTER_BAR := {"material": "S235", "kind": "round", "d": 60.0, "w": 0.0, "h": 0.0, "l": 2000.0}
const LATHE_MAX_LEN := 800.0       # längstes Stück im Futter
const MILL_MAX_LEN := 300.0        # längstes Stück im Schraubstock
var accepted: Array = []          # angenommene Aufträge als Schlüssel, siehe JobBoard.key
var tracked := ""                 # Auftrag, der oben rechts steht
var grind_jobs: Array = []        # vorbearbeitet, wartet aufs Schleifen, Schlüssel wie accepted
var crate_nodes: Array = []
var bin_nodes: Array = []
var containers: Array = []        # ChipTray je Spänecontainer im Hof

const CONTAINER_KG := 120.0
const CONTAINER_SORTS := ["stahl", "aluminium", "messing"]


func _ready() -> void:
	_build_environment()
	_lights = Workshop.build(self)
	site = Site.new()
	site.world = self
	add_child(site)

	lathe = Lathe.new()
	lathe.conventional = true
	lathe.position = Vector3(0, 0, -2.0)
	add_child(lathe)

	mill = Mill.new()
	mill.position = Vector3(6.85, 0, -3.1)
	add_child(mill)

	office_pc = OfficePC.new()
	office_pc.position = Workshop.OFFICE_PC_POS
	add_child(office_pc)

	player = Player.new()
	player.position = Vector3(0.5, 0.05, 2.5)
	add_child(player)

	hud = HUD.new()
	hud.lathe = lathe
	add_child(hud)

	_add_mount(lathe)
	_add_mount(mill)
	layout.site = site
	player.held_changed.connect(hud.set_held)

	mill_hud = MillHUD.new()
	mill_hud.mill = mill
	add_child(mill_hud)

	build_menu = BuildMenu.new()
	build_menu.world = self
	add_child(build_menu)

	rack_menu = RackMenu.new()
	rack_menu.world = self
	add_child(rack_menu)

	job_menu = JobMenu.new()
	job_menu.world = self
	add_child(job_menu)

	pause_menu = PauseMenu.new()
	pause_menu.world = self
	add_child(pause_menu)

	clamp_dialog = ClampDialog.new()
	clamp_dialog.world = self
	add_child(clamp_dialog)

	drawing = DrawingOverlay.new()
	drawing.world = self
	add_child(drawing)

	player.prompt_changed.connect(hud.set_prompt)
	_wire_lathe(lathe)
	_wire_mill(mill, mill_hud)
	office_pc.using_changed.connect(func(on: bool): hud.visible = not on)
	office_pc.overlay.raw.shop = self
	office_pc.overlay.stock_view.shop = self
	office_pc.overlay.site_tab.shop = self
	office_pc.overlay.shop_tab.shop = self
	office_pc.overlay.machines_tab.shop = self
	office_pc.overlay.tool_tab.shop = self
	office_pc.overlay.jobs_tab.shop = self
	office_pc.overlay.waste_tab.shop = self
	office_pc.overlay.skill_app.shop = self
	office_pc.overlay.reputation_app.shop = self
	office_pc.overlay.world = self
	player.material_to_machine.connect(ask_clamp)
	player.gate = _work_blocked
	office_pc.overlay.day_app.shop = self
	office_pc.overlay.dev_app.shop = self
	Settings.changed.connect(_apply_quality)

	_apply_pending(GameState.pending)
	_apply_quality()
	_setup_ambient()
	restore_mouse()
	if company.owns("lathe"):
		hud.show_message("Willkommen in der Werkstatt, %s! Drehmaschine, Werkbank mit Grundwerkzeugen, Bandsäge und ein Regal mit einer Stange stehen bereit. Starte den Tag am PC im Büro, im Programm Tagesbericht." % save_name, Color(0.9, 0.95, 1.0))
	else:
		hud.show_message("Willkommen in der Werkstatt, %s! Die Halle ist leer: Am PC im Büro gibt es die erste Drehmaschine und die Bandsäge gratis, dazu Werkbank, Werkzeuge und Aufträge." % save_name, Color(0.9, 0.95, 1.0))


## Drehmaschine oder Rundschleifmaschine an HUD und Aufträge anschließen.
func _wire_lathe(m: Lathe) -> void:
	m.message.connect(hud.show_message)
	m.operating_changed.connect(func(on: bool):
		hud.use_lathe(m)
		_refresh_hud()
		hud.set_operating(on)
		if m.grinder_type != "":
			_hint_grinder(on, m)
		else:
			_hint_empty(on, m.has_part, _lathe_need())
			_hint_tool(on, m))
	m.levers_changed.connect(func(on: bool):
		hud.use_lathe(m)
		hud.set_levers(m, on))
	m.tool_lost.connect(_on_tool_lost.bind(m.MACHINE_ID))
	if m.grinder_type != "":
		m.submit_requested.connect(_on_grind_submit.bind(m))
		m.new_part_requested.connect(_on_grind_new_part)
	else:
		m.submit_requested.connect(_on_submit.bind(m))
		m.new_part_requested.connect(_on_new_part.bind(m))


## Fräs-, Bohr- oder Flachschleifmaschine an ihre eigene Anzeige und die Aufträge anschließen.
func _wire_mill(m: Mill, mh: MillHUD) -> void:
	m.message.connect(hud.show_message)
	m.operating_changed.connect(mh.set_operating)
	m.operating_changed.connect(hud.set_other_machine)
	m.levers_changed.connect(mh.set_levers_open)
	m.levers_changed.connect(hud.set_other_machine)
	m.tool_lost.connect(_on_tool_lost.bind(m.MACHINE_ID))
	if m.grinder_type != "":
		m.operating_changed.connect(func(on: bool): _hint_grinder(on, m))
		m.submit_requested.connect(_on_grind_submit.bind(m))
		m.new_part_requested.connect(_on_grind_new_part)
	else:
		m.operating_changed.connect(func(on: bool): _hint_empty(on, m.has_part, _need_of(JobBoard.key(m.MACHINE_ID, _active_index(m.MACHINE_ID)))); _hint_tool(on, m))
		m.submit_requested.connect(_on_mill_submit.bind(m))
		m.new_part_requested.connect(_on_mill_new_part.bind(m))


func _hint_grinder(on: bool, m: Node) -> void:
	if on and not m.has_part:
		hud.show_message("Schleifmaschine: spannt nur vorbearbeitete Teile. Auftrag mit Schleifanforderung abgeben, Teil herbringen und mit Linksklick einspannen.", Color(1, 0.75, 0.2))


func _add_mount(machine: Node) -> void:
	var mount := ToolMount.new()
	mount.machine = machine
	mount.player = player
	machine.add_child(mount)
	machine.tool_mount = mount


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	# Himmel über dem Hof. Er spiegelt sich nicht in den Maschinen und beleuchtet die Halle nicht.
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.84)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.03
	env.adjustment_enabled = true
	we.environment = env
	add_child(we)

	probe = ReflectionProbe.new()
	probe.size = Vector3(24, 6.5, 16)
	probe.position = Vector3(0, 3.0, 0)
	probe.box_projection = true
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)


func _apply_quality() -> void:
	var q := int(Settings.graphics["quality"])
	env.ssao_enabled = q >= 1
	env.ssao_intensity = 1.6
	env.ssr_enabled = q >= 2
	env.ssil_enabled = q >= 3
	Settings.apply_bloom(env)
	env.adjustment_brightness = float(Settings.graphics["brightness"])
	for l in _lights.get("shadow_lights", []):
		(l as Light3D).shadow_enabled = q >= 2
	lathe.lamp.shadow_enabled = q >= 1
	mill.lamp.shadow_enabled = q >= 2
	probe.visible = q >= 1


func _process(delta: float) -> void:
	play_time += delta
	_advance_day(delta)
	_fill_ambient()


# ------------------------------------------------------------ Aufträge

func _current_job() -> Dictionary:
	return Jobs.get_job(job_index)


func mill_job() -> Dictionary:
	return MillJobs.get_job(mill_job_index)


# ------------------------------------------------------------ Tage und Ansehen

func _advance_day(delta: float) -> void:
	if day_started and not day_over:
		day_time += delta
		if day_time >= DAY_SECONDS:
			end_day()
	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = 1.0
		_show_clock()


## Uhrzeit: Der Arbeitstag läuft von 7 bis 17 Uhr.
func clock_text() -> String:
	var minutes := 7 * 60 + int(clampf(day_time / DAY_SECONDS, 0.0, 1.0) * 600.0)
	return "Tag %d   %02d:%02d" % [day, minutes / 60, minutes % 60]


func _show_clock() -> void:
	var text := clock_text()
	if not day_started:
		text += "   Tag noch nicht gestartet: am PC im Programm Tagesbericht"
	elif day_over:
		text += "   FEIERABEND: am PC den Tag beenden"
	hud.set_clock(text, day_over)


## Tag ist um: Das laufende Teil lässt sich noch fertigstellen, sonst geht nichts Neues mehr.
func end_day() -> void:
	if day_over:
		return
	day_over = true
	_show_clock()
	hud.show_message("Feierabend: Das laufende Teil lässt sich noch abgeben, neue Aufträge und Einkäufe gibt es erst morgen. Tag am PC beenden.", Color(1, 0.75, 0.3))
	office_pc.overlay.refresh_all()


## Tag starten: Erst jetzt lässt sich arbeiten und bestellen, die Uhr läuft.
func start_day() -> void:
	day_started = true
	_show_clock()
	_jobs_changed()
	hud.show_message("Tag %d beginnt." % day, Color(0.9, 0.95, 1.0))


## Nächster Tag: Abgelaufene Fristen kosten Ansehen. Der neue Tag wartet, bis er gestartet wird.
func next_day() -> void:
	day += 1
	day_time = 0.0
	day_over = false
	day_started = false
	last_day_stats = day_stats
	day_stats = {}
	_check_deadlines()
	_show_clock()
	_jobs_changed()
	hud.show_message("Tag %d: am PC im Programm Tagesbericht starten." % day, Color(0.9, 0.95, 1.0))


## Darf der Spieler dieses Ziel gerade benutzen? Vor Tagesbeginn wird nichts bearbeitet. silent: nur prüfen.
func _work_blocked(target: Node, silent: bool) -> bool:
	if day_started or free_mode or target == null:
		return false
	if not (target is Lathe or target is Mill or target is BandSaw or target is ToolMount or target is Lathe.LeverTarget or target is MillLeverPanel):
		return false
	if not silent:
		hud.show_message("Der Tag hat noch nicht begonnen: am PC im Programm Tagesbericht starten.", Color(1, 0.75, 0.2))
	return true


func _check_deadlines() -> void:
	for key in deadlines.keys():
		if day > int(deadlines[key]):
			_job_late(str(key))


## Frist verpasst: Der Auftrag ist weg, mit ihm das Teil, das noch auf Schleifen wartet.
func _job_late(key: String) -> void:
	var job := JobBoard.job_of(key)
	company.change_reputation(REP_LATE, day, "Frist verpasst: %s" % job["title"])
	hud.show_message("Frist verpasst: %s. Das Ansehen sinkt." % job["title"], Color(1, 0.5, 0.4))
	accepted.erase(key)
	grind_jobs.erase(key)
	deadlines.erase(key)
	_job_gone(key)
	if str(player.carry.get("key", "")) == key:
		player.clear_carry()
	for i in range(deliveries.size() - 1, -1, -1):
		if str(deliveries[i].get("key", "")) == key:
			deliveries.remove_at(i)
	_deliveries_changed()
	for m in _work_machines():
		if m.semi_key == key:
			_clear_grinder(m)


## Einkaufen und Annehmen sind am Feierabend gesperrt, außer im Testmodus.
func _closed_error() -> String:
	if free_mode:
		return ""
	if not day_started:
		return "Der Tag hat noch nicht begonnen: am PC im Programm Tagesbericht starten."
	return "Feierabend: Erst morgen wieder. Tag am PC beenden." if day_over else ""


## Vergütung nach Ansehen.
func _pay(base: float) -> int:
	return int(round(base * company.pay_factor()))


## Aufträge im System: nur freigeschaltete Maschinen und Werkstoffe, je Maschine höchstens 2 zusammen mit
## den schon angenommenen, insgesamt höchstens 9. Auswahl und Reihenfolge sind zufällig und wechseln mit dem Tag.
func offers() -> Array:
	var out := []
	var taken := {}
	for k in accepted + grind_jobs:
		var mk := JobBoard.machine_of(str(k))
		taken[mk] = int(taken.get(mk, 0)) + 1
	var groups := {}
	for k in JobBoard.all_keys():
		if accepted.has(k) or grind_jobs.has(k) or not JobBoard.unlocked(k, company):
			continue
		var mk := JobBoard.machine_of(k)
		if not groups.has(mk):
			groups[mk] = []
		groups[mk].append(k)
	for mk in groups:
		var list := _shuffled(groups[mk], "%d|%s" % [day, mk])
		var room := mini(JobBoard.MAX_PER_MACHINE - int(taken.get(mk, 0)), list.size())
		for i in maxi(room, 0):
			out.append(list[i])
	return _shuffled(out, str(day)).slice(0, maxi(JobBoard.MAX_TOTAL - (accepted.size() + grind_jobs.size()), 0))


## Zufällige Reihenfolge, die innerhalb eines Tages gleich bleibt.
static func _shuffled(list: Array, salt: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(salt)
	var out := list.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var k := rng.randi_range(0, i)
		var t = out[i]
		out[i] = out[k]
		out[k] = t
	return out


## Grund, warum dieser Auftrag jetzt nicht angenommen werden kann. Leer = geht.
func accept_error(key: String) -> String:
	var closed := _closed_error()
	if closed != "":
		return closed
	if accepted.has(key) or grind_jobs.has(key):
		return "Dieser Auftrag ist schon angenommen."
	var machine := JobBoard.machine_of(key)
	var count := 0
	for k in accepted + grind_jobs:
		if JobBoard.machine_of(str(k)) == machine:
			count += 1
	if count >= JobBoard.MAX_PER_MACHINE:
		return "Für diese Maschine laufen schon %d Aufträge." % JobBoard.MAX_PER_MACHINE
	if accepted.size() + grind_jobs.size() >= JobBoard.MAX_TOTAL:
		return "Es laufen schon %d Aufträge." % JobBoard.MAX_TOTAL
	return JobBoard.lock_reason(key, company)


## Ist für diese Maschine der gewählte Auftrag angenommen?
func has_job(machine: String) -> bool:
	return accepted.has(JobBoard.key(machine, _active_index(machine)))


## Gewählter Auftrag einer Maschinenart. Beide Drehmaschinen teilen sich einen.
func _active_index(machine: String) -> int:
	match machine:
		"lathe", "cnc_lathe":
			return job_index
		"drill":
			return drill_job_index
	return mill_job_index


func _active_job(machine: String) -> Dictionary:
	var kind := "lathe" if machine == "cnc_lathe" else machine
	return JobBoard.job_of(JobBoard.key(kind, _active_index(kind)))


## Auftrag annehmen. Gibt einen Fehlertext zurück, leer = angenommen.
func accept_job(key: String) -> String:
	var reason := accept_error(key)
	if reason != "":
		return reason
	deadlines[key] = day + JobBoard.days_for(key)
	day_stats["accepted"] = int(day_stats.get("accepted", 0)) + 1
	# Kundenauftrag: Das Teil kommt mit und steht gleich vor dem Lagertor
	if JobBoard.key_machine(key) == "ceramic":
		grind_jobs.append(key)
		deliveries.append(CeramicJobs.delivery_of(key, JobBoard.job_of(key)))
		_deliveries_changed()
		_jobs_changed()
		return ""
	accepted.append(key)
	# An einer Maschine ohne Auftrag gilt der neue sofort, oben rechts steht er, wenn dort nichts steht
	var machine := JobBoard.key_machine(key)
	if not has_job(machine):
		_set_active(key)
	if tracked == "":
		tracked = key
	_jobs_changed()
	return ""


## Auftrag wieder abgeben, ohne Folgen.
func return_job(key: String) -> void:
	accepted.erase(key)
	deadlines.erase(key)
	_job_gone(key)
	_jobs_changed()


## Auswahl auf der Taste Tab: Dieser Auftrag steht oben rechts und gilt für seine Maschine.
func select_job(key: String) -> void:
	if not accepted.has(key):
		return
	tracked = key
	_set_active(key)
	_jobs_changed()


func _set_active(key: String) -> void:
	match JobBoard.key_machine(key):
		"lathe":
			job_index = JobBoard.key_index(key)
		"drill":
			drill_job_index = JobBoard.key_index(key)
		_:
			mill_job_index = JobBoard.key_index(key)


## Ein Auftrag ist weg: Anzeige und Maschine rücken auf den nächsten angenommenen.
func _job_gone(key: String) -> void:
	if tracked == key:
		tracked = str(accepted[0]) if not accepted.is_empty() else ""
	var machine := JobBoard.key_machine(key)
	if machine == "ceramic":
		return
	for k in accepted:
		if JobBoard.key_machine(str(k)) == machine:
			_set_active(str(k))
			return


## Erfolgreich abgegeben: Erfahrung gutschreiben, Auftrag ist erledigt. Gibt den Text fürs Protokoll zurück.
func _finish_job(key: String) -> String:
	day_stats["done"] = int(day_stats.get("done", 0)) + 1
	var skills := company.skills
	var before := skills.free_points()
	var xp := JobBoard.xp_for(JobBoard.job_of(key))
	skills.xp += xp
	accepted.erase(key)
	deadlines.erase(key)
	_job_gone(key)
	company.change_reputation(REP_DONE, day, "Abgeschlossen: %s" % JobBoard.job_of(key)["title"])
	var text := "\n\nErfahrung: +%d" % xp
	var gained := skills.free_points() - before
	if gained > 0:
		text += "\nNeuer Skillpunkt! Am PC im Programm Skilltree einsetzen."
	if accepted.is_empty():
		text += "\nKein Auftrag mehr offen: am PC im Büro einen neuen annehmen."
	return text


func _jobs_changed() -> void:
	_refresh_hud()
	office_pc.overlay.refresh_all()


## Stand beim Material für den Auftrag der gewählten Maschine.
func job_status(category: String) -> String:
	if JobBoard.JOB_MACHINES.has(category):
		return job_status_of(JobBoard.key(category, _active_index(category)))
	return ""


## Stand beim Material für einen Auftrag, für das Auftragsmenü.
func job_status_of(key: String) -> String:
	var job := JobBoard.job_of(key)
	if JobBoard.key_machine(key) == "lathe":
		return _material_status(lathe.has_part and lathe.material == str(job["material"]) and lathe.is_untouched(),
			_find_lathe_stock(job) >= 0, _need_of(key))
	var in_crate := false
	for c in layout.crates:
		for it in c["items"]:
			in_crate = in_crate or _match_mill_job(it, job, false) > 0
	var m: Mill = _machine_node(JobBoard.key_machine(key))
	return _material_status(m != null and m.has_part and m.material == str(job["material"]) and m.untouched,
		in_crate or _find_mill_stock(job) >= 0, _need_of(key))


func _material_status(clamped: bool, stored: bool, need: String) -> String:
	if clamped:
		return "Material: Rohteil ist eingespannt."
	if stored:
		return "Material: liegt bereit. Am Regal oder aus der Kiste nehmen, ganze Stangen an der Bandsäge absägen und mit Linksklick an der Maschine einspannen."
	if not deliveries.is_empty():
		return "Material: Lieferungen stehen vor dem Lager-Rolltor, erst einlagern. Benötigt: %s." % need
	return "Material fehlt, am PC im Büro kaufen: %s." % need


func _refresh_hud() -> void:
	hud.set_money(money, parts)
	var sk := company.skills
	var prog := sk.progress()
	hud.set_skill_info("Erfahrung %d / %d    |    Skillpunkte: %d" % [prog.x, prog.y, sk.free_points()])
	var corner := "Kein Auftrag gewählt.\nAm PC im Büro annehmen, mit [%s] auswählen." % Settings.binding_text("job_menu")
	if tracked != "":
		corner = JobBoard.describe_key(tracked, company)
	var detail := "Kein Drehauftrag angenommen. Aufträge gibt es am PC im Büro."
	if has_job("lathe"):
		detail = Jobs.describe(_current_job(), JobBoard.grind_active(_current_job(), company))
	hud.set_job(corner, detail)
	var lathe_job := _hud_lathe_job()
	hud.set_job_data(lathe_job, hud.lathe != null and hud.lathe.grinder_type != "" or JobBoard.grind_active(lathe_job, company))
	if has_job("mill"):
		mill_hud.set_job(mill_job(), JobBoard.grind_active(mill_job(), company))
	else:
		mill_hud.set_no_job()
	for id in mill_huds:
		var mh: MillHUD = mill_huds[id]
		var m: Mill = extra_machines[id]
		if m.grinder_type != "":
			if m.semi_key != "":
				mh.set_job(JobBoard.job_of(m.semi_key), true)
			else:
				mh.set_no_job("Kein vorbearbeitetes Teil eingespannt.")
		elif has_job(id):
			mh.set_job(_active_job(id))
		else:
			mh.set_no_job("Kein Bohrauftrag angenommen. Aufträge gibt es am PC im Büro.")


## Auftrag der Drehmaschine im HUD. An der Rundschleifmaschine das eingespannte Teil.
func _hud_lathe_job() -> Dictionary:
	if hud.lathe != null and hud.lathe.grinder_type != "":
		return JobBoard.job_of(hud.lathe.semi_key) if hud.lathe.semi_key != "" else {}
	return _current_job() if has_job("lathe") else {}


## Zeichnung: Auftrag der Maschine, an der gearbeitet wird, sonst der oben rechts gewählte.
func drawing_job() -> Dictionary:
	var op: Node = player.operating
	if op is Lathe or op is Mill:
		if op.grinder_type != "":
			return JobBoard.job_of(op.semi_key) if op.semi_key != "" else {}
		var id: String = op.MACHINE_ID
		var category := "lathe" if op is Lathe else id
		if has_job(category):
			return _current_job() if op is Lathe else _active_job(id)
		return {}
	return JobBoard.job_of(tracked) if tracked != "" else {}


func _mill_new_workpiece(m: Mill = null) -> void:
	if m == null:
		m = mill
	var job := _active_job(m.MACHINE_ID)
	var s: Array = job["size"]
	m.set_material(str(job.get("material", Materials.DEFAULT)))
	m.new_workpiece(s[0], s[1], s[2])


func _on_mill_new_part(m: Mill = null) -> void:
	hud.show_message(_mill_take_part(m), Color(0.9, 0.95, 1.0))
	_refresh_hud()


func _on_mill_submit(m: Mill = null) -> void:
	if m == null:
		m = mill
	if not m.has_part:
		hud.show_message("Es ist kein Rohteil eingespannt.", Color(1, 0.75, 0.2))
		return
	if m.untouched:
		hud.show_message("Das Rohteil ist noch unbearbeitet.", Color(1, 0.75, 0.2))
		return
	var id: String = m.MACHINE_ID
	if not has_job(id):
		hud.show_message("Kein %s angenommen. Aufträge gibt es am PC im Büro." % JobBoard.MACHINE_NAMES[id], Color(1, 0.75, 0.2))
		return
	var job := _active_job(id)
	var res := m.evaluate(job)
	var score := _material_score(float(res["score"]), m.material, job)
	var to_grind: bool = score >= 0.999 and JobBoard.grind_active(job, company)
	if to_grind and not player.hands_free():
		hud.show_message("Das Teil muss zum Schleifen getragen werden: erst die Hände frei machen.", Color(1, 0.75, 0.2))
		return
	var pay := 0
	var verdict := "Ausschuss! Keine Vergütung."
	if score >= 0.999:
		pay = _pay(float(job["reward"]))
		verdict = "Alle Maße in Toleranz - sehr gut!"
	elif score >= 0.5:
		pay = _pay(float(job["reward"]) * score * 0.5)
		verdict = "Nacharbeit nötig - Teilvergütung."
	money += pay
	parts += 1
	var lines: Array = res["lines"]
	var text := "PRÜFPROTOKOLL - %s\n\n%s\n\n%d / %d Merkmale in Ordnung\n%s\nVergütung: %d EUR" % [
		job["title"], "\n".join(lines), int(res["ok"]), int(res["total"]), verdict, pay]
	var key := JobBoard.key(id, _active_index(id))
	if to_grind:
		text += _send_to_grinding(key, m)
	elif score >= 0.999:
		text += _finish_job(key)
	hud.show_result(text)
	# Das fertige Teil ist weg. Das nächste Rohteil holt der Spieler selbst aus dem Lager.
	m.set_material(str(_active_job(id)["material"]))
	m.clear_workpiece()
	hud.show_message("Schraubstock ist leer: Material für den nächsten Auftrag aus dem Lager holen.", Color(0.9, 0.95, 1.0))
	_jobs_changed()


func _lathe_new_workpiece(m: Lathe = null) -> void:
	if m == null:
		m = lathe
	var job := _current_job()
	m.set_material(str(job.get("material", Materials.DEFAULT)))
	m.new_workpiece(float(job["stock_d"]), float(job["stock_len"]))


func _on_new_part(m: Lathe = null) -> void:
	hud.show_message(_lathe_take_part(m), Color(0.9, 0.95, 1.0))
	_refresh_hud()


func _on_submit(m: Lathe = null) -> void:
	if m == null:
		m = lathe
	if not m.has_part:
		hud.show_message("Es ist kein Rohteil eingespannt.", Color(1, 0.75, 0.2))
		return
	if m.is_untouched():
		hud.show_message("Das Rohteil ist noch unbearbeitet.", Color(1, 0.75, 0.2))
		return
	if not has_job("lathe"):
		hud.show_message("Kein Drehauftrag angenommen. Aufträge gibt es am PC im Büro.", Color(1, 0.75, 0.2))
		return
	var job := _current_job()
	var res := m.evaluate(job)
	var score := _material_score(float(res["score"]), m.material, job)
	var to_grind: bool = score >= 0.999 and JobBoard.grind_active(job, company)
	if to_grind and not player.hands_free():
		hud.show_message("Das Teil muss zum Schleifen getragen werden: erst die Hände frei machen.", Color(1, 0.75, 0.2))
		return
	var pay := 0
	var verdict := ""
	if score >= 0.999:
		pay = _pay(float(job["reward"]))
		verdict = "Alle Maße in Toleranz - sehr gut!"
	elif score >= 0.5:
		pay = _pay(float(job["reward"]) * score * 0.5)
		verdict = "Nacharbeit nötig - Teilvergütung."
	else:
		verdict = "Ausschuss! Keine Vergütung."
	money += pay
	parts += 1
	var lines: Array = res["lines"]
	var text := "PRÜFPROTOKOLL - %s\n\n%s\n\n%d / %d Merkmale in Ordnung\n%s\nVergütung: %d EUR" % [
		job["title"], "\n".join(lines), int(res["ok"]), int(res["total"]), verdict, pay]
	var key := JobBoard.key("lathe", job_index)
	if to_grind:
		text += _send_to_grinding(key, m)
	elif score >= 0.999:
		text += _finish_job(key)
	hud.show_result(text)
	# Das fertige Teil ist weg. Das nächste Rohteil holt der Spieler selbst aus dem Lager.
	m.set_material(str(_current_job()["material"]))
	m.clear_workpiece()
	hud.show_message("Futter ist leer: Material für den nächsten Auftrag aus dem Lager holen.", Color(0.9, 0.95, 1.0))
	_jobs_changed()


# ------------------------------------------------------------ Schleifen

## Vorbearbeitet und bezahlt: Das Teil kommt in die Hände und muss noch zur Schleifmaschine. Die Erfahrung
## gibt es erst, wenn der ganze Auftrag fertig ist.
func _send_to_grinding(key: String, m: Node) -> String:
	var job := JobBoard.job_of(key)
	accepted.erase(key)
	_job_gone(key)
	grind_jobs.append(key)
	player.set_carry({"kind": "semi", "key": key, "type": job["grind"]["type"], "title": job["title"], "part": m.part_state()})
	var grinder: String = Layout.SPECS[JobBoard.GRINDERS[job["grind"]["type"]]]["title"]
	# Die Frist läuft weiter, bis auch geschliffen ist
	return "\n\nDas Teil muss noch auf die %s: %s.\nEs liegt in deinen Händen." % [grinder, JobBoard.grind_line(job)]


## Vorbearbeitetes Teil an der Schleifmaschine einspannen. Fehlertext, leer = eingespannt.
func _clamp_semi(machine: Node) -> String:
	var item: Dictionary = player.carry
	var want: String = JobBoard.GRINDERS[item["type"]]
	if machine.get("MACHINE_ID") != want:
		var wrong := "Dieses Teil gehört auf die %s." % Layout.SPECS[want]["title"]
		hud.show_message(wrong, Color(1, 0.75, 0.2))
		return wrong
	if machine.spindle_speed > 5.0:
		var busy := "Erst die Spindel stoppen."
		hud.show_message(busy, Color(1, 0.75, 0.2))
		return busy
	if machine.has_part:
		var full := "Es ist schon ein Teil eingespannt."
		hud.show_message(full, Color(1, 0.75, 0.2))
		return full
	var mix := _tray_conflict(machine, str(item["part"]["material"]))
	if mix != "":
		hud.show_message(mix, Color(1, 0.75, 0.2))
		return mix
	machine.load_part(item["part"])
	machine.semi_key = str(item["key"])
	player.clear_carry()
	hud.show_message("Eingespannt: %s." % JobBoard.grind_line(JobBoard.job_of(machine.semi_key)), Color(0.7, 0.95, 1.0))
	_refresh_hud()
	return ""


func _on_grind_new_part() -> void:
	hud.show_message("Schleifmaschinen spannen nur vorbearbeitete Teile: Auftrag mit Schleifanforderung abgeben, Teil herbringen und mit Linksklick einspannen.", Color(0.9, 0.95, 1.0))


## Geschliffenes Teil abgeben. Passt die Fläche noch nicht, darf weitergeschliffen werden. Sind die Maße
## verschliffen, ist das Teil Ausschuss und der Auftrag ohne Schleifvergütung beendet.
func _on_grind_submit(m: Node) -> void:
	if not m.has_part or m.semi_key == "":
		hud.show_message("Es ist kein vorbearbeitetes Teil eingespannt.", Color(1, 0.75, 0.2))
		return
	var key: String = m.semi_key
	var job := JobBoard.job_of(key)
	var g: Dictionary = job["grind"]
	var res: Dictionary = m.evaluate_grind(job)
	var lines: Array = res["lines"]
	var ok_all: bool = int(res["ok"]) == int(res["total"])
	var measures_ok: bool = int(res["ok"]) >= int(res["total"]) - 1 and str(lines[lines.size() - 1]).begins_with("FEHL")
	var head := "PRÜFPROTOKOLL SCHLEIFEN - %s\n\n%s\n\n" % [job["title"], "\n".join(lines)]
	if ok_all:
		var pay := _pay(float(g["reward"]))
		money += pay
		parts += 1
		var text := head + "Fläche in Ordnung - sehr gut!\nVergütung: %d EUR" % pay
		grind_jobs.erase(key)
		text += _finish_job(key)
		hud.show_result(text)
		_clear_grinder(m)
	elif measures_ok:
		hud.show_result(head + "Die Fläche ist noch nicht fertig: weiterschleifen, zuletzt fein zustellen und langsam fahren.")
	else:
		grind_jobs.erase(key)
		deadlines.erase(key)
		company.change_reputation(REP_SCRAP, day, "Ausschuss: %s" % job["title"])
		hud.show_result(head + "Maße verschliffen: Ausschuss! Keine Schleifvergütung.")
		_clear_grinder(m)
	_jobs_changed()


func _clear_grinder(m: Node) -> void:
	m.semi_key = ""
	m.ceramic_part = false
	m.clear_workpiece()


## Falscher Werkstoff ist Ausschuss, egal wie gut die Maße sind.
func _material_score(score: float, used: String, job: Dictionary) -> float:
	var want := str(job.get("material", Materials.DEFAULT))
	if used == want:
		return score
	hud.show_message("Falscher Werkstoff: %s statt %s!" % [Materials.label(used), Materials.label(want)], Color(1, 0.45, 0.35))
	return 0.0


# ------------------------------------------------------------ Rohmaterial

## Taste ^ schaltet den Testmodus um. Auf deutschen Tastaturen ist ^ eine Tottaste, darum auch nach Lage.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode != KEY_ASCIICIRCUM and event.key_label != KEY_ASCIICIRCUM and event.physical_keycode != KEY_QUOTELEFT:
		return
	# Beim Eintippen von Werten oder NC-Programmen schaltet die Taste nichts um
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or lathe.typing() or (cnc_lathe != null and cnc_lathe.typing()):
		return
	set_free_mode(not free_mode)
	get_viewport().set_input_as_handled()


func set_free_mode(on: bool) -> void:
	free_mode = on
	hud.set_free_mode(on)
	office_pc.overlay.refresh_all()


## Werkzeug zerstört oder verschlissen: Es ist weg und muss am PC neu gekauft werden.
func _on_tool_lost(_price: int, tool_name: String, _machine: String) -> void:
	hud.append_message("%s ist hin: am PC im Shop neu kaufen." % tool_name)
	office_pc.overlay.tool_tab.refresh()


func _hint_tool(on: bool, machine: Node) -> void:
	if on and machine.has_part and not machine.has_cutter():
		hud.show_message("Kein Werkzeug eingesetzt: am PC kaufen, an der Werkbank nehmen und mit Linksklick einsetzen.", Color(1, 0.75, 0.2))


## Preis eines Werkzeugs nach Schneidstoff und Skills.
func tool_price(machine: String, id: String, grade: String) -> int:
	if Wheels.WIDTHS.has(machine):
		return int(Wheels.by_id(machine, id)["price"])
	var base: int = lathe.INSERT_PRICE if machine == "lathe" or machine == "cnc_lathe" else int(MillTools.by_id(id)["price"])
	return maxi(int(round(base * company.skills.tool_price_factor(machine, grade))), 1)


## Werkzeug kaufen, es liegt dann auf der Werkbank. Je Werkzeug höchstens 5 Stück. Fehlertext, leer = gekauft.
func buy_tool(machine: String, id: String, grade: String) -> String:
	var closed := _closed_error()
	if closed != "":
		return closed
	var sk := company.skills
	if Wheels.WIDTHS.has(machine):
		var need := str(Wheels.TYPES[Wheels.by_id(machine, id)["type"]]["skill"])
		if need != "" and not sk.has(need):
			return "Erst im Skilltree freischalten: %s." % Skills.title_of(need)
		grade = "wheel"
	if not sk.has(Skills.machine_skill(machine)):
		return "Erst im Skilltree freischalten: %s." % Skills.title_of(Skills.machine_skill(machine))
	if grade == "hss" and not sk.has("%s_hss" % Skills.tool_family(machine)):
		return "HSS erst im Skilltree freischalten."
	if company.tools[machine].count(id) >= ToolStore.MAX_COPIES:
		return "Mehr als %d Stück von einem Werkzeug passen nicht." % ToolStore.MAX_COPIES
	var bench := _bench_of(machine)
	if bench != null and company.tools[machine].total() >= bench.holders.size():
		return "Alle %d Halterungen der Werkbank sind voll." % bench.holders.size()
	var cost: int = 0 if free_mode else tool_price(machine, id, grade)
	if cost > money:
		return "Nicht genug Geld: %d EUR nötig, %d EUR vorhanden." % [cost, money]
	money -= cost
	company.tools[machine].add(id, grade)
	_apply_skills()
	_refresh_hud()
	return ""


## Eingesetzte Werkstoffe dürfen die Späne in der Wanne nicht mischen. Fehlertext, leer = geht.
func _tray_conflict(machine: Node, material: String) -> String:
	var sort := str(ChipTray.SORTS.get(Materials.group_of(material)["id"], "stahl"))
	if machine.tray.takes(sort):
		return ""
	return "Erst die Spänewanne leeren: Darin liegen %sspäne, %sspäne dürfen nicht dazu." % [ChipTray.SORT_TITLES[machine.tray.sort()], ChipTray.SORT_TITLES[sort]]
	_refresh_hud()


func _hint_empty(on: bool, has_part: bool, need: String) -> void:
	if on and not has_part and free_mode:
		hud.show_message("Kein Rohteil eingespannt. Testmodus: [%s] spannt %s gratis ein." % [
			Settings.binding_text("new_workpiece"), need], Color(1, 0.75, 0.2))
		return
	if on and not has_part:
		if has_job("lathe") and money < _job_cost("lathe") and deliveries.is_empty() and stock.is_empty():
			hud.show_message("Kein Rohteil eingespannt. Das Geld reicht nicht für Material: [%s] drücken, dann stellt der Kunde das Rohteil." % Settings.binding_text("new_workpiece"), Color(1, 0.75, 0.2))
			return
		hud.show_message("Kein Rohteil eingespannt. Benötigt: %s. Aus dem Lager holen, an der Bandsäge absägen und mit Linksklick einspannen." % need, Color(1, 0.75, 0.2))


func _lathe_need() -> String:
	var job := _current_job()
	return "Rund Ø%d x %d mm aus %s" % [int(job["stock_d"]), int(job["stock_len"]), Materials.label(str(job["material"]))]


func _mill_need() -> String:
	var job := MillJobs.get_job(mill_job_index)
	var s: Array = job["size"]
	return "%d x %d x %d mm aus %s" % [int(s[0]), int(s[1]), int(s[2]), Materials.label(str(job["material"]))]


func _need_of(key: String) -> String:
	var job := JobBoard.job_of(key)
	if JobBoard.key_machine(key) == "lathe":
		return "Rund Ø%d x %d mm aus %s" % [int(job["stock_d"]), int(job["stock_len"]), Materials.label(str(job["material"]))]
	var s: Array = job["size"]
	return "%d x %d x %d mm aus %s" % [int(s[0]), int(s[1]), int(s[2]), Materials.label(str(job["material"]))]


## Was die angenommenen Aufträge brauchen, für die Anzeige am PC.
func job_needs() -> String:
	if accepted.is_empty():
		return "Noch kein Auftrag angenommen."
	var lines: Array[String] = []
	for k in accepted:
		lines.append("%s: %s" % [JobBoard.MACHINE_NAMES[JobBoard.key_machine(str(k))], _need_of(str(k))])
	return "\n".join(lines)


## Bestellvorschlag für den laufenden Auftrag: Rundstange oder Fertigschnitt.
func job_spec(machine: String) -> Dictionary:
	if machine == "lathe":
		var job := _current_job()
		return {"kind": Materials.KIND_ROUND, "material": str(job["material"]), "d": float(job["stock_d"]), "w": 0.0, "h": 0.0, "l": Materials.BAR_LEN}
	var mj := _active_job(machine)
	var s: Array = mj["size"]
	return {"kind": Materials.KIND_CUT, "material": str(mj["material"]), "d": 0.0, "w": float(s[1]), "h": float(s[2]), "l": float(s[0])}


## Billigster Weg zum Material für den laufenden Auftrag.
func _job_cost(machine: String) -> int:
	var sp := job_spec(machine)
	return Materials.price(str(sp["material"]), str(sp["kind"]), float(sp["d"]), float(sp["w"]), float(sp["h"]), float(sp["l"]))


## Passendes Stück im Lager für den Drehauftrag: dünnste Stange, die reicht. -1 = keine.
func _find_lathe_stock(job := {}) -> int:
	if job.is_empty():
		job = _current_job()
	var best := -1
	for i in stock.size():
		var it: Dictionary = stock[i]
		if str(it["kind"]) != Materials.KIND_ROUND or str(it["material"]) != str(job["material"]):
			continue
		if float(it["d"]) < float(job["stock_d"]) or float(it["l"]) < float(job["stock_len"]):
			continue
		if best < 0 or float(it["d"]) < float(stock[best]["d"]):
			best = i
	return best


## Passt das Stück zum Fräsauftrag? 2 = Fertigschnitt, 1 = Vierkantstange, 0 = nein.
## turn: Das Stück dabei so drehen, dass die Maße zum Auftrag stimmen.
func _match_mill_job(it: Dictionary, job: Dictionary, turn := true) -> int:
	if str(it["material"]) != str(job["material"]):
		return 0
	var s: Array = job["size"]
	if str(it["kind"]) == Materials.KIND_CUT:
		var want := [float(s[0]), float(s[1]), float(s[2])]
		want.sort()
		var have := [float(it["l"]), float(it["w"]), float(it["h"])]
		have.sort()
		if have != want:
			return 0
		if turn:
			it["l"] = float(s[0])
			it["w"] = float(s[1])
			it["h"] = float(s[2])
		return 2
	if str(it["kind"]) == Materials.KIND_SQUARE and float(it["l"]) >= float(s[0]):
		var section := [float(s[1]), float(s[2])]
		section.sort()
		var have := [float(it["w"]), float(it["h"])]
		have.sort()
		if have != section:
			return 0
		if turn:
			it["w"] = float(s[1])
			it["h"] = float(s[2])
		return 1
	return 0


## Passendes Stück für den Fräsauftrag, Fertigschnitt vor Vierkantstange. -1 = keines.
func _find_mill_stock(job := {}) -> int:
	if job.is_empty():
		job = MillJobs.get_job(mill_job_index)
	var bar := -1
	for i in stock.size():
		var m := _match_mill_job(stock[i], job)
		if m == 2:
			return i
		if m == 1 and bar < 0:
			bar = i
	return bar


## Taste für ein neues Rohteil. Material kommt nur noch per Tragen an die Maschine: Die Taste nennt, wo es
## liegt. Nur im Testmodus und wenn das Geld für Material fehlt, kommt ein Rohteil direkt in die Maschine.
func _lathe_take_part(m: Lathe = null) -> String:
	if m == null:
		m = lathe
	var job := _current_job()
	if m.has_part and m.is_untouched() and m.material == str(job["material"]) \
			and m.stock_d >= float(job["stock_d"]) and m.stock_len >= float(job["stock_len"]):
		return "Das eingespannte Rohteil ist noch unbearbeitet."
	if not has_job("lathe"):
		return "Kein Drehauftrag angenommen. Aufträge gibt es am PC im Büro."
	var mix := _tray_conflict(m, str(job["material"]))
	if mix != "":
		return mix
	if free_mode:
		_lathe_new_workpiece(m)
		return "Testmodus: Rohteil %s gratis eingespannt." % _lathe_need()
	if _find_lathe_stock() >= 0:
		return "Passendes Material liegt im Lager: am Regal nehmen, an der Bandsäge absägen und hier mit Linksklick einspannen."
	if money < _job_cost("lathe") and deliveries.is_empty():
		_lathe_new_workpiece(m)
		return "Das Geld reicht nicht für Material: Der Kunde stellt dieses Rohteil ausnahmsweise bei."
	return _no_stock_message(_lathe_need())


func _mill_take_part(m: Mill = null) -> String:
	if m == null:
		m = mill
	var id: String = m.MACHINE_ID
	var job := _active_job(id)
	var s: Array = job["size"]
	if m.has_part and m.untouched and m.material == str(job["material"]) \
			and m.block_l == float(s[0]) and m.block_w == float(s[1]) and m.block_h == float(s[2]):
		return "Das eingespannte Rohteil ist noch unbearbeitet."
	var need := _need_of(JobBoard.key(id, _active_index(id)))
	if not has_job(id):
		return "Kein %s angenommen. Aufträge gibt es am PC im Büro." % JobBoard.MACHINE_NAMES[id]
	var mix := _tray_conflict(m, str(job["material"]))
	if mix != "":
		return mix
	if free_mode:
		_mill_new_workpiece(m)
		return "Testmodus: Rohteil %s gratis eingespannt." % need
	if _find_mill_stock(job) >= 0:
		return "Passendes Material liegt im Lager: am Regal nehmen und hier mit Linksklick einspannen."
	if money < _job_cost(id) and deliveries.is_empty():
		_mill_new_workpiece(m)
		return "Das Geld reicht nicht für Material: Der Kunde stellt dieses Rohteil ausnahmsweise bei."
	return _no_stock_message(need)


## Bestellung vom PC. Gibt einen Fehlertext zurück, leer = bestellt.
func order_material(spec: Dictionary) -> String:
	var closed := _closed_error()
	if closed != "":
		return closed
	var qty := int(spec.get("qty", 1))
	var node := Skills.material_node(str(spec["material"]))
	if not company.skills.has(node):
		return "Erst im Skilltree freischalten: %s." % Skills.title_of(node)
	if not Storage.fits_empty(spec):
		return "Zu groß für das Lagerregal: Ein Regalplatz misst %d x %d x %d mm." % [int(Storage.BOARD_L), int(Storage.BOARD_D), int(Storage.BOARD_H)]
	var one := Materials.price(str(spec["material"]), str(spec["kind"]), float(spec["d"]), float(spec["w"]), float(spec["h"]), float(spec["l"]))
	var cost := 0 if free_mode else one * qty
	if cost > money:
		return "Nicht genug Geld: %d EUR nötig, %d EUR vorhanden." % [cost, money]
	money -= cost
	for i in qty:
		deliveries.append({"material": spec["material"], "kind": spec["kind"], "d": float(spec["d"]),
			"w": float(spec["w"]), "h": float(spec["h"]), "l": float(spec["l"])})
	_deliveries_changed()
	_refresh_hud()
	return ""


func _deliveries_changed() -> void:
	site.show_deliveries(deliveries)


func _stock_changed() -> void:
	site.show_stock(stock)


## Hinweis beim Anvisieren einer Lieferung im Hof.
func delivery_prompt(i: int) -> String:
	if i < 0 or i >= deliveries.size():
		return ""
	var it: Dictionary = deliveries[i]
	var what := "%s  %s" % [Materials.label(str(it["material"])), RawMaterialTab.describe(it)]
	var same := 0
	for other in deliveries:
		if Site.delivery_key(other) == Site.delivery_key(it):
			same += 1
	if same > 1:
		what += "    |    %d Stück auf der Palette" % same
	if not player.hands_free():
		return "%s    |    Hände voll" % what
	return "[Linksklick] %s aufheben" % what


## Lieferung aufheben. Gibt einen Fehlertext zurück, leer = in den Händen.
func pick_delivery(i: int) -> String:
	if i < 0 or i >= deliveries.size():
		return "Diese Lieferung gibt es nicht mehr."
	if not player.hands_free():
		var full := "Erst die Hände frei machen."
		hud.show_message(full, Color(1, 0.75, 0.2))
		return full
	var item: Dictionary = deliveries[i]
	deliveries.remove_at(i)
	player.set_carry(item)
	# Vorher entfernen: Die Lieferung löscht gerade das Ziel, auf das der Sichtstrahl zeigt
	player._focus = null
	_deliveries_changed()
	office_pc.overlay.stock_changed()
	return ""


## Hinweis beim Anvisieren eines Fachs.
func rack_prompt(slot: int) -> String:
	var where := Site.slot_name(slot)
	if player.carrying_bin() or player.carrying_semi():
		return "%s    |    Hände voll" % where
	var here := Storage.on_board(stock, slot)
	if not player.carry.is_empty():
		if Storage.fits_with(here, player.carry):
			return "[Linksklick] In %s legen" % where
		return "%s: Das passt hier nicht" % where
	var what := "leer" if here.is_empty() else Site.sign_text(here)
	return "[Linksklick] Lagerbestand ansehen    |    %s: %s" % [where, what]


## Linksklick auf ein Fach: Material genau dort ablegen, sonst den Bestand zeigen.
func rack_click(slot: int) -> void:
	if player.carry.is_empty():
		rack_menu.open()
	else:
		store_at(slot)


## Material aus den Händen in genau dieses Fach legen. Fehlertext, leer = abgelegt.
func store_at(slot: int) -> String:
	if player.carry.is_empty():
		return "Keine Hand voll Material."
	if player.carrying_bin() or player.carrying_semi():
		return "Das gehört nicht ins Regal."
	if not Storage.fits_with(Storage.on_board(stock, slot), player.carry):
		var full := "%s: Das passt hier nicht. Stangen und Fertigschnitte liegen getrennt, nach Maßen ist irgendwann Schluss." % Site.slot_name(slot)
		hud.show_message(full, Color(1, 0.75, 0.2))
		return full
	_put_in_slot(slot)
	return ""


func _put_in_slot(slot: int) -> void:
	var item: Dictionary = player.carry
	item["slot"] = slot
	stock.append(item)
	player.clear_carry()
	_stock_changed()
	hud.show_message("Abgelegt: %s. Belegt: %d von %d Fächern." % [Site.slot_name(slot), Storage.used_slots(stock), site.capacity()], Color(0.7, 0.95, 1.0))
	office_pc.overlay.stock_changed()


## Material aus den Händen ablegen, in diesem Regal oder mit rack -1 im ersten freien.
## Gibt einen Fehlertext zurück, leer = abgelegt.
func store_carried(rack := -1) -> String:
	if player.carry.is_empty():
		return "Keine Hand voll Material."
	if player.carrying_bin() or player.carrying_semi():
		return "Das gehört nicht ins Regal."
	var slot := -1
	if rack >= 0:
		slot = Storage.find_slot_in(stock, player.carry, Site.rack_slots(rack))
	else:
		slot = Storage.find_slot(stock, player.carry, site.capacity())
	if slot < 0:
		var full := "Dieses Regal ist voll. Ein anderes nehmen oder am PC ein weiteres kaufen." if rack >= 0 else "Kein Platz im Lager. Am PC im Tab Einkauf ein Lagerregal kaufen."
		hud.show_message(full, Color(1, 0.75, 0.2))
		return full
	_put_in_slot(slot)
	return ""


## Stück aus dem Regal in die Hände nehmen. Gibt einen Fehlertext zurück, leer = genommen.
func take_from_stock(i: int) -> String:
	if i < 0 or i >= stock.size():
		return "Nicht mehr im Lager."
	if not player.hands_free():
		return "Erst die Hände frei machen."
	var item: Dictionary = stock[i]
	stock.remove_at(i)
	item.erase("slot")
	player.set_carry(item)
	_stock_changed()
	office_pc.overlay.stock_changed()
	return ""


## Material aus den Händen an der Maschine einspannen. Ganze Stangen sind dafür zu lang, sie müssen vorher
## an die Bandsäge.
func clamp_carried(machine: Node) -> String:
	if player.carry.is_empty():
		return ""
	if player.carrying_bin():
		return pour_tray(machine)
	if machine is BandSaw:
		return saw_load(machine)
	if player.carrying_semi():
		return _clamp_semi(machine)
	var item: Dictionary = player.carry
	var round_bar := str(item["kind"]) == Materials.KIND_ROUND
	var err := ""
	if machine is Lathe and machine.grinder_type != "" or machine is Mill and machine.grinder_type != "":
		err = "Schleifmaschinen spannen nur vorbearbeitete Teile."
	elif machine is Lathe and not round_bar:
		err = "Die Drehmaschine spannt nur Rundmaterial."
	elif machine is Mill and round_bar:
		err = "Der Schraubstock spannt nur eckiges Material."
	elif not machine is Lathe and not machine is Mill:
		err = "Hier lässt sich nichts einspannen."
	elif str(item["kind"]) != Materials.KIND_CUT and float(item["l"]) > (LATHE_MAX_LEN if machine is Lathe else MILL_MAX_LEN):
		err = "Zu lang zum Einspannen (%d mm): Erst an der Bandsäge absägen." % int(item["l"])
	else:
		err = _tray_conflict(machine, str(item["material"]))
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.2))
		return err
	if machine is Mill:
		_match_mill_job(item, _active_job(machine.MACHINE_ID))
	stock.append(item)
	var i := stock.size() - 1
	err = load_stock(i, float(item["l"]), machine)
	if err != "":
		stock.remove_at(i)
		hud.show_message(err, Color(1, 0.75, 0.2))
		return err
	player.clear_carry()
	_stock_changed()
	hud.show_message("Eingespannt.", Color(0.7, 0.95, 1.0))
	return ""


# ------------------------------------------------------------ Einspannen

## Klick auf eine Maschine mit Teil in der Hand oder im Futter. flip: andersherum spannen.
func ask_clamp(machine: Node, flip: bool) -> void:
	if player.carrying_bin() or machine is BandSaw:
		if not flip:
			clamp_carried(machine)
		return
	if not machine is Lathe and not machine is Mill:
		clamp_carried(machine)
		return
	# Was gar nicht passt, gibt sofort den Hinweis
	var err := _clamp_precheck(machine)
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.2))
		return
	clamp_dialog.open(machine, flip)


## Fehler, die schon vor der Frage nach der Spanntiefe feststehen.
func _clamp_precheck(machine: Node) -> String:
	if player.carry.is_empty():
		return "Erst die Spindel stoppen, dann umspannen." if machine.spindle_speed > 5.0 else ""
	if player.carrying_semi():
		return ""
	var round_bar := str(player.carry["kind"]) == Materials.KIND_ROUND
	if machine.grinder_type != "":
		return "Schleifmaschinen spannen nur vorbearbeitete Teile."
	if machine is Lathe and not round_bar:
		return "Die Drehmaschine spannt nur Rundmaterial."
	if machine is Mill and round_bar:
		return "Der Schraubstock spannt nur eckiges Material."
	if str(player.carry["kind"]) != Materials.KIND_CUT and float(player.carry["l"]) > (LATHE_MAX_LEN if machine is Lathe else MILL_MAX_LEN):
		return "Zu lang zum Einspannen (%d mm): Erst an der Bandsäge absägen." % int(player.carry["l"])
	return ""


## Kleinste und größte Spanntiefe für das Teil in der Hand oder in der Maschine.
func clamp_limit(machine: Node) -> Vector2:
	var size := 0.0
	var item: Dictionary = player.carry
	if machine is Lathe:
		size = float(item.get("l", machine.stock_len)) if not player.carrying_semi() else float(machine.stock_len)
		if player.carrying_semi():
			size = float(item["part"].get("stock_len", 100.0))
		return Vector2(3.0, maxf(minf(size - 10.0, 200.0), 3.0))
	size = float(item.get("h", machine.block_h)) if not player.carrying_semi() else float(machine.block_h)
	if player.carrying_semi():
		var s = item["part"].get("size", [0.0, 0.0, 40.0])
		size = float(s[2]) if s is Array and s.size() > 2 else 40.0
	return Vector2(5.0, maxf(size - 3.0, 5.0))


## Antwort aus dem Fenster: einspannen und auf die gewählte Spanntiefe setzen.
func finish_clamp(machine: Node, flip: bool, depth: float) -> String:
	if not player.carry.is_empty():
		var err := clamp_carried(machine)
		if err != "":
			return err
	var res: String = machine.reclamp(depth, flip)
	if res == "":
		var text := "Kopfüber eingespannt" if flip and machine is Mill else ("Umgedreht eingespannt" if flip else "Eingespannt")
		hud.show_message("%s, Spanntiefe %d mm." % [text, int(depth)], Color(0.7, 0.95, 1.0))
	return res


# ------------------------------------------------------------ Bandsäge

## Stange aus den Händen auf die Rollbahn legen.
func saw_load(saw: BandSaw) -> String:
	var err := ""
	if player.carrying_semi():
		err = "Kundenteile werden nicht gesägt."
	elif str(player.carry["kind"]) == Materials.KIND_CUT:
		err = "Fertigschnitte sind schon auf Maß."
	elif saw.cutting:
		err = "Die Säge läuft gerade."
	elif saw.has_bar() or saw.has_piece():
		err = "Auf der Rollbahn liegt noch etwas: Erst mit freien Händen abräumen."
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.2))
		return err
	saw.load_bar(player.carry)
	player.clear_carry()
	player._focus = null
	hud.show_message("Stange liegt auf der Rollbahn. Mit [%s] die Länge einstellen und sägen." % Settings.binding_text("interact"), Color(0.7, 0.95, 1.0))
	return ""


## Linksklick mit leeren Händen: erst den Abschnitt nehmen, sonst die Stange.
func saw_click(saw: BandSaw) -> void:
	if not player.carry.is_empty() or not player.held.is_empty() or saw.cutting:
		return
	if saw.has_piece():
		player.set_carry(saw.take_piece())
	elif saw.has_bar():
		player.set_carry(saw.take_bar())


## Abschnittslänge für den laufenden Auftrag, 0 = kein passender Auftrag.
func saw_suggestion(item: Dictionary) -> float:
	if str(item["kind"]) == Materials.KIND_ROUND:
		if has_job("lathe"):
			var job := _current_job()
			if str(item["material"]) == str(job["material"]) and float(item["d"]) >= float(job["stock_d"]):
				return float(job["stock_len"])
	elif has_job("mill"):
		var mj := _active_job("mill")
		if str(item["material"]) == str(mj["material"]):
			return float(mj["size"][0])
	return 0.0


# ------------------------------------------------------------ Kisten

func crate_prompt(i: int) -> String:
	var c: Dictionary = layout.crates[i]
	var what := "%s (%d von %d Teilen)" % [Crate.SIZES[c["size"]]["title"], c["items"].size(), int(Crate.SIZES[c["size"]]["max"])]
	if player.carrying_bin() or player.carrying_semi():
		return "%s    |    Hände voll" % what
	if not player.carry.is_empty():
		return "[Linksklick] In die Kiste legen    |    %s" % what
	if not player.held.is_empty():
		return "%s    |    Hände voll" % what
	if c["items"].is_empty():
		return "%s    |    leer" % what
	var top: Dictionary = c["items"][-1]
	return "[Linksklick] %s  %s nehmen    |    %s" % [Materials.label(str(top["material"])), RawMaterialTab.describe(top), what]


func crate_click(i: int) -> void:
	if not player.carry.is_empty():
		var err := crate_put(i)
		if err != "":
			hud.show_message(err, Color(1, 0.75, 0.2))
	elif player.held.is_empty():
		crate_take(i)


## Material aus den Händen in die Kiste. Fehlertext, leer = hineingelegt.
func crate_put(i: int) -> String:
	if player.carry.is_empty():
		return "Keine Hand voll Material."
	if player.carrying_bin():
		return "Der Spänebehälter passt nicht in die Kiste."
	var c: Dictionary = layout.crates[i]
	if not Crate.accepts(player.carry):
		return "Stangen gehören ins Regal. In die Kiste kommen Fertigschnitte und abgesägte Teile."
	if not Crate.fits(c["size"], c["items"], player.carry):
		return "Das passt nicht mehr in diese Kiste."
	c["items"].append(player.carry)
	player.clear_carry()
	crate_nodes[i].refresh()
	return ""


## Oberstes Stück aus der Kiste in die Hände. Fehlertext, leer = genommen.
func crate_take(i: int) -> String:
	var c: Dictionary = layout.crates[i]
	if c["items"].is_empty():
		return "Die Kiste ist leer."
	if not player.hands_free():
		return "Erst die Hände frei machen."
	player.set_carry(c["items"].pop_back())
	crate_nodes[i].refresh()
	return ""


## Kiste aufstellen oder umstellen. moving = Nummer der Kiste, sonst -1. Fehlertext, leer = aufgestellt.
func place_crate(moving: int, size_id: String, pos: Vector2, rot: int) -> String:
	var err := layout.check_crate(size_id, pos, rot, moving)
	if err != "":
		return err
	var bench := layout.crate_bench_at(size_id, pos, rot)
	if moving >= 0:
		var c: Dictionary = layout.crates[moving]
		c["pos"] = pos
		c["rot"] = rot
		c["bench"] = bench
	else:
		if int(inventory.get(size_id, 0)) <= 0:
			return "Diese Kiste wurde nicht gekauft."
		inventory[size_id] = int(inventory[size_id]) - 1
		layout.crates.append({"size": size_id, "pos": pos, "rot": rot, "bench": bench, "items": []})
	_rebuild_stands()
	return ""


## Spänebehälter aufstellen oder umstellen.
func place_bin(moving: int, size_id: String, pos: Vector2, rot: int) -> String:
	var err := layout.check_bin(pos, rot, moving)
	if err != "":
		return err
	if moving >= 0:
		if layout.bins[moving]["out"]:
			return "Erst den Behälter abstellen."
		layout.bins[moving]["pos"] = pos
		layout.bins[moving]["rot"] = rot
	else:
		if int(inventory.get(size_id, 0)) <= 0:
			return "Dieser Behälter wurde nicht gekauft."
		inventory[size_id] = int(inventory[size_id]) - 1
		layout.bins.append({"size": size_id, "pos": pos, "rot": rot, "chips": ChipTray.new(float(ChipBin.SIZES[size_id]["kg"])), "out": false})
	_rebuild_stands()
	return ""


## Lagerregal aufstellen oder umstellen, es rastet auf der Kachel ein. moving = Regalnummer, sonst -1.
## Der Inhalt bleibt im Regal. Fehlertext, leer = aufgestellt.
func place_rack(moving: int, pos: Vector2) -> String:
	var cell := Site.l_cell_at(pos)
	var err := site.rack_error(cell, moving)
	if err != "":
		return err
	player._focus = null
	if moving >= 0:
		site.move_rack(moving, cell)
	else:
		if int(inventory.get("rack", 0)) <= 0:
			return "Es wurde kein Lagerregal gekauft."
		inventory["rack"] = int(inventory["rack"]) - 1
		site.add_rack(cell)
	_stock_changed()
	office_pc.overlay.stock_changed()
	return ""


## Was steckt hinter dem Treffer des Sichtstrahls? {"kind", "item", "index", "title", "rect"}, leer = nichts
## Umstellbares. Fürs Baumenü.
func build_target(hit: Object) -> Dictionary:
	if hit == null:
		return {}
	var meta = hit.get_meta("interact", null) if hit.has_meta("interact") else null
	if meta is Site.RackTarget:
		return {"kind": "rack", "item": "rack", "index": meta.rack, "title": "Regal %d" % (meta.rack + 1),
			"rect": Site.rack_rect(site.rack_cells[meta.rack])}
	var n: Node = hit as Node
	while n != null and n != self:
		if n == lathe or n == mill or extra_machines.values().has(n):
			var id := "lathe" if n == lathe else ("mill" if n == mill else str(extra_machines.find_key(n)))
			if layout.machines.has(id):
				return {"kind": "machine", "item": id, "index": -1, "title": str(Layout.SPECS[id]["title"]), "rect": layout.area_of(id)}
		if n is ToolBench:
			var id := str(bench_nodes.find_key(n))
			return {"kind": "bench", "item": id, "index": -1, "title": "Werkbank der %s" % Layout.SPECS[id]["title"], "rect": layout.bench_area(id)}
		if n is Crate:
			var c: Dictionary = layout.crates[n.index]
			return {"kind": "crate", "item": n.size_id, "index": n.index, "title": equipment_title(n.size_id),
				"rect": Layout.crate_rect(n.size_id, c["pos"], c["rot"])}
		if n is ChipBin:
			var b: Dictionary = layout.bins[n.index]
			return {"kind": "bin", "item": n.size_id, "index": n.index, "title": equipment_title(n.size_id), "rect": Layout.bin_rect(b["pos"], b["rot"])}
		n = n.get_parent()
	return {}


## Knoten des Teils, das gerade umgestellt wird. Neues und Regale haben keinen.
func build_node(kind: String, item: String, index: int) -> Node3D:
	match kind:
		"machine":
			return _machine_node(item) if layout.machines.has(item) else null
		"bench":
			return _bench_of(item) if item != "" else null
		"crate":
			return crate_nodes[index] if index >= 0 else null
		"bin":
			return bin_nodes[index] if index >= 0 else null
	return null


## Kisten und Spänebehälter neu aufstellen.
func _rebuild_stands() -> void:
	player._focus = null
	for n in crate_nodes + bin_nodes:
		n.free()
	crate_nodes.clear()
	bin_nodes.clear()
	for i in layout.crates.size():
		var c: Dictionary = layout.crates[i]
		var node := Crate.new()
		node.world = self
		node.index = i
		node.size_id = c["size"]
		node.items = c["items"]
		node.position = Vector3(c["pos"].x, 0, c["pos"].y)
		node.rotation.y = int(c["rot"]) * PI / 2.0
		add_child(node)
		crate_nodes.append(node)
	for i in layout.bins.size():
		var b: Dictionary = layout.bins[i]
		var node := ChipBin.new()
		node.world = self
		node.index = i
		node.size_id = b["size"]
		node.position = Vector3(b["pos"].x, 0, b["pos"].y)
		node.rotation.y = int(b["rot"]) * PI / 2.0
		add_child(node)
		node.show_state(b["chips"].fraction(), b["out"])
		bin_nodes.append(node)


# ------------------------------------------------------------ Späne

func bin_prompt(i: int) -> String:
	var b: Dictionary = layout.bins[i]
	var title := str(ChipBin.SIZES[b["size"]]["title"])
	if b["out"]:
		return "[Linksklick] %s abstellen" % title if player.carrying_bin() and int(player.carry["bin"]) == i else "Stellplatz: %s" % title
	var what := "%s: %d von %d kg" % [title, int(b["chips"].kg), int(b["chips"].capacity)]
	if not b["chips"].is_empty():
		what += " %sspäne" % ChipTray.SORT_TITLES[b["chips"].sort()]
	if not player.hands_free():
		return "%s    |    Hände voll" % what
	return "[Linksklick] Aufnehmen    |    %s" % what


## Linksklick auf einen Spänebehälter oder seinen Stellplatz.
func bin_click(i: int) -> void:
	var b: Dictionary = layout.bins[i]
	if b["out"]:
		if player.carrying_bin() and int(player.carry["bin"]) == i:
			b["out"] = false
			player.clear_carry()
			bin_nodes[i].show_state(b["chips"].fraction(), false)
		return
	if player.hands_free():
		b["out"] = true
		player.set_carry({"kind": "chip_bin", "bin": i, "title": ChipBin.SIZES[b["size"]]["title"]})
		bin_nodes[i].show_state(b["chips"].fraction(), true)


## Spänewanne der Maschine in den Behälter in den Händen leeren.
func pour_tray(machine: Node) -> String:
	if machine.spindle_speed > 5.0:
		var busy := "Erst die Spindel stoppen."
		hud.show_message(busy, Color(1, 0.75, 0.2))
		return busy
	var chips: ChipTray = layout.bins[int(player.carry["bin"])]["chips"]
	var moved := chips.take_from(machine.tray)
	machine.refresh_tray()
	if moved <= 0.0:
		var why := "Die Spänewanne ist leer."
		if chips.is_full():
			why = "Der Behälter ist voll: im Hof in den Container leeren."
		elif not machine.tray.is_empty():
			why = "Im Behälter liegen %sspäne: erst in den Container leeren, nicht mischen." % ChipTray.SORT_TITLES[chips.sort()]
		hud.show_message(why, Color(1, 0.75, 0.2))
		return why
	hud.show_message("%d kg Späne im Behälter, jetzt %d von %d kg." % [int(round(moved)), int(chips.kg), int(chips.capacity)], Color(0.7, 0.95, 1.0))
	return ""


func container_prompt(i: int) -> String:
	var c: ChipTray = containers[i]
	var what := "Container %s: %d von %d kg" % [ChipTray.SORT_TITLES[c.only], int(c.kg), int(c.capacity)]
	if player.carrying_bin():
		return "[Linksklick] Behälter hineinleeren    |    %s" % what
	return what + ("    |    Voll: am PC abholen lassen" if c.is_full() else "")


func container_click(i: int) -> void:
	if not player.carrying_bin():
		return
	var c: ChipTray = containers[i]
	var n := int(player.carry["bin"])
	var chips: ChipTray = layout.bins[n]["chips"]
	var moved := c.take_from(chips)
	if moved <= 0.0:
		var why := "Der Behälter ist leer."
		if c.is_full():
			why = "Der Container ist voll: am PC im Programm Entsorgung abholen lassen."
		elif not chips.is_empty():
			why = "Das sind %sspäne, sie gehören nicht in diesen Container." % ChipTray.SORT_TITLES[chips.sort()]
		hud.show_message(why, Color(1, 0.75, 0.2))
		return
	bin_nodes[n].show_state(chips.fraction(), true)
	site.show_containers(containers)
	player._focus = null
	hud.show_message("%d kg in den Container gekippt, jetzt %d von %d kg." % [int(round(moved)), int(c.kg), int(c.capacity)], Color(0.7, 0.95, 1.0))
	office_pc.overlay.waste_tab.refresh()


func container_value(i: int) -> int:
	return containers[i].value(company.skills.recycle_factor())


## Vollen Container abholen lassen. Gibt die Vergütung zurück, 0 = noch nicht voll.
func collect_container(i: int) -> int:
	var c: ChipTray = containers[i]
	if not c.is_full():
		return 0
	var pay := container_value(i)
	money += pay
	c.clear()
	site.show_containers(containers)
	player._focus = null
	_refresh_hud()
	office_pc.overlay.refresh_all()
	return pay


# ------------------------------------------------------------ Skilltree

## Skill freischalten, im Testmodus kostenlos. Gibt einen Fehlertext zurück, leer = freigeschaltet.
func unlock_skill(id: String) -> String:
	var err := company.skills.unlock(id, free_mode)
	if err != "":
		return err
	_apply_skills()
	_refresh_hud()
	office_pc.overlay.refresh_all()
	hud.show_message("Freigeschaltet: %s" % Skills.title_of(id), Color(0.5, 0.9, 0.5))
	return ""


## Alle Maschinen, an denen gearbeitet wird.
func _work_machines() -> Array:
	var out: Array = [lathe, mill]
	for id in extra_machines:
		if not extra_machines[id] is SimpleMachine and not extra_machines[id] is BandSaw:
			out.append(extra_machines[id])
	return out


## Wirkung der Skills auf Maschinen und Schnittdaten.
func _apply_skills() -> void:
	var sk := company.skills
	Materials.coolant_factor = sk.coolant_factor()
	for m in _work_machines():
		m.tray.capacity = sk.tray_capacity()
		if m.tool_stock != null:
			m.skills = sk
			m.refresh_tool_mods()
	if extra_machines.get("saw", null) is BandSaw:
		extra_machines["saw"].tray.capacity = sk.tray_capacity()


# ------------------------------------------------------------ Gelände

## Kachel kaufen. Gibt einen Fehlertext zurück, leer = gekauft.
func buy_tile(area: String, cell: Vector2i) -> String:
	var closed := _closed_error()
	if closed != "":
		return closed
	if not site.can_buy(area, cell):
		return "Diese Kachel kann nicht gekauft werden."
	var cost: int = 0 if free_mode else site.tile_price(area)
	if cost > money:
		return "Nicht genug Geld: %d EUR nötig, %d EUR vorhanden." % [cost, money]
	money -= cost
	site.buy_cell(area, cell)
	_stock_changed()
	_refresh_hud()
	return ""


func equipment_price(id: String) -> int:
	if id == "bench":
		return Layout.BENCH_PRICE
	if id == "bench_big":
		return Layout.BENCH_BIG_PRICE
	if id == "rack":
		return Site.RACK_PRICE
	if Crate.SIZES.has(id):
		return int(Crate.SIZES[id]["price"])
	if ChipBin.SIZES.has(id):
		return int(ChipBin.SIZES[id]["price"])
	return int(Layout.SPECS[id]["price"])


func equipment_title(id: String) -> String:
	match id:
		"bench":
			return "Werkbank"
		"bench_big":
			return "Große Werkbank"
		"rack":
			return "Lagerregal"
	if Crate.SIZES.has(id):
		return str(Crate.SIZES[id]["title"])
	if ChipBin.SIZES.has(id):
		return str(ChipBin.SIZES[id]["title"])
	return str(Layout.SPECS[id]["title"])


## Mehrfach kaufbar sind Werkbänke, Kisten und Spänebehälter, Maschinen gibt es je einmal.
static func _is_machine(id: String) -> bool:
	return Layout.SPECS.has(id)


## Kaufen. Maschinen, Werkbänke, Regale, Kisten und Behälter warten im Baumodus auf das Aufstellen.
func buy_equipment(id: String) -> String:
	var closed := _closed_error()
	if closed != "":
		return closed
	if Skills.EQUIPMENT.has(id) and not company.skills.has(Skills.EQUIPMENT[id]):
		return "Erst im Skilltree freischalten: %s." % Skills.title_of(Skills.EQUIPMENT[id])
	if _is_machine(id) and (layout.machines.has(id) or int(inventory.get(id, 0)) > 0):
		return "Diese Maschine gibt es schon."
	var cost: int = 0 if free_mode else equipment_price(id)
	if cost > money:
		return "Nicht genug Geld: %d EUR nötig, %d EUR vorhanden." % [cost, money]
	money -= cost
	inventory[id] = int(inventory.get(id, 0)) + 1
	_refresh_hud()
	return ""


func _machine_node(id: String) -> Node3D:
	match id:
		"lathe":
			return lathe
		"mill":
			return mill
	return extra_machines.get(id, null)


func machine_busy(id: String) -> bool:
	var m := _machine_node(id)
	return m != null and m.get("spindle_speed") != null and float(m.get("spindle_speed")) > 5.0


func _bench_of(id: String) -> ToolBench:
	return bench_nodes.get(id, null)


## Maschine aufstellen oder umstellen. Ihr Bereich und ihre Werkbank wandern mit.
## Gibt einen Fehlertext zurück, leer = aufgestellt.
func place_machine(id: String, pos: Vector2, rot: int) -> String:
	var err := layout.check_machine(id, pos, rot)
	if err != "":
		return err
	if machine_busy(id):
		return "Erst die Spindel stoppen, dann umstellen."
	var moved := layout.machines.has(id)
	if not moved and int(inventory.get(id, 0)) <= 0:
		return "Diese Maschine wurde nicht gekauft."
	var old_pos: Vector2 = layout.machines[id]["pos"] if moved else pos
	var old_rot: int = layout.machines[id]["rot"] if moved else rot
	if not moved:
		inventory[id] = int(inventory[id]) - 1
	layout.machines[id] = {"pos": pos, "rot": rot}
	_put_machine(id)
	company.add_machine(id)
	# Werkbank behält ihre Lage zur Maschine
	if layout.benches.has(id):
		var b: Dictionary = layout.benches[id]
		var local := Layout._turn(b["pos"] - old_pos, -old_rot)
		b["pos"] = Layout._turn(local, rot) + pos
		b["rot"] = posmod(int(b["rot"]) + rot - old_rot, 4)
		_put_bench(id)
	# Die Kisten bleiben neben der Werkbank
	for c in layout.crates:
		if c["bench"] == id:
			var local := Layout._turn(c["pos"] - old_pos, -old_rot)
			c["pos"] = Layout._turn(local, rot) + pos
			c["rot"] = posmod(int(c["rot"]) + rot - old_rot, 4)
	_rebuild_stands()
	site.show_areas(layout)
	_jobs_changed()
	_refresh_hud()
	return ""


## Neue Maschine erzeugen und anschließen. Sie startet ohne Werkzeuge und ohne Teil.
func _make_machine(id: String) -> void:
	var m: Node3D
	match id:
		"cnc_lathe":
			var l := Lathe.new()
			l.MACHINE_ID = "cnc_lathe"
			m = l
		"drill":
			m = DrillPress.new()
		"flat_grinder":
			m = FlatGrinder.new()
		"round_grinder":
			m = RoundGrinder.new()
		"saw":
			var saw := BandSaw.new()
			saw.world = self
			saw.tray.capacity = company.skills.tray_capacity()
			m = saw
		_:
			var s := SimpleMachine.new()
			s.id = id
			m = s
	add_child(m)
	extra_machines[id] = m
	if m is SimpleMachine or m is BandSaw:
		return
	if m is Lathe:
		_wire_lathe(m)
	else:
		var mh := MillHUD.new()
		mh.mill = m
		add_child(mh)
		mill_huds[id] = mh
		_wire_mill(m, mh)
	if company.tools.has(id):
		m.tool_stock = company.tools[id]
		_add_mount(m)
		m.skills = company.skills
		if m is Lathe:
			m.clear_tools()
		else:
			m.clear_spindle()
	m.clear_workpiece()
	m.tray.capacity = company.skills.tray_capacity()


## Maschine abräumen, zum Beispiel beim Laden eines Spielstands, in dem sie nicht steht.
func _drop_machine(id: String) -> void:
	extra_machines[id].free()
	extra_machines.erase(id)
	if mill_huds.has(id):
		mill_huds[id].free()
		mill_huds.erase(id)


func _put_machine(id: String) -> void:
	if not _machine_node(id):
		_make_machine(id)
	var n := _machine_node(id)
	var at: Dictionary = layout.machines[id]
	n.visible = true
	n.scale = Vector3.ONE * (Layout.MACHINE_SCALE if Layout.SCALED.has(id) else 1.0)
	n.position = Vector3(at["pos"].x, 0, at["pos"].y)
	n.rotation.y = int(at["rot"]) * PI / 2.0


## Werkbank aufstellen oder umstellen. moving = Maschine der umgestellten Werkbank, sonst leer.
## big = die große Werkbank aus dem Skilltree.
func place_bench(moving: String, pos: Vector2, rot: int, big := false) -> String:
	if moving != "":
		big = bool(layout.benches[moving].get("big", false))
	var err := layout.check_bench(pos, rot, moving, big)
	if err != "":
		return err
	if moving != "" and layout.crates_of(moving) > 0:
		return "Erst die Kisten neben dieser Werkbank umstellen."
	var kind := "bench_big" if big else "bench"
	if moving == "" and int(inventory.get(kind, 0)) <= 0:
		return "Es wurde keine solche Werkbank gekauft."
	var id := layout.bench_machine_at(pos, rot, big)
	if moving == "":
		inventory[kind] = int(inventory[kind]) - 1
	elif moving != id:
		_remove_bench(moving)
	layout.benches[id] = {"pos": pos, "rot": rot, "big": big}
	_put_bench(id)
	return ""


## Werkbank abbauen, sie wartet dann wieder im Baumenü. So wird Platz für eine große. Fehlertext, leer = abgebaut.
func take_down_bench(id: String) -> String:
	if not layout.benches.has(id):
		return "Hier steht keine Werkbank."
	if layout.crates_of(id) > 0:
		return "Erst die Kisten neben dieser Werkbank umstellen."
	var kind := "bench_big" if bool(layout.benches[id].get("big", false)) else "bench"
	_remove_bench(id)
	inventory[kind] = int(inventory.get(kind, 0)) + 1
	player._focus = null
	return ""


func _remove_bench(id: String) -> void:
	layout.benches.erase(id)
	var b := _bench_of(id)
	if b:
		b.free()
	bench_nodes.erase(id)


## Werkbank an ihren Platz setzen, beim ersten Mal erzeugen.
func _put_bench(id: String) -> void:
	var b := _bench_of(id)
	if b == null:
		b = ToolBench.new()
		b.machine = _machine_node(id)
		b.player = player
		if bool(layout.benches[id].get("big", false)):
			b.width = Layout.BENCH_BIG_SIZE.x
			b.depth = Layout.BENCH_BIG_SIZE.y
		add_child(b)
		bench_nodes[id] = b
	var at: Dictionary = layout.benches[id]
	b.position = Vector3(at["pos"].x, 0, at["pos"].y)
	b.rotation.y = int(at["rot"]) * PI / 2.0


## Werkbank direkt aufstellen, ohne Kauf (alte Spielstände).
func spawn_bench(id: String, pos: Vector2, rot: int) -> void:
	layout.benches[id] = {"pos": pos, "rot": rot}
	_put_bench(id)


func _site_state() -> Dictionary:
	var w := []
	for c in site.workshop_cells:
		w.append([c.x, c.y])
	var l := []
	for c in site.lager_cells:
		l.append([c.x, c.y])
	var r := []
	for c in site.rack_cells:
		r.append([c.x, c.y])
	return {"workshop_cells": w, "lager_cells": l, "racks": r,
		"door_workshop": site.door_workshop.is_opening(), "door_lager": site.door_lager.is_opening()}


## keep_racks: Spielstand von vor dem Regalkauf, jede Kachel hatte schon ihr Regal.
func _apply_site(d: Dictionary, keep_racks := false) -> void:
	var w: Array = []
	var l: Array = []
	for c in d.get("workshop_cells", []):
		w.append(Vector2i(int(c[0]), int(c[1])))
	for c in d.get("lager_cells", []):
		l.append(Vector2i(int(c[0]), int(c[1])))
	# Alte Spielstände zählen Ausbaustufen: als Spalten und Reihen übernehmen
	for level in int(d.get("workshop", 0)):
		for row in range(-2, 2):
			w.append(Vector2i(Site.W_CX_BASE - 1 - level, row))
	for level in int(d.get("lager", 0)):
		l.append(Vector2i(0, 2 + level))
		l.append(Vector2i(1, 2 + level))
	var racks: Array = []
	for c in d.get("racks", []):
		racks.append(Vector2i(int(c[0]), int(c[1])))
	site.set_tiles(w, l, racks)
	if keep_racks and not d.has("racks"):
		site.set_tiles(w, l, site.lager_cells.duplicate())
	site.door_workshop.set_open(bool(d.get("door_workshop", false)), true)
	site.door_lager.set_open(bool(d.get("door_lager", false)), true)


## Stellplan aus dem Spielstand. Ohne Plan stehen die Startmaschinen an ihrem Platz; alte Spielstände
## hatten ihre Werkbänke schon, ein neues Spiel bekommt die Werkbank der ersten Drehmaschine.
func _apply_layout(d: Dictionary) -> void:
	var saved = d.get("layout", null)
	var want_m := {}
	var want_b := {}
	if saved is Dictionary:
		for id in saved.get("machines", {}):
			var v: Array = saved["machines"][id]
			want_m[id] = {"pos": Vector2(v[0], v[1]), "rot": int(v[2])}
		for id in saved.get("benches", {}):
			var v: Array = saved["benches"][id]
			want_b[id] = {"pos": Vector2(v[0], v[1]), "rot": int(v[2]), "big": v.size() > 3 and bool(v[3])}
	else:
		for id in company.machines:
			if Layout.SPECS.has(id) and Layout.SPECS[id].has("pos"):
				want_m[id] = {"pos": Layout.SPECS[id]["pos"], "rot": 0}
		if d.has("lathe"):
			for id in Layout.DEFAULT_BENCH:
				var v: Array = Layout.DEFAULT_BENCH[id]
				want_b[id] = {"pos": Vector2(v[0], v[1]), "rot": int(v[2])}
		elif bool(d.get("starter", false)):
			var v: Array = Layout.DEFAULT_BENCH["lathe"]
			want_b["lathe"] = {"pos": Vector2(v[0], v[1]), "rot": int(v[2])}
	for id in Layout.BENCH_MACHINES:
		if layout.benches.has(id) and not want_b.has(id):
			_remove_bench(id)
	for id in extra_machines.keys():
		if not want_m.has(id):
			_drop_machine(id)
	layout.machines = want_m
	for id in want_m:
		_put_machine(id)
	# Noch nicht gekauft: Die Maschine ist unsichtbar und weit weg vom Geschehen
	for id in ["lathe", "mill"]:
		if not want_m.has(id):
			var hidden := _machine_node(id)
			hidden.visible = false
			hidden.position = Vector3(0, -50, 0)
	layout.benches = want_b
	for id in want_b:
		_put_bench(id)
	var inv = d.get("inventory", {})
	inventory = inv.duplicate() if inv is Dictionary else {}
	# Der erste Spänebehälter gehört zur Werkstatt: Eine volle Wanne darf nie zur Sackgasse werden
	if not saved is Dictionary or not saved.has("bins"):
		inventory["bin_s"] = int(inventory.get("bin_s", 0)) + 1
	layout.crates = []
	layout.bins = []
	if saved is Dictionary:
		for c in saved.get("crates", []):
			var items = c.get("items", [])
			layout.crates.append({"size": str(c["size"]), "pos": Vector2(c["pos"][0], c["pos"][1]), "rot": int(c["rot"]),
				"bench": str(c["bench"]), "items": items.duplicate(true) if items is Array else []})
		for b in saved.get("bins", []):
			var chips := ChipTray.new(float(ChipBin.SIZES[str(b["size"])]["kg"]))
			chips.load_state(b.get("chips", {}))
			layout.bins.append({"size": str(b["size"]), "pos": Vector2(b["pos"][0], b["pos"][1]), "rot": int(b["rot"]),
				"chips": chips, "out": bool(b.get("out", false))})
	_rebuild_stands()
	site.show_areas(layout)


## Meldung, wenn für einen Auftrag nichts im Lager liegt.
func _no_stock_message(need: String) -> String:
	if not deliveries.is_empty():
		return "Kein passendes Material im Lager. Vor dem Lager-Rolltor stehen noch %d Lieferungen, mit Linksklick aufheben und ins Regal legen." % deliveries.size()
	return "Kein Material im Lager. Am PC im Büro kaufen: %s." % need


## Rohmaterial einspannen, das Stück steht dazu kurz in der Lagerliste. Von Stangen wird length abgesägt.
## Fehlertext, leer = eingespannt.
func load_stock(i: int, length: float, machine: Node = null) -> String:
	if i < 0 or i >= stock.size():
		return "Nicht mehr im Lager."
	var item: Dictionary = stock[i]
	var kind := str(item["kind"])
	var bar := kind != Materials.KIND_CUT and not bool(item.get("sawn", false))
	var l := minf(length, float(item["l"])) if bar else float(item["l"])
	if kind == Materials.KIND_ROUND:
		var m: Lathe = machine if machine is Lathe else lathe
		var err := _lathe_fit(float(item["d"]), l, m)
		if err != "":
			return err
		m.set_material(str(item["material"]))
		m.new_workpiece(float(item["d"]), l)
	else:
		var m: Mill = machine if machine is Mill else mill
		var err := _mill_fit(l, float(item["w"]), float(item["h"]), m)
		if err != "":
			return err
		m.set_material(str(item["material"]))
		m.new_workpiece(l, float(item["w"]), float(item["h"]))
	item["l"] = float(item["l"]) - l - Materials.KERF
	if not bar or float(item["l"]) < RawMaterialTab.CUT_MIN:
		stock.remove_at(i)
	_stock_changed()
	return ""


func _lathe_fit(d: float, l: float, m: Lathe) -> String:
	if m.spindle_speed > 5.0:
		return "Erst die Spindel der Drehmaschine stoppen."
	if d < 5.0 or d > 200.0:
		return "Das Futter spannt nur Ø5 bis Ø200 mm."
	if l > LATHE_MAX_LEN:
		return "Abschnitt zu lang: höchstens %d mm." % int(LATHE_MAX_LEN)
	return ""


func _mill_fit(l: float, w: float, h: float, m: Mill) -> String:
	if m.spindle_speed > 5.0:
		return "Erst die Spindel stoppen."
	if l < RawMaterialTab.CUT_MIN or l > MILL_MAX_LEN:
		return "Länge passt nicht: %d bis %d mm." % [int(RawMaterialTab.CUT_MIN), int(MILL_MAX_LEN)]
	if w < 10.0 or w > 120.0:
		return "Der Schraubstock spannt nur 10 bis 120 mm Breite."
	if h < 15.0 or h > 100.0:
		return "Höhe passt nicht: 15 bis 100 mm."
	return ""


# ------------------------------------------------------------ Speichern / Laden

func _apply_pending(d: Dictionary) -> void:
	save_name = str(d.get("name", "Werkstatt"))
	# Spielstände von vor dem Skilltree behalten, was sie schon hatten
	var veteran := bool(d.get("unlock_all", false)) or (d.has("lathe") and not d.has("skills"))
	var starter := bool(d.get("starter", false)) and not d.has("layout")
	var first_machines = ["lathe", "mill"] if veteran else (STARTER_MACHINES if starter else null)
	company.load_state(int(d.get("money", GameState.START_MONEY)), d.get("machines", first_machines))
	company.skills = Skills.new()
	if d.get("skills", null) is Dictionary:
		company.skills.load_state(d["skills"])
	elif veteran:
		company.skills.unlock_basics()
	# Werkzeugbestand: Spielstände von vor dem Werkzeugkauf haben alle Werkzeuge in Hartmetall
	var saved_tools = d.get("tools", null)
	for m in company.tools:
		var store: ToolStore = company.tools[m]
		store.clear()
		if saved_tools is Dictionary:
			store.load_state(saved_tools.get(m, {}))
		elif veteran:
			var all_tools: Array = Wheels.list(m) if Wheels.WIDTHS.has(m) else (LatheTools.all() if m == "lathe" or m == "cnc_lathe" else MillTools.TOOLS)
			for t in all_tools:
				store.add(str(t["id"]), "wheel" if Wheels.WIDTHS.has(m) else "hm")
	if starter and not saved_tools is Dictionary:
		for id in STARTER_TOOLS:
			company.tools["lathe"].add(id, "hm")
	lathe.tool_stock = company.tools["lathe"]
	mill.tool_stock = company.tools["mill"]
	job_index = int(d.get("job", 0))
	mill_job_index = int(d.get("mill_job", 0))
	drill_job_index = int(d.get("drill_job", 0))
	day = int(d.get("day", 1))
	day_time = float(d.get("day_time", 0.0))
	day_over = bool(d.get("day_over", false))
	day_started = bool(d.get("day_started", not bool(d.get("starter", false))))
	var saved_stats = d.get("day_stats", {})
	day_stats = saved_stats.duplicate() if saved_stats is Dictionary else {}
	var saved_last = d.get("last_day_stats", {})
	last_day_stats = saved_last.duplicate() if saved_last is Dictionary else {}
	company.reputation = float(d.get("reputation", 50.0))
	var saved_log = d.get("rep_log", [])
	company.rep_log = saved_log.duplicate(true) if saved_log is Array else []
	grind_jobs = []
	var saved_grind = d.get("grind_jobs", [])
	if saved_grind is Array:
		for k in saved_grind:
			if JobBoard.all_keys().has(str(k)):
				grind_jobs.append(str(k))
	accepted = []
	var saved_jobs = d.get("accepted", [JobBoard.key("lathe", job_index), JobBoard.key("mill", mill_job_index)] if veteran else [])
	if saved_jobs is Array:
		for k in saved_jobs:
			if JobBoard.all_keys().has(str(k)):
				accepted.append(str(k))
	deadlines = {}
	var saved_due = d.get("deadlines", null)
	for k in accepted + grind_jobs:
		# Spielstände von vor den Fristen bekommen die volle Zeit ab heute
		deadlines[k] = int(saved_due.get(k, day + JobBoard.days_for(k))) if saved_due is Dictionary else day + JobBoard.days_for(k)
	tracked = str(d.get("tracked", accepted[0] if veteran and not accepted.is_empty() else ""))
	if not accepted.has(tracked):
		tracked = ""
	parts = int(d.get("parts", 0))
	play_time = float(d.get("play_time", 0.0))
	var st = d.get("stock", [])
	stock = st.duplicate(true) if st is Array else []
	var dl = d.get("deliveries", [])
	deliveries = dl.duplicate(true) if dl is Array else []
	var sd = d.get("site", {})
	_apply_site(sd if sd is Dictionary else {}, veteran)
	if starter and not d.has("site"):
		site.add_rack(Site.l_cell_at(STARTER_RACK))
		stock.append(STARTER_BAR.duplicate())
	_apply_layout(d)
	Storage.assign_missing(stock, site.capacity())
	_deliveries_changed()
	_stock_changed()
	containers = []
	var saved_c = d.get("containers", [])
	for i in CONTAINER_SORTS.size():
		var chips := ChipTray.new(CONTAINER_KG, CONTAINER_SORTS[i])
		if saved_c is Array and i < saved_c.size():
			chips.load_state(saved_c[i])
			# Alte Spielstände kannten nur gemischte Container
			if not chips.is_empty() and chips.sort() != chips.only:
				chips.clear()
		containers.append(chips)
	site.show_containers(containers)
	lathe.tray.clear()
	mill.tray.clear()
	if d.has("lathe") and d["lathe"] is Dictionary:
		lathe.set_state(d["lathe"])
		# Alte Spielstände kennen keinen Werkstoff: das Teil gehört zum laufenden Auftrag
		if not d["lathe"].has("material"):
			lathe.set_material(str(_current_job().get("material", Materials.DEFAULT)))
	else:
		# Neues Spiel: Die Maschinen sind leer, Material muss man selbst kaufen
		lathe.set_material(str(_current_job().get("material", Materials.DEFAULT)))
		lathe.clear_workpiece()
	if d.has("mill") and d["mill"] is Dictionary:
		mill.set_state(d["mill"])
		if not d["mill"].has("material"):
			mill.set_material(str(MillJobs.get_job(mill_job_index).get("material", Materials.DEFAULT)))
	else:
		mill.set_material(str(MillJobs.get_job(mill_job_index).get("material", Materials.DEFAULT)))
		mill.clear_workpiece()
	# Neues Spiel: Die Maschinen sind leer, Werkzeuge muss man selbst kaufen
	if not d.has("lathe"):
		if veteran:
			lathe.reset_tools()
		else:
			lathe.clear_tools()
	if not d.has("mill"):
		if veteran:
			mill.select_tool(0, true)
		else:
			mill.clear_spindle()
	# Weitere Maschinen aus dem Spielstand
	var saved_states = d.get("machine_states", {})
	if saved_states is Dictionary:
		for id in extra_machines:
			if saved_states.has(id) and saved_states[id] is Dictionary and not extra_machines[id] is SimpleMachine:
				extra_machines[id].set_state(saved_states[id])
	lathe.refresh_tray()
	mill.refresh_tray()
	_apply_skills()
	if d.has("player") and d["player"] is Dictionary:
		player.set_state(d["player"])
		var h = d["player"].get("held", {})
		if h is Dictionary and h.has("id"):
			var hm: Node3D = _machine_node(str(h.get("machine", "lathe")))
			player.set_held(hm if hm != null else lathe, str(h["id"]))
	_refresh_hud()


func save_game() -> bool:
	var data := {
		"name": save_name, "money": money, "machines": company.machines, "job": job_index, "parts": parts, "play_time": play_time,
		"player": player.get_state(), "lathe": lathe.get_state(),
		"mill_job": mill_job_index, "mill": mill.get_state(), "stock": stock, "deliveries": deliveries, "site": _site_state(),
		"layout": layout.to_state(), "inventory": inventory, "skills": company.skills.to_state(),
		"tools": _tool_states(), "machine_states": _machine_states(), "drill_job": drill_job_index, "grind_jobs": grind_jobs,
		"day": day, "day_time": day_time, "day_over": day_over, "day_started": day_started, "day_stats": day_stats, "last_day_stats": last_day_stats, "deadlines": deadlines,
		"reputation": company.reputation, "rep_log": company.rep_log,
		"accepted": accepted, "tracked": tracked, "containers": containers.map(func(c: ChipTray) -> Dictionary: return c.to_state()),
	}
	return SaveManager.write_slot(GameState.current_slot, data)


func _tool_states() -> Dictionary:
	var out := {}
	for m in company.tools:
		out[m] = company.tools[m].to_state()
	return out


func _machine_states() -> Dictionary:
	var out := {}
	for id in extra_machines:
		if not extra_machines[id] is SimpleMachine:
			out[id] = extra_machines[id].get_state()
	return out


func restore_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if player.operating != null else Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------ Werkstatt-Atmosphäre

func _setup_ambient() -> void:
	_ambient = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 11025
	gen.buffer_length = 0.2
	_ambient.stream = gen
	_ambient.bus = "Ambient"
	_ambient.volume_db = -8.0
	add_child(_ambient)
	_ambient.play()
	_amb_pb = _ambient.get_stream_playback() as AudioStreamGeneratorPlayback


func _fill_ambient() -> void:
	if _amb_pb == null:
		return
	var frames := _amb_pb.get_frames_available()
	for i in frames:
		_amb_ph = fmod(_amb_ph + 100.0 / 11025.0, 1.0)
		_amb_lp = lerpf(_amb_lp, randf() * 2.0 - 1.0, 0.04)
		var s := _amb_lp * 0.35 + sin(TAU * _amb_ph) * 0.015
		_amb_pb.push_frame(Vector2(s, s))
