extends Node3D
## Spielwelt: Werkstatt, Maschinen, Spieler, HUD, Pause-Menü, Aufträge und Speichern. lathe und mill sind
## die konventionelle Drehmaschine und die Fräsmaschine, alle anderen Maschinen entstehen beim Aufstellen.

var player: Player
var lathe: Lathe
var mill: Mill
var office_pc: OfficePC
var whiteboard: Whiteboard        # Tagesbericht an der Bürowand: Tag starten und beenden
var office_clock: OfficeClock
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
var cnc_mill: CncMill:
	get:
		return extra_machines.get("cnc_mill", null)
var hud: HUD
var mill_hud: MillHUD
var mill_huds: Dictionary = {}    # Maschinen-id -> MillHUD der Bohr- und Flachschleifmaschine
var pause_menu: PauseMenu
var env: Environment
var probe: ReflectionProbe                 # Halle
var probes: Array[ReflectionProbe] = []    # Halle, Büro, QM-Raum
var _probe_light := -1.0                   # Tageslicht bei der letzten Aufnahme der Reflexionen
var _probe_wait := 0.0                     # Sekunden bis zur nächsten erlaubten Neuaufnahme
var _probe_due := false                    # Neuaufnahme angefordert (Umbau, Lichtwechsel)
var _was_building := false
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
var day_started := true           # Jeder Tag muss am Whiteboard im Büro gestartet werden
var day_stats: Dictionary = {}    # {"accepted", "done", "earned", "spent"} des laufenden Tages
var last_day_stats: Dictionary = {}
var job_index := 0
var mill_job_index := 0
var drill_job_index := 0
var parts := 0
var day := 1                      # laufender Tag
var day_time := 0.0               # s seit Tagesbeginn
var day_cycle: DayCycle           # Sonne, Himmel und Tageslicht nach der Uhrzeit
var _evening := 0.0               # s seit Feierabend, nur für den Sonnenuntergang
var day_over := false             # Feierabend: Nichts annehmen und nichts kaufen, bis der Tag beendet wird
var deadlines: Dictionary = {}    # Auftrag -> letzter Tag
var _clock_t := 0.0
const DAY_SECONDS := 720.0        # der Tag (6 bis 18 Uhr) dauert 12 Minuten
const NIGHT_SECONDS := 720.0      # die Nacht nach Feierabend (18 bis 6 Uhr) dauert ebenfalls 12 Minuten
const REP_DONE := 2.0             # Ansehen für einen erfolgreichen Auftrag
const REP_LATE := -8.0            # Ansehen für eine verpasste Frist
const REP_SCRAP := -3.0           # Ansehen für Ausschuss beim Schleifen
## Die Spänekiste unter dem Späneförderer schiebt man nicht von Hand: Hallenkran, Stapler oder Baumodus.
const MACHINE_BIN_FIXED := "Die Spänekiste steht unter dem Späneförderer: mit dem Hallenkran herausheben oder im Baumodus umstellen."
var play_time := 0.0
var stock: Array = []             # bestelltes Rohmaterial im Lager
var free_mode := false            # Testmodus: alles gratis, wird nicht gespeichert
var time_scale := 1.0             # Zeitraffer aus dem Debug-Menü, wird nicht gespeichert
var debug_menu: DebugMenu
var deliveries: Array = []        # bestellt, steht noch vor dem Lagertor
var delivery_spots: Dictionary = {}   # delivery_key -> {"pos": Vector2, "rot": int, "carried": bool}: Lieferpaletten, die mit Stapler oder Hubwagen bewegt wurden
var site: Site
var crane: HallCrane              # Hallenkran mit Funkfernbedienung
var forklift: Forklift            # Gabelstapler, solange jemand darauf sitzt (sonst Ausstattung "forklift")
const FORKLIFT_DUMP_H := 1.4      # so hoch muss die Gabel stehen, damit der Behälter über den Containerrand kippt
var job_menu: JobMenu
var rack_menu: RackMenu
var places: Places                # Orte außerhalb des Geländes: Supermarkt, je Spieler ein Zuhause
var travel_menu: TravelMenu       # Hoftor und Ausgangstüren: wohin gehen
var shop_menu: ShopMenu           # Kasse im Supermarkt
var autosave := true              # nach dem Schlafen und alle paar Minuten speichern; Tests schalten es ab, sonst überschreiben sie Slot 0
var _autosave_t := 0.0            # Spielzeit seit dem letzten automatischen Speichern
const SITE_ENTRY := Vector3(Site.GATE_X, 0.05, Site.YARD_Z1 - 1.5)   # wer zurückkommt, steht innen am Hoftor
var build_menu: BuildMenu
var layout := Layout.new()        # Stellplan: Maschinen, Bereiche, Werkbänke
var inventory: Dictionary = {}    # gekauft, aber noch nicht aufgestellt
var extra_machines: Dictionary = {}
var drawing: DrawingOverlay
var clamp_dialog: ClampDialog
var tool_slot_dialog: ToolSlotDialog
var quality: QualityStation        # Qualitätsmanagement: hier werden ausgespannte Teile abgegeben
var pins: Array = []               # angepinnte Zeichnungen (PinnedDrawing)
var _drawing_vps: Dictionary = {}  # Auftrag -> SubViewport, das die Zeichnung als Bild rendert
const QM_COLOR := Color(0.7, 0.95, 1.0)
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
var shelf_nodes: Array = []
var _pallet_ghost: Node3D               # Vorschau: wo Q die getragene Palette abstellt
var _pallet_ghost_mat: StandardMaterial3D
var _ghost_n := 0                        # so viele Paletten zeigt die Vorschau gerade
var _crate_ghost: Node3D                 # Vorschau: wo Linksklick die getragene Kiste abstellt
var _crate_ghost_key := []               # Größe und Inhalt, für die die Kisten-Vorschau gebaut ist
var _crate_spot_key := []                # letzter Stellplatz der Kiste (Ziel, Aufstellung) ...
var _crate_spot_cache := {}              # ... und sein Ergebnis
var _bench_spot_cache := {}              # "Größe|Werkbank" -> freie Stellen auf der Platte, siehe _bench_crate_spots
var containers: Array = []        # ChipTray je Spänecontainer im Hof

const CONTAINER_KG := 120.0
const CONTAINER_SORTS := ["stahl", "aluminium", "messing"]
## Teil, das nach der Rückfrage beim nächsten Klick auf einen Container entsorgt wird
var _dispose_armed := ""


func _ready() -> void:
	_build_environment()
	_lights = Workshop.build(self)
	crane = HallCrane.new()
	crane.world = self
	add_child(crane)
	site = Site.new()
	site.world = self
	add_child(site)
	day_cycle = DayCycle.new()
	add_child(day_cycle)
	day_cycle.setup(env, site.sun, _lights)

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

	whiteboard = Whiteboard.new()
	whiteboard.position = Workshop.WHITEBOARD_POS
	whiteboard.rotation.y = Workshop.WHITEBOARD_YAW
	add_child(whiteboard)

	office_clock = OfficeClock.new()
	office_clock.position = Workshop.CLOCK_POS
	office_clock.rotation.y = Workshop.CLOCK_YAW
	office_clock.day_seconds = DAY_SECONDS
	add_child(office_clock)

	quality = QualityStation.new()
	quality.world = self
	quality.position = QualityStation.POS
	add_child(quality)

	player = Player.new()
	player.position = Vector3(0.5, 0.05, 2.5)
	player.drawing_texture = drawing_texture
	player.machine_lookup = _machine_node
	add_child(player)
	player.pin_requested.connect(pin_drawing)

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
	places = Places.new()
	places.world = self
	add_child(places)
	travel_menu = TravelMenu.new()
	travel_menu.world = self
	add_child(travel_menu)
	shop_menu = ShopMenu.new()
	shop_menu.world = self
	add_child(shop_menu)
	places.home_of(player.player_id)
	debug_menu = DebugMenu.new()
	debug_menu.world = self
	add_child(debug_menu)

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
	player.cigarette.notice.connect(func(t: String): hud.show_message(t, Color(0.9, 0.95, 1.0)))
	hud.cigarette = player.cigarette
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
	player.pallet_drop = put_pallet
	player.goods_attach = attach_goods
	player.bin_drop = bin_set_down
	player.crane_click = crane.hook_click
	player.crane_release = crane.release
	player.crane_drop_hint = crane.drop_hint
	player.crane_bench = crane_bench_at
	player.crane_put = crane_put_on_bench
	player.jack_lift = jack_lift
	player.jack_drop = jack_park
	player.bucket_scoop = bucket_scoop
	player.bucket_drop = bucket_drop
	player.crate_drop = crate_set_down
	player.crate_spot = crate_spot.bind(true)
	player.jack_abandon = jack_abandon
	player.forklift_leave = forklift_leave
	whiteboard.shop = self
	whiteboard.overlay.day_app.shop = self
	whiteboard.using_changed.connect(func(on: bool): hud.visible = not on)
	office_clock.shop = self
	office_pc.overlay.dev_app.shop = self
	Settings.changed.connect(_apply_quality)

	_apply_pending(GameState.pending)
	_apply_quality()
	_setup_ambient()
	restore_mouse()
	if company.owns("lathe"):
		hud.show_message("Willkommen in der Werkstatt, %s! Drehmaschine, Werkbank mit Grundwerkzeugen, Bandsäge und ein Regal mit einer Stange stehen bereit. Starte den Tag am Whiteboard im Meisterbüro." % save_name, Color(0.9, 0.95, 1.0))
	else:
		hud.show_message("Willkommen in der Werkstatt, %s! Die Halle ist leer: Am PC im Büro gibt es die erste Drehmaschine und die Bandsäge gratis, dazu Werkbank, Werkzeuge und Aufträge." % save_name, Color(0.9, 0.95, 1.0))


## Drehmaschine oder Rundschleifmaschine an HUD und Aufträge anschließen.
func _wire_lathe(m: Lathe) -> void:
	m.message.connect(hud.show_message)
	if m.kss_station != null:
		m.kss_station.world = self      # Konzentrat-Kosten und Meldungen des KSS-Tanks
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
	m.tailstock_changed.connect(hud.set_other_machine)
	m.tool_lost.connect(_on_tool_lost.bind(m.MACHINE_ID))
	m.submit_requested.connect(_submit_hint)
	if m.grinder_type != "":
		m.new_part_requested.connect(_on_grind_new_part)
	else:
		m.new_part_requested.connect(_on_new_part.bind(m))


## Fräs-, Bohr- oder Flachschleifmaschine an ihre eigene Anzeige und die Aufträge anschließen.
func _wire_mill(m: Mill, mh: MillHUD) -> void:
	m.message.connect(hud.show_message)
	m.operating_changed.connect(mh.set_operating)
	m.operating_changed.connect(hud.set_other_machine)
	m.levers_changed.connect(mh.set_levers_open)
	m.levers_changed.connect(hud.set_other_machine)
	m.tool_lost.connect(_on_tool_lost.bind(m.MACHINE_ID))
	m.submit_requested.connect(_submit_hint)
	if m.grinder_type != "":
		m.operating_changed.connect(func(on: bool): _hint_grinder(on, m))
		m.new_part_requested.connect(_on_grind_new_part)
	else:
		m.operating_changed.connect(func(on: bool): _hint_empty(on, m.has_part, _need_of(JobBoard.key(job_kind(m.MACHINE_ID), _active_index(m.MACHINE_ID)))); _hint_tool(on, m))
		m.new_part_requested.connect(_on_mill_new_part.bind(m))


func _hint_grinder(on: bool, m: Node) -> void:
	if on and not m.has_part:
		hud.show_message("Schleifmaschine: spannt nur vorbearbeitete Teile. Auftrag mit Schleifanforderung abgeben, Teil herbringen und mit Linksklick einspannen.", Color(1, 0.75, 0.2))


func _add_mount(machine: Node) -> void:
	var mount := ToolMount.new()
	mount.machine = machine
	mount.player = player
	if machine is Lathe:
		mount.dialog = _tool_slot_dialog()
	machine.add_child(mount)
	machine.tool_mount = mount


## Fenster am Werkzeughalter, wird beim ersten Halter angelegt.
func _tool_slot_dialog() -> ToolSlotDialog:
	if tool_slot_dialog == null:
		tool_slot_dialog = ToolSlotDialog.new()
		tool_slot_dialog.world = self
		add_child(tool_slot_dialog)
	return tool_slot_dialog


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

	# Reflexionen: je Raum eine Sonde, deren Kasten genau die Wände trifft (Box-Projektion), aufgenommen auf
	# Augenhöhe, damit Spiegelungen in Blechen, Glas und Drehteilen dort liegen, wo der Spieler sie erwartet.
	# Die Aufnahme ist einmalig und wird erneuert, wenn sich das Licht (Tag/Nacht) oder die Einrichtung ändert.
	var hw := Workshop.W * 0.5
	var hd := Workshop.D * 0.5
	probe = _add_probe(Vector3(-hw, 0, -hd), Vector3(hw, Workshop.H, hd), 0.4)
	_add_probe(Vector3(Workshop.OFFICE_X.x, 0, hd), Vector3(Workshop.OFFICE_X.y, Workshop.OFFICE_H, Workshop.OFFICE_Z1), 0.2)
	_add_probe(Vector3(Workshop.QM_X.x, 0, hd), Vector3(Workshop.QM_X.y, Workshop.OFFICE_H, Workshop.OFFICE_Z1), 0.2)


## Innenraum-Sonde für den Quader a..b (Boden bis Decke). Aufnahmepunkt auf 1,6 m Augenhöhe.
func _add_probe(a: Vector3, b: Vector3, blend: float) -> ReflectionProbe:
	var p := ReflectionProbe.new()
	var size := b - a
	p.size = size
	p.position = (a + b) * 0.5
	p.origin_offset = Vector3(0, minf(1.6, size.y * 0.5) - size.y * 0.5, 0)
	p.box_projection = true
	p.interior = true
	p.blend_distance = blend
	p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	p.update_mode = ReflectionProbe.UPDATE_ONCE
	p.max_distance = maxf(size.x, size.z)
	add_child(p)
	probes.append(p)
	return p


## Reflexionen neu aufnehmen lassen (z. B. nach einem Umbau). Mehrere Anfragen kurz hintereinander
## führen zu einer Aufnahme.
func request_reflections() -> void:
	_probe_due = true


func _update_reflections(delta: float) -> void:
	_probe_wait = maxf(0.0, _probe_wait - delta)
	var building: bool = player != null and player.build_mode
	if _was_building and not building:
		_probe_due = true
	_was_building = building
	if day_cycle != null and absf(day_cycle.daylight - _probe_light) > 0.08:
		_probe_due = true
	if not _probe_due or _probe_wait > 0.0 or building:
		return
	_probe_due = false
	_probe_wait = 1.5
	if day_cycle != null:
		_probe_light = day_cycle.daylight
	for p in probes:
		# Jede Änderung an der Sonde markiert sie im RenderingServer als veraltet; UPDATE_ONCE nimmt dann neu auf.
		p.intensity = p.intensity


func _apply_quality() -> void:
	var q := int(Settings.graphics["quality"])
	env.ssao_enabled = q >= 1
	env.ssao_intensity = 1.6
	env.ssr_enabled = q >= 2
	# Bildschirmraum-Spiegelungen weich ein- und ausblenden, sonst reißen sie am Bildrand und hinter Kanten ab
	env.ssr_max_steps = 96 if q >= 3 else 64
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.3
	env.ssil_enabled = q >= 3
	Settings.apply_bloom(env)
	env.adjustment_brightness = float(Settings.graphics["brightness"])
	for l in _lights.get("shadow_lights", []):
		(l as Light3D).shadow_enabled = q >= 2
	lathe.lamp.shadow_enabled = q >= 1
	mill.lamp.shadow_enabled = q >= 2
	for p in probes:
		p.visible = q >= 1
		p.enable_shadows = q >= 2
	request_reflections()


func _process(delta: float) -> void:
	play_time += delta
	_tick_autosave(delta)
	_advance_day(delta * time_scale)
	_update_reflections(delta)
	_fill_ambient()
	_update_pallet_ghost()
	_update_crate_ghost()


