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
## V (m/min, konstante Schnittgeschwindigkeit), D Zustellung, UX Aufmaß X (Ø), UZ Aufmaß Z.
##
## Bahnen gelten für die Schneide (WKS wie die Positionsanzeige: Z ab Backen-Stirnfläche, X im
## Radius). Damit nichts ins Fertigteil schneidet, rechnet die Bahn mit der echten Plattenform:
## safe_x(z) ist die tiefste Lage der Schneide bei z, bei der die Platte die Sollkontur nicht
## verletzt (vollständige Schneidenradiuskorrektur). Ein Zug ist ein Array [z, x, eilgang].

const SEG := 0.25               # wie Lathe.SEG
const RPM_MIN := 40.0           # wie Lathe.RPM_MIN
const RAPID := 100.0            # Eilgang mm/s
const CENTER_OVER := -0.4       # über die Drehmitte hinaus plandrehen (Restzapfen)
const MODES := ["Schruppen", "Schlichten"]
const DIRS := ["längs", "plan"]
const TRANS := ["-", "Fase", "Radius"]


# ======================================================================= Programme

static func new_program(pname: String) -> Dictionary:
	return {"name": pname, "blocks": [new_block("head")]}


static func new_block(type: String, prog := {}) -> Dictionary:
	match type:
		"head":
			return {"type": "head", "sc": 1.0, "xt": 160.0, "zt": 230.0, "smax": 2500.0, "kss": 1}
		"cut":
			return {"type": "cut", "mode": 0, "dir": 0, "t": "T1", "f": 0.25, "v": 180.0,
				"z0": 160.0, "x1": 50.0, "z1": 100.0, "d": 2.0, "ux": 0.4, "uz": 0.2}
		"contour":
			var n := 1
			while not find_contour(prog, "KONTUR%d" % n).is_empty():
				n += 1
			return {"type": "contour", "name": "KONTUR%d" % n, "x0": 0.0, "z0": 150.0, "els": [
				{"x": 40.0, "z": 150.0, "tr": 0, "tv": 0.0},
				{"x": 40.0, "z": 100.0, "tr": 0, "tv": 0.0},
				{"x": 64.0, "z": 100.0, "tr": 0, "tv": 0.0},
			]}
		"stock":
			var cname := ""
			for b in prog.get("blocks", []):
				if str(b["type"]) == "contour":
					cname = str(b["name"])
			return {"type": "stock", "contour": cname, "mode": 0, "dir": 0, "t": "T1", "f": 0.25,
				"v": 180.0, "d": 2.0, "ux": 0.4, "uz": 0.2}
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
	return str(b.get("type", "")) in ["cut", "stock"]


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
				b["contour"], b["t"], fmt(b["f"]), int(b["v"]), ("  D%s" % fmt(b["d"])) if int(b["mode"]) == 0 else ""]
	return "?"


## Beispielprogramme (stehen im Programm-Manager, wenn noch keine Programme da sind).
static func examples() -> Array:
	var welle := new_program("WELLE_AUFTRAG2")
	welle["blocks"].append({"type": "contour", "name": "WELLE", "x0": 0.0, "z0": 150.0, "els": [
		{"x": 50.0, "z": 150.0, "tr": 1, "tv": 1.0},
		{"x": 50.0, "z": 90.0, "tr": 0, "tv": 0.0},
		{"x": 58.0, "z": 90.0, "tr": 0, "tv": 0.0},
		{"x": 58.0, "z": 5.0, "tr": 0, "tv": 0.0},
		{"x": 64.0, "z": 5.0, "tr": 0, "tv": 0.0},
	]})
	welle["blocks"].append({"type": "stock", "contour": "WELLE", "mode": 0, "dir": 0, "t": "T1", "f": 0.3,
		"v": 180.0, "d": 2.5, "ux": 0.4, "uz": 0.2})
	welle["blocks"].append({"type": "stock", "contour": "WELLE", "mode": 1, "dir": 0, "t": "T3", "f": 0.1,
		"v": 220.0, "d": 1.0, "ux": 0.0, "uz": 0.0})
	var plan := new_program("PLANEN_2MM")
	plan["blocks"].append({"type": "cut", "mode": 0, "dir": 1, "t": "T1", "f": 0.2, "v": 180.0,
		"z0": 160.0, "x1": 0.0, "z1": 158.0, "d": 1.0, "ux": 0.0, "uz": 0.0})
	var flansch := new_program("BUND_PLAN")
	flansch["blocks"].append({"type": "contour", "name": "BUND", "x0": 0.0, "z0": 156.0, "els": [
		{"x": 30.0, "z": 156.0, "tr": 0, "tv": 0.0},
		{"x": 30.0, "z": 140.0, "tr": 2, "tv": 2.0},
		{"x": 52.0, "z": 140.0, "tr": 1, "tv": 1.0},
		{"x": 52.0, "z": 120.0, "tr": 0, "tv": 0.0},
		{"x": 64.0, "z": 120.0, "tr": 0, "tv": 0.0},
	]})
	flansch["blocks"].append({"type": "stock", "contour": "BUND", "mode": 0, "dir": 1, "t": "T1", "f": 0.25,
		"v": 180.0, "d": 2.0, "ux": 0.4, "uz": 0.2})
	flansch["blocks"].append({"type": "stock", "contour": "BUND", "mode": 1, "dir": 1, "t": "T3", "f": 0.1,
		"v": 220.0, "d": 1.0, "ux": 0.0, "uz": 0.0})
	return [welle, plan, flansch]


