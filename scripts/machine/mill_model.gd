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
# Bedienfeld, eingelassen in die rechte Säulenfläche: je ein Drehknopf mit Tasten I und II
const PANEL_POS := Vector3(0.182, 1.28, -0.43)
const PANEL_W := 0.25
const PANEL_H := 0.44
const DIAL_Y := [0.09, -0.13] # Mitte der Drehknöpfe auf dem Feld: oben Drehzahl, unten Vorschub
const DIAL_R := 0.08          # Außenradius der Skala
const DIAL_R_BLACK := 0.068   # Schriftkreis des schwarzen Rings (Stufe II)
const DIAL_R_BLUE := 0.046    # Schriftkreis des blauen Rings (Stufe I)
const HANDLE_R := 0.09        # Griffkugel so weit von der Knopfmitte
const HANDLE_OFFSET := PI / 8.0   # Griff steht zwischen zwei Werten und verdeckt so keinen
const STAGE_X := [-0.07, 0.07]    # Tasten I und II
const STAGE_DY := 0.1         # Tasten liegen so weit über der Knopfmitte
const STAGE_R := 0.016
# Rastwerte je Stufe. Blauer Ring = Stufe I, schwarzer Ring = Stufe II, beide über die vollen 360°.
const RPM_DIAL := [[40, 63, 100, 160, 250, 400, 630, 1000], [80, 125, 200, 315, 500, 800, 1250, 2000]]
const FEED_DIAL := [[10, 16, 25, 40, 63, 100, 160, 250], [20, 32, 50, 80, 125, 200, 315, 500]]


## Gibt die beweglichen Teile zurück: saddle, table, vise, head, spindle, hw_x, hw_y, hw_z, screen
## (Label3D), led, lamp, panel (Node3D des Bedienfelds, Bedienseite = lokal +Z) und dials
## (je {"knob": Node3D, "stages": [Tasten I und II], "labels": [Werte Stufe I, Werte Stufe II]}).
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

	# Bedienfeld: flach in der rechten Säulenfläche, so breit wie die Fläche es zulässt
	var bedien := add_panel(root, PANEL_POS, PI / 2, RPM_DIAL, FEED_DIAL, "Vorschub mm/min", dark, light, black, steel)
	var panel: Node3D = bedien["panel"]
	var dials: Array = bedien["dials"]

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
		"hw_x": hw_x, "hw_y": hw_y, "hw_z": hw_z, "screen": screen, "led": led, "lamp": lamp, "panel": panel, "dials": dials}


## Bedienfeld mit je einem Drehknopf für Drehzahl und Vorschub. Bedienseite = lokal +Z. Auch für die
## anderen konventionellen Maschinen. Gibt {"panel", "dials"} zurück.
static func add_panel(root: Node3D, pos: Vector3, rot_y: float, rpm: Array, feed: Array, feed_title: String,
		dark: Material, light: Material, black: Material, steel: Material) -> Dictionary:
	var panel := Node3D.new()
	panel.position = pos
	panel.rotation.y = rot_y
	root.add_child(panel)
	Build.box(panel, Vector3(PANEL_W, PANEL_H, 0.002), Vector3.ZERO, dark)
	Build.box(panel, Vector3(PANEL_W - 0.01, PANEL_H - 0.01, 0.004), Vector3.ZERO, light)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			Build.cyl(panel, 0.005, 0.004, Vector3(sx * (PANEL_W * 0.5 - 0.016), sy * (PANEL_H * 0.5 - 0.016), 0.003), black, Build.AXIS_Z)
	return {"panel": panel, "dials": [_dial(panel, 0, "Drehzahl 1/min", rpm, black, steel), _dial(panel, 1, feed_title, feed, black, steel)]}


## Winkel einer Raste, im Uhrzeigersinn ab 12 Uhr. Die Rasten verteilen sich auf die vollen 360°.
static func dial_angle(pos: int, positions := 8) -> float:
	return TAU * pos / float(maxi(positions, 1))


## Winkel des Griffhebels, wenn der Knopf auf Raste pos steht.
static func handle_angle(pos: int, positions := 8) -> float:
	return dial_angle(pos, positions) + HANDLE_OFFSET


