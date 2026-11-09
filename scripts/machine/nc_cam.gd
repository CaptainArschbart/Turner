class_name NcCam
extends RefCounted
## Programme der Zyklensteuerung (an SINUMERIK ShopTurn angelehnt) und deren Bahnberechnung.
##
## Ein Programm ist ein Dictionary {"name", "blocks"}; Sätze:
##   head    - Programmkopf: Sicherheitsabstand SC, Werkzeugwechselpunkt XT (Ø) / ZT, S max, KSS
##   contour - Kontur: Startpunkt X0 (Ø) / Z0 und Geraden-Elemente {x (Ø), z, tr, tv}
##             tr = Übergang zum nächsten Element: 0 keiner, 1 Fase (tv = Schenkellänge), 2 Radius
##   cut     - Abspanen Rechteck: Bereich Z0..Z1 auf Ø X1 (Rohteil = Ist-Material)
##   stock   - Konturabspanen: Material außerhalb der Kontur bis zum Werkstückende
## Abspansätze: mode 0 Schruppen / 1 Schlichten, dir 0 längs / 1 plan, Werkzeug t, F (mm/U),
## V (m/min, konstante Schnittgeschwindigkeit), D Zustellung, UX Aufmaß X (Ø), UZ Aufmaß Z,
## hs Hinterschnitte bearbeiten (1 ja / 0 nein, nur Konturabspanen Schruppen).
## Eine Kontur begrenzt ihren Bearbeitungsbereich in Z: links davon bleibt alles stehen, rechts
## davon auch - außer die Kontur beginnt an der Drehmitte oder bei Z0 (dann wird bis zum
## Werkstückende abgespant). So lassen sich mehrere Konturen nacheinander bearbeiten, z. B. ein
## Freistich als eigene Kontur mitten im Teil.
##
## Bahnen gelten für die Schneide (WKS wie die Positionsanzeige: Z ab Backen-Stirnfläche, X im
## Radius). Damit nichts ins Fertigteil schneidet, rechnet die Bahn mit der echten Plattenform:
## safe_x(z) ist die tiefste Lage der Schneide bei z, bei der die Platte die Sollkontur nicht
## verletzt (vollständige Schneidenradiuskorrektur). Ein Zug ist ein Array [z, x, eilgang].

const SEG := 0.25               # wie Lathe.SEG
const RPM_MIN := 40.0           # wie Lathe.RPM_MIN
const RAPID := 100.0            # Eilgang mm/s
const CENTER_OVER := -0.4       # über die Drehmitte hinaus plandrehen (Restzapfen)
const MODES := ["Schruppen", "Schlichten", "Komplett"]   # Komplett = Schruppen + Schlichten, ein Werkzeug
const DIRS := ["längs", "plan"]
const TRANS := ["-", "Fase", "Radius"]
const UC_FORMS := ["Gewinde DIN 76", "Form E DIN 509"]
## Gewindefreistich DIN 76-1 (Regelfall, außen): [Steigung P, d - dg, g1 (Breite am Grund), r]
const DIN76 := [
	[0.5, 0.8, 1.1, 0.2], [0.7, 1.1, 1.5, 0.4], [0.75, 1.2, 1.6, 0.4], [0.8, 1.3, 1.7, 0.4],
	[1.0, 1.6, 2.1, 0.6], [1.25, 2.0, 2.7, 0.6], [1.5, 2.3, 3.2, 0.8], [1.75, 2.6, 3.9, 1.0],
	[2.0, 3.0, 4.5, 1.0], [2.5, 3.6, 5.6, 1.2], [3.0, 4.4, 6.7, 1.6], [3.5, 5.0, 7.7, 1.6],
	[4.0, 5.7, 9.0, 2.0],
]
const FORM_E_NAMES := ["E0,6x0,2", "E0,6x0,3", "E1x0,2", "E1x0,4", "E1,6x0,3", "E2,5x0,4", "E4x0,5"]
## Freistich Form E DIN 509: [Bezeichnung, r, t1 (Tiefe), f (Breite)]; Flanke zum Zylinder 15°
const FORM_E := [
	["E0,6x0,2", 0.6, 0.2, 2.0], ["E0,6x0,3", 0.6, 0.3, 2.5], ["E1x0,2", 1.0, 0.2, 2.5],
	["E1x0,4", 1.0, 0.4, 4.0], ["E1,6x0,3", 1.6, 0.3, 4.0], ["E2,5x0,4", 2.5, 0.4, 5.0],
	["E4x0,5", 4.0, 0.5, 7.0],
]


# ======================================================================= Programme

static func new_program(pname: String) -> Dictionary:
	return {"name": pname, "wks": true, "blocks": [new_block("head")]}


## Programme vor dem Werkstücknullpunkt hatten Z ab Backen-Stirnfläche: auf WKS umrechnen
## (Nullpunkt bei zero_z, also z - zero_z). Gibt true zurück, wenn umgerechnet wurde.
static func migrate_to_wks(prog: Dictionary, zero_z: float) -> bool:
	if bool(prog.get("wks", false)):
		return false
	for b in prog.get("blocks", []):
		match str(b["type"]):
			"head":
				b["zt"] = float(b["zt"]) - zero_z
			"cut":
				b["z0"] = float(b["z0"]) - zero_z
				b["z1"] = float(b["z1"]) - zero_z
			"undercut":
				b["z0"] = float(b["z0"]) - zero_z
			"contour":
				b["z0"] = float(b["z0"]) - zero_z
				for e in b["els"]:
					e["z"] = float(e["z"]) - zero_z
	prog["wks"] = true
	return true


static func new_block(type: String, prog := {}) -> Dictionary:
	match type:
		"head":
			return {"type": "head", "sc": 1.0, "xt": 160.0, "zt": 70.0, "smax": 2500.0, "kss": 1}
		"cut":
			return {"type": "cut", "mode": 0, "dir": 0, "t": "T1", "f": 0.25, "v": 180.0,
				"z0": 0.0, "x1": 50.0, "z1": -60.0, "d": 2.0, "ux": 0.4, "uz": 0.2}
		"contour":
			var n := 1
			while not find_contour(prog, "KONTUR%d" % n).is_empty():
				n += 1
			return {"type": "contour", "name": "KONTUR%d" % n, "x0": 0.0, "z0": 0.0, "els": [
				{"x": 40.0, "z": 0.0, "tr": 0, "tv": 0.0},
				{"x": 40.0, "z": -50.0, "tr": 0, "tv": 0.0},
				{"x": 64.0, "z": -50.0, "tr": 0, "tv": 0.0},
			]}
		"stock":
			var cname := ""
			for b in prog.get("blocks", []):
				if str(b["type"]) == "contour":
					cname = str(b["name"])
			return {"type": "stock", "contour": cname, "mode": 0, "dir": 0, "t": "T1", "f": 0.25,
				"v": 180.0, "d": 2.0, "ux": 0.4, "uz": 0.2, "hs": 1}
		"undercut":
			# Bezugspunkt X0/Z0: Ecke Gewinde- bzw. Zylinderdurchmesser an der Schulter
			return {"type": "undercut", "form": 0, "mode": 2, "t": "T3", "f": 0.1, "v": 200.0,
				"x0": 20.0, "z0": -30.0, "p": 1.5, "a": 30.0, "size": 3, "d": 1.0, "ux": 0.2, "uz": 0.1}
	return {}


