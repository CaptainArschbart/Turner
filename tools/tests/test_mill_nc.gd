extends SceneTree
## NC-Kern der Fräse (MillNc): Parser, Formatierer, Übersetzer, Zyklen, Simulation. Reine Logik, keine Szene.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)

func tools_ctx() -> Dictionary:
	return {"tools": {1: MillTools.by_id("MK63"), 2: MillTools.by_id("F12"), 3: MillTools.by_id("B10"), 4: MillTools.by_id("F10")}}

## Programmrumpf in BEGIN/M30/END packen.
func prog(body: Array) -> Array:
	var out: Array = ["BEGIN PGM T MM"]
	out.append_array(body)
	out.append("M30")
	out.append("END PGM T MM")
	return out

func has_err(res: Dictionary, part: String) -> bool:
	for e in res["errs"]:
		if str(e).contains(part):
			return true
	return false

func mvs(ops: Array, rapid_filter := -1) -> Array:
	var out: Array = []
	for o in ops:
		if o["op"] == "mv":
			if rapid_filter == -1 or bool(o["rapid"]) == (rapid_filter == 1):
				out.append(o)
	return out

func at(sim: Dictionary, x: float, y: float) -> float:
	var nx: int = sim["nx"]
	var c: float = sim["cell"]
	var h: PackedFloat32Array = sim["h"]
	return h[int(y / c) * nx + int(x / c)]

func near(a: float, b: float, tol := 0.01) -> bool:
	return absf(a - b) <= tol

func _initialize() -> void:
	test_fmt()
	test_parse()
	test_format()
	test_samples()
	test_cycle_200()
	test_arc()
	test_motion()
	test_labels()
	test_errors()
	test_pockets()
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()

func test_fmt() -> void:
	ok(MillNc.fmt(50.0) == "+50", "fmt +50")
	ok(MillNc.fmt(-10.5) == "-10.5", "fmt -10.5")
	ok(MillNc.fmt(0.0) == "+0", "fmt 0")
	ok(MillNc.fmt(-0.0001) == "+0", "fmt -0.0001")
	ok(MillNc.fmt(1.23456) == "+1.235", "fmt 3 Nachkommastellen")
	ok(MillNc.fmt(100.0) == "+100", "fmt 100")
	ok(MillNc.fmt(10.0) == "+10", "fmt 10")
	ok(MillNc.fmt(0.5) == "+0.5", "fmt 0.5")
	ok(MillNc.fmt(-2.0) == "-2", "fmt -2")

func test_parse() -> void:
	ok(MillNc.parse_line("")["type"] == "empty", "leer")
	ok(MillNc.parse_line("   \t ")["type"] == "empty", "nur Leerzeichen")
	var c := MillNc.parse_line("; Das ist ein Kommentar")
	ok(c["type"] == "comment" and c["text"] == "Das ist ein Kommentar", "Kommentar")
	var b := MillNc.parse_line("BEGIN PGM Test MM")
	ok(b["type"] == "begin" and b["name"] == "TEST", "begin")
	b = MillNc.parse_line("0 begin pgm Test mm")
	ok(b["type"] == "begin" and b["name"] == "TEST", "begin mit Satznummer")
	b = MillNc.parse_line("END PGM TEST MM")
	ok(b["type"] == "end" and b["name"] == "TEST", "end")
	b = MillNc.parse_line("BLK FORM 0.1 Z X+0 Y+0 Z-40")
	ok(b["type"] == "blk_form" and b["idx"] == 1 and b["x"] == 0.0 and b["z"] == -40.0, "blk 0.1")
	b = MillNc.parse_line("BLK FORM 0.2 X+100 Y+60 Z+0")
	ok(b["type"] == "blk_form" and b["idx"] == 2 and b["x"] == 100.0 and b["y"] == 60.0, "blk 0.2")
	b = MillNc.parse_line("TOOL CALL 1 Z S1200 F300")
	ok(b["type"] == "tool_call" and b["t"] == 1 and b["s"] == 1200.0 and b["f"] == 300.0, "tool call mit F")
	b = MillNc.parse_line("tool call 5 z s800")
	ok(b["type"] == "tool_call" and b["t"] == 5 and b["s"] == 800.0 and not b.has("f"), "tool call ohne F")
	b = MillNc.parse_line("L X+50 Y-10,5 Z+2 R0 F300 M3")
	ok(b["type"] == "l" and b["x"] == 50.0 and b["y"] == -10.5 and b["z"] == 2.0 and b["r"] == "R0" and b["f"] == 300.0 and b["m"] == [3], "L voll")
	b = MillNc.parse_line("  l   x10   ")
	ok(b["type"] == "l" and b["x"] == 10.0 and not b.has("y") and not b.has("f") and b["m"] == [], "L klein und Leerzeichen")
	b = MillNc.parse_line("12 L IX+5 IZ-1 FMAX M13 M99")
	ok(b["type"] == "l" and b["x"] == 5.0 and b["ix"] == true and b["z"] == -1.0 and b["iz"] == true and not b.has("iy") and b["fmax"] == true and b["m"] == [13, 99], "L inkremental FMAX M")
	b = MillNc.parse_line("L X50 ; Kommentar am Ende")
	ok(b["type"] == "l" and b["x"] == 50.0, "L mit Endkommentar")
	b = MillNc.parse_line("L X +5 Y -3")
	ok(b["type"] == "l" and b["x"] == 5.0 and b["y"] == -3.0, "L mit Leerzeichen nach Vorzeichen")
	b = MillNc.parse_line("L X+1 RL")
	ok(b["type"] == "l" and b["r"] == "RL", "L RL wird gelesen")
	b = MillNc.parse_line("CC X+10 Y+20")
	ok(b["type"] == "cc" and b["x"] == 10.0 and b["y"] == 20.0, "CC")
	b = MillNc.parse_line("C X+0 Y+10 DR- F200 M8")
	ok(b["type"] == "c" and b["dr"] == -1 and b["f"] == 200.0 and b["m"] == [8], "C DR-")
	b = MillNc.parse_line("C IX+5 Y+0 DR+")
	ok(b["type"] == "c" and b["dr"] == 1 and b["ix"] == true, "C DR+ inkremental")
	b = MillNc.parse_line("CYCL DEF 200 BOHREN Q200=+2 Q201=-25 Q211=+0,5")
	ok(b["type"] == "cycl_def" and b["cycle"] == 200 and b["name"] == "BOHREN" and b["q"][201] == -25.0 and b["q"][211] == 0.5 and b["q"][200] == 2.0, "CYCL DEF")
	b = MillNc.parse_line("cycl def 251 q218 = +50 q219=+30")
	ok(b["type"] == "cycl_def" and b["name"] == "" and b["q"][218] == 50.0 and b["q"][219] == 30.0, "CYCL DEF klein, ohne Name")
	b = MillNc.parse_line("CYCL CALL M3")
	ok(b["type"] == "cycl_call" and b["m"] == [3], "CYCL CALL M3")
	b = MillNc.parse_line("CYCL CALL")
	ok(b["type"] == "cycl_call" and b["m"] == [], "CYCL CALL")
	b = MillNc.parse_line("M3")
	ok(b["type"] == "m" and b["m"] == [3], "M3")
	b = MillNc.parse_line("M8 M3")
	ok(b["type"] == "m" and b["m"] == [8, 3], "M8 M3")
	ok(MillNc.parse_line("STOP")["type"] == "stop", "STOP")
	b = MillNc.parse_line("LBL 3")
	ok(b["type"] == "lbl" and b["n"] == 3, "LBL")
	b = MillNc.parse_line("CALL LBL 3 REP 5")
	ok(b["type"] == "call_lbl" and b["n"] == 3 and b["rep"] == 5, "CALL LBL REP")
	b = MillNc.parse_line("CALL LBL 2")
	ok(b["type"] == "call_lbl" and b["n"] == 2 and b["rep"] == 0, "CALL LBL ohne REP")
	# Fehlerfälle
	for bad in ["FOO", "L Xabc", "L Q5", "L X", "C X+1 Y+1", "TOOL CALL", "CALL LBL x", "BLK FORM 0.3 X+1",
			"CYCL DEF", "CYCL DEF 200 BOHREN Q200=abc", "BEGIN TEST", "BLK FORM 0.2 X+1 Y+1", "L X+1 R5", "CC X+1", "LBL", "L X+1 ?"]:
		var e := MillNc.parse_line(bad)
		ok(e["type"] == "error" and str(e.get("err", "")) != "", "Fehler: " + bad)

