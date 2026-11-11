extends SceneTree
## Rendert den Hallenkran aus mehreren Blickwinkeln als PNG (Kontrolle des Modells models/hallenkran.glb).
## Aufruf: Godot --path . -s res://tools/render_crane.gd -- <ausgabeordner>

## Name -> [Brücke x, Katze z, Haken y, Kamera, Blickziel, Öffnungswinkel]
const VIEWS := {
	"halle": [-2.0, -1.5, 2.6, Vector3(7.5, 1.7, 5.5), Vector3(-2.0, 4.6, -1.0), 70.0],
	"bruecke": [-2.0, 2.0, 3.2, Vector3(2.5, 3.2, 6.5), Vector3(-2.0, 5.4, 1.0), 60.0],
	"katze": [-2.0, 2.0, 3.6, Vector3(-0.2, 4.3, 3.9), Vector3(-2.0, 5.25, 2.0), 50.0],
	"katze_west": [-2.0, 2.0, 3.6, Vector3(-3.9, 4.4, 3.6), Vector3(-2.0, 5.25, 2.0), 50.0],
	"kopftraeger": [-2.0, 2.0, 3.6, Vector3(0.6, 4.9, 4.6), Vector3(-2.0, 5.6, 7.3), 45.0],
	"haken": [-2.0, 2.0, 1.25, Vector3(-1.0, 1.55, 2.9), Vector3(-2.0, 1.5, 2.0), 45.0],
	"haken_seite": [-2.0, 2.0, 1.25, Vector3(-2.9, 1.6, 2.5), Vector3(-2.0, 1.5, 2.0), 45.0],
	"oben": [-2.0, 6.6, 4.6, Vector3(1.2, 4.6, 3.8), Vector3(-2.0, 5.3, 6.9), 55.0],
	"unten": [3.0, 0.0, 3.0, Vector3(3.6, 1.7, 1.2), Vector3(3.0, 5.4, 0.0), 75.0],
	"geparkt": [-2.0, -6.6, 3.6, Vector3(1.0, 4.2, -3.6), Vector3(-2.0, 5.3, -6.6), 50.0],
	"nordende": [-2.0, -6.6, 3.6, Vector3(-4.2, 4.6, -4.4), Vector3(-2.0, 5.5, -7.0), 45.0],
	"gehaenge": [-4.0, -3.0, 1.9, Vector3(-2.4, 1.6, -1.6), Vector3(-4.0, 1.5, -3.0), 55.0],
	"gehaenge_nah": [-4.0, -3.0, 1.9, Vector3(-3.3, 1.75, -2.2), Vector3(-4.0, 1.75, -3.0), 40.0],
}
const BIN_AT := Vector2(-4.0, -3.0)      # Spänebehälter für die Ansichten mit Kettengehänge


func _initialize() -> void:
	var out := "user://shots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	w.hud.visible = false
	w.day_started = true
	w.day_time = 0.5 * w.DAY_SECONDS
	w.day_cycle.shown = -1.0
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.current = true
	w.layout.bins.append({"size": "bin_l", "pos": BIN_AT, "rot": 0, "chips": ChipTray.new(60.0), "out": false})
	w._rebuild_stands()
	var bin: int = w.layout.bins.size() - 1
	for k in VIEWS:
		var v: Array = VIEWS[k]
		if k.begins_with("gehaenge") and w.crane.hooked < 0:
			# Behälter einhängen: Haken dicht über die Oberkante, dann anheben
			w.crane.bridge_x = BIN_AT.x
			w.crane.trolley_z = BIN_AT.y
			w.crane.hook_y = w.crane_bin_height(bin) + w.crane.SLING + 0.02
			w.crane.hook_click()
		w.crane.bridge_x = v[0]
		w.crane.trolley_z = v[1]
		w.crane.hook_y = v[2]
		cam.fov = v[5]
		cam.look_at_from_position(v[3], v[4])
		for i in 8:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("kran_%s.png" % k))
	quit()
