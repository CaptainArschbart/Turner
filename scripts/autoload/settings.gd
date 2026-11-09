extends Node
## Globale Einstellungen: Grafik, Audio, Maus, Spiel, Tastenbelegung.
## Wird in user://settings.cfg gespeichert.

signal changed

const PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const QUALITY_NAMES := ["Niedrig", "Mittel", "Hoch", "Ultra"]
const WINDOW_MODES := ["Fenster", "Vollbild (randlos)", "Exklusives Vollbild"]
const FPS_LIMITS := [0, 30, 60, 120, 144, 240]
const MSAA_NAMES := ["Aus", "2x MSAA", "4x MSAA", "8x MSAA"]
const HANDWHEEL_STEPS := [0.001, 0.01, 0.1]
const HANDWHEEL_NAMES := ["0,001 mm", "0,01 mm", "0,1 mm"]
## Automatisch speichern alle so viele Minuten (Spielzeit ohne Pause)
const AUTOSAVE_MIN := 2
const AUTOSAVE_MAX := 10
## Bei Änderung der Standardbelegung erhöhen -> alte gespeicherte Belegung wird verworfen.
const CONTROLS_VERSION := 3

## [Aktion, Anzeigename, Gruppe, Typ ("k" Taste / "m" Maustaste), Code]
const BINDINGS := [
	["move_forward", "Vorwärts gehen", "Bewegung", "k", KEY_W],
	["move_back", "Rückwärts gehen", "Bewegung", "k", KEY_S],
	["move_left", "Nach links", "Bewegung", "k", KEY_A],
	["move_right", "Nach rechts", "Bewegung", "k", KEY_D],
	["jump", "Springen", "Bewegung", "k", KEY_SPACE],
	["sprint", "Rennen", "Bewegung", "k", KEY_SHIFT],
	["crouch", "Ducken", "Bewegung", "k", KEY_CTRL],
	["interact", "Interagieren / Maschine bedienen", "Bewegung", "k", KEY_E],
	["drop", "Getragenes fallen lassen", "Bewegung", "k", KEY_Q],
	["toggle_view", "Kamera 1./3. Person", "Bewegung", "k", KEY_V],
	["lathe_z_minus", "Bettschlitten zum Futter (Z-)", "Drehmaschine", "k", KEY_A],
	["lathe_z_plus", "Bettschlitten weg vom Futter (Z+)", "Drehmaschine", "k", KEY_D],
	["lathe_x_in", "Planschlitten zustellen (X-)", "Drehmaschine", "k", KEY_W],
	["lathe_x_out", "Planschlitten zurück (X+)", "Drehmaschine", "k", KEY_S],
	["lathe_rapid", "10-facher Vorschub beim Verfahren (halten)", "Drehmaschine", "k", KEY_SHIFT],
	["hw_axis", "Handrad-Achse X / Z umschalten", "Drehmaschine", "k", KEY_TAB],
	["hw_step", "Handrad-Schritt 0,001 / 0,01 / 0,1 mm", "Drehmaschine", "k", KEY_Q],
	["spindle_toggle", "Spindel Start / Stopp", "Drehmaschine", "k", KEY_SPACE],
	["rpm_up", "Drehzahl erhöhen", "Drehmaschine", "k", KEY_R],
	["rpm_down", "Drehzahl verringern", "Drehmaschine", "k", KEY_F],
	["auto_feed", "Auto-Vorschub an/aus (in Handrad-Achse)", "Drehmaschine", "k", KEY_V],
	["feed_up", "Vorschub erhöhen", "Drehmaschine", "k", KEY_T],
	["feed_down", "Vorschub verringern", "Drehmaschine", "k", KEY_G],
	["coolant", "Kühlschmierstoff an/aus", "Drehmaschine", "k", KEY_C],
	["emergency_stop", "Not-Halt / quittieren", "Drehmaschine", "k", KEY_X],
	["door_toggle", "Schutztür auf- / zuschieben", "Drehmaschine", "k", KEY_O],
	["new_workpiece", "Rohteil anfordern (Testmodus)", "Drehmaschine", "k", KEY_N],
	["submit_part", "Teil prüfen & abgeben", "Drehmaschine", "k", KEY_ENTER],
	["mill_z_up", "Fräskopf heben (Z+)", "Fräsmaschine", "k", KEY_Z],
	["mill_z_down", "Fräskopf senken (Z-)", "Fräsmaschine", "k", KEY_H],
	["zoom_in", "Heranzoomen (halten)", "Kamera an der Maschine", "k", KEY_PLUS],
	["zoom_out", "Herauszoomen (halten)", "Kamera an der Maschine", "k", KEY_MINUS],
	["cam_top", "Draufsicht (genau von oben)", "Kamera an der Maschine", "k", KEY_F1],
	["cam_front", "Vorderansicht", "Kamera an der Maschine", "k", KEY_F2],
	["cam_reset", "Standardansicht / Verschiebung zurück", "Kamera an der Maschine", "k", KEY_F3],
	["cam_panel", "Blick auf das Bedienpult (an/aus)", "Kamera an der Maschine", "k", KEY_F4],
	["pause", "Pause-Menü", "Allgemein", "k", KEY_ESCAPE],
	["show_drawing", "Werkstückzeichnung ein / aus", "Allgemein", "k", KEY_P],
	["smoke", "Zigarette anzünden / ausmachen", "Allgemein", "k", KEY_K],
	["job_menu", "Angenommene Aufträge (nicht an Maschinen)", "Allgemein", "k", KEY_TAB],
	["build_menu", "Baumenü (nicht an Maschinen)", "Allgemein", "k", KEY_B],
]

