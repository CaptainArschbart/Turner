class_name MillNc
extends RefCounted
## NC-Kern der CNC-Fräsmaschine: Klartext-Dialekt nach Vorbild der HEIDENHAIN TNC.
## Reine Logik ohne Szenenbezug. Ein Satz = eine Textzeile (Satznummern stehen nicht im Text).
## Koordinaten wie in MillJobs: Ursprung = vordere linke Ecke der Rohteil-Oberseite, X nach rechts,
## Y nach hinten, Z = 0 auf der rohen Oberseite (Tiefen negativ). Gesteuerter Punkt = Mitte der Werkzeugspitze.
##
## parse_line / format_block: Text <-> Satz-Dictionary (für den Dialog-Editor).
## compile: ganzes Programm vorab in eine flache Liste von Arbeitsschritten (ops) übersetzen.
## simulate: Abtrag als grobe Höhenkarte.

const RAPID := 12000.0  ## mm/min, Eilgang (FMAX)
const S_MAX := 10000.0  ## 1/min
const TOOL_CHANGE_TIME := 6.0  ## s, pauschal je Werkzeugwechsel
const MAX_MOVES := 100000  ## Bewegungen je Programm, danach Endlosschleife
const MAX_STEPS := 400000  ## ausgeführte Sätze je Programm
const MAX_DEPTH := 8  ## Schachtelungstiefe der Unterprogramme
const ARC_SAG := 0.02  ## mm, größter Sehnenfehler bei Kreisbahnen

## Zyklen für den Dialog-Editor: Nummer -> {"name", "q": [[Nummer, Dialogtext, Standardwert], ...]} in Dialogreihenfolge.
const CYCLES := {
	200: {"name": "BOHREN", "q": [
		[200, "SICHERHEITS-ABST.", 2.0],
		[201, "TIEFE", -20.0],
		[206, "VORSCHUB TIEFENZUST.", 150.0],
		[202, "ZUSTELL-TIEFE", 5.0],
		[210, "VERWEILZEIT OBEN", 0.0],
		[203, "KOORD. OBERFLÄCHE", 0.0],
		[204, "2. SICHERHEITS-ABST.", 50.0],
		[211, "VERWEILZEIT UNTEN", 0.0],
	]},
	233: {"name": "PLANFRAESEN", "q": [
		[225, "STARTPUNKT 1. ACHSE", 0.0],
		[226, "STARTPUNKT 2. ACHSE", 0.0],
		[227, "STARTPUNKT 3. ACHSE", 0.0],
		[386, "ENDPUNKT 3. ACHSE", -1.0],
		[218, "1. SEITEN-LÄNGE", 100.0],
		[219, "2. SEITEN-LÄNGE", 60.0],
		[202, "MAX. ZUSTELL-TIEFE", 3.0],
		[370, "BAHN-ÜBERLAPPUNG", 1.0],
		[207, "VORSCHUB FRÄSEN", 400.0],
		[253, "VORSCHUB VORPOS. (0=EILGANG)", 0.0],
		[357, "SICHERHEITS-ABST. SEITE", 2.0],
		[200, "SICHERHEITS-ABST.", 2.0],
		[204, "2. SICHERHEITS-ABST.", 50.0],
	]},
	251: {"name": "RECHTECKTASCHE", "q": [
		[218, "1. SEITEN-LÄNGE", 50.0],
		[219, "2. SEITEN-LÄNGE", 30.0],
		[367, "TASCHENLAGE (0=MITTE, 1=ECKE)", 0.0],
		[201, "TIEFE", -10.0],
		[202, "ZUSTELL-TIEFE", 3.0],
		[206, "VORSCHUB TIEFENZUST.", 120.0],
		[207, "VORSCHUB FRÄSEN", 300.0],
		[200, "SICHERHEITS-ABST.", 2.0],
		[203, "KOORD. OBERFLÄCHE", 0.0],
		[204, "2. SICHERHEITS-ABST.", 50.0],
		[370, "BAHN-ÜBERLAPPUNG", 1.0],
	]},
	252: {"name": "KREISTASCHE", "q": [
		[223, "KREISDURCHMESSER", 40.0],
		[201, "TIEFE", -10.0],
		[202, "ZUSTELL-TIEFE", 3.0],
		[206, "VORSCHUB TIEFENZUST.", 120.0],
		[207, "VORSCHUB FRÄSEN", 300.0],
		[200, "SICHERHEITS-ABST.", 2.0],
		[203, "KOORD. OBERFLÄCHE", 0.0],
		[204, "2. SICHERHEITS-ABST.", 50.0],
		[370, "BAHN-ÜBERLAPPUNG", 1.0],
	]},
	253: {"name": "NUTENFRAESEN", "q": [
		[218, "NUTLÄNGE", 50.0],
		[219, "NUTBREITE", 12.0],
		[374, "DREHLAGE (0 ODER 90)", 0.0],
		[367, "NUTLAGE (0=MITTE)", 0.0],
		[201, "TIEFE", -6.0],
		[202, "ZUSTELL-TIEFE", 3.0],
		[206, "VORSCHUB TIEFENZUST.", 120.0],
		[207, "VORSCHUB FRÄSEN", 300.0],
		[200, "SICHERHEITS-ABST.", 2.0],
		[203, "KOORD. OBERFLÄCHE", 0.0],
		[204, "2. SICHERHEITS-ABST.", 50.0],
	]},
}

## M-Funktionen für die Anzeige: Nummer -> Text.
const M_CODES := {
	0: "Programmierter Halt",
	2: "Programmende",
	3: "Spindel rechts",
	4: "Spindel links",
	5: "Spindel Halt",
	8: "KSS ein",
	9: "KSS aus",
	13: "Spindel rechts, KSS ein",
	14: "Spindel links, KSS ein",
	30: "Programmende",
	99: "Zyklus nach dem Satz aufrufen",
}

