class_name Cigarette
extends Node3D
## Zigarette im Mundwinkel. Die Hände bleiben frei: Man raucht beim Tragen, in der Halle und an der Maschine.
## In der Ego-Ansicht hängt sie unten im Bild, in der Außenansicht im Mund der Figur. An der Maschine ist die
## Figur ausgeblendet, der Rauch steigt aber weiter dort auf, wo sie steht, nicht vor der Maschinenkamera.
## Ab und zu nimmt die Figur einen Zug: Die linke Hand geht zum Mund, die Zigarette hebt sich, die Glut
## leuchtet auf, danach wird mit leicht gehobenem Kinn Rauch ausgeatmet. Ausgemacht fällt ein Stummel zu Boden.

signal notice(text: String)
signal craving_changed(on: bool)

## Sucht: need 1 = gerade geraucht, sinkt mit der Spielzeit. Bei 0 setzt der Entzug ein (craving): Die Figur
## zittert, geht langsamer und das Bild verschwimmt am Rand, bis wieder eine brennt.
const NEED_TIME := 540.0          # so lange hält eine Zigarette vor (s Spielzeit, ein Tag sind 1200 s)
const NEED_REFILL := 1.6          # eine ganze Zigarette füllt das Meter mehr als ganz auf
const NEED_LOW := 0.2             # ab hier gibt es eine Warnung
const START_STOCK := 20           # eine volle Schachtel zu Spielbeginn

const R := 0.0042                 # Radius
const TOBACCO := 0.07             # Länge Tabak (m)
const FILTER := 0.022
const BAND := 0.005               # weißer Mundstückstreifen hinter dem Filter
const BURN_TIME := 240.0          # so lange brennt eine Zigarette ohne Züge (s)
const DRAG_PAUSE := Vector2(7.0, 13.0)
const INHALE := 1.3               # Dauer eines Zugs
const EXHALE_DELAY := 1.4         # nach dem Zug wird ausgeatmet
const DRAG_END := EXHALE_DELAY + 1.1
## Lage in der Ego-Ansicht (lokal zur Kamera): unten rechts im Bild, Glut nach vorn unten.
## Beim Zug hebt sie sich und rückt etwas zur Mitte.
const VIEW := Vector3(0.024, -0.082, -0.072)
const VIEW_ROT := Vector3(-0.34, 0.2, 0.0)
const VIEW_DRAG := Vector3(0.014, -0.074, -0.068)
const VIEW_DRAG_ROT := Vector3(-0.1, 0.1, 0.0)
## Lage im Mund der Figur (lokal zum Kopf)
const MOUTH := Vector3(0.022, 0.044, -0.102)
const MOUTH_ROT := Vector3(-0.32, 0.35, 0.0)
const MOUTH_DRAG_ROT := Vector3(-0.08, 0.25, 0.0)

## Rauch in Kameranähe ausblenden, sonst liegt er wie Nebel über dem ganzen Bild
const FADE_NEAR := Vector2(0.05, 0.25)

var player: Node                  # Player: cam, body, third_person, operating
var lit := false
var left := 1.0                   # verbleibender Tabak 0..1
var drags := 0
var _cigs: Array = []             # {"root", "paper", "ash", "ember", "mat"}: Ego-Ansicht und im Mund
var _wisp: CPUParticles3D         # Rauchfaden von der Glut
var _puff: CPUParticles3D         # ausgeatmeter Rauch
var _ash_fall: CPUParticles3D     # abfallende Asche
var _glow_light: OmniLight3D
var _next_drag := 4.0
var _drag_t := -1.0               # Zeit seit Beginn des Zugs, negativ = kein Zug
var _light_t := 0.0               # Feuerzeug beim Anzünden
var _time := 0.0
var _last_ash := 0
var need := 1.0                   # Sucht-Meter 0..1
var stock := START_STOCK          # Zigaretten in der Tasche, Nachschub im Supermarkt
var craving := false              # Entzug: Meter leer und keine brennt
var _warned := false


