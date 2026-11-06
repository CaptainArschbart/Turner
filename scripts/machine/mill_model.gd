class_name MillModel
extends RefCounted
## Baut die konventionelle Fräsmaschine (Arbeitsfläche 410 x 210 mm) als 3D-Modell. Maße in Metern,
## 1 mm Arbeitsfläche = 1 mm im Spiel. Bedienerseite = +Z. Der Tisch fährt in X, der Kreuzschlitten
## in Y, der Fräskopf in Z. Die Spindelachse liegt bei x = 0, z = 0.

const TABLE_L := 0.41        # Arbeitsfläche X (m)
const TABLE_W := 0.21        # Arbeitsfläche Y (m)
const TABLE_Y := 0.95        # Oberkante Tisch
const TOP_Y := 1.06          # Oberseite Rohteil über Boden
const VISE_L := 0.13         # Länge der Schraubstockbacken (m)
# Späne-Auffangwanne: offenes Becken, reicht unter dem Tisch hindurch
const TRAY_X := 0.5          # halbe Breite
const TRAY_Z0 := -0.3        # Rückwand
const TRAY_Z1 := 0.42        # Vorderwand
const TRAY_FLOOR := 0.56     # Oberkante Wannenboden
const TRAY_TOP := 0.7        # Oberkante Wannenrand
const PEDESTAL_X := 0.1      # halbe Breite der Führung, die den Kreuzschlitten trägt
const GUARD_TOP := 1.05      # Oberkante der festen Schutzwand, 100 mm über dem Spanntisch
# Hebelfeld, eingelassen in die rechte Säulenfläche
const LEVER_POS := Vector3(0.182, 1.26, -0.43)
const LEVER_H := 0.28        # Länge der Hebelkulisse
const LEVER_X := [-0.058, 0.058]    # Lage der Kulissen auf dem Feld
const RPM_STEPS := [63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000]
const FEED_STEPS := [10, 16, 25, 40, 63, 100, 160, 250, 400, 630, 1000]


