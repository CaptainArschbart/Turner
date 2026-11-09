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
const WHITEBOARD_POS := Vector3(11.55, 1.5, 10.3)   # Whiteboard an der Ostwand des Büros
const WHITEBOARD_YAW := -PI / 2.0                    # beschriebene Seite zeigt nach Westen in den Raum
const CLOCK_POS := Vector3(5.44, 2.45, 10.65)        # Wanduhr über dem Aktenschrank
const CLOCK_YAW := PI / 2.0
const QM_X := Vector2(-0.8, 5.2)     # Raum fürs Qualitätsmanagement westlich vom Büro, von x bis x
const QM_DOOR_X := 1.0               # Scharnier der QM-Tür in der Südwand (zwischen Stütze und Druckluftabgang)


static func build(root: Node3D) -> Dictionary:
	var lights: Array = []
	var shadow_lights: Array = []

	var wall_mat := HallTex.wall()
	var wall_low := HallTex.concrete()
	var steel_blue := Build.mat(Color(0.20, 0.28, 0.36), 0.55, 0.3)
	var anth := Build.mat(Color(0.18, 0.19, 0.21), 0.6)
	var yellow := Build.mat(Color(0.95, 0.75, 0.05), 0.6)
	var ceiling := HallTex.ceiling()

	# ---------------- Boden (Epoxid-Beschichtung mit leichter Struktur)
	var floor_mat := HallTex.floor_mat(Vector2(W / 3.0, D / 3.0))
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
	# Südwand mit Öffnungen für die Bürotür und den Durchgang zum Qualitätsmanagement
	var ox0 := OFFICE_DOOR_X
	var ox1 := OFFICE_DOOR_X + OfficeDoor.WIDTH
	var qx0 := QM_DOOR_X
	var qx1 := QM_DOOR_X + OfficeDoor.WIDTH
	Build.box(root, Vector3(qx0 + W / 2, H, 0.3), Vector3((qx0 - W / 2) / 2, H / 2, D / 2 + 0.15), wall_mat, true)
	Build.box(root, Vector3(ox0 - qx1, H, 0.3), Vector3((qx1 + ox0) / 2, H / 2, D / 2 + 0.15), wall_mat, true)
	Build.box(root, Vector3(W / 2 - ox1, H, 0.3), Vector3((ox1 + W / 2) / 2, H / 2, D / 2 + 0.15), wall_mat, true)
	Build.box(root, Vector3(OfficeDoor.WIDTH, H - OfficeDoor.HEIGHT, 0.3), Vector3((ox0 + ox1) / 2, (H + OfficeDoor.HEIGHT) / 2, D / 2 + 0.15), wall_mat, true)
	Build.box(root, Vector3(OfficeDoor.WIDTH, H - OfficeDoor.HEIGHT, 0.3), Vector3((qx0 + qx1) / 2, (H + OfficeDoor.HEIGHT) / 2, D / 2 + 0.15), wall_mat, true)
	# Die Westseite baut das Gelände aus Kacheln
	# Ostwand mit Öffnung für das Rolltor
	var door_z0 := DOOR_Z - RollDoor.WIDTH / 2.0
	var door_z1 := DOOR_Z + RollDoor.WIDTH / 2.0
	Build.box(root, Vector3(0.3, H, door_z0 + D / 2), Vector3(W / 2 + 0.15, H / 2, (door_z0 - D / 2) / 2), wall_mat, true)
	Build.box(root, Vector3(0.3, H, D / 2 - door_z1), Vector3(W / 2 + 0.15, H / 2, (door_z1 + D / 2) / 2), wall_mat, true)
	Build.box(root, Vector3(0.3, H - RollDoor.HEIGHT, RollDoor.WIDTH), Vector3(W / 2 + 0.15, (H + RollDoor.HEIGHT) / 2, DOOR_Z), wall_mat, true)
	# Sockelpaneele
	Build.box(root, Vector3(W, 1.2, 0.04), Vector3(0, 0.6, -D / 2 + 0.02), wall_low)
	Build.box(root, Vector3(qx0 + W / 2, 1.2, 0.04), Vector3((qx0 - W / 2) / 2, 0.6, D / 2 - 0.02), wall_low)
	Build.box(root, Vector3(ox0 - qx1, 1.2, 0.04), Vector3((qx1 + ox0) / 2, 0.6, D / 2 - 0.02), wall_low)
	Build.box(root, Vector3(W / 2 - ox1, 1.2, 0.04), Vector3((ox1 + W / 2) / 2, 0.6, D / 2 - 0.02), wall_low)
	Build.box(root, Vector3(0.04, 1.2, door_z0 + D / 2), Vector3(W / 2 - 0.02, 0.6, (door_z0 - D / 2) / 2), wall_low)
	Build.box(root, Vector3(0.04, 1.2, D / 2 - door_z1), Vector3(W / 2 - 0.02, 0.6, (door_z1 + D / 2) / 2), wall_low)
	# Abschlussprofil auf dem Betonsockel
	var trim := Build.mat(Color(0.2, 0.22, 0.24), 0.45, 0.6)
	Build.box(root, Vector3(W, 0.05, 0.07), Vector3(0, 1.225, -D / 2 + 0.035), trim)
	for seg in [[-W / 2, qx0], [qx1, ox0], [ox1, W / 2]]:
		Build.box(root, Vector3(seg[1] - seg[0], 0.05, 0.07), Vector3((seg[0] + seg[1]) / 2, 1.225, D / 2 - 0.035), trim)
	for seg in [[-D / 2, door_z0], [door_z1, D / 2]]:
		Build.box(root, Vector3(0.07, 0.05, seg[1] - seg[0]), Vector3(W / 2 - 0.035, 1.225, (seg[0] + seg[1]) / 2), trim)
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
	crane.position = Vector3(-6.0, 0, 0)      # unter dem Dachträger, zwischen den Leuchtenseilen
	root.add_child(crane)
	Build.box(crane, Vector3(0.5, 0.6, 15.0), Vector3(0, 5.6, 0), yellow)
	Build.box(crane, Vector3(0.6, 0.45, 0.6), Vector3(0, 5.1, -1.5), anth)
	Build.cyl(crane, 0.015, 2.0, Vector3(0, 3.9, -1.5), Build.mat(Color(0.3, 0.3, 0.3), 0.4, 1.0))
	Build.box(crane, Vector3(0.12, 0.18, 0.06), Vector3(0, 2.85, -1.5), yellow)
	Build.label(crane, "5 t", Vector3(0.26, 5.6, 2.0), 0.01, Color(0.1, 0.1, 0.1), 64, PI / 2)

	# ---------------- Hallenleuchten aus models/non_machine_parts.glb: Röhre mit Schutzgitter, an zwei
	# Seilpaaren von der Decke. Mittig zwischen den Dachträgern, damit die Seile (±0,83 m) frei hängen.
	var led := Build.emissive(Color(1.0, 0.98, 0.94), 4.0)
	var lamp_h := 0.0
	for x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		for z in [-5.0, 0.0, 5.0]:
			var lamp := Props.make("ceiling_lamp")
			lamp_h = Props.bounds(lamp).size.y
			lamp.position = Vector3(x, H - lamp_h, z)          # Seile enden an der Decke
			root.add_child(lamp)
			for mi in lamp.find_children("*", "MeshInstance3D", true, false):
				for s in (mi as MeshInstance3D).mesh.get_surface_count():
					var mat := (mi as MeshInstance3D).mesh.surface_get_material(s)
					if mat and mat.resource_name == "emissive_light":
						(mi as MeshInstance3D).set_surface_override_material(s, led)
			var l := OmniLight3D.new()
			l.position = Vector3(x, H - lamp_h - 0.3, z)
			l.light_color = Color(1.0, 0.97, 0.92)
			l.light_energy = 0.9      # 15 Leuchten, tiefer als die alten Panels
			l.omni_range = 9.0
			l.omni_attenuation = 1.2
			root.add_child(l)
			lights.append(l)
			if (x == 0.0 and z == 0.0) or (x == -4.0 and z == 0.0) or (x == 4.0 and z == -5.0):
				shadow_lights.append(l)

	# ---------------- Einrichtung: Die Halle ist leer bis auf das, was an den Wänden und unter der Decke hängt
	lights.append(_office(root))
	lights.append(_qm_room(root))
	_wall_clock(root)
	_floor_details(root)
	_wall_details(root)
	Surroundings.build(root)

	return {"lights": lights, "shadow_lights": shadow_lights, "window_mat": sky, "window_light": window_light}


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
	# Außenhaut nur im Osten: Im Westen schließt der QM-Raum an, dort stünde das Blech im Raum
	Build.box(root, Vector3(0.02, h, z1 - z0), Vector3(x1 + 0.21, h * 0.5, cz), skin).layers = Site.OUTDOOR_LAYER
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
	# Rahmen ragt 1 cm in die Öffnung, sonst liegen seine Innenflächen genau auf den Wandkanten (Z-Fighting)
	for x in [dx0 - 0.025, dx1 + 0.025]:
		Build.box(root, Vector3(0.07, dh + 0.06, 0.34), Vector3(x, (dh + 0.06) * 0.5, D / 2.0 + 0.15), frame)
	Build.box(root, Vector3(OfficeDoor.WIDTH + 0.12, 0.07, 0.34), Vector3((dx0 + dx1) * 0.5, dh + 0.025, D / 2.0 + 0.15), frame)
	var sign_x := (dx0 + dx1) * 0.5
	Build.box(root, Vector3(1.0, 0.24, 0.02), Vector3(sign_x, dh + 0.3, D / 2.0 - 0.01), Build.mat(Color(0.05, 0.3, 0.6), 0.5))
	Build.label(root, "MEISTERBÜRO", Vector3(sign_x, dh + 0.3, D / 2.0 - 0.025), 0.0028, Color.WHITE, 48, PI)
	_office_interior(root, x0, x1, z0, z1, h, frame)
	# Zwei LED-Panels unter der Decke
	var panel_frame := Build.mat(Color(0.85, 0.86, 0.86), 0.4, 0.3)
	for px in [cx - 1.3, cx + 1.3]:
		Build.box(root, Vector3(0.66, 0.03, 0.66), Vector3(px, h - 0.015, cz), panel_frame)
		Build.box(root, Vector3(0.6, 0.012, 0.6), Vector3(px, h - 0.032, cz), Build.emissive(Color(1.0, 0.97, 0.9), 2.6))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(cx, h - 0.4, cz)
	lamp.light_energy = 1.1
	lamp.light_color = Color(1.0, 0.96, 0.9)
	lamp.omni_range = 6.5
	root.add_child(lamp)
	return lamp


