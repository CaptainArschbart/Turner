extends SceneTree
## Modell des Hallenkrans (models/hallenkran.glb): Teile geladen und an den fahrenden Knoten, Brücke unter Dach
## und Leuchten, Katze und Unterflasche folgen der Stellung, Hubseil, Schleppleitung, Meldeleuchte und das
## Kettengehänge an den Kranösen des Behälters.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## Hüllquader eines einzelnen Netzes in der Halle (ohne seine Kinder).
func box(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.get_aabb()


## Länge der Leitung einer Schlaufe: entlang einer Kante des Netzes gemessen.
func cable_length(mesh: ArrayMesh) -> float:
	var vs: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var total := 0.0
	var n := vs.size() / 4          # vier Streifen, je zwei Punkte pro Stützstelle
	for k in range(2, n, 2):
		total += vs[k].distance_to(vs[k - 2])
	return total


## Kleinster Abstand eines Kettenglieds zum Punkt at (in der Halle).
func nearest_link(c, at: Vector3) -> float:
	var best := INF
	for t in c._links:
		best = minf(best, (c._sling.global_transform * t.origin).distance_to(at))
	return best


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 5000, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var c = w.crane
	w.start_day()
	var hall = load("res://scripts/world/workshop.gd")

	# ---------------------------------------------------- Teile des Modells
	ok(ResourceLoader.exists(c.MODEL_PATH), "Modell vorhanden: " + c.MODEL_PATH)
	var bridge := c._bridge.find_child("Bruecke", true, false) as MeshInstance3D
	var cat := c._trolley.find_child("Katze", true, false) as MeshInstance3D
	var block := c._hook.find_child("Unterflasche", true, false) as MeshInstance3D
	var runway := c.find_child("Kranbahn", true, false) as MeshInstance3D
	ok(bridge != null and cat != null and block != null, "Brücke, Katze und Unterflasche hängen an den fahrenden Knoten")
	ok(runway != null and runway.get_parent() == c, "Kranbahn steht fest in der Halle")
	ok(c._lamp != null and str(c._lamp.name) == "Lampe" and c._lamp.get_parent() == c._trolley, "Meldeleuchte an der Katze")
	ok(c._chains.find_child("Gehaenge", true, false) != null and not c._chains.visible, "Kettengehänge am Haken, ohne Last versteckt")
	if bridge == null or cat == null or block == null or runway == null:
		print("CHECKS %d FAILS %d" % [checks, fails])
		quit()
		return

	# ---------------------------------------------------- Brücke in der Halle
	c.bridge_x = 3.0
	c.trolley_z = -2.0
	c.hook_y = 2.0
	await frames(2)
	var bb := box(bridge)
	ok(absf(bb.get_center().x - 3.0) < 0.05, "Brücke steht bei x = 3: %.2f" % bb.get_center().x)
	ok(bb.end.y < float(hall.LAMP_Y) and bb.end.y < float(hall.H) - 0.5, "Brücke bleibt unter Leuchten und Dachträgern: Oberkante %.2f" % bb.end.y)
	ok(bb.position.z > -7.56 and bb.end.z < 7.56, "Brücke zwischen den Stützen: z %.2f bis %.2f" % [bb.position.z, bb.end.z])
	ok(bb.position.y > 5.2, "Brücke hängt nicht tiefer als die Kranbahn: Unterkante %.2f" % bb.position.y)
	var rb := box(runway)
	ok(rb.position.x >= -float(hall.W) * 0.5 and rb.end.x <= float(hall.W) * 0.5, "Kranbahn endet an den Hallenwänden: x %.2f bis %.2f" % [rb.position.x, rb.end.x])
	for x in [c.X_RANGE.x, c.X_RANGE.y]:
		c.bridge_x = x
		await frames(2)
		bb = box(bridge)
		ok(bb.position.x > rb.position.x and bb.end.x < rb.end.x, "Am Fahrwegende bleibt die Brücke auf der Kranbahn (x = %.1f)" % x)
	c.bridge_x = 3.0

	# ---------------------------------------------------- Katze und Schleppleitung
	await frames(2)
	bb = box(bridge)
	var cb := box(cat)
	ok(absf(cb.get_center().x - 3.0) < 0.1 and absf(cb.get_center().z + 2.0) < 0.15, "Katze steht bei z = -2: %s" % cb.get_center())
	ok(cb.end.y < bb.end.y and cb.position.y > 5.0, "Katze hängt unter dem Träger: y %.2f bis %.2f" % [cb.position.y, cb.end.y])
	ok(c._carriers.size() == c.CABLE_LOOPS - 1 and c._loops.size() == c.CABLE_LOOPS, "Schleppleitung: %d Wagen, %d Schlaufen" % [c._carriers.size(), c._loops.size()])
	for z in [c.Z_RANGE.x, c.Z_RANGE.y]:
		c.trolley_z = z
		await frames(2)
		cb = box(cat)
		ok(cb.position.z > -7.2 and cb.end.z < 7.2, "Katze bleibt am Fahrwegende unter dem Träger: z %.2f bis %.2f" % [cb.position.z, cb.end.z])
		var step: float = c._carriers[1].global_position.z - c._carriers[0].global_position.z
		ok(step > 0.05 and step < c.CABLE_LEN, "Leitungswagen stehen hintereinander, Abstand %.3f m" % step)
		var last: Node3D = c._carriers[c._carriers.size() - 1]
		var tow: float = z + c._cable_to.z
		ok(absf(tow - last.global_position.z - step) < 0.001, "Letzter Wagen einen Abstand vor dem Mitnehmer der Katze")
		var lb := box(c._loops[0])
		ok(absf(lb.size.z - step) < 0.01, "Schlaufe spannt von Wagen zu Wagen: %.3f m" % lb.size.z)
		ok(lb.position.y > 4.7 and lb.end.y < bb.end.y, "Schlaufe hängt neben dem Träger: tiefster Punkt %.2f" % lb.position.y)
		var len := cable_length(c._loop_mesh)
		ok(absf(len - c.CABLE_LEN) < 0.03, "Leitung je Schlaufe bleibt %.2f m lang: %.3f" % [c.CABLE_LEN, len])
	c.trolley_z = -2.0

	# ---------------------------------------------------- Unterflasche und Hubseil
	c.hook_y = 2.0
	await frames(2)
	var ub := box(block)
	ok(absf(ub.position.y - 2.0) < 0.005, "Hakenunterkante auf Hakenhöhe: %.3f" % ub.position.y)
	ok(absf(ub.get_center().x - 3.0) < 0.02 and absf(ub.get_center().z + 2.0) < 0.03, "Unterflasche hängt unter der Katze")
	ok(c._ropes.size() == 2, "Zwei Seilstränge")
	for i in c._ropes.size():
		var want: float = c._rope_top[i].y - (c.hook_y + c._rope_end[i].y)
		var got: float = c._ropes[i].global_transform.basis.y.length()
		ok(c._ropes[i].visible and absf(got - want) < 0.001, "Seilstrang %d reicht von der Katze zur Seilrolle: %.2f m" % [i + 1, got])
	c.hook_y = c.HOOK_TOP
	await frames(2)
	ub = box(block)
	ok(ub.end.y < c._rope_top[0].y - 0.08, "Ganz oben bleibt die Unterflasche unter der Seiltrommel: %.2f" % ub.end.y)
	c.hook_y = 2.0

	# ---------------------------------------------------- Meldeleuchte
	p.global_position = Vector3(2.0, 0.05, 0.0)
	await frames(2)
	ok(c._lamp.material_override == c._lamp_off, "Leuchte aus, solange die Fernbedienung in der Halterung liegt")
	c.grab(p)
	await frames(2)
	ok(c._lamp.material_override == c._lamp_on, "Leuchte an mit der Fernbedienung in der Hand")
	c.release()
	await frames(2)
	ok(c._lamp.material_override == c._lamp_off, "Leuchte wieder aus")

	# ---------------------------------------------------- Kettengehänge an den Kranösen
	var at := Vector2(-4.0, -3.0)
	for rot in [0, 1]:
		w.layout.bins.append({"size": "bin_l" if rot == 0 else "bin_s", "pos": at + Vector2(0, 5.0 * rot), "rot": rot, "chips": ChipTray.new(60.0), "out": false})
		w._rebuild_stands()
		var bi: int = w.layout.bins.size() - 1
		var node: Node3D = w.bin_nodes[bi]
		var size := str(w.layout.bins[bi]["size"])
		c.bridge_x = at.x
		c.trolley_z = at.y + 5.0 * rot
		c.hook_y = c.SLING + float(w.crane_bin_height(bi)) + 0.02
		await frames(2)
		c.hook_click()
		ok(c.hooked == bi and c._chains.visible, "Behälter eingehängt, Gehänge sichtbar (Drehung %d)" % rot)
		c.hook_y = 3.2
		await frames(3)
		ok(c._links.size() > 80 and c._sling.multimesh.instance_count == c._links.size(), "Vier Kettenstränge: %d Glieder" % c._links.size())
		var worst := 0.0
		for lug in ChipBin.lugs(size):
			worst = maxf(worst, nearest_link(c, node.global_transform * lug))
		ok(worst < 0.03, "Jeder Strang endet in einer Kranöse (größter Abstand %.3f m)" % worst)
		var start: Vector3 = c._hook.global_transform * c._chain_start
		ok(nearest_link(c, start) < 0.03, "Die Stränge beginnen im Aufhängeglied")
		c.hook_y = 0.0
		await frames(3)
		c.hook_click()
		ok(c.hooked < 0 and not c._chains.visible, "Ausgehängt, Gehänge wieder versteckt")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