func _ready() -> void:
	top_level = true
	for i in 2:
		_cigs.append(_make_cig())
	# Dünner, ruhig aufsteigender Faden, der sich im Luftzug wiegt
	_wisp = _smoke(80, 3.4, 0.005, 0.075, 0.09, Color(0.74, 0.78, 0.86))
	_wisp.direction = Vector3(0, 1, 0)
	_wisp.spread = 4.0
	_wisp.initial_velocity_min = 0.05
	_wisp.initial_velocity_max = 0.08
	_wisp.gravity = Vector3(0, 0.025, 0)
	_wisp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_wisp.emission_sphere_radius = 0.0015
	# Ausgeatmet: weiche, graue Schwade, die schnell langsamer wird und sich verteilt
	_puff = _smoke(36, 2.8, 0.025, 0.32, 0.12, Color(0.84, 0.85, 0.87))
	_puff.one_shot = true
	_puff.explosiveness = 0.15
	_puff.spread = 14.0
	_puff.initial_velocity_min = 0.35
	_puff.initial_velocity_max = 0.6
	_puff.damping_min = 0.4
	_puff.damping_max = 0.6
	_puff.gravity = Vector3(0, 0.05, 0)
	_ash_fall = _smoke(4, 0.9, 0.003, 0.002, 0.9, Color(0.4, 0.4, 0.39))
	_ash_fall.one_shot = true
	_ash_fall.explosiveness = 0.9
	_ash_fall.gravity = Vector3(0, -6.0, 0)
	_ash_fall.initial_velocity_max = 0.1
	_ash_fall.spread = 60.0
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color(1.0, 0.45, 0.12)
	_glow_light.omni_range = 0.22
	_glow_light.light_energy = 0.0
	_glow_light.shadow_enabled = false
	add_child(_glow_light)
	_show(false)


## Eine Zigarette: Filter am Ursprung, der Tabak zeigt nach -Z, vorne die Glut.
func _make_cig() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var ember_m := CigLook.ember_mat(1.0)
	var parts: Array[MeshInstance3D] = []
	# Mundende: Faserwatte im Querschnitt, dann Korkfilter, Goldrand und weißer Mundstückstreifen
	parts.append(Build.cyl(root, R * 0.93, 0.0004, Vector3(0, 0, 0.0002), CigLook.filter_end_mat(), Build.AXIS_Z, false, 24))
	parts.append(Build.cyl(root, R, FILTER, Vector3(0, 0, -FILTER * 0.5), CigLook.filter_mat(), Build.AXIS_Z, false, 24))
	parts.append(Build.cyl(root, R * 1.006, 0.0006, Vector3(0, 0, -FILTER + 0.0003), CigLook.gold_mat(), Build.AXIS_Z, false, 24))
	parts.append(Build.cyl(root, R * 1.003, BAND, Vector3(0, 0, -FILTER - BAND * 0.5), CigLook.band_mat(), Build.AXIS_Z, false, 24))
	var paper := Build.cyl(root, R, TOBACCO, Vector3(0, 0, -FILTER - TOBACCO * 0.5), CigLook.paper_mat(), Build.AXIS_Z, false, 24)
	# Brennende Spitze: schmaler verkohlter Rand, Glut, darüber Asche, die zur Spitze hin schmaler wird
	var char_ring := Build.cyl(root, R * 1.004, 0.0014, Vector3.ZERO, CigLook.char_mat(), Build.AXIS_Z, false, 24)
	var ash := Build.cyl(root, R * 0.84, 0.006, Vector3.ZERO, CigLook.ash_mat(), Build.AXIS_Z, false, 24, R * 0.97)
	var ember := Build.cyl(root, R * 1.01, 0.0025, Vector3.ZERO, ember_m, Build.AXIS_Z, false, 24)
	parts.append_array([paper, char_ring, ash, ember])
	for mi in parts:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"root": root, "paper": paper, "char": char_ring, "ash": ash, "ember": ember, "mat": ember_m}