## Beispielprogramme (passend zu MillJobs.LIST). Für Typ Array[String] siehe samples().
const SAMPLES := [
	{"name": "PLANEN", "lines": [
		"BEGIN PGM PLANEN MM",
		"; Fräsauftrag 1: Oberseite 100 x 60 um 2 mm abplanen",
		"; Magazin: T1 = Messerkopf Ø63 (MK63)",
		"BLK FORM 0.1 Z X+0 Y+0 Z-40",
		"BLK FORM 0.2 X+100 Y+60 Z+0",
		"TOOL CALL 1 Z S800",
		"L Z+100 R0 FMAX M13",
		"CYCL DEF 233 PLANFRAESEN Q225=+0 Q226=+0 Q227=+0 Q386=-2 Q218=+100 Q219=+60 Q202=+3 Q370=+1 Q207=+400 Q253=+0 Q357=+2 Q200=+2 Q204=+50",
		"CYCL CALL",
		"L Z+100 R0 FMAX",
		"M30",
		"END PGM PLANEN MM",
	]},
	{"name": "TASCHE", "lines": [
		"BEGIN PGM TASCHE MM",
		"; Fräsauftrag 4: Rechtecktasche 50 x 30, 10 tief, Mitte bei X50 Y30",
		"; Magazin: T2 = Schaftfräser Ø12 (F12)",
		"BLK FORM 0.1 Z X+0 Y+0 Z-40",
		"BLK FORM 0.2 X+100 Y+60 Z+0",
		"TOOL CALL 2 Z S2000",
		"L Z+100 R0 FMAX",
		"L X+50 Y+30 R0 FMAX M13",
		"; Je Seite 0,75 mm größer als das Maß: Der Fräser lässt in den Ecken seinen Eckenradius stehen",
		"CYCL DEF 251 RECHTECKTASCHE Q218=+51.5 Q219=+31.5 Q367=+0 Q201=-10 Q202=+3 Q206=+120 Q207=+300 Q200=+2 Q203=+0 Q204=+50 Q370=+1",
		"CYCL CALL",
		"L Z+100 R0 FMAX",
		"M30",
		"END PGM TASCHE MM",
	]},
	{"name": "BOHRBILD", "lines": [
		"BEGIN PGM BOHRBILD MM",
		"; Fräsauftrag 5: zwei Bohrungen Ø10, 25 tief, bei X25 und X75, Y30",
		"; Magazin: T3 = Spiralbohrer Ø10 (B10)",
		"BLK FORM 0.1 Z X+0 Y+0 Z-40",
		"BLK FORM 0.2 X+100 Y+60 Z+0",
		"TOOL CALL 3 Z S1500",
		"L Z+100 R0 FMAX",
		"CYCL DEF 200 BOHREN Q200=+2 Q201=-25 Q206=+120 Q202=+5 Q210=+0 Q203=+0 Q204=+50 Q211=+0.5",
		"L X+25 Y+30 R0 FMAX M13 M99",
		"L X+75 Y+30 R0 FMAX M99",
		"L Z+100 R0 FMAX",
		"M30",
		"END PGM BOHRBILD MM",
	]},
]

static var _re_tok: RegEx
static var _re_glue: RegEx
static var _re_q: RegEx
static var _re_satz: RegEx


static func _init_re() -> void:
	if _re_tok != null:
		return
	_re_tok = RegEx.new()
	_re_tok.compile("([A-Z]+)([+-]?[0-9.]*)")
	_re_glue = RegEx.new()
	_re_glue.compile("([A-Z])\\s+([+-]?[0-9.])")
	_re_q = RegEx.new()
	_re_q.compile("Q([0-9]+)\\s*=\\s*([+-]?[0-9]*\\.?[0-9]+)")
	_re_satz = RegEx.new()
	_re_satz.compile("^[0-9]+\\s+(?=[A-Z])")


## Beispielprogramme mit echten Array[String]-Zeilen (Kopien, frei veränderbar).
static func samples() -> Array:
	var out: Array = []
	for s in SAMPLES:
		var lines: Array[String] = []
		for l in s["lines"]:
			lines.append(str(l))
		out.append({"name": str(s["name"]), "lines": lines})
	return out


## Standardwert eines Q-Parameters laut CYCLES (0, wenn der Zyklus ihn nicht kennt).
static func q_default(cycle: int, id: int) -> float:
	if CYCLES.has(cycle):
		for e in CYCLES[cycle]["q"]:
			if int(e[0]) == id:
				return float(e[2])
	return 0.0


## "+50", "-10.5", "+0": Vorzeichen immer, höchstens 3 Nachkommastellen, keine Nullen am Ende.
static func fmt(v: float) -> String:
	if absf(v) < 0.0005:
		return "+0"
	var s := "%.3f" % absf(v)
	s = s.rstrip("0").rstrip(".")
	return ("-" if v < 0.0 else "+") + s


static func _plain(v: float) -> String:
	return fmt(v).trim_prefix("+")


static func _num(s: String) -> Variant:
	if s == "" or s == "+" or s == "-" or s == "." or not s.is_valid_float():
		return null
	return s.to_float()


static func _err(text: String) -> Dictionary:
	return {"type": "error", "err": text}


## Zerlegt einen Satzrest in Wörter: [[Buchstaben, Zahlentext], ...].
static func _scan(rest: String) -> Dictionary:
	_init_re()
	var s := _re_glue.sub(rest, "$1$2", true)
	var toks: Array = []
	var covered := 0
	for m in _re_tok.search_all(s):
		toks.append([m.get_string(1), m.get_string(2)])
		covered += m.get_string().length()
	if covered != s.replace(" ", "").length():
		return {"err": "Unlesbare Zeichen in '%s'" % rest.strip_edges()}
	return {"toks": toks}


## Wörter eines L- oder C-Satzes in d eintragen. Rückgabe: Fehlertext oder "".
static func _parse_motion(rest: String, d: Dictionary, circ: bool) -> String:
	var sc := _scan(rest)
	if sc.has("err"):
		return str(sc["err"])
	var ms: Array = []
	for t in sc["toks"]:
		var w: String = t[0]
		var ns: String = t[1]
		match w:
			"X", "Y", "Z", "IX", "IY", "IZ":
				if circ and w.ends_with("Z"):
					return "Achse Z beim Kreis nicht möglich"
				var v: Variant = _num(ns)
				if v == null:
					return "Zahl bei %s fehlt oder ist ungültig" % w
				var ax := w.right(1).to_lower()
				d[ax] = float(v)
				if w.begins_with("I"):
					d["i" + ax] = true
				else:
					d.erase("i" + ax)
			"R":
				if circ:
					return "Radiuskorrektur beim Kreis nicht möglich"
				if ns != "0":
					return "Radiuskorrektur: R0, RL oder RR erwartet"
				d["r"] = "R0"
			"RL", "RR":
				if circ or ns != "":
					return "Radiuskorrektur: R0, RL oder RR erwartet"
				d["r"] = w
			"F":
				var v: Variant = _num(ns)
				if v == null or float(v) <= 0.0:
					return "Vorschub F fehlt oder ist ungültig"
				d["f"] = float(v)
			"FMAX":
				if circ:
					return "FMAX beim Kreis nicht möglich"
				d["fmax"] = true
			"M":
				if not ns.is_valid_int():
					return "M-Funktion ohne Nummer"
				ms.append(int(ns))
			"DR":
				if not circ or (ns != "+" and ns != "-"):
					return "Drehsinn DR+ oder DR- erwartet"
				d["dr"] = 1 if ns == "+" else -1
			_:
				return "Unbekanntes Wort '%s'" % (w + ns)
	d["m"] = ms
	return ""