# ======================================================================= Kontur

## Kontur als Polylinie Vector2(z, r) mit eingerechneten Fasen und Rundungen.
static func contour_points(c: Dictionary) -> PackedVector2Array:
	var pts: Array[Vector2] = [Vector2(float(c["z0"]), float(c["x0"]) * 0.5)]
	var trs: Array = [[0, 0.0]]
	for e in c.get("els", []):
		var p := Vector2(float(e["z"]), float(e["x"]) * 0.5)
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
static func target(b: Dictionary, prog: Dictionary, prof: PackedFloat32Array) -> Dictionary:
	var n := prof.size()
	var tg := PackedFloat32Array()
	tg.resize(n)
	if str(b["type"]) == "cut":
		var za := minf(float(b["z0"]), float(b["z1"]))
		var zb := maxf(float(b["z0"]), float(b["z1"]))
		var r1 := maxf(float(b["x1"]) * 0.5, 0.0)
		if zb - za < SEG:
			return {"err": "Abspanen: Bereich Z0 bis Z1 zu kurz."}
		for i in n:
			var zc := (i + 0.5) * SEG
			tg[i] = minf(prof[i], r1) if zc > za and zc < zb else prof[i]
		return {"tg": tg, "zlo": za, "zhi": zb}
	var c := find_contour(prog, str(b.get("contour", "")))
	if c.is_empty():
		return {"err": "Kontur \"%s\" nicht im Programm." % b.get("contour", "")}
	var poly := contour_points(c)
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
	for i in n:
		var a := i * SEG + 0.0001
		var e := (i + 1) * SEG - 0.0001
		if (i + 0.5) * SEG < zlo:
			tg[i] = prof[i]
		elif a > zhi:
			tg[i] = 0.0
		else:
			var r := poly_max(poly, a, e)
			tg[i] = minf(prof[i], r if r >= 0.0 else 0.0)
	return {"tg": tg, "zlo": zlo, "zhi": zhi, "poly": poly}


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
## der Maschine für dieses Werkzeug). Ergebnis: {"moves", "after" (Material danach), "err", "info"}.
static func plan(b: Dictionary, prog: Dictionary, t: Dictionary, ctx: Dictionary) -> Dictionary:
	var err := check_block(b, t)
	if err != "":
		return {"err": err}
	var prof: PackedFloat32Array = ctx["prof"]
	var tr := target(b, prog, prof)
	if tr.has("err"):
		return {"err": tr["err"]}
	var tg: PackedFloat32Array = tr["tg"]
	var hd := head(prog)
	var p := {
		"sc": maxf(float(hd["sc"]), 0.2), "d": float(b["d"]), "zlim": float(ctx.get("zlim", 1.0)),
		"t": t, "pos": ctx["pos"],
	}
	var finish := int(b["mode"]) == 1
	var face := int(b["dir"]) == 1
	var goal := tg if finish else dilate(tg, maxf(float(b["ux"]), 0.0) * 0.5, maxf(float(b["uz"]), 0.0))
	var res: Dictionary
	if finish:
		res = _finish(prof, goal, p, face)
	elif face:
		res = _rough_face(prof, goal, p)
	else:
		res = _rough_long(prof, goal, p)
	if res.has("err"):
		return res
	var after := prof.duplicate()
	for i in after.size():
		after[i] = minf(after[i], goal[i])
	res["after"] = after
	res["tg"] = tg
	if tr.has("poly"):
		res["poly"] = tr["poly"]
	return res