static func head(prog: Dictionary) -> Dictionary:
	for b in prog.get("blocks", []):
		if str(b["type"]) == "head":
			return b
	return new_block("head")


static func find_contour(prog: Dictionary, cname: String) -> Dictionary:
	for b in prog.get("blocks", []):
		if str(b["type"]) == "contour" and str(b["name"]) == cname:
			return b
	return {}


static func is_machining(b: Dictionary) -> bool:
	return str(b.get("type", "")) in ["cut", "stock", "undercut"]


static func fmt(v: float, dec := 3) -> String:
	var s := String.num(v, dec)
	return s


## Kurzbeschreibung eines Satzes für den Arbeitsplan.
static func summary(b: Dictionary) -> String:
	match str(b["type"]):
		"head":
			return "Programmkopf     SC %s   WP X%s Z%s   S max %d   KSS %s" % [fmt(b["sc"]), fmt(b["xt"]), fmt(b["zt"]),
				int(b["smax"]), "ein" if int(b["kss"]) else "aus"]
		"contour":
			return "Kontur %s     Start X%s Z%s, %d Elemente" % [b["name"], fmt(b["x0"]), fmt(b["z0"]), b["els"].size()]
		"cut":
			return "Abspanen %s %s   %s F%s V%d   Z%s..%s auf Ø%s" % [MODES[int(b["mode"])], DIRS[int(b["dir"])],
				b["t"], fmt(b["f"]), int(b["v"]), fmt(b["z0"]), fmt(b["z1"]), fmt(b["x1"])]
		"stock":
			return "Kontur abspanen %s %s   %s   %s F%s V%d%s" % [MODES[int(b["mode"])], DIRS[int(b["dir"])],
				b["contour"], b["t"], fmt(b["f"]), int(b["v"]), ("  D%s%s" % [fmt(b["d"]),
				"" if int(b.get("hs", 1)) == 1 else "  ohne Hinterschn."]) if int(b["mode"]) != 1 else ""]
		"undercut":
			var g := ("P%s" % fmt(b["p"])) if int(b["form"]) == 0 else str(FORM_E[clampi(int(b["size"]), 0, FORM_E.size() - 1)][0])
			return "Freistich %s %s   %s   X%s Z%s   %s F%s V%d" % [UC_FORMS[int(b["form"])], g, MODES[int(b["mode"])],
				fmt(b["x0"]), fmt(b["z0"]), b["t"], fmt(b["f"]), int(b["v"])]
	return "?"


## Gewindefreistich-Maße DIN 76 für Steigung p (Tabelle, Zwischenwerte linear): [d - dg, g1, r].
static func din76(p: float) -> Array:
	var lo: Array = DIN76[0]
	if p <= float(lo[0]):
		return [lo[1], lo[2], lo[3]]
	for i in range(1, DIN76.size()):
		var hi: Array = DIN76[i]
		if p <= float(hi[0]):
			var u := (p - float(lo[0])) / (float(hi[0]) - float(lo[0]))
			return [lerpf(lo[1], hi[1], u), lerpf(lo[2], hi[2], u), lerpf(lo[3], hi[3], u)]
		lo = hi
	var k := p / float(lo[0])
	return [float(lo[1]) * k, float(lo[2]) * k, float(lo[3]) * k]


## Kontur eines Freistichzyklus (wie im Hilfebild): rechts auf dem Gewinde-/Zylinder-Ø X0
## beginnend die Flanke hinab (DIN 76: Winkel a, meist 30°; Form E: 15°), Grund mit Radius r an
## der Schulter, an der Schulter (Z0) wieder auf X0. Liegt mitten im Teil: Gewinde und Schulter
## bleiben stehen.
static func undercut_contour(b: Dictionary) -> Dictionary:
	var d := float(b["x0"])
	var z0 := float(b["z0"])
	var h: float
	var g1: float
	var r: float
	var ang: float
	if int(b["form"]) == 0:
		var m := din76(maxf(float(b["p"]), 0.2))
		h = float(m[0]) * 0.5
		g1 = float(m[1])
		r = float(m[2])
		ang = clampf(float(b.get("a", 30.0)), 10.0, 90.0)
	else:
		var e: Array = FORM_E[clampi(int(b["size"]), 0, FORM_E.size() - 1)]
		r = float(e[1])
		h = float(e[2])
		ang = 15.0
		g1 = maxf(float(e[3]) - h / tan(deg_to_rad(ang)), r)
	var run := h / tan(deg_to_rad(ang))
	return {"type": "contour", "name": "FREISTICH", "x0": d, "z0": z0 + g1 + run, "els": [
		{"x": d - 2.0 * h, "z": z0 + g1, "tr": 0, "tv": 0.0},
		{"x": d - 2.0 * h, "z": z0, "tr": 2, "tv": r},
		{"x": d, "z": z0, "tr": 0, "tv": 0.0},
	]}


## Beispielprogramme (stehen im Programm-Manager, wenn noch keine Programme da sind).
static func examples() -> Array:
	var welle := new_program("WELLE_AUFTRAG2")
	welle["blocks"].append({"type": "contour", "name": "WELLE", "x0": 0.0, "z0": -10.0, "els": [
		{"x": 50.0, "z": -10.0, "tr": 1, "tv": 1.0},
		{"x": 50.0, "z": -70.0, "tr": 0, "tv": 0.0},
		{"x": 58.0, "z": -70.0, "tr": 0, "tv": 0.0},
		{"x": 58.0, "z": -155.0, "tr": 0, "tv": 0.0},
		{"x": 64.0, "z": -155.0, "tr": 0, "tv": 0.0},
	]})
	welle["blocks"].append({"type": "stock", "contour": "WELLE", "mode": 0, "dir": 0, "t": "T1", "f": 0.3,
		"v": 180.0, "d": 2.5, "ux": 0.4, "uz": 0.2})
	welle["blocks"].append({"type": "stock", "contour": "WELLE", "mode": 1, "dir": 0, "t": "T3", "f": 0.1,
		"v": 220.0, "d": 1.0, "ux": 0.0, "uz": 0.0})
	var plan := new_program("PLANEN_2MM")
	plan["blocks"].append({"type": "cut", "mode": 0, "dir": 1, "t": "T1", "f": 0.2, "v": 180.0,
		"z0": 0.0, "x1": 0.0, "z1": -2.0, "d": 1.0, "ux": 0.0, "uz": 0.0})
	var flansch := new_program("BUND_PLAN")
	flansch["blocks"].append({"type": "contour", "name": "BUND", "x0": 0.0, "z0": -4.0, "els": [
		{"x": 30.0, "z": -4.0, "tr": 0, "tv": 0.0},
		{"x": 30.0, "z": -20.0, "tr": 2, "tv": 2.0},
		{"x": 52.0, "z": -20.0, "tr": 1, "tv": 1.0},
		{"x": 52.0, "z": -40.0, "tr": 0, "tv": 0.0},
		{"x": 64.0, "z": -40.0, "tr": 0, "tv": 0.0},
	]})
	flansch["blocks"].append({"type": "stock", "contour": "BUND", "mode": 0, "dir": 1, "t": "T1", "f": 0.25,
		"v": 180.0, "d": 2.0, "ux": 0.4, "uz": 0.2})
	flansch["blocks"].append({"type": "stock", "contour": "BUND", "mode": 1, "dir": 1, "t": "T3", "f": 0.1,
		"v": 220.0, "d": 1.0, "ux": 0.0, "uz": 0.0})
	return [welle, plan, flansch]