## Eine Programmzeile lesen. Ergebnis {"type": ...} (siehe Kopf der Datei / format_block).
static func parse_line(text: String) -> Dictionary:
	_init_re()
	var s := text
	var ci := s.find(";")
	var comment := ""
	if ci >= 0:
		comment = s.substr(ci + 1).strip_edges()
		s = s.substr(0, ci)
	s = s.strip_edges()
	if s == "":
		if ci >= 0:
			return {"type": "comment", "text": comment}
		return {"type": "empty"}
	s = s.to_upper().replace("\t", " ").replace(",", ".")
	var sm := _re_satz.search(s)
	if sm != null:
		s = s.substr(sm.get_end()).strip_edges()
	var words := s.split(" ", false)
	if words.is_empty():
		return {"type": "empty"}
	var w0 := words[0]
	var rest := " ".join(words.slice(1))
	match w0:
		"BEGIN", "END":
			if words.size() < 3 or words[1] != "PGM":
				return _err("%s PGM <NAME> MM erwartet" % w0)
			if words.size() > 3 and words[3] == "INCH":
				return _err("Nur Millimeter (MM) wird unterstützt")
			return {"type": w0.to_lower(), "name": words[2]}
		"BLK":
			if words.size() < 3 or words[1] != "FORM":
				return _err("BLK FORM 0.1 oder 0.2 erwartet")
			var idx := 1 if words[2] == "0.1" else (2 if words[2] == "0.2" else 0)
			if idx == 0:
				return _err("BLK FORM 0.1 oder 0.2 erwartet")
			var sc := _scan(" ".join(words.slice(3)))
			if sc.has("err"):
				return _err(str(sc["err"]))
			var d := {"type": "blk_form", "idx": idx}
			for t in sc["toks"]:
				var w: String = t[0]
				if w == "Z" and t[1] == "":
					continue
				if w != "X" and w != "Y" and w != "Z":
					return _err("Unbekanntes Wort '%s'" % (w + t[1]))
				var v: Variant = _num(t[1])
				if v == null:
					return _err("Zahl bei %s fehlt oder ist ungültig" % w)
				d[w.to_lower()] = float(v)
			if not (d.has("x") and d.has("y") and d.has("z")):
				return _err("BLK FORM braucht X, Y und Z")
			return d
		"TOOL":
			if words.size() < 3 or words[1] != "CALL" or not words[2].is_valid_int():
				return _err("TOOL CALL <T> Z S<Drehzahl> erwartet")
			var d := {"type": "tool_call", "t": int(words[2]), "s": 0.0}
			var sc := _scan(" ".join(words.slice(3)))
			if sc.has("err"):
				return _err(str(sc["err"]))
			for t in sc["toks"]:
				var w: String = t[0]
				if w == "Z" and t[1] == "":
					continue
				if w != "S" and w != "F":
					return _err("Unbekanntes Wort '%s'" % (w + t[1]))
				var v: Variant = _num(t[1])
				if v == null:
					return _err("Zahl bei %s fehlt oder ist ungültig" % w)
				d[w.to_lower()] = float(v)
			return d
		"L":
			var d := {"type": "l"}
			var e := _parse_motion(rest, d, false)
			if e != "":
				return _err(e)
			return d
		"CC":
			var sc := _scan(rest)
			if sc.has("err"):
				return _err(str(sc["err"]))
			var d := {"type": "cc"}
			for t in sc["toks"]:
				var w: String = t[0]
				if w != "X" and w != "Y":
					return _err("Unbekanntes Wort '%s'" % (w + t[1]))
				var v: Variant = _num(t[1])
				if v == null:
					return _err("Zahl bei %s fehlt oder ist ungültig" % w)
				d[w.to_lower()] = float(v)
			if not (d.has("x") and d.has("y")):
				return _err("CC braucht X und Y")
			return d
		"C":
			var d := {"type": "c"}
			var e := _parse_motion(rest, d, true)
			if e != "":
				return _err(e)
			if not d.has("dr"):
				return _err("Drehsinn DR+ oder DR- fehlt")
			return d
		"CYCL":
			return _parse_cycl(words)
		"STOP":
			return {"type": "stop"}
		"LBL":
			if words.size() < 2 or not words[1].is_valid_int() or int(words[1]) < 0:
				return _err("LBL <Nummer> erwartet")
			return {"type": "lbl", "n": int(words[1])}
		"CALL":
			if words.size() < 3 or words[1] != "LBL" or not words[2].is_valid_int() or int(words[2]) < 0:
				return _err("CALL LBL <Nummer> [REP <Anzahl>] erwartet")
			var rep := 0
			if words.size() > 3:
				var rs := ""
				if words[3] == "REP" and words.size() > 4:
					rs = words[4]
				elif words[3].begins_with("REP"):
					rs = words[3].substr(3)
				if not rs.is_valid_int() or int(rs) < 0:
					return _err("REP <Anzahl> erwartet")
				rep = int(rs)
			return {"type": "call_lbl", "n": int(words[2]), "rep": rep}
	# Alleinstehende M-Funktionen
	var sc := _scan(s)
	if not sc.has("err") and not sc["toks"].is_empty():
		var ms: Array = []
		for t in sc["toks"]:
			if t[0] != "M" or not str(t[1]).is_valid_int():
				ms = []
				break
			ms.append(int(t[1]))
		if not ms.is_empty():
			return {"type": "m", "m": ms}
	return _err("Satz nicht verständlich: %s" % s)


static func _parse_cycl(words: PackedStringArray) -> Dictionary:
	if words.size() < 2:
		return _err("CYCL DEF oder CYCL CALL erwartet")
	if words[1] == "CALL":
		var sc := _scan(" ".join(words.slice(2)))
		if sc.has("err"):
			return _err(str(sc["err"]))
		var ms: Array = []
		for t in sc["toks"]:
			if t[0] != "M" or not str(t[1]).is_valid_int():
				return _err("Nach CYCL CALL sind nur M-Funktionen erlaubt")
			ms.append(int(t[1]))
		return {"type": "cycl_call", "m": ms}
	if words[1] != "DEF" or words.size() < 3 or not words[2].is_valid_int():
		return _err("CYCL DEF <Nummer> erwartet")
	var qi := words.size()
	for i in range(3, words.size()):
		if words[i].length() > 1 and words[i][0] == "Q" and words[i].substr(1, 1).is_valid_int():
			qi = i
			break
	var name := " ".join(words.slice(3, qi))
	var qs := " ".join(words.slice(qi))
	var q := {}
	var found := 0
	for m in _re_q.search_all(qs):
		q[int(m.get_string(1))] = m.get_string(2).to_float()
		found += 1
	if found != qs.count("="):
		return _err("Q-Parameter nicht lesbar (Q<Nr>=<Wert> erwartet)")
	return {"type": "cycl_def", "cycle": int(words[2]), "name": name, "q": q}


