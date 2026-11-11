class_name DebugMenu
extends CanvasLayer
## Debug-Menü auf der Taste ^: Testmodus (alles gratis), Noclip, Uhrzeit und Zeitraffer, Geld, Ansehen und
## Skillpunkte, Sprung an feste Orte, HUD und Bildrate. Alles wirkt sofort; Geld und Fortschritt landen im
## Spielstand, Testmodus, Noclip und Zeitraffer nicht.

## Spielwelt: player, company, money, free_mode, set_free_mode(on), time_scale, debug_set_hour(h), next_day(),
## day_started, start_day(), clock_text(), hud
var world: Node
var _status: Label
var _toggles := {}                # Name -> Button, zeigen ihren Zustand
var _pitch := 0.0
var _fps: Label
var _look_label: Label
var _look := {}                   # beim Öffnen angeschautes Objekt, siehe world.debug_target
var _look_msg := ""
var _look_from := Vector3.ZERO    # Blickstrahl beim Öffnen, damit nach dem Entfernen neu gezielt werden kann
var _look_to := Vector3.ZERO
var _look_mask := 0

## Sprungziele: Name -> Position der Spielfigur, Blickrichtung (Yaw)
const PLACES := {
	"Halle": [Vector3(0.0, 0.1, 4.5), PI],
	"Meisterbüro": [Vector3(8.0, 0.1, 9.6), PI],
	"QM-Raum": [Vector3(2.2, 0.1, 9.4), PI],
	"Lager": [Vector3(18.0, 0.1, -10.0), 0.0],
	"Hof": [Vector3(22.0, 0.1, 6.0), PI / 2.0],
	"Straße": [Vector3(23.0, 0.1, 21.0), PI],
}


func _ready() -> void:
	layer = 30
	visible = false
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(UITheme.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.window_style())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(1060, 0)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(UITheme.window_head("Debug", "Entwickler")["box"])
	var close_btn := UITheme.button("Schließen", close, 170)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(close_btn)
	_status = UITheme.note("", 15)
	v.add_child(_status)
	v.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	v.add_child(cols)

	var game := _column(cols, "Spiel")
	_toggle(game, "free", "Testmodus (alles gratis)", func(): world.set_free_mode(not world.free_mode))
	_toggle(game, "noclip", "Noclip (fliegen)", func(): world.player.noclip = not world.player.noclip)
	_toggle(game, "hud", "HUD ausblenden", func(): world.hud.visible = not world.hud.visible)
	_toggle(game, "fps", "Bildrate anzeigen", func(): _fps.visible = not _fps.visible)

	var time := _column(cols, "Zeit")
	var hours := GridContainer.new()
	hours.columns = 3
	hours.add_theme_constant_override("h_separation", 6)
	hours.add_theme_constant_override("v_separation", 6)
	time.add_child(hours)
	for h in [6, 9, 12, 15, 18, 20, 22, 0, 4]:
		hours.add_child(UITheme.small_button("%02d:00" % h, func(): _set_hour(float(h)), 74))
	time.add_child(UITheme.small_button("+1 Stunde", func(): _set_hour(fposmod(world.sky_hour() + 1.0, 24.0)), 234))
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 6)
	time.add_child(speeds)
	for s in [1, 10, 30, 0]:
		var b := UITheme.small_button("Pause" if s == 0 else "×%d" % s, func(): world.time_scale = float(s), 54)
		speeds.add_child(b)
	time.add_child(UITheme.small_button("Nächster Tag", func(): world.next_day(), 234))

	var progress := _column(cols, "Geld und Fortschritt")
	var cash := GridContainer.new()
	cash.columns = 2
	cash.add_theme_constant_override("h_separation", 6)
	cash.add_theme_constant_override("v_separation", 6)
	progress.add_child(cash)
	for a in [100, 1000, 10000, 100000]:
		cash.add_child(UITheme.small_button("+%d EUR" % a, func(): _set_money(int(world.company.balance) + a), 114))
	cash.add_child(UITheme.small_button("Geld auf 0", func(): _set_money(0), 114))
	cash.add_child(UITheme.small_button("Startgeld (250)", func(): _set_money(250), 114))
	var rep := HBoxContainer.new()
	rep.add_theme_constant_override("separation", 6)
	progress.add_child(rep)
	rep.add_child(UITheme.small_button("Ansehen +10", func(): _reputation(10.0), 114))
	rep.add_child(UITheme.small_button("Ansehen −10", func(): _reputation(-10.0), 114))
	progress.add_child(UITheme.small_button("+1 Skillpunkt", _skill_point, 234))

	var places := _column(cols, "Springen nach")
	for p in PLACES:
		places.add_child(UITheme.small_button(p, func(): _teleport(p), 200))
	places.add_child(UITheme.section("Angeschaut"))
	_look_label = UITheme.note("", 14)
	_look_label.custom_minimum_size = Vector2(200, 0)
	_look_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	places.add_child(_look_label)
	places.add_child(UITheme.small_button("Entfernen", _remove_looked, 200))

	v.add_child(UITheme.key_hint("^ / Esc  ·  schließen          Noclip: Bewegen wie gewohnt, Springen hoch, Ducken runter, Rennen schneller"))

	# Bildrate oben rechts, unabhängig vom offenen Menü
	_fps = Label.new()
	_fps.visible = false
	_fps.add_theme_font_size_override("font_size", 16)
	_fps.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_fps.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps.position = Vector2(-120, 8)
	var fps_layer := CanvasLayer.new()
	fps_layer.layer = 31
	add_child(fps_layer)
	fps_layer.add_child(_fps)


