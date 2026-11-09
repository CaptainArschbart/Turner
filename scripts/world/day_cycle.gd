class_name DayCycle
extends Node
## Tag und Nacht: Die Uhrzeit (Stunde, durchgehend gezählt, nach Mitternacht über 24) bestimmt Sonnen- und
## Mondstand, Licht- und Himmelsfarben, Dämmerungsglühen, Sterne, Dunst und Morgennebel, das Tageslicht durch
## das Fensterband der Halle und das Grundlicht. Nachts gehen Straßenlaternen und Hofstrahler an: Lichter in der
## Gruppe "night_light" (Meta "energy") und leuchtende Meshes in der Gruppe "night_glow" (Meta "energy").
## Innen bleibt es durch die Hallenleuchten hell.

const SUNRISE := 6.2
const SUNSET := 17.8
const MAX_ELEVATION := deg_to_rad(56.0)
const MOONRISE := 19.0            # Der Mond zieht nachts von Osten über Süden nach Westen
const MOONSET := 29.0
const MOON_ELEVATION := deg_to_rad(38.0)

const DAY_TOP := Color(0.2, 0.42, 0.78)
const DAY_HORIZON := Color(0.66, 0.79, 0.92)
const GOLDEN_HORIZON := Color(1.0, 0.78, 0.52)
const DUSK_TOP := Color(0.2, 0.22, 0.46)
const DUSK_HORIZON := Color(1.0, 0.5, 0.26)
const BLUE_TOP := Color(0.06, 0.1, 0.26)        # blaue Stunde nach Sonnenuntergang
const BLUE_HORIZON := Color(0.22, 0.28, 0.5)
const NIGHT_TOP := Color(0.006, 0.01, 0.03)
const NIGHT_HORIZON := Color(0.03, 0.05, 0.1)

var env: Environment
var sun: DirectionalLight3D
var window_mat: StandardMaterial3D
var window_light: OmniLight3D
var hour := 12.0                  # Ziel
var shown := -1.0                 # gerade dargestellte Stunde, läuft weich hinterher
var daylight := 1.0               # 0 = Nacht, 1 = voller Tag
var night := 0.0                  # 1 = Laternen an
var _sky_mat: ShaderMaterial


func setup(environment: Environment, sun_light: DirectionalLight3D, lights: Dictionary) -> void:
	env = environment
	sun = sun_light
	window_mat = lights.get("window_mat", null)
	window_light = lights.get("window_light", null)
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://scripts/world/sky.gdshader")
	env.sky.sky_material = _sky_mat
	env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky.radiance_size = Sky.RADIANCE_SIZE_64
	# Luftperspektive: Ferne Dinge nehmen die Himmelsfarbe an, morgens liegt etwas Nebel über dem Gelände
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.55
	_apply(hour)


func set_hour(h: float) -> void:
	hour = h


func _process(delta: float) -> void:
	if shown < 0.0 or absf(hour - shown) > 3.0:
		shown = hour
	else:
		shown = move_toward(shown, hour, delta * 0.4)
	_apply(shown)


## Richtung zur Sonne. Tagsüber von Osten über Süden nach Westen, nachts unter dem Horizont weiter, damit die
## Dämmerung nach Sonnenuntergang langsam ausklingt und vor Sonnenaufgang langsam beginnt.
static func sun_direction(h: float) -> Vector3:
	var t := h if h >= SUNRISE - 3.0 else h + 24.0
	var el: float
	var az: float
	if t <= SUNSET:
		var f := (t - SUNRISE) / (SUNSET - SUNRISE)
		el = sin(f * PI) * MAX_ELEVATION
		az = PI * f
	else:
		var f := (t - SUNSET) / (24.0 - (SUNSET - SUNRISE))
		el = -sin(f * PI) * deg_to_rad(50.0)
		az = PI + PI * f
	# Osten = +X, Süden = +Z
	return Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)).normalized()


static func moon_direction(h: float) -> Vector3:
	var t := h if h >= 12.0 else h + 24.0
	var f := (t - MOONRISE) / (MOONSET - MOONRISE)
	var el := sin(clampf(f, -0.15, 1.15) * PI) * MOON_ELEVATION
	var az := PI * clampf(f, -0.15, 1.15)
	return Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el) * 0.8 + 0.2).normalized()