func test_format() -> void:
	var zeilen := [
		"BEGIN PGM TEST MM", "END PGM TEST MM", "BLK FORM 0.1 Z X+0 Y+0 Z-40", "BLK FORM 0.2 X+100 Y+60 Z+0",
		"TOOL CALL 1 Z S1200 F300", "TOOL CALL 2 Z S800", "L X+50 Y-10.5 Z+2 R0 F300 M3", "L IX+5 IZ-1 FMAX M13 M99",
		"L Z+100 R0 FMAX", "L", "L M99", "CC X+10 Y+20", "C X+0 Y+10 DR- F200 M8", "C IX+5 IY+2.25 DR+",
		"CYCL DEF 200 BOHREN Q200=+2 Q201=-25 Q206=+120 Q202=+5 Q210=+0 Q203=+0 Q204=+50 Q211=+0.5",
		"CYCL DEF 251 RECHTECKTASCHE Q218=+50 Q219=+30", "CYCL DEF 233 PLANFRAESEN Q225=+0 Q386=-2 Q999=+7",
		"CYCL CALL", "CYCL CALL M3 M8", "M3", "M8 M3", "M5 M9", "STOP", "LBL 3", "LBL 0", "CALL LBL 3 REP 5", "CALL LBL 2", "; Kommentar", ""]
	for z in zeilen:
		var b := MillNc.parse_line(z)
		var t := MillNc.format_block(b)
		var b2 := MillNc.parse_line(t)
		ok(b2 == b, "Rundlauf: '%s' -> '%s'" % [z, t])
	ok(MillNc.format_block(MillNc.parse_line("l  x50 y-10,5 r0 f300 m3")) == "L X+50 Y-10.5 R0 F300 M3", "format normalisiert L")
	ok(MillNc.format_block(MillNc.parse_line("12 begin pgm abc mm")) == "BEGIN PGM ABC MM", "format begin")
	ok(MillNc.format_block(MillNc.parse_line("TOOL CALL 1 Z S1200 F300")) == "TOOL CALL 1 Z S1200 F300", "format tool call")
	ok(MillNc.format_block(MillNc.parse_line("CALL LBL 1 REP 2")) == "CALL LBL 1 REP 2", "format call lbl")
	ok(MillNc.format_block(MillNc.parse_line("BLK FORM 0.1 Z X+0 Y+0 Z-40")) == "BLK FORM 0.1 Z X+0 Y+0 Z-40", "format blk 0.1")
	var d := MillNc.format_block(MillNc.parse_line("cycl def 200 bohren q201=-25 q200=2"))
	ok(d == "CYCL DEF 200 BOHREN Q200=+2 Q201=-25", "format cycl def sortiert nach Dialogreihenfolge: " + d)
	# alle Zyklen: Standardwerte ergeben einen lesbaren Satz
	for no in MillNc.CYCLES:
		var q := {}
		for e in MillNc.CYCLES[no]["q"]:
			q[int(e[0])] = float(e[2])
		var t := MillNc.format_block({"type": "cycl_def", "cycle": no, "name": MillNc.CYCLES[no]["name"], "q": q})
		var b := MillNc.parse_line(t)
		ok(b["type"] == "cycl_def" and b["cycle"] == no and b["q"] == q, "Zyklus %d Standardsatz" % no)