# ======================================================================= Kontur

## Kontur als Polylinie Vector2(z, r) mit eingerechneten Fasen und Rundungen.
static func contour_points(c: Dictionary, zoff := 0.0) -> PackedVector2Array:
	var pts: Array[Vector2] = [Vector2(float(c["z0"]) + zoff, float(c["x0"]) * 0.5)]
	var trs: Array = [[0, 0.0]]
	for e in c.get("els", []):
		var p := Vector2(float(e["z"]) + zoff, float(e["x"]) * 0.5)
		if p.distance_to(pts[pts.size() - 1]) < 0.0005:
			continue
		pts.append(p)
		trs.append([int(e.get("tr", 0)), float(e.get("tv", 0.0))])
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var p := pts[i]
		var tr: int = trs[i][0]
		var tv: float = trs[i][1]
		if i == pts.size() - 1 or tr == 0 or tv <= 0.0:
			out.append(p)
			continue
		var u := pts[i - 1] - p
		var v := pts[i + 1] - p
		var lu := u.length()
		var lv := v.length()
		u /= lu
		v /= lv
		var theta := acos(clampf(u.dot(v), -1.0, 1.0))
		if theta < 0.02 or theta > PI - 0.02:
			out.append(p)
			continue
		if tr == 1:
			var s := minf(tv, minf(lu, lv) * 0.5)
			out.append(p + u * s)
			out.append(p + v * s)
			continue
		var t := minf(tv / tan(theta * 0.5), minf(lu, lv) * 0.5)
		var r := t * tan(theta * 0.5)
		var center := p + (u + v).normalized() * (r / sin(theta * 0.5))
		var pa := p + u * t
		var pb := p + v * t
		var a0 := (pa - center).angle()
		var da := wrapf((pb - center).angle() - a0, -PI, PI)
		var n := maxi(4, int(ceil(absf(da) * r / 0.25)))
		for s in n + 1:
			out.append(center + Vector2.from_angle(a0 + da * float(s) / n) * r)
	return out


## Größter Radius der Polylinie im z-Intervall [a, b], -1 wenn sie dort nicht liegt.
static func poly_max(poly: PackedVector2Array, a: float, b: float) -> float:
	var m := -1.0
	for k in poly.size() - 1:
		var p := poly[k]
		var q := poly[k + 1]
		var lo := minf(p.x, q.x)
		var hi := maxf(p.x, q.x)
		if hi < a or lo > b:
			continue
		if hi - lo < 1e-9:
			m = maxf(m, maxf(p.y, q.y))
			continue
		var za := maxf(a, lo)
		var zb := minf(b, hi)
		m = maxf(m, maxf(lerpf(p.y, q.y, (za - p.x) / (q.x - p.x)), lerpf(p.y, q.y, (zb - p.x) / (q.x - p.x))))
	return m


# ======================================================================= Sollprofil

## Sollradius je Segment für einen Abspansatz. prof = Ist-Material (Radius je Segment).
## Segmente außerhalb des Bearbeitungsbereichs behalten ihr Material (geschützt).
## zoff = Lage des Werkstücknullpunkts (Programm-Z 0) über der Backen-Stirnfläche (mm).
static func target(b: Dictionary, prog: Dictionary, prof: PackedFloat32Array, zoff := 0.0) -> Dictionary:
	var n := prof.size()
	var tg := PackedFloat32Array()
	tg.resize(n)
	if str(b["type"]) == "cut":
		var za := minf(float(b["z0"]), float(b["z1"])) + zoff
		var zb := maxf(float(b["z0"]), float(b["z1"])) + zoff
		var r1 := maxf(float(b["x1"]) * 0.5, 0.0)
		if zb - za < SEG:
			return {"err": "Abspanen: Bereich Z0 bis Z1 zu kurz."}
		for i in n:
			var zc := (i + 0.5) * SEG
			tg[i] = minf(prof[i], r1) if zc > za and zc < zb else prof[i]
		return {"tg": tg, "zlo": za, "zhi": zb}
	var c := undercut_contour(b) if str(b["type"]) == "undercut" else find_contour(prog, str(b.get("contour", "")))
	if c.is_empty():
		return {"err": "Kontur \"%s\" nicht im Programm." % b.get("contour", "")}
	var poly := contour_points(c, zoff)
	if poly.size() < 2:
		return {"err": "Kontur %s hat keine Elemente." % c["name"]}
	var zlo := INF
	var zhi := -INF
	for p in poly:
		zlo = minf(zlo, p.x)
		zhi = maxf(zhi, p.x)
		if p.y < -0.001:
			return {"err": "Kontur %s: negativer Durchmesser." % c["name"]}
	if zhi - zlo < SEG:
		return {"err": "Kontur %s: keine Länge in Z." % c["name"]}
	# Rechts der Kontur (zum Werkstückende) nur abspanen, wenn die Kontur dort an der Drehmitte
	# beginnt oder bis zum Werkstücknullpunkt reicht. Eine Kontur mitten am Teil (z. B. ein
	# zweiter Absatz bei Z-80) darf das Material rechts davon - andere Konturen - nicht wegnehmen.
	var r_end := INF
	for p in poly:
		if p.x >= zhi - 0.001:
			r_end = minf(r_end, p.y)
	var clear_right := r_end <= 0.001 or zhi - zoff >= -0.001
	# tc = Kontur wie programmiert (Schlichtbahn): über bereits tieferem Material (z. B. einem
	# vorher gestochenen Freistich) fährt das Schlichten auf der Kontur hinweg statt hinein.
	var tc := PackedFloat32Array()
	tc.resize(n)
	var x_all := _max_prof(prof)
	for i in n:
		var a := i * SEG + 0.0001
		var e := (i + 1) * SEG - 0.0001
		if (i + 0.5) * SEG < zlo:
			tg[i] = prof[i]
			tc[i] = prof[i]
		elif a > zhi:
			tg[i] = 0.0 if clear_right else prof[i]
			tc[i] = tg[i]
		else:
			var r := poly_max(poly, a, e)
			r = r if r >= 0.0 else 0.0
			tg[i] = minf(prof[i], r)
			tc[i] = minf(r, x_all)
	return {"tg": tg, "tc": tc, "zlo": zlo, "zhi": zhi, "poly": contour_points(c)}   # poly in Programm-Z