## Raum fürs Qualitätsmanagement westlich vom Büro, durch eine Tür aus der Halle betretbar. Messtisch, Prüfplatz
## und Prüfmittelschrank setzt die Spielwelt als QualityStation, den Rest der Einrichtung baut _qm_interior.
## Gibt die Raumleuchte zurück.
static func _qm_room(root: Node3D) -> OmniLight3D:
	var x0 := QM_X.x
	var x1 := QM_X.y
	var z0 := D / 2.0 + 0.3
	var z1 := OFFICE_Z1
	var h := OFFICE_H
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var wall := Build.mat(Color(0.9, 0.91, 0.9), 0.85)
	var skin := Build.mat(Color(0.7, 0.73, 0.74), 0.8, 0.1)
	var frame := Build.mat(Color(0.2, 0.2, 0.22), 0.4, 0.5)
	var glass := Build.glass(Color(0.7, 0.85, 0.95, 0.2))
	# Heller Vinylboden wie in einem Messraum, er reicht bis in die Türöffnung, dazu feine Fugen
	Build.box(root, Vector3(x1 - x0 + 0.2, 0.4, z1 - D / 2.0 + 0.2), Vector3(cx, -0.2, (z1 + D / 2.0) * 0.5 + 0.1), Build.mat(Color(0.74, 0.77, 0.79), 0.4), true)
	var joint := Build.mat(Color(0.62, 0.65, 0.67), 0.5)
	var jx := x0 + 0.6
	while jx < x1 - 0.1:
		Build.box(root, Vector3(0.006, 0.0015, z1 - z0), Vector3(jx, 0.0008, cz), joint)
		jx += 0.6
	var jz := z0 + 0.6
	while jz < z1 - 0.1:
		Build.box(root, Vector3(x1 - x0, 0.0015, 0.006), Vector3(cx, 0.0009, jz), joint)
		jz += 0.6
	Build.box(root, Vector3(x1 - x0, 0.1, z1 - z0), Vector3(cx, h + 0.05, cz), Build.mat(Color(0.94, 0.94, 0.92), 0.9))
	var roof := Build.box(root, Vector3(x1 - x0 + 0.5, 0.1, z1 - z0 + 0.5), Vector3(cx - 0.05, h + 0.16, cz + 0.05), Build.mat(Color(0.3, 0.32, 0.34), 0.9))
	roof.layers = Site.OUTDOOR_LAYER
	# Westwand, die Ostwand ist die Bürowand
	Build.box(root, Vector3(0.2, h, z1 - z0), Vector3(x0 - 0.1, h * 0.5, cz), wall, true)
	Build.box(root, Vector3(0.02, h, z1 - z0), Vector3(x0 - 0.21, h * 0.5, cz), skin).layers = Site.OUTDOOR_LAYER
	# Südwand mit Fenster hinter der Messmaschine
	var wx0 := -0.3
	var wx1 := 1.2
	var wxc := (wx0 + wx1) * 0.5
	var sy0 := 0.95
	var sy1 := 2.25
	for t in [[x0 - 0.2, wx0], [wx1, x1]]:
		Build.box(root, Vector3(t[1] - t[0], h, 0.2), Vector3((t[0] + t[1]) * 0.5, h * 0.5, z1 + 0.1), wall, true)
	Build.box(root, Vector3(wx1 - wx0, sy0, 0.2), Vector3(wxc, sy0 * 0.5, z1 + 0.1), wall, true)
	Build.box(root, Vector3(wx1 - wx0, h - sy1, 0.2), Vector3(wxc, (h + sy1) * 0.5, z1 + 0.1), wall)
	Build.box(root, Vector3(wx1 - wx0, sy1 - sy0, 0.03), Vector3(wxc, (sy0 + sy1) * 0.5, z1 + 0.1), glass, true)
	for x in [wx0, wxc, wx1]:
		Build.box(root, Vector3(0.05, sy1 - sy0, 0.06), Vector3(x, (sy0 + sy1) * 0.5, z1 + 0.1), frame)
	for y in [sy0, sy1]:
		Build.box(root, Vector3(wx1 - wx0 + 0.05, 0.05, 0.06), Vector3(wxc, y, z1 + 0.1), frame)
	Build.box(root, Vector3(wx1 - wx0 + 0.1, 0.03, 0.16), Vector3(wxc, sy0 - 0.03, z1 - 0.04), Build.mat(Color(0.95, 0.95, 0.93), 0.5))
	for t in [[x0 - 0.3, wx0], [wx1, x1 + 0.1]]:
		Build.box(root, Vector3(t[1] - t[0], h, 0.02), Vector3((t[0] + t[1]) * 0.5, h * 0.5, z1 + 0.21), skin).layers = Site.OUTDOOR_LAYER
	Build.box(root, Vector3(wx1 - wx0, sy0, 0.02), Vector3(wxc, sy0 * 0.5, z1 + 0.21), skin).layers = Site.OUTDOOR_LAYER
	Build.box(root, Vector3(wx1 - wx0, h - sy1, 0.02), Vector3(wxc, (h + sy1) * 0.5, z1 + 0.21), skin).layers = Site.OUTDOOR_LAYER
	# Tür in der Hallenwand mit Rahmen und Schild
	var door := OfficeDoor.new()
	door.title = "Tür zum Qualitätsmanagement"
	door.tint = Color(0.8, 0.87, 0.83)
	door.position = Vector3(QM_DOOR_X, 0, D / 2.0 + 0.15)
	root.add_child(door)
	var dx0 := QM_DOOR_X
	var dx1 := QM_DOOR_X + OfficeDoor.WIDTH
	var dh := OfficeDoor.HEIGHT
	for x in [dx0 - 0.025, dx1 + 0.025]:
		Build.box(root, Vector3(0.07, dh + 0.06, 0.34), Vector3(x, (dh + 0.06) * 0.5, D / 2.0 + 0.15), frame)
	Build.box(root, Vector3(OfficeDoor.WIDTH + 0.12, 0.07, 0.34), Vector3((dx0 + dx1) * 0.5, dh + 0.025, D / 2.0 + 0.15), frame)
	var sign_x := (dx0 + dx1) * 0.5
	Build.box(root, Vector3(1.9, 0.24, 0.02), Vector3(sign_x, dh + 0.3, D / 2.0 - 0.01), Build.mat(Color(0.08, 0.5, 0.28), 0.5))
	Build.label(root, "QUALITÄTSMANAGEMENT", Vector3(sign_x, dh + 0.3, D / 2.0 - 0.025), 0.0026, Color.WHITE, 48, PI)
	# Innen ist die Hallenwand verputzt, mit Lücke für die Tür
	var lz := z0 + 0.01
	for t in [[x0, dx0 - 0.065], [dx1 + 0.065, x1]]:
		Build.box(root, Vector3(t[1] - t[0], h, 0.02), Vector3((t[0] + t[1]) * 0.5, h * 0.5, lz), wall)
	Build.box(root, Vector3(dx1 - dx0 + 0.13, h - dh - 0.06, 0.02), Vector3(sign_x, (h + dh + 0.06) * 0.5, lz), wall)
	# Sockelleisten
	var skirt := Build.mat(Color(0.3, 0.3, 0.32), 0.6)
	Build.box(root, Vector3(0.02, 0.08, z1 - z0), Vector3(x0 + 0.01, 0.04, cz), skirt)
	Build.box(root, Vector3(0.02, 0.08, z1 - z0), Vector3(x1 - 0.01, 0.04, cz), skirt)
	Build.box(root, Vector3(x1 - x0, 0.08, 0.02), Vector3(cx, 0.04, z1 - 0.01), skirt)
	for t in [[x0, dx0 - 0.065], [dx1 + 0.065, x1]]:
		Build.box(root, Vector3(t[1] - t[0], 0.08, 0.02), Vector3((t[0] + t[1]) * 0.5, 0.04, lz + 0.02), skirt)
	_qm_interior(root, x0, x1, z0, z1)
	# Vier LED-Panels: Im Messraum ist es hell
	var panel_frame := Build.mat(Color(0.85, 0.86, 0.86), 0.4, 0.3)
	var led := Build.emissive(Color(0.95, 0.98, 1.0), 2.8)
	for px in [cx - 1.6, cx + 1.6]:
		for pz in [cz - 1.0, cz + 1.0]:
			Build.box(root, Vector3(0.66, 0.03, 0.66), Vector3(px, h - 0.015, pz), panel_frame)
			Build.box(root, Vector3(0.6, 0.012, 0.6), Vector3(px, h - 0.032, pz), led)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(cx, h - 0.4, cz)
	lamp.light_energy = 1.35
	lamp.light_color = Color(0.96, 0.98, 1.0)
	lamp.omni_range = 7.5
	root.add_child(lamp)
	return lamp


