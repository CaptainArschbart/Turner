class_name TncDialog
extends RefCounted
## Satz-Dialog der Steuerung (TncScreen): wie an der TNC wird je Eingabe eine Dialogfrage gestellt
## ("KOORDINATEN? X", "VORSCHUB F=? / FMAX", bei Zyklen jeder Q-Parameter mit Dialogtext und Standardwert).
## Reine Logik ohne Oberfläche. Der Satz entsteht als Dictionary im Format von MillNc.parse_line und wird mit
## MillNc.format_block zu Text.
##
## Ablauf: TncDialog.make("l") -> prompt() / default_text() anzeigen -> answer(text) oder choose(i) oder skip()
## (NO ENT) -> bis finished. finish() (ENDE) beendet vorzeitig, wenn alles Übrige optional ist oder einen
## Standardwert hat. lines() liefert den Klartext (ein Satz, bei "blk2" die beiden BLK-FORM-Sätze).
## Satzarten (kind): l, cc, c, tool_call, cycl_def, cycl_call, m, lbl, call_lbl, blk_form, blk2, comment, begin, stop.
## Mit base (vorhandener Satz) werden die Felder mit den bisherigen Werten vorbelegt (Satz im Dialog ändern).

const KINDS := ["l", "cc", "c", "tool_call", "cycl_def", "cycl_call", "m", "lbl", "call_lbl", "blk_form", "blk2", "comment", "begin", "stop"]

var kind := ""
var cycle := 0
var editing := false
var steps: Array = []
var blocks: Array = []
var i := 0
var finished := false


## ctx (optional): "cycle" (Zyklusnummer), "t" (vorgeschlagene T-Nummer), "s" (Drehzahl), "block" Vector3 (Rohteil
## Länge, Breite, Höhe für BLK FORM), "pockets" (Magazinplätze), "name" (Programmname).
static func make(block_kind: String, base: Dictionary = {}, ctx: Dictionary = {}) -> TncDialog:
	var d := TncDialog.new()
	d.kind = block_kind
	d.editing = not base.is_empty()
	d.cycle = int(ctx.get("cycle", base.get("cycle", 0)))
	d._build(base, ctx)
	if d.steps.is_empty():
		d.finished = true
	return d


## Art eines vorhandenen Satzes (parse_line-Typ) als Dialogart; "" = nicht im Dialog änderbar.
static func kind_of(block: Dictionary) -> String:
	var t := str(block.get("type", ""))
	if t == "cycl_def" and not MillNc.CYCLES.has(int(block.get("cycle", 0))):
		return ""
	return t if KINDS.has(t) else ""