## Durchscheinende Palette dort, wo die Ablegen-Taste die getragene Palette abstellt:
## grün = frei, rot = geht dort nicht.
func _update_pallet_ghost() -> void:
	var n := 0
	var at := Vector2.ZERO
	var rot := 0
	if player != null and not player.operating and not player.build_mode:
		if player.carrying_pallet():
			n = 1
			at = player.pallet_spot()
			rot = player.pallet_rot()
		elif player.jack_load() > 0:
			# Hubwagen: Die Last wird dort abgesenkt, wo sie auf der Gabel liegt
			n = player.jack_load()
			at = player.jack_spot()
			rot = player.jack_load_rot()
	if n == 0:
		if _pallet_ghost:
			_pallet_ghost.visible = false
		return
	if not _pallet_ghost:
		_ghost_material()
		_pallet_ghost = Node3D.new()
		add_child(_pallet_ghost)
	if n != _ghost_n:
		for c in _pallet_ghost.get_children():
			_pallet_ghost.remove_child(c)
			c.queue_free()
		Shelf.add_pallets(_pallet_ghost, n)
		_ghostify(_pallet_ghost)
		_ghost_n = n
	var is_free: bool
	var stack: Shelf = player.pallet_target() if player.carrying_pallet() else null
	if stack and stack.is_inside_tree():
		# Auf einen Stapel gezielt: Vorschau liegt oben auf der obersten Palette
		var h := float(Shelf.SIZES["pallet"]["height"])
		is_free = stack.stack < Shelf.MAX_STACK
		_pallet_ghost.global_transform = stack.global_transform.translated(Vector3(0, h * stack.stack + 0.003, 0))
	else:
		is_free = layout.check_shelf("pallet", at, rot) == ""
		_pallet_ghost.transform = Transform3D(Basis(Vector3.UP, rot * PI / 2.0), Vector3(at.x, 0.003, at.y))
	_pallet_ghost_mat.albedo_color = _ghost_color(is_free)
	_pallet_ghost.visible = true


## Durchscheinende Kiste samt Inhalt dort, wo Linksklick die getragene Kiste abstellt (immer beim Tragen):
## grün = frei, rot = geht dort nicht. Gleiche Optik wie die Paletten-Vorschau.
func _update_crate_ghost() -> void:
	var wanted: bool = player != null and player.carrying_crate() and not player.operating and not player.build_mode
	if not wanted:
		if _crate_ghost:
			_crate_ghost.visible = false
		return
	var size_id := str(player.carry["size"])
	var items: Array = player.carry["items"]
	var key := [size_id, items.size()]
	if not _crate_ghost or key != _crate_ghost_key:
		if _crate_ghost:
			_crate_ghost.queue_free()
		_ghost_material()
		_crate_ghost = Crate.make_model(size_id, items)
		add_child(_crate_ghost)
		_ghostify(_crate_ghost)
		_crate_ghost_key = key
	var s := crate_spot(player.crate_aim(), true)
	var at: Vector2 = s["pos"]
	var y := ToolBench.TOP_Y if bool(s["top"]) else 0.0
	_crate_ghost.transform = Transform3D(Basis(Vector3.UP, int(s["rot"]) * PI / 2.0), Vector3(at.x, y + 0.003, at.y))
	# Die Paletten-Vorschau teilt das Material: Beide sind nie gleichzeitig zu sehen
	_pallet_ghost_mat.albedo_color = _ghost_color(str(s["err"]) == "")
	_crate_ghost.visible = true


## Gemeinsames durchscheinendes Material der Vorschauen (Paletten und Kisten).
func _ghost_material() -> StandardMaterial3D:
	if _pallet_ghost_mat == null:
		_pallet_ghost_mat = StandardMaterial3D.new()
		_pallet_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_pallet_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _pallet_ghost_mat


static func _ghost_color(is_free: bool) -> Color:
	return Color(0.35, 1.0, 0.45, 0.38) if is_free else Color(1.0, 0.3, 0.25, 0.38)


func _ghostify(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = _pallet_ghost_mat
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is CollisionObject3D:
		(n as CollisionObject3D).collision_layer = 0
		(n as CollisionObject3D).collision_mask = 0
	for c in n.get_children():
		_ghostify(c)


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
	if day_over:
		_evening += delta
	day_cycle.set_hour(sky_hour())
	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = 1.0
		_show_clock()


## Stunde für Sonne und Himmel, durchgehend gezählt (nach Mitternacht über 24): Vor dem Start dämmert es um 6 Uhr,
## der Tag läuft in 12 Minuten von 6 bis 18 Uhr, nach Feierabend die Nacht in 12 Minuten bis 6 Uhr morgens.
## Danach bleibt es Morgen, bis der Tag am Whiteboard beendet wird.
func sky_hour() -> float:
	if not day_started:
		return 6.0
	if day_over:
		return 18.0 + minf(_evening / NIGHT_SECONDS, 1.0) * 12.0
	return 6.0 + clampf(day_time / DAY_SECONDS, 0.0, 1.0) * 12.0


## Uhrzeit: Tagsüber läuft sie von 6 bis 18 Uhr, nach Feierabend weiter durch die Nacht.
func clock_text() -> String:
	var minutes := int(sky_hour() * 60.0) % (24 * 60) if day_started else 6 * 60
	@warning_ignore("integer_division")
	return "Tag %d   %02d:%02d" % [day, minutes / 60, minutes % 60]


func _show_clock() -> void:
	var text := clock_text()
	if not day_started:
		text += "   Tag noch nicht gestartet: am Whiteboard im Büro"
	elif day_over:
		text += "   FEIERABEND: am Hoftor nach Hause gehen und schlafen"
	hud.set_clock(text, day_over)
	whiteboard.refresh()


## Tag ist um: Das laufende Teil lässt sich noch fertigstellen, sonst geht nichts Neues mehr.
func end_day() -> void:
	if day_over:
		return
	day_over = true
	_show_clock()
	hud.show_message("Feierabend: Das laufende Teil lässt sich noch abgeben, neue Aufträge und Einkäufe gibt es erst morgen. Am Hoftor nach Hause gehen und schlafen.", Color(1, 0.75, 0.3))
	office_pc.overlay.refresh_all()


## Warum gerade nicht geschlafen werden kann, leer = es geht.
func sleep_error() -> String:
	if not day_started:
		return "Ausgeschlafen: Der Tag wartet auf den Start am Whiteboard im Büro."
	if not day_over:
		return "Noch kein Feierabend: Erst um 18 Uhr oder nach \"Tag beenden\" am Whiteboard im Büro geht es ins Bett."
	return ""


## Im Bett zuhause: schlafen, wenn es geht, sonst sagen, warum nicht.
func sleep_in_bed(p: Node) -> void:
	var err := go_sleep(p)
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.3))


## Schlafen: Der nächste Tag beginnt sofort, man wacht neben dem eigenen Bett auf. Danach wird gespeichert.
## Multiplayer später: Der Tag ist für alle gleich, dann erst weiterschalten, wenn alle im Bett liegen.
func go_sleep(p: Node) -> String:
	var err := sleep_error()
	if err != "":
		return err
	if p.driving_jack():
		jack_abandon()          # der Hubwagen bleibt in der Werkstatt, nichts geht verloren
	next_day()
	start_day()
	var home := places.home_of(p.player_id)
	p.global_position = home.wake_point()
	p.velocity = Vector3.ZERO
	p.location = home.id
	hud.show_message("Ausgeschlafen. Tag %d beginnt: durch die Haustür zur Werkstatt." % day, Color(0.9, 0.95, 1.0))
	if autosave:
		save_game()
	return ""


## Hier kommt man aufs Gelände zurück: innen am Hoftor, Blick zur Halle.
func site_entry() -> Vector3:
	return SITE_ENTRY


func site_entry_yaw() -> float:
	return 0.0


## Supermarkt: Zigaretten aus Supermarket.GOODS kaufen, bezahlt wird aus der Kasse der Werkstatt.
func buy_cigarettes(p: Node, i: int) -> String:
	if i < 0 or i >= Supermarket.GOODS.size():
		return "Gibt es nicht."
	var g: Dictionary = Supermarket.GOODS[i]
	var price := 0 if free_mode else int(g["price"])
	if money < price:
		return "Zu wenig Geld in der Kasse."
	money -= price
	p.cigarette.stock += int(g["count"])
	return ""


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
	_evening = 0.0
	day_over = false
	day_started = false
	last_day_stats = day_stats
	day_stats = {}
	_check_deadlines()
	_show_clock()
	_jobs_changed()
	hud.show_message("Tag %d: am Whiteboard im Büro starten." % day, Color(0.9, 0.95, 1.0))


## Darf der Spieler dieses Ziel gerade benutzen? Vor Tagesbeginn wird nichts bearbeitet. silent: nur prüfen.
func _work_blocked(target: Node, silent: bool) -> bool:
	if day_started or free_mode or target == null:
		return false
	if not (target is Lathe or target is Mill or target is BandSaw or target is ToolMount or target is Lathe.LeverTarget or target is MillLeverPanel):
		return false
	if not silent:
		hud.show_message("Der Tag hat noch nicht begonnen: am Whiteboard im Büro starten.", Color(1, 0.75, 0.2))
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
	for n in get_tree().get_nodes_in_group(DroppedItem.GROUP):
		if str(n.item.get("kind", "")) == "semi" and str(n.item.get("key", "")) == key:
			n.discard()
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
		return "Der Tag hat noch nicht begonnen: am Whiteboard im Büro starten."
	return "Feierabend: Erst morgen wieder. Am Hoftor nach Hause gehen und schlafen." if day_over else ""


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
	return accepted.has(JobBoard.key(job_kind(machine), _active_index(machine)))


## Auftragsart einer Maschine: Beide Drehmaschinen bekommen Drehaufträge, beide Fräsmaschinen Fräsaufträge.
static func job_kind(machine: String) -> String:
	match machine:
		"cnc_lathe":
			return "lathe"
		"cnc_mill":
			return "mill"
	return machine


## Gewählter Auftrag einer Maschinenart. Beide Drehmaschinen teilen sich einen, beide Fräsmaschinen auch.
func _active_index(machine: String) -> int:
	match job_kind(machine):
		"lathe":
			return job_index
		"drill":
			return drill_job_index
	return mill_job_index


func _active_job(machine: String) -> Dictionary:
	var kind := job_kind(machine)
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
	whiteboard.refresh()


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
		elif job_kind(id) == "mill":
			if has_job(id):
				mh.set_job(_active_job(id), JobBoard.grind_active(_active_job(id), company))
			else:
				mh.set_no_job()
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
		var category := "lathe" if op is Lathe else job_kind(id)
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




func _lathe_new_workpiece(m: Lathe = null) -> void:
	if m == null:
		m = lathe
	var job := _current_job()
	m.set_material(str(job.get("material", Materials.DEFAULT)))
	m.new_workpiece(float(job["stock_d"]), float(job["stock_len"]))


func _on_new_part(m: Lathe = null) -> void:
	hud.show_message(_lathe_take_part(m), Color(0.9, 0.95, 1.0))
	_refresh_hud()




# ------------------------------------------------------------ Schleifen

## Vorbearbeitet und bezahlt: Das Teil kommt in die Hände und muss noch zur Schleifmaschine. Die Erfahrung
## gibt es erst, wenn der ganze Auftrag fertig ist. part = part_state des Teils.
func _send_to_grinding(key: String, part: Dictionary) -> String:
	var job := JobBoard.job_of(key)
	accepted.erase(key)
	_job_gone(key)
	grind_jobs.append(key)
	player.set_carry({"kind": "semi", "key": key, "type": job["grind"]["type"], "title": job["title"], "part": part})
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


func _clear_grinder(m: Node) -> void:
	m.semi_key = ""
	m.ceramic_part = false
	m.clear_workpiece()


# ------------------------------------------------------------ Ausspannen und Qualitätsmanagement

## Abgabetaste an der Maschine: Verkauft wird dort nichts mehr. Sie misst das Teil nur zwischendurch.
func _submit_hint() -> void:
	var m: Node = player.operating
	var how := "Teile werden im Qualitätsmanagement abgegeben: Maschine verlassen, mit Linksklick aufs Teil ausspannen und zum Prüfplatz an der Südwand bringen."
	if m == null or not (m is Lathe or m is Mill) or not m.has_part:
		hud.show_message(how, Color(0.9, 0.95, 1.0))
		return
	var key := _key_in(m)
	if key == "":
		hud.show_message("Kein passender Auftrag zum Messen. " + how, Color(1, 0.75, 0.2))
		return
	var job := JobBoard.job_of(key)
	var res: Dictionary = m.evaluate_grind(job) if m.grinder_type != "" else m.evaluate(job)
	var lines: Array = res["lines"]
	hud.show_result("ZWISCHENMESSUNG - %s\n\n%s\n\n%d / %d Merkmale in Ordnung\n\n%s" % [job["title"], "\n".join(lines), int(res["ok"]), int(res["total"]), how])


## Auftrag, zu dem das eingespannte Teil gehört. Leer = keiner.
func _key_in(m: Node) -> String:
	if m.grinder_type != "":
		return str(m.semi_key)
	var category := "lathe" if m is Lathe else job_kind(str(m.MACHINE_ID))
	return JobBoard.key(category, _active_index(category)) if has_job(category) else ""


## Ausgespanntes Teil zum Tragen: Maße für die Kiste, Kontur zum Wiedereinspannen und das Prüfergebnis.
func _part_item(m: Node, key: String, res: Dictionary) -> Dictionary:
	var it := {"kind": "part", "key": key, "machine": str(m.MACHINE_ID), "material": str(m.material), "part": m.part_state(), "res": res,
		"title": str(JobBoard.job_of(key)["title"]) if key != "" else "Teil ohne Auftrag"}
	if m is Lathe:
		it["shape"] = "round"
		it["d"] = float(m.stock_d)
		it["l"] = float(m.stock_len)
	else:
		it["shape"] = "block"
		it["l"] = float(m.block_l)
		it["w"] = float(m.block_w)
		it["h"] = float(m.block_h)
	return it


## Teil aus der Maschine in die Hände nehmen. Unbearbeitetes Rohmaterial bleibt Rohmaterial, alles andere ist
## ein Teil für das Qualitätsmanagement oder eine Kiste. Fehlertext, leer = ausgespannt.
func unclamp_part(m: Node) -> String:
	if m == null or not m.has_part:
		return "Es ist kein Teil eingespannt."
	if m.spindle_speed > 5.0:
		return "Erst die Spindel stoppen."
	var door := _door_block(m)
	if door != "":
		return door
	if not player.hands_free():
		return "Erst die Hände frei machen."
	var item := {}
	var text := ""
	if m.grinder_type != "":
		var key: String = str(m.semi_key)
		item = _part_item(m, key, m.evaluate_grind(JobBoard.job_of(key)) if key != "" else {})
		item["grind"] = key != ""
		_clear_grinder(m)
		text = "Ausgespannt: %s. Im Qualitätsmanagement prüfen lassen." % item["title"]
	else:
		var untouched: bool = (m.is_untouched() if m is Lathe else m.untouched) and not m.ceramic_part
		if untouched:
			if m is Lathe:
				item = {"kind": Materials.KIND_ROUND, "sawn": true, "material": str(m.material), "d": float(m.stock_d), "l": float(m.stock_len)}
			else:
				item = {"kind": Materials.KIND_CUT, "material": str(m.material), "l": float(m.block_l), "w": float(m.block_w), "h": float(m.block_h)}
			text = "Rohteil ausgespannt: ins Regal, in eine Kiste oder an einer anderen Maschine einspannen."
		else:
			var key := _key_in(m)
			item = _part_item(m, key, m.evaluate(JobBoard.job_of(key)) if key != "" else {})
			text = "Ausgespannt: %s. Im Qualitätsmanagement an der Südwand abgeben oder in eine Kiste legen." % item["title"]
		m.clear_workpiece()
	player.set_carry(item)
	player._focus = null
	hud.show_message(text, QM_COLOR)
	_jobs_changed()
	return ""


func qm_prompt() -> String:
	if player.carrying_part():
		var it: Dictionary = player.carry
		if not _qm_open(it):
			return "[Linksklick] Teil ohne offenen Auftrag verschrotten    |    Qualitätsmanagement"
		return "[Linksklick] %s zur Prüfung abgeben    |    Qualitätsmanagement" % it["title"]
	if player.carrying_semi():
		return "Vorbearbeitetes Teil: erst auf die Schleifmaschine    |    Qualitätsmanagement"
	return "Qualitätsmanagement: ausgespannte Teile hier abgeben"


func qm_click() -> void:
	if not player.carrying_part():
		if player.hands_free():
			hud.show_message("Hier werden fertige Teile abgegeben: an der Maschine mit Linksklick aufs Teil ausspannen und herbringen.", Color(0.9, 0.95, 1.0))
		return
	var err := qm_submit()
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.2))


## Gehört das Teil zu einem Auftrag, der noch offen ist?
func _qm_open(it: Dictionary) -> bool:
	var key := str(it.get("key", ""))
	if key == "" or (it.get("res", {}) as Dictionary).is_empty():
		return false
	return grind_jobs.has(key) if bool(it.get("grind", false)) else accepted.has(key)


