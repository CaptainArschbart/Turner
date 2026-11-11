extends SceneTree
## Zyklensteuerung mit mehreren Konturen und Hinterschnitten (Gewindefreistich, Einstich zwischen
## zwei Bunden): Schruppen mit konturparallelem Eintauchen, Restmaterial mit dem Schlichtmeißel,
## Schlichten nur entlang der programmierten Kontur. Prüft das fertige Teil an der Maschine.
## Aufruf: godot --headless --path . -s res://tools/tests/test_nc_contours.gd

var checks := 0
var fails := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


func run(l, max_s := 4000.0) -> float:
	var t := 0.0
	var dt := 0.05
	while l.nc.busy() and t < max_s:
		l._physics_process(dt)
		l._step_index_anim(dt)
		t += dt
	return t


func el(x: float, z: float, tr := 0, tv := 0.0) -> Dictionary:
	return {"x": x, "z": z, "tr": tr, "tv": tv}


func rough(cname: String, t: String, d: float, hs := 1) -> Dictionary:
	return {"type": "stock", "contour": cname, "mode": 0, "dir": 0, "t": t, "f": 0.2, "v": 180.0,
		"d": d, "ux": 0.4, "uz": 0.2, "hs": hs}


func finish(cname: String) -> Dictionary:
	return {"type": "stock", "contour": cname, "mode": 1, "dir": 0, "t": "T3", "f": 0.1, "v": 220.0,
		"d": 1.0, "ux": 0.0, "uz": 0.0}


## Fertiges Teil gegen die Kontur: nirgends tiefer als die Kontur (kein Hineinschneiden) und im
## Bereich [za, zb] (Programm-Z) höchstens tol über der Kontur.
func check_part(l, c: Dictionary, za: float, zb: float, tol: float, what: String) -> void:
	var poly: PackedVector2Array = NcCam.contour_points(c, l.wcs_z)
	var worst_in := 0.0
	var worst_over := 0.0
	var at_in := 0.0
	var at_over := 0.0
	var z := za
	while z <= zb + 0.001:
		# je Segment: Soll = höchster Konturpunkt im Segment (wie das Sollprofil des Zyklus)
		var i := int(floor((z + l.wcs_z) / NcCam.SEG))
		# tiefster Konturpunkt im Segment (an Fasen/Flanken liegt das Segment schräg)
		var r := minf(NcCam.poly_max(poly, i * NcCam.SEG + 0.001, i * NcCam.SEG + 0.001),
			NcCam.poly_max(poly, (i + 1) * NcCam.SEG - 0.001, (i + 1) * NcCam.SEG - 0.001))
		var rm := NcCam.poly_max(poly, (i - 1) * NcCam.SEG, (i + 2) * NcCam.SEG)
		var a: float = l.profile[i]
		if r >= 0.0 and r - a > worst_in:
			worst_in = r - a
			at_in = z
		if rm >= 0.0 and a - rm > worst_over:
			worst_over = a - rm
			at_over = z
		z += 0.25
	ok(worst_in < 0.03, "%s: nirgends in die Kontur geschnitten (%.3f mm bei Z%.2f)" % [what, worst_in, at_in])
	ok(worst_over < tol, "%s: Kontur fertig (%.3f mm Rest bei Z%.2f)" % [what, worst_over, at_over])


func start(l, p: Dictionary) -> void:
	l.programs.append(p)
	l.prog_sel = str(p["name"])
	l.nc.reset()
	l.set_door(true)
	var sim: Dictionary = NcCam.simulate(p, l)
	ok(sim["errs"].is_empty(), "%s: Simulation ohne Fehler %s" % [p["name"], sim["errs"]])
	ok(l.nc.nc_start(p), "%s: NC-Start" % p["name"])
	var dur := run(l)
	ok(l.nc.state == "done" and not l.estop, "%s beendet (%s %s) nach %.0f s" % [p["name"], l.nc.state, l.nc.alarm, dur])


