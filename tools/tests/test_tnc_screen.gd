extends SceneTree
## Steuerung am Pult der CNC-Fräse (TncScreen): Aufbau, Betriebsarten, Satzdialog, Textbearbeitung, Speichern,
## Programm-Test, Programmlauf über den Bildschirm, MDI, Bezugspunkt, Werkzeugtabelle, Mausklick auf Softkeys,
## Sperren bei laufendem Programm, Zustand ohne Strom.
## Aufruf: Godot --headless --path . -s res://tools/tests/test_tnc_screen.gd
var checks := 0
var fails := 0
const DT := 1.0 / 60.0
var m
var s


func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func frames(n: int) -> void:
	for i in n:
		m._physics_process(DT)


func run_channel(max_frames := 60000) -> int:
	var n := 0
	while m.channel.state == "run" and n < max_frames:
		m._physics_process(DT)
		n += 1
	return n


func wait_change() -> void:
	var n := 0
	while m.changing and n < 3000:
		m._physics_process(DT)
		n += 1


## Dialog mit den Antworten durchlaufen: Text = Eingabe, "-" = NO ENT, "#n" = Auswahl n, "!" = ENDE.
func dialog(kind: String, answers: Array, extra: Dictionary = {}) -> void:
	s._dlg_new(kind, extra)
	for a in answers:
		var t := str(a)
		if s._dlg == null:
			break
		if t == "-":
			s._dlg_skip()
		elif t == "!":
			s._dlg_end()
		elif t.begins_with("#"):
			s._dlg_choose(int(t.substr(1)))
		else:
			s._bar_submit(t)


func click(btn: Control) -> void:
	var px: Vector2 = btn.get_global_transform() * (btn.size * 0.5)
	var mv := InputEventMouseMotion.new()
	mv.position = px
	m.push_screen_event(mv, px)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.position = px
	m.push_screen_event(d, px)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = px
	m.push_screen_event(u, px)


func item_texts(l: ItemList) -> String:
	var out := ""
	for i in l.item_count:
		out += l.get_item_text(i) + "\n"
	return out


