class_name Workshop
extends RefCounted
## Baut die leere Werkstatthalle (ca. 24 x 16 m) mit dem Meisterbüro prozedural auf.
## Gibt ein Dictionary mit Lichtern zurück, damit die Qualitätseinstellung Schatten steuern kann.

const W := 24.0
const D := 16.0
const H := 6.5
const DOOR_Z := 3.4      # Mitte des Rolltors in der Ostwand, in der Flucht des markierten Wegs
const OFFICE_DOOR_X := 7.0   # Scharnier der Bürotür in der Südwand
const OFFICE_X := Vector2(5.4, 11.6)   # Büroanbau von x bis x
const OFFICE_Z1 := 12.6      # Rückwand des Büros
const OFFICE_H := 3.0
const OFFICE_PC_POS := Vector3(9.3, 1.05, 12.1)


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
	# Südwand mit Öffnung für die Bürotür
	var ox0 := OFFICE_DOOR_X
	var ox1 := OFFICE_DOOR_X + OfficeDoor.WIDTH
	Build.box(root, Vector3(ox0 + W / 2, H, 0.3), Vector3((ox0 - W / 2) / 2, H / 2, D / 2 + 0.15), wall_mat, true)
	Build.box(root, Vector3(W / 2 - ox1, H, 0.3), Vector3((ox1 + W / 2) / 2, H / 2, D / 2 + 0.15), wall_mat, true)
	Build.box(root, Vector3(OfficeDoor.WIDTH, H - OfficeDoor.HEIGHT, 0.3), Vector3((ox0 + ox1) / 2, (H + OfficeDoor.HEIGHT) / 2, D / 2 + 0.15), wall_mat, true)
	# Die Westseite baut das Gelände aus Kacheln
	# Ostwand mit Öffnung für das Rolltor
	var door_z0 := DOOR_Z - RollDoor.WIDTH / 2.0
	var door_z1 := DOOR_Z + RollDoor.WIDTH / 2.0
	Build.box(root, Vector3(0.3, H, door_z0 + D / 2), Vector3(W / 2 + 0.15, H / 2, (door_z0 - D / 2) / 2), wall_mat, true)
	Build.box(root, Vector3(0.3, H, D / 2 - door_z1), Vector3(W / 2 + 0.15, H / 2, (door_z1 + D / 2) / 2), wall_mat, true)
	Build.box(root, Vector3(0.3, H - RollDoor.HEIGHT, RollDoor.WIDTH), Vector3(W / 2 + 0.15, (H + RollDoor.HEIGHT) / 2, DOOR_Z), wall_mat, true)
	# Sockelpaneele
	Build.box(root, Vector3(W, 1.2, 0.04), Vector3(0, 0.6, -D / 2 + 0.02), wall_low)
	Build.box(root, Vector3(ox0 + W / 2, 1.2, 0.04), Vector3((ox0 - W / 2) / 2, 0.6, D / 2 - 0.02), wall_low)
	Build.box(root, Vector3(W / 2 - ox1, 1.2, 0.04), Vector3((ox1 + W / 2) / 2, 0.6, D / 2 - 0.02), wall_low)
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

	# ---------------- Einrichtung: Die Halle ist leer bis auf das, was an den Wänden und unter der Decke hängt
	lights.append(_office(root))
	_wall_signs(root)
	_floor_details(root)
	_wall_details(root)
	Surroundings.build(root)

	return {"lights": lights, "shadow_lights": shadow_lights}


static func rect_marking(root: Node3D, a: Vector2, b: Vector2, m: Material) -> void:
	var y := 0.0045
	var w := b.x - a.x
	var d := b.y - a.y
	Build.box(root, Vector3(w, 0.004, 0.08), Vector3(a.x + w / 2, y, a.y), m)
	Build.box(root, Vector3(w, 0.004, 0.08), Vector3(a.x + w / 2, y, b.y), m)
	Build.box(root, Vector3(0.08, 0.004, d), Vector3(a.x, y, a.y + d / 2), m)
	Build.box(root, Vector3(0.08, 0.004, d), Vector3(b.x, y, a.y + d / 2), m)


