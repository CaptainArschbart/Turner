class_name Workshop
extends RefCounted
## Baut die leere Werkstatthalle (ca. 24 x 16 m) mit dem Meisterbüro prozedural auf.
## Gibt ein Dictionary mit Lichtern zurück, damit die Qualitätseinstellung Schatten steuern kann.

const W := 24.0
const D := 16.0
const H := 6.5
const DOOR_Z := -2.0     # Mitte des Rolltors in der Ostwand


static func build(root: Node3D) -> Dictionary:
	var lights: Array = []
	var shadow_lights: Array = []

	var wall_mat := Build.mat(Color(0.86, 0.87, 0.86), 0.9)
	var wall_low := Build.mat(Color(0.24, 0.27, 0.30), 0.8)
	var steel_blue := Build.mat(Color(0.20, 0.28, 0.36), 0.55, 0.3)
	var anth := Build.mat(Color(0.18, 0.19, 0.21), 0.6)
	var yellow := Build.mat(Color(0.95, 0.75, 0.05), 0.6)
	var ceiling := Build.mat(Color(0.32, 0.33, 0.35), 0.9)

	# ---------------- Boden (Epoxid-Beschichtung mit leichter Struktur)
	var floor_mat := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.36, 0.40, 0.39))
	ramp.set_color(1, Color(0.47, 0.51, 0.50))
	tex.color_ramp = ramp
	floor_mat.albedo_texture = tex
	var ntex := NoiseTexture2D.new()
	ntex.width = 512
	ntex.height = 512
	ntex.seamless = true
	ntex.as_normal_map = true
	ntex.bump_strength = 1.5
	ntex.noise = noise
	floor_mat.normal_enabled = true
	floor_mat.normal_texture = ntex
	floor_mat.normal_scale = 0.3
	floor_mat.roughness = 0.42
	floor_mat.uv1_scale = Vector3(10, 7, 1)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, D)
	floor_mi.mesh = pm
	floor_mi.material_override = floor_mat
	root.add_child(floor_mi)
	Build.collider(root, Vector3(W, 0.4, D), Vector3(0, -0.2, 0))

	# Bodenmarkierungen (Gehwege, Maschinenbereich)
	var mark_y := 0.003
	for z in [1.6, 5.2]:
		Build.box(root, Vector3(W - 2.0, 0.004, 0.08), Vector3(0, mark_y, z), yellow)
	# Die Bereiche der Maschinen zeichnet das Gelände.

	# ---------------- Wände
	Build.box(root, Vector3(W, H, 0.3), Vector3(0, H / 2, -D / 2 - 0.15), wall_mat, true)
	Build.box(root, Vector3(W, H, 0.3), Vector3(0, H / 2, D / 2 + 0.15), wall_mat, true)
	# Die Westseite baut das Gelände aus Kacheln
	# Ostwand mit Öffnung für das Rolltor
	var door_z0 := DOOR_Z - RollDoor.WIDTH / 2.0
	var door_z1 := DOOR_Z + RollDoor.WIDTH / 2.0
	Build.box(root, Vector3(0.3, H, door_z0 + D / 2), Vector3(W / 2 + 0.15, H / 2, (door_z0 - D / 2) / 2), wall_mat, true)
	Build.box(root, Vector3(0.3, H, D / 2 - door_z1), Vector3(W / 2 + 0.15, H / 2, (door_z1 + D / 2) / 2), wall_mat, true)
	Build.box(root, Vector3(0.3, H - RollDoor.HEIGHT, RollDoor.WIDTH), Vector3(W / 2 + 0.15, (H + RollDoor.HEIGHT) / 2, DOOR_Z), wall_mat, true)
	# Sockelpaneele
	Build.box(root, Vector3(W, 1.2, 0.04), Vector3(0, 0.6, -D / 2 + 0.02), wall_low)
	Build.box(root, Vector3(W, 1.2, 0.04), Vector3(0, 0.6, D / 2 - 0.02), wall_low)
	Build.box(root, Vector3(0.04, 1.2, door_z0 + D / 2), Vector3(W / 2 - 0.02, 0.6, (door_z0 - D / 2) / 2), wall_low)
	Build.box(root, Vector3(0.04, 1.2, D / 2 - door_z1), Vector3(W / 2 - 0.02, 0.6, (door_z1 + D / 2) / 2), wall_low)
	# Stahlstützen an den Längswänden
	for x in range(-12, 13, 6):
		for z in [-D / 2 + 0.2, D / 2 - 0.2]:
			Build.box(root, Vector3(0.3, H, 0.3), Vector3(x, H / 2, z), steel_blue, true)

	# Fensterband (Tageslicht) oben an der Nordwand
	var sky := Build.emissive(Color(0.78, 0.88, 1.0), 1.6)
	for i in 8:
		var x := -10.5 + i * 3.0
		Build.box(root, Vector3(2.5, 1.3, 0.04), Vector3(x, 4.6, -D / 2 + 0.02), sky)
		Build.box(root, Vector3(2.6, 0.08, 0.1), Vector3(x, 3.92, -D / 2 + 0.05), anth)
		Build.box(root, Vector3(0.05, 1.3, 0.08), Vector3(x, 4.6, -D / 2 + 0.05), anth)
	var window_light := OmniLight3D.new()
	window_light.position = Vector3(0, 4.5, -6.5)
	window_light.light_color = Color(0.8, 0.88, 1.0)
	window_light.light_energy = 0.8
	window_light.omni_range = 10
	root.add_child(window_light)
	lights.append(window_light)

	# ---------------- Decke, Träger, Hallenkran
	Build.box(root, Vector3(W, 0.3, D), Vector3(0, H + 0.15, 0), ceiling)
	for x in range(-10, 11, 4):
		Build.box(root, Vector3(0.25, 0.5, D), Vector3(x, H - 0.25, 0), steel_blue)
	# Kranbahn + Brücke (gelb)
	for z in [-7.4, 7.4]:
		Build.box(root, Vector3(W, 0.35, 0.3), Vector3(0, 5.3, z), steel_blue)
	var crane := Node3D.new()
	crane.position = Vector3(-4.0, 0, 0)
	root.add_child(crane)
	Build.box(crane, Vector3(0.5, 0.6, 15.0), Vector3(0, 5.6, 0), yellow)
	Build.box(crane, Vector3(0.6, 0.45, 0.6), Vector3(0, 5.1, -1.5), anth)
	Build.cyl(crane, 0.015, 2.0, Vector3(0, 3.9, -1.5), Build.mat(Color(0.3, 0.3, 0.3), 0.4, 1.0))
	Build.box(crane, Vector3(0.12, 0.18, 0.06), Vector3(0, 2.85, -1.5), yellow)
	Build.label(crane, "5 t", Vector3(0.26, 5.6, 2.0), 0.01, Color(0.1, 0.1, 0.1), 64, PI / 2)

	# ---------------- LED-Hallenleuchten
	var led := Build.emissive(Color(1.0, 0.98, 0.94), 4.0)
	var housing := Build.mat(Color(0.75, 0.76, 0.78), 0.4, 0.6)
	for x in [-8.0, -3.0, 2.0, 7.0]:
		for z in [-5.0, 0.0, 5.0]:
			var y := H - 0.8
			Build.box(root, Vector3(1.4, 0.06, 0.36), Vector3(x, y + 0.04, z), housing)
			Build.box(root, Vector3(1.32, 0.02, 0.28), Vector3(x, y, z), led)
			Build.cyl(root, 0.006, 0.75, Vector3(x - 0.6, y + 0.42, z), housing)
			Build.cyl(root, 0.006, 0.75, Vector3(x + 0.6, y + 0.42, z), housing)
			var l := OmniLight3D.new()
			l.position = Vector3(x, y - 0.3, z)
			l.light_color = Color(1.0, 0.97, 0.92)
			l.light_energy = 1.1
			l.omni_range = 9.0
			l.omni_attenuation = 1.2
			root.add_child(l)
			lights.append(l)
			if (x == 2.0 and z == 0.0) or (x == -3.0 and z == 0.0) or (x == 2.0 and z == -5.0):
				shadow_lights.append(l)

	# ---------------- Einrichtung: Die Halle ist leer bis auf das Büro und was an den Wänden hängt
	_office(root)
	_wall_signs(root)

	return {"lights": lights, "shadow_lights": shadow_lights}