## Aufmaß: Sollkontur um UZ axial und UX/2 radial aufdicken.
static func dilate(tg: PackedFloat32Array, ux_r: float, uz: float) -> PackedFloat32Array:
	var k := int(ceil(uz / SEG - 0.001))
	var out := PackedFloat32Array()
	out.resize(tg.size())
	for i in tg.size():
		var m := 0.0
		for j in range(maxi(i - k, 0), mini(i + k, tg.size() - 1) + 1):
			m = maxf(m, tg[j])
		out[i] = m + ux_r
	return out


## Tiefste Lage der Schneide (X, Radius) bei z, ohne dass die Platte das Soll tg verletzt.
## Vor der Backen-Stirnfläche (z < 0) liegt das Futter.
static func safe_x(t: Dictionary, tg: PackedFloat32Array, z: float) -> float:
	var a := int(floor((z + float(t["zmin"])) / SEG + 0.0004))   # Rundung: Schneide genau auf der Segmentgrenze
	var b := int(floor((z + float(t["zmax"])) / SEG))
	var m := -INF
	for i in range(a, b + 1):
		var e := LatheTools.env_min(t, i * SEG - z, (i + 1) * SEG - z)
		if e == INF:
			continue
		var r := 1.0e6 if i < 0 else (tg[i] if i < tg.size() else 0.0)
		m = maxf(m, r - e)
	return m


# ======================================================================= Bahnen

## Bahn für einen Abspansatz. ctx: prof (Ist-Material), pos (Schneide z, x), zlim (kleinstes Z
## der Maschine für dieses Werkzeug), zoff (Werkstücknullpunkt über der Backen-Stirnfläche).
## Bahnen und Material in Maschinen-Z (ab Backen-Stirnfläche), Konturen (poly) in Programm-Z. Ergebnis: {"moves", "after" (Material danach), "err", "info"}.
static func plan(b: Dictionary, prog: Dictionary, t: Dictionary, ctx: Dictionary) -> Dictionary:
	var err := check_block(b, t)
	if err != "":
		return {"err": err}
	if int(b["mode"]) == 2:
		return _plan_complete(b, prog, t, ctx)
	var prof: PackedFloat32Array = ctx["prof"]
	var tr := target(b, prog, prof, float(ctx.get("zoff", 0.0)))
	if tr.has("err"):
		return {"err": tr["err"]}
	var tg: PackedFloat32Array = tr["tg"]
	var hd := head(prog)
	var p := {
		"sc": maxf(float(hd["sc"]), 0.2), "d": float(b["d"]), "zlim": float(ctx.get("zlim", 1.0)),
		"t": t, "pos": ctx["pos"], "hs": int(b.get("hs", 1)) == 1,
		"zr": Vector2(float(tr["zlo"]), float(tr["zhi"])), "tg": tg,
	}
	var finish := int(b["mode"]) == 1
	var face := int(b.get("dir", 0)) == 1
	var goal := tg if finish else dilate(tg, maxf(float(b["ux"]), 0.0) * 0.5, maxf(float(b["uz"]), 0.0))
	var res: Dictionary
	if finish:
		res = _finish(prof, goal, tr.get("tc", tg), p, face)
	elif face:
		res = _rough_face(prof, goal, p)
	else:
		res = _rough_long(prof, goal, p)
	if res.has("err"):
		return res
	# Material danach: beim Längsschruppen das mitgeführte Ist-Material (auch Reste, an die das
	# Werkzeug nicht herankommt - wie die Restmaterial-Erkennung der Steuerung), sonst das Ziel.
	var after := prof.duplicate()
	var cur: PackedFloat32Array = res.get("cur", goal)
	res.erase("cur")
	for i in after.size():
		after[i] = minf(after[i], maxf(cur[i], goal[i]))
	res["after"] = after
	res["tg"] = tg
	if tr.has("poly"):
		res["poly"] = tr["poly"]
	return res


## Komplettbearbeitung (∇ + ∇∇∇): erst schruppen mit Aufmaß, dann mit demselben Werkzeug auf dem
## so entstandenen Material schlichten. fin_from = erster Zug des Schlichtens.
static func _plan_complete(b: Dictionary, prog: Dictionary, t: Dictionary, ctx: Dictionary) -> Dictionary:
	var br := b.duplicate()
	br["mode"] = 0
	var r1 := plan(br, prog, t, ctx)
	if r1.has("err"):
		return r1
	var mv1: Array = r1["moves"]
	var c2 := ctx.duplicate()
	c2["prof"] = r1["after"]
	if not mv1.is_empty():
		var e: Array = mv1[mv1.size() - 1]
		c2["pos"] = Vector2(e[0], e[1])
	var bf := b.duplicate()
	bf["mode"] = 1
	var r2 := plan(bf, prog, t, c2)
	if r2.has("err"):
		return r2
	var res := r2.duplicate()
	res["moves"] = mv1 + r2["moves"]
	res["finish"] = false
	res["fin_from"] = mv1.size()
	return res


## Plausibilität eines Abspansatzes für Werkzeug t ("" = in Ordnung).
static func check_block(b: Dictionary, t: Dictionary) -> String:
	if int(t.get("feed_dir", -1)) > 0:
		return "%s ist ein Linksmeißel - die Zyklen arbeiten zum Futter bzw. zur Mitte hin (z. B. T1, T3)." % t["id"]
	if float(b["f"]) < 0.01 or float(b["f"]) > 0.5:
		return "Vorschub F muss zwischen 0.01 und 0.5 mm/U liegen."
	if float(b["v"]) < 20.0 or float(b["v"]) > 400.0:
		return "Schnittgeschwindigkeit V muss zwischen 20 und 400 m/min liegen."
	if str(b["type"]) == "undercut":
		if float(b["x0"]) <= 2.0:
			return "Freistich: Durchmesser X0 zu klein."
		if int(b["form"]) == 0 and (float(b["p"]) < 0.2 or float(b["p"]) > 6.0):
			return "Freistich DIN 76: Steigung P zwischen 0.2 und 6 mm."
	if int(b["mode"]) != 1:
		var d := float(b["d"])
		if d <= 0.05:
			return "Zustellung D zu klein."
		if d > float(t["max_dz"]) + 0.001:
			return "Zustellung D %s zu groß für %s %s (max. %s mm)." % [fmt(d), t["id"], t["short"], fmt(t["max_dz"])]
		if float(b["ux"]) < 0.0 or float(b["uz"]) < 0.0:
			return "Aufmaß darf nicht negativ sein."
	return ""


## Segmentbereich, in dem noch Material über dem Ziel liegt (x = erstes, y = letztes; -1 = keins).
static func _need(prof: PackedFloat32Array, goal: PackedFloat32Array, tol := 0.01) -> Vector2i:
	var lo := -1
	var hi := -1
	for i in prof.size():
		if prof[i] > goal[i] + tol:
			if lo < 0:
				lo = i
			hi = i
	return Vector2i(lo, hi)


static func _max_prof(prof: PackedFloat32Array) -> float:
	var m := 0.0
	for r in prof:
		m = maxf(m, r)
	return m


## Anfahren aus der aktuellen Lage: erst auf Freifahrhöhe, dann in Z, dann in X zustellen.
static func _approach(mv: Array, pos: Vector2, z: float, x: float, x_clear: float) -> void:
	var xc := maxf(pos.y, x_clear)
	if xc > pos.y + 0.001:
		mv.append([pos.x, xc, true])
	mv.append([z, xc, true])
	mv.append([z, x, true])