func _apply(h: float) -> void:
	if env == null or sun == null:
		return
	var to_sun := sun_direction(h)
	var s := to_sun.y
	daylight = smoothstep(-0.1, 0.22, s)
	# Goldene Stunde (Sonne tief), Abendrot (am Horizont), blaue Stunde (knapp darunter)
	var golden := (1.0 - smoothstep(0.08, 0.35, s)) * smoothstep(-0.02, 0.06, s)
	var warm := (1.0 - smoothstep(0.02, 0.2, s)) * smoothstep(-0.1, 0.0, s)
	var blue := (1.0 - smoothstep(-0.08, 0.0, s)) * smoothstep(-0.3, -0.12, s)
	night = 1.0 - smoothstep(-0.12, 0.02, s)

	var top := NIGHT_TOP.lerp(BLUE_TOP, blue).lerp(DAY_TOP, daylight).lerp(DUSK_TOP, warm * 0.6)
	var horizon := NIGHT_HORIZON.lerp(BLUE_HORIZON, blue).lerp(DAY_HORIZON, daylight)
	horizon = horizon.lerp(GOLDEN_HORIZON, golden * 0.45).lerp(DUSK_HORIZON, warm * 0.85)

	var to_moon := moon_direction(h)
	var moon_up := smoothstep(-0.02, 0.15, to_moon.y)
	if s > -0.04:
		sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.78, 0.55), golden).lerp(Color(1.0, 0.5, 0.25), warm)
		sun.light_energy = 1.25 * smoothstep(-0.04, 0.16, s)
		sun.basis = Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
		_sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.92, 0.8).lerp(Color(1.0, 0.55, 0.22), maxf(warm, golden * 0.5)))
		_sky_mat.set_shader_parameter("sun_size", 0.9995)
		_sky_mat.set_shader_parameter("sun_glow", 0.5 + warm * 1.2 + golden * 0.4)
	else:
		# Nachts ist der Mond die Lichtquelle: kühl und schwach, solange er über dem Horizont steht
		var md := to_moon if to_moon.y > 0.05 else Vector3(to_moon.x, 0.05, to_moon.z).normalized()
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.light_energy = 0.26 * night * (0.35 + 0.65 * moon_up)
		sun.basis = Basis.looking_at(-md, Vector3.UP)
		_sky_mat.set_shader_parameter("sun_color", Color(0.92, 0.94, 1.0))
		_sky_mat.set_shader_parameter("sun_size", 0.99975)
		_sky_mat.set_shader_parameter("sun_glow", 0.2 * moon_up)

	_sky_mat.set_shader_parameter("top_color", top)
	_sky_mat.set_shader_parameter("horizon_color", horizon)
	_sky_mat.set_shader_parameter("ground_color", horizon.darkened(0.55))
	_sky_mat.set_shader_parameter("stars", 1.0 - smoothstep(0.0, 0.3, daylight + blue * 0.5))
	_sky_mat.set_shader_parameter("sun_dir", to_sun)
	_sky_mat.set_shader_parameter("twilight", clampf(warm + blue * 0.6 + golden * 0.3, 0.0, 1.0))
	_sky_mat.set_shader_parameter("twilight_color", DUSK_HORIZON.lerp(Color(0.95, 0.45, 0.4), blue))
	_sky_mat.set_shader_parameter("cloud_color", Color(0.1, 0.11, 0.15).lerp(Color(1.0, 1.0, 1.0), daylight)
			.lerp(Color(1.0, 0.68, 0.5), warm * 0.8).lerp(Color(0.45, 0.42, 0.6), blue * 0.6))
	_sky_mat.set_shader_parameter("cloud_lit", Color(1.0, 0.85, 0.65).lerp(Color(1.0, 0.45, 0.3), warm) * (golden + warm))

	env.ambient_light_color = Color(0.36, 0.42, 0.6).lerp(Color(0.78, 0.8, 0.84), daylight).lerp(Color(0.9, 0.7, 0.6), warm * 0.4)
	env.ambient_light_energy = lerpf(0.28, 0.4, daylight)
	# Dunst in Himmelsfarbe, am Morgen etwas Nebel über dem Gelände
	var t := h if h < 24.0 else h - 24.0
	var mist := smoothstep(4.5, 6.3, t) * (1.0 - smoothstep(6.5, 9.0, t))
	env.fog_light_color = horizon.lerp(Color(0.85, 0.87, 0.9), mist * daylight * 0.5)
	env.fog_density = 0.0016 + mist * 0.006 + night * 0.0008
	env.fog_sun_scatter = 0.25 * (golden + warm)
	# Belichtung: Die Nacht bleibt dunkel, aber lesbar
	env.tonemap_exposure = lerpf(1.25, 1.0, daylight)
	if window_mat:
		var wc := horizon.lerp(top, 0.4).lightened(0.25 * daylight)
		window_mat.albedo_color = wc
		window_mat.emission = wc
		window_mat.emission_energy_multiplier = lerpf(0.1, 1.6, daylight)
	if window_light:
		window_light.light_color = Color(0.8, 0.88, 1.0).lerp(Color(1.0, 0.75, 0.55), warm)
		window_light.light_energy = 0.8 * daylight
	_night_lights()


## Laternen und Strahler: Sie gehen in der Dämmerung an und morgens wieder aus.
func _night_lights() -> void:
	if not is_inside_tree():
		return
	var on := smoothstep(0.25, 0.75, night)
	for l in get_tree().get_nodes_in_group("night_light"):
		var light := l as Light3D
		light.light_energy = float(light.get_meta("energy", 1.0)) * on
		light.visible = on > 0.01
	for g in get_tree().get_nodes_in_group("night_glow"):
		var m := (g as MeshInstance3D).material_override as StandardMaterial3D
		if m:
			m.emission_energy_multiplier = lerpf(0.15, float(g.get_meta("energy", 3.0)), on)
