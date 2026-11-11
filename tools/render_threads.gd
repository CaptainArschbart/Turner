extends SceneTree
## Rendert ein Drehteil mit Bohrung, Innen- und Außengewinde als PNG (Design-Kontrolle des
## Werkstück-Meshes). Aufruf: Godot --path . -s res://tools/render_threads.gd -- <ausgabeordner>


func _initialize() -> void:
	var out := "user://shots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1400, 800)
	var scene := Node3D.new()
	root.add_child(scene)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.58, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.77, 0.8)
	env.ambient_light_energy = 0.6
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.9, 0)
	sun.light_energy = 1.2
	scene.add_child(sun)
	var lathe = load("res://scripts/machine/lathe.gd").new()
	lathe.demo = true
	lathe.visible = false
	scene.add_child(lathe)
	for i in 3:
		await process_frame
	lathe.new_workpiece(40.0, 80.0)
	var seg: float = lathe.SEG
	for i in lathe.profile.size():
		var z: float = (i + 0.5) * seg
		if z > 45.0:
			lathe.profile[i] = 12.0                 # Zapfen Ø24
			lathe.machined[i] = 1
			lathe.rz[i] = 3.0
		if z > 50.0 and z < 78.0:
			lathe.thr[i] = 0.92                     # M24 x 1,5 außen
			lathe.thr_p[i] = 1.5
		if z > 30.0:
			lathe.bore[i] = 7.0 if z > 60.0 else maxf(0.0, minf(5.0, (z - 30.0) * 1.66))
			lathe.rz_in[i] = 6.0
		if z > 65.0:
			lathe.thr_in[i] = 0.81                  # M16 x 1,5 innen (Kern Ø14)
			lathe.thr_in_p[i] = 1.5
	var mi := MeshInstance3D.new()
	mi.mesh = lathe._make_mesh(0, lathe.profile.size() - 1, true)
	mi.material_override = lathe._wp_mat
	scene.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 35
	scene.add_child(cam)
	cam.current = true
	var shots := {
		"threads_side": [Vector3(0.05, 0.03, 0.16), Vector3(0.05, 0.0, 0.0)],
		"threads_end": [Vector3(0.16, 0.035, 0.06), Vector3(0.07, 0.0, 0.0)],
	}
	for k in shots:
		cam.look_at_from_position(shots[k][0], shots[k][1])
		for i in 4:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png(out.path_join("%s.png" % k))
		print("saved ", out.path_join("%s.png" % k))
	quit()