## Meisterbüro als Anbau an der Südseite, durch die Tür aus der Halle betretbar. Gibt seine Leuchte zurück.
static func _office(root: Node3D) -> OmniLight3D:
	var x0 := OFFICE_X.x
	var x1 := OFFICE_X.y
	var z0 := D / 2.0 + 0.3
	var z1 := OFFICE_Z1
	var h := OFFICE_H
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var wall := Build.mat(Color(0.88, 0.88, 0.84), 0.85)
	var skin := Build.mat(Color(0.7, 0.73, 0.74), 0.8, 0.1)
	var frame := Build.mat(Color(0.2, 0.2, 0.22), 0.4, 0.5)
	var glass := Build.glass(Color(0.7, 0.85, 0.95, 0.2))
	# Boden reicht bis in die Türöffnung, sonst bleibt dort eine Lücke
	Build.box(root, Vector3(x1 - x0 + 0.4, 0.4, z1 - D / 2.0 + 0.2), Vector3(cx, -0.2, (z1 + D / 2.0) * 0.5 + 0.1), Build.mat(Color(0.5, 0.38, 0.26), 0.6), true)
	Build.box(root, Vector3(x1 - x0, 0.1, z1 - z0), Vector3(cx, h + 0.05, cz), Build.mat(Color(0.92, 0.92, 0.9), 0.9))
	var roof := Build.box(root, Vector3(x1 - x0 + 0.6, 0.1, z1 - z0 + 0.5), Vector3(cx, h + 0.16, cz + 0.05), Build.mat(Color(0.3, 0.32, 0.34), 0.9))
	roof.layers = Site.OUTDOOR_LAYER
	# Westwand und Ostwand, innen hell, außen Blech
	for x in [x0 - 0.1, x1 + 0.1]:
		Build.box(root, Vector3(0.2, h, z1 - z0), Vector3(x, h * 0.5, cz), wall, true)
		var out_x: float = x + (0.11 if x > cx else -0.11)
		Build.box(root, Vector3(0.02, h, z1 - z0), Vector3(out_x, h * 0.5, cz), skin).layers = Site.OUTDOOR_LAYER
	# Südwand mit Fenster
	var wx0 := cx - 1.4
	var wx1 := cx + 1.4
	var sy0 := 0.95
	var sy1 := 2.25
	for t in [[x0, wx0], [wx1, x1]]:
		Build.box(root, Vector3(t[1] - t[0], h, 0.2), Vector3((t[0] + t[1]) * 0.5, h * 0.5, z1 + 0.1), wall, true)
	Build.box(root, Vector3(wx1 - wx0, sy0, 0.2), Vector3(cx, sy0 * 0.5, z1 + 0.1), wall, true)
	Build.box(root, Vector3(wx1 - wx0, h - sy1, 0.2), Vector3(cx, (h + sy1) * 0.5, z1 + 0.1), wall)
	Build.box(root, Vector3(wx1 - wx0, sy1 - sy0, 0.03), Vector3(cx, (sy0 + sy1) * 0.5, z1 + 0.1), glass, true)
	for x in [wx0, cx, wx1]:
		Build.box(root, Vector3(0.05, sy1 - sy0, 0.06), Vector3(x, (sy0 + sy1) * 0.5, z1 + 0.1), frame)
	for y in [sy0, sy1]:
		Build.box(root, Vector3(wx1 - wx0 + 0.05, 0.05, 0.06), Vector3(cx, y, z1 + 0.1), frame)
	Build.box(root, Vector3(wx1 - wx0 + 0.1, 0.03, 0.16), Vector3(cx, sy0 - 0.03, z1 - 0.04), Build.mat(Color(0.95, 0.95, 0.93), 0.5))
	for t in [[x0, wx0], [wx1, x1]]:
		Build.box(root, Vector3(t[1] - t[0], h, 0.02), Vector3((t[0] + t[1]) * 0.5, h * 0.5, z1 + 0.21), skin).layers = Site.OUTDOOR_LAYER
	# Tür in der Hallenwand mit Rahmen und Schild
	var door := OfficeDoor.new()
	door.position = Vector3(OFFICE_DOOR_X, 0, D / 2.0 + 0.15)
	root.add_child(door)
	var dx0 := OFFICE_DOOR_X
	var dx1 := OFFICE_DOOR_X + OfficeDoor.WIDTH
	var dh := OfficeDoor.HEIGHT
	for x in [dx0 - 0.03, dx1 + 0.03]:
		Build.box(root, Vector3(0.06, dh + 0.06, 0.34), Vector3(x, (dh + 0.06) * 0.5, D / 2.0 + 0.15), frame)
	Build.box(root, Vector3(OfficeDoor.WIDTH + 0.12, 0.06, 0.34), Vector3((dx0 + dx1) * 0.5, dh + 0.03, D / 2.0 + 0.15), frame)
	var sign_x := (dx0 + dx1) * 0.5
	Build.box(root, Vector3(1.0, 0.24, 0.02), Vector3(sign_x, dh + 0.3, D / 2.0 - 0.01), Build.mat(Color(0.05, 0.3, 0.6), 0.5))
	Build.label(root, "MEISTERBÜRO", Vector3(sign_x, dh + 0.3, D / 2.0 - 0.025), 0.0028, Color.WHITE, 48, PI)
	# Schreibtisch, Monitor, Stuhl
	var desk := Build.mat(Color(0.9, 0.9, 0.88), 0.6)
	var dk := OFFICE_PC_POS
	Build.box(root, Vector3(1.6, 0.04, 0.8), Vector3(dk.x, 0.75, dk.z - 0.24), desk, true)
	Build.box(root, Vector3(0.04, 0.73, 0.7), Vector3(dk.x - 0.75, 0.37, dk.z - 0.24), frame)
	Build.box(root, Vector3(0.04, 0.73, 0.7), Vector3(dk.x + 0.75, 0.37, dk.z - 0.24), frame)
	Build.box(root, Vector3(0.6, 0.36, 0.03), Vector3(dk.x, dk.y, dk.z + 0.01), frame)
	Build.box(root, Vector3(0.56, 0.32, 0.005), Vector3(dk.x, dk.y, dk.z - 0.007), Build.emissive(Color(0.3, 0.5, 0.75), 1.2))
	Build.box(root, Vector3(0.08, 0.2, 0.05), Vector3(dk.x, 0.87, dk.z + 0.02), frame)
	Build.box(root, Vector3(0.42, 0.015, 0.14), Vector3(dk.x, 0.78, dk.z - 0.36), Build.mat(Color(0.15, 0.15, 0.16), 0.6))
	Build.box(root, Vector3(0.5, 0.08, 0.5), Vector3(dk.x, 0.48, dk.z - 1.0), Build.mat(Color(0.1, 0.1, 0.1), 0.7))
	Build.box(root, Vector3(0.5, 0.55, 0.06), Vector3(dk.x, 0.8, dk.z - 1.25), Build.mat(Color(0.1, 0.1, 0.1), 0.7))
	Build.cyl(root, 0.03, 0.42, Vector3(dk.x, 0.22, dk.z - 1.0), frame)
	# Aktenschrank mit Ordnern, Pflanze, Teppich, Tafel
	var cab := Build.mat(Color(0.75, 0.77, 0.78), 0.5, 0.2)
	Build.box(root, Vector3(0.42, 2.0, 1.4), Vector3(x0 + 0.21, 1.0, cz + 0.2), cab, true)
	var colors := [Color(0.1, 0.25, 0.55), Color(0.55, 0.12, 0.1), Color(0.15, 0.4, 0.2), Color(0.75, 0.6, 0.1)]
	for row in 3:
		for i in 9:
			Build.box(root, Vector3(0.02, 0.32, 0.1), Vector3(x0 + 0.43, 0.55 + row * 0.5, cz - 0.3 + i * 0.12), Build.mat(colors[(i + row) % 4], 0.7))
	Build.cyl(root, 0.18, 0.4, Vector3(x1 - 0.3, 0.2, z1 - 0.3), Build.mat(Color(0.85, 0.85, 0.85), 0.5))
	Build.sphere(root, 0.32, Vector3(x1 - 0.3, 0.7, z1 - 0.3), Build.mat(Color(0.2, 0.5, 0.2), 0.8))
	Build.box(root, Vector3(2.2, 0.006, 1.5), Vector3(dk.x, 0.004, dk.z - 1.0), Build.mat(Color(0.3, 0.33, 0.4), 0.95))
	Build.box(root, Vector3(0.02, 0.9, 1.5), Vector3(x1 - 0.01, 1.6, cz - 0.3), Build.mat(Color(0.95, 0.95, 0.93), 0.6))
	Build.box(root, Vector3(0.022, 0.5, 0.7), Vector3(x1 - 0.012, 1.65, cz - 0.6), Build.mat(Color(0.8, 0.72, 0.5), 0.8))
	# Deckenleuchte
	Build.box(root, Vector3(1.2, 0.04, 0.3), Vector3(cx, h - 0.03, cz), Build.emissive(Color(1.0, 0.98, 0.94), 3.0))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(cx, h - 0.4, cz)
	lamp.light_energy = 1.1
	lamp.omni_range = 6.5
	root.add_child(lamp)
	return lamp


