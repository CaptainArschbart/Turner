extends SceneTree
## Schneidengeometrie der Drehmeißel: Die sichtbare Platte ist genau die Kontur, mit der gerechnet wird.
## Geprüft an der konventionellen Maschine und an der E50: Größe und Lage der Platten, Stech- und Radiusplatte
## im Nennmaß, Fase mit der ganzen Schneidkante des 45°-Meißels, Einstichbreite gleich Plattenbreite.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


## Umriss (axial, radial in mm ab Schneide) eines sichtbaren Netzes, von oben gesehen.
func outline(l, mi: MeshInstance3D) -> Rect2:
	var tip: Vector3 = l.to_global(Vector3((l.tool_z - l.clamp_depth) * 0.001, l.AXIS_H, l.tool_x * 0.001))
	var r := Rect2()
	var first := true
	for s in mi.mesh.get_surface_count():
		for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var g: Vector3 = l.to_local(mi.global_transform * v) - l.to_local(tip)
			var p := Vector2(g.x, g.z) * 1000.0
			r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
			first = false
	return r


func _initialize() -> void:
	await process_frame
	var tools = load("res://scripts/machine/lathe_tools.gd")
	for conv in [true, false]:
		var name := "konventionell" if conv else "E50"
		var l = load("res://scripts/machine/lathe.gd").new()
		l.conventional = conv
		root.add_child(l)
		for i in 3:
			await process_frame
		ok(l.model != null, name + ": Modell geladen")
		if l.model == null:
			continue

		# ------------------------------------------------ Platten: sichtbar = gerechnet
		for k in tools.count():
			var nominal: Dictionary = tools.get_tool(k)
			var id := str(nominal["id"])
			var t: Dictionary = l.tool_at(k)
			l.holder = [id, "", "", ""]
			l.active_slot = 0
			l._apply_holder()
			l.tool_z = 120.0
			l.tool_x = 50.0
			l._sync_slides()
			await process_frame
			var want := Rect2(float(t["zmin"]), 0.0, float(t["zmax"]) - float(t["zmin"]), float(t["top"]))
			ok(is_equal_approx(float(t["nose"]), float(nominal["nose"])), "%s %s: Eckenradius bleibt %.1f" % [name, id, nominal["nose"]])
			if tools.scalable(id):
				ok(want.size.x > (float(nominal["zmax"]) - float(nominal["zmin"])) * 1.5, "%s %s: Platte in sichtbarer Größe (%.1f mm breit)" % [name, id, want.size.x])
				var plate := l.tool_nodes[k].find_child("Platte", false, false) as MeshInstance3D
				ok(plate != null and l.tool_nodes[k].visible, "%s %s: Platte wird aus der Schneidenkontur gezeichnet" % [name, id])
				if plate:
					var got := outline(l, plate)
					ok(got.position.distance_to(want.position) < 0.02 and got.end.distance_to(want.end) < 0.02,
						"%s %s: sichtbare Platte deckt die Schneide (%s gegen %s)" % [name, id, got, want])
				if l.model.has_tool(id):
					ok(not (l.model._holders[id]["insert"] as MeshInstance3D).visible, "%s %s: Platte des Modells ausgeblendet" % [name, id])
			else:
				ok(is_equal_approx(want.size.x, float(nominal["zmax"]) - float(nominal["zmin"])), "%s %s: Plattenbreite im Nennmaß (%.1f mm)" % [name, id, want.size.x])
				if l.model.has_tool(id):
					var ins := l.model._holders[id]["insert"] as MeshInstance3D
					var got := outline(l, ins)
					ok(ins.visible and absf(got.position.x - want.position.x) < 0.05 and absf(got.size.x - want.size.x) < 0.05,
						"%s %s: Stechplatte des Modells ist so breit wie der Einstich (%.2f mm ab %.2f)" % [name, id, got.size.x, got.position.x])

		# ------------------------------------------------ Fase mit der ganzen Schneidkante
		l.holder = ["T5", "", "", ""]
		l.active_slot = 0
		l._apply_holder()
		var t5: Dictionary = l.tool()
		var edge: float = tools.edge_height(t5)
		ok(edge > 12.0, "%s: Die Schneidkante des Fasenmeißels reicht für Fasen bis %.1f mm" % [name, edge])
		# Radial einstechen: Spitze 12 mm unter der Oberfläche, die linke Flanke schneidet die Fase
		l.new_workpiece(60.0, 160.0)
		l.spindle_on = true
		l.spindle_speed = 800.0
		l.tool_z = 160.0
		l.tool_x = 34.0
		l.move_tool(0.0, -16.0, false, 1.0)
		ok(absf(l.tool_x - 18.0) < 0.01, "%s: 12 mm tief eingestochen (X %.2f)" % [name, l.tool_x])
		var slope := 0.0
		var off := 0.0
		for d in [2.0, 4.0, 6.0, 8.0, 10.0, 11.0]:
			slope = maxf(slope, absf((l.radius_at(160.0 - d) - l.radius_at(160.0 - d + 1.0)) - 1.0))
			off = maxf(off, absf(l.radius_at(160.0 - d) - (18.0 + d)))
		ok(slope < 0.26 and off < 0.7, "%s: Fase 12 x 45° über die ganze Kante (Steigung +-%.2f, Lage +-%.2f mm)" % [name, slope, off])
		ok(absf(l.radius_at(146.0) - 30.0) < 0.01, "%s: hinter der Fase bleibt der Durchmesser stehen" % name)
		# Axial anfahren: 12 mm Eingriff nimmt die ganze Kante, früher war bei 3 mm Schluss
		l.new_workpiece(60.0, 160.0)
		l.tool_z = 176.0
		l.tool_x = 18.0
		l.move_tool(-16.0, 0.0, false, 1.0)
		ok(absf(l.tool_z - 160.0) < 0.01 and absf(l.radius_at(154.0) - 24.0) < 0.7, "%s: Fase 12 x 45° auch im Längsvorschub (Z %.2f)" % [name, l.tool_z])
		# Material steht mehr als die zulässige Spantiefe über die Kante hinaus: Der Meißel bleibt davor stehen
		l.new_workpiece(60.0, 160.0)
		l.tool_z = 190.0
		l.tool_x = 30.0 - edge - float(t5["max_dz"]) - 1.5
		l.move_tool(-30.0, 0.0, false, 1.0)
		ok(l.tool_z > 160.0 and l.is_untouched(), "%s: mehr als die Schneidkante lang ist geht nicht (Z %.2f)" % [name, l.tool_z])
		# Fase an der linken Flanke: Schulter von rechts anfahren, 4 x 45°
		l.new_workpiece(60.0, 160.0)
		for i in range(int(100.0 / l.SEG), l.profile.size()):
			l.profile[i] = 20.0
		l.tool_z = 104.0
		l.tool_x = 36.0
		l.move_tool(0.0, -13.7, false, 1.0)
		ok(absf(l.radius_at(99.9) - 26.0) < 0.7 and absf(l.radius_at(97.0) - 29.0) < 0.7 and absf(l.radius_at(95.0) - 30.0) < 0.01,
			"%s: Fase 4 x 45° an der Schulter mit der linken Flanke (r %.2f bei Z 99,9)" % [name, l.radius_at(99.9)])

		# ------------------------------------------------ Einstichbreite = Plattenbreite
		for id in ["T1", "T6"]:
			l.holder = [id, "", "", ""]
			l._apply_holder()
			var t: Dictionary = l.tool()
			l.new_workpiece(60.0, 160.0)
			l.spindle_on = true
			l.spindle_speed = 800.0
			l._cut(100.0, 24.0, 1.0)
			var z0: float = 100.0 + float(t["zmin"])
			var z1: float = 100.0 + float(t["zmax"])
			# Schruppplatte: die flache Nebenschneide reicht bis kurz vor die rechte Ecke
			var reach: float = z1 - 0.5 if id == "T6" else z0 + (z1 - z0) * 0.85
			ok(l.radius_at(z0 + 0.5) < 29.9 and l.radius_at(reach) < 29.9, "%s %s: unter der Schneide ist Material weg (bis Z %.1f)" % [name, id, reach])
			ok(is_equal_approx(l.radius_at(z0 - 0.5), 30.0) and is_equal_approx(l.radius_at(z1 + 0.5), 30.0), "%s %s: neben der Platte bleibt es stehen" % [name, id])
		l.spindle_on = false
		l.queue_free()
		await process_frame

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