## Rauch aus kleinen, weichen Wölkchen, die wachsen und verblassen. Ganz nah an der Kamera ausgeblendet.
func _smoke(amount: int, life: float, size0: float, size1: float, alpha: float, col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.top_level = true
	p.local_coords = false
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true          # sonst ist jedes Wölkchen einen Meter groß
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_texture()
	m.disable_receive_shadows = true
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = FADE_NEAR.x
	m.distance_fade_max_distance = FADE_NEAR.y
	q.material = m
	p.mesh = q
	p.scale_amount_min = size0
	p.scale_amount_max = size0 * 1.3
	var grow := Curve.new()
	var g1 := size1 / size0
	grow.max_value = maxf(g1, 1.0)
	grow.add_point(Vector2(0, 1))
	grow.add_point(Vector2(0.4, lerpf(1.0, g1, 0.6)))
	grow.add_point(Vector2(1, g1))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(col, 0.0))
	fade.set_color(1, Color(col.lightened(0.08), 0.0))
	fade.add_point(0.08, Color(col, alpha))
	fade.add_point(0.45, Color(col.lightened(0.04), alpha * 0.6))
	p.color_ramp = fade
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -25.0
	p.angular_velocity_max = 25.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


static var _tex: Texture2D = null


## Weicher runder Fleck als Rauchwölkchen, zum Rand hin sanft auslaufend.
static func _puff_texture() -> Texture2D:
	if _tex != null:
		return _tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	g.add_point(0.7, Color(1, 1, 1, 0.12))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_tex = t
	return _tex


# ------------------------------------------------------------ Anzünden und Ausmachen

func toggle() -> void:
	if lit:
		put_out("Zigarette ausgemacht.")
	elif stock <= 0:
		notice.emit("Keine Zigaretten mehr: am Hoftor zum Supermarkt gehen.")
	else:
		stock -= 1
		light()


func light() -> void:
	lit = true
	left = 1.0
	drags = 0
	_drag_t = -1.0
	_next_drag = 2.5
	_light_t = 0.5
	_last_ash = 0
	_show(true)
	_wisp.emitting = true
	notice.emit("Zigarette angezündet, noch %d in der Schachtel." % stock if stock > 0 else "Zigarette angezündet, das war die letzte.")
	_set_craving(false)


func put_out(text := "") -> void:
	if not lit:
		return
	_drop_butt()
	lit = false
	_drag_t = -1.0
	_show(false)
	_wisp.emitting = false
	_glow_light.light_energy = 0.0
	_pose_body(0.0, 0.0)
	if text != "":
		notice.emit(text)


func _show(on: bool) -> void:
	for c in _cigs:
		c["root"].visible = on


## Selbst einen Zug nehmen (Linksklick ins Leere). Nur wenn eine brennt und gerade kein Zug läuft.
## Danach dauert es wieder eine Weile, bis die Figur von sich aus zieht.
func take_drag() -> bool:
	if not lit or _drag_t >= 0.0:
		return false
	_drag_t = 0.0
	drags += 1
	_next_drag = randf_range(DRAG_PAUSE.x, DRAG_PAUSE.y)
	return true


## Gerade beim Zug? 0 = nein, 1 = Glut am hellsten.
func glow() -> float:
	if _drag_t < 0.0:
		return 0.0
	if _drag_t < INHALE:
		return _drag_t / INHALE
	return clampf(1.0 - (_drag_t - INHALE) / 0.8, 0.0, 1.0)


## Hand am Mund und Zigarette angehoben: 0..1 während des Zugs.
func lift() -> float:
	if _drag_t < 0.0:
		return 0.0
	return smoothstep(0.0, 0.45, _drag_t) * (1.0 - smoothstep(INHALE, INHALE + 0.5, _drag_t))