## Einrichtung des QM-Raums neben der QualityStation: Koordinatenmessmaschine vor dem Fenster, Ordnerregal,
## Thermo-Hygrometer, Regelkarte und Zertifikat an der Bürowand, Ausschussbehälter, Stuhl, Pflanze, Fußmatte.
static func _qm_interior(root: Node3D, x0: float, x1: float, z0: float, z1: float) -> void:
	var granite := Build.mat(Color(0.16, 0.17, 0.18), 0.3, 0.1)
	var steel := Build.mat(Color(0.5, 0.53, 0.56), 0.5, 0.4)
	var white := Build.mat(Color(0.93, 0.94, 0.93), 0.5)
	var dark := Build.mat(Color(0.09, 0.09, 0.1), 0.6)
	var chrome := Build.mat(Color(0.8, 0.81, 0.83), 0.2, 0.9)
	var blue := Build.mat(Color(0.1, 0.32, 0.62), 0.5)
	var green := Build.mat(Color(0.08, 0.5, 0.28), 0.5)
	var red := Build.mat(Color(0.75, 0.1, 0.08), 0.55)
	var paper := Build.mat(Color(0.97, 0.97, 0.95), 0.9)
	var oak := Build.mat(Color(0.62, 0.45, 0.28), 0.55)

	# ---- Koordinatenmessmaschine (Portalbauweise) vor dem Fenster
	var k := Vector3(0.35, 0, z1 - 0.85)
	Build.box(root, Vector3(1.15, 0.7, 0.8), Vector3(k.x, 0.35, k.z), Build.mat(Color(0.62, 0.65, 0.68), 0.5, 0.3))
	Build.box(root, Vector3(1.16, 0.05, 0.81), Vector3(k.x, 0.69, k.z), blue)
	Build.box(root, Vector3(1.3, 0.18, 0.95), Vector3(k.x, 0.79, k.z), granite)
	var top := 0.88
	# Führungsschiene hinten, Portal mit zwei Füßen, Brücke, Schlitten und Pinole mit Taster
	Build.box(root, Vector3(0.06, 0.03, 0.9), Vector3(k.x + 0.6, top + 0.015, k.z), chrome)
	var py := k.z + 0.05
	for sx in [-0.58, 0.58]:
		Build.box(root, Vector3(0.09, 0.72, 0.14), Vector3(k.x + sx, top + 0.36, py), white)
	Build.box(root, Vector3(1.3, 0.14, 0.16), Vector3(k.x, top + 0.79, py), white)
	Build.box(root, Vector3(1.3, 0.03, 0.005), Vector3(k.x, top + 0.79, py - 0.083), blue)
	Build.label(root, "KMM", Vector3(k.x - 0.3, top + 0.79, py - 0.095), 0.0018, Color.WHITE, 48, PI)
	var cxk := k.x + 0.15
	Build.box(root, Vector3(0.2, 0.24, 0.24), Vector3(cxk, top + 0.79, py - 0.02), white)
	Build.box(root, Vector3(0.07, 0.62, 0.07), Vector3(cxk, top + 0.5, py - 0.1), chrome)
	Build.box(root, Vector3(0.05, 0.06, 0.05), Vector3(cxk, top + 0.16, py - 0.1), dark)
	Build.cyl(root, 0.004, 0.07, Vector3(cxk, top + 0.1, py - 0.1), chrome)
	Build.sphere(root, 0.009, Vector3(cxk, top + 0.062, py - 0.1), red)
	# Werkstück auf der Platte und Bedienpult mit Joystick
	Build.cyl(root, 0.055, 0.05, Vector3(cxk, top + 0.025, py - 0.1), chrome)
	Build.box(root, Vector3(0.2, 0.04, 0.13), Vector3(k.x - 0.4, top + 0.02, k.z - 0.3), dark)
	Build.cyl(root, 0.008, 0.06, Vector3(k.x - 0.43, top + 0.07, k.z - 0.3), dark)
	Build.box(root, Vector3(0.05, 0.002, 0.03), Vector3(k.x - 0.35, top + 0.041, k.z - 0.3), Build.emissive(Color(0.2, 1.0, 0.4), 1.2))
	Build.collider(root, Vector3(1.3, 1.75, 0.95), Vector3(k.x, 0.875, k.z))

	# ---- Ordnerregal an der Westwand mit Prüfberichten
	var rx := x0 + 0.2
	var rz0 := z0 + 0.55
	var rz1 := rz0 + 1.6
	var rcz := (rz0 + rz1) * 0.5
	for z in [rz0, rz1]:
		Build.box(root, Vector3(0.38, 2.0, 0.03), Vector3(rx, 1.0, z), steel)
	var binders: Array[Color] = [Color(0.1, 0.3, 0.65), Color(0.85, 0.2, 0.15), Color(0.95, 0.75, 0.1),
			Color(0.1, 0.5, 0.28), Color(0.15, 0.15, 0.17), Color(0.92, 0.92, 0.9)]
	for i in 5:
		var by := 0.08 + i * 0.44
		Build.box(root, Vector3(0.38, 0.025, rz1 - rz0), Vector3(rx, by, rcz), steel)
		if i == 0 or i == 4:
			continue
		var z := rz0 + 0.06
		var n := 0
		while z < rz1 - 0.12:
			var bc: Color = binders[(i * 3 + n * 5) % binders.size()]
			var tall := 0.32 if n % 4 != 3 else 0.28
			Build.box(root, Vector3(0.3, tall, 0.075), Vector3(rx + 0.02, by + 0.0125 + tall * 0.5, z + 0.04), Build.mat(bc, 0.6))
			Build.box(root, Vector3(0.002, 0.07, 0.045), Vector3(rx + 0.171, by + 0.2, z + 0.04), paper)
			z += 0.08
			n += 1
			if n % 7 == 0:
				z += 0.12
	Build.box(root, Vector3(0.01, 0.1, 0.5), Vector3(rx + 0.195, 1.9, rcz), white)
	Build.label(root, "Prüfberichte", Vector3(rx + 0.201, 1.9, rcz), 0.0012, Color(0.15, 0.17, 0.2), 48, PI / 2)
	Build.collider(root, Vector3(0.4, 2.0, rz1 - rz0), Vector3(rx, 1.0, rcz))

	# ---- Thermo-Hygrometer und Hinweis an der Westwand: Gemessen wird bei 20 °C
	var tz := rz1 + 0.5
	Build.box(root, Vector3(0.03, 0.16, 0.12), Vector3(x0 + 0.015, 1.6, tz), white)
	Build.box(root, Vector3(0.002, 0.09, 0.09), Vector3(x0 + 0.031, 1.61, tz), Build.emissive(Color(0.75, 0.85, 0.75), 0.4))
	Build.label(root, "20,1 °C\n46 %", Vector3(x0 + 0.033, 1.61, tz), 0.0008, Color(0.05, 0.1, 0.05), 40, PI / 2)
	Build.box(root, Vector3(0.01, 0.2, 0.95), Vector3(x0 + 0.005, 1.95, tz), green)
	Build.label(root, "MESSRAUM · 20 °C", Vector3(x0 + 0.011, 1.95, tz), 0.0016, Color.WHITE, 48, PI / 2)

	# ---- Pflanze in der Ecke neben der Messmaschine
	_plant(root, Vector3(x0 + 0.3, 0, z1 - 1.65), 0.85, 1.1)

	# ---- Regelkarte (SPC) und Zertifikat an der Bürowand
	var ex := x1 - 0.012
	var rc := Vector3(ex, 1.6, z0 + 1.5)
	Build.box(root, Vector3(0.02, 0.86, 1.3), rc, Build.mat(Color(0.75, 0.77, 0.8), 0.4, 0.5))
	Build.box(root, Vector3(0.004, 0.8, 1.24), rc + Vector3(-0.012, 0, 0), paper)
	var face := ex - 0.016
	var chart_w := 1.0
	var c0 := rc.z - chart_w * 0.5     # Anfang der Karte: Vom Raum aus (Blick nach +X) liegt -Z links
	Build.box(root, Vector3(0.002, 0.008, chart_w), Vector3(face, rc.y - 0.05, rc.z), green)
	for e in [-1.0, 1.0]:
		Build.box(root, Vector3(0.002, 0.006, chart_w), Vector3(face, rc.y - 0.05 + e * 0.22, rc.z), red)
	var vals := [0.02, -0.06, 0.08, 0.03, -0.1, 0.05, 0.12, -0.02, -0.08, 0.04, 0.1, -0.04, 0.0]
	var step := chart_w / float(vals.size() - 1)
	for i in vals.size():
		var pz := c0 + i * step
		var vy := rc.y - 0.05 + float(vals[i])
		Build.box(root, Vector3(0.003, 0.018, 0.018), Vector3(face - 0.001, vy, pz), blue)
		if i > 0:
			var qz := pz - step
			var qy := rc.y - 0.05 + float(vals[i - 1])
			var dy := vy - qy
			var seg := sqrt(step * step + dy * dy)
			Build.box(root, Vector3(0.002, 0.005, seg), Vector3(face, (vy + qy) * 0.5, (pz + qz) * 0.5), blue, false, Vector3(atan2(-dy, step), 0, 0))
	Build.label(root, "Regelkarte  Ø40 h6", Vector3(face - 0.002, rc.y + 0.3, rc.z), 0.0013, Color(0.1, 0.12, 0.16), 48, -PI / 2)
	Build.label(root, "OEG", Vector3(face - 0.002, rc.y + 0.19, rc.z - 0.56), 0.0008, Color(0.7, 0.1, 0.08), 40, -PI / 2)
	Build.label(root, "UEG", Vector3(face - 0.002, rc.y - 0.29, rc.z - 0.56), 0.0008, Color(0.7, 0.1, 0.08), 40, -PI / 2)
	# Zertifikat im Rahmen
	var cert := Vector3(ex, 1.65, z0 + 2.75)
	Build.box(root, Vector3(0.025, 0.5, 0.38), cert, oak)
	Build.box(root, Vector3(0.004, 0.44, 0.32), cert + Vector3(-0.014, 0, 0), paper)
	Build.label(root, "ZERTIFIKAT\n\nDIN EN ISO\n9001", cert + Vector3(-0.017, 0.04, 0), 0.0011, Color(0.1, 0.2, 0.45), 40, -PI / 2)
	Build.sphere(root, 0.025, cert + Vector3(-0.016, -0.15, 0), Build.mat(Color(0.85, 0.65, 0.15), 0.3, 0.8))

	# ---- Roter Ausschussbehälter: Sperrteile gehen nicht zurück in die Fertigung
	var sb := Vector3(x1 - 0.4, 0, z0 + 0.45)
	Build.box(root, Vector3(0.5, 0.02, 0.45), sb + Vector3(0, 0.06, 0), red)
	for e in [-1.0, 1.0]:
		Build.box(root, Vector3(0.5, 0.42, 0.02), sb + Vector3(0, 0.27, e * 0.215), red)
		Build.box(root, Vector3(0.02, 0.42, 0.45), sb + Vector3(e * 0.24, 0.27, 0), red)
	for sx in [-0.2, 0.2]:
		for sz in [-0.17, 0.17]:
			Build.cyl(root, 0.03, 0.03, sb + Vector3(sx, 0.03, sz), dark, Build.AXIS_X)
	Build.box(root, Vector3(0.002, 0.12, 0.34), sb + Vector3(-0.251, 0.33, 0), Build.mat(Color(0.98, 0.85, 0.1), 0.5))
	Build.label(root, "AUSSCHUSS\nSperrteile", sb + Vector3(-0.253, 0.33, 0), 0.0011, Color(0.1, 0.05, 0.05), 40, -PI / 2)
	Build.collider(root, Vector3(0.5, 0.48, 0.45), sb + Vector3(0, 0.24, 0))

	# ---- Bürostuhl vor dem Prüfplatz
	var ch := QualityStation.POS + Vector3(1.05, 0, -0.5)
	var cushion := Build.mat(Color(0.13, 0.14, 0.16), 0.85)
	Build.box(root, Vector3(0.46, 0.08, 0.44), ch + Vector3(0, 0.48, 0), cushion)
	Build.box(root, Vector3(0.44, 0.5, 0.06), ch + Vector3(0, 0.82, -0.22), cushion, false, Vector3(-0.12, 0, 0))
	Build.cyl(root, 0.025, 0.36, ch + Vector3(0, 0.26, 0), chrome)
	for i in 5:
		var a := TAU * i / 5.0
		Build.box(root, Vector3(0.03, 0.03, 0.3), ch + Vector3(sin(a) * 0.14, 0.06, cos(a) * 0.14), dark, false, Vector3(0, a, 0))
		Build.sphere(root, 0.025, ch + Vector3(sin(a) * 0.28, 0.025, cos(a) * 0.28), dark)

	# ---- Fußmatte hinter der Tür
	Build.box(root, Vector3(1.0, 0.006, 0.6), Vector3(QM_DOOR_X + OfficeDoor.WIDTH * 0.5, 0.003, z0 + 0.45), Build.mat(Color(0.2, 0.22, 0.24), 0.95))


