extends Node3D
## Spielwelt: Werkstatt, Drehmaschine, Spieler, HUD, Pause-Menü, Aufträge und Speichern.

var player: Player
var lathe: Lathe
var office_pc: OfficePC
var hud: HUD
var pause_menu: PauseMenu
var env: Environment
var probe: ReflectionProbe
var _lights: Dictionary = {}
var _ambient: AudioStreamPlayer
var _amb_pb: AudioStreamGeneratorPlayback
var _amb_lp := 0.0
var _amb_ph := 0.0

var save_name := "Werkstatt"
var money := 0
var job_index := 0
var parts := 0
var play_time := 0.0


func _ready() -> void:
	_build_environment()
	_lights = Workshop.build(self)

	lathe = Lathe.new()
	lathe.position = Vector3(0, 0, -2.0)
	add_child(lathe)

	office_pc = OfficePC.new()
	office_pc.position = Vector3(10.5, 1.05, 7.54)
	add_child(office_pc)

	player = Player.new()
	player.position = Vector3(0.5, 0.05, 2.5)
	add_child(player)

	hud = HUD.new()
	hud.lathe = lathe
	add_child(hud)

	pause_menu = PauseMenu.new()
	pause_menu.world = self
	add_child(pause_menu)

	player.prompt_changed.connect(hud.set_prompt)
	lathe.message.connect(hud.show_message)
	lathe.operating_changed.connect(hud.set_operating)
	lathe.submit_requested.connect(_on_submit)
	lathe.new_part_requested.connect(_on_new_part)
	office_pc.using_changed.connect(func(on: bool): hud.visible = not on)
	Settings.changed.connect(_apply_quality)

	_apply_pending(GameState.pending)
	_apply_quality()
	_setup_ambient()
	restore_mouse()
	hud.show_message("Willkommen in der Werkstatt, %s! Geh zur Drehmaschine und drücke [%s]." % [
		save_name, Settings.binding_text("interact")], Color(0.9, 0.95, 1.0))


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.06)
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
	probe.visible = q >= 1


func _process(delta: float) -> void:
	play_time += delta
	_fill_ambient()


# ------------------------------------------------------------ Aufträge

func _current_job() -> Dictionary:
	return Jobs.get_job(job_index)


func _refresh_hud() -> void:
	hud.set_money(money, parts)
	hud.set_job(Jobs.describe(_current_job()))
	hud.set_job_data(_current_job())


func _on_new_part() -> void:
	var job := _current_job()
	lathe.new_workpiece(float(job["stock_d"]), float(job["stock_len"]))
	hud.show_message("Neues Rohteil Ø%d x %d eingespannt." % [int(job["stock_d"]), int(job["stock_len"])])


func _on_submit() -> void:
	if lathe.is_untouched():
		hud.show_message("Das Rohteil ist noch unbearbeitet.", Color(1, 0.75, 0.2))
		return
	var job := _current_job()
	var res := lathe.evaluate(job)
	var score := float(res["score"])
	var pay := 0
	var verdict := ""
	if score >= 0.999:
		pay = int(job["reward"])
		verdict = "Alle Maße in Toleranz - sehr gut!"
	elif score >= 0.5:
		pay = int(round(float(job["reward"]) * score * 0.5))
		verdict = "Nacharbeit nötig - Teilvergütung."
	else:
		verdict = "Ausschuss! Keine Vergütung."
	money += pay
	parts += 1
	var lines: Array = res["lines"]
	var text := "PRÜFPROTOKOLL - %s\n\n%s\n\n%d / %d Merkmale in Ordnung\n%s\nVergütung: %d EUR" % [
		job["title"], "\n".join(lines), int(res["ok"]), int(res["total"]), verdict, pay]
	if score >= 0.999:
		job_index += 1
		text += "\n\nNächster Auftrag: %s" % _current_job()["title"]
	hud.show_result(text)
	_on_new_part()
	_refresh_hud()


# ------------------------------------------------------------ Speichern / Laden

func _apply_pending(d: Dictionary) -> void:
	save_name = str(d.get("name", "Werkstatt"))
	money = int(d.get("money", 0))
	job_index = int(d.get("job", 0))
	parts = int(d.get("parts", 0))
	play_time = float(d.get("play_time", 0.0))
	if d.has("lathe") and d["lathe"] is Dictionary:
		lathe.set_state(d["lathe"])
	else:
		var job := _current_job()
		lathe.new_workpiece(float(job["stock_d"]), float(job["stock_len"]))
	if d.has("player") and d["player"] is Dictionary:
		player.set_state(d["player"])
	_refresh_hud()


func save_game() -> bool:
	var data := {
		"name": save_name, "money": money, "job": job_index, "parts": parts, "play_time": play_time,
		"player": player.get_state(), "lathe": lathe.get_state(),
	}
	return SaveManager.write_slot(GameState.current_slot, data)


func restore_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if lathe.operating else Input.MOUSE_MODE_CAPTURED


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
