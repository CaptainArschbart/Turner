extends Control
## Hauptmenü mit 3D-Vorschau der Drehmaschine im Hintergrund.

var _main_box: VBoxContainer
var _center: CenterContainer
var _slots_panel: PanelContainer
var _slot_list: SlotList
var _name_edit: LineEdit
var _slot_title: Label
var _settings: SettingsMenu
var _cam: Camera3D
var _cam_t := 0.0
var _demo_lathe: Lathe


func _ready() -> void:
	theme = UITheme.build()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_background()
	_build_ui()


func _build_background() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	svc.add_child(sv)

	var scene := Node3D.new()
	sv.add_child(scene)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.055, 0.065)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	Settings.apply_bloom(env)
	Settings.changed.connect(func(): Settings.apply_bloom(env))
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.09, 0.1)
	env.fog_density = 0.03
	we.environment = env
	scene.add_child(we)

	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	floor_mi.material_override = Build.mat(Color(0.32, 0.36, 0.35), 0.4)
	scene.add_child(floor_mi)

	_demo_lathe = Lathe.new()
	_demo_lathe.demo = true
	scene.add_child(_demo_lathe)

	var key := SpotLight3D.new()
	key.position = Vector3(1.2, 3.5, 2.5)
	key.spot_range = 8.0
	key.spot_angle = 40
	key.light_energy = 6.0
	key.shadow_enabled = true
	scene.add_child(key)
	key.look_at(Vector3(0.5, 1.0, 0))
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.5, 2.5, -1.5)
	rim.light_color = Color(1.0, 0.65, 0.35)
	rim.light_energy = 2.0
	rim.omni_range = 6
	scene.add_child(rim)

	_cam = Camera3D.new()
	_cam.fov = 50
	scene.add_child(_cam)
	_cam.make_current()
	_update_cam(0.0)

	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.02, 0.03, 0.95))
	grad.set_color(1, Color(0.02, 0.02, 0.03, 0.05))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.75, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


func _update_cam(t: float) -> void:
	var a := 0.55 + sin(t * 0.12) * 0.35
	var target := Vector3(0.35, 1.15, 0.0)
	_cam.position = target + Vector3(sin(a) * 2.6, 0.7 + sin(t * 0.2) * 0.15, cos(a) * 2.6)
	_cam.look_at(target)


func _process(delta: float) -> void:
	_cam_t += delta
	_update_cam(_cam_t)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	add_child(margin)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	margin.add_child(h)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 14)
	_main_box.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(_main_box)

	var t := UITheme.title("TURNER", 84)
	t.add_theme_color_override("font_color", UITheme.ACCENT)
	_main_box.add_child(t)
	var sub := UITheme.title("Drehmaschinen-Simulator  |  Weiler E50 HD", 22)
	sub.add_theme_color_override("font_color", UITheme.MUTED)
	_main_box.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 30
	_main_box.add_child(spacer)

	if SaveManager.any_save():
		_main_box.add_child(UITheme.button("Fortsetzen", func(): GameState.load_game(SaveManager.latest_slot())))
	_main_box.add_child(UITheme.button("Neues Spiel", func(): _show_slots("new")))
	_main_box.add_child(UITheme.button("Spiel laden", func(): _show_slots("load")))
	_main_box.add_child(UITheme.button("Einstellungen", _show_settings))
	_main_box.add_child(UITheme.button("Beenden", func(): get_tree().quit()))

	var ver := Label.new()
	ver.text = "v0.1  -  Godot %s" % Engine.get_version_info()["string"]
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	ver.add_theme_font_size_override("font_size", 14)
	_main_box.add_child(ver)

	_center = CenterContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_center)

	# Speicherplatz-Panel
	_slots_panel = PanelContainer.new()
	_slots_panel.visible = false
	_center.add_child(_slots_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_slots_panel.add_child(v)
	_slot_title = UITheme.title("Spiel laden")
	v.add_child(_slot_title)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name des Spielstands"
	_name_edit.text = "Meine Werkstatt"
	_name_edit.custom_minimum_size.y = 42
	v.add_child(_name_edit)
	_slot_list = SlotList.new()
	_slot_list.chosen.connect(_on_slot_chosen)
	v.add_child(_slot_list)
	v.add_child(UITheme.button("Zurück", _close_panels, 180))

	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.closed.connect(_close_panels)
	_center.add_child(_settings)


func _show_slots(mode: String) -> void:
	_settings.visible = false
	_slot_list.mode = mode
	_slot_list.refresh()
	_slot_title.text = "Neues Spiel - Speicherplatz wählen" if mode == "new" else "Spiel laden"
	_name_edit.visible = mode == "new"
	_slots_panel.visible = true


func _show_settings() -> void:
	_slots_panel.visible = false
	_settings.open()


func _close_panels() -> void:
	_slots_panel.visible = false
	_settings.visible = false


func _on_slot_chosen(slot: int) -> void:
	if _slot_list.mode == "new":
		var n := _name_edit.text.strip_edges()
		GameState.new_game(slot, n if n != "" else "Werkstatt %d" % (slot + 1))
	else:
		GameState.load_game(slot)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _slots_panel.visible:
		_close_panels()
		get_viewport().set_input_as_handled()