## Fugen, Flecken, Abläufe und Warnstreifen.
static func _floor_details(root: Node3D) -> void:
	var joint := Build.mat(Color(0.22, 0.24, 0.24), 0.8)
	var x := -8.0
	while x < 12.0:
		Build.box(root, Vector3(0.012, 0.002, D), Vector3(x, 0.0011, 0), joint)
		x += 8.0
	for z in [-4.0, 4.0]:
		Build.box(root, Vector3(W, 0.002, 0.012), Vector3(0, 0.0013, z), joint)
	# Ölflecken
	var stain := Build.mat(Color(0.14, 0.15, 0.15, 0.3), 0.3)
	stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for s in [[-9.5, -1.5, 1.2, 0.8], [3.8, 0.4, 0.8, 1.1], [-3.0, 6.7, 1.4, 0.7], [9.5, -6.0, 1.0, 1.0], [-10.4, 6.2, 0.7, 0.9]]:
		Build.box(root, Vector3(s[2], 0.001, s[3]), Vector3(s[0], 0.0021, s[1]), stain)
	# Bodenablauf
	var steel := Build.mat(Color(0.3, 0.32, 0.33), 0.5, 0.6)
	for at in [Vector2(-4.0, 7.0), Vector2(4.0, -7.0)]:
		Build.box(root, Vector3(0.6, 0.004, 0.3), Vector3(at.x, 0.0024, at.y), steel)
		for i in 7:
			Build.box(root, Vector3(0.02, 0.003, 0.26), Vector3(at.x - 0.24 + i * 0.08, 0.0048, at.y), joint)
	# Warnstreifen vor dem Rolltor
	var yellow := Build.mat(Color(0.95, 0.75, 0.05), 0.6)
	var black := Build.mat(Color(0.07, 0.07, 0.08), 0.6)
	var z0 := DOOR_Z - RollDoor.WIDTH * 0.5
	var n := int(RollDoor.WIDTH / 0.3)
	for i in n:
		Build.box(root, Vector3(0.25, 0.003, 0.3), Vector3(W * 0.5 - 0.13, 0.0035, z0 + 0.15 + i * 0.3), yellow if i % 2 == 0 else black)
	# Pfeile auf dem Weg
	var white := Build.mat(Color(0.88, 0.88, 0.84), 0.7)
	var ax := -8.0
	while ax < 9.0:
		Build.box(root, Vector3(0.9, 0.003, 0.1), Vector3(ax, 0.0036, DOOR_Z), white)
		for s in [-1.0, 1.0]:
			Build.box(root, Vector3(0.4, 0.003, 0.1), Vector3(ax + 0.34, 0.0036, DOOR_Z + s * 0.12), white, false, Vector3(0, s * 0.7, 0))
		ax += 6.0