## Plausibilität eines Abspansatzes für Werkzeug t ("" = in Ordnung).
static func check_block(b: Dictionary, t: Dictionary) -> String:
	if int(t.get("feed_dir", -1)) > 0:
		return "%s ist ein Linksmeißel - die Zyklen arbeiten zum Futter bzw. zur Mitte hin (z. B. T1, T3)." % t["id"]
	if float(b["f"]) < 0.01 or float(b["f"]) > 0.5:
		return "Vorschub F muss zwischen 0.01 und 0.5 mm/U liegen."
	if float(b["v"]) < 20.0 or float(b["v"]) > 400.0:
		return "Schnittgeschwindigkeit V muss zwischen 20 und 400 m/min liegen."
	if int(b["mode"]) == 0:
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


## Längsschruppen: Schnitte in Z- auf abnehmenden Durchmessern, am Schnittende Kontur nachziehen.
static func _rough_long(prof: PackedFloat32Array, goal: PackedFloat32Array, p: Dictionary) -> Dictionary:
	var t: Dictionary = p["t"]
	var sc: float = p["sc"]
	var need := _need(prof, goal)
	if need.x < 0:
		return {"moves": [], "info": "Nichts zu zerspanen."}
	var zmin_t := float(t["zmin"])
	var zmax_t := float(t["zmax"])
	var x_top := 0.0
	for i in range(need.x, need.y + 1):
		x_top = maxf(x_top, prof[i])
	var k0 := int(ceil(maxf(float(p["zlim"]), need.x * SEG - zmax_t - 1.0) / SEG))
	var k1 := int(ceil(((need.y + 1) * SEG - zmin_t + sc) / SEG))
	var xs := PackedFloat32Array()
	for k in range(k0, k1 + 1):
		xs.append(safe_x(t, goal, k * SEG))
	var x_bot := INF
	for v in xs:
		x_bot = minf(x_bot, v)
	x_bot = maxf(x_bot, 0.0)
	if x_bot >= x_top - 0.01:
		return {"err": "Kontur mit %s nicht erreichbar (Platte stößt an)." % t["id"]}
	var nl := maxi(1, int(ceil((x_top - x_bot) / float(p["d"]) - 0.001)))
	var step := (x_top - x_bot) / nl
	var x_clear := _max_prof(prof) + sc
	var mv: Array = []
	var pos: Vector2 = p["pos"]
	for li in range(1, nl + 1):
		var lv := x_top - li * step
		var lp := x_top - (li - 1) * step
		# Materialende in dieser Höhe -> Schnittbeginn
		var jh := -1
		for i in range(need.y, need.x - 1, -1):
			if prof[i] > lv + 0.001:
				jh = i
				break
		if jh < 0:
			continue
		var ks := mini(k1, int(ceil(((jh + 1) * SEG - zmin_t + sc) / SEG)))
		if xs[ks - k0] > lv + 0.0001:
			continue
		var ke := ks
		while ke - 1 >= k0 and xs[ke - 1 - k0] <= lv + 0.0001:
			ke -= 1
		if ke == ks:
			continue
		if mv.is_empty():
			_approach(mv, pos, ks * SEG, lv, x_clear)
		else:
			_rapid_to(mv, ks * SEG, lv)
		mv.append([ke * SEG, lv, false])
		# Kontur bis zur vorigen Schnitthöhe nachziehen (nur steigend, keine Hinterschnitte)
		var kz := ke
		var xc := lv
		while kz - 1 >= k0:
			var xn := xs[kz - 1 - k0]
			if xn < xs[kz - k0] - 0.0001 or xn > lp + 0.0001:
				break
			kz -= 1
			if xn - xc > 2.0 * SEG:
				mv.append([(kz + 1) * SEG, xn, false])
			mv.append([kz * SEG, xn, false])
			xc = xn
		mv.append([kz * SEG + sc, xc + sc, false])   # 45° abheben
	if mv.is_empty():
		return {"moves": [], "info": "Nichts zu zerspanen."}
	mv.append([mv[mv.size() - 1][0], x_clear, true])
	return {"moves": _simplify(mv)}


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
static func _finish(prof: PackedFloat32Array, goal: PackedFloat32Array, p: Dictionary, face: bool) -> Dictionary:
	var t: Dictionary = p["t"]
	var sc: float = p["sc"]
	var need := _need(prof, goal, 0.003)
	if need.x < 0:
		return {"moves": [], "info": "Kontur bereits fertig."}
	var zmin_t := float(t["zmin"])
	var zmax_t := float(t["zmax"])
	var x_all := _max_prof(prof)
	var x_clear := x_all + sc
	var k0 := int(ceil(maxf(float(p["zlim"]), need.x * SEG - zmax_t - 1.0) / SEG))
	var k1 := int(ceil(((need.y + 1) * SEG - zmin_t + sc) / SEG))
	# Konturzug der Schneide von rechts nach links, steile Sprünge als Ecke
	var pts := PackedVector2Array()
	var prev_x := NAN
	for k in range(k1, k0 - 1, -1):
		var x := maxf(safe_x(t, goal, k * SEG), 0.0)
		if not is_nan(prev_x) and x - prev_x > 2.0 * SEG:
			pts.append(Vector2((k + 1) * SEG, x))
		pts.append(Vector2(k * SEG, x))
		prev_x = x
		if x >= x_all - 0.005 and k * SEG < need.x * SEG:
			break   # links vom Bearbeitungsbereich auf Rohteilhöhe angekommen
	pts = _simplify_pts(pts)
	var mv: Array = []
	var pos: Vector2 = p["pos"]
	if face:
		pts.reverse()
		_approach(mv, pos, pts[0].x, minf(pts[0].y + sc, x_clear), x_clear)
		for q in pts:
			mv.append([q.x, q.y, false])
		var last := pts[pts.size() - 1]
		if last.y <= 0.01:
			mv.append([last.x, CENTER_OVER, false])
		mv.append([last.x + sc, maxf(last.y, 0.0) + sc, false])
		mv.append([last.x + sc, x_clear, true])
		return {"moves": _simplify(mv)}
	# längs
	_approach(mv, pos, pts[0].x, pts[0].y, x_clear)
	var lim := maxf(0.3, float(t["max_dz"]) * 0.5)
	var i := 0
	while i < pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if not _steep(a, b):
			mv.append([b.x, b.y, false])
			i += 1
			continue
		var j := i + 1
		while j < pts.size() - 1 and _steep(pts[j], pts[j + 1]):
			j += 1
		var top := pts[j]
		# Materialschicht vor der Fläche (rechts davon) über der Schneide?
		var hi_seg := -1
		var s0 := maxi(int(floor((a.x + zmin_t) / SEG)), 0)
		var s1 := mini(int(floor((a.x + zmax_t + 20.0) / SEG)), prof.size() - 1)
		for s in range(s0, s1 + 1):
			if prof[s] > a.y + lim:
				hi_seg = s
		if hi_seg < 0:
			for q in range(i + 1, j + 1):
				mv.append([pts[q].x, pts[q].y, false])
			i = j
			continue
		var zg := (hi_seg + 1) * SEG - zmin_t + 0.3
		# bisherige Bahn (letzter Zug endet in a) bei zg kappen
		var last: Array = mv[mv.size() - 1]
		var prev: Array = mv[mv.size() - 2]
		if zg < float(prev[0]) - 0.001 and zg > a.x:
			var f := (zg - float(prev[0])) / (a.x - float(prev[0]))
			mv[mv.size() - 1] = [zg, lerpf(float(prev[1]), a.y, f), false]
		last = mv[mv.size() - 1]
		var xh := top.y + maxf(sc, 0.5)
		mv.append([last[0], xh, false])
		mv.append([top.x, xh, false])
		for q in range(j, i - 1, -1):           # Fläche von oben nach innen
			mv.append([pts[q].x, pts[q].y, false])
		if a.y <= 0.01:
			mv.append([a.x, CENTER_OVER, false])
			mv.append([a.x, a.y, false])
		for q in range(i + 1, j + 1):           # an der fertigen Fläche zurück nach oben
			mv.append([pts[q].x, pts[q].y, false])
		i = j
	var e: Array = mv[mv.size() - 1]
	mv.append([e[0], x_clear, true])
	return {"moves": _simplify(mv)}


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
			var wp := Vector2(float(hd["zt"]), float(hd["xt"]) * 0.5)
			time += pos.distance_to(wp) / RAPID + 4.0
			pos = wp
			cur_t = tid
		var r := plan(b, prog, t, {"prof": prof, "pos": pos, "zlim": maxf(1.0, -float(t["zmin"]) + 0.5)})
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