## Einrichtung des Meisterbüros: Schreibtisch mit PC, Aktenschrank, Sideboard mit Kaffeemaschine,
## Pinnwand, Urkunden, Garderobe, Drucker, Pflanzen und Teppich. Das Whiteboard und die Uhr setzt die Spielwelt.
static func _office_interior(root: Node3D, x0: float, x1: float, z0: float, z1: float, h: float, frame: Material) -> void:
	var cz := (z0 + z1) * 0.5
	var white := Build.mat(Color(0.93, 0.93, 0.91), 0.55)
	var oak := Build.mat(Color(0.62, 0.45, 0.28), 0.55)
	var black := Build.mat(Color(0.09, 0.09, 0.1), 0.6)
	var chrome := Build.mat(Color(0.75, 0.76, 0.78), 0.25, 0.9)
	var paper := Build.mat(Color(0.96, 0.96, 0.94), 0.9)

	# Sockelleisten, an der Hallenwand mit Lücke für die Tür
	var skirt := Build.mat(Color(0.3, 0.3, 0.32), 0.6)
	Build.box(root, Vector3(0.02, 0.08, z1 - z0), Vector3(x0 + 0.01, 0.04, cz), skirt)
	Build.box(root, Vector3(0.02, 0.08, z1 - z0), Vector3(x1 - 0.01, 0.04, cz), skirt)
	Build.box(root, Vector3(x1 - x0, 0.08, 0.02), Vector3((x0 + x1) * 0.5, 0.04, z1 - 0.01), skirt)
	Build.box(root, Vector3(OFFICE_DOOR_X - 0.05 - x0, 0.08, 0.02), Vector3((x0 + OFFICE_DOOR_X - 0.05) * 0.5, 0.04, z0 + 0.01), skirt)
	var dx1 := OFFICE_DOOR_X + OfficeDoor.WIDTH + 0.05
	Build.box(root, Vector3(x1 - dx1, 0.08, 0.02), Vector3((dx1 + x1) * 0.5, 0.04, z0 + 0.01), skirt)

	# Schreibtisch mit Stuhl und Rollcontainer aus dem Modell (Bedienerseite -Z), darauf Monitor,
	# Tastatur, Maus, Lampe, Tasse, Papierstapel und Telefon
	var dk := OFFICE_PC_POS
	var top_z := dk.z - 0.2
	var desk := Props.make("desk")
	desk.position = Vector3(dk.x, 0, top_z)
	desk.rotation.y = PI
	root.add_child(desk)
	Build.collider(root, Vector3(1.5, 0.78, 0.6), Vector3(dk.x, 0.39, top_z))
	Build.box(root, Vector3(0.6, 0.36, 0.03), Vector3(dk.x, dk.y, dk.z + 0.01), frame)
	Build.box(root, Vector3(0.56, 0.32, 0.005), Vector3(dk.x, dk.y, dk.z - 0.007), Build.emissive(Color(0.3, 0.5, 0.75), 1.2))
	Build.box(root, Vector3(0.08, 0.2, 0.05), Vector3(dk.x, 0.87, dk.z + 0.02), frame)
	Build.box(root, Vector3(0.24, 0.012, 0.16), Vector3(dk.x, 0.788, dk.z + 0.02), frame)
	Build.box(root, Vector3(0.42, 0.015, 0.14), Vector3(dk.x, 0.79, dk.z - 0.36), Build.mat(Color(0.15, 0.15, 0.16), 0.6))
	Build.box(root, Vector3(0.22, 0.004, 0.18), Vector3(dk.x + 0.36, 0.784, dk.z - 0.36), black)
	Build.box(root, Vector3(0.06, 0.02, 0.1), Vector3(dk.x + 0.36, 0.795, dk.z - 0.36), Build.mat(Color(0.2, 0.2, 0.22), 0.5))
	# Schreibtischlampe links
	var lx := dk.x - 0.62
	var lz := dk.z - 0.05
	Build.cyl(root, 0.07, 0.02, Vector3(lx, 0.792, lz), black, Build.AXIS_Y, false, 16)
	Build.box(root, Vector3(0.015, 0.36, 0.015), Vector3(lx, 0.97, lz - 0.06), black, false, Vector3(-0.35, 0, 0))
	Build.box(root, Vector3(0.015, 0.26, 0.015), Vector3(lx, 1.17, lz - 0.2), black, false, Vector3(0.9, 0, 0))
	Build.cyl(root, 0.06, 0.1, Vector3(lx, 1.15, lz - 0.32), black, Build.AXIS_Y, false, 16, 0.03)
	Build.cyl(root, 0.055, 0.005, Vector3(lx, 1.1, lz - 0.32), Build.emissive(Color(1.0, 0.9, 0.7), 2.0), Build.AXIS_Y, false, 16)
	var desk_lamp := OmniLight3D.new()
	desk_lamp.position = Vector3(lx, 1.02, lz - 0.32)
	desk_lamp.light_color = Color(1.0, 0.88, 0.7)
	desk_lamp.light_energy = 0.5
	desk_lamp.omni_range = 1.4
	root.add_child(desk_lamp)
	# Tasse, Papierstapel, Telefon
	Build.cyl(root, 0.04, 0.09, Vector3(dk.x - 0.42, 0.827, dk.z - 0.42), Build.mat(Color(0.75, 0.15, 0.12), 0.4), Build.AXIS_Y, false, 16)
	Build.cyl(root, 0.034, 0.005, Vector3(dk.x - 0.42, 0.87, dk.z - 0.42), Build.mat(Color(0.2, 0.12, 0.06), 0.2), Build.AXIS_Y, false, 16)
	for i in 6:
		Build.box(root, Vector3(0.21, 0.006, 0.297), Vector3(dk.x + 0.58 + i * 0.002, 0.787 + i * 0.006, dk.z - 0.15), paper, false, Vector3(0, 0.04 * (i % 3) - 0.04, 0))
	Build.box(root, Vector3(0.18, 0.05, 0.2), Vector3(dk.x + 0.6, 0.805, dk.z - 0.42), black, false, Vector3(0.12, 0, 0))
	Build.box(root, Vector3(0.05, 0.035, 0.19), Vector3(dk.x + 0.55, 0.845, dk.z - 0.42), Build.mat(Color(0.15, 0.15, 0.16), 0.5))
	# Papierkorb neben dem Tisch
	Build.cyl(root, 0.14, 0.32, Vector3(dk.x - 1.02, 0.16, dk.z + 0.05), Build.mat(Color(0.25, 0.27, 0.3), 0.5, 0.4), Build.AXIS_Y, false, 20, 0.16)
	Build.sphere(root, 0.05, Vector3(dk.x - 1.0, 0.3, dk.z + 0.07), paper)

	# Teppich mit Rand
	Build.box(root, Vector3(2.4, 0.006, 1.7), Vector3(dk.x - 0.1, 0.003, dk.z - 0.95), Build.mat(Color(0.55, 0.16, 0.12), 0.95))
	Build.box(root, Vector3(2.2, 0.006, 1.5), Vector3(dk.x - 0.1, 0.005, dk.z - 0.95), Build.mat(Color(0.2, 0.24, 0.34), 0.95))

	# Aktenschrank mit Ordnern und Beschriftung, oben Kartons
	var cab := Build.mat(Color(0.75, 0.77, 0.78), 0.5, 0.2)
	var cab_z := cz + 0.2
	Build.box(root, Vector3(0.42, 2.0, 1.4), Vector3(x0 + 0.21, 1.0, cab_z), cab, true)
	var colors := [Color(0.1, 0.25, 0.55), Color(0.55, 0.12, 0.1), Color(0.15, 0.4, 0.2), Color(0.75, 0.6, 0.1)]
	for row in 3:
		Build.box(root, Vector3(0.012, 0.02, 1.32), Vector3(x0 + 0.43, 0.38 + row * 0.5, cab_z), cab)
		for i in 9:
			var fx := x0 + 0.43
			var fz := cab_z - 0.5 + i * 0.12
			Build.box(root, Vector3(0.02, 0.32, 0.1), Vector3(fx, 0.55 + row * 0.5, fz), Build.mat(colors[(i + row) % 4], 0.7))
			Build.box(root, Vector3(0.022, 0.08, 0.06), Vector3(fx, 0.6 + row * 0.5, fz), paper)
			Build.cyl(root, 0.012, 0.022, Vector3(fx, 0.47 + row * 0.5, fz), black, Build.AXIS_X, false, 8)
	Build.box(root, Vector3(0.36, 0.24, 0.5), Vector3(x0 + 0.2, 2.12, cab_z - 0.3), Build.mat(Color(0.7, 0.55, 0.36), 0.9))
	Build.box(root, Vector3(0.34, 0.18, 0.42), Vector3(x0 + 0.2, 2.09, cab_z + 0.3), Build.mat(Color(0.65, 0.5, 0.33), 0.9))

	# Garderobe in der Ecke neben der Tür mit Jacke und Helm
	var cr := Vector3(x0 + 0.4, 0, z0 + 0.4)
	Build.cyl(root, 0.2, 0.03, Vector3(cr.x, 0.015, cr.z), black, Build.AXIS_Y, false, 20)
	Build.cyl(root, 0.022, 1.8, Vector3(cr.x, 0.9, cr.z), black)
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		Build.box(root, Vector3(0.016, 0.016, 0.16), Vector3(cr.x + sin(a) * 0.07, 1.72, cr.z + cos(a) * 0.07), black, false, Vector3(-0.6, a, 0))
	Build.box(root, Vector3(0.36, 0.72, 0.12), Vector3(cr.x + 0.05, 1.32, cr.z + 0.1), Build.mat(Color(0.12, 0.28, 0.5), 0.9), false, Vector3(0, 0.6, 0.05))
	Build.box(root, Vector3(0.38, 0.1, 0.14), Vector3(cr.x + 0.05, 1.64, cr.z + 0.1), Build.mat(Color(0.95, 0.5, 0.1), 0.8), false, Vector3(0, 0.6, 0.05))
	var helmet := Build.sphere(root, 0.13, Vector3(cr.x - 0.05, 1.8, cr.z - 0.08), Build.mat(Color(0.95, 0.8, 0.1), 0.45))
	helmet.scale = Vector3(1.0, 0.7, 1.15)

	# Sideboard an der Hallenwand mit Kaffeemaschine, Tassen und Wasserkiste
	var sb_x := x1 - 1.05
	var sb_z := z0 + 0.25
	Build.box(root, Vector3(1.5, 0.78, 0.45), Vector3(sb_x, 0.39, sb_z), white, true)
	Build.box(root, Vector3(1.54, 0.03, 0.48), Vector3(sb_x, 0.795, sb_z + 0.01), oak)
	for i in 3:
		Build.box(root, Vector3(0.48, 0.7, 0.004), Vector3(sb_x - 0.5 + i * 0.5, 0.39, sb_z + 0.227), Build.mat(Color(0.88, 0.88, 0.86), 0.5))
		Build.box(root, Vector3(0.015, 0.14, 0.02), Vector3(sb_x - 0.29 + i * 0.5, 0.5, sb_z + 0.24), chrome)
	var km := Vector3(sb_x - 0.4, 0.81, sb_z)
	Build.box(root, Vector3(0.28, 0.38, 0.36), Vector3(km.x, km.y + 0.19, km.z - 0.02), black)
	Build.box(root, Vector3(0.28, 0.05, 0.3), Vector3(km.x, km.y + 0.4, km.z - 0.02), Build.mat(Color(0.2, 0.2, 0.22), 0.3, 0.6))
	Build.box(root, Vector3(0.2, 0.03, 0.12), Vector3(km.x, km.y + 0.015, km.z + 0.12), chrome)
	Build.box(root, Vector3(0.1, 0.06, 0.03), Vector3(km.x, km.y + 0.3, km.z + 0.17), Build.emissive(Color(0.3, 0.7, 1.0), 1.0))
	Build.cyl(root, 0.03, 0.07, Vector3(km.x, km.y + 0.065, km.z + 0.12), white, Build.AXIS_Y, false, 12)
	for i in 4:
		Build.cyl(root, 0.035, 0.08, Vector3(sb_x + 0.0 + (i % 2) * 0.09, 0.85, sb_z - 0.08 + floorf(i / 2.0) * 0.1), Build.mat(colors[i], 0.4), Build.AXIS_Y, false, 12)
	Build.box(root, Vector3(0.3, 0.04, 0.2), Vector3(sb_x + 0.5, 0.83, sb_z), Build.mat(Color(0.75, 0.75, 0.73), 0.4, 0.5))
	for i in 3:
		Build.cyl(root, 0.035, 0.26, Vector3(sb_x + 0.4 + i * 0.1, 0.98, sb_z), Build.glass(Color(0.6, 0.8, 0.95, 0.45)), Build.AXIS_Y, false, 12)
		Build.cyl(root, 0.017, 0.03, Vector3(sb_x + 0.4 + i * 0.1, 1.125, sb_z), Build.mat(Color(0.1, 0.4, 0.8), 0.5), Build.AXIS_Y, false, 10)
	# Wandregal darüber mit Ordnern und Pokal
	var shelf_y := 1.75
	Build.box(root, Vector3(1.4, 0.03, 0.26), Vector3(sb_x, shelf_y, z0 + 0.13), oak)
	for sx in [-0.6, 0.6]:
		Build.box(root, Vector3(0.02, 0.14, 0.2), Vector3(sb_x + sx, shelf_y - 0.08, z0 + 0.1), black)
	for i in 7:
		Build.box(root, Vector3(0.07, 0.31, 0.24), Vector3(sb_x - 0.6 + i * 0.075, shelf_y + 0.17, z0 + 0.14), Build.mat(colors[i % 4], 0.7))
		Build.box(root, Vector3(0.05, 0.08, 0.002), Vector3(sb_x - 0.6 + i * 0.075, shelf_y + 0.22, z0 + 0.262), paper)
	var gold := Build.mat(Color(0.9, 0.7, 0.2), 0.25, 0.9)
	Build.box(root, Vector3(0.12, 0.05, 0.12), Vector3(sb_x + 0.35, shelf_y + 0.04, z0 + 0.14), black)
	Build.cyl(root, 0.012, 0.1, Vector3(sb_x + 0.35, shelf_y + 0.11, z0 + 0.14), gold)
	Build.cyl(root, 0.06, 0.12, Vector3(sb_x + 0.35, shelf_y + 0.22, z0 + 0.14), gold, Build.AXIS_Y, false, 16, 0.025)
	_plant(root, Vector3(sb_x + 0.53, shelf_y + 0.015, z0 + 0.14), 0.16, 0.5)

	# Pinnwand neben der Tür mit Zetteln und einer Zeichnung
	var pw_x := OFFICE_DOOR_X + OfficeDoor.WIDTH + 0.6
	Build.box(root, Vector3(0.8, 0.6, 0.02), Vector3(pw_x, 1.55, z0 + 0.012), Build.mat(Color(0.72, 0.56, 0.36), 0.95))
	for y in [1.25, 1.85]:
		Build.box(root, Vector3(0.84, 0.025, 0.03), Vector3(pw_x, y, z0 + 0.016), oak)
	var notes := [[-0.25, 0.12, Color(0.98, 0.93, 0.45), 0.1], [0.0, 0.14, Color(0.95, 0.95, 0.95), -0.05], [0.24, 0.1, Color(0.6, 0.85, 0.95), 0.07],
			[-0.22, -0.13, Color(0.95, 0.65, 0.75), -0.08], [0.18, -0.12, Color(0.95, 0.95, 0.95), 0.03]]
	for n in notes:
		Build.box(root, Vector3(0.17, 0.2, 0.002), Vector3(pw_x + n[0], 1.55 + n[1], z0 + 0.024), Build.mat(n[2], 0.9), false, Vector3(0, 0, n[3]))
		Build.sphere(root, 0.008, Vector3(pw_x + n[0], 1.55 + n[1] + 0.085, z0 + 0.028), Build.mat(Color(0.85, 0.1, 0.1), 0.4))
	Build.label(root, "Prüfmittel\nkalibrieren", Vector3(pw_x - 0.25, 1.67, z0 + 0.026), 0.0011, Color(0.1, 0.1, 0.15), 32)
	Build.label(root, "Ø 40 h7\nnachmessen!", Vector3(pw_x + 0.18, 1.43, z0 + 0.026), 0.0011, Color(0.1, 0.1, 0.15), 32)

	# Südwand: Urkunden links vom Fenster, Zeichnung rechts davon
	var cert_y := 1.75
	for c in [[x0 + 0.55, "MEISTERBRIEF\nZerspanungsmechanik"], [x0 + 1.2, "ISO 9001\nzertifiziert"]]:
		Build.box(root, Vector3(0.44, 0.34, 0.02), Vector3(c[0], cert_y, z1 - 0.012), Build.mat(Color(0.12, 0.1, 0.08), 0.5))
		Build.box(root, Vector3(0.38, 0.28, 0.002), Vector3(c[0], cert_y, z1 - 0.023), Build.mat(Color(0.97, 0.95, 0.88), 0.8))
		Build.label(root, c[1], Vector3(c[0], cert_y + 0.03, z1 - 0.025), 0.0011, Color(0.25, 0.18, 0.08), 32, PI)
		Build.cyl(root, 0.025, 0.004, Vector3(c[0] + 0.12, cert_y - 0.09, z1 - 0.025), gold, Build.AXIS_Z, false, 16)
	var dr_x := x1 - 0.75
	Build.box(root, Vector3(0.84, 0.6, 0.02), Vector3(dr_x, 1.7, z1 - 0.012), Build.mat(Color(0.75, 0.76, 0.78), 0.3, 0.7))
	Build.box(root, Vector3(0.78, 0.54, 0.002), Vector3(dr_x, 1.7, z1 - 0.023), Build.mat(Color(0.93, 0.95, 0.98), 0.8))
	# Gedrehte Welle als Zeichnung: Absätze, Mittellinie, Maßlinie
	var ink := Build.mat(Color(0.12, 0.2, 0.45), 0.8)
	var steps := [[-0.28, 0.16, 0.12], [-0.12, 0.2, 0.2], [0.1, 0.24, 0.14], [0.26, 0.08, 0.09]]
	for st in steps:
		var sx: float = dr_x - st[0]
		var sw: float = st[1]
		var sh: float = st[2]
		for yy in [1.72 + sh * 0.5, 1.72 - sh * 0.5]:
			Build.box(root, Vector3(sw, 0.004, 0.001), Vector3(sx, yy, z1 - 0.025), ink)
		for xx in [sx - sw * 0.5, sx + sw * 0.5]:
			Build.box(root, Vector3(0.004, sh, 0.001), Vector3(xx, 1.72, z1 - 0.025), ink)
	Build.box(root, Vector3(0.7, 0.002, 0.001), Vector3(dr_x, 1.72, z1 - 0.026), Build.mat(Color(0.7, 0.15, 0.1), 0.8))
	Build.box(root, Vector3(0.62, 0.003, 0.001), Vector3(dr_x, 1.53, z1 - 0.025), ink)
	Build.label(root, "WELLE  Ø 40 h7", Vector3(dr_x, 1.48, z1 - 0.025), 0.001, Color(0.12, 0.2, 0.45), 32, PI)

	# Drucker auf einem Beistellschrank in der Ecke unter der Urkunde
	var pr := Vector3(x0 + 0.45, 0, z1 - 0.4)
	Build.box(root, Vector3(0.7, 0.62, 0.55), Vector3(pr.x + 0.1, 0.31, pr.z), white, true)
	Build.box(root, Vector3(0.66, 0.006, 0.004), Vector3(pr.x + 0.1, 0.33, pr.z - 0.276), frame)
	Build.box(root, Vector3(0.46, 0.24, 0.4), Vector3(pr.x + 0.1, 0.74, pr.z), Build.mat(Color(0.82, 0.83, 0.84), 0.5))
	Build.box(root, Vector3(0.3, 0.012, 0.2), Vector3(pr.x + 0.1, 0.87, pr.z + 0.02), black)
	Build.box(root, Vector3(0.21, 0.01, 0.15), Vector3(pr.x + 0.1, 0.705, pr.z - 0.23), paper, false, Vector3(-0.15, 0, 0))
	Build.box(root, Vector3(0.05, 0.02, 0.005), Vector3(pr.x + 0.26, 0.82, pr.z - 0.2), Build.emissive(Color(0.2, 0.9, 0.3), 1.5))

	# Pflanzen aus dem Modell: große Kübelpflanze in der Ecke, kleine auf der Fensterbank
	_plant(root, Vector3(x1 - 0.5, 0, z1 - 0.5), 1.0, 0.4)
	_plant(root, Vector3(OFFICE_X.x + 2.07, 0.935, z1 - 0.08), 0.2, 1.3)


## Kübelpflanze aus dem Modell, s = Größe gegenüber der großen Pflanze (1,4 m hoch).
static func _plant(root: Node3D, pos: Vector3, s: float, yaw: float) -> void:
	var p := Props.make("plant")
	p.position = pos
	p.rotation.y = yaw
	p.scale = Vector3.ONE * s
	root.add_child(p)
	if s > 0.5:
		Build.collider(root, Vector3(0.36, 0.5, 0.36), Vector3(pos.x, 0.25, pos.z))


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


## Hallenuhr an der Nordwand.
static func _wall_clock(root: Node3D) -> void:
	var black := Build.mat(Color(0.08, 0.08, 0.08), 0.6)
	Build.cyl(root, 0.25, 0.04, Vector3(-4.0, 3.2, -7.95), Build.mat(Color(0.95, 0.95, 0.95), 0.5), Build.AXIS_Z)
	Build.box(root, Vector3(0.02, 0.18, 0.01), Vector3(-4.0, 3.27, -7.92), black)
	Build.box(root, Vector3(0.13, 0.02, 0.01), Vector3(-3.95, 3.2, -7.92), black)
