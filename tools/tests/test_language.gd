extends SceneTree
## Sprachauswahl im Hauptmenü und Mundart-Sprachpakete (Schwäbisch, Sächsisch, Schweizerdeutsch,
## Bayerisch, Piratisch): Übersetzung ganzer Texte, Wörter, Lautregeln, Tags und Abkürzungen.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


const SAMPLES := [
	"Werkzeug wechseln", "Gabel heben", "Teil prüfen & abgeben", "Kühlschmierstoff an/aus",
	"Spänebehälter in den Container leeren", "Erst die Schutztür schließen", "Halterung für die Fernbedienung",
	"Drehzahl erhöhen", "Vorschub verringern", "Interagieren / Maschine bedienen", "Getragenes fallen lassen",
	"Fortsetzen", "Drehmaschine bedienen", "Linksklick: Rohteil einspannen",
	"Die Spänewanne ist voll. Erst leeren!", "Kein Platz in der Werkstatt", "Einstellungen",
	"Aufträge annehmen und Teile abgeben", "Zigarette anzünden / ausmachen",
	"[b]Geld:[/b] 120 EUR", "Spindel Start / Stopp", "Gabelstapler fahren",
]


func _initialize() -> void:
	await process_frame
	var st = root.get_node("Settings")
	var before: String = st.language()
	var codes: Array = Dialects.codes()
	ok(codes == ["de", "swg", "sxu", "gsw", "bar", "pir"], "Sechs Sprachen: %s" % [codes])
	ok(Dialects.make("de") == null, "Hochdeutsch braucht kein Sprachpaket")

	for code in codes:
		var d := Dialects.make(code)
		if d == null:
			continue
		print("--- ", Dialects.display_name(code))
		for s in SAMPLES:
			print("  ", s, "  ->  ", d.render(s))
		ok(d.render("Fortsetzen") != "Fortsetzen", code + ": Menüeintrag übersetzt")
		ok(d.render("CNC G01 X20 Z-5 CuZn") == "CNC G01 X20 Z-5 CuZn", code + ": Code und Abkürzungen bleiben")
		ok(d.render("[color=#ffcc00]x[/color]").begins_with("[color=#ffcc00]"), code + ": BBCode bleibt")
		ok(d.render("res://models/lathe.glb") == "res://models/lathe.glb", code + ": Pfade bleiben")

	var swg := Dialects.make("swg")
	ok(swg.render("Das ist nicht gut") == "'s isch net guat", "Schwäbisch: " + swg.render("Das ist nicht gut"))
	ok(swg.render("Einstellung") == "Eistellong", "Schwäbisch -ung: " + swg.render("Einstellung"))
	var sxu := Dialects.make("sxu")
	ok(sxu.render("Ich kaufe") == "Isch goofe", "Sächsisch: " + sxu.render("Ich kaufe"))
	var gsw := Dialects.make("gsw")
	ok(gsw.render("heiß").find("ß") < 0, "Schweizerdeutsch ohne ß")
	var bar := Dialects.make("bar")
	ok(bar.render("Das ist nicht viel") == "'s is ned vui", "Bayerisch: " + bar.render("Das ist nicht viel"))
	ok(gsw.render("Das geht nicht mehr") == "Ds gaht nümme", "Zwei Wörter als Eintrag: " + gsw.render("Das geht nicht mehr"))
	ok(gsw.render("Kiste") == "Chischte" and gsw.render("Kran") == "Chran", "Schweizerdeutsch K- wird Ch-")
	ok(bar.render("Geld") == "Gäid" and bar.render("Hilfe") == "Huif" and bar.render("Gold") == "Goid", "Bairisch l-Vokalisierung: " + bar.render("Geld") + " " + bar.render("Hilfe"))
	ok(sxu.render("Stopp") == "Schdobb", "Sächsisch st/p: " + sxu.render("Stopp"))
	ok(swg.render("Gewicht") == "Gwicht" and swg.render("Fenster") == "Fenschter", "Schwäbisch ge- und st: " + swg.render("Fenster"))
	for pair in [["angenommen", "agnomma"], ["Angenommen", "Agnomma"], ["eingespannt", "eigspannt"],
			["aufgenommen", "uffgnomma"], ["anzünden", "azünda"], ["abgeschlossen", "abgschlossa"],
			["Anzahl", "Azahl"], ["anders", "andersch"], ["Andersherum", "Andersherum"],
			["hingehen", "hingeha"], ["hochgefahren", "hochgfahra"], ["Ankerkette", "Ankerkett"]]:
		ok(swg.render(pair[0]) == pair[1], "Schwäbisch %s -> %s (ist %s)" % [pair[0], pair[1], swg.render(pair[0])])
	var pir := Dialects.make("pir")
	ok(pir.render("Alles fertig!").ends_with("Arr!"), "Piratisch: " + pir.render("Alles fertig!"))

	# ----------------------------------------------- Umschalten über die Einstellungen
	st.set_language("swg")
	ok(TranslationServer.translate("Das ist nicht gut") == "'s isch net guat", "Übersetzung aktiv")
	var l := Label.new()
	l.text = "Spiel laden"
	root.add_child(l)
	await process_frame
	ok(l.atr(l.text) == "Spiel lada", "Label übersetzt: " + l.atr(l.text))
	st.set_language("de")
	ok(TranslationServer.translate("Das ist nicht gut") == "Das ist nicht gut", "Zurück auf Hochdeutsch")
	st.set_language("xyz")
	ok(st.language() == "de", "Unbekannte Sprache wird ignoriert")
	l.queue_free()

	# ----------------------------------------------- Hauptmenü
	var m = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(m)
	for i in 3:
		await process_frame
	ok(m._lang_button != null and m._buttons.has(m._lang_button), "Menüeintrag Sprache")
	m._show_languages()
	ok(m._lang_panel.visible and m._lang_list.get_child_count() == 6, "Sprachfenster mit sechs Sprachen")
	m._choose_language("bar")
	ok(st.language() == "bar" and m._lang_sub().text == "Bayerisch", "Bayerisch gewählt")
	await process_frame
	ok(m._lang_list.get_node("lang_bar").find_children("*", "Label", true, false)[0].text.contains("✓"), "Haken bei der gewählten Sprache")
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	ok(str(cfg.get_value("game", "language", "")) == "bar", "Sprache gespeichert")
	m._close_panels()
	ok(not m._lang_panel.visible, "Sprachfenster geschlossen")

	st.set_language(before)
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
