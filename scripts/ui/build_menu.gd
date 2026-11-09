class_name BuildMenu
extends CanvasLayer
## Baumodus auf der Taste B: Man läuft frei herum. Anvisieren und E nimmt, was schon steht, die Zifferntasten
## nehmen Gekauftes aus der Liste. Mit dem Teil in der Hand folgt die Vorschau dem Blick: Linksklick stellt
## ab, R dreht, Rechtsklick oder Esc legt es zurück. B beendet den Baumodus.

const SNAP := 0.25
const REACH := 15.0
const GOOD := Color(0.2, 0.9, 0.3, 0.45)
const BAD := Color(0.95, 0.2, 0.15, 0.45)
const MARK := Color(0.95, 0.8, 0.1, 0.4)

## Spielwelt: player, layout, site, inventory, place_*, machine_busy, build_target(collider), build_node(target)
var world: Node
var active := false          # Baumodus läuft
var placing := false         # etwas ist in der Hand
var kind := ""               # "machine", "bench", "crate", "bin", "shelf" oder "rack"
var item := ""               # Maschinen-id, bei Werkbänken die Maschine beim Umstellen, sonst leer,
                             # bei Kisten und Behältern die Größe
var move_index := -1         # umgestellte Kiste, Behälter oder umgestelltes Regal, sonst -1
var big := false             # große Werkbank
var ghost_pos := Vector2.ZERO
var ghost_rot := 0
var error := ""
var target: Dictionary = {}  # worauf gerade geschaut wird
var stock_keys: Array = []   # Liste Nicht aufgestellt, Zifferntaste 1 = Eintrag 0
var _panel: PanelContainer
var _list: VBoxContainer
var _hint: Label
var _ghost_area: MeshInstance3D
var _ghost_foot: MeshInstance3D
var _mark: MeshInstance3D
var _held_node: Node3D = null


func _ready() -> void:
	layer = 14
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.position = Vector2(20, 20)
	_panel.custom_minimum_size.x = 340
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	var t := UITheme.title("Baumodus", 24)
	v.add_child(t)
	v.add_child(UITheme.key_hint("%s  ·  beenden" % Settings.binding_text("build_menu")))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	v.add_child(_list)
	_hint = Label.new()
	_hint.anchor_left = 0
	_hint.anchor_right = 1
	_hint.anchor_top = 1
	_hint.anchor_bottom = 1
	_hint.offset_top = -120
	_hint.offset_bottom = -70
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	root.add_child(_hint)


## Läuft der Baumodus, ohne dass etwas in der Hand ist?
func menu_open() -> bool:
	return active and not placing


func open_menu() -> void:
	if active or world.player.operating != null:
		return
	active = true
	world.player.set_build_mode(true)
	_panel.visible = true
	_hint.visible = true
	_refresh_list()


func close_menu() -> void:
	if not active:
		return
	cancel()
	active = false
	world.player.set_build_mode(false)
	_panel.visible = false
	_hint.visible = false
	_free_mark()


## Liste Nicht aufgestellt neu aufbauen.
func _refresh_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.free()
	stock_keys.clear()
	_list.add_child(UITheme.section("Nicht aufgestellt"))
	for id in world.inventory:
		var n := int(world.inventory[id])
		if n <= 0:
			continue
		stock_keys.append(id)
		_line("[%d]  %d x %s" % [stock_keys.size(), n, world.equipment_title(id)], UITheme.TEXT)
	if stock_keys.is_empty():
		_line("Nichts. Gekauft wird am PC im Shop.", UITheme.MUTED)