static func rect_marking(root: Node3D, a: Vector2, b: Vector2, m: Material) -> void:
	var y := 0.003
	var w := b.x - a.x
	var d := b.y - a.y
	Build.box(root, Vector3(w, 0.004, 0.08), Vector3(a.x + w / 2, y, a.y), m)
	Build.box(root, Vector3(w, 0.004, 0.08), Vector3(a.x + w / 2, y, b.y), m)
	Build.box(root, Vector3(0.08, 0.004, d), Vector3(a.x, y, a.y + d / 2), m)
	Build.box(root, Vector3(0.08, 0.004, d), Vector3(b.x, y, a.y + d / 2), m)


static func _office(root: Node3D) -> void:
	var g := Build.glass(Color(0.7, 0.85, 0.95, 0.15))
	var frame := Build.mat(Color(0.2, 0.2, 0.22), 0.4, 0.5)
	# Glaswand bei x = 8, z 4..8 und z = 4, x 8..12
	Build.box(root, Vector3(0.05, 2.8, 4.0), Vector3(8.0, 1.4, 6.0), g, true)
	Build.box(root, Vector3(2.6, 2.8, 0.05), Vector3(10.7, 1.4, 4.0), g, true)
	Build.box(root, Vector3(0.08, 0.08, 4.0), Vector3(8.0, 2.8, 6.0), frame)
	Build.box(root, Vector3(4.0, 0.08, 0.08), Vector3(10.0, 2.8, 4.0), frame)
	for z in [4.0, 6.0, 8.0]:
		Build.box(root, Vector3(0.08, 2.8, 0.08), Vector3(8.0, 1.4, z), frame)
	Build.box(root, Vector3(4.0, 0.08, 4.0), Vector3(10.0, 2.84, 6.0), Build.mat(Color(0.85, 0.85, 0.85), 0.8))
	# Schreibtisch, Monitor, Stuhl, Pflanze
	var desk := Build.mat(Color(0.9, 0.9, 0.88), 0.6)
	Build.box(root, Vector3(1.6, 0.04, 0.8), Vector3(10.5, 0.75, 7.3), desk, true)
	Build.box(root, Vector3(0.04, 0.73, 0.7), Vector3(9.75, 0.37, 7.3), frame)
	Build.box(root, Vector3(0.04, 0.73, 0.7), Vector3(11.25, 0.37, 7.3), frame)
	Build.box(root, Vector3(0.6, 0.36, 0.03), Vector3(10.5, 1.05, 7.55), frame)
	Build.box(root, Vector3(0.56, 0.32, 0.005), Vector3(10.5, 1.05, 7.533), Build.emissive(Color(0.3, 0.5, 0.75), 1.2))
	Build.box(root, Vector3(0.5, 0.08, 0.5), Vector3(10.5, 0.48, 6.7), Build.mat(Color(0.1, 0.1, 0.1), 0.7))
	Build.box(root, Vector3(0.5, 0.55, 0.06), Vector3(10.5, 0.8, 6.45), Build.mat(Color(0.1, 0.1, 0.1), 0.7))
	Build.cyl(root, 0.18, 0.4, Vector3(11.6, 0.2, 4.5), Build.mat(Color(0.85, 0.85, 0.85), 0.5))
	Build.sphere(root, 0.32, Vector3(11.6, 0.7, 4.5), Build.mat(Color(0.2, 0.5, 0.2), 0.8))
	Build.label(root, "MEISTERBÜRO", Vector3(7.97, 2.5, 6.0), 0.005, Color(0.15, 0.15, 0.15), 48, -PI / 2)


