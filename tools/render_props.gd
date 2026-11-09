extends SceneTree
## Rendert die Teile aus models/non_machine_parts.glb einzeln als PNG und gibt ihre Maße aus.
## Aufruf: Godot --path . -s res://tools/render_props.gd -- <ausgabeordner>


func _initialize() -> void:
	var out := "user://shots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(900, 900)
	var scene := Node3D.new()
	root.add_child(scene)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.58, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.77, 0.8)
	env.ambient_light_energy = 0.7
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40
	scene.add_child(cam)
	cam.current = true
	await process_frame
	for key in Props.PARTS:
		var n := Props.make(key)
		scene.add_child(n)
		var box := Props.bounds(n)
		print(key, "  size=", box.size, "  pos=", box.position)
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mi.mesh
			for s in m.get_surface_count():
				var mat = mi.get_active_material(s)
				print("   ", mi.name, " ", s, " ", mat.resource_name if mat else "-", " ", mat.albedo_color if mat is BaseMaterial3D else "", " tex=", mat.albedo_texture != null if mat is BaseMaterial3D else "")
		var c := box.get_center()
		var r := box.size.length()
		for view in [["iso", Vector3(0.7, 0.5, 1.0)], ["front", Vector3(0, 0.25, 1.0)]]:
			cam.look_at_from_position(c + (view[1] as Vector3).normalized() * r * 1.4, c)
			for i in 4:
				await process_frame
			root.get_texture().get_image().save_png(out.path_join(key + "_" + view[0] + ".png"))
		n.queue_free()
		await process_frame
	quit()