## Gibt die beweglichen Teile zurück: saddle, table, vise, head, spindle, hw_x, hw_y, hw_z,
## screen (Label3D), led, lamp, levers (Node3D des Hebelfelds, Bedienseite = lokal +Z) und knobs.
static func build(root: Node3D) -> Dictionary:
	var grey := Build.mat(Color(0.8, 0.81, 0.8), 0.5, 0.1)
	var light := Build.mat(Color(0.9, 0.9, 0.88), 0.5)
	var red := Build.mat(Color(0.72, 0.09, 0.09), 0.45, 0.1)
	var dark := Build.mat(Color(0.12, 0.13, 0.15), 0.55, 0.2)
	var black := Build.mat(Color(0.05, 0.05, 0.06), 0.6)
	var steel := Build.mat(Color(0.62, 0.64, 0.67), 0.3, 0.9)
	var yellow := Build.mat(Color(0.95, 0.75, 0.05), 0.6)

	# Maschinenfuß trägt die Säule und die Wanne
	Build.box(root, Vector3(0.56, 0.54, 0.86), Vector3(0, 0.27, -0.13), dark)
	Build.box(root, Vector3(0.14, 0.12, 0.01), Vector3(0, 0.34, 0.305), yellow)

	# Späne-Auffangwanne: Boden und vier Wände, innen offen und unter dem Tisch durchgehend
	var tray_w := TRAY_X * 2.0
	var tray_d := TRAY_Z1 - TRAY_Z0
	var tray_c := (TRAY_Z0 + TRAY_Z1) * 0.5
	var wall_h := TRAY_TOP - TRAY_FLOOR + 0.02
	var wall_y := TRAY_FLOOR - 0.02 + wall_h * 0.5
	Build.box(root, Vector3(tray_w, 0.02, tray_d), Vector3(0, TRAY_FLOOR - 0.01, tray_c), red)
	Build.box(root, Vector3(tray_w, wall_h, 0.015), Vector3(0, wall_y, TRAY_Z1 - 0.0075), red)
	Build.box(root, Vector3(tray_w, wall_h, 0.015), Vector3(0, wall_y, TRAY_Z0 + 0.0075), red)
	for s in [-1.0, 1.0]:
		Build.box(root, Vector3(0.015, wall_h, tray_d), Vector3(s * (TRAY_X - 0.0075), wall_y, tray_c), red)

	# Feste, durchgehende Schutzwand auf dem Wannenrand: Sichtscheiben im Rahmen, Rückseite läuft an die Säule
	var pane := Build.glass(Color(0.75, 0.85, 0.9, 0.16))
	var guard_h := GUARD_TOP - TRAY_TOP
	var guard_y := TRAY_TOP + guard_h * 0.5
	Build.box(root, Vector3(tray_w, guard_h, 0.006), Vector3(0, guard_y, TRAY_Z1 - 0.0075), pane)
	Build.box(root, Vector3(tray_w, 0.024, 0.024), Vector3(0, GUARD_TOP, TRAY_Z1 - 0.0075), dark)
	for s in [-1.0, 1.0]:
		Build.box(root, Vector3(0.006, guard_h, tray_d), Vector3(s * (TRAY_X - 0.0075), guard_y, tray_c), pane)
		for z in [TRAY_Z0 + 0.012, TRAY_Z1 - 0.012]:
			Build.box(root, Vector3(0.024, guard_h, 0.024), Vector3(s * (TRAY_X - 0.0075), guard_y, z), dark)
		Build.box(root, Vector3(0.024, 0.024, tray_d), Vector3(s * (TRAY_X - 0.0075), GUARD_TOP, tray_c), dark)
		var back_w := TRAY_X - 0.18
		Build.box(root, Vector3(back_w, guard_h, 0.006), Vector3(s * (TRAY_X + 0.18) * 0.5, guard_y, TRAY_Z0 + 0.0075), pane)
		Build.box(root, Vector3(back_w, 0.024, 0.024), Vector3(s * (TRAY_X + 0.18) * 0.5, GUARD_TOP, TRAY_Z0 + 0.0075), dark)

	# Führung steht schmal in der Wanne und trägt den Kreuzschlitten, links und rechts bleibt die Wanne frei
	Build.box(root, Vector3(PEDESTAL_X * 2.0, 0.34, 0.5), Vector3(0, 0.72, -0.05), grey)

	# Kreuzschlitten (Y) und Tisch (X)
	var saddle := Node3D.new()
	saddle.position.y = TABLE_Y
	root.add_child(saddle)
	Build.box(saddle, Vector3(0.28, 0.06, 0.24), Vector3(0, -0.06, 0), dark)
	var table := Node3D.new()
	saddle.add_child(table)
	Build.box(table, Vector3(TABLE_L, 0.03, TABLE_W), Vector3(0, -0.015, 0), Build.mat(Color(0.34, 0.36, 0.38), 0.45, 0.6))
	for z in [-0.06, 0.0, 0.06]:
		Build.box(table, Vector3(TABLE_L, 0.002, 0.012), Vector3(0, 0.0, z), black)
	var hw_x := _handwheel(table, Vector3(-TABLE_L * 0.5 - 0.05, -0.015, 0), Build.AXIS_X, steel, black)

	# Schraubstock: Grundplatte, feste und bewegliche Backe sitzen je nach Rohteil (Mill)
	var vise := Node3D.new()
	table.add_child(vise)
	Build.box(vise, Vector3(0.15, 0.03, 0.2), Vector3(0, 0.015, 0), dark)

	# Säule mit Faltenbalg, steht hinter der Wanne
	Build.box(root, Vector3(0.36, 1.06, 0.26), Vector3(0, 1.07, -0.43), grey)
	Build.box(root, Vector3(0.3, 0.72, 0.2), Vector3(0, 1.96, -0.45), dark)
	for i in 11:
		var y := 1.02 + i * 0.05
		Build.box(root, Vector3(0.26, 0.04, 0.02), Vector3(0, y, -0.295), light if i % 2 == 0 else Build.mat(Color(0.55, 0.56, 0.57), 0.6))
	Build.box(root, Vector3(0.38, 0.05, 0.02), Vector3(0, 1.58, -0.295), red)
	Build.cyl(root, 0.012, 0.3, Vector3(0, 0.78, 0.33), steel, Build.AXIS_Z)
	var hw_y := _handwheel(root, Vector3(0, 0.78, 0.5), Build.AXIS_Z, steel, black)

	# Fräskopf (Ursprung = Spindelnase)
	var head := Node3D.new()
	head.position.y = TOP_Y + 0.2
	root.add_child(head)
	Build.box(head, Vector3(0.2, 0.6, 0.1), Vector3(0, 0.27, -0.235), dark)
	Build.box(head, Vector3(0.22, 0.44, 0.26), Vector3(0, 0.24, -0.07), light)
	Build.box(head, Vector3(0.18, 0.12, 0.015), Vector3(0, 0.36, 0.065), grey)
	Build.cyl(head, 0.025, 0.012, Vector3(-0.05, 0.36, 0.076), Build.mat(Color(0.12, 0.35, 0.65), 0.4), Build.AXIS_Z)
	Build.box(head, Vector3(0.07, 0.016, 0.012), Vector3(0.04, 0.38, 0.076), black)
	Build.box(head, Vector3(0.07, 0.016, 0.012), Vector3(0.04, 0.34, 0.076), black)
	Build.cyl(head, 0.08, 0.2, Vector3(0, 0.56, -0.08), black)
	Build.cyl(head, 0.055, 0.03, Vector3(0, 0.015, 0), steel)
	var hw_z := _handwheel(head, Vector3(0.16, 0.2, -0.08), Build.AXIS_X, steel, black)

	var spindle := Node3D.new()
	head.add_child(spindle)

	# Arbeitsleuchte am Fräskopf (Gelenkarm links)
	Build.cyl(head, 0.012, 0.32, Vector3(-0.15, 0.3, -0.1), black)
	Build.cyl(head, 0.012, 0.36, Vector3(-0.15, 0.46, 0.08), black, Build.AXIS_Z)
	Build.cyl(head, 0.05, 0.1, Vector3(-0.15, 0.42, 0.26), black, Build.AXIS_Y, false, 16, 0.03)
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(-0.15, 0.36, 0.26)
	# Auf die Schneide unter der Spindel gerichtet
	lamp.basis = Basis.looking_at((Vector3(0, -0.3, 0.02) - lamp.position).normalized(), Vector3.BACK)
	lamp.light_energy = 1.4
	lamp.spot_range = 1.4
	lamp.spot_angle = 13
	lamp.light_color = Color(1.0, 0.96, 0.9)
	head.add_child(lamp)

	# Hebelfeld: flach in der rechten Säulenfläche, so breit wie die Fläche es zulässt
	var levers := Node3D.new()
	levers.position = LEVER_POS
	levers.rotation.y = PI / 2
	root.add_child(levers)
	Build.box(levers, Vector3(0.24, 0.37, 0.002), Vector3.ZERO, dark)
	Build.box(levers, Vector3(0.23, 0.36, 0.004), Vector3.ZERO, light)
	var knobs := [_lever(levers, 0, "Drehzahl 1/min", RPM_STEPS, black), _lever(levers, 1, "Vorschub mm/min", FEED_STEPS, black)]

	# Rotes Bediengehäuse am Schwenkarm, schwarzer Kabelschlauch läuft außen an der Wanne vorbei
	Build.box(root, Vector3(0.4, 0.05, 0.05), Vector3(0.38, 1.78, -0.42), dark)
	Build.box(root, Vector3(0.05, 0.05, 0.54), Vector3(0.58, 1.78, -0.17), dark)
	var cp := Node3D.new()
	cp.position = Vector3(0.58, 1.48, 0.1)
	cp.rotation.y = -0.3
	root.add_child(cp)
	Build.box(cp, Vector3(0.05, 0.28, 0.05), Vector3(0, 0.15, -0.03), dark)
	Build.box(cp, Vector3(0.42, 0.34, 0.1), Vector3.ZERO, red)
	Build.box(cp, Vector3(0.36, 0.2, 0.004), Vector3(0, 0.05, 0.051), black)
	Build.box(cp, Vector3(0.34, 0.18, 0.004), Vector3(0, 0.05, 0.054), Build.emissive(Color(0.04, 0.14, 0.26), 1.0))
	var screen := Label3D.new()
	screen.position = Vector3(0, 0.05, 0.058)
	screen.pixel_size = 0.00042
	screen.font_size = 40
	screen.outline_size = 0
	screen.modulate = Color(0.55, 0.95, 1.0)
	screen.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cp.add_child(screen)
	Build.cyl(cp, 0.018, 0.02, Vector3(-0.13, -0.11, 0.055), Build.mat(Color(0.1, 0.55, 0.15), 0.4), Build.AXIS_Z)
	Build.cyl(cp, 0.018, 0.02, Vector3(-0.07, -0.11, 0.055), black, Build.AXIS_Z)
	Build.cyl(cp, 0.03, 0.01, Vector3(0.12, -0.11, 0.052), yellow, Build.AXIS_Z)
	Build.cyl(cp, 0.022, 0.03, Vector3(0.12, -0.11, 0.065), red, Build.AXIS_Z)
	var led := Build.cyl(cp, 0.008, 0.01, Vector3(0.0, -0.11, 0.052), Build.mat(Color(0.05, 0.2, 0.05), 0.5), Build.AXIS_Z)
	var hose := Build.mat(Color(0.06, 0.06, 0.07), 0.8)
	Build.cyl(root, 0.025, 1.0, Vector3(0.58, 0.8, 0.1), hose)
	Build.cyl(root, 0.025, 0.32, Vector3(0.43, 0.3, 0.1), hose, Build.AXIS_X)

	return {"saddle": saddle, "table": table, "vise": vise, "head": head, "spindle": spindle,
		"hw_x": hw_x, "hw_y": hw_y, "hw_z": hw_z, "screen": screen, "led": led, "lamp": lamp, "levers": levers, "knobs": knobs}