## Kabeltrasse, Druckluft, Schaltschränke, Lüftung, Anfahrschutz an den Stützen.
static func _wall_details(root: Node3D) -> void:
	var steel := Build.mat(Color(0.6, 0.62, 0.64), 0.4, 0.7)
	var grey := Build.mat(Color(0.72, 0.74, 0.74), 0.5, 0.2)
	var dark := Build.mat(Color(0.15, 0.16, 0.18), 0.6)
	var blue := Build.mat(Color(0.12, 0.35, 0.65), 0.45, 0.3)
	var yellow := Build.mat(Color(0.95, 0.75, 0.05), 0.5)
	var black := Build.mat(Color(0.07, 0.07, 0.08), 0.6)
	var north := -D * 0.5
	var south := D * 0.5
	# Kabeltrasse an der Nordwand unter den Fenstern, mit Abgängen zu den Schaltschränken
	Build.box(root, Vector3(W - 0.5, 0.05, 0.16), Vector3(0, 3.5, north + 0.12), steel)
	var bx := -11.0
	while bx < 12.0:
		Build.box(root, Vector3(0.03, 0.12, 0.2), Vector3(bx, 3.42, north + 0.1), dark)
		bx += 2.0
	for cx in [-9.5, -8.6, 3.6]:
		Build.box(root, Vector3(0.8, 1.9, 0.26), Vector3(cx, 1.15, north + 0.14), grey)
		Build.box(root, Vector3(0.01, 1.8, 0.01), Vector3(cx, 1.15, north + 0.275), dark)
		Build.box(root, Vector3(0.02, 0.12, 0.03), Vector3(cx + 0.06, 1.2, north + 0.285), dark)
		Build.box(root, Vector3(0.16, 0.14, 0.01), Vector3(cx - 0.2, 1.7, north + 0.275), yellow)
		Build.box(root, Vector3(0.1, 1.4, 0.05), Vector3(cx, 2.78, north + 0.1), steel)
	# Druckluftleitung an der Südwand mit Abgängen und Wartungseinheit
	Build.cyl(root, 0.022, W - 0.8, Vector3(0, 2.8, south - 0.1), blue, Build.AXIS_X, false, 12)
	for px in [-9.0, -3.0, 3.0]:
		Build.cyl(root, 0.012, 1.2, Vector3(px, 2.2, south - 0.1), blue, Build.AXIS_Y, false, 10)
		Build.box(root, Vector3(0.12, 0.18, 0.08), Vector3(px, 1.55, south - 0.09), grey)
		Build.cyl(root, 0.03, 0.06, Vector3(px, 1.42, south - 0.09), dark, Build.AXIS_Y, false, 10)
	for hx in [-10.0, -5.0, 0.0, 5.0, 10.0]:
		Build.box(root, Vector3(0.04, 0.08, 0.1), Vector3(hx, 2.8, south - 0.06), dark)
	# Steckdosenkästen
	for sx in [-6.0, 0.0, 6.0]:
		Build.box(root, Vector3(0.22, 0.28, 0.08), Vector3(sx + 1.3, 1.45, north + 0.05), blue)
		Build.box(root, Vector3(0.16, 0.08, 0.02), Vector3(sx + 1.3, 1.5, north + 0.1), dark)
	# Lüftungskanal unter der Decke
	Build.cyl(root, 0.26, W - 1.0, Vector3(0, 4.7, north + 1.35), steel, Build.AXIS_X, false, 20)
	var vx := -9.0
	while vx < 10.0:
		Build.box(root, Vector3(0.03, 1.0, 0.03), Vector3(vx, 5.45, north + 1.35), dark)
		Build.cyl(root, 0.27, 0.04, Vector3(vx, 4.7, north + 1.35), dark, Build.AXIS_X, false, 20)
		Build.box(root, Vector3(0.5, 0.03, 0.3), Vector3(vx + 1.5, 4.43, north + 1.35), grey)
		vx += 4.5
	# Anfahrschutz an den Stützen
	for x in range(-12, 13, 6):
		for z in [north + 0.2, south - 0.2]:
			for i in 4:
				Build.box(root, Vector3(0.34, 0.14, 0.34), Vector3(x, 0.07 + i * 0.14, z), yellow if i % 2 == 0 else black)
	# Fluchtweg-Schild über der Bürotür und Hinweistafeln
	Build.box(root, Vector3(1.3, 0.9, 0.02), Vector3(-7.0, 2.3, south - 0.012), Build.mat(Color(0.93, 0.93, 0.9), 0.7))
	Build.label(root, "Arbeitssicherheit\nGehörschutz  Schutzbrille\nSicherheitsschuhe", Vector3(-7.0, 2.3, south - 0.025), 0.0025, Color(0.1, 0.12, 0.16), 48, PI)
	Build.box(root, Vector3(0.5, 0.2, 0.02), Vector3(10.2, 3.1, south - 0.012), Build.emissive(Color(0.05, 0.6, 0.25), 0.7))


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