static func _axes_text(b: Dictionary, axes: String) -> Array:
	var parts: Array = []
	for i in axes.length():
		var k := axes[i].to_lower()
		if b.has(k):
			parts.append(("I" if b.get("i" + k, false) else "") + k.to_upper() + fmt(float(b[k])))
	return parts


## Gegenstück zu parse_line: sauberer Klartext aus einem Satz-Dictionary.
static func format_block(b: Dictionary) -> String:
	var parts: Array = []
	match str(b.get("type", "")):
		"comment":
			return "; " + str(b.get("text", ""))
		"begin":
			return "BEGIN PGM %s MM" % str(b.get("name", ""))
		"end":
			return "END PGM %s MM" % str(b.get("name", ""))
		"blk_form":
			var p := _axes_text(b, "XYZ")
			if int(b.get("idx", 1)) == 1:
				return "BLK FORM 0.1 Z " + " ".join(p)
			return "BLK FORM 0.2 " + " ".join(p)
		"tool_call":
			var s := "TOOL CALL %d Z S%s" % [int(b.get("t", 0)), _plain(float(b.get("s", 0.0)))]
			if b.has("f"):
				s += " F" + _plain(float(b["f"]))
			return s
		"l":
			parts = ["L"] + _axes_text(b, "XYZ")
			if b.has("r"):
				parts.append(str(b["r"]))
			if b.get("fmax", false):
				parts.append("FMAX")
			elif b.has("f"):
				parts.append("F" + _plain(float(b["f"])))
			for m in b.get("m", []):
				parts.append("M%d" % int(m))
			return " ".join(parts)
		"cc":
			return " ".join(["CC"] + _axes_text(b, "XY"))
		"c":
			parts = ["C"] + _axes_text(b, "XY")
			parts.append("DR+" if int(b.get("dr", 1)) >= 0 else "DR-")
			if b.has("f"):
				parts.append("F" + _plain(float(b["f"])))
			for m in b.get("m", []):
				parts.append("M%d" % int(m))
			return " ".join(parts)
		"cycl_def":
			var no := int(b.get("cycle", 0))
			parts = ["CYCL DEF %d" % no]
			if str(b.get("name", "")) != "":
				parts.append(str(b["name"]))
			var q: Dictionary = b.get("q", {})
			var done := {}
			if CYCLES.has(no):
				for e in CYCLES[no]["q"]:
					if q.has(int(e[0])):
						parts.append("Q%d=%s" % [int(e[0]), fmt(float(q[int(e[0])]))])
						done[int(e[0])] = true
			var rest_keys := q.keys()
			rest_keys.sort()
			for k in rest_keys:
				if not done.has(int(k)):
					parts.append("Q%d=%s" % [int(k), fmt(float(q[k]))])
			return " ".join(parts)
		"cycl_call":
			parts = ["CYCL CALL"]
			for m in b.get("m", []):
				parts.append("M%d" % int(m))
			return " ".join(parts)
		"m":
			for m in b.get("m", []):
				parts.append("M%d" % int(m))
			return " ".join(parts)
		"stop":
			return "STOP"
		"lbl":
			return "LBL %d" % int(b.get("n", 0))
		"call_lbl":
			var s := "CALL LBL %d" % int(b.get("n", 0))
			if int(b.get("rep", 0)) > 0:
				s += " REP %d" % int(b["rep"])
			return s
	return ""


## Programm übersetzen. ctx (alles optional): "tools" {T-Nr -> Werkzeug}, "pos" Vector3, "t" int,
## "limits" {"min": Vector3, "max": Vector3}. Rückgabe siehe Kopf: name, ops, errs, blk, time, tools.
static func compile(lines: Array, ctx: Dictionary = {}) -> Dictionary:
	_init_re()
	var run := _Run.new()
	if ctx.has("tools"):
		run.has_tools = true
		run.tools = ctx["tools"]
	if ctx.has("limits"):
		run.limits = ctx["limits"]
	if ctx.has("pos"):
		run.pos = ctx["pos"]
	run.t = int(ctx.get("t", 0))
	if run.t > 0:
		run.tl = run.tool_dict(run.t)
		run.s_set = float(ctx.get("s", 1000.0))  # Solldrehzahl des eingespannten Werkzeugs
	var blocks: Array = []
	var labels := {}
	var first_real := -1
	var end_idx := -1
	var name := ""
	var bmin := Vector3.ZERO
	var bmax := Vector3.ZERO
	var got1 := false
	var got2 := false
	for i in lines.size():
		var b := parse_line(str(lines[i]))
		blocks.append(b)
		var ty := str(b["type"])
		if ty == "error":
			run.n = i
			run.err(str(b["err"]))
			continue
		if ty != "empty" and ty != "comment" and first_real < 0:
			first_real = i
			if ty != "begin":
				run.n = i
				run.err("BEGIN PGM fehlt")
		match ty:
			"begin":
				name = str(b["name"])
			"end":
				if end_idx < 0:
					end_idx = i
			"blk_form":
				var p := Vector3(b["x"], b["y"], b["z"])
				if int(b["idx"]) == 1:
					bmin = p
					got1 = true
				else:
					bmax = p
					got2 = true
			"lbl":
				var ln := int(b["n"])
				if ln > 0:
					if labels.has(ln):
						run.n = i
						run.err("LBL %d ist doppelt vergeben" % ln)
					else:
						labels[ln] = i
	if first_real < 0:
		run.n = 0
		run.err("BEGIN PGM fehlt")
	if end_idx < 0:
		run.n = maxi(0, lines.size() - 1)
		run.err("END PGM fehlt")
	var blk := {}
	if got1 and got2:
		blk = {"min": Vector3(minf(bmin.x, bmax.x), minf(bmin.y, bmax.y), minf(bmin.z, bmax.z)),
				"max": Vector3(maxf(bmin.x, bmax.x), maxf(bmin.y, bmax.y), maxf(bmin.z, bmax.z))}
	var last_n := run.execute(blocks, labels)
	run.finish(last_n)
	return {"name": name, "ops": run.ops, "errs": run.errs, "blk": blk, "time": run.time, "tools": run.used}