## Eilgang zum nächsten Schnittbeginn: hoch nur in X, sonst erst Z (über dem Material), dann X.
static func _rapid_to(mv: Array, z: float, x: float) -> void:
	var last: Array = mv[mv.size() - 1]
	if x > float(last[1]):
		mv.append([last[0], x, true])
		mv.append([z, x, true])
	else:
		mv.append([z, last[1], true])
		mv.append([z, x, true])


## Arbeitsstand einer Bahnberechnung: Hüllkurve der Platte je Segmentversatz und das mitgeführte
## Ist-Material. Damit weiß der Zyklus nach jedem Schnitt, wo noch Material steht - Eilgänge gehen
## nur dort, wo nichts im Weg ist, und Zustellungen enden mit Sicherheitsabstand vor dem Material.
## Werkzeuglagen auf dem Segmentraster k (Schneide bei z = k * SEG).
class Pass:
	extends RefCounted
	var t: Dictionary
	var j0 := 0                       # Segmentversatz der Plattenkante links
	var env := PackedFloat32Array()   # tiefste Hüllkurve je Segmentversatz j0 + j (INF = keine Platte)
	var env_lo := INF
	var cur := PackedFloat32Array()   # Ist-Material (Radius je Segment)
	var sc := 1.0
	var mv: Array = []

	func _init(tool: Dictionary, prof: PackedFloat32Array, safety: float, pos: Vector2) -> void:
		t = tool
		sc = safety
		cur = prof.duplicate()
		j0 = int(floor(float(t["zmin"]) / SEG + 0.0004))
		var j1 := int(floor(float(t["zmax"]) / SEG))
		for j in range(j0, j1 + 1):
			var e := LatheTools.env_min(t, j * SEG, (j + 1) * SEG)
			env.append(e)
			env_lo = minf(env_lo, e)
		mv.append([pos.x, pos.y, true])   # Startlage, wird am Ende entfernt

	## Tiefste Schneidenlage bei k, ohne dass die Platte das Profil g verletzt (wie safe_x).
	func safe(g: PackedFloat32Array, k: int) -> float:
		var m := -INF
		for j in env.size():
			var e := env[j]
			if e == INF:
				continue
			var i := k + j0 + j
			var r := 1.0e6 if i < 0 else (g[i] if i < g.size() else 0.0)
			m = maxf(m, r - e)
		return m

	## Tiefste Schneidenlage bei k, bei der die Platte kein Material berührt.
	func clear_at(k: int) -> float:
		var m := 0.0
		for j in env.size():
			var e := env[j]
			var i := k + j0 + j
			if e == INF or i < 0 or i >= cur.size():
				continue
			m = maxf(m, cur[i] - e)
		return m

	## Freifahrhöhe über dem Material zwischen za und zb.
	func clear_span(za: float, zb: float) -> float:
		var m := 0.0
		for k in range(int(floor(minf(za, zb) / SEG + 0.0001)), int(ceil(maxf(za, zb) / SEG - 0.0001)) + 1):
			m = maxf(m, clear_at(k))
		return m

	## Material abtragen für Schneidenlagen k = ka..kb auf Höhe x (wie Lathe._cut).
	func sweep(ka: int, kb: int, x: float) -> void:
		var n := env.size()
		for i in range(maxi(ka + j0, 0), mini(kb + j0 + n - 1, cur.size() - 1) + 1):
			var jlo := maxi(0, i - kb - j0)
			var jhi := mini(n - 1, i - ka - j0)
			var e := env_lo
			if jlo > 0 or jhi < n - 1:
				e = INF
				for j in range(jlo, jhi + 1):
					e = minf(e, env[j])
			if e == INF:
				continue
			var lim := maxf(x + e, 0.0)
			if lim < 0.3:
				lim = 0.0
			if lim < cur[i]:
				cur[i] = lim

	func last() -> Vector2:
		var m: Array = mv[mv.size() - 1]
		return Vector2(m[0], m[1])

	## Vorschubzug; das überfahrene Material wird abgetragen (an den Rasterlagen der Bahn).
	func feed(z: float, x: float, cuts := true) -> void:
		var p := last()
		mv.append([z, x, false])
		if not cuts:
			return
		var za := minf(p.x, z)
		var zb := maxf(p.x, z)
		var ka := int(ceil(za / SEG - 0.0001))
		var kb := int(floor(zb / SEG + 0.0001))
		if absf(x - p.y) < 0.000001:
			if ka <= kb:
				sweep(ka, kb, x)
			return
		for k in range(ka, kb + 1):
			var xi := minf(p.y, x) if zb - za < 0.000001 else lerpf(p.y, x, (k * SEG - p.x) / (z - p.x))
			sweep(k, k, xi)

	## Eilgang nach (z, x): auf Freifahrhöhe über dem Material, in Z, dann zustellen - bis auf den
	## Sicherheitsabstand vor dem Material im Eilgang, den Rest im Vorschub.
	func travel(z: float, x: float) -> void:
		var p := last()
		var h := maxf(p.y, clear_span(p.x, z) + sc)
		if x > h:
			h = x
		if h > p.y + 0.0005:
			mv.append([p.x, h, true])
		mv.append([z, h, true])
		if x >= h - 0.0005:
			return
		var c := clear_span(z, z)
		if c <= 0.001 or x >= c + sc * 0.5:
			mv.append([z, x, true])
		else:
			if c + sc < h - 0.0005:
				mv.append([z, c + sc, true])
			feed(z, x)

	func moves() -> Array:
		return mv.slice(1)


const EPS := 0.0001


