class_name Dialect
extends Translation
## Mundart-Sprachpaket: übersetzt die hochdeutschen Texte des Spiels zur Laufzeit.
## Godot schickt jeden Text von Label, Button, Label3D usw. durch _get_message.
## Reihenfolge: ganzer Satz aus `phrases`, sonst Wort für Wort aus `words`,
## sonst Lautregeln (`rules`, nur auf Wörter ab 4 Buchstaben). BBCode-Tags, Wörter
## an Ziffern oder Unterstrichen und Abkürzungen (CNC, CuZn) bleiben unverändert.

## Ganze Texte, exakt wie im Spiel
var phrases: Dictionary = {}
## kleingeschriebenes Wort -> Ersatz
var words: Dictionary = {}
## [[RegEx, Ersatz], ...] für Wörter, die nicht in `words` stehen
var rules: Array = []
## [[Suchtext, Ersatz], ...] zum Schluss auf den ganzen Text
var post: Array = []
## Text, der an Sätze mit "!" am Ende angehängt wird
var exclaim := ""

const MAX_CACHE := 20000
var _cache: Dictionary = {}
var _word_re := RegEx.create_from_string("[A-Za-zÄÖÜäöüß]+")
var _tag_re := RegEx.create_from_string("\\[[^\\]]*\\]")


func _init(code: String, data: Dictionary) -> void:
	locale = code
	phrases = data.get("phrases", {})
	words = data.get("words", {})
	post = data.get("post", [])
	exclaim = data.get("exclaim", "")
	for r in data.get("rules", []):
		rules.append([RegEx.create_from_string(r[0]), r[1]])


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	var s := str(src_message)
	if s.is_empty():
		return src_message
	if _cache.has(s):
		return _cache[s]
	if _cache.size() > MAX_CACHE:
		_cache.clear()
	var out := StringName(render(s))
	_cache[s] = out
	return out


## Ganzen Text übersetzen (BBCode-Tags bleiben stehen).
func render(s: String) -> String:
	if phrases.has(s):
		return phrases[s]
	var out := ""
	var at := 0
	for m in _tag_re.search_all(s):
		out += _text(s.substr(at, m.get_start() - at)) + m.get_string()
		at = m.get_end()
	out += _text(s.substr(at))
	for p in post:
		out = out.replace(p[0], p[1])
	if exclaim != "" and out.ends_with("!") and not out.ends_with(exclaim):
		out += exclaim
	return out


func _text(s: String) -> String:
	if s.is_empty():
		return s
	var key := s.strip_edges()
	if phrases.has(key):
		return s.replace(key, phrases[key])
	var out := ""
	var at := 0
	var ms := _word_re.search_all(s)
	var i := 0
	while i < ms.size():
		var m: RegExMatch = ms[i]
		var a := m.get_start()
		var b := m.get_end()
		out += s.substr(at, a - at)
		var w := m.get_string()
		# Zwei Wörter als ein Eintrag ("nicht mehr" -> "nümme")
		if i + 1 < ms.size() and ms[i + 1].get_start() == b + 1 and s[b] == " ":
			var pair := w + " " + ms[i + 1].get_string()
			if words.has(pair.to_lower()):
				out += _case(pair, words[pair.to_lower()])
				at = ms[i + 1].get_end()
				i += 2
				continue
		var touch := (a > 0 and _techy(s[a - 1])) or (b < s.length() and _techy(s[b]))
		out += w if touch else word(w)
		at = b
		i += 1
	return out + s.substr(at)


func _case(src: String, rep: String) -> String:
	if rep != "" and src[0] != src[0].to_lower():
		return rep[0].to_upper() + rep.substr(1)
	return rep


func _techy(c: String) -> bool:
	return c == "_" or c == "/" or c == "\\" or (c >= "0" and c <= "9")


## Ein einzelnes Wort übersetzen, Großschreibung am Wortanfang bleibt erhalten.
func word(w: String) -> String:
	if w.length() < 2:
		return w
	var rest := w.substr(1)
	if rest != rest.to_lower():
		return w                       # Abkürzung oder Formel (CNC, CuZn, KSS)
	var low := w.to_lower()
	var rep: String
	if words.has(low):
		rep = words[low]
	elif low.length() >= 4:
		rep = low
		for r in rules:
			rep = r[0].sub(rep, r[1], true)
	else:
		return w
	if rep == low:
		return w
	if w[0] != low[0] and rep != "":
		rep = rep[0].to_upper() + rep.substr(1)
	return rep