func _line(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", col)
	_list.add_child(l)


## Gekauftes aus der Liste in die Hand nehmen.
func take_from_stock(n: int) -> void:
	if n < 0 or n >= stock_keys.size():
		return
	var id := str(stock_keys[n])
	if id == "bench" or id == "bench_big":
		start("bench", "", -1, id == "bench_big")
	elif Crate.SIZES.has(id):
		start("crate", id)
	elif ChipBin.SIZES.has(id):
		start("bin", id)
	elif Shelf.SIZES.has(id):
		start("shelf", id)
	elif id == "rack":
		start("rack", "rack")
	else:
		start("machine", id)


## Das Anvisierte in die Hand nehmen. Gibt true zurück, wenn es geklappt hat.
func take_target() -> bool:
	if target.is_empty():
		return false
	start(str(target["kind"]), str(target["item"]), int(target.get("index", -1)))
	return placing


## Aufstellen beginnen. Beim Umstellen startet die Vorschau mit der bisherigen Drehung.
func start(what: String, id: String, moving := -1, big_bench := false) -> void:
	if what == "machine" and world.machine_busy(id):
		world.hud.show_message("Erst die Spindel stoppen, dann umstellen.", Color(1, 0.75, 0.2))
		return
	if what == "bench" and id != "" and world.layout.crates_of(id) > 0:
		world.hud.show_message("Erst die Kisten neben dieser Werkbank umstellen.", Color(1, 0.75, 0.2))
		return
	if what == "bin" and moving >= 0 and world.layout.bins[moving].has("machine"):
		world.hud.show_message(world.MACHINE_BIN_FIXED, Color(1, 0.75, 0.2))
		return
	if what == "bin" and moving >= 0 and world.layout.bins[moving]["out"]:
		world.hud.show_message("Erst den Behälter abstellen.", Color(1, 0.75, 0.2))
		return
	if not active:
		open_menu()
	cancel()
	kind = what
	item = id
	move_index = moving
	big = big_bench
	if what == "bench" and id != "":
		big = bool(world.layout.benches[id].get("big", false))
	ghost_rot = 2 if what == "bench" else 0
	if what == "machine" and world.layout.machines.has(id):
		ghost_rot = world.layout.machines[id]["rot"]
	elif what == "bench" and world.layout.benches.has(id):
		ghost_rot = world.layout.benches[id]["rot"]
	elif what == "crate" and moving >= 0:
		ghost_rot = world.layout.crates[moving]["rot"]
	elif what == "bin" and moving >= 0:
		ghost_rot = world.layout.bins[moving]["rot"]
	elif what == "shelf" and moving >= 0:
		ghost_rot = world.layout.shelves[moving]["rot"]
	placing = true
	target = {}
	_free_mark()
	_make_ghost()
	# Genommen: Das Teil selbst verschwindet, solange die Vorschau läuft
	_held_node = world.build_node(what, id, moving)
	if _held_node:
		_held_node.visible = false
	_update_ghost()


## Teil aus der Hand zurücklegen. Der Baumodus läuft weiter.
func cancel() -> void:
	if not placing:
		return
	placing = false
	_restore_held()
	_free_ghost()


func _restore_held() -> void:
	if is_instance_valid(_held_node):
		_held_node.visible = true
	_held_node = null


## Platz bestätigen. Bleibt bei einem Fehler in der Vorschau.
func confirm() -> bool:
	var err: String
	match kind:
		"machine":
			err = world.place_machine(item, ghost_pos, ghost_rot)
		"crate":
			err = world.place_crate(move_index, item, ghost_pos, ghost_rot)
		"bin":
			err = world.place_bin(move_index, item, ghost_pos, ghost_rot)
		"shelf":
			err = world.place_shelf(move_index, item, ghost_pos, ghost_rot)
		"rack":
			err = world.place_rack(move_index, ghost_pos)
		_:
			err = world.place_bench(item, ghost_pos, ghost_rot, big)
	if err != "":
		world.hud.show_message(err, Color(1, 0.45, 0.35))
		return false
	cancel()
	_refresh_list()
	return true


func _make_ghost() -> void:
	_free_ghost()
	_ghost_area = _ghost_mesh()
	_ghost_foot = _ghost_mesh()


func _ghost_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	world.add_child(mi)
	return mi


func _free_ghost() -> void:
	for g in [_ghost_area, _ghost_foot]:
		if g:
			g.queue_free()
	_ghost_area = null
	_ghost_foot = null


func _free_mark() -> void:
	if _mark:
		_mark.queue_free()
	_mark = null


## Punkt auf dem Boden, auf den die Spielfigur schaut.
func _aim_point() -> Vector2:
	var cam: Camera3D = world.player.cam
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var dist := REACH
	if d.y < -0.02:
		dist = minf(-o.y / d.y, REACH)
	var p := o + d * dist
	return Vector2(snappedf(p.x, SNAP), snappedf(p.z, SNAP))


func _update_ghost() -> void:
	var area: Rect2
	var foot: Rect2
	var h := 1.2
	var what: String
	match kind:
		"machine":
			error = world.layout.check_machine(item, ghost_pos, ghost_rot)
			var spec: Dictionary = Layout.SPECS[item]
			area = Layout.rect_at(spec["area"], ghost_pos, ghost_rot)
			foot = Layout.rect_at(spec["foot"], ghost_pos, ghost_rot)
			what = str(spec["title"])
		"crate":
			error = world.layout.check_crate(item, ghost_pos, ghost_rot, move_index)
			area = Layout.crate_rect(item, ghost_pos, ghost_rot)
			foot = area
			h = float(Crate.SIZES[item]["h"]) * 0.001 + 0.06
			what = world.equipment_title(item)
		"bin":
			error = world.layout.check_bin(ghost_pos, ghost_rot, move_index, item)
			area = Layout.bin_rect(ghost_pos, ghost_rot, item)
			foot = area
			h = ChipBin.height(item)
			what = world.equipment_title(item)
		"shelf":
			error = world.layout.check_shelf(item, ghost_pos, ghost_rot, move_index)
			area = Layout.shelf_rect(item, ghost_pos, ghost_rot)
			foot = area
			h = float(Shelf.SIZES[item]["height"])
			what = world.equipment_title(item)
		"rack":
			var cell: Vector2i = world.site.l_cell_at(ghost_pos)
			error = world.site.rack_error(cell, move_index)
			area = world.site.rack_rect(cell)
			foot = area
			h = 3.6
			what = "Lagerregal"
		_:
			error = world.layout.check_bench(ghost_pos, ghost_rot, item, big)
			area = Layout.bench_rect(ghost_pos, ghost_rot, big)
			foot = area
			h = 0.92
			what = "Große Werkbank" if big else "Werkbank"
	if error == "" and foot.has_point(_player_xz()):
		error = "Du stehst im Weg."
	_show_box(_ghost_area, area, 0.03)
	_show_box(_ghost_foot, foot, h)
	var col := GOOD if error == "" else BAD
	(_ghost_area.material_override as StandardMaterial3D).albedo_color = col
	(_ghost_foot.material_override as StandardMaterial3D).albedo_color = col
	var keys := "Linksklick abstellen   |   Rechtsklick oder Esc zurücklegen"
	if kind != "rack":
		keys = "Linksklick abstellen   |   R drehen   |   Rechtsklick oder Esc zurücklegen"
	_hint.text = "%s: %s\n%s" % [what, "Platz ist frei" if error == "" else error, keys]
	_hint.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7) if error == "" else Color(1.0, 0.6, 0.5))