## Längsschruppen (wie CYCLE952 "Abspanen längs außen"): Lagen im Abstand D von außen nach innen.
## Je Lage werden alle Bereiche bearbeitet, in denen die Schneide auf dieser Höhe Platz hat - auch
## Hinterschnitte (Einstiche, Freistiche zwischen zwei Absätzen), wenn hs gesetzt ist. Dort taucht
## das Werkzeug konturparallel an der rechten Flanke ein. Am Schnittende wird die Kontur bis zur
## vorigen Lage nachgezogen, dann 45° abgehoben. Erst der freie Hauptbereich, dann jeder
## Hinterschnitt für sich (keine Leerwege zwischen den Taschen in jeder Lage).
static func _rough_long(prof: PackedFloat32Array, goal: PackedFloat32Array, p: Dictionary) -> Dictionary:
	var t: Dictionary = p["t"]
	var sc: float = p["sc"]
	var need := _need(prof, goal)
	if need.x < 0:
		return {"moves": [], "info": "Nichts zu zerspanen."}
	var w := Pass.new(t, prof, sc, p["pos"])
	var x_top := 0.0
	for i in range(need.x, need.y + 1):
		x_top = maxf(x_top, prof[i])
	var k0 := int(ceil(maxf(float(p["zlim"]), need.x * SEG - float(t["zmax"]) - 1.0) / SEG))
	var k1 := int(ceil(((need.y + 1) * SEG - float(t["zmin"]) + sc) / SEG))
	var xs := PackedFloat32Array()
	for k in range(k0, k1 + 1):
		xs.append(w.safe(goal, k))
	# tiefste Lage: tiefste erreichbare Stelle, an der auch Material weg muss
	var x_bot := INF
	for k in range(k0, k1 + 1):
		if w.clear_at(k) > xs[k - k0] + 0.01:
			x_bot = minf(x_bot, xs[k - k0])
	x_bot = maxf(x_bot, 0.0)
	if x_bot >= x_top - 0.01:
		return {"err": "Kontur mit %s nicht erreichbar (Platte stößt an)." % t["id"]}
	var nl := maxi(1, int(ceil((x_top - x_bot) / float(p["d"]) - 0.001)))
	var step := (x_top - x_bot) / nl
	var zr: Vector2 = p["zr"]
	# Bereiche je Lage: zusammenhängende Schneidenlagen mit xs <= Lage. Eine Lage-Spanne, deren
	# rechter Nachbar höher liegt, ist ein Hinterschnitt; er gehört zur Tasche, in der er beginnt.
	var main: Array = []
	var pockets := {}          # Wurzel-Spanne -> Array der Spannen (von oben nach unten)
	var prev: Array = []       # Spannen der vorigen Lage: [ka, kb, wurzel]
	for li in range(1, nl + 1):
		var lv := x_top - li * step
		var lp := lv + step
		var spans: Array = []
		var k := k1
		while k >= k0:
			if xs[k - k0] > lv + EPS:
				k -= 1
				continue
			var kb := k
			while k - 1 >= k0 and xs[k - 1 - k0] <= lv + EPS:
				k -= 1
			var ka := k
			k -= 1
			# rechts begrenzt: Einstieg von oben (Eintauchen). Hinterschnitt nur, wenn die Begrenzung
			# zur Kontur selbst gehört - nicht das stehende Material rechts einer Kontur mitten am Teil
			var bounded := kb != k1
			var open := not bounded
			if bounded:
				open = true
				var tg0: PackedFloat32Array = p["tg"]   # Soll ohne Aufmaß (UZ greift sonst über den Rand)
				for i in range(maxi(kb + 1, 0), mini(int(floor(zr.y / SEG)), tg0.size())):
					if tg0[i] > lv + EPS:
						open = false
						break
			var root := ""
			if not open:
				root = "%d:%d" % [ka, kb]
				for q in prev:
					if ka >= int(q[0]) and kb <= int(q[1]) and str(q[2]) != "":
						root = str(q[2])     # Fortsetzung einer Tasche aus der Lage darüber
			spans.append([ka, kb, root])
			var job := {"ka": ka, "kb": kb, "lv": lv, "lp": lp, "pocket": bounded}
			if open:
				main.append(job)
			elif bool(p["hs"]):
				if not pockets.has(root):
					pockets[root] = []
				pockets[root].append(job)
		prev = spans
	var jobs: Array = main.duplicate()
	var roots: Array = pockets.keys()
	roots.sort_custom(func(a, b): return int(str(a).split(":")[1]) > int(str(b).split(":")[1]))
	for r in roots:
		jobs.append_array(pockets[r])
	for job in jobs:
		_rough_span(w, xs, k0, k1, job)
	_rough_rest(w, xs, k0, k1, bool(p["hs"]), zr.y)
	if w.mv.size() <= 1:
		return {"moves": [], "info": "Nichts zu zerspanen."}
	var e := w.last()
	w.mv.append([e.x, maxf(_max_prof(prof) + sc, e.y), true])
	return {"moves": _simplify(w.moves()), "cur": w.cur}


## Abschluss des Schruppens: konturparallel mit Aufmaß dort, wo zwischen zwei Lagen noch eine
## Stufe steht (Absatz, dessen Höhe zwischen zwei Schnitten liegt). Ohne Hinterschnitte folgt der
## Zug der Hülle der Kontur (Taschen werden überfahren, nicht ausgeräumt).
static func _rough_rest(w: Pass, xs: PackedFloat32Array, k0: int, k1: int, hs: bool, zhi: float) -> void:
	var px := xs.duplicate()
	if not hs:
		# Hülle ab dem rechten Konturende (Material rechts einer Kontur mitten am Teil zählt nicht)
		for k in range(k1 - 1, k0 - 1, -1):
			if (k + 1) * SEG < zhi - SEG:
				px[k - k0] = maxf(px[k - k0], px[k + 1 - k0])
	var gap := int(ceil(2.0 * w.sc / SEG))
	var k := k1
	while k >= k0:
		if w.clear_at(k) <= px[k - k0] + 0.08:
			k -= 1
			continue
		# zusammenhängender Bereich mit Rest (kleine Lücken überbrücken)
		var rb := k
		var ra := k
		var q := k - 1
		while q >= k0 and q >= ra - gap:
			if w.clear_at(q) > px[q - k0] + 0.08:
				ra = q
			q -= 1
		k = ra - 1
		rb = mini(rb + 1, k1)
		ra = maxi(ra - 1, k0)
		var pts := PackedVector2Array([Vector2(rb * SEG, px[rb - k0])])
		for r in range(rb - 1, ra - 1, -1):
			var x := px[r - k0]
			var xp := px[r + 1 - k0]
			if x - xp > 2.0 * SEG:
				pts.append(Vector2((r + 1) * SEG, x))
			elif xp - x > 2.0 * SEG:
				pts.append(Vector2(r * SEG, xp))
			pts.append(Vector2(r * SEG, x))
		pts = _simplify_pts(pts)
		var s0 := pts[0]
		if w.clear_span(s0.x, s0.x + w.sc) <= s0.y + 0.01:
			w.travel(s0.x + w.sc, s0.y)
		else:
			w.travel(s0.x, s0.y + w.sc)
		for pt in pts:
			w.feed(pt.x, pt.y)
		var e := pts[pts.size() - 1]
		if w.clear_span(e.x, e.x + w.sc) <= e.y + 0.01:
			w.feed(e.x + w.sc, e.y + w.sc, false)
		else:
			w.mv.append([e.x, e.y + w.sc, true])