## Kinn beim Ausatmen leicht gehoben.
func chin() -> float:
	if _drag_t < EXHALE_DELAY:
		return 0.0
	return sin(PI * clampf((_drag_t - EXHALE_DELAY) / (DRAG_END - EXHALE_DELAY), 0.0, 1.0))


# ------------------------------------------------------------ Ablauf

func _process(delta: float) -> void:
	if player == null:
		return
	if not lit:
		tick_need(delta)
		return
	_time += delta
	# Abbrennen, beim Zug schneller
	var g := glow()
	var burnt := delta / BURN_TIME * (1.0 + g * 3.0)
	left -= burnt
	tick_need(delta, burnt)
	if left <= 0.0:
		put_out("Zigarette aufgeraucht.")
		return
	_next_drag -= delta
	if _drag_t < 0.0 and _next_drag <= 0.0:
		_drag_t = 0.0
		drags += 1
	if _drag_t >= 0.0:
		var before := _drag_t
		_drag_t += delta
		if before < EXHALE_DELAY and _drag_t >= EXHALE_DELAY:
			_exhale()
		if _drag_t > DRAG_END:
			_drag_t = -1.0
			_next_drag = randf_range(DRAG_PAUSE.x, DRAG_PAUSE.y)
	_light_t = maxf(_light_t - delta, 0.0)
	_pose_body(lift(), chin())
	_place()


## Sucht-Meter fortschreiben: Ohne Zigarette sinkt es, verbrannter Tabak füllt es auf.
func tick_need(delta: float, burnt := 0.0) -> void:
	if lit:
		need = minf(need + burnt * NEED_REFILL, 1.0)
	else:
		need = maxf(need - delta / NEED_TIME, 0.0)
	if need > NEED_LOW + 0.1:
		_warned = false
	elif not _warned and not lit and need > 0.0:
		_warned = true
		notice.emit("Du brauchst bald eine Zigarette.")
	_set_craving(need <= 0.0 and not lit)


func _set_craving(on: bool) -> void:
	if on == craving:
		return
	craving = on
	craving_changed.emit(on)
	if on:
		notice.emit("Entzug! Die Hände zittern, alles geht langsamer: %s zum Rauchen." % Settings.binding_text("smoke"))


## Arbeitstempo der Figur: im Entzug deutlich langsamer.
func work_factor() -> float:
	return 0.55 if craving else 1.0


func _pose_body(hand: float, c: float) -> void:
	if player == null or player.body == null:
		return
	player.body.set("smoke_hand", hand)
	player.body.set("smoke_chin", c)


## Ego-Ansicht: Zigarette vor der Kamera. Sonst (Außenansicht, an der Maschine) im Mund der Figur.
func _first_person() -> bool:
	return player.operating == null and not player.third_person