func _player_xz() -> Vector2:
	return Vector2(world.player.global_position.x, world.player.global_position.z)


func _show_box(mi: MeshInstance3D, r: Rect2, h: float) -> void:
	(mi.mesh as BoxMesh).size = Vector3(r.size.x, h, r.size.y)
	mi.position = Vector3(r.get_center().x, h * 0.5 + 0.01, r.get_center().y)


## Worauf schaut die Spielfigur? Markiert es und nennt die Tasten.
func _update_target() -> void:
	target = world.build_target(world.player.ray.get_collider() if world.player.ray.is_colliding() else null)
	var keys := "E nimmt, was du anschaust   |   1-9 aus der Liste   |   B beenden"
	if target.is_empty():
		_hint.text = "Auf etwas schauen, das steht\n" + keys
		_hint.add_theme_color_override("font_color", UITheme.TEXT)
		_free_mark()
		return
	var line := "%s: E nehmen" % str(target["title"])
	if target["kind"] == "bench":
		line += "   |   X abbauen"
	_hint.text = "%s\n1-9 aus der Liste   |   B beenden" % line
	_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	if _mark == null:
		_mark = _ghost_mesh()
		(_mark.material_override as StandardMaterial3D).albedo_color = MARK
	_show_box(_mark, target["rect"], 0.04)


func _process(_delta: float) -> void:
	if not active:
		return
	# Spielfigur hat doch eine Maschine übernommen: Baumodus beenden
	if world.player.operating != null:
		close_menu()
		return
	if not placing:
		_update_target()
		return
	ghost_pos = _aim_point()
	if kind == "rack":
		ghost_pos = world.site.rack_center(world.site.l_cell_at(ghost_pos))
	_update_ghost()


func _input(event: InputEvent) -> void:
	if placing:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				get_viewport().set_input_as_handled()
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					confirm()
				else:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				get_viewport().set_input_as_handled()
				cancel()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
			get_viewport().set_input_as_handled()
			ghost_rot = posmod(ghost_rot + 1, 4)
		elif event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			cancel()
		elif event.is_action_pressed("build_menu"):
			get_viewport().set_input_as_handled()
			close_menu()
		elif event.is_action_pressed("interact") or event.is_action_pressed("job_menu"):
			get_viewport().set_input_as_handled()
		return
	if active:
		if event.is_action_pressed("build_menu") or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			close_menu()
		elif event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
			take_target()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_X and not target.is_empty() and target["kind"] == "bench":
				get_viewport().set_input_as_handled()
				var err: String = world.take_down_bench(str(target["item"]))
				if err != "":
					world.hud.show_message(err, Color(1, 0.45, 0.35))
				target = {}
				_refresh_list()
			elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
				get_viewport().set_input_as_handled()
				take_from_stock(event.keycode - KEY_1)
		return
	if event.is_action_pressed("build_menu") and world.player.operating == null and not world.get_tree().paused:
		get_viewport().set_input_as_handled()
		open_menu()