## Teil aus den Händen prüfen lassen und abrechnen. Fehlertext, leer = abgegeben.
func qm_submit() -> String:
	if not player.carrying_part():
		return "Kein ausgespanntes Teil in den Händen."
	var item: Dictionary = player.carry
	if not _qm_open(item):
		player.clear_carry()
		quality.show_result("%s\nKein offener Auftrag:\nverschrottet." % item.get("title", "Teil"))
		hud.show_message("Zu diesem Teil gibt es keinen offenen Auftrag: Es wurde verschrottet.", Color(1, 0.75, 0.2))
		return ""
	if bool(item.get("grind", false)):
		_qm_grind(item)
		return ""
	var key := str(item["key"])
	var job := JobBoard.job_of(key)
	var res: Dictionary = item["res"]
	var score := _material_score(float(res["score"]), str(item["material"]), job)
	var to_grind: bool = score >= 0.999 and JobBoard.grind_active(job, company)
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
	player.clear_carry()
	if to_grind:
		text += _send_to_grinding(key, item["part"])
	elif score >= 0.999:
		text += _finish_job(key)
	hud.show_result(text)
	quality.show_result("%s\n%d / %d Merkmale i.O.\n%s\n%d EUR" % [job["title"], int(res["ok"]), int(res["total"]), verdict, pay])
	_jobs_changed()
	return ""


## Geschliffenes Teil prüfen. Passt die Fläche noch nicht, kommt es zurück in die Hände zum Weiterschleifen.
## Sind die Maße verschliffen, ist das Teil Ausschuss und der Auftrag ohne Schleifvergütung beendet.
func _qm_grind(item: Dictionary) -> void:
	var key := str(item["key"])
	var job := JobBoard.job_of(key)
	var g: Dictionary = job["grind"]
	var res: Dictionary = item["res"]
	var lines: Array = res["lines"]
	var ok_all: bool = int(res["ok"]) == int(res["total"])
	var measures_ok: bool = int(res["ok"]) >= int(res["total"]) - 1 and str(lines[lines.size() - 1]).begins_with("FEHL")
	var head := "PRÜFPROTOKOLL SCHLEIFEN - %s\n\n%s\n\n" % [job["title"], "\n".join(lines)]
	player.clear_carry()
	if ok_all:
		var pay := _pay(float(g["reward"]))
		money += pay
		parts += 1
		var text := head + "Fläche in Ordnung - sehr gut!\nVergütung: %d EUR" % pay
		grind_jobs.erase(key)
		text += _finish_job(key)
		hud.show_result(text)
		quality.show_result("%s\nGeschliffen i.O.\n%d EUR" % [job["title"], pay])
	elif measures_ok:
		player.set_carry({"kind": "semi", "key": key, "type": g["type"], "title": job["title"], "part": item["part"]})
		hud.show_result(head + "Die Fläche ist noch nicht fertig: Das Teil liegt wieder in deinen Händen. Erneut einspannen, weiterschleifen, zuletzt fein zustellen und langsam fahren.")
		quality.show_result("%s\nFläche noch nicht fertig:\nweiterschleifen." % job["title"])
	else:
		grind_jobs.erase(key)
		deadlines.erase(key)
		company.change_reputation(REP_SCRAP, day, "Ausschuss: %s" % job["title"])
		hud.show_result(head + "Maße verschliffen: Ausschuss! Keine Schleifvergütung.")
		quality.show_result("%s\nMaße verschliffen:\nAusschuss." % job["title"])
	_jobs_changed()


## Abgabe wie früher in einem Schritt: ausspannen und gleich prüfen lassen. Fehlertext, leer = abgegeben.
func _submit_direct(m: Node, untouched: bool, category: String) -> void:
	var err := ""
	if not m.has_part:
		err = "Es ist kein Rohteil eingespannt."
	elif m.grinder_type != "" and str(m.semi_key) == "":
		err = "Es ist kein vorbearbeitetes Teil eingespannt."
	elif m.grinder_type == "" and untouched:
		err = "Das Rohteil ist noch unbearbeitet."
	elif m.grinder_type == "" and not has_job(category):
		err = "Kein %s angenommen. Aufträge gibt es am PC im Büro." % JobBoard.MACHINE_NAMES.get(category, "Auftrag")
	if err == "":
		err = unclamp_part(m)
	if err == "":
		err = qm_submit()
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.2))


func _on_submit(m: Lathe = null) -> void:
	if m == null:
		m = lathe
	_submit_direct(m, m.is_untouched(), "lathe")


func _on_mill_submit(m: Mill = null) -> void:
	if m == null:
		m = mill
	_submit_direct(m, m.untouched, job_kind(m.MACHINE_ID))


func _on_grind_submit(m: Node) -> void:
	_submit_direct(m, false, "")


## Teil aus den Händen wieder einspannen, zum Beispiel aus der Kiste. Fehlertext, leer = eingespannt.
func _clamp_part(machine: Node) -> String:
	var item: Dictionary = player.carry
	var err := _part_fit(machine, item)
	if err == "":
		err = _door_block(machine)
	if err == "" and machine.spindle_speed > 5.0:
		err = "Erst die Spindel stoppen."
	elif err == "" and machine.has_part:
		err = "Es ist schon ein Teil eingespannt: erst mit Linksklick aufs Teil ausspannen."
	if err == "":
		err = _tray_conflict(machine, str(item["material"]))
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.2))
		return err
	machine.load_part(item["part"])
	player.clear_carry()
	_jobs_changed()
	return ""


## Passt das ausgespannte Teil auf diese Maschine? Fehlertext, leer = ja.
func _part_fit(machine: Node, item: Dictionary) -> String:
	var round_part := str(item.get("shape", "")) == "round"
	if not machine is Lathe and not machine is Mill:
		return "Hier lässt sich nichts einspannen."
	if machine.grinder_type != "":
		return "Schleifmaschinen spannen nur vorbearbeitete Teile."
	if machine is Lathe and not round_part:
		return "Die Drehmaschine spannt nur runde Teile."
	if machine is Mill and round_part:
		return "Der Schraubstock spannt nur eckige Teile."
	return ""


## Kurzbeschreibung eines Stücks für Kisten und Hinweise.
func _item_text(it: Dictionary) -> String:
	if str(it.get("kind", "")) == "part":
		return "%s (%s)" % [it.get("title", "Teil"), Materials.label(str(it["material"]))]
	return "%s  %s" % [Materials.label(str(it["material"])), RawMaterialTab.describe(it)]


# ------------------------------------------------------------ Zeichnungen in der Hand und an der Wand

## Bild der Zeichnung für Blatt und Hand. Je Auftrag wird es einmal gerendert.
func drawing_texture(job: Dictionary) -> Texture2D:
	var id := JSON.stringify(job).hash()
	if not _drawing_vps.has(id):
		var vp := SubViewport.new()
		vp.size = Vector2i(1120, 660)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.gui_disable_input = true
		var d := PartDrawing.new()
		d.printed = true
		d.job = job
		d.position = Vector2.ZERO
		d.size = Vector2(1120, 660)
		d.theme = UITheme.build()
		vp.add_child(d)
		add_child(vp)
		_drawing_vps[id] = vp
	return (_drawing_vps[id] as SubViewport).get_texture()


## Ausgedruckte Zeichnung in die Hand nehmen. Fehlertext, leer = in der Hand.
func take_drawing(job: Dictionary) -> String:
	if job.is_empty():
		return "Keine Zeichnung: Es ist kein Auftrag gewählt."
	if player.operating != null:
		return "Erst die Maschine verlassen, dann die Zeichnung nehmen."
	if not player.hands_free():
		return "Erst die Hände frei machen."
	player.set_carry({"kind": "drawing", "job": job.duplicate(true)})
	hud.show_message("Zeichnung in der Hand: Mit Linksklick an eine Fläche pinnen, zum Beispiel an die Maschinentür. Rechtsklick legt sie weg.", QM_COLOR)
	return ""


## Zeichnung aus der Hand an die Stelle pinnen, auf die der Blick fällt.
func pin_drawing(collider: Object, point: Vector3, normal: Vector3) -> void:
	if not player.carrying_drawing():
		return
	var n := normal.normalized()
	var up := Vector3.UP
	if absf(n.dot(up)) > 0.9:
		# Waagrecht (Tisch, Boden): Die Oberkante zeigt vom Spieler weg
		up = -player.global_transform.basis.z
		up = (up - n * up.dot(n)).normalized()
	var x := up.cross(n).normalized()
	var y := n.cross(x).normalized()
	var xf := Transform3D(Basis(x, y, n), point + n * 0.002)
	_add_pin(player.carry["job"], xf, collider as Node3D)
	player.clear_carry()
	hud.show_message("Zeichnung angepinnt. [%s] zeigt sie groß, Linksklick nimmt sie wieder ab." % Settings.binding_text("interact"), QM_COLOR)


func _add_pin(job: Dictionary, xf: Transform3D, anchor: Node3D) -> PinnedDrawing:
	var p := PinnedDrawing.new()
	p.world = self
	p.job = job
	add_child(p)
	p.global_transform = xf
	p.attach(anchor)
	pins.append(p)
	return p


func pin_prompt(pin: PinnedDrawing) -> String:
	var what := "Zeichnung %s" % str(pin.job.get("title", ""))
	if not player.hands_free():
		return "[%s] %s ansehen    |    Hände voll" % [Settings.binding_text("interact"), what]
	return "[%s] %s ansehen    [Linksklick] Abnehmen" % [Settings.binding_text("interact"), what]


## Angepinnte Zeichnung wieder in die Hand nehmen.
func pin_click(pin: PinnedDrawing) -> void:
	if not player.hands_free():
		return
	pins.erase(pin)
	var job := pin.job
	pin.queue_free()
	player._focus = null
	player.set_carry({"kind": "drawing", "job": job})


func _pin_states() -> Array:
	var out: Array = []
	for p in pins:
		if not is_instance_valid(p):
			continue
		var t: Transform3D = p.global_transform
		out.append({"job": p.job, "xf": [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
			t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]})
	return out


## Geladene Zeichnungen wieder an den Körper hängen, auf dem sie sitzen (zum Beispiel eine Maschinentür).
func _anchor_pins() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for p in pins:
		if not is_instance_valid(p) or p.anchor != null:
			continue
		var n: Vector3 = p.global_transform.basis.z.normalized()
		var q := PhysicsRayQueryParameters3D.create(p.global_position + n * 0.05, p.global_position - n * 0.05)
		q.exclude = [p.body.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] is Node3D:
			p.attach(hit["collider"])


## Falscher Werkstoff ist Ausschuss, egal wie gut die Maße sind.
func _material_score(score: float, used: String, job: Dictionary) -> float:
	var want := str(job.get("material", Materials.DEFAULT))
	if used == want:
		return score
	hud.show_message("Falscher Werkstoff: %s statt %s!" % [Materials.label(used), Materials.label(want)], Color(1, 0.45, 0.35))
	return 0.0


# ------------------------------------------------------------ Rohmaterial

## Taste ^ öffnet und schließt das Debug-Menü (Testmodus, Noclip, Zeit, Geld). Auf deutschen Tastaturen ist ^
## eine Tottaste, darum auch nach Lage.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode != KEY_ASCIICIRCUM and event.key_label != KEY_ASCIICIRCUM and event.physical_keycode != KEY_QUOTELEFT:
		return
	# Beim Eintippen von Werten oder NC-Programmen schaltet die Taste nichts um
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or lathe.typing() or (cnc_lathe != null and cnc_lathe.typing()) or (cnc_mill != null and cnc_mill.typing()):
		return
	# An einer Maschine oder in einem anderen Menü bleibt es zu, das Debug-Menü selbst schließt die Taste
	if debug_menu.visible or player.operating == null:
		debug_menu.toggle()
		get_viewport().set_input_as_handled()


## Debug: Uhrzeit setzen. 6 bis 18 Uhr ist Arbeitstag, sonst Nacht nach Feierabend (bis 6 Uhr morgens).
func debug_set_hour(h: float) -> void:
	if not day_started:
		start_day()
	if h >= 6.0 and h < 18.0:
		day_over = false
		_evening = 0.0
		day_time = (h - 6.0) / 12.0 * DAY_SECONDS
	else:
		day_time = DAY_SECONDS
		if not day_over:
			end_day()
		var hh := h if h >= 18.0 else h + 24.0
		_evening = (hh - 18.0) / 12.0 * NIGHT_SECONDS
	day_cycle.shown = -1.0
	day_cycle.set_hour(sky_hour())
	_show_clock()


func set_free_mode(on: bool) -> void:
	free_mode = on
	hud.set_free_mode(on)
	office_pc.overlay.refresh_all()


## Werkzeug zerstört oder verschlissen: Es ist weg und muss am PC neu gekauft werden.
func _on_tool_lost(_price: int, tool_name: String, _machine: String) -> void:
	hud.append_message("%s ist hin: am PC im Shop neu kaufen." % tool_name)
	office_pc.overlay.tool_tab.refresh()


func _hint_tool(on: bool, machine: Node) -> void:
	# Die CNC-Fräsmaschine holt ihre Werkzeuge aus dem Magazin, ein Platz dort zählt als vorhanden
	if machine is CncMill and not machine.magazine_tools().is_empty():
		return
	if on and machine.has_part and not machine.has_cutter():
		hud.show_message("Kein Werkzeug eingesetzt: am PC kaufen, an der Werkbank nehmen und mit Linksklick einsetzen.", Color(1, 0.75, 0.2))


## Kabinentür der CNC-Fräsmaschine: Teile spannt man nur bei ganz offener Tür. Fehlertext, leer = erlaubt.
func _door_block(machine: Node) -> String:
	return machine.clamp_blocked() if machine is CncMill else ""


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
	var id: String = job_kind(m.MACHINE_ID)
	var door := _door_block(m)
	if door != "":
		return door
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
	# Höchstens PALLET_MAX_LOAD Ladehöhe je Palette: Was nicht draufpasst, kommt auf eine weitere
	Site.split_pallets(deliveries)
	# Eine Palette, von der nichts mehr da ist, braucht keinen Platz mehr gemerkt
	if not delivery_spots.is_empty():
		var keys := {}
		for it in deliveries:
			keys[Site.delivery_key(it)] = true
		for k in delivery_spots.keys():
			if not keys.has(k):
				delivery_spots.erase(k)
	site.show_deliveries(deliveries, delivery_spots)
	if layout:
		layout.goods.clear()
		for g in delivery_view():
			if not bool(g["carried"]):
				var p: Vector3 = g["pos"]
				layout.goods.append(Site.delivery_rect(Vector2(p.x, p.z), int(g["rot"]), g["extent"]))


## Lieferpaletten samt Lage, wie sie gerade stehen (Site.place_deliveries).
func delivery_view() -> Array:
	return Site.place_deliveries(deliveries, delivery_spots)


## Die Stücke der Lieferpalette mit diesem delivery_key.
func _goods_items(key: String) -> Array:
	return deliveries.filter(func(it: Dictionary) -> bool: return Site.delivery_key(it) == key)


## Ware der Lieferpalette key auf eine Palette legen, die gerade ein Fahrzeug trägt (parent: Palettenmitte am Boden der Palette).
func attach_goods(parent: Node3D, key: String) -> void:
	var list := _goods_items(key)
	if list.is_empty() or site == null:
		return
	var holder := Node3D.new()
	holder.name = "Goods"
	holder.position.y = Site.PALLET_TOP
	holder.rotation.y = -PI / 2.0         # Stücke liegen längs Z, die lange Palettenseite längs X
	parent.add_child(holder)
	site.add_goods(holder, list)


## Alle Lieferpaletten am Boden an ihrem jetzigen Platz festhalten, bevor eine davon aufgenommen wird
## (sonst rücken die übrigen im Raster nach). Die oberen Lagen des Rasters bleiben im Raster.
func _freeze_deliveries() -> void:
	for g in delivery_view():
		var p: Vector3 = g["pos"]
		if bool(g["moved"]) or p.y > Site.PALLET_TOP + 0.01:
			continue
		delivery_spots[str(g["key"])] = {"pos": Vector2(p.x, p.z), "rot": int(g["rot"]), "carried": false}


## Lieferpalette g (aus delivery_view) auf ein Fahrzeug nehmen: Sie verschwindet vom Boden, bleibt in deliveries.
func _carry_goods(g: Dictionary) -> String:
	_freeze_deliveries()
	var key := str(g["key"])
	delivery_spots[key]["carried"] = true
	player._focus = null
	_deliveries_changed()
	return key


