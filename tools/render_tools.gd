extends SceneTree
## Rendert jeden Drehmeißel im Schnitt von oben und schräg als PNG: Kontrolle, ob die sichtbare Platte
## genau die Kontur hinterlässt, die sie im Werkstück abträgt.
## Aufruf: Godot --path . -s res://tools/render_tools.gd -- <ausgabeordner> [e50]

## Werkzeug -> Schnitte [z, x] (mm, x = Radius der Schneide), die letzte Stellung wird gezeigt
const CUTS := {
	"T1": [[150.0, 27.0], [140.0, 27.0], [130.0, 27.0], [124.0, 27.0]],
	"T2": [[60.0, 27.0], [70.0, 27.0], [80.0, 27.0], [86.0, 27.0]],
	"T3": [[150.0, 29.0], [140.0, 29.0], [132.0, 29.0], [128.0, 25.0], [124.0, 22.0]],
	"T4": [[150.0, 29.0], [140.0, 29.0], [134.0, 25.0], [130.0, 21.0]],
	"T5": [[160.0, 24.0]],
	"T6": [[120.0, 20.0]],
	"T7": [[120.0, 26.0]],
}


func _initialize() -> void:
	var out := "user://shots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var e50 := args.size() > 1 and args[1] == "e50"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var scene := Node3D.new()
	root.add_child(scene)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.58, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.85)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.1, 0.6, 0)
	sun.light_energy = 1.0
	scene.add_child(sun)
	var lathe = load("res://scripts/machine/lathe.gd").new()
	lathe.conventional = not e50
	scene.add_child(lathe)
	var cam := Camera3D.new()
	cam.cull_mask = 1                      # ohne Dach und Tür der E50
	scene.add_child(cam)
	cam.current = true
	for i in 10:
		await process_frame
	if lathe.has_method("power_on"):
		lathe.power_on(true)
	var tools = load("res://scripts/machine/lathe_tools.gd")
	for id in CUTS:
		lathe.holder = [id, "", "", ""]
		lathe.active_slot = 0
		lathe._apply_holder()
		lathe.new_workpiece(60.0, 160.0)
		lathe.spindle_on = true
		lathe.spindle_speed = 800.0
		var last: Array = []
		for c in CUTS[id]:
			lathe._cut(float(c[0]), float(c[1]), 2.0)
			last = c
		lathe.tool_z = float(last[0])
		lathe.tool_x = float(last[1])
		lathe._sync_slides()
		lathe._dirty = true
		lathe.spindle_on = false
		lathe.spindle_speed = 0.0
		for i in 6:
			await process_frame
		var tip: Vector3 = lathe.to_global(Vector3((lathe.tool_z - lathe.clamp_depth) * 0.001, lathe.AXIS_H, lathe.tool_x * 0.001))
		var suffix := "_e50" if e50 else ""
		# Von oben, senkrecht und ohne Perspektive. Die Kamera schneidet alles weg, was mehr als 3 mm über
		# der Schneidenebene liegt (Kühlmittelschlauch, obere Hälfte des Werkstücks).
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.085
		cam.near = 0.297
		cam.look_at_from_position(tip + Vector3(0, 0.3, 0.012), tip + Vector3(0, 0, 0.012), Vector3(0, 0, -1))
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("%s_oben%s.png" % [id, suffix]))
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.near = 0.01
		cam.fov = 22.0
		cam.look_at_from_position(tip + Vector3(0.16, 0.14, 0.22), tip + Vector3(0, -0.005, 0.01))
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("%s_schraeg%s.png" % [id, suffix]))
		print("BILD ", id, " ", tools.get_tool(tools.index_of(id))["name"])
	quit()
