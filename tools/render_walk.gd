extends SceneTree
## Design-Kontrolle: Figur seitlich in sechs Gehphasen (walk.png) und Nahaufnahme der Zigarette (cig.png).
## Aufruf mit Fenster: Godot --path . -s res://tools/render_walk.gd -- <Ausgabeordner>

var out := "user://shots/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0].path_join("")
	DirAccess.make_dir_recursive_absolute(out)
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.65)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment.ambient_light_energy = 0.6
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	root3.add_child(sun)
	var bodies: Array = []
	for i in 6:
		var b: Node3D = load("res://scripts/player/worker_body.gd").new()
		b.position = Vector3(i * 0.9, 0, 0)
		b.rotation.y = -PI / 2           # Blick nach +X, Seitenansicht
		root3.add_child(b)
		bodies.append(b)
	var cam := Camera3D.new()
	cam.position = Vector3(2.25, 0.95, 4.6)
	cam.fov = 50
	root3.add_child(cam)
	cam.current = true
	get_root().size = Vector2i(1600, 700)
	# Zigarette nah
	var cig = load("res://scripts/player/cigarette.gd").new()
	root3.add_child(cig)
	await process_frame
	cig._show(true)
	var c0: Node3D = cig._cigs[0]["root"]
	c0.global_transform = Transform3D(Basis(Vector3.UP, -PI / 2) * Basis(Vector3.RIGHT, 0.0), Vector3(20, 1, 0))
	cig._cigs[1]["root"].visible = false
	cig.left = 0.8
	for c in cig._cigs:
		var paper: Node3D = c["paper"]
		var tip: float = -cig.FILTER - cig.TOBACCO * cig.left
		paper.scale.y = cig.left
		paper.position.z = -cig.FILTER - cig.TOBACCO * cig.left * 0.5
		c["ash"].scale.y = 1.0
		c["ash"].position.z = tip - 0.002 - 0.003
		c["ember"].position.z = tip - 0.0012
		c["char"].position.z = tip + 0.0004
	# Phasen: die Figur läuft mit Gehtempo; jede Figur bekommt einen anderen Zeitversatz
	for frame in 90:
		for i in bodies.size():
			var dt := 1.0 / 60.0 + (i * 0.06 if frame == 0 else 0.0)
			bodies[i].pose(dt, 3.2, true, false, false, 0.0)
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "walk.png")
	var cam2 := Camera3D.new()
	cam2.position = Vector3(20 + 0.045, 1.04, 0.17)
	root3.add_child(cam2)
	cam2.look_at(Vector3(20 + 0.045, 1.0, 0))
	cam2.fov = 30
	cam2.current = true
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "cig.png")
	quit()