func _initialize() -> void:
	await process_frame
	var l = load("res://scripts/machine/lathe.gd").new()
	root.add_child(l)
	l.power_on(true)
	await process_frame

	# --- 1) Gewindefreistich als Hinterschnitt in EINER Kontur: T1 schruppt, was er erreicht,
	#        T3 räumt den Freistich (Restmaterial, eintauchen an der 30°-Flanke), T3 schlichtet.
	var kf := {"type": "contour", "name": "FREISTICH", "x0": 0.0, "z0": 0.0, "els": [
		el(20.0, 0.0, 1, 1.0), el(20.0, -24.0), el(17.0, -26.6), el(17.0, -30.0), el(30.0, -30.0),
		el(30.0, -55.0), el(42.0, -55.0)]}
	l.new_workpiece(40.0, 100.0)
	var p1 := NcCam.new_program("FS_EINE_KONTUR")
	p1["blocks"].append(kf)
	p1["blocks"].append(rough("FREISTICH", "T1", 2.0))
	p1["blocks"].append(rough("FREISTICH", "T3", 1.0))
	p1["blocks"].append(finish("FREISTICH"))
	var t0 := Time.get_ticks_msec()
	var sim1: Dictionary = NcCam.simulate(p1, l)
	print("Simulation FS_EINE_KONTUR: %d ms, %d Züge" % [Time.get_ticks_msec() - t0, sim1["moves"].size()])
	start(l, p1)
	ok(absf(l.radius_at(85.0) * 2.0 - 20.0) < 0.05, "Gewinde-Ø20 (%.3f)" % (l.radius_at(85.0) * 2.0))
	ok(absf(l.radius_at(71.5) * 2.0 - 17.0) < 0.1, "Freistichgrund Ø17 (%.3f)" % (l.radius_at(71.5) * 2.0))
	ok(absf(l.radius_at(55.0) * 2.0 - 30.0) < 0.05, "Bund Ø30 (%.3f)" % (l.radius_at(55.0) * 2.0))
	ok(absf(l.radius_at(20.0) * 2.0 - 40.0) < 0.01, "links der Kontur Rohteil (%.3f)" % (l.radius_at(20.0) * 2.0))
	check_part(l, kf, -54.5, -0.5, 0.12, "Freistich in einer Kontur")
	# Restmaterial-Schruppen mit T3: der Freistich, sonst nur Ecken, in die T1 (r 0,8) nicht kam
	var in_fs := 0.0
	var out_fs := 0.0
	var mvs: Array = sim1["moves"]
	for k in range(1, mvs.size()):
		if int(mvs[k][3]) != 3 or bool(mvs[k][2]):
			continue
		var a := Vector2(mvs[k - 1][0], mvs[k - 1][1])
		var b := Vector2(mvs[k][0], mvs[k][1])
		if minf(a.x, b.x) > 69.0 and maxf(a.x, b.x) < 80.0:
			in_fs += a.distance_to(b)
		else:
			out_fs += a.distance_to(b)
	ok(in_fs > 10.0 and out_fs < 8.0, "Restmaterial T3: Freistich %.1f mm, sonst %.1f mm Vorschubweg" % [in_fs, out_fs])

	# --- 2) Zwei Konturen nacheinander: Außenkontur, dann der Freistich als eigene Kontur mitten
	#        im Teil. Rechts davon (Gewinde) und links (Bund) bleibt alles stehen.
	var ka := {"type": "contour", "name": "AUSSEN", "x0": 0.0, "z0": 0.0, "els": [
		el(20.0, 0.0, 1, 1.0), el(20.0, -30.0), el(30.0, -30.0), el(30.0, -55.0), el(42.0, -55.0)]}
	var kb := {"type": "contour", "name": "FS", "x0": 20.0, "z0": -24.0, "els": [
		el(17.0, -26.6), el(17.0, -30.0), el(30.0, -30.0)]}
	l.new_workpiece(40.0, 100.0)
	var p2 := NcCam.new_program("FS_ZWEI_KONTUREN")
	p2["blocks"].append(ka)
	p2["blocks"].append(kb)
	p2["blocks"].append(rough("AUSSEN", "T1", 2.0))
	p2["blocks"].append(finish("AUSSEN"))
	p2["blocks"].append(rough("FS", "T3", 1.0))
	p2["blocks"].append(finish("FS"))
	var sim2: Dictionary = NcCam.simulate(p2, l)
	start(l, p2)
	ok(absf(l.radius_at(85.0) * 2.0 - 20.0) < 0.05, "2 Konturen: Gewinde-Ø20 (%.3f)" % (l.radius_at(85.0) * 2.0))
	ok(absf(l.radius_at(71.5) * 2.0 - 17.0) < 0.1, "2 Konturen: Freistichgrund Ø17 (%.3f)" % (l.radius_at(71.5) * 2.0))
	ok(absf(l.radius_at(55.0) * 2.0 - 30.0) < 0.05, "2 Konturen: Bund Ø30 (%.3f)" % (l.radius_at(55.0) * 2.0))
	check_part(l, kb, -29.75, -24.0, 0.12, "Freistich als 2. Kontur")
	check_part(l, ka, -54.5, -30.5, 0.12, "Außenkontur am Bund")
	check_part(l, ka, -23.5, -0.5, 0.12, "Außenkontur am Gewinde")
	# Schruppen und Schlichten des Freistichs bleiben am Freistich (kein Abfahren des ganzen Teils)
	for bi in [5, 6]:
		var fm: Array = sim2["moves"].filter(func(m): return int(m[3]) == bi and not bool(m[2]))
		var a := INF
		var b := -INF
		for m in fm:
			a = minf(a, float(m[0]))
			b = maxf(b, float(m[0]))
		ok(fm.size() > 0 and a > 69.0 and b < 78.0, "Satz %d bleibt am Freistich (Z %.2f..%.2f)" % [bi + 1, a - 100.0, b - 100.0])

	# --- 2b) Kontur mitten am Teil OHNE Hinterschnitte: trotzdem in Lagen zu D (nicht in einem Zug)
	# Die Tasche ist länger als die Platte breit ist (rund 30 mm): Erst dahinter erreicht die Schneide die
	# volle Tiefe, davor steht die Platte noch über dem Rohteil rechts der Kontur.
	var km := {"type": "contour", "name": "MITTE", "x0": 30.0, "z0": -20.0, "els": [
		el(30.0, -70.0), el(42.0, -70.0)]}
	l.new_workpiece(40.0, 100.0)
	var pm := NcCam.new_program("MITTE_HS0")
	pm["blocks"].append(km)
	pm["blocks"].append(rough("MITTE", "T1", 2.0, 0))
	var smm: Dictionary = NcCam.simulate(pm, l)
	var cuts := 0
	for m in smm["moves"]:
		if not bool(m[2]) and absf(float(m[1]) - 15.2) > 0.05 and float(m[0]) < 60.0:
			cuts += 1
	var pr_m: PackedFloat32Array = smm["prof"]
	ok(smm["errs"].is_empty() and cuts >= 2, "Kontur mitten am Teil ohne HS: mehrere Lagen (%d Züge)" % cuts)
	ok(absf(pr_m[int(38.0 / NcCam.SEG)] - 15.2) < 0.05 and absf(pr_m[int(95.0 / NcCam.SEG)] - 20.0) < 0.01,
		"Kontur mitten am Teil: Ø30,4 im Bereich, rechts Rohteil (%.2f / %.2f)" % [pr_m[int(38.0 / NcCam.SEG)] * 2.0, pr_m[int(95.0 / NcCam.SEG)] * 2.0])
	start(l, pm)
	ok(absf(l.radius_at(38.0) - 15.2) < 0.05 and absf(l.radius_at(95.0) - 20.0) < 0.01, "Kontur mitten am Teil an der Maschine (Ø%.2f)" % (l.radius_at(38.0) * 2.0))

	# --- 3) Einstich zwischen zwei Bunden: Schruppen mit Hinterschnitt räumt den Einstich (soweit
	#        die Platte hineinpasst), ohne Hinterschnitt bleibt er voll stehen.
	#        Der Einstich ist 40 mm breit, die Platte sticht rechts ein und ist rund 30 mm breit: Auf Maß
	#        liegt der Grund links davon, gemessen wird bei Z-55.
	var kn := {"type": "contour", "name": "HALS", "x0": 0.0, "z0": 0.0, "els": [
		el(30.0, 0.0), el(30.0, -20.0), el(20.0, -20.0), el(20.0, -60.0), el(30.0, -60.0),
		el(30.0, -75.0), el(42.0, -75.0)]}
	l.new_workpiece(40.0, 100.0)
	for hs in [1, 0]:
		var pn := NcCam.new_program("HALS_HS%d" % hs)
		pn["blocks"].append(kn)
		pn["blocks"].append(rough("HALS", "T1", 2.0, hs))
		var sn: Dictionary = NcCam.simulate(pn, l)
		ok(sn["errs"].is_empty(), "Hals HS%d: Simulation ohne Fehler %s" % [hs, sn["errs"]])
		var pr: PackedFloat32Array = sn["prof"]
		var r_neck := pr[int(45.0 / NcCam.SEG)]
		if hs == 1:
			ok(absf(r_neck - 10.2) < 0.05, "Hals mit Hinterschnitt geräumt (Ø%.2f bei Z-55)" % (r_neck * 2.0))
		else:
			ok(r_neck > 14.9, "Hals ohne Hinterschnitt bleibt stehen (Ø%.2f bei Z-55)" % (r_neck * 2.0))
		ok(absf(pr[int(90.0 / NcCam.SEG)] - 15.2) < 0.05, "Hals HS%d: Bund rechts Ø30,4 (%.2f)" % [hs, pr[int(90.0 / NcCam.SEG)] * 2.0])
	var ph := NcCam.new_program("HALS_MASCHINE")
	ph["blocks"].append(kn)
	ph["blocks"].append(rough("HALS", "T1", 2.0))
	start(l, ph)
	ok(absf(l.radius_at(45.0) - 10.2) < 0.05, "Hals an der Maschine geräumt (Ø%.2f)" % (l.radius_at(45.0) * 2.0))
	ok(absf(l.radius_at(90.0) - 15.2) < 0.05, "Bund rechts mit Aufmaß (Ø%.2f)" % (l.radius_at(90.0) * 2.0))
	ok(absf(l.radius_at(20.0) - 20.0) < 0.01, "links der Kontur Rohteil (Ø%.2f)" % (l.radius_at(20.0) * 2.0))
	# Enger Einstich (25 mm): Die Schruppplatte ist breiter und kommt nicht bis auf den Grund
	var kq := {"type": "contour", "name": "ENG", "x0": 0.0, "z0": 0.0, "els": [
		el(30.0, 0.0), el(30.0, -20.0), el(20.0, -20.0), el(20.0, -45.0), el(30.0, -45.0),
		el(30.0, -60.0), el(42.0, -60.0)]}
	l.new_workpiece(40.0, 100.0)
	var pq := NcCam.new_program("HALS_ENG")
	pq["blocks"].append(kq)
	pq["blocks"].append(rough("ENG", "T1", 2.0, 1))
	var sq: Dictionary = NcCam.simulate(pq, l)
	var wide: float = float(l.tool_by_id("T1")["zmax"]) - float(l.tool_by_id("T1")["zmin"])
	var r_eng: float = (sq["prof"] as PackedFloat32Array)[int(60.0 / NcCam.SEG)]
	ok(sq["errs"].is_empty() and wide > 25.0 and r_eng > 11.0 and r_eng < 15.0,
		"Enger Hals: Die %.1f mm breite Platte räumt nur, so weit sie hineinpasst (Ø%.2f)" % [wide, r_eng * 2.0])

	# --- 4) Zum Futter hin fallender Kegel (Hinterschnitt für einen Rechtsmeißel) mit Radius:
	#        T3 schruppt konturparallel hinein und schlichtet, nichts wird verletzt.
	var kk := {"type": "contour", "name": "KEGEL", "x0": 0.0, "z0": 0.0, "els": [
		el(30.0, 0.0, 1, 0.5), el(30.0, -10.0), el(22.0, -30.0, 2, 3.0), el(22.0, -40.0, 2, 1.0),
		el(36.0, -40.0), el(36.0, -50.0), el(42.0, -50.0)]}
	l.new_workpiece(40.0, 100.0)
	var pk := NcCam.new_program("KEGEL_FALLEND")
	pk["blocks"].append(kk)
	pk["blocks"].append(rough("KEGEL", "T3", 1.5))
	pk["blocks"].append(finish("KEGEL"))
	start(l, pk)
	ok(absf(l.radius_at(80.0) * 2.0 - 26.0) < 0.1, "Kegel Mitte Ø26 (%.3f)" % (l.radius_at(80.0) * 2.0))
	check_part(l, kk, -49.5, -0.5, 0.15, "fallender Kegel")

	# --- 5) Freistichzyklus: Gewinde DIN 76 (P1,5) und Form E (E1x0,4), jeweils Komplett mit T3
	ok(absf(float(NcCam.din76(1.5)[0]) - 2.3) < 0.001 and absf(float(NcCam.din76(1.5)[1]) - 3.2) < 0.001, "DIN 76: P1,5 -> dg = d-2,3, g1 = 3,2")
	var kz := {"type": "contour", "name": "ZAPFEN", "x0": 0.0, "z0": 0.0, "els": [
		el(20.0, 0.0, 1, 1.0), el(20.0, -30.0), el(30.0, -30.0), el(30.0, -55.0), el(42.0, -55.0)]}
	var u76 := NcCam.new_block("undercut")
	u76["x0"] = 20.0
	u76["z0"] = -30.0
	u76["p"] = 1.5
	var ue := NcCam.new_block("undercut")
	ue["form"] = 1
	ue["size"] = 3
	ue["x0"] = 30.0
	ue["z0"] = -55.0
	l.new_workpiece(40.0, 100.0)
	var pu := NcCam.new_program("FREISTICH_ZYKLUS")
	pu["blocks"].append(kz)
	pu["blocks"].append(rough("ZAPFEN", "T1", 2.0))
	pu["blocks"].append(finish("ZAPFEN"))
	pu["blocks"].append(u76)
	pu["blocks"].append(ue)
	ok(NcCam.summary(u76).begins_with("Freistich Gewinde DIN 76 P1.5"), "Arbeitsplan: %s" % NcCam.summary(u76))
	var su: Dictionary = NcCam.simulate(pu, l)
	start(l, pu)
	ok(absf(l.radius_at(71.5) * 2.0 - 17.7) < 0.1, "DIN 76: Freistichgrund Ø17,7 (%.3f)" % (l.radius_at(71.5) * 2.0))
	ok(absf(l.radius_at(85.0) * 2.0 - 20.0) < 0.05, "DIN 76: Gewinde-Ø20 bleibt (%.3f)" % (l.radius_at(85.0) * 2.0))
	ok(absf(l.radius_at(65.0) * 2.0 - 30.0) < 0.05, "DIN 76: Schulter Ø30 bleibt (%.3f)" % (l.radius_at(65.0) * 2.0))
	check_part(l, NcCam.undercut_contour(u76), -29.75, -25.0, 0.12, "Freistich DIN 76")
	ok(absf(l.radius_at(46.0) * 2.0 - 29.2) < 0.1, "Form E: Grund Ø29,2 (%.3f)" % (l.radius_at(46.0) * 2.0))
	ok(absf(l.radius_at(55.0) * 2.0 - 30.0) < 0.05, "Form E: Zylinder Ø30 rechts davon (%.3f)" % (l.radius_at(55.0) * 2.0))
	check_part(l, NcCam.undercut_contour(ue), -54.75, -51.5, 0.12, "Freistich Form E")
	var stray := 0
	for m in su["moves"]:
		if int(m[3]) == 4 and not bool(m[2]) and (float(m[0]) < 69.0 or float(m[0]) > 78.0):
			stray += 1
	ok(stray == 0, "Freistichzyklus bleibt am Freistich (%d Züge daneben)" % stray)

	# --- 6) Bedienung: Softkey Freistich legt den Satz über die Maske an
	var s = l.screen
	s.show_page("pm")
	s._pm_name.text = "fs test"
	s._pm_new()
	s._ed_new("undercut")
	ok(s.page == "form" and str(s._form_blk["type"]) == "undercut", "Maske Freistich offen")
	s._form_accept()
	var tp: Dictionary = s.prog_by_name("FS_TEST")
	ok(tp["blocks"].size() == 2 and str(tp["blocks"][1]["type"]) == "undercut", "Freistich im Arbeitsplan")
	s.show_page("sim")
	ok(s._sim_plot.moves.size() > 0, "Simulation zeigt Freistichbahn (%d)" % s._sim_plot.moves.size())

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