func test_samples() -> void:
	var t0 := Time.get_ticks_msec()
	var sams := MillNc.samples()
	ok(sams.size() == 3 and MillNc.SAMPLES.size() == 3, "drei Beispielprogramme")
	var size := Vector3(100, 60, 40)
	var simd := {}
	for s in sams:
		var nm: String = s["name"]
		var res := MillNc.compile(s["lines"], tools_ctx())
		ok(res["errs"].is_empty(), "%s ohne Fehler: %s" % [nm, str(res["errs"])])
		ok(res["name"] == nm, nm + " Name")
		ok(res["blk"].has("min") and res["blk"]["min"] == Vector3(0, 0, -40) and res["blk"]["max"] == Vector3(100, 60, 0), nm + " Rohteil")
		ok(res["time"] > 10.0 and res["time"] < 3000.0, nm + " Laufzeit plausibel: %s" % str(res["time"]))
		var ops: Array = res["ops"]
		ok(ops.back()["op"] == "end", nm + " endet mit end")
		var n_end := 0
		var i_blk := -1
		var i_tool := -1
		var i_spin := -1
		var i_mv := -1
		for i in ops.size():
			var o: Dictionary = ops[i]
			match o["op"]:
				"end": n_end += 1
				"blk": if i_blk < 0: i_blk = i
				"tool": if i_tool < 0: i_tool = i
				"spindle": if i_spin < 0 and o["on"]: i_spin = i
				"mv": if i_mv < 0: i_mv = i
		ok(n_end == 1, nm + " genau ein end")
		ok(i_blk >= 0 and i_blk < i_tool and i_tool < i_spin and i_spin < i_mv, nm + " Reihenfolge blk/tool/spindle/mv: %d %d %d %d" % [i_blk, i_tool, i_spin, i_mv])
		var last_spin: Dictionary = {}
		for o in ops:
			if o["op"] == "spindle":
				last_spin = o
		ok(not last_spin.is_empty() and last_spin["on"] == false, nm + " Spindel am Ende aus")
		var zmax := -1000.0
		for m in mvs(ops):
			zmax = maxf(zmax, m["to"].z)
		ok(near(zmax, 100.0), nm + " fährt auf Z+100")
		ok(near(ops[ops.size() - 2]["to"].z if ops[ops.size() - 2].has("to") else 100.0, 100.0), nm + " letzte Fahrt auf Z+100")
		simd[nm] = MillNc.simulate(ops, tools_ctx()["tools"], size, 1.0)
	# PLANEN: überall -2
	var sp: Dictionary = simd["PLANEN"]
	var h: PackedFloat32Array = sp["h"]
	ok(sp["nx"] == 100 and sp["ny"] == 60 and h.size() == 6000, "Karte 100x60")
	var lo := 0.0
	var hi := -100.0
	for v in h:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	ok(lo > -2.2 and hi < -1.8, "Planfläche überall -2 (min %f max %f)" % [lo, hi])
	# TASCHE
	var st: Dictionary = simd["TASCHE"]
	var bad_in := 0
	var bad_out := 0
	for j in 60:
		for i in 100:
			var x := i + 0.5
			var y := j + 0.5
			var v: float = st["h"][j * 100 + i]
			if x >= 27.0 and x <= 73.0 and y >= 17.0 and y <= 43.0:
				if absf(v + 10.0) > 0.2:
					bad_in += 1
			elif x < 24.0 or x > 76.0 or y < 14.0 or y > 46.0:
				if absf(v) > 0.001:
					bad_out += 1
	ok(bad_in == 0, "Taschenboden -10 überall im Innenbereich (falsch: %d)" % bad_in)
	ok(bad_out == 0, "außerhalb der Tasche unberührt (falsch: %d)" % bad_out)
	ok(near(at(st, 26.0, 16.0), 0.0, 20.0), "Ecke zählt nicht")
	ok(at(st, 25.5, 30.5) < -9.8 and at(st, 74.5, 30.5) < -9.8, "Taschenränder links/rechts")
	ok(at(st, 24.5, 30.5) < -9.8 and at(st, 75.5, 30.5) < -9.8 and at(st, 50.5, 14.5) < -9.8 and at(st, 50.5, 45.5) < -9.8, "Tasche je Seite 0,75 mm größer (Eckenradius des Fräsers)")
	ok(near(at(st, 23.5, 30.5), 0.0, 0.001) and near(at(st, 76.5, 30.5), 0.0, 0.001), "Tasche bleibt innerhalb der Toleranz")
	# BOHRBILD
	var sb: Dictionary = simd["BOHRBILD"]
	ok(near(at(sb, 25.0, 30.0), -25.0, 0.2) and near(at(sb, 75.0, 30.0), -25.0, 0.2), "Bohrungen auf -25")
	ok(near(at(sb, 22.0, 28.0), -25.0, 0.2) and near(at(sb, 28.0, 32.0), -25.0, 0.2), "Bohrungsrand innen")
	ok(near(at(sb, 33.0, 30.0), 0.0, 0.001) and near(at(sb, 50.0, 30.0), 0.0, 0.001) and near(at(sb, 25.0, 40.0), 0.0, 0.001) and near(at(sb, 18.0, 30.0), 0.0, 0.001), "neben den Bohrungen 0")
	var ms := Time.get_ticks_msec() - t0
	ok(ms < 1500, "Beispiele und Simulation schnell genug (%d ms)" % ms)
	print("  Beispiele inkl. Simulation: %d ms" % ms)
	# ohne tools-Kontext: jedes T vorhanden
	var res2 := MillNc.compile(sams[1]["lines"])
	ok(res2["errs"].is_empty(), "ohne tools-ctx keine Fehler")
	ok(res2["tools"] == [2], "benutzte Werkzeuge [2]")