## Lieferpalette key am Boden absetzen. Fehlertext, leer = steht.
func put_goods(key: String, at: Vector2, rot: int) -> String:
	var list := _goods_items(key)
	if list.is_empty():
		return "Diese Lieferung gibt es nicht mehr."
	var err := check_goods_spot(at, rot, Site.delivery_extent(list), key)
	if err != "":
		return err
	delivery_spots[key] = {"pos": at, "rot": posmod(rot, 4), "carried": false}
	player._focus = null
	_deliveries_changed()
	return ""


## Fehlertext, wenn dort keine Lieferpalette (ext: lange Seite, Breite) stehen darf. Die Palette key zählt nicht als Hindernis.
func check_goods_spot(at: Vector2, rot: int, ext: Vector2, key: String) -> String:
	var r := Site.delivery_rect(at, rot, ext).grow(-0.001)
	for g in delivery_view():
		if bool(g["carried"]) or str(g["key"]) == key:
			continue
		var p: Vector3 = g["pos"]
		if r.intersects(Site.delivery_rect(Vector2(p.x, p.z), int(g["rot"]), g["extent"])):
			return "Dort steht schon eine Lieferung."
	var err := layout.check_goods(at, rot, ext)
	if err != "":
		return err
	for ci in containers.size():
		var cp := Site.container_pos(ci)
		if r.intersects(Rect2(cp.x - 1.25, cp.z - 2.9, 2.5, 5.8)):
			return "Dort steht ein Container."
	return ""


## Nach dem Laden: Eine Lieferpalette, die weder Stapler noch Hubwagen trägt, steht wieder an ihrem letzten Platz.
func _release_orphan_goods() -> void:
	var live := {}
	for s in layout.shelves:
		if str(s.get("goods", "")) != "":
			live[str(s["goods"])] = true
	if player.driving_jack() and player.jack_goods() != "":
		live[player.jack_goods()] = true
	for k in delivery_spots:
		if bool(delivery_spots[k].get("carried", false)) and not live.has(k):
			delivery_spots[k]["carried"] = false
	_deliveries_changed()


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
	if int(it.get("pallet", 0)) > 0:
		what += " %d" % (int(it["pallet"]) + 1)
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
	item.erase("pallet")       # die Palettennummer gilt nur im Hof
	player.set_carry(item)
	# Vorher entfernen: Die Lieferung löscht gerade das Ziel, auf das der Sichtstrahl zeigt
	player._focus = null
	_deliveries_changed()
	office_pc.overlay.stock_changed()
	return ""


## Hinweis beim Anvisieren eines Fachs.
func rack_prompt(slot: int) -> String:
	var where := Site.slot_name(slot)
	if player.carrying_bin() or player.carrying_bucket() or player.carrying_crate() or player.carrying_semi() or player.carrying_part() or player.carrying_drawing():
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
	if player.carrying_bin() or player.carrying_bucket() or player.carrying_crate() or player.carrying_semi() or player.carrying_part() or player.carrying_drawing():
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
	if player.carrying_bin() or player.carrying_bucket() or player.carrying_crate() or player.carrying_semi() or player.carrying_part() or player.carrying_drawing():
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
	if player.carrying_pendant():
		return ""
	if machine is BandSaw:
		return saw_load(machine)
	if player.carrying_semi():
		return _clamp_semi(machine)
	if player.carrying_part():
		return _clamp_part(machine)
	if player.carrying_drawing():
		return ""
	var item: Dictionary = player.carry
	var round_bar := str(item["kind"]) == Materials.KIND_ROUND
	var err := _door_block(machine)
	if err != "":
		pass
	elif machine is Lathe and machine.grinder_type != "" or machine is Mill and machine.grinder_type != "":
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
	if player.carrying_bucket():
		return          # der Eimer wird nicht eingespannt, Linksklick schöpft Späne (bucket_scoop)
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
	var door := _door_block(machine)
	if door != "":
		return door
	if player.carry.is_empty():
		return "Erst die Spindel stoppen, dann umspannen." if machine.spindle_speed > 5.0 else ""
	if player.carrying_semi():
		return ""
	if player.carrying_part():
		var fit := _part_fit(machine, player.carry)
		if fit == "" and machine.has_part:
			fit = "Es ist schon ein Teil eingespannt: erst mit Linksklick aufs Teil ausspannen."
		return fit
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
	if player.carrying_semi() or player.carrying_part():
		err = "Bearbeitete Teile werden nicht gesägt."
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
	if player.carrying_bin() or player.carrying_bucket() or player.carrying_semi() or player.carrying_drawing():
		return "%s    |    Hände voll" % what
	if not player.carry.is_empty():
		return "[Linksklick] In die Kiste legen    |    %s" % what
	if not player.held.is_empty():
		return "%s    |    Hände voll" % what
	var lift := "    [%s] Kiste aufnehmen" % Settings.binding_text("interact") if Crate.CARRY.has(str(c["size"])) else ""
	if c["items"].is_empty():
		return "%s    |    leer%s" % [what, lift]
	var top: Dictionary = c["items"][-1]
	return "[Linksklick] %s nehmen%s    |    %s" % [_item_text(top), lift, what]


func crate_click(i: int) -> void:
	if not player.carry.is_empty():
		var err := crate_put(i)
		if err != "":
			hud.show_message(err, Color(1, 0.75, 0.2))
	elif player.held.is_empty():
		crate_take(i)


## E auf eine Kiste: Die kleine Kiste samt Inhalt in die Hände nehmen. Fehlertext, leer = aufgenommen.
func crate_lift(i: int) -> String:
	var c: Dictionary = layout.crates[i]
	var err := ""
	if not Crate.CARRY.has(str(c["size"])):
		err = "Diese Kiste ist zu groß und zu schwer zum Tragen. Nur die kleine Kiste lässt sich aufnehmen."
	elif not player.hands_free():
		err = "Erst die Hände frei machen."
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.2))
		return err
	layout.crates.remove_at(i)
	player.set_carry({"kind": "crate", "size": str(c["size"]), "items": c["items"], "title": str(Crate.SIZES[c["size"]]["title"])})
	_rebuild_stands()
	return ""


## Stellplatz für die getragene Kiste zum Blickpunkt at (Weltpunkt): Auf einer Werkbank die nächste freie
## Stelle auf der Platte, sonst am Boden neben einer Werkbank wie beim Aufstellen.
## {"pos": Vector2, "rot": int, "top": auf der Platte?, "err": Fehlertext, leer = geht dort}
## cached: Ergebnis vom letzten Aufruf mit gleichem Ziel wiederverwenden (Vorschau und Hinweis, pro Bild).
func crate_spot(at: Vector3, cached := false) -> Dictionary:
	if not player.carrying_crate():
		return {"pos": Vector2(at.x, at.z), "rot": 0, "top": false, "err": "Keine Kiste in den Händen."}
	var size_id := str(player.carry["size"])
	var spot := Vector2(at.x, at.z)
	var yaw_rot := posmod(int(round(player.yaw / (PI / 2.0))), 4)
	# Die Bank-Suche ist teuer: Pro Bild nur neu rechnen, wenn sich Ziel oder Aufstellung geändert haben
	var key := [size_id, spot.snappedf(0.02), at.y > ToolBench.TOP_Y - 0.1, yaw_rot, layout.crates.size(), layout.benches.size()]
	if cached and key == _crate_spot_key:
		return _crate_spot_cache
	var best := {}
	# Werkbank, auf deren Platte (oder knapp daneben) der Blick zeigt: nächste freie Stelle
	for id in layout.benches:
		if not layout.bench_area(id).grow(0.15).has_point(spot):
			continue
		var best_d := INF
		for s in _bench_crate_spots(size_id, id):
			var d := (s["pos"] as Vector2).distance_squared_to(spot)
			if d < best_d:
				best_d = d
				best = s
		if not best.is_empty():
			break
	var err := ""
	if best.is_empty():
		err = layout.check_crate(size_id, spot, yaw_rot)
		if err == "":
			best = {"pos": spot, "rot": yaw_rot}
		elif at.y > ToolBench.TOP_Y - 0.1:
			err = "Auf dieser Werkbank ist kein Platz mehr für die Kiste."
	var res := {"pos": spot, "rot": yaw_rot, "top": false, "err": err}
	if not best.is_empty():
		var bench := layout.crate_bench_at(size_id, best["pos"], best["rot"])
		res = {"pos": best["pos"], "rot": best["rot"], "bench": bench, "err": "",
			"top": layout.crate_on_top(size_id, best["pos"], best["rot"], bench)}
	elif at.y > ToolBench.TOP_Y - 0.1:
		res["top"] = true
	_crate_spot_key = key
	_crate_spot_cache = res
	return res


## Alle freien Stellen (5-cm-Raster, zwei Drehungen) für eine Kiste auf der Platte der Werkbank bench_id.
## Hängt nicht vom Blick ab, nur von der Aufstellung: einmal rechnen, bis sich in der Werkstatt etwas ändert.
func _bench_crate_spots(size_id: String, bench_id: String) -> Array:
	var stamp := [layout.crates.size(), layout.benches.size(), layout.machines.size(), layout.shelves.size(), layout.bins.size()]
	var key := "%s|%s" % [size_id, bench_id]
	var hit: Dictionary = _bench_spot_cache.get(key, {})
	if not hit.is_empty() and hit["stamp"] == stamp:
		return hit["spots"]
	var spots: Array = []
	var rot := int(layout.benches[bench_id]["rot"])
	var area := layout.bench_area(bench_id)
	var x := area.position.x
	while x <= area.end.x:
		var z := area.position.y
		while z <= area.end.y:
			var p := Vector2(x, z)
			for r in [rot, posmod(rot + 1, 4)]:
				if layout.crate_on_top(size_id, p, r, bench_id) and layout.check_crate(size_id, p, r) == "":
					spots.append({"pos": p, "rot": r})
			z += 0.05
		x += 0.05
	_bench_spot_cache[key] = {"stamp": stamp, "spots": spots}
	return spots


## Getragene Kiste abstellen, wohin der Blick zeigt (at, Weltpunkt), siehe crate_spot.
## Fehlertext, leer = abgestellt.
func crate_set_down(at: Vector3) -> String:
	if not player.carrying_crate():
		return ""
	var s := crate_spot(at)
	var err := str(s["err"])
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.2))
		return err
	layout.crates.append({"size": str(player.carry["size"]), "pos": s["pos"], "rot": s["rot"],
		"bench": s["bench"], "items": player.carry["items"]})
	player.clear_carry()
	_rebuild_stands()
	return ""


## Material aus den Händen in die Kiste. Fehlertext, leer = hineingelegt.
func crate_put(i: int) -> String:
	if player.carry.is_empty():
		return "Keine Hand voll Material."
	if player.carrying_bin():
		return "Der Spänebehälter passt nicht in die Kiste."
	if player.carrying_bucket():
		return "Der Eimer passt nicht in die Kiste."
	if player.carrying_crate():
		return "Erst die Kiste aus den Händen abstellen."
	if player.carrying_drawing():
		return "Die Zeichnung lieber anpinnen."
	var c: Dictionary = layout.crates[i]
	if not Crate.accepts(player.carry):
		return "Stangen gehören ins Regal. In die Kiste kommen Fertigschnitte, abgesägte und ausgespannte Teile."
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


## Spänebehälter aufstellen oder umstellen. Die Spänekiste einer Maschine (E50) lässt sich wie jeder
## Behälter umstellen, nahe ihrem Stellplatz rastet sie wieder unter dem Förderer ein.
func place_bin(moving: int, size_id: String, pos: Vector2, rot: int) -> String:
	if moving >= 0:
		var mb: Dictionary = layout.bins[moving]
		if mb["out"] or bool(mb.get("hooked", false)) or bool(mb.get("fork", false)):
			return "Erst den Behälter abstellen."
		size_id = str(mb["size"])
		if not machine_bin_snap(moving, pos).is_empty():
			mb["away"] = false
			_sync_machine_bins()
			_rebuild_stands()
			return ""
	var err := layout.check_bin(pos, rot, moving, size_id)
	if err != "":
		return err
	if moving >= 0:
		layout.bins[moving]["pos"] = pos
		layout.bins[moving]["rot"] = rot
		if layout.bins[moving].has("machine"):
			layout.bins[moving]["away"] = true
			_sync_machine_bins()
	else:
		if int(inventory.get(size_id, 0)) <= 0:
			return "Dieser Behälter wurde nicht gekauft."
		inventory[size_id] = int(inventory[size_id]) - 1
		layout.bins.append({"size": size_id, "pos": pos, "rot": rot, "chips": ChipTray.new(float(ChipBin.SIZES[size_id]["kg"])), "out": false})
	_rebuild_stands()
	return ""


## Spänekiste einer Maschine nahe ihrem Stellplatz unter dem Förderer: {"pos", "rot"} dieses Platzes,
## sonst {}. Für alle anderen Behälter immer {}.
func machine_bin_snap(i: int, at: Vector2) -> Dictionary:
	if i < 0 or i >= layout.bins.size():
		return {}
	var mid := str(layout.bins[i].get("machine", ""))
	var m: Node3D = _machine_node(mid) if mid != "" and layout.machines.has(mid) else null
	if not (m is Lathe and m.has_chip_bin_spot):
		return {}
	var t: Transform3D = m.transform * m.chip_bin_spot
	var spot := Vector2(t.origin.x, t.origin.z)
	if at.distance_to(spot) >= 0.8:
		return {}
	return {"pos": spot, "rot": posmod(roundi(t.basis.get_euler().y / (PI / 2.0)), 4)}


## Q im Baumodus: Das umgestellte Teil kommt zurück in die Liste Nicht aufgestellt.
## Fehlertext, leer = eingelagert.
func store_equipment(kind: String, item: String, index: int) -> String:
	match kind:
		"bench":
			return take_down_bench(item)
		"crate":
			if index < 0 or index >= layout.crates.size():
				return "Hier steht keine Kiste."
			var c: Dictionary = layout.crates[index]
			if not (c["items"] as Array).is_empty():
				return "Erst die Kiste leeren."
			layout.crates.remove_at(index)
			inventory[str(c["size"])] = int(inventory.get(str(c["size"]), 0)) + 1
		"bin":
			if index < 0 or index >= layout.bins.size():
				return "Hier steht kein Behälter."
			var b: Dictionary = layout.bins[index]
			if b.has("machine"):
				return "Die Spänekiste gehört zur %s und bleibt in der Werkstatt." % Layout.SPECS[str(b["machine"])]["title"]
			if b["out"] or bool(b.get("hooked", false)) or bool(b.get("fork", false)):
				return "Erst den Behälter abstellen."
			if not (b["chips"] as ChipTray).is_empty():
				return "Erst den Behälter leeren."
			layout.bins.remove_at(index)
			# Ein gerade geschobener Behälter rückt in der Liste nach
			if player.carrying_bin() and int(player.carry["bin"]) > index:
				player.carry["bin"] = int(player.carry["bin"]) - 1
			inventory[str(b["size"])] = int(inventory.get(str(b["size"]), 0)) + 1
		"shelf":
			if index < 0 or index >= layout.shelves.size():
				return "Hier steht nichts."
			var s: Dictionary = layout.shelves[index]
			if str(s.get("goods", "")) != "" or int(s.get("load", 0)) > 0:
				return "Erst die Last abladen."
			var chips = s.get("chips")
			if chips is ChipTray and not (chips as ChipTray).is_empty():
				return "Erst den Eimer leeren."
			layout.shelves.remove_at(index)
			inventory[str(s["size"])] = int(inventory.get(str(s["size"]), 0)) + int(s.get("stack", 1))
		"machine":
			return "Maschinen bleiben aufgestellt: mit Linksklick woanders hinstellen."
		_:
			return "Lagerregale bleiben stehen: mit Linksklick woanders hinstellen."
	player._focus = null
	_rebuild_stands()
	_refresh_hud()
	return ""


## Debug: Was der Strahl trifft, als Beschreibung fürs Debug-Menü. Leer = nichts Entfernbares.
func debug_target(hit: Object) -> Dictionary:
	if hit is DroppedItem and is_instance_valid(hit):
		return {"kind": "dropped", "node": hit, "title": "Liegender Gegenstand"}
	# Beladene Lieferpalette aus dem Shop im Hof
	var meta = hit.get_meta("interact", null) if hit != null and hit.has_meta("interact") else null
	if meta is Site.Delivery and int(meta.index) >= 0 and int(meta.index) < deliveries.size():
		var it: Dictionary = deliveries[int(meta.index)]
		var key := Site.delivery_key(it)
		var n := _goods_items(key).size()
		return {"kind": "delivery", "item": key, "index": -1,
			"title": "Lieferpalette %s  %s (%d Stück)" % [Materials.label(str(it["material"])), RawMaterialTab.describe(it), n]}
	var t := build_target(hit)
	if t.is_empty() or t["kind"] == "rack":
		return {}
	return t