## Zigaretten an Kamera und Mund setzen, Länge, Glut und Rauch nachführen.
func _place() -> void:
	var cam: Camera3D = player.cam
	var fp := _first_person()
	var view: Dictionary = _cigs[0]
	var mouth: Dictionary = _cigs[1]
	view["root"].visible = fp
	# An der Maschine ist die Figur ausgeblendet, eine schwebende Zigarette sähe seltsam aus
	mouth["root"].visible = not fp and player.operating == null
	var up := lift()
	if cam != null:
		var rot := VIEW_ROT.lerp(VIEW_DRAG_ROT, up)
		view["root"].global_transform = cam.global_transform * Transform3D(Basis.from_euler(rot), VIEW.lerp(VIEW_DRAG, up))
	var head: Node3D = player.body.get("_head")
	if head != null:
		var mrot := MOUTH_ROT.lerp(MOUTH_DRAG_ROT, up)
		mouth["root"].global_transform = head.global_transform * Transform3D(Basis.from_euler(mrot), MOUTH)
	var g := glow()
	var tip := -FILTER - TOBACCO * left
	var ash_phase := (1.0 - left) * 4.0
	var ash_len := 0.003 + 0.01 * fposmod(ash_phase, 1.0)
	for c in _cigs:
		var paper: Node3D = c["paper"]
		paper.scale.y = maxf(left, 0.02)          # Länge liegt auf der Y-Achse des Zylinders
		paper.position.z = -FILTER - TOBACCO * left * 0.5
		c["ash"].scale.y = ash_len / 0.006
		c["ash"].position.z = tip - 0.002 - ash_len * 0.5
		c["ember"].position.z = tip - 0.0012
		c["char"].position.z = tip + 0.0004
		c["mat"].emission_energy_multiplier = 1.2 + g * 5.0 + _light_t * 6.0
	# Rauch kommt immer aus der Zigarette der Figur (in der Ego-Ansicht ist das die vor der Kamera)
	var active: Dictionary = view if fp else mouth
	var ember_pos: Vector3 = (active["ember"] as Node3D).global_position
	_wisp.global_position = ember_pos
	# Leichter Luftzug in der Halle: Der Faden wiegt sich und kräuselt
	_wisp.gravity = Vector3(sin(_time * 0.7) * 0.035 + sin(_time * 2.3) * 0.01, 0.025, cos(_time * 0.53) * 0.03)
	_glow_light.global_position = ember_pos
	_glow_light.light_energy = (0.06 + g * 0.15 + _light_t * 1.0) if player.operating == null else 0.0
	if int(ash_phase) > _last_ash:
		_last_ash = int(ash_phase)
		_ash_fall.global_position = ember_pos
		_ash_fall.restart()
		_ash_fall.emitting = true


## Rauch aus dem Mund ausatmen, in Blickrichtung der Figur.
func _exhale() -> void:
	var from: Transform3D
	var head: Node3D = player.body.get("_head")
	if _first_person() and player.cam != null:
		from = player.cam.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.07, -0.08))
	elif head != null:
		from = head.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.04, -0.12))
		if player.operating != null:
			# Kopf ist an der Maschine nicht animiert: Blick waagerecht nach vorn
			from.basis = Basis(Vector3.UP, player.yaw)
	else:
		return
	_puff.global_transform = from
	_puff.direction = Vector3(0, -0.25, -1)
	_puff.restart()
	_puff.emitting = true


# ------------------------------------------------------------ Stummel

## Ausgemacht: Ein kurzer Stummel fällt aus dem Mund und bleibt auf dem Boden liegen.
func _drop_butt() -> void:
	var world := player.get_parent() if player != null else null
	if world == null or not is_inside_tree():
		return
	var src: Node3D = _cigs[0]["root"] if _first_person() else _cigs[1]["root"]
	var stub := maxf(TOBACCO * left, 0.008)
	var b := CigButt.new()
	b.name = "Kippe"
	b.build(R, FILTER, stub)
	world.add_child(b)
	# Mitte des Stummels an die Stelle der Zigarette
	b.global_transform = src.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, -(FILTER + stub) * 0.5))
	var fwd: Vector3 = -player.global_basis.z
	var side: Vector3 = player.global_basis.x
	# An der Maschine fällt er vor die Füße statt in den Arbeitsraum
	var toss := 0.9 if player.operating == null else -0.25
	b.vel = fwd * toss + side * randf_range(-0.3, 0.3) + Vector3(0, 0.9 if player.operating == null else 0.3, 0)
	b.spin = Vector3(randf_range(-9, 9), randf_range(-4, 4), randf_range(-9, 9))


func get_state() -> Dictionary:
	return {"lit": lit, "left": left, "need": need, "stock": stock}


func set_state(d: Dictionary) -> void:
	need = clampf(float(d.get("need", 1.0)), 0.0, 1.0)
	stock = maxi(int(d.get("stock", START_STOCK)), 0)
	_set_craving(need <= 0.0 and not bool(d.get("lit", false)))
	if bool(d.get("lit", false)):
		light()
		left = clampf(float(d.get("left", 1.0)), 0.05, 1.0)