var graphics: Dictionary = {}
var audio: Dictionary = {}
var mouse: Dictionary = {}
var game: Dictionary = {}
var controls: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_defaults()
	load_settings()
	_ensure_buses()
	apply_controls()
	apply_audio()
	apply_graphics()


func _set_defaults() -> void:
	graphics = {
		"window_mode": 0, "resolution": 1, "vsync": true, "fps_limit": 0,
		"quality": 2, "render_scale": 1.0, "fov": 75.0, "brightness": 1.0, "bloom": 1.0,
		"msaa": 1, "show_fps": false,
	}
	audio = {"master": 0.8, "sfx": 0.8, "ambient": 0.5, "mute": false}
	mouse = {"sensitivity": 0.25, "invert_y": false, "handwheel_step": 1, "handwheel_invert": false}
	game = {"autosave_minutes": 5}
	controls = {}
	for b in BINDINGS:
		controls[b[0]] = "%s:%d" % [b[3], b[4]]


func reset_defaults() -> void:
	_set_defaults()
	apply_controls()
	apply_audio()
	apply_graphics()
	save_settings()
	changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in graphics.keys():
		graphics[k] = cfg.get_value("graphics", k, graphics[k])
	for k in audio.keys():
		audio[k] = cfg.get_value("audio", k, audio[k])
	for k in mouse.keys():
		mouse[k] = cfg.get_value("mouse", k, mouse[k])
	for k in game.keys():
		game[k] = cfg.get_value("game", k, game[k])
	game["autosave_minutes"] = clampi(int(game["autosave_minutes"]), AUTOSAVE_MIN, AUTOSAVE_MAX)
	var cv := int(cfg.get_value("meta", "controls_version", 1))
	if cv < 2:
		# Steuerung wurde vereinfacht: alte Belegung und alte Handrad-Stufen nicht übernehmen
		mouse["handwheel_step"] = 1
		return
	for k in controls.keys():
		controls[k] = str(cfg.get_value("controls", k, controls[k]))
	if cv < 3:
		controls["drop"] = "k:%d" % KEY_Q      # Fallenlassen liegt jetzt auf Q


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in graphics.keys():
		cfg.set_value("graphics", k, graphics[k])
	for k in audio.keys():
		cfg.set_value("audio", k, audio[k])
	for k in mouse.keys():
		cfg.set_value("mouse", k, mouse[k])
	for k in game.keys():
		cfg.set_value("game", k, game[k])
	for k in controls.keys():
		cfg.set_value("controls", k, controls[k])
	cfg.set_value("meta", "controls_version", CONTROLS_VERSION)
	cfg.save(PATH)


func set_value(section: String, key: String, value) -> void:
	match section:
		"graphics":
			graphics[key] = value
			apply_graphics()
		"audio":
			audio[key] = value
			apply_audio()
		"mouse":
			mouse[key] = value
		"game":
			game[key] = value
	changed.emit()


## Abstand zwischen zwei automatischen Speicherungen in Sekunden.
func autosave_seconds() -> float:
	return clampi(int(game.get("autosave_minutes", 5)), AUTOSAVE_MIN, AUTOSAVE_MAX) * 60.0


# ---------------------------------------------------------------- Grafik

func apply_graphics() -> void:
	var mode := int(graphics["window_mode"])
	if DisplayServer.get_name() != "headless":
		match mode:
			0:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var res: Vector2i = RESOLUTIONS[clampi(int(graphics["resolution"]), 0, RESOLUTIONS.size() - 1)]
				var screen := DisplayServer.window_get_current_screen()
				var ss := DisplayServer.screen_get_size(screen)
				res = Vector2i(mini(res.x, ss.x), mini(res.y, ss.y))
				if DisplayServer.window_get_size() != res:
					DisplayServer.window_set_size(res)
					DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + (ss - res) / 2)
			1:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			2:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if bool(graphics["vsync"]) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(graphics["fps_limit"])
	var vp := get_viewport()
	vp.scaling_3d_scale = float(graphics["render_scale"])
	var msaa_modes := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
	vp.msaa_3d = msaa_modes[clampi(int(graphics["msaa"]), 0, 3)]
	var q := clampi(int(graphics["quality"]), 0, 3)
	vp.positional_shadow_atlas_size = [1024, 2048, 4096, 8192][q]