## Debug: Angeschautes endgültig entfernen, ohne Rückgabe ins Lager. Inhalt (Teile in Kisten, Späne) geht
## mit verloren. Fehlertext, leer = entfernt.
func debug_remove(t: Dictionary) -> String:
	if t.is_empty():
		return "Nichts Entfernbares im Blick."
	var index := int(t.get("index", -1))
	match str(t["kind"]):
		"dropped":
			var n = t["node"]
			if not is_instance_valid(n):
				return "Der Gegenstand ist schon weg."
			(n as Node).remove_from_group(DroppedItem.GROUP)
			(n as Node).queue_free()
			player._focus = null
			return ""
		"delivery":
			var key := str(t["item"])
			if _goods_items(key).is_empty():
				return "Diese Lieferung gibt es nicht mehr."
			if bool(delivery_spots.get(key, {}).get("carried", false)):
				return "Die Palette hängt gerade an Stapler oder Hubwagen: erst absetzen."
			_drop_goods(key)
			player._focus = null
			_deliveries_changed()
			_refresh_hud()
			office_pc.overlay.stock_changed()
			return ""
		"machine":
			return "Maschinen lassen sich hier nicht entfernen."
		"bench":
			var id := str(t["item"])
			if not layout.benches.has(id):
				return "Hier steht keine Werkbank."
			if layout.crates_of(id) > 0:
				return "Erst die Kisten neben dieser Werkbank entfernen."
			_remove_bench(id)
			player._focus = null
			_refresh_hud()
			return ""
		"crate":
			if index < 0 or index >= layout.crates.size():
				return "Hier steht keine Kiste."
			if player.carrying_crate():
				return "Erst die getragene Kiste abstellen."
			layout.crates.remove_at(index)
		"bin":
			if index < 0 or index >= layout.bins.size():
				return "Hier steht kein Behälter."
			var b: Dictionary = layout.bins[index]
			if b.has("machine"):
				return "Die Spänekiste gehört zur %s." % Layout.SPECS[str(b["machine"])]["title"]
			if b["out"] or bool(b.get("hooked", false)) or bool(b.get("fork", false)) or player.carrying_bin():
				return "Erst den Behälter abstellen."
			layout.bins.remove_at(index)
		"shelf":
			if index < 0 or index >= layout.shelves.size():
				return "Hier steht nichts."
			var s: Dictionary = layout.shelves[index]
			if player.carrying_pallet():
				return "Erst die getragene Palette abstellen."
			# Steht eine Lieferung darauf (abgestellter Hubwagen), geht sie mit
			var goods := str(s.get("goods", ""))
			layout.shelves.remove_at(index)
			if goods != "":
				_drop_goods(goods)
				_deliveries_changed()
		_:
			return "Das lässt sich nicht entfernen."
	player._focus = null
	_rebuild_stands()
	_refresh_hud()
	return ""


## Debug: Alle Stücke der Lieferpalette key samt gemerktem Platz löschen.
func _drop_goods(key: String) -> void:
	for i in range(deliveries.size() - 1, -1, -1):
		if Site.delivery_key(deliveries[i]) == key:
			deliveries.remove_at(i)
	delivery_spots.erase(key)


## Holzregal aufstellen oder umstellen.
# ------------------------------------------------------------ Leere Paletten von Hand stapeln

## Hinweis auf einem Palettenstapel.
func pallet_prompt(i: int) -> String:
	var n := int(layout.shelves[i].get("stack", 1))
	var what := "Europalette" if n == 1 else "%d Europaletten gestapelt" % n
	if player.carrying_pallet():
		if n >= Shelf.MAX_STACK:
			return "Stapel ist voll (%d)    |    Palette woanders abstellen" % Shelf.MAX_STACK
		return "[%s] Palette auflegen    |    %s" % [Settings.binding_text("interact"), what]
	if not player.hands_free():
		return "%s    |    Hände voll" % what
	return "[%s] Palette aufnehmen    |    %s" % [Settings.binding_text("interact"), what]


## E auf einen Palettenstapel: oberste aufnehmen oder die getragene drauflegen.
func pallet_click(i: int) -> void:
	var s: Dictionary = layout.shelves[i]
	var n := int(s.get("stack", 1))
	if player.carrying_pallet():
		if n >= Shelf.MAX_STACK:
			hud.show_message("Der Stapel ist voll: höchstens %d Paletten." % Shelf.MAX_STACK, Color(1, 0.75, 0.2))
			return
		s["stack"] = n + 1
		player.clear_carry()
		_rebuild_stands()
		return
	if not player.hands_free():
		return
	if n <= 1:
		layout.shelves.remove_at(i)
	else:
		s["stack"] = n - 1
	player.set_carry({"kind": "pallet", "title": "Europalette"})
	_rebuild_stands()


# ------------------------------------------------------------ Gabelstapler

func forklift_prompt(i: int) -> String:
	var n := int(layout.shelves[i].get("load", 0))
	var what := "Gabelstapler" if n == 0 else "Gabelstapler mit %d Palette%s" % [n, "" if n == 1 else "n"]
	if not player.hands_free():
		return "%s    |    Hände voll" % what
	return "[%s] Einsteigen    |    %s    |    im Baumenü umstellen" % [Settings.binding_text("interact"), what]


## E auf den abgestellten Gabelstapler: einsteigen. Er wird zum fahrbaren Körper, die Figur sitzt darauf.
func forklift_click(i: int) -> void:
	if not player.hands_free() or forklift != null:
		return
	var s: Dictionary = layout.shelves[i]
	if str(s["size"]) != "forklift":
		return
	layout.shelves.remove_at(i)
	var f := Forklift.new()
	f.world = self
	f.lift = float(s.get("lift", 0.0))
	f.load_n = int(s.get("load", 0))
	f.load_rot = int(s.get("load_rot", 0))
	f.shift = float(s.get("shift", 0.0))
	f.tilt = float(s.get("tilt", 0.0))
	add_child(f)
	f.place(s["pos"], float(s.get("angle", int(s["rot"]) * PI / 2.0)))
	f.add_collision_exception_with(player)
	forklift = f
	f.driver = player
	player.board_forklift(f)
	_rebuild_stands()
	hud.show_message("Gabelstapler: [WASD] fahren   [%s / %s] Gabel heben / senken   [%s / %s] Seitenschieber   [%s / %s] neigen   [%s] aussteigen" % [
		Settings.binding_text("fork_up"), Settings.binding_text("fork_down"), Settings.binding_text("fork_left"), Settings.binding_text("fork_right"),
		Settings.binding_text("fork_tilt_fwd"), Settings.binding_text("fork_tilt_back"), Settings.binding_text("interact")], Color(0.7, 0.95, 1.0))


func _forklift_entry(f: Forklift) -> Dictionary:
	return {"size": "forklift", "pos": f.origin2(), "rot": posmod(roundi(f.phi / (PI / 2.0)), 4), "angle": f.phi,
		"lift": f.lift, "load": f.load_n, "load_rot": f.load_rot, "shift": f.shift, "tilt": f.tilt}


func _forklift_entry_state(f: Forklift) -> Dictionary:
	var e := _forklift_entry(f)
	e["pos"] = [e["pos"].x, e["pos"].y]
	e["stack"] = 1
	e["cross"] = false
	return e


## E auf dem Gabelstapler: aussteigen, links neben dem Fahrersitz (sonst rechts). Fehlertext, leer = ausgestiegen.
func forklift_leave() -> String:
	var f := forklift
	if f == null:
		return ""
	if f.load_bin >= 0:
		hud.show_message("Erst den Spänebehälter absetzen: Gabel ganz absenken.", Color(1, 0.75, 0.2))
		return "Behälter auf der Gabel."
	if f.load_goods != "":
		hud.show_message("Erst die Lieferpalette absetzen: Gabel ganz absenken.", Color(1, 0.75, 0.2))
		return "Lieferpalette auf der Gabel."
	var spot := Vector3.INF
	for side in [-1.0, 1.0]:
		for back in [0.0, -0.6, 0.6]:
			var q: Vector3 = f.to_global(Vector3(Forklift.SEAT.x + back, 0.0, side * (Forklift.WIDTH * 0.5 + 0.45)))
			if spot == Vector3.INF and _stand_free(Vector3(q.x, 0.05, q.z), f):
				spot = q
	if spot == Vector3.INF:
		hud.show_message("Hier ist kein Platz zum Aussteigen.", Color(1, 0.75, 0.2))
		return "Kein Platz zum Aussteigen."
	layout.shelves.append(_forklift_entry(f))
	forklift = null
	player.leave_forklift(Vector3(spot.x, 0.05, spot.z))
	f.queue_free()
	_rebuild_stands()
	return ""


## Palettenstapel unter der Gabelmitte, in den die Gabel gerade genug hineinsteht: {"i", "rot"} oder {}.
func _forklift_stack(f: Forklift) -> Dictionary:
	var at := f.fork_spot()
	for i in layout.shelves.size():
		var s: Dictionary = layout.shelves[i]
		if str(s["size"]) != "pallet":
			continue
		var r := Layout.shelf_rect("pallet", s["pos"], int(s["rot"]))
		if not r.has_point(at):
			continue
		var al: Array = f.align_to(int(s["rot"]))
		if float(al[0]) > Forklift.PICK_TOL_DEG:
			continue
		return {"i": i, "rot": int(al[1])}
	return {}


## Lieferpalette am Boden unter der Gabelmitte, in die die Gabel gerade genug hineinsteht: {"g": Eintrag aus delivery_view, "rot"} oder {}.
func _forklift_goods(f: Forklift) -> Dictionary:
	var at := f.fork_spot()
	var foot := Shelf.foot("pallet")
	for g in delivery_view():
		var p: Vector3 = g["pos"]
		if bool(g["carried"]) or p.y > Site.PALLET_TOP + 0.01:
			continue
		if not Layout.rect_at(Rect2(-foot * 0.5, foot), Vector2(p.x, p.z), int(g["rot"])).has_point(at):
			continue
		var al: Array = f.align_to(int(g["rot"]))
		if float(al[0]) > Forklift.PICK_TOL_DEG:
			continue
		return {"g": g, "rot": int(al[1])}
	return {}


## Leere Gabel hebt an und steckt auf Höhe der Unterkante der k-ten Palette (0 = unterste): Diese und alle
## darüber kommen auf die Gabel, die unteren k bleiben stehen. Ganz unten ohne Stapel nimmt sie einen
## Spänebehälter. {"n", "rot"}, {"bin", "rot"} oder {}.
func forklift_pick(f: Forklift, k := 0) -> Dictionary:
	var st := _forklift_stack(f)
	if not st.is_empty():
		var s: Dictionary = layout.shelves[int(st["i"])]
		var n := int(s.get("stack", 1))
		if k >= n:
			return {}
		if k == 0:
			layout.shelves.remove_at(int(st["i"]))
		else:
			s["stack"] = k
		_rebuild_stands()
		return {"n": n - k, "rot": int(st["rot"])}
	if k != 0:
		return {}
	var gd := _forklift_goods(f)
	if not gd.is_empty():
		return {"n": 1, "rot": int(gd["rot"]), "goods": _carry_goods(gd["g"])}
	var at := f.fork_spot()
	for i in layout.bins.size():
		var b: Dictionary = layout.bins[i]
		if b["out"] or bool(b.get("hooked", false)) or bool(b.get("fork", false)) or _bin_under_conveyor(b):
			continue
		if not Layout.bin_rect(b["pos"], int(b["rot"]), str(b["size"])).has_point(at):
			continue
		var al: Array = f.align_to(int(b["rot"]))
		if float(al[0]) > Forklift.PICK_TOL_DEG:
			continue
		b["fork"] = true
		bin_nodes[i].set_carried(true)
		_sync_machine_bins()
		return {"bin": i, "rot": int(al[1])}
	return {}


## Spänebehälter auf der Gabel mitführen: Lage der Last, Drehung zur Gabel, Kippwinkel nach vorn.
func forklift_carry_bin(i: int, holder: Transform3D, rot_q: int, dump: float) -> void:
	if i < 0 or i >= bin_nodes.size() or not is_instance_valid(bin_nodes[i]):
		return
	var s := ChipBin.size_of(str(layout.bins[i]["size"]))
	var ext := s.x if rot_q % 2 == 0 else s.z
	# Kippen um die Vorderkante: Der Behälter schwenkt über den Rand nach vorn
	var edge := Vector3(ext * 0.5, 0.0, 0.0)
	var xf := holder * Transform3D(Basis.IDENTITY, edge) * Transform3D(Basis(Vector3(0, 0, 1), -dump), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, -edge) * Transform3D(Basis(Vector3.UP, rot_q * PI / 2.0), Vector3.ZERO)
	bin_nodes[i].global_transform = xf


## Hubgerüst ganz nach vorn geneigt: Hängt der Behälter über einem Container und hoch genug, wird er
## hineingekippt. true = gekippt (die Kippbewegung läuft dann).
func forklift_dump(f: Forklift) -> bool:
	var i := f.load_bin
	var chips: ChipTray = layout.bins[i]["chips"]
	var at := f.fork_spot()
	for ci in containers.size():
		var cp := Site.container_pos(ci)
		# Öffnung 1,9 x 3,6 m (lange Seite nach Norden), der Behälter darf ein Stück überstehen
		if absf(at.x - cp.x) > 0.95 + 0.6 or absf(at.y - cp.z) > 1.8 + 0.6:
			continue
		if f.lift < FORKLIFT_DUMP_H:
			hud.show_message("Zu tief: Den Behälter über den Rand heben (mind. %.1f m), dann nach vorn kippen." % FORKLIFT_DUMP_H, Color(1, 0.75, 0.2))
			return false
		var c: ChipTray = containers[ci]
		var moved := c.take_from(chips)
		if moved <= 0.0:
			var why := "Der Behälter ist leer."
			if c.is_full():
				why = "Der Container ist voll: am PC im Programm Entsorgung abholen lassen."
			elif not chips.is_empty():
				why = "Das sind %sspäne, sie gehören nicht in diesen Container." % ChipTray.SORT_TITLES[chips.sort()]
			hud.show_message(why, Color(1, 0.75, 0.2))
			return false
		bin_nodes[i].show_state(chips.fraction(), false)
		site.show_containers(containers)
		hud.show_message("%d kg in den Container gekippt, jetzt %d von %d kg." % [int(round(moved)), int(c.kg), int(c.capacity)], Color(0.7, 0.95, 1.0))
		if is_instance_valid(office_pc) and office_pc.overlay:
			office_pc.overlay.waste_tab.refresh()
		return true
	return false


## Worauf die Last abgesenkt würde: {"h": Höhe, "i": Stapel} (Stapel unter der Gabel) oder {"h": 0}.
func forklift_base(f: Forklift) -> Dictionary:
	var st := _forklift_stack(f)
	if st.is_empty():
		return {"h": 0.0}
	var s: Dictionary = layout.shelves[int(st["i"])]
	return {"h": int(s.get("stack", 1)) * float(Shelf.SIZES["pallet"]["height"]), "i": int(st["i"])}


## Last ganz abgesenkt: auf den Stapel darunter oder auf den Boden. Fehlertext, leer = abgesetzt.
func forklift_drop(f: Forklift) -> String:
	if f.load_bin >= 0:
		return _forklift_drop_bin(f)
	var base := forklift_base(f)
	if f.load_goods != "":
		if base.has("i"):
			return "Lieferpaletten lassen sich nicht auf andere Paletten stapeln."
		var gl := _goods_items(f.load_goods)
		if gl.is_empty():
			return "Diese Lieferung gibt es nicht mehr."
		return put_goods(f.load_goods, f.fork_spot(), posmod(roundi(f.phi / (PI / 2.0)) + f.load_rot, 4))
	if base.has("i"):
		var s: Dictionary = layout.shelves[int(base["i"])]
		var n := int(s.get("stack", 1))
		if n + f.load_n > Shelf.MAX_STACK:
			return "Zu hoch: höchstens %d Paletten auf einem Stapel." % Shelf.MAX_STACK
		s["stack"] = n + f.load_n
		_rebuild_stands()
		return ""
	var rot: int = posmod(roundi(f.phi / (PI / 2.0)) + f.load_rot, 4)
	var at := f.fork_spot()
	var err := layout.check_shelf("pallet", at, rot)
	if err != "":
		return "Hier lassen sich die Paletten nicht absetzen: %s" % err
	layout.shelves.append({"size": "pallet", "pos": at, "rot": rot, "stack": f.load_n})
	_rebuild_stands()
	return ""