func test_cycle_200() -> void:
	var lines := prog([
		"TOOL CALL 3 Z S1000",
		"CYCL DEF 200 BOHREN Q200=+2 Q201=-25 Q206=+100 Q202=+5 Q203=+0 Q204=+50",
		"L X+10 Y+10 R0 FMAX M3 M99",
		"L X+30 Y+10 R0 FMAX",
	])
	var res := MillNc.compile(lines, tools_ctx())
	ok(res["errs"].is_empty(), "Bohrzyklus ohne Fehler: " + str(res["errs"]))
	var feeds := mvs(res["ops"], 0)
	ok(feeds.size() == 5, "5 Bohrstufen (M99 nur an dem einen Satz): %d" % feeds.size())
	var zs: Array = []
	for f in feeds:
		zs.append(f["to"].z)
	ok(zs == [-5.0, -10.0, -15.0, -20.0, -25.0], "Stufen -5..-25: " + str(zs))
	var rap_up := 0
	for m in mvs(res["ops"], 1):
		if near(m["to"].z, 2.0) and near(m["to"].x, 10.0):
			rap_up += 1
	ok(rap_up == 6, "Anfahren + 4 Entspan-Rückzüge + Endrückzug auf Sicherheitsabstand: %d" % rap_up)
	var all_xy := true
	for m in mvs(res["ops"]):
		if m["n"] == 3 and (not near(m["to"].x, 10.0) or not near(m["to"].y, 10.0)):
			all_xy = false
	ok(all_xy, "Bohrzyklus bleibt auf der Position")
	var mvl := mvs(res["ops"])
	ok(near(mvl[mvl.size() - 2]["to"].z, 50.0) and near(mvl[mvl.size() - 3]["to"].z, 2.0), "Endrückzug auf Q204 über Sicherheitsabstand")
	# Verweilzeit unten
	lines = prog(["TOOL CALL 3 Z S1000", "CYCL DEF 200 BOHREN Q201=-10 Q202=+10 Q206=+100 Q211=+1.5 Q210=+0.5",
		"M3", "CYCL CALL"])
	res = MillNc.compile(lines, tools_ctx())
	var dw := 0.0
	for o in res["ops"]:
		if o["op"] == "dwell":
			dw += o["t"]
	ok(near(dw, 1.5), "Verweilzeit unten 1.5 s (Q210 nur bei Entspanen): %f" % dw)
	# Entspanen mit Q210
	lines = prog(["TOOL CALL 3 Z S1000", "CYCL DEF 200 BOHREN Q201=-10 Q202=+5 Q206=+100 Q210=+0.5",
		"M3", "CYCL CALL"])
	res = MillNc.compile(lines, tools_ctx())
	dw = 0.0
	for o in res["ops"]:
		if o["op"] == "dwell":
			dw += o["t"]
	ok(near(dw, 0.5), "Verweilzeit oben einmal: %f" % dw)
	# CYCL CALL mit M-Funktion im Satz
	lines = prog(["TOOL CALL 3 Z S1000", "CYCL DEF 200 BOHREN Q201=-10 Q202=+5 Q206=+100", "CYCL CALL M3"])
	res = MillNc.compile(lines, tools_ctx())
	ok(res["errs"].is_empty(), "CYCL CALL M3 startet die Spindel vor dem Zyklus: " + str(res["errs"]))
	ok(MillNc.compile(prog(["TOOL CALL 3 Z S1000", "CYCL DEF 200 BOHREN Q201=-10 Q202=+5 Q206=+100", "CYCL CALL"]), tools_ctx())["errs"].size() == 1, "ohne Spindel Fehler")