## Abtrag als grobe Höhenkarte. size = Rohteil (Länge X, Breite Y, Höhe), Ursprung vorne links oben.
## Rückgabe {"nx", "ny", "cell", "h"}: h je Zelle (Zeile j = Y, Spalte i = X), 0 = roh, negativ = abgetragen.
static func simulate(ops: Array, tools: Dictionary, size: Vector3, cell: float = 1.0) -> Dictionary:
	var cs := maxf(cell, 0.05)
	var nx := maxi(1, ceili(size.x / cs - 1e-6))
	var ny := maxi(1, ceili(size.y / cs - 1e-6))
	var h := PackedFloat32Array()
	h.resize(nx * ny)
	h.fill(0.0)
	var floor_z := -size.z
	var r := 5.0
	var have := false
	var p := Vector3.ZERO
	for op in ops:
		var kind := str(op["op"])
		if kind == "tool":
			var td: Variant = tools.get(int(op["t"]))
			r = float(td["d"]) * 0.5 if td is Dictionary else 5.0
		elif kind == "mv":
			var to: Vector3 = op["to"]
			if not have:
				have = true
				p = to
				if to.z < 0.0:
					_cut(h, nx, ny, cs, Vector2(to.x, to.y), Vector2(to.x, to.y), r, maxf(to.z, floor_z))
				continue
			var a2 := Vector2(p.x, p.y)
			var b2 := Vector2(to.x, to.y)
			if a2.distance_to(b2) < 1e-6:
				var zl := minf(p.z, to.z)
				if zl < 0.0:
					_cut(h, nx, ny, cs, b2, b2, r, maxf(zl, floor_z))
			else:
				var pieces := clampi(ceili(absf(to.z - p.z) / 0.5), 1, 200)
				for k in pieces:
					var t0 := float(k) / pieces
					var t1 := float(k + 1) / pieces
					var z0 := lerpf(p.z, to.z, t0)
					var z1 := lerpf(p.z, to.z, t1)
					var zl := minf(z0, z1)
					if zl < 0.0:
						_cut(h, nx, ny, cs, a2.lerp(b2, t0), a2.lerp(b2, t1), r, maxf(zl, floor_z))
			p = to
	return {"nx": nx, "ny": ny, "cell": cs, "h": h}


## Kapsel (Strecke a-b, Radius r) in die Höhenkarte schneiden.
static func _cut(h: PackedFloat32Array, nx: int, ny: int, cs: float, a: Vector2, b: Vector2, r: float, z: float) -> void:
	var i0 := maxi(0, floori((minf(a.x, b.x) - r) / cs))
	var i1 := mini(nx - 1, floori((maxf(a.x, b.x) + r) / cs))
	var j0 := maxi(0, floori((minf(a.y, b.y) - r) / cs))
	var j1 := mini(ny - 1, floori((maxf(a.y, b.y) + r) / cs))
	if i0 > i1 or j0 > j1:
		return
	var ab := b - a
	var l2 := ab.length_squared()
	var r2 := r * r
	for j in range(j0, j1 + 1):
		var cy := (j + 0.5) * cs
		for i in range(i0, i1 + 1):
			var cx := (i + 0.5) * cs
			var t := 0.0
			if l2 > 1e-12:
				t = clampf(((cx - a.x) * ab.x + (cy - a.y) * ab.y) / l2, 0.0, 1.0)
			var dx := cx - (a.x + ab.x * t)
			var dy := cy - (a.y + ab.y * t)
			if dx * dx + dy * dy <= r2:
				var idx := j * nx + i
				if z < h[idx]:
					h[idx] = z


