extends SceneTree
## Headless-Prüfung der Zyklenerweiterung an der E50: Kreisbögen in Konturen, Bohrzyklus,
## Innenkontur mit der Bohrstange, Gewinde außen und innen, dazu das Innenprofil des Werkstücks
## (Schnittmodell, Mesh, Speichern/Laden, Umspannen, Maßprüfung).
## Aufruf: godot --headless --path . -s res://tools/tests/test_inner_cycles.gd

var checks := 0
var fails := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


func run(l, max_s := 3000.0) -> float:
	var t := 0.0
	var dt := 0.05
	while l.nc.busy() and t < max_s:
		l._physics_process(dt)
		l._step_index_anim(dt)
		t += dt
	return t


## Programm anlegen, anwählen und abarbeiten. Gibt den Endzustand zurück.
func exec(l, pname: String, blocks: Array) -> String:
	var p := NcCam.new_program(pname)
	p["blocks"].append_array(blocks)
	l.programs.append(p)
	l.prog_sel = pname
	var sim: Dictionary = NcCam.simulate(p, l)
	ok(sim["errs"].is_empty(), "%s: Simulation ohne Fehler %s" % [pname, sim["errs"]])
	if not l.nc.nc_start(p):
		ok(false, "%s: NC-Start" % pname)
		return "refused"
	var dur := run(l)
	ok(l.nc.state == "done" and not l.estop, "%s beendet (%s %s, %.0f s)" % [pname, l.nc.state, l.nc.alarm, dur])
	return l.nc.state


func stop(l) -> void:
	l.spindle_on = false
	var guard := 0
	while l.spindle_speed > 5.0 and guard < 400:
		l._physics_process(0.05)
		guard += 1


func holder(l, ids: Array) -> void:
	# Spindel auslaufen lassen, dann alles außer dem aktiven Platz leeren und neu bestücken
	stop(l)
	for s in 4:
		if s != l.active_slot:
			l.mount_tool(s, "")
	l.mount_tool(l.active_slot, str(ids[l.active_slot]))
	for s in 4:
		if s != l.active_slot:
			ok(l.mount_tool(s, str(ids[s])), "%s in Platz %d einspannen" % [ids[s], s + 1])