func test_arc() -> void:
	var head := ["TOOL CALL 4 Z S1000 F200", "M3", "L X+10 Y+0 R0 FMAX", "CC X+0 Y+0"]
	var res := MillNc.compile(prog(head + ["C X+0 Y+10 DR+"]), tools_ctx())
	ok(res["errs"].is_empty(), "Kreis ohne Fehler: " + str(res["errs"]))
	var feeds := mvs(res["ops"], 0)
	ok(feeds.size() >= 10, "Viertelkreis aus mehreren Sehnen: %d" % feeds.size())
	var all_r := true
	var quarter := true
	for f in feeds:
		var p: Vector3 = f["to"]
		if absf(Vector2(p.x, p.y).length() - 10.0) > 0.001:
			all_r = false
		if p.x < -0.001 or p.y < -0.001:
			quarter = false
	ok(all_r, "alle Punkte auf dem Kreis R10")
	ok(quarter, "DR+ ist der kurze Weg gegen den Uhrzeigersinn")
	var lastp: Vector3 = feeds.back()["to"]
	ok(near(lastp.x, 0.0, 0.001) and near(lastp.y, 10.0, 0.001), "Endpunkt (0, 10)")
	# Sehnenfehler
	var maxd := 0.0
	for i in range(1, feeds.size()):
		var a: Vector3 = feeds[i - 1]["to"]
		var b: Vector3 = feeds[i]["to"]
		var mid := Vector2((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
		maxd = maxf(maxd, 10.0 - mid.length())
	ok(maxd <= 0.021, "Sehnenfehler <= 0.02 (%f)" % maxd)
	# DR-: langer Weg im Uhrzeigersinn
	res = MillNc.compile(prog(head + ["C X+0 Y+10 DR-"]), tools_ctx())
	feeds = mvs(res["ops"], 0)
	var neg := false
	var all_r2 := true
	for f in feeds:
		var p: Vector3 = f["to"]
		if p.x < -5.0 and p.y < 0.0:
			neg = true
		if absf(Vector2(p.x, p.y).length() - 10.0) > 0.001:
			all_r2 = false
	ok(neg and all_r2, "DR- läuft 270 Grad im Uhrzeigersinn")
	var lastn: Vector3 = feeds.back()["to"]
	ok(near(lastn.y, 10.0, 0.001) and near(lastn.x, 0.0, 0.001), "DR- Endpunkt")
	# Vollkreis
	res = MillNc.compile(prog(head + ["C X+10 Y+0 DR+"]), tools_ctx())
	feeds = mvs(res["ops"], 0)
	var minx := 100.0
	var maxy := -100.0
	for f in feeds:
		minx = minf(minx, f["to"].x)
		maxy = maxf(maxy, f["to"].y)
	ok(minx < -9.9 and maxy > 9.9, "Vollkreis geht ganz herum")
	ok(feeds.size() > 40 and near(feeds.back()["to"].x, 10.0, 0.001) and near(feeds.back()["to"].y, 0.0, 0.001), "Vollkreis endet am Start")
	# Endpunkt nicht auf dem Kreis
	res = MillNc.compile(prog(head + ["C X+0 Y+11 DR+"]), tools_ctx())
	ok(has_err(res, "nicht auf dem Kreis"), "Endpunkt abseits des Kreises: " + str(res["errs"]))
	# Kreis mit Mittelpunkt außerhalb des Ursprungs
	res = MillNc.compile(prog(["TOOL CALL 4 Z S1000 F200", "M3", "L X+30 Y+20 R0 FMAX", "CC X+20 Y+20", "C X+10 Y+20 DR+"]), tools_ctx())
	feeds = mvs(res["ops"], 0)
	var cok := feeds.size() > 5
	var miny := 100.0
	for f in feeds:
		cok = cok and absf(Vector2(f["to"].x - 20.0, f["to"].y - 20.0).length() - 10.0) < 0.001
		miny = minf(miny, f["to"].y)
	ok(cok and miny > 19.99, "Halbkreis um CC (20, 20) gegen den Uhrzeigersinn, nur obere Hälfte")

func test_motion() -> void:
	# inkremental
	var res := MillNc.compile(prog(["TOOL CALL 2 Z S1000 F100", "M3", "L X+10 Y+10 Z+50 R0 FMAX", "L IX+5 IY-2 IZ-1 F100"]), tools_ctx().merged({"pos": Vector3(0, 0, 50)}))
	var m := mvs(res["ops"])
	ok(res["errs"].is_empty(), "inkremental ohne Fehler: " + str(res["errs"]))
	ok(m.size() == 2 and m[1]["to"] == Vector3(15, 8, 49) and m[1]["rapid"] == false and m[1]["f"] == 100.0, "L IX+5 IY-2 IZ-1 -> (15, 8, 49)")
	ok(m[0]["rapid"] == true and m[0]["f"] == MillNc.RAPID, "FMAX ist Eilgang")
	# nicht programmierte Achsen bleiben stehen, F modal, FMAX nur satzweise
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "M3", "L X+10 Y+5 F300", "L X+20 FMAX", "L X+30", "L Y+9 F150", "L X+40"]), tools_ctx())
	m = mvs(res["ops"])
	ok(res["errs"].is_empty(), "F modal ohne Fehler: " + str(res["errs"]))
	ok(m.size() == 5, "5 Fahrten")
	ok(m[0]["f"] == 300.0 and not m[0]["rapid"], "F300")
	ok(m[1]["rapid"] and m[1]["to"] == Vector3(20, 5, 100), "FMAX Eilgang, Y/Z bleiben")
	ok(not m[2]["rapid"] and m[2]["f"] == 300.0, "danach wieder F300 (modal)")
	ok(m[3]["f"] == 150.0 and m[4]["f"] == 150.0, "neues F bleibt")
	# M-Funktionen: Reihenfolge an einem Satz
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "L X+10 FMAX M13", "L X+20 FMAX M5 M9", "M0", "STOP"]), tools_ctx())
	var kinds: Array = []
	for o in res["ops"]:
		if o["op"] != "blk" and o["op"] != "tool":
			kinds.append(o["op"])
	ok(kinds == ["spindle", "coolant", "mv", "mv", "spindle", "coolant", "stop", "stop", "end"], "M13 am Anfang, M5/M9 am Ende, M0/STOP: " + str(kinds))
	ok(res["errs"].is_empty(), "M-Funktionen ohne Fehler: " + str(res["errs"]))
	# M30 schaltet Spindel und KSS ab
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "M13", "L X+20 FMAX"]), tools_ctx())
	var tail: Array = res["ops"].slice(res["ops"].size() - 3)
	ok(tail[0]["op"] == "spindle" and tail[0]["on"] == false and tail[1]["op"] == "coolant" and tail[1]["on"] == false and tail[2]["op"] == "end", "M30 schaltet alles ab")
	# M4
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "M4"]), tools_ctx())
	var s4: Dictionary = {}
	for o in res["ops"]:
		if o["op"] == "spindle":
			s4 = o
			break
	ok(s4.get("on", false) == true and s4.get("ccw", false) == true, "M4 Spindel links")
	# Werkzeugwechsel mit laufender Spindel: Spindel wird erst abgeschaltet
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "M3", "TOOL CALL 3 Z S500"]), tools_ctx())
	var seq: Array = []
	for o in res["ops"]:
		if o["op"] == "tool" or o["op"] == "spindle":
			seq.append(o["op"] + (str(o["on"]).capitalize() if o["op"] == "spindle" else str(o["t"])))
	ok(seq == ["tool2", "spindleTrue", "spindleFalse", "tool3", "spindleFalse"] or seq == ["tool2", "spindleTrue", "spindleFalse", "tool3"], "Werkzeugwechsel stoppt Spindel: " + str(seq))
	ok(res["tools"] == [2, 3], "benutzte Werkzeuge in Reihenfolge")
	# Startposition und Zeit
	res = MillNc.compile(prog(["L X+1000 FMAX"]), {"pos": Vector3(0, 0, 0)})
	ok(near(res["time"], 5.0, 0.01), "1000 mm im Eilgang = 5 s (%f)" % res["time"])