## Spänebehälter von der Gabel auf den Boden stellen. Die Spänekiste einer Maschine rastet unter ihrem
## Förderer ein, wenn sie nahe genug steht.
func _forklift_drop_bin(f: Forklift) -> String:
	var i := f.load_bin
	var b: Dictionary = layout.bins[i]
	var at := f.fork_spot()
	var rot: int = posmod(roundi(f.phi / (PI / 2.0)) + f.load_rot, 4)
	var mid := str(b.get("machine", ""))
	var m: Node3D = _machine_node(mid) if mid != "" and layout.machines.has(mid) else null
	if m is Lathe and m.has_chip_bin_spot:
		var t: Transform3D = m.transform * m.chip_bin_spot
		if at.distance_to(Vector2(t.origin.x, t.origin.z)) < 0.8:
			b.erase("fork")
			bin_nodes[i].set_carried(false)
			b["away"] = false
			_sync_machine_bins()
			bin_nodes[i].global_transform = Transform3D(Basis(Vector3.UP, int(b["rot"]) * PI / 2.0), Vector3(b["pos"].x, 0, b["pos"].y))
			return ""
	var err := layout.check_bin(at, rot, i, str(b["size"]))
	if err != "":
		return "Hier lässt sich der Behälter nicht absetzen: %s" % err
	b.erase("fork")
	bin_nodes[i].set_carried(false)
	b["pos"] = at
	b["rot"] = rot
	if mid != "":
		b["away"] = true
	bin_nodes[i].global_transform = Transform3D(Basis(Vector3.UP, rot * PI / 2.0), Vector3(at.x, 0, at.y))
	_sync_machine_bins()
	request_reflections()
	return ""


# ------------------------------------------------------------ Hubwagen

## Abgesenkte Paletten rasten auf 90° ein, dafür darf der Wagen höchstens so viele Grad davon entfernt stehen
## (sonst klemmen die Zinken in den Klötzen). Der Hubwagen selbst bleibt in jedem Winkel stehen ("angle").
const PALLET_SNAP_DEG := 6.0
## Seitlicher Versatz der Palettenmitte zur Zinkenmitte: Die Zinken-Kollision (z 0,205 bis 0,325) hat in der
## Öffnung (0,095 bis 0,38) außen 0,055 m Luft. Etwas mehr erlaubt, damit jede Lage, in die man hineinfährt, auch hebt.
const LIFT_SIDE_TOL := 0.07


## Hinweis auf dem abgestellten Hubwagen.
func jack_prompt(i: int) -> String:
	var n := int(layout.shelves[i].get("load", 0))
	var what := "Hubwagen" if n == 0 else "Hubwagen mit %d Palette%s" % [n, "" if n == 1 else "n"]
	if not player.hands_free():
		return "%s    |    Hände voll" % what
	return "[%s] Deichsel greifen    |    %s    |    im Baumenü umstellen" % [Settings.binding_text("interact"), what]


## E auf den abgestellten Hubwagen: Deichsel greifen. Die Figur steht dann hinter dem Lenkrad (Handgriff-Seite),
## sonst seitlich davon; ist nirgends Platz, passiert nichts.
func jack_click(i: int) -> void:
	if not player.hands_free():
		return
	var s: Dictionary = layout.shelves[i]
	if str(s["size"]) != "pallet_jack":
		return
	var phi := float(s.get("angle", int(s["rot"]) * PI / 2.0))
	var f := Vector2(cos(phi), -sin(phi))
	var center: Vector2 = s["pos"]
	var node: Node = shelf_nodes[i] if i < shelf_nodes.size() else null
	var rear := -f
	var spot := Vector2.ZERO
	var found := false
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var dir := rear.rotated(turn as float)
		var q := center + f * JackCart.PIVOT_X + dir * JackCart.HOLD
		if _stand_free(Vector3(q.x, player.global_position.y, q.y), node):
			spot = q
			rear = dir
			found = true
			break
	if not found:
		hud.show_message("Hier ist kein Platz, um die Deichsel zu greifen.", Color(1, 0.75, 0.2))
		return
	var load_n := int(s.get("load", 0))
	var cross := bool(s.get("cross", false))
	layout.shelves.remove_at(i)
	# Die Figur blickt zum Wagen
	player.yaw = atan2(rear.x, rear.y)
	player.rotation.y = player.yaw
	player.global_position = Vector3(spot.x, player.global_position.y, spot.y)
	player.velocity = Vector3.ZERO
	player.set_carry({"kind": "jack", "title": "Hubwagen", "load": load_n, "cross": cross, "goods": str(s.get("goods", "")), "pos": [center.x, center.y], "rot": phi})
	_rebuild_stands()


## Ist an dieser Stelle Platz für die Figur (Kapsel)? Der Knoten ignore (der Hubwagen selbst) zählt nicht.
func _stand_free(at: Vector3, ignore: Node) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.95, 0))
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var c := hit["collider"] as Node
		if c and ignore and c.has_meta("interact") and c.get_meta("interact") == ignore:
			continue
		return false
	return true


## Leertaste beim Fahren: ohne Last die Palette über den Zinken anheben, mit Last absenken.
func jack_lift() -> void:
	if not player.driving_jack():
		return
	var cart: JackCart = player.jack_cart
	var spot: Vector2 = cart.load_spot()
	if cart.load_n > 0:
		# Absenken: Die Palette steht danach mit gerundeter Drehung, dafür muss der Wagen fast gerade stehen
		if player.jack_snap_error(PI / 2.0 if cart.cross else 0.0) > deg_to_rad(PALLET_SNAP_DEG):
			hud.show_message("Palette gerader ausrichten.", Color(1, 0.75, 0.2))
			return
		var rot: int = player.jack_load_rot()
		if cart.goods != "":
			var err_g := put_goods(cart.goods, spot, rot)
			if err_g != "":
				hud.show_message(err_g, Color(1, 0.75, 0.2))
				return
			player.set_jack_load(0)
			return
		var err := layout.check_shelf("pallet", spot, rot)
		if err != "":
			hud.show_message(err, Color(1, 0.75, 0.2))
			return
		layout.shelves.append({"size": "pallet", "pos": spot, "rot": rot, "stack": cart.load_n})
		player.set_jack_load(0)
		_rebuild_stands()
		_settle_pallets(shelf_nodes.back())
		return
	var best := -1
	var best_d := INF
	var best_cross := false
	for i in layout.shelves.size():
		var s: Dictionary = layout.shelves[i]
		if str(s["size"]) != "pallet":
			continue
		var fit := _jack_fit(cart, s["pos"], int(s["rot"]))
		if not fit.is_empty() and float(fit["d"]) < best_d:
			best_d = float(fit["d"])
			best = i
			best_cross = bool(fit["cross"])
	# Lieferpaletten am Boden (nicht die oberen Lagen des Rasters)
	var best_goods := {}
	for g in delivery_view():
		var p: Vector3 = g["pos"]
		if bool(g["carried"]) or p.y > Site.PALLET_TOP + 0.01:
			continue
		var fit := _jack_fit(cart, Vector2(p.x, p.z), int(g["rot"]))
		if not fit.is_empty() and float(fit["d"]) < best_d:
			best_d = float(fit["d"])
			best_goods = g
			best_cross = bool(fit["cross"])
			best = -1
	if best < 0 and best_goods.is_empty():
		hud.show_message("Die Zinken stecken nicht unter einer Palette.", Color(1, 0.75, 0.2))
		return
	if not best_goods.is_empty():
		player.set_jack_load(1, best_cross, _carry_goods(best_goods))
		return
	var n := int(layout.shelves[best].get("stack", 1))
	layout.shelves.remove_at(best)
	player.set_jack_load(n, best_cross)
	_rebuild_stands()


## Steckt eine Palette mit Mitte p und Drehung rot auf den Zinken? {"d": Abstand zur Zinkenmitte, "cross": quer?} oder {}.
func _jack_fit(cart: JackCart, p: Vector2, rot: int) -> Dictionary:
	var f: Vector2 = cart.forward()
	var l: Vector2 = cart.lateral()
	var d: Vector2 = p - cart.load_spot()
	# Lastmitte muss nahe der Zinkenmitte liegen
	if absf(d.dot(f)) > 0.3 or absf(d.dot(l)) > LIFT_SIDE_TOL:
		return {}
	# Längs oder quer zu den Zinken (Euro-Paletten lassen sich von beiden Seiten unterfahren), um 180° gedreht ist egal
	var axis := Vector2.RIGHT.rotated(-rot * PI / 2.0)
	var is_cross := false
	if absf(f.cross(axis)) > 0.26:
		if absf(f.dot(axis)) > 0.26:
			return {}       # schräg: passt nicht auf die Zinken
		is_cross = true
	return {"d": d.length(), "cross": is_cross}


## Die abgesenkte Palette sinkt in 0,4 s die Hubhöhe herunter (nur Optik).
func _settle_pallets(node: Node3D) -> void:
	if node == null:
		return
	for c in node.get_children():
		if c is Node3D and not c is CollisionObject3D:
			var y: float = (c as Node3D).position.y
			(c as Node3D).position.y = y + Shelf.JACK_LIFT
			create_tween().tween_property(c, "position:y", y, JackCart.LIFT_TIME)


## Hubwagen sofort an der Stelle des Wagens abstellen (Figur teleportiert, schläft, ist zu weit weg).
func jack_abandon() -> void:
	if not player.driving_jack():
		return
	_leave_jack()
	hud.show_message("Hubwagen an seiner Stelle abgestellt.", Color(0.9, 0.95, 1.0))


## E oder Q beim Fahren: Hubwagen (samt Last) loslassen. Er bleibt genau so stehen, wie er gerade steht, in
## jedem Winkel und überall, auch unter einer Palette. Fehlertext, leer = abgestellt (immer leer).
func jack_park() -> String:
	if not player.driving_jack():
		return ""
	_leave_jack()
	return ""


## Wagen mit genauer Lage ins Layout eintragen. "rot" (gerundet) dient nur der Grobprüfung im Baumodus,
## gezeichnet und wieder gegriffen wird mit "angle".
func _leave_jack() -> void:
	var cart: JackCart = player.jack_cart
	layout.shelves.append({"size": "pallet_jack", "pos": player.jack_center(), "rot": player.jack_rot(),
			"angle": cart.phi if cart else player.jack_rot() * PI / 2.0,
			"load": player.jack_load(), "cross": player.jack_cross(), "goods": player.jack_goods()})
	player.clear_carry()
	_rebuild_stands()


## Getragene Palette am Punkt (x, z) abstellen, die lange Seite quer zur Blickrichtung. Fehlertext, leer = abgestellt.
func put_pallet(at: Vector2) -> String:
	if not player.carrying_pallet():
		return ""
	var rot: int = player.pallet_rot()
	var err := layout.check_shelf("pallet", at, rot)
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.2))
		return err
	layout.shelves.append({"size": "pallet", "pos": at, "rot": rot, "stack": 1})
	player.clear_carry()
	_rebuild_stands()
	return ""


func place_shelf(moving: int, size_id: String, pos: Vector2, rot: int) -> String:
	var cargo := 0
	var cross := false
	if moving >= 0:
		cargo = int(layout.shelves[moving].get("load", 0))
		cross = bool(layout.shelves[moving].get("cross", false))
	var err := layout.check_shelf(size_id, pos, rot, moving, cargo, cross)
	if err != "":
		return err
	if moving >= 0:
		layout.shelves[moving]["pos"] = pos
		layout.shelves[moving]["rot"] = rot
		layout.shelves[moving].erase("angle")      # im Baumodus umgestellt: wieder gerade
	else:
		if int(inventory.get(size_id, 0)) <= 0:
			return "Dieses Regal wurde nicht gekauft."
		inventory[size_id] = int(inventory[size_id]) - 1
		layout.shelves.append({"size": size_id, "pos": pos, "rot": rot})
		if size_id == "bucket":
			layout.shelves.back()["chips"] = ChipTray.new(Bucket.CAPACITY)
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
			return {"kind": "bin", "item": n.size_id, "index": n.index, "title": equipment_title(n.size_id), "rect": Layout.bin_rect(b["pos"], b["rot"], n.size_id)}
		if n is Shelf:
			var s: Dictionary = layout.shelves[n.index]
			return {"kind": "shelf", "item": n.size_id, "index": n.index, "title": equipment_title(n.size_id),
				"rect": Layout.shelf_rect(n.size_id, s["pos"], s["rot"], int(s.get("load", 0)), bool(s.get("cross", false)))}
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
		"shelf":
			return shelf_nodes[index] if index >= 0 else null
	return null


## Kisten und Spänebehälter neu aufstellen.
func _rebuild_stands() -> void:
	request_reflections()
	_crate_spot_key = []
	_bench_spot_cache.clear()
	player._focus = null
	# Nicht sofort free(): der Aufruf kommt oft aus click() genau eines dieser Knoten (Palettenstapel),
	# der dann gesperrt ist und als Geist mit veraltetem Index stehen bliebe. Aus dem Baum nehmen, später löschen.
	# Die Nummern der Behälter können sich ändern: Der Kran hängt seine Last aus, sie bleibt am Stellplatz
	if crane and crane.hooked >= 0:
		for b in layout.bins:
			b.erase("hooked")
		crane.drop_hook()
	if forklift and is_instance_valid(forklift) and forklift.load_bin >= 0:
		for b in layout.bins:
			b.erase("fork")
		forklift.load_bin = -1
	for n in crate_nodes + bin_nodes + shelf_nodes:
		if is_instance_valid(n):
			if n.get_parent():
				n.get_parent().remove_child(n)
			n.queue_free()
	crate_nodes.clear()
	bin_nodes.clear()
	shelf_nodes.clear()
	for i in layout.shelves.size():
		var s: Dictionary = layout.shelves[i]
		var sn := Shelf.new()
		sn.index = i
		sn.size_id = s["size"]
		sn.stack = int(s.get("stack", 1))
		sn.cargo = int(s.get("load", 0))
		sn.chips = s.get("chips") as ChipTray
		sn.cargo_cross = bool(s.get("cross", false))
		sn.cargo_goods = str(s.get("goods", ""))
		sn.lift = float(s.get("lift", 0.0))
		sn.load_rot = int(s.get("load_rot", 0))
		sn.fork_shift = float(s.get("shift", 0.0))
		sn.fork_tilt = float(s.get("tilt", 0.0))
		sn.world = self
		sn.position = Vector3(s["pos"].x, 0, s["pos"].y)
		sn.rotation.y = float(s.get("angle", int(s["rot"]) * PI / 2.0))
		add_child(sn)
		shelf_nodes.append(sn)
	for i in layout.crates.size():
		var c: Dictionary = layout.crates[i]
		var node := Crate.new()
		node.world = self
		node.index = i
		node.size_id = c["size"]
		node.items = c["items"]
		# Auf der Werkbank steht die Kiste auf der Platte
		node.position = Vector3(c["pos"].x, ToolBench.TOP_Y if layout.crate_is_on_top(c) else 0.0, c["pos"].y)
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
		# Spänekiste unter dem Förderer: Die Maschine zeigt ihren Füllstand an diesem Behälter
		var owner_m: Node3D = _machine_node(str(b.get("machine", ""))) if b.has("machine") else null
		if owner_m is Lathe:
			owner_m.chip_bin_node = node


# ------------------------------------------------------------ Späne

func bin_prompt(i: int) -> String:
	var b: Dictionary = layout.bins[i]
	if player.carrying_bucket():
		var verb := "Späne in den Eimer nehmen" if _bucket_takes_from(b["chips"]) else "Eimer leeren"
		return "[Linksklick] %s (Eimer %s)    |    %s: %s" % [verb, Bucket.describe(player.bucket_chips()),
				ChipBin.SIZES[b["size"]]["title"], Bucket.describe(b["chips"])]
	var title := str(ChipBin.SIZES[b["size"]]["title"])
	var what := "%s: %d von %d kg" % [title, int(b["chips"].kg), int(b["chips"].capacity)]
	if not b["chips"].is_empty():
		what += " %sspäne" % ChipTray.SORT_TITLES[b["chips"].sort()]
	if bool(b.get("hooked", false)):
		return "%s    |    Hängt am Hallenkran" % what
	if bool(b.get("fork", false)):
		return "%s    |    Auf dem Gabelstapler" % what
	if b["out"]:
		if player.carrying_bin() and int(player.carry["bin"]) == i:
			return "[Linksklick] Zurück an den Stellplatz    |    %s" % what
		return what
	if _bin_under_conveyor(b):
		return "%s    |    Unter dem Späneförderer der %s: zum Leeren mit dem Hallenkran herausheben" % [what, Layout.SPECS[str(b["machine"])]["title"]]
	if str(b.get("machine", "")) != "":
		what += "    |    Spänekiste der %s, mit dem Kran oder im Baumodus wieder unter den Förderer stellen" % Layout.SPECS[str(b["machine"])]["title"]
	if player.hands_free():
		return "[Linksklick] Auf den Rollen schieben    |    %s" % what
	return what