## Bloom (Glow) auf ein Environment anwenden. Stärke 0 = aus, 1 = Standard, 2 = doppelt.
## Auf "Niedrig" bleibt Bloom aus Performance-Gründen immer aus.
func apply_bloom(env: Environment) -> void:
	var k := clampf(float(graphics["bloom"]), 0.0, 2.0)
	env.glow_enabled = k > 0.001 and int(graphics["quality"]) >= 1
	env.glow_intensity = 0.35 * k
	env.glow_bloom = 0.03 * k


# ---------------------------------------------------------------- Audio

func _ensure_buses() -> void:
	for bus_name in ["SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")


func apply_audio() -> void:
	_set_bus("Master", float(audio["master"]))
	AudioServer.set_bus_mute(0, bool(audio["mute"]))
	_set_bus("SFX", float(audio["sfx"]))
	_set_bus("Ambient", float(audio["ambient"]))


func _set_bus(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))


# ---------------------------------------------------------------- Steuerung

func apply_controls() -> void:
	for b in BINDINGS:
		var action: String = b[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var ev := event_from_spec(str(controls.get(action, "")))
		if ev:
			InputMap.action_add_event(action, ev)


func set_binding(action: String, ev: InputEvent) -> void:
	controls[action] = spec_from_event(ev)
	apply_controls()
	changed.emit()


func event_from_spec(spec: String) -> InputEvent:
	var parts := spec.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "m":
		var m := InputEventMouseButton.new()
		m.button_index = int(parts[1]) as MouseButton
		return m
	var k := InputEventKey.new()
	k.keycode = int(parts[1]) as Key
	return k


func spec_from_event(ev: InputEvent) -> String:
	if ev is InputEventMouseButton:
		return "m:%d" % int((ev as InputEventMouseButton).button_index)
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := int(k.keycode)
		if code == 0:
			code = int(k.physical_keycode)
		return "k:%d" % code
	return ""


func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		match k.keycode:
			KEY_SPACE: return "Leertaste"
			KEY_SHIFT: return "Umschalt"
			KEY_CTRL: return "Strg"
			KEY_ALT: return "Alt"
			KEY_ENTER: return "Enter"
			KEY_ESCAPE: return "Esc"
			KEY_PAGEUP: return "Bild auf"
			KEY_PAGEDOWN: return "Bild ab"
			KEY_BACKSPACE: return "Rücktaste"
			KEY_TAB: return "Tab"
			KEY_UP: return "Pfeil hoch"
			KEY_DOWN: return "Pfeil runter"
			KEY_LEFT: return "Pfeil links"
			KEY_RIGHT: return "Pfeil rechts"
		return OS.get_keycode_string(k.keycode)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Linke Maustaste"
			MOUSE_BUTTON_RIGHT: return "Rechte Maustaste"
			MOUSE_BUTTON_MIDDLE: return "Mittlere Maustaste"
			MOUSE_BUTTON_WHEEL_UP: return "Mausrad hoch"
			MOUSE_BUTTON_WHEEL_DOWN: return "Mausrad runter"
			MOUSE_BUTTON_XBUTTON1: return "Maustaste 4"
			MOUSE_BUTTON_XBUTTON2: return "Maustaste 5"
		return "Maustaste %d" % int((ev as InputEventMouseButton).button_index)
	return "-"


func binding_text(action: String) -> String:
	return event_text(event_from_spec(str(controls.get(action, ""))))


func handwheel_step() -> float:
	return HANDWHEEL_STEPS[clampi(int(mouse["handwheel_step"]), 0, HANDWHEEL_STEPS.size() - 1)]


func handwheel_step_name() -> String:
	return HANDWHEEL_NAMES[clampi(int(mouse["handwheel_step"]), 0, HANDWHEEL_NAMES.size() - 1)]


## Drehknebel an der Maschine: 0,001 -> 0,01 -> 0,1 -> 0,001 ...
func cycle_handwheel_step() -> void:
	mouse["handwheel_step"] = (int(mouse["handwheel_step"]) + 1) % HANDWHEEL_STEPS.size()
	save_settings()
	changed.emit()


## Handrad-Schritt direkt wählen (Wahlschalter im Bedienpult): 0 = 0,001, 1 = 0,01, 2 = 0,1 mm.
func set_handwheel_step(i: int) -> void:
	i = clampi(i, 0, HANDWHEEL_STEPS.size() - 1)
	if int(mouse["handwheel_step"]) == i:
		return
	mouse["handwheel_step"] = i
	save_settings()
	changed.emit()
