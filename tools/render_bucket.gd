extends SceneTree
## Rendert den Eimer: abgestellt mit Spänen, in der Hand (Ego und 3rd Person).
## Aufruf: Godot --path . -s res://tools/render_bucket.gd -- <ausgabeordner>


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
	var bi := 0
	for i in w.layout.shelves.size():
		if str(w.layout.shelves[i]["size"]) == "bucket":
			bi = i
	var at: Vector2 = w.layout.shelves[bi]["pos"]
	(w.layout.shelves[bi]["chips"] as ChipTray).add("baustahl", 6.0)
	w._rebuild_stands()
	p.global_position = Vector3(at.x - 1.6, 0.05, at.y + 0.2)
	p.yaw = -PI / 2.0
	p.rotation.y = p.yaw
	p.pitch = -0.25
	await shot(out.path_join("bucket_standing.png"))
	(w.shelf_nodes[bi] as Shelf).interact(p)
	await shot(out.path_join("bucket_ego.png"))
	p.third_person = true
	p._update_camera()
	await shot(out.path_join("bucket_third.png"))
	quit()