func test_labels() -> void:
	var head := ["TOOL CALL 2 Z S1000 F200", "M3", "L X+0 Y+0 R0 FMAX"]
	var res := MillNc.compile(prog(head + ["LBL 1", "L IX+1", "CALL LBL 1 REP 3"]), tools_ctx())
	ok(res["errs"].is_empty(), "Wiederholung ohne Fehler: " + str(res["errs"]))
	var m := mvs(res["ops"])
	ok(m.back()["to"].x == 4.0, "LBL/REP 3: Teil läuft 4x -> X4 (%s)" % str(m.back()["to"]))
	# Unterprogramm (hinter M30)
	var lines := ["BEGIN PGM T MM"] + head + ["CALL LBL 5", "CALL LBL 5", "M30", "LBL 5", "L IX+10", "LBL 0", "END PGM T MM"]
	res = MillNc.compile(lines, tools_ctx())
	ok(res["errs"].is_empty(), "Unterprogramm ohne Fehler: " + str(res["errs"]))
	m = mvs(res["ops"])
	ok(m.back()["to"].x == 20.0, "Unterprogramm zweimal -> X20")
	# Unterprogramm mit REP: ruft 1 + 2 mal
	lines = ["BEGIN PGM T MM"] + head + ["CALL LBL 5 REP 2", "M30", "LBL 5", "L IX+10", "LBL 0", "END PGM T MM"]
	res = MillNc.compile(lines, tools_ctx())
	ok(mvs(res["ops"]).back()["to"].x == 30.0, "Unterprogramm mit REP 2 -> 3 Läufe")
	# geschachtelt
	lines = ["BEGIN PGM T MM"] + head + ["CALL LBL 1", "M30", "LBL 1", "CALL LBL 2", "CALL LBL 2", "LBL 0", "LBL 2", "L IX+1", "LBL 0", "END PGM T MM"]
	res = MillNc.compile(lines, tools_ctx())
	ok(res["errs"].is_empty() and mvs(res["ops"]).back()["to"].x == 2.0, "geschachtelte Unterprogramme")
	# zu tief
	lines = ["BEGIN PGM T MM"] + head + ["CALL LBL 1", "M30", "LBL 1", "CALL LBL 1", "LBL 0", "END PGM T MM"]
	res = MillNc.compile(lines, tools_ctx())
	ok(has_err(res, "zu tief"), "Rekursion bricht ab: " + str(res["errs"]))
	# Endlosschleife
	res = MillNc.compile(prog(head + ["LBL 1", "L IX+0.1", "CALL LBL 1 REP 9999999"]), tools_ctx())
	ok(has_err(res, "endlos"), "Endlosschleife erkannt: " + str(res["errs"]))
	ok(res["ops"].size() > 1000 and res["ops"].back()["op"] != "end", "Endlosschleife: Teilergebnis, kein end")
	# Label nicht gefunden
	res = MillNc.compile(prog(head + ["CALL LBL 9"]), tools_ctx())
	ok(has_err(res, "LBL 9 nicht gefunden"), "LBL nicht gefunden")