static func _wall_signs(root: Node3D) -> void:
	var black := Build.mat(Color(0.08, 0.08, 0.08), 0.6)
	# Schilder
	var sign_bg := Build.mat(Color(0.05, 0.35, 0.75), 0.6)
	Build.box(root, Vector3(1.6, 0.7, 0.02), Vector3(0.5, 2.6, -7.97), sign_bg)
	Build.label(root, "Schutzbrille und\nGehörschutz tragen!", Vector3(0.5, 2.6, -7.955), 0.0028, Color.WHITE, 48)
	Build.box(root, Vector3(0.35, 0.35, 0.12), Vector3(-1.5, 1.6, 7.93), Build.mat(Color(0.05, 0.55, 0.25), 0.5))
	Build.label(root, "+", Vector3(-1.5, 1.6, 7.865), 0.008, Color.WHITE, 64, PI)
	Build.label(root, "WERKSTATT TURNER", Vector3(0, 5.0, 7.83), 0.012, Color(0.25, 0.27, 0.3), 96, PI)
	# Uhr
	Build.cyl(root, 0.25, 0.04, Vector3(-4.0, 3.2, -7.95), Build.mat(Color(0.95, 0.95, 0.95), 0.5), Build.AXIS_Z)
	Build.box(root, Vector3(0.02, 0.18, 0.01), Vector3(-4.0, 3.27, -7.92), black)
	Build.box(root, Vector3(0.13, 0.02, 0.01), Vector3(-3.95, 3.2, -7.92), black)