## Ein Schruppschnitt auf Höhe lv in der Spanne ka..kb (Schneidenlagen).
static func _rough_span(w: Pass, xs: PackedFloat32Array, k0: int, k1: int, job: Dictionary) -> void:
	var ka: int = job["ka"]
	var kb: int = job["kb"]
	var lv: float = job["lv"]
	var lp: float = job["lp"]
	# Material auf dieser Höhe: rechtes und linkes Ende
	var ks := -1
	for q in range(kb, ka - 1, -1):
		if w.clear_at(q) > lv + 0.01:
			ks = q
			break
	if ks < 0:
		return
	var ke := ks
	for q in range(ka, ks + 1):
		if w.clear_at(q) > lv + 0.01:
			ke = q
			break
	# Steht an der Kontur links (Absatz) noch eine Stufe von der vorigen Lage, bis dorthin schneiden
	var to_wall := ke == ka
	if not to_wall and ka > k0:
		var q := ka - 1
		while q >= k0 and xs[q - k0] > lv and xs[q - k0] <= lp + EPS:
			if w.clear_at(q) > xs[q - k0] + 0.02:
				to_wall = true
				break
			q -= 1
	if to_wall:
		ke = ka
	# Einstieg
	if not bool(job["pocket"]) or ks < kb:
		w.travel(mini(kb, ks + int(ceil(w.sc / SEG))) * SEG, lv)
	else:
		# Hinterschnitt: an der rechten Flanke entlang konturparallel eintauchen
		var q := kb
		while q + 1 <= k1 and xs[q + 1 - k0] < lp - EPS and xs[q + 1 - k0] > xs[q - k0] + EPS:
			q += 1
		w.travel(q * SEG, maxf(xs[q - k0], lv))
		for r in range(q - 1, kb - 1, -1):
			w.feed(r * SEG, maxf(xs[r - k0], lv))
	w.feed(ke * SEG, lv)
	# Kontur bis zur vorigen Lage nachziehen (nur steigend, nur solange dort Material steht)
	var kz := ke
	var xc := lv
	if to_wall:
		while kz - 1 >= k0:
			var xn := xs[kz - 1 - k0]
			if xn < xc - EPS or xn > lp + EPS:
				break
			if w.clear_at(kz - 1) <= xn + 0.01:
				break
			kz -= 1
			if xn - xc > 2.0 * SEG:
				w.feed((kz + 1) * SEG, xn)
			w.feed(kz * SEG, xn)
			xc = xn
	# 45° abheben - oder senkrecht, wenn rechts daneben gleich wieder Kontur steht
	var lz := kz * SEG + w.sc
	if w.clear_span(kz * SEG, lz) <= xc + 0.01:
		w.feed(lz, xc + w.sc, false)
	else:
		w.mv.append([kz * SEG, xc + w.sc, true])


## Planschruppen: Schnitte in X- (zur Mitte) auf abnehmenden Z, Kontur nachziehen.
static func _rough_face(prof: PackedFloat32Array, goal: PackedFloat32Array, p: Dictionary) -> Dictionary:
	var t: Dictionary = p["t"]
	var sc: float = p["sc"]
	var need := _need(prof, goal)
	if need.x < 0:
		return {"moves": [], "info": "Nichts zu zerspanen."}
	var zmin_t := float(t["zmin"])
	var x_top := 0.0
	for i in range(need.x, need.y + 1):
		x_top = maxf(x_top, prof[i])
	var x_s := x_top + sc
	var x_clear := _max_prof(prof) + sc
	var f_top := (need.y + 1) * SEG
	var f_bot := need.x * SEG
	var nl := maxi(1, int(ceil((f_top - f_bot) / float(p["d"]) - 0.001)))
	var step := (f_top - f_bot) / nl
	var mv: Array = []
	var pos: Vector2 = p["pos"]
	var zlim: float = p["zlim"]
	for li in range(1, nl + 1):
		var zl := maxf(f_top - li * step - zmin_t, zlim)
		var zp := f_top - (li - 1) * step - zmin_t
		var xe := safe_x(t, goal, zl)
		var mat := 0.0
		for i in range(maxi(int(floor((zl + zmin_t) / SEG)), 0), mini(int(floor((zl + float(t["zmax"])) / SEG)), prof.size() - 1) + 1):
			mat = maxf(mat, prof[i])
		if xe >= mat - 0.01 or xe >= x_s:
			continue
		if xe <= 0.01:
			xe = CENTER_OVER
		if mv.is_empty():
			_approach(mv, pos, zl, x_s, x_clear)
		else:
			_rapid_to(mv, zl, x_s)
		mv.append([zl, maxf(xe, CENTER_OVER), false])
		# Nachziehen: Kontur zwischen dieser und der vorigen Schnittebene (fallend in X)
		var zc := zl
		var xc := xe
		if xe > 0.0:
			var z := zl + SEG
			while z <= zp + 0.0001:
				var xn := safe_x(t, goal, z)
				if xn > xc + 0.0001:
					break
				mv.append([z, maxf(xn, 0.0), false])
				zc = z
				xc = maxf(xn, 0.0)
				z += SEG
		mv.append([zc + sc, xc + sc, false])          # abheben
		mv.append([zc + sc, x_s, true])
	if mv.is_empty():
		return {"moves": [], "info": "Nichts zu zerspanen."}
	mv.append([mv[mv.size() - 1][0], x_clear, true])
	return {"moves": _simplify(mv)}


## Schlichten entlang der Kontur. Längs: von rechts nach links (Z-); steile Flächen (Absätze)
## werden von oben nach innen geschlichtet. Plan: von links (großer Ø) zur Mitte.
static func _finish(prof: PackedFloat32Array, goal: PackedFloat32Array, path_goal: PackedFloat32Array, p: Dictionary, face: bool) -> Dictionary:
	var t: Dictionary = p["t"]
	var sc: float = p["sc"]
	var need := _need(prof, goal, 0.003)
	if need.x < 0:
		return {"moves": [], "info": "Kontur bereits fertig."}
	var x_all := _max_prof(prof)
	var x_clear := x_all + sc
	var w := Pass.new(t, prof, sc, p["pos"])
	# Schlichtbahn nur über die programmierte Kontur (zr), wie die Steuerung die Kontur vom Anfang
	# bis zum Ende abfährt - nicht an Rohteil oder Nachbarkonturen entlang. Links eine Lage mehr:
	# dort steht ggf. die Schulter, an der die Kontur endet.
	var zr: Vector2 = p["zr"]
	var k_lim := int(ceil(float(p["zlim"]) / SEG))
	var kl := maxi(k_lim, int(floor(zr.x / SEG + 0.0001)))
	var kr := maxi(kl + 1, int(ceil(zr.y / SEG - 0.0001)))
	# Konturzug der Schneide von rechts nach links; senkrechte Sprünge als Ecke
	var pts := PackedVector2Array()
	var prev_x := NAN
	for k in range(kr, kl - 2, -1):
		if k < k_lim:
			break
		var x := maxf(w.safe(path_goal, k), 0.0)
		if k == kl - 1:
			if x - prev_x > 2.0 * SEG:
				pts.append(Vector2((k + 1) * SEG, x))   # Schulter am Konturende hinauf
			break
		if not is_nan(prev_x):
			if x - prev_x > 2.0 * SEG:
				pts.append(Vector2((k + 1) * SEG, x))
			elif prev_x - x > 2.0 * SEG:
				pts.append(Vector2(k * SEG, prev_x))    # Einstich: erst über die Kante, dann hinein
		pts.append(Vector2(k * SEG, x))
		prev_x = x
	pts = _simplify_pts(pts)
	if pts.size() < 2:
		return {"moves": [], "info": "Kontur bereits fertig."}
	var mv: Array = []
	var pos: Vector2 = p["pos"]
	if face:
		pts.reverse()
		# Anfang: direkt über der ersten Planfläche ansetzen (nur EINE Zustellung - kein Anfahren
		# am Außendurchmesser und Nachrücken in Z). Ende: an der Drehmitte aufhören, nicht noch
		# auf X0 in Z weiterfahren.
		var s := 0
		for q in range(pts.size() - 1):
			if pts[q + 1].y < pts[q].y - 2.0 * SEG:
				s = q
				break
		var e := pts.size() - 1
		for q in range(s, pts.size()):
			if pts[q].y <= 0.01:
				e = q
				break
		pts = pts.slice(s, e + 1)
		w.travel(pts[0].x, minf(pts[0].y + sc, maxf(x_clear, pts[0].y)))
		for q in pts:
			w.feed(q.x, q.y)
		var last := pts[pts.size() - 1]
		if last.y <= 0.01:
			w.feed(last.x, CENTER_OVER)
		w.feed(last.x + sc, maxf(last.y, 0.0) + sc, false)
		w.mv.append([last.x + sc, maxf(x_clear, last.y + sc), true])
		return {"moves": _simplify(w.moves()), "finish": true}
	# längs: die Kontur vom Anfang bis zum Ende abfahren - von rechts kommend die Planflächen hinauf,
	# die Durchmesser entlang und in Einstiche hinein, in einem Zug (das Schlichtaufmaß vor
	# Planflächen nimmt die Schneide mit)
	var thick := _finish_too_thick(prof, goal, t)
	if thick != "":
		return {"err": thick}
	# Anfahren: an der Drehmitte bzw. bei freiem Raum rechts waagerecht auf den Konturanfang zu,
	# sonst (Kontur beginnt neben stehendem Material, z. B. ein Freistich hinter dem Gewinde) von oben.
	var s0 := pts[0]
	if s0.y <= 0.01 or w.clear_span(s0.x, s0.x + sc) <= s0.y + 0.01:
		w.travel(s0.x + sc, s0.y)
	else:
		w.travel(s0.x, s0.y + sc)
	w.feed(s0.x, s0.y)
	for q in range(1, pts.size()):
		w.feed(pts[q].x, pts[q].y)
	var e := w.last()
	w.mv.append([e.x, maxf(x_clear, e.y + sc), true])
	return {"moves": _simplify(w.moves()), "finish": true}