func test_errors() -> void:
	var res := MillNc.compile(prog(["TOOL CALL 5 Z S1000"]), tools_ctx())
	ok(has_err(res, "Satz 1: Werkzeug T5 ist nicht im Magazin"), "leerer Magazinplatz: " + str(res["errs"]))
	ok(not res["errs"].is_empty(), "errs nicht leer")
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000 F100", "L X+10"]), tools_ctx())
	ok(has_err(res, "Satz 2: Spindel dreht nicht: M3 fehlt"), "M3 fehlt: " + str(res["errs"]))
	res = MillNc.compile(prog(["L X+10 F100"]), tools_ctx())
	ok(has_err(res, "TOOL CALL fehlt"), "Vorschub ohne Werkzeug: " + str(res["errs"]))
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "M3", "L X+10"]), tools_ctx())
	ok(has_err(res, "F fehlt"), "F fehlt: " + str(res["errs"]))
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "M3", "L X+10 RL F100"]), tools_ctx())
	ok(has_err(res, "Radiuskorrektur RL/RR wird noch nicht unterstützt, mit R0 programmieren"), "RL: " + str(res["errs"]))
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "M3", "L X+10 RR F100"]), tools_ctx())
	ok(has_err(res, "Radiuskorrektur"), "RR")
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "CYCL DEF 999 FOO Q1=+2"]), tools_ctx())
	ok(has_err(res, "Unbekannte Zyklusnummer 999"), "unbekannter Zyklus: " + str(res["errs"]))
	res = MillNc.compile(prog(["TOOL CALL 1 Z S500", "L X+50 Y+30 R0 FMAX M3",
		"CYCL DEF 251 RECHTECKTASCHE Q218=+50 Q219=+30 Q201=-10 Q202=+3 Q206=+100 Q207=+300", "CYCL CALL"]), tools_ctx())
	ok(has_err(res, "Werkzeug-Radius zu groß"), "Messerkopf zu groß für Tasche: " + str(res["errs"]))
	res = MillNc.compile(prog(["TOOL CALL 3 Z S500", "L X+50 Y+30 R0 FMAX M3",
		"CYCL DEF 251 RECHTECKTASCHE Q218=+50 Q219=+30 Q201=-10 Q202=+3 Q206=+100 Q207=+300", "CYCL CALL"]), tools_ctx())
	ok(has_err(res, "Bohrer"), "Bohrer im Fräszyklus: " + str(res["errs"]))
	res = MillNc.compile(prog(["TOOL CALL 3 Z S500", "M3", "CYCL DEF 233 PLANFRAESEN Q386=-1", "CYCL CALL"]), tools_ctx())
	ok(has_err(res, "Bohrer"), "Bohrer im Planfräszyklus")
	var lim := {"min": Vector3(-10, -10, -50), "max": Vector3(110, 70, 120)}
	res = MillNc.compile(prog(["L X+200 FMAX"]), {"limits": lim})
	ok(has_err(res, "Satz 1: Endschalter X+"), "Endschalter X+: " + str(res["errs"]))
	res = MillNc.compile(prog(["L Y-20 FMAX"]), {"limits": lim})
	ok(has_err(res, "Endschalter Y-"), "Endschalter Y-")
	res = MillNc.compile(prog(["L Z-60 FMAX"]), {"limits": lim})
	ok(has_err(res, "Endschalter Z-"), "Endschalter Z-")
	res = MillNc.compile(prog(["L X+100 FMAX"]), {"limits": lim})
	ok(res["errs"].is_empty(), "innerhalb der Grenzen keine Fehler")
	res = MillNc.compile(["BEGIN PGM T MM", "M30"], tools_ctx())
	ok(has_err(res, "END PGM fehlt"), "END PGM fehlt: " + str(res["errs"]))
	res = MillNc.compile(["M30", "END PGM T MM"], tools_ctx())
	ok(has_err(res, "BEGIN PGM fehlt"), "BEGIN PGM fehlt")
	res = MillNc.compile([], tools_ctx())
	ok(has_err(res, "BEGIN PGM fehlt") and has_err(res, "END PGM fehlt"), "leeres Programm")
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000 F100", "M3", "C X+1 Y+1 DR+"]), tools_ctx())
	ok(has_err(res, "C ohne CC"), "C ohne CC: " + str(res["errs"]))
	res = MillNc.compile(prog(["TOOL CALL 2 Z S99999", "TOOL CALL 2 Z S0"]), tools_ctx())
	ok(has_err(res, "Satz 1: Drehzahl") and has_err(res, "Satz 2: Drehzahl"), "S größer S_MAX und S = 0: " + str(res["errs"]))
	res = MillNc.compile(prog(["TOOL CALL 0 Z S1000"]), tools_ctx())
	ok(not res["errs"].is_empty(), "TOOL CALL 0 ist ein Fehler")
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "CYCL CALL"]), tools_ctx())
	ok(has_err(res, "Zyklusaufruf ohne CYCL DEF"), "Zyklusaufruf ohne CYCL DEF")
	res = MillNc.compile(prog(["TOOL CALL 3 Z S1000", "M3", "CYCL DEF 200 BOHREN Q201=+5", "CYCL CALL"]), tools_ctx())
	ok(has_err(res, "Q201"), "positive Tiefe Q201: " + str(res["errs"]))
	res = MillNc.compile(prog(["TOOL CALL 3 Z S1000", "M3", "CYCL DEF 200 BOHREN Q201=-5 Q202=+0", "CYCL CALL"]), tools_ctx())
	ok(has_err(res, "Q202"), "Zustell-Tiefe 0")
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "M3", "CYCL DEF 251 RECHTECKTASCHE Q224=+45", "CYCL CALL"]), tools_ctx())
	ok(has_err(res, "Q224"), "Drehlage Q224 ungleich 0")
	res = MillNc.compile(prog(["TOOL CALL 2 Z S1000", "M3", "CYCL DEF 253 NUTENFRAESEN Q374=+45", "CYCL CALL"]), tools_ctx())
	ok(has_err(res, "Q374"), "Nut Drehlage 45")
	res = MillNc.compile(prog(["FOO BAR", "TOOL CALL 2 Z S1000"]), tools_ctx())
	ok(has_err(res, "Satz 1:"), "Zeilenindex im Fehler: " + str(res["errs"]))
	res = MillNc.compile(prog(["M7"]), tools_ctx())
	ok(has_err(res, "M7"), "unbekannte M-Funktion")
	# Anfangswerkzeug im ctx
	res = MillNc.compile(prog(["M3", "L X+10 F100"]), tools_ctx().merged({"t": 2}))
	ok(res["errs"].is_empty(), "Werkzeug aus ctx t: " + str(res["errs"]))
	# Syntaxfehler zeigen den Satzindex
	res = MillNc.compile(prog(["", "L Xabc"]), tools_ctx())
	ok(has_err(res, "Satz 2:"), "Parser-Fehler mit Satzindex")

func run_sim(lines: Array, size := Vector3(100, 60, 40)) -> Dictionary:
	var res := MillNc.compile(lines, tools_ctx())
	if not res["errs"].is_empty():
		print("  Fehler: ", res["errs"])
	var sim := MillNc.simulate(res["ops"], tools_ctx()["tools"], size, 1.0)
	sim["errs"] = res["errs"]
	return sim