func _column(parent: Control, title: String) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 8)
	parent.add_child(c)
	c.add_child(UITheme.section(title))
	return c


func _toggle(parent: Control, key: String, text: String, cb: Callable) -> void:
	var b := UITheme.small_button(text, cb, 250)
	b.toggle_mode = true
	b.set_meta("text", text)
	parent.add_child(b)
	_toggles[key] = b


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible or world.player.operating != null:
		return
	visible = true
	_pitch = world.player.pitch
	var ray: RayCast3D = world.player.ray
	_look_from = ray.global_position
	_look_to = ray.to_global(ray.target_position)
	_look_mask = ray.collision_mask
	_look = world.debug_target(ray.get_collider() if ray.is_colliding() else null)
	_look_msg = ""
	world.player.start_operating(self, world.player.global_position, world.player.yaw)
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	world.player.stop_operating()
	world.player.pitch = _pitch


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func _process(_delta: float) -> void:
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if visible:
		_refresh()


func _refresh() -> void:
	var states := {"free": world.free_mode, "noclip": world.player.noclip, "hud": not world.hud.visible, "fps": _fps.visible}
	for k in _toggles:
		var b: Button = _toggles[k]
		b.set_pressed_no_signal(states[k])
		b.text = "%s: %s" % [b.get_meta("text"), "an" if states[k] else "aus"]
	var speed := "Pause" if world.time_scale == 0.0 else "×%d" % int(world.time_scale)
	_status.text = "%s    ·    Zeitraffer %s    ·    Kasse %d EUR    ·    Ansehen %d    ·    Skillpunkte frei %d" % [
		world.clock_text(), speed, int(world.company.balance), int(world.company.reputation), world.company.skills.free_points()]
	var now := str(_look["title"]) if not _look.is_empty() else "nichts im Blick"
	_look_label.text = now if _look_msg == "" else "%s
Jetzt: %s" % [_look_msg, now]


## Das beim Öffnen angeschaute Objekt endgültig entfernen (nicht zurück ins Lager).
func _remove_looked() -> void:
	var err: String = world.debug_remove(_look)
	if err != "":
		_look_msg = err
		return
	_look_msg = "%s entfernt." % _look["title"]
	_look = {}
	# Gelöschte Körper verschwinden erst im nächsten Physikschritt: danach mit demselben Strahl neu zielen
	await get_tree().physics_frame
	await get_tree().physics_frame
	if visible and _look.is_empty():
		_look = look_again()


## Mit dem beim Öffnen gemerkten Blickstrahl erneut abfragen, was jetzt dort steht.
func look_again() -> Dictionary:
	var space: PhysicsDirectSpaceState3D = (world.player as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_look_from, _look_to, _look_mask, [(world.player as CollisionObject3D).get_rid()])
	q.collide_with_areas = world.player.ray.collide_with_areas
	var hit: Dictionary = space.intersect_ray(q)
	return world.debug_target(hit.get("collider") if not hit.is_empty() else null)


func _set_hour(h: float) -> void:
	world.debug_set_hour(h)


## Kasse direkt setzen: Debug-Geld zählt nicht als Einnahme oder Ausgabe im Tagesbericht.
func _set_money(v: int) -> void:
	world.company.balance = maxi(v, 0)
	world.office_pc.overlay.refresh_all()


func _reputation(d: float) -> void:
	world.company.change_reputation(d, int(world.day), "Debug")


func _skill_point() -> void:
	var sk = world.company.skills
	var before: int = sk.free_points()
	while sk.free_points() == before:
		sk.xp += 1
	world.office_pc.overlay.refresh_all()


func _teleport(place: String) -> void:
	var p: Array = PLACES[place]
	close()
	world.player.global_position = p[0]
	world.player.velocity = Vector3.ZERO
	world.player.yaw = float(p[1])
	world.player.pitch = 0.0