## Steht der Behälter als Spänekiste unter dem Förderer seiner Maschine?
func _bin_under_conveyor(b: Dictionary) -> bool:
	return str(b.get("machine", "")) != "" and not bool(b.get("away", false))


## Linksklick auf einen Spänebehälter: Er rollt, die Figur schiebt ihn zur Maschine und zum Container.
## Die Spänekiste unter dem Förderer ist eingebaut, sie kommt nur mit dem Hallenkran heraus.
func bin_click(i: int) -> void:
	if player.carrying_bucket():
		_bin_bucket_click(i)
		return
	var b: Dictionary = layout.bins[i]
	if bool(b.get("hooked", false)) or bool(b.get("fork", false)):
		return
	if b["out"]:
		if player.carrying_bin() and int(player.carry["bin"]) == i:
			_bin_back(i)
		return
	if _bin_under_conveyor(b):
		hud.show_message(MACHINE_BIN_FIXED, Color(1, 0.75, 0.2))
		return
	if not player.hands_free():
		return
	b["out"] = true
	player.set_carry({"kind": "chip_bin", "bin": i, "title": ChipBin.SIZES[b["size"]]["title"]})
	bin_nodes[i].show_state(b["chips"].fraction(), true)
	hud.show_message("Behälter zur Maschine schieben und die Spänewanne hineinleeren, voll im Hof in den Container kippen. [%s] stellt ihn ab." % Settings.binding_text("drop"), Color(0.7, 0.95, 1.0))


func _bin_back(i: int) -> void:
	var b: Dictionary = layout.bins[i]
	b["out"] = false
	if player.carrying_bin() and int(player.carry["bin"]) == i:
		player.clear_carry()
	bin_nodes[i].position = Vector3(b["pos"].x, 0, b["pos"].y)
	bin_nodes[i].show_state(b["chips"].fraction(), false)
	_sync_machine_bins()


## Q mit dem Behälter: vor der Figur abstellen, das ist dann sein neuer Stellplatz.
func bin_set_down() -> void:
	if not player.carrying_bin():
		return
	var i := int(player.carry["bin"])
	var b: Dictionary = layout.bins[i]
	var fwd := -player.global_basis.z
	var foot := ChipBin.foot(str(b["size"]))
	var at := Vector2(player.global_position.x, player.global_position.z) + Vector2(fwd.x, fwd.z).normalized() * (maxf(foot.x, foot.y) * 0.5 + 0.5)
	var err := layout.check_bin(at, int(b["rot"]), i, str(b["size"]))
	if err != "":
		hud.show_message("Hier lässt sich der Behälter nicht abstellen: %s" % err, Color(1, 0.75, 0.2))
		return
	b["pos"] = at
	if b.has("machine"):
		b["away"] = true
	_bin_back(i)


## Spänewanne der Maschine in den geschobenen Behälter leeren.
func pour_tray(machine: Node) -> String:
	if machine.get("tray") == null:
		return "Diese Maschine hat keine Spänewanne."
	var rpm = machine.get("spindle_speed")
	if rpm != null and float(rpm) > 5.0:
		var busy := "Erst die Spindel stoppen."
		hud.show_message(busy, Color(1, 0.75, 0.2))
		return busy
	var i := int(player.carry["bin"])
	var chips: ChipTray = layout.bins[i]["chips"]
	var moved := chips.take_from(machine.tray)
	if machine.has_method("refresh_tray"):
		machine.refresh_tray()
	if moved <= 0.0:
		var why := "Die Spänewanne ist leer."
		if chips.is_full():
			why = "Der Behälter ist voll: im Hof in den passenden Container kippen."
		elif not machine.tray.is_empty():
			why = "Im Behälter liegen %sspäne: erst in den Container leeren, nicht mischen." % ChipTray.SORT_TITLES[chips.sort()]
		hud.show_message(why, Color(1, 0.75, 0.2))
		return why
	bin_nodes[i].show_state(chips.fraction(), true)
	hud.show_message("%d kg Späne im Behälter, jetzt %d von %d kg." % [int(round(moved)), int(chips.kg), int(chips.capacity)], Color(0.7, 0.95, 1.0))
	return ""


# ------------------------------------------------------------ Hallenkran

## Werkbank unter dem Blick (Maschinen-id), wenn der Strahl oben auf ihre Platte trifft, sonst "".
func crane_bench_at(collider: Object, point: Vector3, normal: Vector3) -> String:
	if normal.y < 0.7 or absf(point.y - ToolBench.TOP_Y) > 0.1:
		return ""
	var n := collider as Node
	while n != null and n != self:
		if n is ToolBench:
			var id = bench_nodes.find_key(n)
			return str(id) if id != null else ""
		n = n.get_parent()
	return ""


## E mit der Fernbedienung auf eine Werkbankplatte: dort ablegen. true = abgelegt.
func crane_put_on_bench(collider: Object, point: Vector3, normal: Vector3) -> bool:
	var id := crane_bench_at(collider, point, normal)
	if id == "":
		return false
	crane.put_on_bench(id, bench_nodes[id], point, player.yaw)
	hud.show_message("Fernbedienung auf der Werkbank abgelegt.", Color(0.7, 0.95, 1.0))
	return true