func _initialize() -> void:
	await process_frame
	m = load("res://scripts/machine/cnc_mill.gd").new()
	root.add_child(m)
	await process_frame
	await process_frame
	m.power_on(true)
	await process_frame
	s = m.screen
	ok(s != null and s.get_script().resource_path.ends_with("tnc_screen.gd") and s.mill == m, "Bildschirm ist TncScreen und kennt die Maschine")
	ok(s.size == m.SCREEN_UI, "Bildschirm hat die Größe des Pults (%s)" % s.size)
	m.magazine_set(1, "MK63")
	m.magazine_set(2, "F12")
	m.magazine_set(3, "B10")
	m.magazine_set(5, "F6")
	s._tick()

	# ------------------------------------------------------------------ Betriebsarten
	for pair in [["manual", "manual"], ["mdi", "mdi"], ["single", "run"], ["auto", "run"], ["edit", "edit"], ["pgm", "pgm"],
			["test", "test"], ["tools", "tools"], ["machine", "manual"]]:
		s.show_mode(pair[0])
		await process_frame
		s._tick()
		ok(s.mode == pair[1], "Betriebsart %s -> Seite %s (ist %s)" % [pair[0], pair[1], s.mode])
		var vis := 0
		for k in s._pages:
			if (s._pages[k] as Control).visible:
				vis += 1
		ok(vis == 1, "genau eine Seite sichtbar in %s" % pair[0])
	s.show_mode("single")
	ok(m.channel.single_block, "Einzelsatz-Taste setzt Einzelsatz")
	s.show_mode("auto")
	ok(not m.channel.single_block, "Satzfolge-Taste hebt Einzelsatz auf")
	ok(s._hdr_l_lbl.text == "Programmlauf Satzfolge", "Kopfzeile links: %s" % s._hdr_l_lbl.text)

	# ------------------------------------------------------------------ Programm neu anlegen
	var n0: int = m.programs.size()
	s.show_mode("pgm")
	ok(s._pgm_list.item_count == n0, "PGM MGT listet alle %d Programme" % n0)
	ok(s._pgm_list.get_item_text(0).contains("PLANEN.H"), "Liste zeigt NAME.H (%s)" % s._pgm_list.get_item_text(0))
	ok(s._pgm_do_new("") != "", "leerer Programmname wird abgelehnt")
	ok(s._pgm_do_new("planen") != "", "doppelter Programmname wird abgelehnt")
	ok(s._pgm_do_new("Probe 1") == "", "Programm anlegen")
	ok(not m.program("PROBE_1").is_empty(), "Programm PROBE_1 liegt in mill.programs")
	var pl: Array = m.program("PROBE_1")["lines"]
	ok(pl.size() == 4 and pl[0] == "BEGIN PGM PROBE_1 MM" and pl[3] == "END PGM PROBE_1 MM", "neues Programm: BEGIN, BLK FORM x2, END (%s)" % [pl])
	ok(m.selected_program()["name"] == "PROBE_1" and s.mode == "edit", "neues Programm ist angewählt und im Editor")
	ok(s._lines.size() == 4 and s._prog == "PROBE_1", "Editor hat das Programm geladen")

	# ------------------------------------------------------------------ Sätze über den Dialog einfügen
	s._cursor = 2
	dialog("tool_call", ["2", "3500", "-"])
	ok(s._lines[3] == "TOOL CALL 2 Z S3500" and s._cursor == 3, "TOOL CALL im Dialog (%s)" % s._lines[3])
	dialog("l", ["-", "-", "100", "#2", "!"])
	ok(s._lines[4] == "L Z+100 R0", "L-Satz mit ENDE nach Radiuskorrektur (%s)" % s._lines[4])
	dialog("l", ["50", "30", "-", "#2", "FMAX", "3"])
	ok(s._lines[5] == "L X+50 Y+30 R0 FMAX M3", "L-Satz mit FMAX und M3 (%s)" % s._lines[5])
	dialog("l", ["i-5", "-", "-", "-", "250", "-"])
	ok(s._lines[6] == "L IX-5 F250", "L-Satz inkremental mit Vorschub (%s)" % s._lines[6])
	dialog("cc", ["50", "30"])
	ok(s._lines[7] == "CC X+50 Y+30", "CC-Satz (%s)" % s._lines[7])
	dialog("c", ["60", "30", "#1", "200", "-"])
	ok(s._lines[8] == "C X+60 Y+30 DR- F200", "C-Satz mit DR- (%s)" % s._lines[8])
	dialog("cycl_def", [], {"cycle": 251})
	ok(s._dlg != null and s._dlg.steps.size() == (MillNc.CYCLES[251]["q"] as Array).size(), "Zyklus 251 fragt alle Q-Parameter")
	ok(s._bar_prompt.text.contains("Q218") and s._bar_edit.text == "+50", "erste Frage Q218 mit Standardwert (%s / %s)" % [s._bar_prompt.text, s._bar_edit.text])
	s._bar_submit("40")
	s._bar_submit("20")
	s._dlg_end()
	ok(s._lines[9].begins_with("CYCL DEF 251 RECHTECKTASCHE Q218=+40 Q219=+20 ") and s._lines[9].contains("Q201=-10"), "CYCL DEF 251 mit geänderten und Standardwerten (%s)" % s._lines[9])
	ok(MillNc.parse_line(s._lines[9])["type"] == "cycl_def", "CYCL-DEF-Satz lässt sich lesen")
	dialog("cycl_call", ["-"])
	ok(s._lines[10] == "CYCL CALL", "CYCL CALL (%s)" % s._lines[10])
	dialog("m", ["5 9"])
	ok(s._lines[11] == "M5 M9", "M-Satz (%s)" % s._lines[11])
	dialog("lbl", ["1"])
	dialog("call_lbl", ["1", "3"])
	ok(s._lines[12] == "LBL 1" and s._lines[13] == "CALL LBL 1 REP 3", "LBL und CALL LBL (%s / %s)" % [s._lines[12], s._lines[13]])
	dialog("comment", ["Tasche fräsen"])
	ok(s._lines[14] == "; Tasche fräsen", "Kommentar (%s)" % s._lines[14])
	dialog("stop", [])
	ok(s._lines[15] == "STOP", "STOP-Satz ohne Fragen (%s)" % s._lines[15])
	dialog("blk2", ["0", "0", "-30", "80", "50", "0"])
	ok(s._lines[16] == "BLK FORM 0.1 Z X+0 Y+0 Z-30" and s._lines[17] == "BLK FORM 0.2 X+80 Y+50 Z+0", "BLK FORM 0.1/0.2 (%s | %s)" % [s._lines[16], s._lines[17]])
	ok(s._lines[s._lines.size() - 1] == "END PGM PROBE_1 MM", "END PGM bleibt am Ende")
	var before: int = s._lines.size()
	s._dlg_new("l")
	ok(s._dlg != null, "Dialog offen")
	s._bar_submit("abc")
	ok(s._dlg.i == 0, "falsche Eingabe bleibt bei der Frage")
	ok(s._dlg.answer("5") == "" and s._dlg.i == 1, "richtige Eingabe geht weiter")
	s._dlg_back()
	ok(s._dlg.i == 0 and s._bar_edit.text == "+5", "ZURÜCK geht eine Frage zurück, Wert bleibt")
	s._dlg_abort()
	ok(s._dlg == null and s._lines.size() == before, "ABBRUCH fügt nichts ein")
	# Satz im Dialog ändern
	s._cursor = 5
	s._dlg_change()
	ok(s._dlg != null and s._bar_edit.text == "+50", "Dialog ändern: Feld mit Wert vorbelegt (%s)" % s._bar_edit.text)
	s._bar_submit("55")
	s._dlg_end()
	ok(s._dlg == null and s._lines[5] == "L X+55 Y+30 R0 FMAX M3", "Satz im Dialog geändert (%s)" % s._lines[5])

	# ------------------------------------------------------------------ Textbearbeitung mit Fehler
	s._cursor = 5
	s._bar_text_open()
	ok(s._bar_mode == "text" and s._bar_edit.text == s._lines[5], "Satzzeile zeigt den Satz am Cursor")
	s._bar_edit.text = "L X5x Y3"
	s._bar_changed("L X5x Y3")
	s._bar_submit("L X5x Y3")
	ok(s._perr.has(5), "fehlerhafter Satz ist markiert")
	ok(s._ed_list.get_item_custom_fg_color(5) == s.C_ERR, "fehlerhafter Satz ist rot")
	ok(s._msg_cls == "err" and s._msg.begins_with("Satz 5:"), "Fehler steht in der Meldezeile (%s)" % s._msg)
	ok(m.program("PROBE_1")["lines"][5] == "L X5x Y3", "fehlerhafter Satz geht nicht verloren")
	s._bar_edit.text = "l x5 y3"
	s._bar_changed("l x5 y3")
	s._bar_submit("l x5 y3")
	ok(not s._perr.has(5) and s._lines[5] == "L X+5 Y+3", "korrigierter Satz wird in Klartext gebracht (%s)" % s._lines[5])
	# Satz löschen / verschieben
	var cnt: int = s._lines.size()
	s._cursor = 14
	var txt14: String = s._lines[14]
	s._ed_move(-1)
	ok(s._lines[13] == txt14 and s._cursor == 13, "Satz nach oben")
	s._ed_move(1)
	ok(s._lines[14] == txt14 and s._cursor == 14, "Satz nach unten")
	s._ed_delete()
	ok(s._lines.size() == cnt - 1 and not s._lines.has(txt14), "Satz löschen")
	s._cursor = 0
	s._ed_delete()
	ok(s._lines[0].begins_with("BEGIN PGM"), "BEGIN PGM lässt sich nicht löschen")
	s._cursor = s._lines.size() - 1
	s._ed_move(-1)
	ok(s._lines[s._lines.size() - 1].begins_with("END PGM"), "END PGM lässt sich nicht verschieben")
	# Speichern
	ok(m.program("PROBE_1")["lines"] == s._lines, "Änderungen stehen in mill.programs")
	# Name über BEGIN PGM ändern
	s._cursor = 0
	s._bar_text_open()
	s._bar_edit.text = "BEGIN PGM TESTPGM MM"
	s._bar_changed("BEGIN PGM TESTPGM MM")
	s._bar_submit("BEGIN PGM TESTPGM MM")
	ok(not m.program("TESTPGM").is_empty() and m.program("PROBE_1").is_empty(), "BEGIN PGM benennt das Programm um")
	ok(s._lines[s._lines.size() - 1] == "END PGM TESTPGM MM", "END PGM zieht den Namen nach")
	# Wechsel der Betriebsart verliert nichts
	s._cursor = 3
	s._bar_text_open()
	s._bar_edit.text = "TOOL CALL 3 Z S1800"
	s._bar_changed("TOOL CALL 3 Z S1800")
	s.show_mode("manual")
	ok(m.program("TESTPGM")["lines"][3] == "TOOL CALL 3 Z S1800", "Wechsel der Betriebsart: Eingabe bleibt erhalten und wird gespeichert")

	# ------------------------------------------------------------------ Programm-Test eines Beispielprogramms
	for i in m.programs.size():
		if m.programs[i]["name"] == "TASCHE":
			m.prog_sel = i
	s.show_mode("test")
	var res: Dictionary = s._test_res
	ok(not res.is_empty() and (res["errs"] as Array).is_empty(), "TASCHE: Programm-Test ohne Fehler (%s)" % [res.get("errs")])
	ok(s._plot.has_data and s._plot._feed.size() > 20 and s._plot._rapid.size() >= 2, "TASCHE: Grafik hat Bahn (%d Vorschub, %d Eilgang)" % [s._plot._feed.size(), s._plot._rapid.size()])
	ok(s._section.has_data, "TASCHE: Seitenansicht hat Daten")
	ok(s._test_verdict.text == "KEINE FEHLER", "Urteil: %s" % s._test_verdict.text)
	ok(s._test_sum.text.contains("Laufzeit") and s._test_sum.text.contains("T2"), "Zusammenfassung nennt Laufzeit und Werkzeug (%s)" % s._test_sum.text.replace("\n", " | "))
	var sig_before: String = s._test_sig
	s._test_run(false)
	ok(s._test_sig == sig_before, "unverändertes Programm wird nicht neu gerechnet")
	# Abtrag der Grafik entspricht der Tasche
	var im: Image = s._plot._tex.get_image()
	var cutc := 0
	for y in im.get_height():
		for x in im.get_width():
			if im.get_pixel(x, y).b < 0.85 and im.get_pixel(x, y).r < 0.5:
				cutc += 1
	ok(cutc > 500, "Grafik zeigt Abtrag als Tiefenfarben (%d blaue Zellen)" % cutc)
	# Fehlerprogramm
	m.save_program("KAPUTT", ["BEGIN PGM KAPUTT MM", "BLK FORM 0.1 Z X+0 Y+0 Z-40", "BLK FORM 0.2 X+100 Y+60 Z+0", "TOOL CALL 1 Z S800",
		"L X+10 Y+10 F200", "L X+20 Y+x", "FOO BAR", "M30", "END PGM KAPUTT MM"])
	m.prog_sel = m.programs.size() - 1
	s.show_mode("test")
	var errs: Array = s._test_res["errs"]
	ok(errs.size() >= 2, "Fehlerprogramm: Fehlerliste (%d)" % errs.size())
	ok(s._test_errs.item_count == errs.size() and s._test_verdict.text.contains("FEHLER") and not s._test_verdict.text.begins_with("KEINE"), "Fehlerliste im Bildschirm (%s)" % s._test_verdict.text)
	var jump := -1
	for i in s._test_errs.item_count:
		if str(s._test_errs.get_item_text(i)).begins_with("Satz 5"):
			jump = i
	ok(jump >= 0, "Fehler von Satz 5 steht in der Liste")
	if jump >= 0:
		s._test_err_picked(jump)
		ok(s.mode == "edit" and s._cursor == 5 and s._prog == "KAPUTT", "Klick auf Fehler springt im Editor zum Satz (%s, %d)" % [s.mode, s._cursor])
	ok(s._perr.has(5) and s._perr.has(6), "Editor markiert die Syntaxfehler (%s)" % [s._perr.keys()])
	s._test_run(true)

	# ------------------------------------------------------------------ Programm über den Bildschirm starten
	m.delete_program("KAPUTT")
	for i in m.programs.size():
		if m.programs[i]["name"] == "TASCHE":
			m.prog_sel = i
	m.set_material("AW-6082")
	m.new_workpiece(100.0, 60.0, 40.0)
	m.tool_z = 100.0
	m._sync_axes()
	m.magazine.fill("")
	m.clear_spindle()
	m.magazine_set(1, "MK63")
	m.magazine_set(2, "F12")
	m.magazine_set(3, "B10")
	s.show_mode("manual")
	s._nc_start()
	ok(m.channel.state == "run" and s.mode == "run", "NC-Start am Bildschirm startet das Programm und zeigt den Programmlauf")
	var lines_seen := {}
	var n := 0
	while m.channel.state == "run" and n < 60000:
		m._physics_process(DT)
		n += 1
		if n % 8 == 0:
			s._tick()
			lines_seen[m.channel.line] = true
			if m.channel.line >= 0 and n % 600 == 0:
				ok(s._run_list.get_selected_items().size() == 1 and s._run_list.get_selected_items()[0] == m.channel.line, "laufender Satz ist markiert (%d)" % m.channel.line)
		if n == 400:
			s._nc_stop()
			ok(m.channel.state == "hold", "NC-Stopp hält an")
			s._tick()
			ok(s._chips["chan"]["lbl"].text == "HALT" and s._run_state.text.begins_with("ANGEHALTEN"), "Anzeige: angehalten")
			s._nc_start()
			ok(m.channel.state == "run", "NC-Start nach NC-Stopp macht weiter")
	ok(m.channel.state == "done", "Programm läuft durch (%s)" % m.channel.alarm)
	ok(lines_seen.size() > 4, "Satzanzeige wandert (%d verschiedene Sätze)" % lines_seen.size())
	s._tick()
	ok(s._run_state.text == "PROGRAMM BEENDET" and absf(m.height_at(50.0, 30.0) + 10.0) < 0.05, "Programm beendet, Tasche gefräst")
	# Einzelsatz
	s._toggle_single()
	ok(m.channel.single_block and s._hdr_l_lbl.text == "Programmlauf Einzelsatz", "Einzelsatz ein, Kopfzeile folgt")
	m.tool_z = 100.0
	m._sync_axes()
	s._nc_start()
	frames(900)
	ok(m.channel.state == "hold" and m.channel.hold_reason == "Einzelsatz", "Einzelsatz hält nach dem Satz (%s)" % m.channel.state)
	var l1: int = m.channel.line
	s._nc_start()
	frames(900)
	ok(m.channel.line != l1 or m.channel.state != "hold", "NC-Start geht zum nächsten Satz")
	s._reset()
	ok(m.channel.state == "idle", "Interner Stopp setzt den Kanal zurück")
	s._toggle_single()
	ok(not m.channel.single_block, "Einzelsatz aus")

	# ------------------------------------------------------------------ Sperren bei laufendem Programm
	m.tool_z = 100.0
	m._sync_axes()
	s.show_mode("edit")
	s._cursor = 3
	var lines_then: Array[String] = s._lines.duplicate()
	m.nc_start()
	frames(30)
	s._tick()
	ok(m.channel.busy(), "Programm läuft für den Sperrtest")
	s._dlg_new("l")
	ok(s._dlg == null, "Dialog ist bei laufendem Programm gesperrt")
	s._ed_delete()
	ok(s._lines == lines_then, "Satz löschen ist gesperrt")
	ok(not s._bar_edit.editable, "Satzzeile ist schreibgeschützt")
	s._tick()
	ok(s._sk_btns[0].disabled and s._sk_btns[1].disabled, "Softkeys zum Einfügen sind gesperrt")
	s.show_mode("mdi")
	s._mdi_text = "L Z+80 R0 FMAX"
	var st: String = m.channel.prog_name
	s._mdi_exec()
	ok(m.channel.prog_name == st, "MDI ist bei laufendem Programm gesperrt")
	s.show_mode("manual")
	s._tick()
	ok(s._sk_btns[1].disabled, "Softkey S ist bei laufendem Programm gesperrt")
	s._ask_datum(0)
	s._reset()
	ok(not m.channel.busy(), "Reset beendet den Sperrtest")
	s._tick()
	ok(not s._sk_btns[1].disabled, "Softkey S ist nach Reset wieder frei")

	# ------------------------------------------------------------------ MDI
	m.tool_z = 100.0
	m._sync_axes()
	s.show_mode("mdi")
	ok(s._bar_mode == "mdi" and s._bar_edit.visible, "MDI zeigt die Eingabezeile")
	s._mdi_text = "L X+x"
	s._mdi_exec()
	ok(s._msg_cls == "err" and not m.channel.busy(), "MDI: fehlerhafter Satz wird gemeldet (%s)" % s._msg)
	s._mdi_text = "l x+20 y+20 z+50 r0 fmax"
	s._nc_start()
	ok(m.channel.state == "run" and m.channel.prog_name == "MDI", "NC-Start führt den MDI-Satz aus")
	run_channel()
	ok(m.channel.state == "done" and absf(m.pos().x - 20.0) < 0.01 and absf(m.pos().z - 50.0) < 0.01, "MDI-Satz hat gefahren (%s)" % m.pos())
	s._tick()
	ok(s._mdi_hist.size() == 1 and s._mdi_hist[0] == "L X+20 Y+20 Z+50 R0 FMAX" and s._mdi_list.item_count == 1, "Verlauf merkt sich den Satz (%s)" % [s._mdi_hist])
	s._mdi_text = ""
	s._dlg_new("l")
	s._bar_submit("30")
	s._dlg_end()
	ok(s._mdi_text == "L X+30" and s._bar_mode == "mdi", "Satzdialog füllt die MDI-Zeile (%s)" % s._mdi_text)
	s._mdi_pick(0)
	ok(s._mdi_text == "L X+20 Y+20 Z+50 R0 FMAX", "Klick auf den Verlauf übernimmt den Satz")
	m.channel.reset()

	# ------------------------------------------------------------------ Manueller Betrieb: Bezugspunkt, S, F, M
	s.show_mode("manual")
	m.tool_x = 33.0
	m.tool_y = 12.0
	m.tool_z = 20.0
	m._sync_axes()
	s._tick()
	ok(s._man_val[0].text == "+33.000" and s._man_val[2].text == "+20.000", "Anzeige IST (%s / %s)" % [s._man_val[0].text, s._man_val[2].text])
	s._ask_datum(0)
	ok(s._bar_mode == "input" and m.typing(), "Bezugspunkt: Eingabefeld hat Tastaturfokus (typing)")
	s._bar_submit("0")
	ok(absf(m.pos().x) < 0.001 and absf(m.datum.x - 33.0) < 0.001, "Bezugspunkt X gesetzt (pos %s, datum %s)" % [m.pos(), m.datum])
	ok(s._bar_mode == "none", "Eingabezeile schließt nach ENT")
	s._tick()
	ok(s._man_val[0].text == "+0.000", "Anzeige folgt dem Bezugspunkt")
	s._set_pos_view(1)
	s._tick()
	ok(s._man_val[0].text == "+33.000", "Anzeige REF zeigt Maschinenposition (%s)" % s._man_val[0].text)
	s._set_pos_view(0)
	s._ask_s()
	s._bar_submit("2500")
	ok(is_equal_approx(m.rpm_set, 2500.0), "S eingegeben")
	s._ask_s()
	s._bar_submit("99999")
	ok(is_equal_approx(m.rpm_set, 2500.0) and s._bar_mode == "input", "S außerhalb des Bereichs wird abgelehnt")
	s._bar_cancel()
	s._ask_f()
	s._bar_submit("450")
	ok(is_equal_approx(m.feed_set, 450.0), "F eingegeben")
	s._tick()
	s._m_func(8)
	ok(m.coolant, "M8 schaltet KSS ein")
	s._m_func(9)
	ok(not m.coolant, "M9 schaltet KSS aus")
	s._ask_datum(2)
	s._bar_cancel()
	ok(not m.typing(), "nach Abbruch kein Eingabefeld mehr aktiv")

	# ------------------------------------------------------------------ Werkzeugtabelle
	m.spindle_speed = 0.0
	s.show_mode("tools")
	s._tick()
	ok(s._tl_list.item_count == m.POCKETS, "Werkzeugtabelle hat %d Zeilen" % m.POCKETS)
	var tt := item_texts(s._tl_list)
	ok(tt.contains("Messerkopf Ø63") and tt.contains("Schaftfräser Ø12") and tt.contains("Spiralbohrer Ø10"), "Tabelle zeigt das Magazin")
	ok(s._tl_list.get_item_text(3).contains("frei"), "freie Plätze sind markiert (%s)" % s._tl_list.get_item_text(3))
	s._tl_picked(2)
	s._tl_change()
	ok(m.changing, "Einwechseln startet den Werkzeugwechsel (%s | tool_t %d, spindle %s %.1f, door %s, estop %s, T2 %s)" % [s._msg, m.tool_t, m.spindle_on, m.spindle_speed, m.door_closed(), m.estop, m.magazine[1]])
	wait_change()
	s._tick()
	ok(m.tool_t == 3 and not m.changing, "T3 ist in der Spindel (T%d)" % m.tool_t)
	ok(s._tl_list.get_item_text(2).begins_with("►") and s._tl_list.get_item_text(2).contains("Spindel"), "Spindelwerkzeug ist markiert (%s)" % s._tl_list.get_item_text(2))
	s.show_mode("manual")
	s._tick()
	ok(s._man_info[0].text.begins_with("T3") and s._man_info[0].text.contains("Spiralbohrer Ø10"), "Manuell zeigt T3 mit Namen (%s)" % s._man_info[0].text)
	s._ask_t()
	s._bar_submit("9")
	ok(s._bar_mode == "input", "T9 ist nicht bestückt und wird abgelehnt")
	s._bar_submit("1")
	ok(m.changing, "T-Eingabe wechselt ein")
	wait_change()
	ok(m.tool_t == 1, "T1 eingewechselt")

	# ------------------------------------------------------------------ Mausklick auf Softkeys, Bedienleiste
	s.show_mode("manual")
	s._tick()
	var sk0: Button = s._sk_btns[0]
	ok(sk0.text == "M", "erster Softkey im Manuellen Betrieb ist M (%s)" % sk0.text)
	click(sk0)
	ok(s._sub == "m" and s._sk_btns[0].text.begins_with("M3"), "Mausklick auf den Softkey M öffnet die M-Funktionen (sub=%s, %s)" % [s._sub, s._sk_btns[0].text])
	click(s._sk_btns[3])
	ok(m.coolant, "Mausklick auf M8 schaltet KSS ein")
	click(s._sk_btns[7])
	ok(s._sub == "" and s._sk_btns[0].text == "M", "Mausklick auf ZURÜCK")
	click(s._b_kss)
	ok(not m.coolant, "Mausklick auf KSS schaltet aus")
	click(s._mode_btns["test"])
	ok(s.mode == "test", "Mausklick auf die Betriebsart Programm-Test")
	click(s._mode_btns["manual"])
	ok(s.mode == "manual", "Mausklick auf Manuell")
	s._ovr_f._apply(0.5)
	s._ovr_r._apply(0.25)
	ok(is_equal_approx(m.channel.feed_ovr, 0.5) and is_equal_approx(m.channel.rapid_ovr, 0.25), "Override-Regler wirken auf den Kanal")
	s._ovr_f._apply(2.0)
	ok(is_equal_approx(m.channel.feed_ovr, 1.5), "Vorschub-Override bis 150 %")
	m.channel.feed_ovr = 1.0
	m.channel.rapid_ovr = 1.0
	m.spindle_speed = 0.0
	s._door_toggle()
	frames(120)
	ok(m.door_open_ok(), "Tür-Taste öffnet die Tür")
	s._tick()
	ok(s._chips["door"]["lbl"].text == "TÜR AUF", "Kopfzeile zeigt Tür auf (%s)" % s._chips["door"]["lbl"].text)
	s._nc_start()
	ok(not m.channel.busy() and s._msg_cls == "warn", "NC-Start bei offener Tür wird gemeldet (%s)" % s._msg)
	s._door_toggle()
	frames(120)
	ok(m.door_closed(), "Tür-Taste schließt")

	# ------------------------------------------------------------------ Meldungen, Alarm, CE, Not-Halt
	m.message.emit("Testfehler", Color(1, 0.3, 0.25))
	ok(s._msg_cls == "err" and s._msg_lbl.text == "Testfehler", "Fehler in der Meldezeile")
	s._ce()
	ok(s._msg_lbl.text == "" and not s._msg_ce.visible, "CE löscht die Meldung")
	ok(s._log.size() >= 1 and s._log[0][0] == "Testfehler", "Meldung bleibt in der Liste")
	m.channel.state = "error"
	m.channel.alarm = "Prüfalarm"
	s._tick()
	ok(s._msg_lbl.text.contains("ALARM") and s._msg_lbl.text.contains("Prüfalarm") and s._chips["chan"]["lbl"].text == "ALARM", "Alarm des Kanals ist sichtbar")
	s._ce()
	ok(m.channel.state == "idle", "CE setzt den Alarm zurück")
	m.toggle_estop()
	s._tick()
	ok(s._msg_lbl.text.contains("NOT-HALT") and s._chips["estop"]["lbl"].text == "NOT-HALT", "Not-Halt ist sichtbar")
	m.toggle_estop()
	s._tick()
	ok(not s._msg_lbl.text.contains("NOT-HALT"), "Not-Halt quittiert")

	# ------------------------------------------------------------------ Ohne Strom
	m.power_off()
	await process_frame
	ok(not s.visible, "ohne Strom ist der Bildschirm aus")
	m.power_on(true)
	await process_frame
	ok(s.visible and s._power_msg, "nach dem Hochfahren: Strom unterbrochen, mit CE quittieren")
	s._tick()
	ok(s._msg_lbl.text.begins_with("Strom unterbrochen"), "Meldung Strom unterbrochen (%s)" % s._msg_lbl.text)
	s._ce()
	ok(s._msg_lbl.text == "", "CE quittiert Strom unterbrochen")

	print("CHECKS ", checks, " FAILS ", fails)
	quit(1 if fails > 0 else 0)