func _build(base: Dictionary, ctx: Dictionary) -> void:
	if kind == "blk2":
		blocks = [{"type": "blk_form", "idx": 1}, {"type": "blk_form", "idx": 2}]
	elif editing:
		blocks = [base.duplicate(true)]
	else:
		blocks = [{"type": kind}]
		if kind == "blk_form":
			blocks[0]["idx"] = 1
	var blk: Vector3 = ctx.get("block", Vector3(100, 60, 40))
	var coords := "XYZ"
	match kind:
		"l":
			for a in 3:
				steps.append(_num(coords[a].to_lower(), "KOORDINATEN? " + coords[a], true, true))
			steps.append({"id": "r", "key": "r", "kind": "choice", "opt": true, "prompt": "RADIUSKORR.: RL/RR/KEINE KORR.?",
				"choices": [["RL", "RL"], ["RR", "RR"], ["KEINE KORR.", "R0"]]})
			steps.append({"id": "f", "key": "f", "kind": "feed", "opt": true, "prompt": "VORSCHUB F=? / FMAX"})
			steps.append({"id": "m", "key": "m", "kind": "mlist", "opt": true, "prompt": "ZUSATZ-FUNKTION M?"})
		"c":
			steps.append(_num("x", "KREISENDPUNKT? X", true, true))
			steps.append(_num("y", "KREISENDPUNKT? Y", true, true))
			steps.append({"id": "dr", "key": "dr", "kind": "choice", "opt": false, "prompt": "DREHSINN: DR+ / DR-?",
				"choices": [["DR+", 1], ["DR-", -1]], "def": 1})
			steps.append({"id": "f", "key": "f", "kind": "feed", "opt": true, "prompt": "VORSCHUB F=?", "nofmax": true})
			steps.append({"id": "m", "key": "m", "kind": "mlist", "opt": true, "prompt": "ZUSATZ-FUNKTION M?"})
		"cc":
			steps.append(_num("x", "KREISMITTELPUNKT CC? X", false, false))
			steps.append(_num("y", "KREISMITTELPUNKT CC? Y", false, false))
		"tool_call":
			steps.append({"id": "t", "key": "t", "kind": "int", "opt": false, "prompt": "WERKZEUG-NUMMER?", "def": int(ctx.get("t", 1)),
				"min": 1, "max": int(ctx.get("pockets", 24))})
			steps.append({"id": "s", "key": "s", "kind": "num", "opt": false, "prompt": "SPINDELDREHZAHL S=?", "def": float(ctx.get("s", 1000.0)),
				"min": 1.0, "max": MillNc.S_MAX})
			steps.append({"id": "f", "key": "f", "kind": "num", "opt": true, "prompt": "VORSCHUB F=?", "min": 1.0})
		"cycl_def":
			if not MillNc.CYCLES.has(cycle):
				return
			var cd: Dictionary = MillNc.CYCLES[cycle]
			if not editing:
				blocks[0]["cycle"] = cycle
				blocks[0]["name"] = str(cd["name"])
				blocks[0]["q"] = {}
			for q in cd["q"]:
				steps.append({"id": "q%d" % int(q[0]), "key": int(q[0]), "q": true, "kind": "num", "opt": false,
					"prompt": "Q%d  %s?" % [int(q[0]), str(q[1])], "def": float(q[2])})
		"cycl_call":
			steps.append({"id": "m", "key": "m", "kind": "mlist", "opt": true, "prompt": "ZUSATZ-FUNKTION M?"})
		"m":
			steps.append({"id": "m", "key": "m", "kind": "mlist", "opt": false, "prompt": "ZUSATZ-FUNKTION M?", "def": [3]})
		"lbl":
			steps.append({"id": "n", "key": "n", "kind": "int", "opt": false, "prompt": "LABEL-NUMMER?", "def": 1, "min": 1, "max": 999})
		"call_lbl":
			steps.append({"id": "n", "key": "n", "kind": "int", "opt": false, "prompt": "LABEL-NUMMER?", "def": 1, "min": 1, "max": 999})
			steps.append({"id": "rep", "key": "rep", "kind": "int", "opt": true, "prompt": "WIEDERHOLUNGEN REP?", "min": 1, "max": 9999})
		"blk_form", "blk2":
			var idxs: Array = [1, 2] if kind == "blk2" else [int(blocks[0].get("idx", 1))]
			for bi in idxs.size():
				var one: bool = int(idxs[bi]) == 1
				for a in 3:
					var dv := 0.0
					if a == 2:
						dv = -blk.z if one else 0.0
					elif not one:
						dv = blk.x if a == 0 else blk.y
					var s := _num(coords[a].to_lower(), "%s-PUNKT? %s" % ["MIN" if one else "MAX", coords[a]], false, false)
					s["def"] = dv
					s["blk"] = bi if kind == "blk2" else 0
					steps.append(s)
		"comment":
			steps.append({"id": "text", "key": "text", "kind": "text", "opt": false, "prompt": "KOMMENTAR?", "def": ""})
		"begin":
			steps.append({"id": "name", "key": "name", "kind": "text", "opt": false, "prompt": "PROGRAMMNAME?", "def": str(ctx.get("name", "NEU"))})
	if steps.is_empty():
		finished = true


func _num(key: String, prompt: String, opt: bool, inc: bool) -> Dictionary:
	return {"id": key, "key": key, "kind": "num", "opt": opt, "inc": inc, "prompt": prompt}


# ======================================================================= Abfrage des Zustands

func step() -> Dictionary:
	return steps[mini(i, steps.size() - 1)] if not steps.is_empty() else {}


func title() -> String:
	match kind:
		"l":
			return "L"
		"cc":
			return "CC"
		"c":
			return "C"
		"tool_call":
			return "TOOL CALL"
		"cycl_def":
			return "CYCL DEF %d %s" % [cycle, str(MillNc.CYCLES.get(cycle, {}).get("name", ""))]
		"cycl_call":
			return "CYCL CALL"
		"m":
			return "M"
		"lbl":
			return "LBL SET"
		"call_lbl":
			return "LBL CALL"
		"blk_form", "blk2":
			return "BLK FORM"
		"comment":
			return "KOMMENTAR"
		"begin":
			return "BEGIN PGM"
	return kind.to_upper()


func prompt() -> String:
	if finished or steps.is_empty():
		return ""
	return "%s   [%d/%d]   %s" % [title(), i + 1, steps.size(), str(step()["prompt"])]