func test_pockets() -> void:
	# Kreistasche Ø30 mit Ø10, Mitte (50, 30), 8 tief
	var sim := run_sim(prog(["TOOL CALL 4 Z S2000", "L X+50 Y+30 R0 FMAX M13",
		"CYCL DEF 252 KREISTASCHE Q223=+30 Q201=-8 Q202=+4 Q206=+100 Q207=+300 Q200=+2 Q203=+0 Q204=+50 Q370=+1", "CYCL CALL"]))
	ok(sim["errs"].is_empty(), "Kreistasche ohne Fehler")
	var bad_in := 0
	var bad_out := 0
	for j in 60:
		for i in 100:
			var d := Vector2(i + 0.5 - 50.0, j + 0.5 - 30.0).length()
			var v: float = sim["h"][j * 100 + i]
			if d <= 14.0 and absf(v + 8.0) > 0.2:
				bad_in += 1
			elif d >= 16.0 and absf(v) > 0.001:
				bad_out += 1
	ok(bad_in == 0 and bad_out == 0, "Kreistasche: innen -8 (%d falsch), außen 0 (%d falsch)" % [bad_in, bad_out])
	# Größte Bahn-Überlappung: weder in der Rechteck- noch in der Kreistasche darf ein Rest stehen bleiben
	for cyc in ["251 RECHTECKTASCHE Q218=+60 Q219=+40", "252 KREISTASCHE Q223=+40"]:
		var res := MillNc.compile(prog(["TOOL CALL 4 Z S2000", "L X+50 Y+30 R0 FMAX M13",
			"CYCL DEF %s Q201=-4 Q202=+4 Q206=+100 Q207=+300 Q200=+2 Q203=+0 Q204=+50 Q370=+1.9" % cyc, "CYCL CALL"]), tools_ctx())
		# Feines Raster: Die Reste wären schmaler als 1 mm
		var wide := MillNc.simulate(res["ops"], tools_ctx()["tools"], Vector3(100, 60, 40), 0.25)
		var wn: int = wide["nx"]
		var rest := 0
		for j in int(wide["ny"]):
			for i in wn:
				var c := Vector2((i + 0.5) * 0.25 - 50.0, (j + 0.5) * 0.25 - 30.0)
				var inside := c.length() <= 19.0 if cyc.begins_with("252") else (absf(c.x) <= 29.0 and absf(c.y) <= 19.0 and (absf(c.x) <= 24.0 or absf(c.y) <= 14.0))
				if inside and absf(float(wide["h"][j * wn + i]) + 4.0) > 0.2:
					rest += 1
		ok(res["errs"].is_empty() and rest == 0, "Zyklus %s mit Q370 = 1,9 räumt ganz aus (%d Zellen Rest)" % [cyc.get_slice(" ", 0), rest])
	# Kreistasche exakt Werkzeugdurchmesser: nur eintauchen
	sim = run_sim(prog(["TOOL CALL 4 Z S2000", "L X+50 Y+30 R0 FMAX M13",
		"CYCL DEF 252 KREISTASCHE Q223=+10 Q201=-3 Q202=+3 Q206=+100 Q207=+300", "CYCL CALL"]))
	ok(sim["errs"].is_empty() and near(at(sim, 50.0, 30.0), -3.0, 0.2) and near(at(sim, 50.0, 37.0), 0.0, 0.001), "Kreistasche = Werkzeugdurchmesser")
	# Nut längs X, breiter als das Werkzeug (Ø14 mit Ø10), Länge 60 über alles
	sim = run_sim(prog(["TOOL CALL 4 Z S2000", "L X+50 Y+30 R0 FMAX M13",
		"CYCL DEF 253 NUTENFRAESEN Q218=+60 Q219=+14 Q374=+0 Q367=+0 Q201=-5 Q202=+3 Q206=+100 Q207=+300", "CYCL CALL"]))
	ok(sim["errs"].is_empty(), "Nut Ø14 ohne Fehler: " + str(sim["errs"]))
	var ok_in := true
	var ok_out := true
	for j in 60:
		for i in 100:
			var x := i + 0.5
			var y := j + 0.5
			var v: float = sim["h"][j * 100 + i]
			var u := absf(x - 50.0)
			var w := absf(y - 30.0)
			if u <= 22.0 and w <= 6.0:
				ok_in = ok_in and absf(v + 5.0) < 0.2
			if u > 31.0 or w > 8.0:
				ok_out = ok_out and absf(v) < 0.001
	ok(ok_in, "Nut breiter als Werkzeug: Boden -5 in der Nut")
	ok(ok_out, "Nut breiter als Werkzeug: außen unberührt")
	ok(at(sim, 21.5, 30.5) < -4.8 and at(sim, 78.5, 30.5) < -4.8, "Nut: Enden reichen bis Länge 60")
	# Nut längs Y, Breite = Werkzeug (Pendelbahn)
	sim = run_sim(prog(["TOOL CALL 4 Z S2000", "L X+50 Y+30 R0 FMAX M13",
		"CYCL DEF 253 NUTENFRAESEN Q218=+40 Q219=+10 Q374=+90 Q201=-5 Q202=+2.5 Q206=+100 Q207=+300", "CYCL CALL"]))
	ok(sim["errs"].is_empty(), "Nut längs Y ohne Fehler: " + str(sim["errs"]))
	ok(near(at(sim, 50.0, 30.0), -5.0, 0.2) and near(at(sim, 50.0, 12.0), -5.0, 0.2) and near(at(sim, 50.0, 48.0), -5.0, 0.2), "Nut längs Y: Boden -5")
	ok(near(at(sim, 50.0, 8.0), 0.0, 0.001) and near(at(sim, 50.0, 52.0), 0.0, 0.001) and near(at(sim, 56.0, 30.0), 0.0, 0.001) and near(at(sim, 43.0, 30.0), 0.0, 0.001), "Nut längs Y: Rand unberührt")
	# Rechtecktasche, Position = Ecke links unten
	sim = run_sim(prog(["TOOL CALL 4 Z S2000", "L X+20 Y+10 R0 FMAX M13",
		"CYCL DEF 251 RECHTECKTASCHE Q218=+40 Q219=+20 Q367=+1 Q201=-4 Q202=+2 Q206=+100 Q207=+300", "CYCL CALL"]))
	ok(sim["errs"].is_empty() and near(at(sim, 40.0, 20.0), -4.0, 0.2) and near(at(sim, 22.5, 12.5), -4.0, 0.25) and near(at(sim, 19.0, 20.0), 0.0, 0.001) and near(at(sim, 61.0, 20.0), 0.0, 0.001), "Tasche ab linker unterer Ecke")
	# Planfräsen mit Schaftfräser Ø12 über 40 x 30: mehrere Bahnen, zwei Zustellungen
	sim = run_sim(prog(["TOOL CALL 2 Z S1500", "M3",
		"CYCL DEF 233 PLANFRAESEN Q225=+0 Q226=+10 Q227=+0 Q386=-4 Q218=+100 Q219=+30 Q202=+2 Q370=+1 Q207=+300 Q253=+0 Q357=+2", "CYCL CALL"]))
	var f_in := true
	var f_out := true
	for j in 60:
		for i in 100:
			var x := i + 0.5
			var y := j + 0.5
			var v: float = sim["h"][j * 100 + i]
			if y >= 10.0 and y <= 40.0:
				f_in = f_in and absf(v + 4.0) < 0.2
			elif y < 9.0 or y > 41.0:
				f_out = f_out and absf(v) < 0.001
	ok(sim["errs"].is_empty(), "Planen Ø12 ohne Fehler: " + str(sim["errs"]))
	ok(f_in and f_out, "Planen Ø12 über volle Länge: Fläche auf -4, außen unberührt (in %s, aus %s)" % [str(f_in), str(f_out)])