## Drehknopf mit zweifarbiger Skala, Griffhebel und den Tasten für Stufe I und II darüber.
static func _dial(plate: Node3D, k: int, title: String, values: Array, black: Material, steel: Material) -> Dictionary:
	var cy: float = DIAL_Y[k]
	var blue := Build.mat(Color(0.05, 0.16, 0.55), 0.35, 0.3)
	var white := Color(0.95, 0.95, 0.95)

	# Skala: Chromrand, schwarzer Ring, blauer Ring, feststehender Kragen
	Build.cyl(plate, DIAL_R, 0.004, Vector3(0, cy, 0.003), steel, Build.AXIS_Z, false, 48)
	Build.cyl(plate, DIAL_R - 0.002, 0.006, Vector3(0, cy, 0.004), black, Build.AXIS_Z, false, 48)
	Build.cyl(plate, 0.057, 0.008, Vector3(0, cy, 0.005), blue, Build.AXIS_Z, false, 48)
	Build.cyl(plate, 0.033, 0.012, Vector3(0, cy, 0.007), black, Build.AXIS_Z, false, 32)
	# Jede Stufe hat ihren eigenen Ring mit Einzelwerten. Untere Hälfte so gedreht, dass sie lesbar bleibt.
	var labels := [[], []]
	for st in 2:
		var r: float = DIAL_R_BLUE if st == 0 else DIAL_R_BLACK
		var z := 0.0095 if st == 0 else 0.0075
		var px := 0.00028 if st == 0 else 0.0003
		var n: int = values[st].size()
		for i in n:
			var a := dial_angle(i, n)
			var l := Build.label(plate, str(values[st][i]), Vector3(sin(a) * r, cy + cos(a) * r, z), px, white, 32)
			l.rotation.z = -a + (PI if cos(a) < -0.01 else 0.0)
			labels[st].append(l)

	# Drehknopf: gerändelter Griff, Chromkappe, Marke auf den Wert und seitlich versetzter Griffhebel mit Kugel
	var knob := Node3D.new()
	knob.position = Vector3(0, cy, 0.012)
	plate.add_child(knob)
	Build.cyl(knob, 0.029, 0.018, Vector3(0, 0, 0.009), black, Build.AXIS_Z, false, 32)
	for i in 16:
		var a := TAU * i / 16.0
		Build.box(knob, Vector3(0.004, 0.004, 0.016), Vector3(sin(a) * 0.029, cos(a) * 0.029, 0.009), black, false, Vector3(0, 0, -a))
	Build.cyl(knob, 0.021, 0.004, Vector3(0, 0, 0.02), Build.mat(Color(0.85, 0.86, 0.88), 0.35, 0.4), Build.AXIS_Z, false, 32)
	Build.label(knob, "I  II", Vector3(0, 0, 0.0225), 0.00034, Color(0.05, 0.05, 0.06), 32)
	Build.box(knob, Vector3(0.003, 0.009, 0.002), Vector3(0, 0.032, 0.006), Build.emissive(Color(0.95, 0.95, 0.95), 0.6))
	var arm := Node3D.new()
	arm.rotation.z = -HANDLE_OFFSET
	knob.add_child(arm)
	Build.box(arm, Vector3(0.004, HANDLE_R - 0.02, 0.005), Vector3(0, (HANDLE_R + 0.02) * 0.5, 0.012), steel)
	Build.sphere(arm, 0.012, Vector3(0, HANDLE_R, 0.016), black)

	# Tastenleiste über dem Knopf
	var bar_y := cy + STAGE_DY
	Build.box(plate, Vector3(0.21, 0.04, 0.004), Vector3(0, bar_y, 0.003), steel)
	Build.box(plate, Vector3(0.204, 0.034, 0.006), Vector3(0, bar_y, 0.003), black)
	Build.label(plate, title.replace(" ", "\n"), Vector3(0, bar_y, 0.0065), 0.00024, white, 32)
	var stages := []
	for s in 2:
		var x: float = STAGE_X[s]
		# Chromring bleibt flach, damit die eingedrückte Taste sichtbar herausschaut
		Build.cyl(plate, STAGE_R + 0.002, 0.004, Vector3(x, bar_y, 0.004), steel, Build.AXIS_Z, false, 24)
		var btn := Node3D.new()
		btn.position = Vector3(x, bar_y, 0.0)
		plate.add_child(btn)
		Build.cyl(btn, STAGE_R - 0.002, 0.012, Vector3(0, 0, 0.006), black, Build.AXIS_Z, false, 24)
		Build.label(btn, ["I", "II"][s], Vector3(0, 0, 0.0125), 0.0004, white, 32)
		stages.append(btn)
	return {"knob": knob, "stages": stages, "labels": labels}


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