## Ablauf des Programms (Interpreter beim Übersetzen: Schleifen und Unterprogramme laufen wirklich).
class _Run extends RefCounted:
	var ops: Array = []
	var errs: Array = []
	var used: Array = []
	var tools: Dictionary = {}
	var has_tools := false
	var limits: Dictionary = {}
	var n := 0
	var fail := false
	var stop_all := false
	var ended := false
	var pos := Vector3(0, 0, 100)
	var t := 0
	var tl: Dictionary = {}
	var s_set := 0.0
	var spindle := false
	var ccw := false
	var coolant := false
	var feed := 0.0
	var cc := Vector2.ZERO
	var has_cc := false
	var cyc_no := -1
	var cyc_q := {}
	var time := 0.0
	var moves := 0
	# Zyklus-Arbeitswerte
	var surf := 0.0
	var zs := 0.0
	var zs2 := 0.0
	var ap := 1.0
	var rad := 5.0
	var lc := Vector2.ZERO
	var lrot := 0

	func err(text: String) -> void:
		var e := "Satz %d: %s" % [n, text]
		if not errs.has(e):
			errs.append(e)
		if errs.size() >= 30:
			stop_all = true

	func tool_dict(tn: int) -> Dictionary:
		if has_tools:
			var d: Variant = tools.get(tn)
			if d is Dictionary:
				return d
			return {}
		return {"id": "T%d" % tn, "name": "Werkzeug %d" % tn, "kind": "end_mill", "d": 10.0, "z": 4}

	func blk() -> void:
		ops.append({"op": "blk", "n": n})

	# --- Bewegung ---
	func mv(to: Vector3, f: float, rapid: bool) -> void:
		if fail or stop_all:
			return
		if not rapid:
			if t == 0 or tl.is_empty():
				err("TOOL CALL fehlt")
				fail = true
				return
			if not spindle:
				err("Spindel dreht nicht: M3 fehlt")
				fail = true
				return
			if f <= 0.0:
				err("F fehlt (kein Vorschub programmiert)")
				fail = true
				return
		if not limits.is_empty():
			var lo: Vector3 = limits["min"]
			var hi: Vector3 = limits["max"]
			for i in 3:
				if to[i] < lo[i] - 1e-3:
					err("Endschalter %s-" % "XYZ"[i])
					fail = true
					return
				if to[i] > hi[i] + 1e-3:
					err("Endschalter %s+" % "XYZ"[i])
					fail = true
					return
		var d := pos.distance_to(to)
		if d < 1e-6:
			return
		moves += 1
		if moves > MillNc.MAX_MOVES:
			err("Programm läuft endlos (mehr als %d Bewegungen)" % MillNc.MAX_MOVES)
			stop_all = true
			fail = true
			return
		var sp := MillNc.RAPID if rapid else f
		time += d / sp * 60.0
		ops.append({"op": "mv", "to": to, "f": sp, "rapid": rapid, "n": n})
		pos = to

	func dwell(sec: float) -> void:
		if sec > 0.0 and not fail:
			ops.append({"op": "dwell", "t": sec, "n": n})
			time += sec

	func set_spindle(on: bool, left: bool) -> void:
		spindle = on
		ccw = left
		ops.append({"op": "spindle", "on": on, "ccw": left, "n": n})

	func set_coolant(on: bool) -> void:
		coolant = on
		ops.append({"op": "coolant", "on": on, "n": n})

	# --- M-Funktionen ---
	func check_m(ms: Array) -> bool:
		for m in ms:
			if not MillNc.M_CODES.has(int(m)):
				err("M%d wird nicht unterstützt" % int(m))
				return false
		return true

	func m_start(ms: Array) -> void:
		for m in ms:
			var c := int(m)
			match c:
				3, 4, 13, 14:
					if s_set <= 0.0:
						err("Spindel ohne Drehzahl: TOOL CALL fehlt")
						fail = true
						return
					set_spindle(true, c == 4 or c == 14)
					if c >= 13:
						set_coolant(true)
				8:
					set_coolant(true)

	func m_end(ms: Array) -> void:
		for m in ms:
			match int(m):
				5:
					set_spindle(false, ccw)
				9:
					set_coolant(false)
				0:
					ops.append({"op": "stop", "n": n})
				2, 30:
					ended = true
				99:
					run_cycle()
					if fail:
						return

	# --- Sätze ---
	func do_tool(b: Dictionary) -> void:
		var tn := int(b["t"])
		if tn <= 0:
			err("TOOL CALL %d: Werkzeug 0 gibt es nicht" % tn)
			return
		if has_tools and not tools.has(tn):
			err("Werkzeug T%d ist nicht im Magazin" % tn)
			return
		var s: float = b.get("s", 0.0)
		if s <= 0.0 or s > MillNc.S_MAX:
			err("Drehzahl S%s ungültig (1 bis %d)" % [MillNc._plain(s), int(MillNc.S_MAX)])
			return
		if spindle:
			set_spindle(false, ccw)
		t = tn
		tl = tool_dict(tn)
		s_set = s
		if b.has("f"):
			feed = b["f"]
		if not used.has(tn):
			used.append(tn)
		time += MillNc.TOOL_CHANGE_TIME
		ops.append({"op": "tool", "t": tn, "s": s, "n": n})

	func do_line(b: Dictionary) -> void:
		if b.has("r") and str(b["r"]) != "R0":
			err("Radiuskorrektur RL/RR wird noch nicht unterstützt, mit R0 programmieren")
			return
		var ms: Array = b.get("m", [])
		if not check_m(ms):
			return
		m_start(ms)
		if fail:
			return
		var tgt := pos
		for i in 3:
			var k: String = "xyz"[i]
			if b.has(k):
				var v: float = b[k]
				tgt[i] = (pos[i] + v) if b.get("i" + k, false) else v
		if b.has("f"):
			feed = b["f"]
		mv(tgt, feed, bool(b.get("fmax", false)))
		if fail:
			return
		m_end(ms)

	func do_arc(b: Dictionary) -> void:
		if not has_cc:
			err("C ohne CC: Kreismittelpunkt fehlt")
			return
		var ms: Array = b.get("m", [])
		if not check_m(ms):
			return
		m_start(ms)
		if fail:
			return
		var ex := pos.x
		var ey := pos.y
		if b.has("x"):
			ex = (pos.x + float(b["x"])) if b.get("ix", false) else float(b["x"])
		if b.has("y"):
			ey = (pos.y + float(b["y"])) if b.get("iy", false) else float(b["y"])
		var sv := Vector2(pos.x, pos.y) - cc
		var ev := Vector2(ex, ey) - cc
		var r0 := sv.length()
		var r1 := ev.length()
		if r0 < 1e-6:
			err("Kreisradius ist 0")
			return
		if absf(r0 - r1) > 0.01:
			err("Kreisendpunkt liegt nicht auf dem Kreis (Abweichung %.3f mm)" % absf(r0 - r1))
			return
		if b.has("f"):
			feed = b["f"]
		var left: bool = int(b["dr"]) > 0
		var a0 := sv.angle()
		var a1 := ev.angle()
		var da := 0.0
		if Vector2(ex, ey).distance_to(Vector2(pos.x, pos.y)) < 0.005:
			da = TAU if left else -TAU
		elif left:
			da = fposmod(a1 - a0, TAU)
		else:
			da = -fposmod(a0 - a1, TAU)
		var dth := 2.0 * acos(clampf(1.0 - MillNc.ARC_SAG / r0, -1.0, 1.0))
		dth = maxf(dth, 0.02)
		var nseg := maxi(1, ceili(absf(da) / dth))
		var z := pos.z
		for i in range(1, nseg + 1):
			var qp := Vector2(ex, ey)
			if i < nseg:
				var fr := float(i) / nseg
				qp = cc + Vector2.from_angle(a0 + da * fr) * lerpf(r0, r1, fr)
			mv(Vector3(qp.x, qp.y, z), feed, false)
			if fail or stop_all:
				return
		m_end(ms)

	func def_cycle(b: Dictionary) -> void:
		var no := int(b["cycle"])
		if not MillNc.CYCLES.has(no):
			err("Unbekannte Zyklusnummer %d" % no)
			return
		cyc_no = no
		cyc_q = (b["q"] as Dictionary).duplicate()

	func do_cycl_call(b: Dictionary) -> void:
		var ms: Array = b.get("m", [])
		if not check_m(ms):
			return
		if cyc_no < 0:
			err("Zyklusaufruf ohne CYCL DEF")
			fail = true
			return
		m_start(ms)
		if fail:
			return
		run_cycle()
		if fail:
			return
		m_end(ms)

	## Das ganze Programm abarbeiten. Rückgabe: Satz, bei dem das Programm endete.
	func execute(blocks: Array, labels: Dictionary) -> int:
		var pc := 0
		var steps := 0
		var cstack: Array = []
		var reps := {}
		n = 0
		while pc < blocks.size() and not stop_all and not ended:
			steps += 1
			n = pc
			if steps > MillNc.MAX_STEPS:
				err("Programm läuft endlos (Schleife ohne Ende)")
				stop_all = true
				break
			var b: Dictionary = blocks[pc]
			var next := pc + 1
			fail = false
			match str(b["type"]):
				"tool_call":
					blk()
					do_tool(b)
				"l":
					blk()
					do_line(b)
				"c":
					blk()
					do_arc(b)
				"cc":
					cc = Vector2(b["x"], b["y"])
					has_cc = true
				"cycl_def":
					def_cycle(b)
				"cycl_call":
					blk()
					do_cycl_call(b)
				"m":
					blk()
					var ms: Array = b["m"]
					if check_m(ms):
						m_start(ms)
						if not fail:
							m_end(ms)
				"stop":
					blk()
					ops.append({"op": "stop", "n": n})
				"end":
					ended = true
				"lbl":
					if int(b["n"]) == 0:
						if cstack.is_empty():
							err("LBL 0 ohne Unterprogramm-Aufruf")
							stop_all = true
						else:
							var fr: Dictionary = cstack.back()
							if int(fr["rem"]) > 0:
								fr["rem"] = int(fr["rem"]) - 1
								next = int(fr["start"])
							else:
								cstack.pop_back()
								next = int(fr["ret"])
				"call_lbl":
					var ln := int(b["n"])
					if not labels.has(ln):
						err("LBL %d nicht gefunden" % ln)
						stop_all = true
					else:
						var lp := int(labels[ln])
						var rep := int(b.get("rep", 0))
						if lp < pc and rep > 0:
							var left := int(reps.get(pc, rep))
							if left > 0:
								reps[pc] = left - 1
								next = lp + 1
							else:
								reps.erase(pc)
						elif cstack.size() >= MillNc.MAX_DEPTH:
							err("Unterprogramme zu tief geschachtelt (höchstens %d)" % MillNc.MAX_DEPTH)
							stop_all = true
						else:
							cstack.append({"ret": pc + 1, "start": lp + 1, "rem": rep})
							next = lp + 1
			pc = next
		return n

	func finish(last_n: int) -> void:
		n = last_n
		if spindle:
			set_spindle(false, ccw)
		if coolant:
			set_coolant(false)
		if errs.is_empty():
			ops.append({"op": "end", "n": n})

	# --- Zyklen ---
	func q(id: int) -> float:
		if cyc_q.has(id):
			return float(cyc_q[id])
		return MillNc.q_default(cyc_no, id)

	func bad(text: String) -> void:
		err(text)
		fail = true

	func run_cycle() -> void:
		if cyc_no < 0:
			bad("Zyklusaufruf ohne CYCL DEF")
			return
		if tl.is_empty():
			bad("TOOL CALL fehlt")
			return
		rad = float(tl.get("d", 10.0)) * 0.5
		if cyc_no != 200 and str(tl.get("kind", "end_mill")) == "drill":
			bad("Zyklus %d ist mit einem Bohrer nicht möglich" % cyc_no)
			return
		surf = q(227) if cyc_no == 233 else q(203)
		if cyc_no != 233 and q(201) >= 0.0:
			bad("Tiefe Q201 muss negativ sein")
			return
		if q(202) <= 0.0:
			bad("Zustell-Tiefe Q202 muss größer 0 sein")
			return
		if cyc_no != 233 and q(206) <= 0.0:
			bad("Vorschub Tiefenzustellung Q206 fehlt")
			return
		if cyc_no != 200 and q(207) <= 0.0:
			bad("Vorschub Fräsen Q207 fehlt")
			return
		ap = maxf(q(202), 0.01)
		zs = surf + q(200)
		zs2 = surf + maxf(q(200), q(204))
		match cyc_no:
			200:
				cyc_drill()
			233:
				cyc_face()
			251:
				cyc_rect()
			252:
				cyc_round()
			253:
				cyc_slot()
			_:
				bad("Unbekannte Zyklusnummer %d" % cyc_no)

	## Erst auf den 2. Sicherheitsabstand hochfahren, wenn die Spindel tiefer steht.
	func cyc_up() -> void:
		if pos.z < zs2 - 1e-6:
			mv(Vector3(pos.x, pos.y, zs2), MillNc.RAPID, true)

	func cyc_end() -> void:
		mv(Vector3(pos.x, pos.y, zs), MillNc.RAPID, true)
		mv(Vector3(pos.x, pos.y, zs2), MillNc.RAPID, true)

	func depths(zend: float) -> Array:
		var out: Array = []
		var zd := surf
		while zd > zend + 1e-6 and out.size() < 5000:
			zd = maxf(zend, zd - ap)
			out.append(zd)
		return out

	func cyc_drill() -> void:
		var zend := surf + q(201)
		var f := q(206)
		cyc_up()
		mv(Vector3(pos.x, pos.y, zs), MillNc.RAPID, true)
		var zprev := surf
		var first := true
		while not fail and not stop_all:
			var zd := maxf(zend, zprev - ap)
			if not first:
				mv(Vector3(pos.x, pos.y, minf(zs, zprev + 0.6)), MillNc.RAPID, true)
			first = false
			mv(Vector3(pos.x, pos.y, zd), f, false)
			if zd <= zend + 1e-6:
				break
			mv(Vector3(pos.x, pos.y, zs), MillNc.RAPID, true)
			dwell(q(210))
			zprev = zd
		dwell(q(211))
		if not fail:
			cyc_end()

	# lokales Koordinatensystem der Tasche: (u, v) um lc, lrot = 0 oder 90 Grad gedreht
	func lw(u: float, v: float) -> Vector2:
		if lrot == 90:
			return Vector2(lc.x - v, lc.y + u)
		return Vector2(lc.x + u, lc.y + v)

	func lmv(u: float, v: float, z: float, f: float) -> void:
		var p := lw(u, v)
		mv(Vector3(p.x, p.y, z), f, false)

	func larc(u0: float, v0: float, r: float, a0: float, da: float, z: float, f: float) -> void:
		if r <= 0.0:
			return
		var dth := maxf(2.0 * acos(clampf(1.0 - MillNc.ARC_SAG / r, -1.0, 1.0)), 0.05)
		var nseg := maxi(1, ceili(absf(da) / dth))
		for i in range(1, nseg + 1):
			var a := a0 + da * float(i) / nseg
			lmv(u0 + r * cos(a), v0 + r * sin(a), z, f)

	## Auf den Startpunkt (su, sv) der Stufe fahren und mit Q206 eintauchen.
	func plunge_start(su: float, sv: float, zprev: float, zd: float, first: bool) -> void:
		var p := lw(su, sv)
		if first:
			cyc_up()
			mv(Vector3(p.x, p.y, pos.z), MillNc.RAPID, true)
			mv(Vector3(p.x, p.y, zs), MillNc.RAPID, true)
		else:
			mv(Vector3(pos.x, pos.y, zs), MillNc.RAPID, true)
			mv(Vector3(p.x, p.y, zs), MillNc.RAPID, true)
			mv(Vector3(p.x, p.y, minf(zs, zprev + 0.5)), MillNc.RAPID, true)
		mv(Vector3(p.x, p.y, zd), q(206), false)

	func step_over() -> float:
		return maxf(clampf(q(370), 0.1, 1.9) * rad, 0.05)

	func cyc_rect() -> void:
		var lx := q(218)
		var ly := q(219)
		if lx <= 0.0 or ly <= 0.0:
			bad("Seitenlängen Q218/Q219 müssen größer 0 sein")
			return
		if absf(q(224)) > 1e-9:
			bad("Taschen-Drehlage Q224 wird nicht unterstützt")
			return
		if q(367) != 0.0 and q(367) != 1.0:
			bad("Taschenlage Q367: 0 (Mitte) oder 1 (Ecke) erwartet")
			return
		if rad * 2.0 > minf(lx, ly) + 1e-6:
			bad("Werkzeug-Radius zu groß")
			return
		lc = Vector2(pos.x, pos.y)
		if q(367) == 1.0:
			lc += Vector2(lx * 0.5, ly * 0.5)
		lrot = 0
		var hx := lx * 0.5 - rad
		var hy := ly * 0.5 - rad
		# Rechteckbahnen: ab 1,7 · R blieben in den Ecken zwischen zwei Bahnen Reste stehen
		var st := minf(step_over(), rad * 1.7)
		var hm := maxf(hx, hy)
		var nr := ceili(hm / st - 1e-6) if hm > 1e-6 else 0
		var f7 := q(207)
		var zprev := surf
		var first := true
		for zd in depths(surf + q(201)):
			plunge_start(0.0, 0.0, zprev, zd, first)
			first = false
			for k in range(1, nr + 1):
				var a := minf(hx, k * st)
				var b := minf(hy, k * st)
				lmv(-a, -b, zd, f7)
				lmv(a, -b, zd, f7)
				lmv(a, b, zd, f7)
				lmv(-a, b, zd, f7)
				lmv(-a, -b, zd, f7)
			zprev = zd
			if fail or stop_all:
				return
		cyc_end()

	func cyc_round() -> void:
		var d := q(223)
		if d <= 0.0:
			bad("Kreisdurchmesser Q223 muss größer 0 sein")
			return
		if rad * 2.0 > d + 1e-6:
			bad("Werkzeug-Radius zu groß")
			return
		lc = Vector2(pos.x, pos.y)
		lrot = 0
		var rmax := d * 0.5 - rad
		var st := step_over()
		var nr := ceili(rmax / st - 1e-6) if rmax > 1e-6 else 0
		var f7 := q(207)
		var zprev := surf
		var first := true
		for zd in depths(surf + q(201)):
			plunge_start(0.0, 0.0, zprev, zd, first)
			first = false
			for k in range(1, nr + 1):
				var rr := minf(rmax, k * st)
				lmv(rr, 0.0, zd, f7)
				larc(0.0, 0.0, rr, 0.0, TAU, zd, f7)
			zprev = zd
			if fail or stop_all:
				return
		cyc_end()

	func cyc_slot() -> void:
		var sl := q(218)
		var sw := q(219)
		var rot := int(roundf(q(374)))
		if rot != 0 and rot != 90:
			bad("Drehlage Q374: nur 0 oder 90 möglich")
			return
		if q(367) != 0.0:
			bad("Nutlage Q367: nur 0 (Mitte) wird unterstützt")
			return
		if sl <= 0.0 or sw <= 0.0:
			bad("Nutlänge und Nutbreite müssen größer 0 sein")
			return
		if rad * 2.0 > sw + 1e-6:
			bad("Werkzeug-Radius zu groß")
			return
		if sl < sw - 1e-6:
			bad("Nutlänge ist kleiner als die Nutbreite")
			return
		lc = Vector2(pos.x, pos.y)
		lrot = rot
		var hc := sl * 0.5 - sw * 0.5
		var rr := sw * 0.5 - rad
		var f7 := q(207)
		var f6 := q(206)
		var zprev := surf
		var first := true
		if rr < 1e-6:
			# Pendelbahn: am Nutende eintauchen, zum anderen Ende fräsen, dort weiter eintauchen
			var cu := -hc
			for zd in depths(surf + q(201)):
				if first:
					plunge_start(cu, 0.0, zprev, zd, true)
				else:
					lmv(cu, 0.0, zd, f6)
				first = false
				cu = -cu
				lmv(cu, 0.0, zd, f7)
				if fail or stop_all:
					return
			cyc_end()
			return
		var st := step_over()
		var nr := ceili(rr / st - 1e-6)
		for zd in depths(surf + q(201)):
			plunge_start(-hc, 0.0, zprev, zd, first)
			first = false
			lmv(hc, 0.0, zd, f7)
			for k in range(1, nr + 1):
				var r := minf(rr, k * st)
				lmv(hc, -r, zd, f7)
				larc(hc, 0.0, r, -PI * 0.5, PI, zd, f7)
				lmv(-hc, r, zd, f7)
				larc(-hc, 0.0, r, PI * 0.5, PI, zd, f7)
				lmv(hc, -r, zd, f7)
			zprev = zd
			if fail or stop_all:
				return
		cyc_end()

	func cyc_face() -> void:
		var xa := q(225)
		var ya := q(226)
		var z0 := q(227)
		var z1 := q(386)
		var lx := absf(q(218))
		var ly := absf(q(219))
		if lx <= 0.0 or ly <= 0.0:
			bad("Seitenlängen Q218/Q219 dürfen nicht 0 sein")
			return
		if z1 >= z0 - 1e-6:
			bad("Endpunkt Q386 muss unter Q227 liegen")
			return
		var x0 := minf(xa, xa + q(218))
		var y0 := minf(ya, ya + q(219))
		var y1 := y0 + ly
		var x1 := x0 + lx
		var side := maxf(q(357), 0.0)
		var xs := x0 - rad - side
		var xe := x1 + rad + side
		var st := step_over()
		var rows: Array = []
		if ly <= rad * 2.0 + 1e-6:
			rows.append((y0 + y1) * 0.5)
		else:
			var ya2 := y0 + rad
			var yb2 := y1 - rad
			var nrow := maxi(1, ceili((yb2 - ya2) / st - 1e-6))
			for i in range(nrow + 1):
				rows.append(ya2 + (yb2 - ya2) * float(i) / nrow)
		var pre := q(253)
		var pre_rapid := pre <= 0.0
		var pre_f := MillNc.RAPID if pre_rapid else pre
		var f7 := q(207)
		var nlev := maxi(1, ceili((z0 - z1) / ap - 1e-6))
		cyc_up()
		var at_start := true
		for lev in nlev:
			var zd := z0 - (z0 - z1) * float(lev + 1) / nlev
			var lrows := rows.duplicate()
			if lev % 2 == 1:
				lrows.reverse()
			for i in lrows.size():
				var y: float = lrows[i]
				var xfrom := xs if at_start else xe
				var xto := xe if at_start else xs
				if lev == 0 and i == 0:
					mv(Vector3(xfrom, y, pos.z), MillNc.RAPID, true)
					mv(Vector3(xfrom, y, zs), MillNc.RAPID, true)
					mv(Vector3(xfrom, y, zd), pre_f, pre_rapid)
				elif i == 0:
					mv(Vector3(pos.x, pos.y, zd), pre_f, pre_rapid)
				else:
					mv(Vector3(xfrom, y, zd), f7, false)
				mv(Vector3(xto, y, zd), f7, false)
				at_start = not at_start
				if fail or stop_all:
					return
		cyc_end()