## Schlichten setzt ein Schruppen voraus: steht irgendwo radial mehr als die zulässige Zustellung
## über der Kontur - und nicht nur als dünnes Planaufmaß direkt vor einer Planfläche -, Fehlertext.
static func _finish_too_thick(prof: PackedFloat32Array, goal: PackedFloat32Array, t: Dictionary) -> String:
	var lim := float(t["max_dx"]) + 0.05
	var near := int(ceil(1.0 / SEG))
	for i in prof.size():
		if prof[i] - goal[i] <= lim:
			continue
		var face_layer := false
		for j in range(maxi(i - near, 0), mini(i + near, prof.size() - 1) + 1):
			if goal[j] >= prof[i] - lim:   # dahinter steht die Schulter (mit ihrem Aufmaß)
				face_layer = true
				break
		if not face_layer:
			return "Zu viel Material für das Schlichten (%.1f mm) - vorher schruppen." % (prof[i] - goal[i])
	return ""


static func _steep(a: Vector2, b: Vector2) -> bool:
	var rise := b.y - a.y
	return rise > 0.5 and rise > 2.0 * absf(a.x - b.x)


static func _simplify_pts(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		var n := out.size()
		if n >= 2:
			var d1 := out[n - 1] - out[n - 2]
			var d2 := q - out[n - 1]
			if absf(d1.cross(d2)) < 0.0005 * maxf(d1.length(), 0.001) and d1.dot(d2) > 0.0:
				out[n - 1] = q
				continue
		if n >= 1 and out[n - 1].distance_to(q) < 0.0005:
			continue
		out.append(q)
	return out


## Aufeinanderfolgende kollineare Züge gleicher Art zusammenfassen, Nullwege entfernen.
static func _simplify(mv: Array) -> Array:
	var out: Array = []
	for m in mv:
		var n := out.size()
		var q := Vector2(m[0], m[1])
		if n >= 1:
			var l: Array = out[n - 1]
			if Vector2(l[0], l[1]).distance_to(q) < 0.0005:
				continue
		if n >= 2:
			var l1: Array = out[n - 1]
			var l0: Array = out[n - 2]
			if bool(l1[2]) == bool(m[2]):
				var a := Vector2(l0[0], l0[1])
				var b := Vector2(l1[0], l1[1])
				var d1 := b - a
				var d2 := q - b
				if absf(d1.cross(d2)) < 0.0005 * maxf(d1.length(), 0.001) and d1.dot(d2) > 0.0:
					out[n - 1] = [m[0], m[1], m[2]]
					continue
		out.append([float(m[0]), float(m[1]), bool(m[2])])
	return out


# ======================================================================= Simulation

## Ganzes Programm vorausberechnen (ohne die Maschine zu bewegen): Bahnen aller Abspansätze auf
## dem fortgeschriebenen Material, Bearbeitungszeit. lathe liefert Material, Lage und Werkzeuge.
static func simulate(prog: Dictionary, lathe) -> Dictionary:
	var prof: PackedFloat32Array = lathe.profile.duplicate()
	var hd := head(prog)
	var zoff: float = lathe.wcs_z
	var pos := Vector2(lathe.tool_z, lathe.tool_x)
	var cur_t := str(lathe.tool()["id"])
	var moves: Array = []
	var polys: Array = []
	var time := 0.0
	var errs: Array[String] = []
	var blocks: Array = prog.get("blocks", [])
	for bi in blocks.size():
		var b: Dictionary = blocks[bi]
		if str(b["type"]) == "contour":
			polys.append(contour_points(b))
		elif str(b["type"]) == "undercut":
			polys.append(contour_points(undercut_contour(b)))
		if not is_machining(b):
			continue
		var tid := str(b["t"])
		var ti := LatheTools.index_of(tid)
		if ti < 0:
			errs.append("Satz %d: Werkzeug %s unbekannt." % [bi + 1, tid])
			continue
		if lathe.holder.find(tid) < 0:
			errs.append("Satz %d: %s ist nicht im Werkzeughalter bestückt." % [bi + 1, tid])
		var t := LatheTools.get_tool(ti)
		if tid != cur_t:
			var wp := Vector2(float(hd["zt"]) + zoff, float(hd["xt"]) * 0.5)
			time += pos.distance_to(wp) / RAPID + 4.0
			pos = wp
			cur_t = tid
		var r := plan(b, prog, t, {"prof": prof, "pos": pos, "zlim": maxf(1.0, -float(t["zmin"]) + 0.5), "zoff": zoff})
		if r.has("err"):
			errs.append("Satz %d: %s" % [bi + 1, r["err"]])
			continue
		for m in r["moves"]:
			var q := Vector2(m[0], m[1])
			var dist := pos.distance_to(q)
			if bool(m[2]):
				time += dist / RAPID
			else:
				var x := maxf(absf((pos.y + q.y) * 0.5), 0.5)
				var nn := clampf(float(b["v"]) * 1000.0 / (PI * 2.0 * x), RPM_MIN, float(hd["smax"]))
				time += dist / maxf(float(b["f"]) * nn / 60.0, 0.01)
			moves.append([m[0], m[1], m[2], bi])
			pos = q
		prof = r["after"]
	return {"moves": moves, "prof": prof, "polys": polys, "time": time, "errs": errs}
