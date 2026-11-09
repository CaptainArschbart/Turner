extends SceneTree
## Rendert Halle, Büro und Hof zu mehreren Uhrzeiten als PNG (Kontrolle von Tag/Nacht und Oberflächen).
## Aufruf: Godot --path . -s res://tools/render_hall.gd -- <ausgabeordner>

const VIEWS := {
	"hall": [Vector3(-9.0, 2.2, 6.0), Vector3(4.0, 1.5, -4.0)],
	"wall": [Vector3(2.0, 1.7, 3.0), Vector3(-2.0, 1.8, 8.0)],
	"office": [Vector3(6.2, 1.7, 9.0), Vector3(9.3, 0.8, 11.8)],
	"yard": [Vector3(20.0, 2.0, -2.0), Vector3(8.0, 3.0, 4.0)],
	"sky": [Vector3(20.0, 1.7, 3.0), Vector3(40.0, 6.0, 10.0)],
	"gate": [Vector3(23.0, 1.7, 4.0), Vector3(23.0, 1.2, 12.0)],
	"market": [Vector3(1996.0, 1.7, 5.0), Vector3(2003.0, 1.0, 2.5)],
	"home": [Vector3(-2001.0, 1.7, 2.6), Vector3(-2002.2, 0.5, -1.6)],
}
## Name -> [day_started, day_over, Anteil des Tages bzw. s nach Feierabend]
const TIMES := {
	"0645": [false, false, 0.0],
	"1200": [true, false, 0.5],
	"1900": [true, true, 96.0],
	"2200": [true, true, 300.0],
}


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
	var cam := Camera3D.new()
	cam.fov = 70
	w.add_child(cam)
	cam.current = true
	for t in TIMES:
		var v: Array = TIMES[t]
		w.day_started = v[0]
		w.day_over = v[1]
		if v[1]:
			w._evening = v[2]
		else:
			w.day_time = float(v[2]) * w.DAY_SECONDS
		w.day_cycle.shown = -1.0
		for k in VIEWS:
			var s: Array = VIEWS[k]
			cam.look_at_from_position(s[0], s[1])
			for i in 6:
				await process_frame
			root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [k, t]))
	quit()