## Höhe einer Hebelstufe auf der Platte. Stufe 0 unten.
static func lever_y(step: int, steps: int) -> float:
	return -LEVER_H * 0.5 + LEVER_H * step / float(maxi(steps - 1, 1))


## Stufenhebel: senkrechte Kulisse mit Stufen-Beschriftung, der Griff wird von Mill verschoben.
static func _lever(plate: Node3D, k: int, title: String, steps: Array, knob_m: Material) -> Node3D:
	var x: float = LEVER_X[k]
	Build.box(plate, Vector3(0.01, LEVER_H + 0.02, 0.002), Vector3(x - 0.024, 0, 0.003), Build.mat(Color(0.05, 0.05, 0.06), 0.7))
	var dark := Color(0.08, 0.08, 0.09)
	Build.label(plate, title, Vector3(x, LEVER_H * 0.5 + 0.022, 0.004), 0.00022, dark, 32)
	for i in steps.size():
		Build.label(plate, str(steps[i]), Vector3(x + 0.014, lever_y(i, steps.size()), 0.004), 0.0003, dark, 32)
	var knob := Node3D.new()
	knob.position = Vector3(x - 0.024, 0, 0.004)
	plate.add_child(knob)
	Build.cyl(knob, 0.005, 0.03, Vector3(0, 0, 0.015), Build.mat(Color(0.62, 0.64, 0.67), 0.3, 0.9), Build.AXIS_Z)
	Build.sphere(knob, 0.013, Vector3(0, 0, 0.033), knob_m)
	return knob


## Handrad, dreht sich um die angegebene Achse des zurückgegebenen Knotens.
static func _handwheel(parent: Node3D, pos: Vector3, axis: int, ring: Material, knob: Material) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	if axis == Build.AXIS_X:
		n.rotation.y = -PI / 2
		if pos.x > 0.0:
			n.rotation.y = PI / 2
	parent.add_child(n)
	Build.cyl(n, 0.012, 0.09, Vector3(0, 0, -0.045), ring, Build.AXIS_Z)
	Build.cyl(n, 0.06, 0.012, Vector3(0, 0, 0.0), ring, Build.AXIS_Z)
	Build.cyl(n, 0.018, 0.02, Vector3(0, 0, 0.012), knob, Build.AXIS_Z)
	Build.cyl(n, 0.008, 0.05, Vector3(0.045, 0, 0.03), knob, Build.AXIS_Z)
	return n