## Behälter, den der Haken bei hook greifen kann: genau darüber und bis kurz über die Oberkante gesenkt.
func crane_find_bin(hook: Vector3) -> int:
	var best := -1
	var best_d := 0.9
	for i in layout.bins.size():
		var b: Dictionary = layout.bins[i]
		if b["out"] or bool(b.get("hooked", false)) or bool(b.get("fork", false)):
			continue
		var gap := hook.y - HallCrane.SLING - ChipBin.height(str(b["size"]))
		if gap < -0.15 or gap > 0.5:
			continue
		var d := Vector2(hook.x, hook.z).distance_to(b["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best


func crane_bin_height(i: int) -> float:
	return ChipBin.height(str(layout.bins[i]["size"])) if i >= 0 and i < layout.bins.size() else 0.0


## Anschlagpunkte an den vier Kranösen des Behälters i, von der Mitte seiner Unterkante aus und so gedreht,
## wie er steht.
func crane_bin_lugs(i: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if i < 0 or i >= layout.bins.size():
		return out
	var b: Dictionary = layout.bins[i]
	var turn := Basis(Vector3.UP, int(b["rot"]) * PI / 2.0)
	if i < bin_nodes.size() and is_instance_valid(bin_nodes[i]):
		turn = bin_nodes[i].global_transform.basis.orthonormalized()
	for p in ChipBin.lugs(str(b["size"])):
		out.append(turn * p)
	return out


func crane_hook(i: int) -> void:
	layout.bins[i]["hooked"] = true
	_sync_machine_bins()
	request_reflections()


## Der Behälter hängt am Haken: Knoten mitführen (bottom = Mitte der Unterkante).
func crane_carry(i: int, bottom: Vector3) -> void:
	if i < 0 or i >= bin_nodes.size() or not is_instance_valid(bin_nodes[i]):
		return
	bin_nodes[i].global_position = bottom


## Behälter am Boden aushängen. Fehlertext, leer = abgesetzt. Die Spänekiste einer Maschine rastet unter
## dem Förderer ein, wenn sie nahe genug an ihrem Platz steht.
func crane_set_down(i: int, at: Vector2) -> String:
	var b: Dictionary = layout.bins[i]
	var mid := str(b.get("machine", ""))
	var m: Node3D = _machine_node(mid) if mid != "" and layout.machines.has(mid) else null
	if m is Lathe and m.has_chip_bin_spot:
		var t: Transform3D = m.transform * m.chip_bin_spot
		if at.distance_to(Vector2(t.origin.x, t.origin.z)) < 0.8:
			b.erase("hooked")
			b["away"] = false
			_sync_machine_bins()
			bin_nodes[i].position = Vector3(b["pos"].x, 0, b["pos"].y)
			bin_nodes[i].rotation.y = int(b["rot"]) * PI / 2.0
			hud.show_message("Spänekiste steht wieder unter dem Förderer.", Color(0.7, 0.95, 1.0))
			return ""
	var err := layout.check_bin(at, int(b["rot"]), i, str(b["size"]))
	if err != "":
		return "Hier lässt sich der Behälter nicht absetzen: %s" % err
	b.erase("hooked")
	b["pos"] = at
	if mid != "":
		b["away"] = true
	bin_nodes[i].position = Vector3(at.x, 0, at.y)
	_sync_machine_bins()
	request_reflections()
	return ""


## Linksklick mit dem Eimer auf einen Spänebehälter: hineinkippen, mit dem leeren Eimer bis zu 10 kg herausnehmen.
func _bin_bucket_click(i: int) -> void:
	var bin_chips: ChipTray = layout.bins[i]["chips"]
	var done := false
	if _bucket_takes_from(bin_chips):
		var chips := player.bucket_chips()
		var moved := chips.take_from(bin_chips)
		done = moved > 0.0
		if done:
			player.refresh_bucket()
			player._focus = null
			hud.show_message("%.1f kg Späne aus dem Behälter in den Eimer, jetzt %s." % [moved, Bucket.describe(chips)], Color(0.7, 0.95, 1.0))
	else:
		done = _pour_bucket(bin_chips, "Der Behälter")
	if done and i < bin_nodes.size():
		bin_nodes[i].show_state(bin_chips.fraction(), false)


## Leerer Eimer an einem Behälter mit Spänen: herausnehmen statt auskippen.
func _bucket_takes_from(bin_chips: ChipTray) -> bool:
	return player.carrying_bucket() and player.bucket_chips().is_empty() and not bin_chips.is_empty()


## Eimerinhalt in einen Behälter oder Container kippen, so viel hineinpasst. Meldet das Ergebnis.
func _pour_bucket(into: ChipTray, what: String) -> bool:
	var chips := player.bucket_chips()
	var moved := into.take_from(chips)
	if moved <= 0.0:
		var why := "Der Eimer ist leer."
		if not chips.is_empty() and into.is_full():
			why = "%s ist voll." % what
		elif not chips.is_empty():
			why = "Das sind %sspäne, sie gehören nicht zu den %sspänen darin." % [ChipTray.SORT_TITLES[chips.sort()], ChipTray.SORT_TITLES.get(into.sort(), "")]
		hud.show_message(why, Color(1, 0.75, 0.2))
		return false
	player.refresh_bucket()
	player._focus = null
	hud.show_message("%.1f kg Späne ausgekippt, im Eimer sind noch %.1f kg." % [moved, chips.kg], Color(0.7, 0.95, 1.0))
	return true


# ------------------------------------------------------------ Eimer

## Hinweis auf einem abgestellten Eimer.
func bucket_prompt(i: int) -> String:
	var chips: ChipTray = layout.shelves[i]["chips"]
	if not player.hands_free():
		return "Eimer (%s)    |    Hände voll" % Bucket.describe(chips)
	return "[%s] Eimer aufnehmen    |    Eimer: %s    |    im Baumenü umstellen" % [Settings.binding_text("interact"), Bucket.describe(chips)]


## E auf einen abgestellten Eimer: in die Hand nehmen, samt Inhalt.
func bucket_click(i: int) -> void:
	if not player.hands_free():
		return
	var s: Dictionary = layout.shelves[i]
	if str(s["size"]) != "bucket":
		return
	var chips: ChipTray = s["chips"]
	layout.shelves.remove_at(i)
	player.set_carry({"kind": "bucket", "title": "Eimer", "chips": chips})
	_rebuild_stands()


## Q mit dem Eimer: aufrecht am Boden abstellen, dorthin, wohin die Kamera zielt. Fehlertext, leer = abgestellt.
func bucket_drop(at: Vector2) -> String:
	if not player.carrying_bucket():
		return ""
	var err := layout.check_shelf("bucket", at, 0)
	if err != "":
		hud.show_message(err, Color(1, 0.75, 0.2))
		return err
	layout.shelves.append({"size": "bucket", "pos": at, "rot": 0, "chips": player.bucket_chips()})
	player.clear_carry()
	_rebuild_stands()
	return ""


## Linksklick mit dem Eimer auf eine Maschine: bis zu 10 kg Späne aus der Spänewanne in den Eimer.
func bucket_scoop(machine: Node) -> void:
	var tray = machine.get("tray")
	if not tray is ChipTray:
		hud.show_message("Hier fallen keine Späne an.", Color(1, 0.75, 0.2))
		return
	var chips := player.bucket_chips()
	var moved := chips.take_from(tray)
	if moved <= 0.0:
		var why := "Die Spänewanne ist leer."
		if chips.is_full():
			why = "Der Eimer ist voll."
		elif not tray.is_empty():
			why = "Im Eimer sind %sspäne, in der Wanne %sspäne: Sorten nicht mischen." % [ChipTray.SORT_TITLES.get(chips.sort(), ""), ChipTray.SORT_TITLES[tray.sort()]]
		hud.show_message(why, Color(1, 0.75, 0.2))
		return
	if machine.has_method("refresh_tray"):
		machine.refresh_tray()
	player.refresh_bucket()
	hud.show_message("%.1f kg Späne in den Eimer, jetzt %s." % [moved, Bucket.describe(chips)], Color(0.7, 0.95, 1.0))


## Die Spänekiste unter dem Späneförderer (E50) ist ein normaler Spänebehälter der Werkstatt. Jede
## Maschine mit Stellplatz bekommt ihre Kiste genau dorthin, Kisten von nicht aufgestellten Maschinen
## verschwinden.
func _sync_machine_bins() -> void:
	for i in range(layout.bins.size() - 1, -1, -1):
		var id := str(layout.bins[i].get("machine", ""))
		if id == "":
			continue
		var owner_m: Node3D = _machine_node(id) if layout.machines.has(id) else null
		if not (owner_m is Lathe and owner_m.has_chip_bin_spot):
			layout.bins.remove_at(i)
	for id in layout.machines:
		var m: Node3D = _machine_node(id)
		if not (m is Lathe and m.has_chip_bin_spot):
			continue
		var b := {}
		for e in layout.bins:
			if str(e.get("machine", "")) == id:
				b = e
		if b.is_empty():
			# Neu unter dem Förderer: übernimmt, was schon in der Kiste der Maschine liegt (alte Spielstände)
			b = {"size": Lathe.CHIP_BIN_SIZE, "chips": m.chip_bin, "out": false, "machine": id}
			layout.bins.append(b)
		# Immer der normale Behälter, auch wenn ein alter Spielstand die Kiste noch groß gespeichert hat
		b["size"] = Lathe.CHIP_BIN_SIZE
		b["chips"].capacity = float(ChipBin.SIZES[Lathe.CHIP_BIN_SIZE]["kg"])
		m.chip_bin = b["chips"]
		# Mit dem Kran herausgehoben: Der Förderer hat keine Kiste, bis sie wieder darunter steht
		m.chip_bin_away = bool(b.get("away", false)) or bool(b.get("hooked", false)) or bool(b.get("out", false)) or bool(b.get("fork", false))
		if bool(b.get("away", false)) or bool(b.get("hooked", false)) or bool(b.get("fork", false)):
			continue
		var t: Transform3D = m.transform * m.chip_bin_spot
		b["pos"] = Vector2(t.origin.x, t.origin.z)
		b["rot"] = posmod(roundi(t.basis.get_euler().y / (PI / 2.0)), 4)
		b["out"] = false


func container_prompt(i: int) -> String:
	var c: ChipTray = containers[i]
	var what := "Container %s: %d von %d kg" % [ChipTray.SORT_TITLES[c.only], int(c.kg), int(c.capacity)]
	if player.carrying_bucket():
		return "[Linksklick] Eimer leeren (Eimer %s)    |    %s" % [Bucket.describe(player.bucket_chips()), what]
	if player.carrying_bin():
		return "[Linksklick] Behälter hineinleeren    |    %s" % what
	if _carrying_scrap():
		var it: Dictionary = player.carry
		var sort := _scrap_sort(it)
		if sort != c.only:
			return "%s gehört in den Container %s    |    %s" % [str(it.get("title", "Teil")), ChipTray.SORT_TITLES[sort], what]
		if _dispose_armed == _scrap_id(it):
			return "[Linksklick] Wirklich entsorgen? Der Auftrag bleibt offen    |    %s" % what
		return "[Linksklick] %s entsorgen (%.1f kg)    |    %s" % [str(it.get("title", "Teil")), _scrap_kg(it), what]
	return what + ("    |    Voll: am PC abholen lassen" if c.is_full() else "")


## Linksklick auf einen Container im Hof: Eimer oder geschobenen Spänebehälter hineinkippen.
func container_click(i: int) -> void:
	if player.carrying_bin():
		_container_from_bin(i)
		return
	if _carrying_scrap():
		_container_from_part(i)
		return
	if not player.carrying_bucket():
		return
	var c: ChipTray = containers[i]
	var chips := player.bucket_chips()
	var moved := c.take_from(chips)
	if moved <= 0.0:
		var why := "Der Eimer ist leer."
		if c.is_full():
			why = "Der Container ist voll: am PC im Programm Entsorgung abholen lassen."
		elif not chips.is_empty():
			why = "Das sind %sspäne, sie gehören nicht in diesen Container." % ChipTray.SORT_TITLES[chips.sort()]
		hud.show_message(why, Color(1, 0.75, 0.2))
		return
	player.refresh_bucket()
	site.show_containers(containers)
	player._focus = null
	hud.show_message("%.1f kg in den Container gekippt, jetzt %d von %d kg." % [moved, int(c.kg), int(c.capacity)], Color(0.7, 0.95, 1.0))
	office_pc.overlay.waste_tab.refresh()


## Trägt die Figur ein bearbeitetes Teil (ausgespannt oder vorbearbeitet), das in den Container darf?
func _carrying_scrap() -> bool:
	return player.carrying_part() or player.carrying_semi()


## Werkstoffgruppe des Teils, wie bei den Spänen.
func _scrap_group(it: Dictionary) -> String:
	var mat := str(it.get("material", it.get("part", {}).get("material", "")))
	return str(Materials.group_of(mat)["id"])


func _scrap_sort(it: Dictionary) -> String:
	return str(ChipTray.SORTS.get(_scrap_group(it), "stahl"))


## Gewicht des Teils aus den Rohteilmaßen (nach oben abgeschätzt, die Späne fehlen schon).
func _scrap_kg(it: Dictionary) -> float:
	var mat := str(it.get("material", ""))
	var l := float(it.get("l", 0.0))
	var round_part := str(it.get("shape", "")) == "round" or str(it.get("type", "")) == "round"
	var kg := 0.0
	if round_part:
		var d := float(it.get("d", 0.0))
		if d <= 0.0:
			d = float(it.get("w", 0.0))
		kg = Materials.weight_kg(mat, Materials.KIND_ROUND, d, 0.0, 0.0, l)
	else:
		kg = Materials.weight_kg(mat, Materials.KIND_SQUARE, 0.0, float(it.get("w", 0.0)), float(it.get("h", 0.0)), l)
	return maxf(kg, 0.05)


## Kennung des getragenen Teils für die Rückfrage vor dem Entsorgen.
func _scrap_id(it: Dictionary) -> String:
	return "%s|%s|%s" % [str(it.get("kind", "")), str(it.get("key", "")), str(it.get("title", ""))]


## Gehört das getragene Teil noch zu einem offenen Auftrag? Dann erst nach einer Rückfrage wegwerfen.
func _scrap_has_job(it: Dictionary) -> bool:
	if player.carrying_semi():
		return grind_jobs.has(str(it.get("key", ""))) or accepted.has(str(it.get("key", "")))
	return _qm_open(it)


## Bearbeitetes Teil in den passenden Recyclingcontainer werfen. Bei einem offenen Auftrag fragt der erste
## Klick nach, der zweite wirft es weg.
func _container_from_part(i: int) -> void:
	var c: ChipTray = containers[i]
	var it: Dictionary = player.carry
	var sort := _scrap_sort(it)
	if sort != c.only:
		hud.show_message("Das Teil ist aus %s, es gehört in den Container %s." % [ChipTray.SORT_TITLES[sort], ChipTray.SORT_TITLES[sort]], Color(1, 0.75, 0.2))
		return
	var kg := _scrap_kg(it)
	if c.capacity - c.kg < kg:
		hud.show_message("Der Container ist zu voll für das Teil: am PC im Programm Entsorgung abholen lassen.", Color(1, 0.75, 0.2))
		return
	var id := _scrap_id(it)
	if _scrap_has_job(it) and _dispose_armed != id:
		_dispose_armed = id
		player._focus = null
		hud.show_message("%s gehört zu einem offenen Auftrag. Nochmal klicken, um es trotzdem zu entsorgen." % str(it.get("title", "Teil")), Color(1, 0.75, 0.2))
		return
	_dispose_armed = ""
	c.add(_scrap_group(it), kg)
	player.clear_carry()
	site.show_containers(containers)
	player._focus = null
	hud.show_message("%s entsorgt: %.1f kg in den Container %s, jetzt %d von %d kg." % [str(it.get("title", "Teil")), kg,
		ChipTray.SORT_TITLES[sort], int(c.kg), int(c.capacity)], Color(0.7, 0.95, 1.0))
	office_pc.overlay.waste_tab.refresh()


## Geschobenen Spänebehälter in den Container leeren.
func _container_from_bin(i: int) -> void:
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
	if Shelf.SIZES.has(id):
		return int(Shelf.SIZES[id]["price"])
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
	if Shelf.SIZES.has(id):
		return str(Shelf.SIZES[id]["title"])
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
	if m is CncMill and (m.channel.busy() or m.changing):
		return true
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
		if id == "cnc_mill":
			return "Erst das Programm beenden und die Spindel stoppen, dann umstellen."
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
	_sync_machine_bins()
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
		"cnc_mill":
			m = CncMill.new()
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
	_solidify(n)


## Teile einer Maschine, die sich drehen oder laufend neu entstehen: ohne genaue Kollision
const SOLID_SKIP := ["spindle_pivot", "spindle", "_block", "_tool_node", "_chip_heap", "_chips", "_stock_node", "chips"]

## Genaue Kollision für lose Gegenstände an Maschine n (einmal, wenn sie steht): Sie fallen aufs Bett, den
## Tisch oder in die Spänewanne statt auf die Hülle der Maschine.
func _solidify(n: Node3D) -> void:
	if n.has_meta("solid_done"):
		return
	var skip: Array = []
	for key in SOLID_SKIP:
		skip.append(n.get(key))
	var nodes = n.get("tool_nodes")
	if nodes is Array:
		skip.append_array(nodes)
	var mdl = n.get("model")
	if mdl is Object and mdl.get("_post_root") is Node:
		skip.append(mdl.get("_post_root"))              # Werkzeugkopf: dreht, Halter kommen und gehen
	for s in skip:
		if s is Node:
			(s as Node).set_meta(Solid.SKIP_META, true)
	Solid.add(n)
	n.set_meta("solid_done", true)


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
	if crane:
		crane.bench_gone(id)
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
	layout.shelves = []
	if saved is Dictionary:
		for s in saved.get("shelves", []):
			if Shelf.SIZES.has(str(s["size"])):
				layout.shelves.append({"size": str(s["size"]), "pos": Vector2(s["pos"][0], s["pos"][1]), "rot": int(s["rot"]),
						"stack": clampi(int(s.get("stack", 1)), 1, Shelf.MAX_STACK),
						"load": clampi(int(s.get("load", 0)), 0, Shelf.MAX_STACK), "cross": bool(s.get("cross", false))})
				if str(s["size"]) == "bucket":
					layout.shelves.back()["chips"] = Bucket.chips_of(s.get("chips", {}))
				if str(s["size"]) == "pallet_jack" and str(s.get("goods", "")) != "" and int(s.get("load", 0)) > 0:
					layout.shelves.back()["goods"] = str(s["goods"])
				if s.has("angle"):
					layout.shelves.back()["angle"] = float(s["angle"])
				if s.has("lift"):
					layout.shelves.back()["lift"] = clampf(float(s["lift"]), 0.0, Forklift.MAX_LIFT)
					layout.shelves.back()["load_rot"] = posmod(int(s.get("load_rot", 0)), 4)
					layout.shelves.back()["shift"] = clampf(float(s.get("shift", 0.0)), -Forklift.MAX_SHIFT, Forklift.MAX_SHIFT)
					layout.shelves.back()["tilt"] = clampf(float(s.get("tilt", 0.0)), -Forklift.TILT_FWD, Forklift.TILT_BACK)
		for c in saved.get("crates", []):
			var items = c.get("items", [])
			layout.crates.append({"size": str(c["size"]), "pos": Vector2(c["pos"][0], c["pos"][1]), "rot": int(c["rot"]),
				"bench": str(c["bench"]), "items": items.duplicate(true) if items is Array else []})
		for b in saved.get("bins", []):
			var chips := ChipTray.new(float(ChipBin.SIZES[str(b["size"])]["kg"]))
			chips.load_state(b.get("chips", {}))
			layout.bins.append({"size": str(b["size"]), "pos": Vector2(b["pos"][0], b["pos"][1]), "rot": int(b["rot"]),
				"chips": chips, "out": false})
			if str(b.get("machine", "")) != "":
				layout.bins[-1]["machine"] = str(b["machine"])
				# Mit dem Kran beiseitegestellt: bleibt dort stehen
				if bool(b.get("away", false)):
					layout.bins[-1]["away"] = true
	# Paletten, Hubwagen und Sackkarre stehen von Anfang an im Lager, auch in älteren Spielständen
	if not (saved is Dictionary and bool(saved.get("starter_transport", false))):
		for st in Shelf.STARTER:
			var pos := Vector2(float(st[1]), float(st[2]))
			if layout.check_shelf(str(st[0]), pos, int(st[3])) == "":
				layout.shelves.append({"size": str(st[0]), "pos": pos, "rot": int(st[3])})
			else:
				inventory[str(st[0])] = int(inventory.get(str(st[0]), 0)) + 1
	# Test: Ein Gabelstapler steht einmalig in der Lagerhalle, auch in älteren Spielständen
	if not (saved is Dictionary and bool(saved.get("starter_forklift", false))):
		var fk_placed := false
		for c in Shelf.STARTER_FORKLIFT:
			if layout.check_shelf("forklift", c[0], int(c[1])) == "":
				layout.shelves.append({"size": "forklift", "pos": c[0], "rot": int(c[1])})
				fk_placed = true
				break
		if not fk_placed:
			inventory["forklift"] = int(inventory.get("forklift", 0)) + 1
	# Ein Eimer steht von Anfang an im Lager, auch in älteren Spielständen
	if not (saved is Dictionary and bool(saved.get("starter_bucket", false))):
		var placed := false
		for at in Shelf.STARTER_BUCKET:
			if layout.check_shelf("bucket", at, 0) == "":
				layout.shelves.append({"size": "bucket", "pos": at, "rot": 0, "chips": ChipTray.new(Bucket.CAPACITY)})
				placed = true
				break
		if not placed:
			inventory["bucket"] = int(inventory.get("bucket", 0)) + 1
	_sync_machine_bins()
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
	var door := _door_block(m)
	if door != "":
		return door
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
	var first_machines: Variant = null
	if veteran:
		first_machines = ["lathe", "mill"]
	elif starter:
		first_machines = STARTER_MACHINES
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
		elif veteran and m != "cnc_mill":
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
	var saved_crane = d.get("crane", {})
	if saved_crane is Dictionary:
		crane.set_state(saved_crane)
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
	delivery_spots = {}
	var ds = d.get("delivery_spots", {})
	if ds is Dictionary:
		for k in ds:
			var e = ds[k]
			if e is Dictionary and e.get("pos") is Array and e["pos"].size() == 2:
				delivery_spots[str(k)] = {"pos": Vector2(float(e["pos"][0]), float(e["pos"][1])), "rot": posmod(int(e.get("rot", 1)), 4),
					"carried": bool(e.get("carried", false))}
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
	var saved_places = d.get("places", {})
	places.from_state(saved_places if saved_places is Dictionary else {})
	if d.has("player") and d["player"] is Dictionary:
		player.set_state(d["player"])
		# Gespeichert unterwegs: Der Ort muss stehen, bevor die Figur dort landet
		if player.location != Places.SITE and places.place(player.location) == null:
			player.location = Places.SITE
			player.global_position = site_entry()
		var h = d["player"].get("held", {})
		if h is Dictionary and h.has("id"):
			var hm: Node3D = _machine_node(str(h.get("machine", "lathe")))
			player.set_held(hm if hm != null else lathe, str(h["id"]))
	_release_orphan_goods()
	# Fallen Gelassenes liegt wieder da
	var saved_drops = d.get("dropped", [])
	if saved_drops is Array:
		for s in saved_drops:
			if s is Dictionary and s.get("item") is Dictionary and s.get("pos") is Array and s["pos"].size() == 3:
				var it: Dictionary = s["item"]
				if str(it.get("kind", "")) == "tool" and _machine_node(str(it.get("machine", ""))) == null:
					continue
				if str(it.get("kind", "")) == "chip_bin":
					continue          # Spänebehälter lassen sich nicht mehr tragen, alte liegende fallen weg
				DroppedItem.restore(self, player, s)
	var saved_pins = d.get("pins", [])
	if saved_pins is Array:
		for p in saved_pins:
			if p is Dictionary and p.get("job") is Dictionary and p.get("xf") is Array and p["xf"].size() == 12:
				var f: Array = p["xf"]
				var xf := Transform3D(Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), Vector3(f[6], f[7], f[8]), Vector3(f[9], f[10], f[11]))
				_add_pin(p["job"], xf, null)
		if not pins.is_empty():
			_anchor_pins.call_deferred()
	_refresh_hud()


## Alle Settings.autosave_seconds() Spielzeit automatisch speichern (Einstellungen > Spiel, 2 bis 10 min).
## Nicht in Test-Skripten (eigene SceneTree), damit sie nie den echten Spielstand überschreiben. Läuft gerade eine
## Bedienung (Maschine, KSS-Panel, Menü), wird gewartet, bis der Spieler wieder frei herumläuft.
func _tick_autosave(delta: float) -> void:
	if not autosave or get_tree().get_script() != null:
		return
	_autosave_t += delta
	if _autosave_t < Settings.autosave_seconds():
		return
	if get_tree().paused or player == null or player.operating or player.build_mode:
		return
	_autosave_t = 0.0
	if save_game():
		hud.show_message("Automatisch gespeichert.", Color(0.75, 0.85, 0.95))


func save_game() -> bool:
	_autosave_t = 0.0
	return SaveManager.write_slot(GameState.current_slot, save_data())


## Der ganze Spielstand als Dictionary (so landet er im Speicherplatz).
func save_data() -> Dictionary:
	var data := {
		"name": save_name, "money": money, "machines": company.machines, "job": job_index, "parts": parts, "play_time": play_time,
		"player": player.get_state(), "lathe": lathe.get_state(),
		"mill_job": mill_job_index, "mill": mill.get_state(), "stock": stock, "deliveries": deliveries, "site": _site_state(),
		"layout": layout.to_state(), "inventory": inventory, "skills": company.skills.to_state(),
		"tools": _tool_states(), "machine_states": _machine_states(), "drill_job": drill_job_index, "grind_jobs": grind_jobs,
		"day": day, "day_time": day_time, "day_over": day_over, "day_started": day_started, "day_stats": day_stats, "last_day_stats": last_day_stats, "deadlines": deadlines,
		"reputation": company.reputation, "rep_log": company.rep_log,
		"accepted": accepted, "tracked": tracked, "containers": containers.map(func(c: ChipTray) -> Dictionary: return c.to_state()),
		"pins": _pin_states(), "places": places.to_state(), "crane": crane.get_state(),
		"dropped": get_tree().get_nodes_in_group(DroppedItem.GROUP).map(func(n: DroppedItem) -> Dictionary: return n.get_state()),
	}
	var spots := delivery_spots.duplicate(true)
	# Sitzt jemand auf dem Gabelstapler, wird er dort gespeichert, wo er gerade steht
	if forklift and is_instance_valid(forklift):
		var fe := _forklift_entry_state(forklift)
		if forklift.load_goods != "":
			# Die Lieferpalette steht dann dort, wo die Gabel sie gerade trägt
			spots[forklift.load_goods] = {"pos": forklift.fork_spot(), "rot": posmod(roundi(forklift.phi / (PI / 2.0)) + forklift.load_rot, 4), "carried": false}
			fe["load"] = 0
		data["layout"]["shelves"].append(fe)
	var ds := {}
	for k in spots:
		var p: Vector2 = spots[k]["pos"]
		ds[k] = {"pos": [p.x, p.y], "rot": int(spots[k]["rot"]), "carried": bool(spots[k].get("carried", false))}
	data["delivery_spots"] = ds
	return data


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
