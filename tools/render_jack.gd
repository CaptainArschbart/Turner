extends SceneTree
## Rendert den Hubwagen im Spiel: Zinken in der Palette (3rd Person), Hände am Griff (Ego und 3rd Person).
## Aufruf: Godot --path . -s res://tools/render_jack.gd -- <ausgabeordner>


func shot(path: String) -> void:
	for i in 6:
		await physics_frame
		await process_frame
	root.get_texture().get_image().save_png(path)


func _initialize() -> void:
	var out := "user://shots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 250, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 8:
		await process_frame
	var p = w.player
	var ji := 0
	for i in w.layout.shelves.size():
		if str(w.layout.shelves[i]["size"]) == "pallet_jack":
			ji = i
	(w.shelf_nodes[ji] as Shelf).interact(p)
	var cart: JackCart = p.jack_cart
	var ppos := Vector2(21.0, -18.0)
	w.layout.shelves.append({"size": "pallet", "pos": ppos, "rot": 0, "stack": 1})
	w._rebuild_stands()
	cart.place(ppos - Vector2(Shelf.JACK_LOAD_X, 0) + Vector2(-0.35, 0), 0.0)
	var q := cart.hold_point(-cart.forward())
	p.global_position = Vector3(q.x, 0.05, q.y)
	p.yaw = -PI / 2.0
	p.pitch = -0.35
	p.rotation.y = p.yaw
	await shot(out.path_join("jack_ego.png"))
	p.third_person = true
	p._update_camera()
	await shot(out.path_join("jack_third_empty.png"))
	cart.place(ppos - Vector2(Shelf.JACK_LOAD_X, 0), 0.0)
	await physics_frame
	w.jack_lift()
	for i in 40:
		await physics_frame
	await shot(out.path_join("jack_third_loaded.png"))
	# Seitenansicht: Kamera frei
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.make_current()
	var c := Vector3(ppos.x, 0.5, ppos.y)
	cam.look_at_from_position(c + Vector3(-0.5, 0.6, 3.2), c + Vector3(-0.4, 0.2, 0))
	await shot(out.path_join("jack_side.png"))
	cam.look_at_from_position(c + Vector3(-3.2, 1.4, 1.4), c + Vector3(-0.6, 0.7, 0))
	await shot(out.path_join("jack_hands.png"))
	quit()
