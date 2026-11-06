class_name DrillPress
extends Mill
## Konventionelle Standbohrmaschine. Technik wie die Fräsmaschine: Kreuztisch in X und Y, Pinole in Z,
## Höhenkarte als Werkstück, Bedienfeld mit Drehknöpfen. Sie nimmt nur Spiralbohrer auf.

const BASE_Y := 0.09
const COLUMN_Z := -0.42
const RPM := [[100, 160, 250, 315, 400, 500, 630, 800], [200, 315, 500, 630, 800, 1000, 1250, 1600]]
const FEED := [[10, 16, 25, 32, 40, 50, 63, 80], [20, 32, 50, 63, 80, 100, 125, 160]]


func _init() -> void:
	MACHINE_ID = "drill"
	tool_family = "drill"
	panel_pos = Vector3(0.21, 1.3, COLUMN_Z)
	panel_stand = Vector3(1.0, 0.0, COLUMN_Z)


func _build_model() -> Dictionary:
	var green := Build.mat(Color(0.26, 0.42, 0.36), 0.5, 0.1)
	var light := Build.mat(Color(0.82, 0.84, 0.82), 0.5)
	var dark := Build.mat(Color(0.12, 0.13, 0.15), 0.55, 0.2)
	var black := Build.mat(Color(0.05, 0.05, 0.06), 0.6)
	var steel := Build.mat(Color(0.65, 0.67, 0.7), 0.3, 0.9)

	# Fuß mit Späneschale
	Build.box(self, Vector3(0.8, 0.09, 1.0), Vector3(0, BASE_Y * 0.5, -0.05), dark)
	Build.box(self, Vector3(0.7, 0.02, 0.7), Vector3(0, BASE_Y + 0.01, 0.05), Build.mat(Color(0.55, 0.12, 0.1), 0.5))
	# Säule und Tischträger
	Build.cyl(self, 0.07, 2.25, Vector3(0, 1.17, COLUMN_Z), steel, Build.AXIS_Y, false, 32)
	Build.box(self, Vector3(0.24, 0.16, 0.3), Vector3(0, 0.74, COLUMN_Z + 0.12), green)
	Build.box(self, Vector3(0.2, 0.1, 0.42), Vector3(0, 0.84, -0.12), green)

	# Kreuzschlitten (Y) und Tisch (X)
	var saddle_n := Node3D.new()
	saddle_n.position.y = MillModel.TABLE_Y
	add_child(saddle_n)
	Build.box(saddle_n, Vector3(0.3, 0.05, 0.26), Vector3(0, -0.055, 0), dark)
	var table_n := Node3D.new()
	saddle_n.add_child(table_n)
	Build.box(table_n, Vector3(0.5, 0.03, 0.3), Vector3(0, -0.015, 0), Build.mat(Color(0.34, 0.36, 0.38), 0.45, 0.6))
	for z in [-0.09, 0.0, 0.09]:
		Build.box(table_n, Vector3(0.5, 0.002, 0.012), Vector3(0, 0.0, z), black)
	var wheel_x := MillModel._handwheel(table_n, Vector3(-0.3, -0.015, 0), Build.AXIS_X, steel, black)
	var wheel_y := MillModel._handwheel(self, Vector3(0, 0.84, 0.28), Build.AXIS_Z, steel, black)
	var vise := Node3D.new()
	table_n.add_child(vise)
	Build.box(vise, Vector3(0.16, 0.03, 0.2), Vector3(0, 0.015, 0), dark)

	# Bohrkopf gleitet an der Säule, Ursprung = Spindelnase
	var head_n := Node3D.new()
	head_n.position.y = MillModel.TOP_Y + 0.2
	add_child(head_n)
	Build.box(head_n, Vector3(0.3, 0.42, 0.56), Vector3(0, 0.27, -0.2), green)
	Build.box(head_n, Vector3(0.32, 0.03, 0.58), Vector3(0, 0.495, -0.2), light)
	Build.cyl(head_n, 0.09, 0.3, Vector3(0, 0.66, -0.3), black)
	Build.cyl(head_n, 0.035, 0.1, Vector3(0, 0.03, 0), steel)
	# Pinolenhebel: drei Griffe am Kreuz
	var wheel_z := Node3D.new()
	wheel_z.position = Vector3(0.18, 0.18, -0.05)
	wheel_z.rotation.y = PI / 2
	head_n.add_child(wheel_z)
	Build.cyl(wheel_z, 0.03, 0.04, Vector3(0, 0, 0.01), steel, Build.AXIS_Z)
	for i in 3:
		var arm := Node3D.new()
		arm.rotation.z = i * TAU / 3.0
		wheel_z.add_child(arm)
		Build.cyl(arm, 0.008, 0.13, Vector3(0, 0.08, 0.02), steel)
		Build.sphere(arm, 0.018, Vector3(0, 0.15, 0.02), black)
	var spindle_n := Node3D.new()
	head_n.add_child(spindle_n)
	var lamp_n := SpotLight3D.new()
	lamp_n.position = Vector3(-0.12, 0.04, 0.08)
	lamp_n.basis = Basis.looking_at((Vector3(0, -0.28, 0) - lamp_n.position).normalized(), Vector3.BACK)
	lamp_n.light_energy = 1.4
	lamp_n.spot_range = 1.2
	lamp_n.spot_angle = 22
	lamp_n.light_color = Color(1.0, 0.96, 0.9)
	head_n.add_child(lamp_n)

	# Anzeige und Lampe
	var screen := Label3D.new()
	screen.position = Vector3(0, 0.3, 0.085)
	screen.pixel_size = 0.0004
	screen.font_size = 36
	screen.outline_size = 0
	screen.modulate = Color(0.55, 0.95, 1.0)
	screen.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	Build.box(head_n, Vector3(0.24, 0.13, 0.004), Vector3(0, 0.3, 0.082), Build.emissive(Color(0.04, 0.14, 0.26), 1.0))
	head_n.add_child(screen)
	var led := Build.cyl(head_n, 0.008, 0.01, Vector3(-0.09, 0.2, 0.084), Build.mat(Color(0.05, 0.2, 0.05), 0.5), Build.AXIS_Z)

	# Bedienfeld an einem Kasten neben der Säule
	Build.box(self, Vector3(0.1, 0.5, 0.3), Vector3(0.15, 1.3, COLUMN_Z), green)
	var p := MillModel.add_panel(self, panel_pos, PI / 2, rpm_dial(), feed_dial(), "Vorschub mm/min", dark, light, black, steel)
	return {"saddle": saddle_n, "table": table_n, "vise": vise, "head": head_n, "spindle": spindle_n,
		"hw_x": wheel_x, "hw_y": wheel_y, "hw_z": wheel_z, "screen": screen, "led": led, "lamp": lamp_n,
		"panel": p["panel"], "dials": p["dials"]}