func is_choice() -> bool:
	return not finished and not steps.is_empty() and str(step()["kind"]) == "choice"


func choices() -> Array:
	return step().get("choices", []) if is_choice() else []


func can_skip() -> bool:
	return not finished and not steps.is_empty() and bool(step().get("opt", false))


## Text, mit dem das Eingabefeld vorbelegt wird (bisheriger Wert oder Standardwert).
func default_text() -> String:
	if finished or steps.is_empty():
		return ""
	var s := step()
	var b: Dictionary = blocks[int(s.get("blk", 0))]
	var key = s["key"]
	match str(s["kind"]):
		"num":
			var src: Variant = null
			if s.get("q", false):
				src = (b.get("q", {}) as Dictionary).get(key, null)
			elif b.has(key):
				src = b[key]
			if src != null:
				return ("I" if s.get("inc", false) and b.get("i" + str(key), false) else "") + MillNc.fmt(float(src))
			return MillNc.fmt(float(s["def"])) if s.has("def") and s["def"] != null else ""
		"int":
			if b.has(key):
				return str(int(b[key]))
			return str(int(s["def"])) if s.has("def") else ""
		"feed":
			if b.get("fmax", false):
				return "FMAX"
			return MillNc.fmt(float(b["f"])).trim_prefix("+") if b.has("f") else ""
		"mlist":
			var ms: Array = b.get("m", [])
			if ms.is_empty() and s.has("def") and not editing:
				ms = s["def"]
			var parts: PackedStringArray = []
			for m in ms:
				parts.append("M%d" % int(m))
			return " ".join(parts)
		"text":
			return str(b.get(key, s.get("def", "")))
	return ""


## Halbfertiger Satz als Text, mit Schreibmarke am Ende.
func preview() -> String:
	var out: PackedStringArray = []
	for b in blocks:
		out.append(MillNc.format_block(b))
	return " | ".join(out)


func lines() -> Array[String]:
	var out: Array[String] = []
	for b in blocks:
		out.append(MillNc.format_block(b))
	return out


# ======================================================================= Eingaben

## Zahl lesen ("12,5", "+3", "-4.25"); null bei Unsinn.
static func parse_num(t: String) -> Variant:
	var s := t.strip_edges().replace(",", ".")
	if s == "" or not s.is_valid_float():
		return null
	return s.to_float()


## Antwort auf die aktuelle Frage (ENT). Rückgabe: Fehlertext oder "" (dann ist der nächste Schritt dran).
func answer(text: String) -> String:
	if finished or steps.is_empty():
		return ""
	var s := step()
	var t := text.strip_edges()
	var b: Dictionary = blocks[int(s.get("blk", 0))]
	var key = s["key"]
	if t == "" and str(s["kind"]) != "text":
		if bool(s.get("opt", false)):
			return skip()
		if s.has("def") and str(s["kind"]) != "choice":
			t = default_text()
		if t == "":
			return "Bitte einen Wert eingeben."
	match str(s["kind"]):
		"num":
			var inc := false
			if bool(s.get("inc", false)) and t.to_upper().begins_with("I"):
				inc = true
				t = t.substr(1)
			var v: Variant = parse_num(t)
			if v == null:
				return "'%s' ist keine Zahl." % text.strip_edges()
			var f := float(v)
			if s.has("min") and f < float(s["min"]):
				return "Wert muss mindestens %s sein." % MillNc.fmt(float(s["min"])).trim_prefix("+")
			if s.has("max") and f > float(s["max"]):
				return "Wert darf höchstens %s sein." % MillNc.fmt(float(s["max"])).trim_prefix("+")
			if s.get("q", false):
				if not b.has("q"):
					b["q"] = {}
				b["q"][key] = f
			else:
				b[key] = f
				if bool(s.get("inc", false)):
					if inc:
						b["i" + str(key)] = true
					else:
						b.erase("i" + str(key))
		"int":
			var v: Variant = parse_num(t)
			if v == null or absf(float(v) - roundf(float(v))) > 1e-6:
				return "'%s' ist keine ganze Zahl." % text.strip_edges()
			var n := int(roundf(float(v)))
			if s.has("min") and n < int(s["min"]):
				return "Wert muss mindestens %d sein." % int(s["min"])
			if s.has("max") and n > int(s["max"]):
				return "Wert darf höchstens %d sein." % int(s["max"])
			b[key] = n
		"feed":
			if t.to_upper() == "FMAX":
				if bool(s.get("nofmax", false)):
					return "FMAX ist hier nicht möglich."
				b["fmax"] = true
				b.erase("f")
			else:
				var v: Variant = parse_num(t)
				if v == null or float(v) <= 0.0:
					return "Vorschub F muss eine Zahl größer 0 sein (oder FMAX)."
				b["f"] = float(v)
				b.erase("fmax")
		"mlist":
			var ms: Array = []
			for w in t.to_upper().replace(",", " ").replace("M", " ").split(" ", false):
				if not w.is_valid_int() or int(w) < 0:
					return "M-Funktion '%s' nicht lesbar." % w
				if not MillNc.M_CODES.has(int(w)):
					return "M%d kennt diese Steuerung nicht." % int(w)
				ms.append(int(w))
			if ms.is_empty():
				return "Bitte eine M-Funktion eingeben (z. B. 3)."
			b["m"] = ms
		"text":
			if str(s["id"]) == "name":
				t = clean_name(t)
				if t == "":
					return "Programmname fehlt (Buchstaben, Ziffern, _)."
			b[key] = t.strip_edges() if str(s["id"]) != "name" else t
		"choice":
			var found := -1
			for ci in (s["choices"] as Array).size():
				if str((s["choices"] as Array)[ci][0]).to_upper() == t.to_upper() or str((s["choices"] as Array)[ci][1]).to_upper() == t.to_upper():
					found = ci
			if found < 0:
				return "Bitte mit einer Softkey-Taste wählen."
			return choose(found)
	return _advance()


