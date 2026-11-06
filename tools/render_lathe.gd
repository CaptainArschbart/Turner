extends SceneTree
## Rendert die Drehmaschine aus mehreren Blickwinkeln als PNG (Design-Kontrolle).
## Aufruf: Godot --path . -s res://tools/render_lathe.gd -- <ausgabeordner>

const SHOTS := {
	"front": [Vector3(0.7, 1.6, 4.2), Vector3(0.6, 1.1, 0)],
	"left": [Vector3(-2.2, 1.8, 2.6), Vector3(0.2, 1.1, 0)],
	"right": [Vector3(3.6, 1.8, 2.4), Vector3(0.8, 1.1, 0)],
	"carriage": [Vector3(0.6, 1.5, 1.3), Vector3(0.1, 1.0, 0.2)],
	"head": [Vector3(-0.2, 1.5, 1.4), Vector3(-0.4, 1.2, 0.1)],
}


func _initialize() -> void:
	var out := "user://shots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	var scene := Node3D.new()
	root.add_child(scene)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.58, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.77, 0.8)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.37, 0.38)
	floor_mi.material_override = fm
	scene.add_child(floor_mi)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(12, 6, 10)
	probe.position = Vector3(0.6, 2.5, 1.5)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	scene.add_child(probe)
	var lathe = load("res://scripts/machine/lathe.gd").new()
	lathe.demo = true
	scene.add_child(lathe)
	var cam := Camera3D.new()
	cam.fov = 50
	scene.add_child(cam)
	cam.current = true
	for i in 10:
		await process_frame
	for k in SHOTS:
		var s: Array = SHOTS[k]
		cam.position = s[0]
		cam.look_at(s[1])
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join(k + ".png"))
	# Schutztür zu (Pult fährt mit) und die Seiten der Pult-Software
	lathe.set_door(true)
	for k in ["front", "head"]:
		var s: Array = SHOTS[k]
		cam.position = s[0]
		cam.look_at(s[1])
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join(k + "_closed.png"))
	lathe.demo = false
	lathe.new_workpiece(60.0, 160.0)
	lathe.spindle_on = false
	lathe.spindle_speed = 0.0
	var scr = lathe.screen
	scr.open_prog = "WELLE_AUFTRAG2"
	for pg in ["jog", "auto", "pm", "edit", "sim", "tools"]:
		scr.show_page(pg)
		if pg == "edit":
			scr._ed_list.select(2)
			scr._ed_plot_update()
		for i in 4:
			await process_frame
		lathe.screen_vp.get_texture().get_image().save_png(out.path_join("screen_" + pg + ".png"))
	scr._ed_list.select(1)
	scr._ed_change()
	for i in 4:
		await process_frame
	lathe.screen_vp.get_texture().get_image().save_png(out.path_join("screen_contour.png"))
	scr.show_page("edit")
	scr._ed_list.select(3)
	scr._ed_change()
	for i in 4:
		await process_frame
	lathe.screen_vp.get_texture().get_image().save_png(out.path_join("screen_form.png"))
	quit()