func _initialize() -> void:
	await process_frame
	var l = load("res://scripts/machine/lathe.gd").new()
	root.add_child(l)
	l.power_on(true)
	await process_frame
	l.set_door(true)
	l.message.connect(func(t, _c): if OS.has_environment("TDEBUG"): print("  MSG ", t))

	# --- Werkzeuge
	var t8: Dictionary = LatheTools.get_tool(LatheTools.index_of("T8"))
	var t9: Dictionary = LatheTools.get_tool(LatheTools.index_of("T9"))
	var t10: Dictionary = LatheTools.get_tool(LatheTools.index_of("T10"))
	var t11: Dictionary = LatheTools.get_tool(LatheTools.index_of("T11"))
	ok(LatheTools.kind(t8) == "bore" and LatheTools.is_inner(t8), "T8 ist eine Bohrstange")
	ok(absf(LatheTools.env_max(t8, -0.1, 1.0)) < 0.01, "T8: Schneide oben am Bezugspunkt (%.3f)" % LatheTools.env_max(t8, -0.1, 1.0))
	ok(float(t8["bottom"]) < -14.0 and float(t8["cut_len"]) > 2.0 and float(t8["cut_len"]) < 8.0, "T8: Stange unter der Platte, Schneidbereich %.1f mm" % float(t8["cut_len"]))
	ok(absf(LatheTools.env_max(t9, 30.0, 30.2) - 10.0) < 0.01 and LatheTools.env_max(t9, 0.0, 0.05) < 0.2, "T9: Bohrer Ø20 mit Spitze")
	ok(LatheTools.is_thread(t10) and LatheTools.is_thread(t11) and LatheTools.is_inner(t11), "T10/T11 Gewindemeißel außen/innen")
	var tm: Dictionary = LatheTools.mirrored(t8)
	ok(absf(LatheTools.env_min(tm, -0.1, 1.0)) < 0.01 and LatheTools.kind(tm) == "", "gespiegelte Bohrstange rechnet wie ein Außenmeißel")

	# --- Kreisbögen in der Kontur
	var c := {"type": "contour", "name": "B", "x0": 0.0, "z0": 0.0, "els": [
		{"x": 30.0, "z": 0.0, "tr": 0, "tv": 0.0},
		{"x": 40.0, "z": -5.0, "tr": 0, "tv": 0.0, "arc": 2, "r": 5.0},
		{"x": 40.0, "z": -30.0, "tr": 0, "tv": 0.0},
		{"x": 60.0, "z": -40.0, "tr": 0, "tv": 0.0, "arc": 1, "r": 10.0},
		{"x": 64.0, "z": -40.0, "tr": 0, "tv": 0.0}]}
	var pts: PackedVector2Array = NcCam.contour_points(c)
	var on1 := 0
	var on2 := 0
	for q in pts:
		if q.x < -0.01 and q.x > -4.99 and absf(q.distance_to(Vector2(-5, 15)) - 5.0) < 0.001:
			on1 += 1
		if q.x < -30.01 and q.x > -39.99 and absf(q.distance_to(Vector2(-30, 30)) - 10.0) < 0.001:
			on2 += 1
	ok(on1 >= 3, "Bogen gegen UZS R5: Punkte auf dem Kreis um Z-5 X30 (%d)" % on1)
	ok(on2 >= 3, "Bogen im UZS R10: Hohlkehle um Z-30 X60 (%d)" % on2)
	var cm := c.duplicate(true)
	cm["els"][1] = {"x": 40.0, "z": -5.0, "tr": 0, "tv": 0.0, "arc": 2, "cm": 1, "ci": 30.0, "ck": -5.0}
	var pts2: PackedVector2Array = NcCam.contour_points(cm)
	ok(pts2.size() == pts.size() and pts2[5].distance_to(pts[5]) < 0.001, "Bogen über Mittelpunkt = Bogen über Radius")
	ok(NcCam.contour_error(c) == "", "Bogenkontur fehlerfrei")
	var bad := c.duplicate(true)
	bad["els"][1]["r"] = 2.0
	ok(NcCam.contour_error(bad) != "", "zu kleiner Radius gemeldet (%s)" % NcCam.contour_error(bad))
	bad = cm.duplicate(true)
	bad["els"][1]["ci"] = 31.0
	ok(NcCam.contour_error(bad) != "", "Endpunkt nicht auf dem Kreis gemeldet")

	# --- Bogenkontur an der Maschine schruppen und schlichten
	l.set_material("S235")
	l.new_workpiece(64.0, 120.0)
	l.set_door(true)
	var cb := c.duplicate(true)
	exec(l, "BOGEN", [cb,
		{"type": "stock", "contour": "B", "side": 0, "mode": 0, "dir": 0, "t": "T1", "f": 0.25, "v": 180.0, "d": 2.0, "ux": 0.4, "uz": 0.2, "hs": 1},
		{"type": "stock", "contour": "B", "side": 0, "mode": 1, "dir": 0, "t": "T3", "f": 0.1, "v": 220.0, "d": 1.0, "ux": 0.0, "uz": 0.0, "hs": 1}])
	var r_a1: float = l.radius_at(120.0 - 2.5)
	var r_a2: float = l.radius_at(120.0 - 35.0)
	ok(absf(r_a1 - (15.0 + sqrt(25.0 - 6.25))) < 0.2, "Bogen R5 gedreht: r %.2f bei Z-2,5 (Soll %.2f)" % [r_a1, 15.0 + sqrt(25.0 - 6.25)])
	ok(absf(r_a2 - (30.0 - sqrt(75.0))) < 0.25, "Hohlkehle R10 gedreht: r %.2f bei Z-35 (Soll %.2f)" % [r_a2, 30.0 - sqrt(75.0)])

	# --- Bohren mittig
	l.new_workpiece(60.0, 100.0)
	l.set_door(true)
	holder(l, ["T1", "T9", "T3", "T8"])
	var drill := NcCam.new_block("drill")
	drill["z1"] = -40.0
	drill["q"] = 15.0
	drill["chip"] = 1
	exec(l, "BOHREN", [drill])
	ok(absf(l.bore_at(100.0 - 20.0) - 10.0) < 0.01, "Bohrung Ø20 bei Z-20 (r %.2f)" % l.bore_at(80.0))
	ok(l.bore_at(100.0 - 40.5) < 0.01 and l.bore_at(100.0 - 39.0) > 0.5 and l.bore_at(100.0 - 39.0) < 10.0, "Bohrgrund mit Spitze bei Z-40")
	ok(absf(l.radius_at(80.0) - 30.0) < 0.01, "Außen-Ø unberührt")
	ok(l.has_inner() and not l.is_untouched(), "Werkstück hat ein Innenprofil")
	var mesh: ArrayMesh = l.workpiece_mi.mesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if mesh.get_surface_count() > 0 else PackedVector3Array()
	var inner_v := 0
	for v in verts:
		if absf(v.x - 0.07) < 0.01 and absf(Vector2(v.y, v.z).length() - 0.010) < 0.0002:
			inner_v += 1
	ok(inner_v >= 48, "Mesh zeigt die Bohrung (%d Punkte auf Ø20)" % inner_v)
	# Spanstau: von Hand ohne Entspänen zu tief bohren
	var e2 = load("res://scripts/machine/lathe.gd").new()
	root.add_child(e2)
	e2.power_on(true)
	await process_frame
	e2.new_workpiece(60.0, 200.0)
	e2.mount_tool(1, "T9")
	e2.index_slot(1, true)
	for i in 30:
		e2._step_index_anim(0.05)
	e2.tool_z = 205.0
	e2.tool_x = 0.0
	e2.spindle_on = true
	e2.css = false
	e2.set_rpm(400.0)
	for i in 60:
		e2._physics_process(0.05)
	e2.move_tool(-120.0, 0.0, false, 1.0)
	ok(e2.tool_z > 200.0 - 120.0 + 1.0 and e2.tool_z < 205.0, "ohne Entspänen bleibt der Bohrer stecken (Z %.1f)" % e2.tool_z)
	e2.move_tool(2.0, 0.0, false, 1.0)
	var z_before: float = e2.tool_z
	e2.move_tool(-5.0, 0.0, false, 1.0)
	ok(e2.tool_z < z_before - 4.0, "nach dem Entspänen bohrt er weiter")
	e2.move_tool(0.0, 3.0, false, 1.0)
	ok(e2.estop, "Bohrer seitlich bewegt: Not-Halt")
	e2.queue_free()

	# --- Innenkontur mit der Bohrstange
	var ci := {"type": "contour", "name": "IN", "x0": 32.0, "z0": 0.0, "els": [
		{"x": 30.0, "z": -1.0, "tr": 0, "tv": 0.0},
		{"x": 30.0, "z": -15.0, "tr": 0, "tv": 0.0},
		{"x": 24.0, "z": -18.0, "tr": 0, "tv": 0.0, "arc": 1, "r": 3.0},
		{"x": 24.0, "z": -30.0, "tr": 0, "tv": 0.0},
		{"x": 20.0, "z": -30.0, "tr": 0, "tv": 0.0}]}
	ok(NcCam.contour_error(ci) == "", "Innenkontur mit Bogen fehlerfrei (%s)" % NcCam.contour_error(ci))
	exec(l, "INNEN", [ci,
		{"type": "stock", "contour": "IN", "side": 1, "mode": 2, "dir": 0, "t": "T8", "f": 0.12, "v": 150.0, "d": 1.0, "ux": 0.2, "uz": 0.1, "hs": 1}])
	ok(absf(l.bore_at(100.0 - 8.0) - 15.0) < 0.12, "Innen-Ø30 ausgedreht (r %.2f)" % l.bore_at(92.0))
	ok(absf(l.bore_at(100.0 - 25.0) - 12.0) < 0.12, "Innen-Ø24 ausgedreht (r %.2f)" % l.bore_at(75.0))
	ok(absf(l.bore_at(100.0 - 32.0) - 10.0) < 0.05, "Bohrung dahinter bleibt Ø20 (r %.2f)" % l.bore_at(68.0))
	ok(absf(l.radius_at(80.0) - 30.0) < 0.01, "Außen-Ø beim Innendrehen unberührt")
	var job := {"features": [
		{"type": "bore", "z0": 100.0 - 14.0, "z1": 100.0 - 2.0, "d": 30.0, "tol": 0.2},
		{"type": "bore", "z0": 100.0 - 29.0, "z1": 100.0 - 19.0, "d": 24.0, "tol": 0.2}]}
	var ev: Dictionary = l.evaluate(job)
	ok(int(ev["ok"]) == 2, "Auftragsprüfung Bohrungen: %s" % [ev["lines"]])
	# Innenwerkzeug stößt im Vollmaterial an

	# --- Gewinde innen M36 x 2 (Kern-Ø 36 - 2·1,083 = 33,83): erst auf Ø33,9 ausdrehen
	var ck := {"type": "contour", "name": "KERN", "x0": 33.9, "z0": 0.0, "els": [
		{"x": 33.9, "z": -14.0, "tr": 0, "tv": 0.0},
		{"x": 30.0, "z": -14.0, "tr": 0, "tv": 0.0}]}
	holder(l, ["T1", "T11", "T3", "T8"])
	var thi := NcCam.new_block("thread")
	thi["side"] = 1
	thi["t"] = "T11"
	thi["p"] = 2.0
	thi["x0"] = 36.0
	thi["h"] = NcCam.iso_depth(2.0, true)
	thi["z1"] = -12.0
	thi["n"] = 8
	thi["v"] = 80.0
	exec(l, "GEWINDE_INNEN", [ck,
		{"type": "stock", "contour": "KERN", "side": 1, "mode": 2, "dir": 0, "t": "T8", "f": 0.1, "v": 150.0, "d": 1.0, "ux": 0.0, "uz": 0.0, "hs": 1},
		thi])
	var tin: Dictionary = l.thread_info(100.0 - 11.0, 100.0 - 1.0, true)
	ok(absf(float(tin["p"]) - 2.0) < 0.01 and absf(float(tin["depth"]) - 1.083) < 0.08 and float(tin["cover"]) > 0.9,
		"Innengewinde M36x2: %s" % [tin])
	ev = l.evaluate({"features": [{"type": "thread", "inner": true, "z0": 100.0 - 11.0, "z1": 100.0 - 1.0, "d": 36.0, "p": 2.0, "tol": 0.3}]})
	ok(int(ev["ok"]) == 1, "Auftragsprüfung Innengewinde: %s" % [ev["lines"]])

	# --- Gewinde außen M20 x 1,5 an einem Zapfen
	l.new_workpiece(40.0, 80.0)
	l.set_door(true)
	holder(l, ["T1", "T10", "T3", ""])
	var cz := {"type": "contour", "name": "ZAPFEN", "x0": 16.0, "z0": 0.0, "els": [
		{"x": 20.0, "z": -2.0, "tr": 0, "tv": 0.0},
		{"x": 20.0, "z": -30.0, "tr": 0, "tv": 0.0},
		{"x": 40.0, "z": -30.0, "tr": 0, "tv": 0.0}]}
	var tho := NcCam.new_block("thread")
	tho["z1"] = -25.0
	exec(l, "GEWINDE_AUSSEN", [cz,
		{"type": "stock", "contour": "ZAPFEN", "side": 0, "mode": 2, "dir": 0, "t": "T1", "f": 0.2, "v": 180.0, "d": 2.0, "ux": 0.3, "uz": 0.1, "hs": 1},
		tho])
	var tout: Dictionary = l.thread_info(80.0 - 24.0, 80.0 - 2.0, false)
	ok(absf(float(tout["p"]) - 1.5) < 0.01 and absf(float(tout["depth"]) - 0.92) < 0.06 and float(tout["cover"]) > 0.9,
		"Außengewinde M20x1,5: %s" % [tout])
	ok(absf(l.radius_at(70.0) - 10.0) < 0.05, "Außen-Ø des Gewindes bleibt 20 (r %.2f)" % l.radius_at(70.0))
	ev = l.evaluate({"features": [{"type": "thread", "z0": 80.0 - 24.0, "z1": 80.0 - 2.0, "d": 20.0, "p": 1.5}]})
	ok(int(ev["ok"]) == 1, "Auftragsprüfung Außengewinde: %s" % [ev["lines"]])
	# Gewinde im Mesh: Radius schwankt je Winkel (Schraubenlinie)
	mesh = l.workpiece_mi.mesh
	verts = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rmin := 1.0
	var rmax := 0.0
	for v in verts:
		if absf(v.x - 0.065) < 0.0005:
			var rr := Vector2(v.y, v.z).length()
			rmin = minf(rmin, rr)
			rmax = maxf(rmax, rr)
	ok(rmax - rmin > 0.0007 and rmax < 0.0101, "Gewindegänge im Mesh (r %.2f .. %.2f mm)" % [rmin * 1000.0, rmax * 1000.0])
	# Gewindeprüfung: falsche Steigung fällt durch
	ev = l.evaluate({"features": [{"type": "thread", "z0": 80.0 - 24.0, "z1": 80.0 - 2.0, "d": 20.0, "p": 1.0}]})
	ok(int(ev["ok"]) == 0, "falsche Steigung fällt durch")
	# Zu große erste Zustellung abgelehnt
	var thx := NcCam.new_block("thread")
	thx["n"] = 1
	ok(NcCam.check_block(thx, t10) != "", "Gewinde in einem Schnitt abgelehnt (%s)" % NcCam.check_block(thx, t10))
	ok(NcCam.check_block(NcCam.new_block("thread"), t11) != "", "Außengewinde mit Innenmeißel abgelehnt")
	ok(NcCam.check_block(NcCam.new_block("drill"), LatheTools.get_tool(0)) != "", "Bohren mit Drehmeißel abgelehnt")

	# --- Speichern / Laden / Umspannen
	var st: Dictionary = l.get_state()
	var l2 = load("res://scripts/machine/lathe.gd").new()
	root.add_child(l2)
	await process_frame
	l2.set_state(st)
	var same := true
	for i in l.profile.size():
		if absf(l.thr[i] - l2.thr[i]) > 0.0001 or absf(l.thr_p[i] - l2.thr_p[i]) > 0.0001 or absf(l.bore[i] - l2.bore[i]) > 0.0001:
			same = false
	ok(same, "Gewinde und Bohrung gespeichert und geladen")
	var ps: Dictionary = l.part_state()
	l2.load_part(ps)
	ok(absf(l2.thr[int(70.0 / NcCam.SEG)] - l.thr[int(70.0 / NcCam.SEG)]) < 0.0001, "Teil weitertragen behält das Gewinde")
	l2.queue_free()
	stop(l)
	var thr_before: float = l.thr[int(70.0 / NcCam.SEG)]
	l.reclamp(0.0, true)
	var flipped_ok: bool = l.thr[int((l.part_length() - 70.0) / NcCam.SEG)] > 0.5
	l.reclamp(0.0, true)
	ok(flipped_ok and absf(l.thr[int(70.0 / NcCam.SEG)] - thr_before) < 0.0001, "Umspannen dreht das Gewinde mit um")

	# --- Rohr: Außen bis auf die Bohrung abdrehen
	l.new_workpiece(30.0, 60.0)
	for i in l.profile.size():
		l.bore[i] = 10.0
	l.set_door(true)
	holder(l, ["T1", "", "T3", ""])
	var cut := NcCam.new_block("cut")
	cut["z0"] = 0.0
	cut["z1"] = -5.0
	cut["x1"] = 0.0
	cut["dir"] = 1
	cut["d"] = 1.0
	exec(l, "PLAN_ROHR", [cut])
	ok(absf(l.part_length() - 55.0) < 0.3, "Rohr plangedreht: Länge %.2f" % l.part_length())
	ok(not l.has_mat(int(57.0 / NcCam.SEG)), "Rohrende ohne Restring")

	# --- Auftragstext mit Bohrung und Gewinde
	var tjob := {"title": "Gewindebuchse", "stock_d": 40.0, "stock_len": 80.0, "reward": 100, "features": [
		{"type": "bore", "z0": 50.0, "z1": 80.0, "d": 22.4},
		{"type": "thread", "z0": 55.0, "z1": 78.0, "d": 24.0, "p": 1.5, "inner": true}]}
	var desc := Jobs.describe(tjob)
	ok(desc.contains("Bohrung") and desc.contains("M24") and desc.contains("x 1.5 innen") and Jobs.target_lines(tjob).size() == 2, "Auftragstext nennt Bohrung und Gewinde")

	# --- Bedienung am Pult: Bogen im Konturrechner, Bohren und Gewinde über die zweite Softkey-Ebene
	var s = l.screen
	ok(s != null, "Pult-Software vorhanden")
	l.new_workpiece(60.0, 100.0)
	holder(l, ["T1", "T9", "T10", "T8"])
	s.show_page("pm")
	s._pm_name.text = "zyklen"
	s._pm_new()
	ok(s.open_prog == "ZYKLEN" and s.page == "edit", "Neues Programm ZYKLEN")
	s._refresh()
	ok(str(s.hsk[5].text).begins_with("Bohren"), "Softkey Bohren/Gewinde im Arbeitsplan")
	s._press(false, 5)
	ok(s._ed_more and str(s.vsk[0].text).begins_with("Bohren") and str(s.vsk[2].text).contains("innen"), "zweite Softkey-Ebene: Bohren, Gewinde, innen")
	s._press(true, 0)
	ok(s.page == "form" and str(s._form_blk["type"]) == "drill", "Maske Bohren offen")
	s._form_blk["z1"] = -30.0
	s._form_accept()
	var zp: Dictionary = s.prog_by_name("ZYKLEN")
	ok(s.page == "edit" and zp["blocks"].size() == 2 and str(zp["blocks"][1]["type"]) == "drill", "Bohrsatz übernommen")
	s._ed_more = true
	s._refresh()
	s._press(true, 2)
	ok(s.page == "form" and int(s._form_blk["side"]) == 1 and str(s._form_blk["t"]) == "T11", "Maske Gewinde innen mit T11")
	s._form_set("p", LineEdit.new(), "2")
	ok(absf(float(s._form_blk["h"]) - NcCam.iso_depth(2.0, true)) < 0.0001, "Tiefe H1 folgt der Steigung (%.3f)" % float(s._form_blk["h"]))
	s.show_page("edit")
	s._ed_more = false
	s._refresh()
	s._ed_new("contour")
	var n0: int = s._ct["els"].size()
	s._ct_sel = 1
	s._ct_add(Vector2(-5.0, 10.0), 2)
	var arc_e: Dictionary = s._ct["els"][1]
	ok(s._ct["els"].size() == n0 + 1 and int(arc_e["arc"]) == 2 and float(arc_e["r"]) > 0.0, "Bogen gegen UZS eingefügt")
	ok(str(s._ct_list.get_item_text(2)).begins_with("Bogen"), "Liste zeigt den Bogen (%s)" % s._ct_list.get_item_text(2))
	arc_e["r"] = 1.0
	var n_blocks: int = zp["blocks"].size()
	s._ct_accept()
	ok(s.page == "contour" and zp["blocks"].size() == n_blocks, "Bogen mit zu kleinem Radius wird nicht übernommen")
	arc_e["r"] = 5.0
	s._ct_accept()
	ok(s.page == "edit" and zp["blocks"].size() == n_blocks + 1, "Bogenkontur übernommen")
	s._ed_more = true
	s._refresh()
	s._press(true, 1)
	ok(str(s._form_blk["type"]) == "thread" and int(s._form_blk["side"]) == 0, "Maske Gewinde außen")
	s._form_blk["x0"] = 60.0
	s._form_blk["z1"] = -10.0
	s._form_accept()
	s.show_page("sim")
	ok(s._sim_plot.moves.size() > 0 and not s._sim_plot.bore.is_empty(), "Simulation mit Bohrung (%d Züge)" % s._sim_plot.moves.size())
	var bmax := 0.0
	for v in s._sim_plot.bore:
		bmax = maxf(bmax, v)
	ok(absf(bmax - 10.0) < 0.01, "Simulation bohrt Ø20 vor (%.2f)" % bmax)
	await process_frame
	s.show_page("edit")
	s._ed_list.select(1)
	s._ed_plot_update()
	ok(s._ed_plot.hi_poly.size() >= 3, "Bohrsatz in der Grafik hervorgehoben")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