func _build_colliders() -> void:
	for b in [[Vector3(0.8, 0.12, 1.0), Vector3(0, 0.06, -0.05)], [Vector3(0.16, 2.3, 0.16), Vector3(0, 1.15, COLUMN_Z)],
			[Vector3(0.5, 0.3, 0.42), Vector3(0, 0.84, -0.1)], [Vector3(0.5, 0.14, 0.4), Vector3(0, 0.98, 0.0)],
			[Vector3(0.3, 0.6, 0.56), Vector3(0, 1.75, -0.2)]]:
		Build.collider(self, b[0], b[1]).set_meta("interact", self)
	var levers := Build.collider(self, Vector3(0.04, MillModel.PANEL_H, MillModel.PANEL_W), panel_pos)
	levers.set_meta("interact", _lever_station)


func rpm_dial() -> Array:
	return RPM


func feed_dial() -> Array:
	return FEED


func default_tool_index() -> int:
	return tool_index("B10")


func tool_list() -> Array:
	return MillTools.of_kind("drill")


func bench_rows() -> Array:
	return [{"depth": 0.5, "flat": false, "tools": MillTools.of_kind("drill")}]


func machine_title() -> String:
	return "Konventionelle Standbohrmaschine"


func head_title() -> String:
	return "Pinole"


func axis_name(axis: int) -> String:
	return ["X (Tisch)", "Y (Kreuzschlitten)", "Z (Pinole)"][axis]


func chip_position() -> Vector3:
	return Vector3(randf_range(-0.3, 0.3), BASE_Y + 0.022 + randf() * 0.006, randf_range(-0.25, 0.35))