## Auswahl bei einer Frage mit Softkeys (RL / RR / KEINE KORR., DR+ / DR-).
func choose(ci: int) -> String:
	if not is_choice():
		return "Keine Auswahl möglich."
	var ch: Array = choices()
	if ci < 0 or ci >= ch.size():
		return "Auswahl ungültig."
	var s := step()
	(blocks[int(s.get("blk", 0))] as Dictionary)[s["key"]] = ch[ci][1]
	return _advance()


## NO ENT: Eingabe überspringen (entfernt den Wert), nur bei freiwilligen Feldern.
func skip() -> String:
	if finished or steps.is_empty():
		return ""
	var s := step()
	if not bool(s.get("opt", false)):
		return "Diese Eingabe ist nötig."
	var b: Dictionary = blocks[int(s.get("blk", 0))]
	var key = s["key"]
	match str(s["kind"]):
		"feed":
			b.erase("f")
			b.erase("fmax")
		"num":
			b.erase(key)
			b.erase("i" + str(key))
		_:
			b.erase(key)
	return _advance()


## ENDE: Rest des Satzes mit Standardwerten bzw. ohne die freiwilligen Felder abschließen.
func finish() -> String:
	while not finished and not steps.is_empty():
		var s := step()
		var b: Dictionary = blocks[int(s.get("blk", 0))]
		var have: bool
		if s.get("q", false):
			have = (b.get("q", {}) as Dictionary).has(s["key"])
		else:
			have = b.has(s["key"])
		if have or bool(s.get("opt", false)):
			i += 1
		elif s.has("def"):
			var e := _apply_default(s, b)
			if e != "":
				return e
			i += 1
		else:
			return "Es fehlt noch: " + str(s["prompt"])
		if i >= steps.size():
			finished = true
	return ""


func _apply_default(s: Dictionary, b: Dictionary) -> String:
	var d: Variant = s["def"]
	var key = s["key"]
	if s.get("q", false):
		if not b.has("q"):
			b["q"] = {}
		b["q"][key] = float(d)
	elif str(s["kind"]) == "mlist":
		b[key] = (d as Array).duplicate()
	elif str(s["kind"]) == "int":
		b[key] = int(d)
	elif str(s["kind"]) == "text":
		b[key] = str(d)
	else:
		b[key] = d
	return ""


## Eine Frage zurück.
func back() -> void:
	if i > 0:
		i -= 1
		finished = false


func _advance() -> String:
	i += 1
	if i >= steps.size():
		finished = true
	return ""


## Programmname bereinigen: Großbuchstaben, Ziffern, Unterstrich, höchstens 16 Zeichen.
static func clean_name(t: String) -> String:
	var up := t.strip_edges().to_upper().replace(" ", "_").replace("Ä", "AE").replace("Ö", "OE").replace("Ü", "UE").replace("ß", "SS")
	var out := ""
	for k in up.length():
		var ch := up[k]
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_":
			out += ch
	return out.substr(0, 16)
