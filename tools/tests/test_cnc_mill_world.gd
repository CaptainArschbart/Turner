extends SceneTree
## CNC-Fräsmaschine in der Spielwelt: Skill und Kauf, Aufstellen, eigene Werkbank und Werkzeuge, Fräsauftrag mit
## Beispielprogramm, Tür beim Spannen, Umstellen bei laufendem Programm, Speichern und Laden, Debug-Taste beim Tippen.
## Aufruf: Godot --headless --path . -s res://tools/tests/test_cnc_mill_world.gd
var checks := 0
var fails := 0
const DT := 1.0 / 60.0
const AT := Vector2(-6.0, 4.0)
const BENCH_AT := Vector2(-7.2, 6.85)


func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


## Programm takten (ein Takt = 1/60 s), bis es nicht mehr läuft.
func run_channel(m, max_frames := 60000) -> int:
	var n := 0
	while m.channel.state == "run" and n < max_frames:
		m._physics_process(DT)
		n += 1
	return n


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var co = w.company
	w.money = 200000

	# ---------------------------------------------------- Skill und Kauf
	ok(Layout.SPECS.has("cnc_mill") and int(Layout.SPECS["cnc_mill"]["price"]) == 30000, "Layout kennt die CNC-Fräsmaschine für 30000")
	ok(Layout.SPECS["cnc_mill"]["foot"] == load("res://scripts/machine/cnc_mill.gd").FOOT, "Grundfläche im Layout = CncMill.FOOT")
	ok(Layout.BENCH_MACHINES.has("cnc_mill") and not Layout.SCALED.has("cnc_mill"), "Mit Werkbank, nicht vergrößert")
	ok(Skills.EQUIPMENT["cnc_mill"] == "mill_cnc" and Skills.machine_skill("cnc_mill") == "mill_cnc", "Skill mill_cnc gehört zur Maschine")
	ok(Skills.tool_family("cnc_mill") == "mill" and Skills.tool_family("mill") == "mill", "Gemeinsamer Werkzeugbaum mit der Fräse")
	ok(not Skills.NODES["mill_cnc"].has("soon"), "Skill ist freigegeben")
	ok(not co.skills.has("mill_cnc"), "Alter Spielstand schenkt den Skill nicht")
	ok(w.buy_equipment("cnc_mill") != "" and not w.inventory.has("cnc_mill"), "Ohne Skill nicht kaufbar")
	ok(co.skills.unlock("mill_cnc", true) == "", "Skill lässt sich freischalten")
	var money0: int = w.money
	ok(w.buy_equipment("cnc_mill") == "" and w.inventory["cnc_mill"] == 1 and w.money == money0 - 30000, "Mit Skill kaufbar (30000 EUR)")
	ok(w.buy_equipment("cnc_mill") != "", "Nur eine Maschine")

	# ---------------------------------------------------- Aufstellen
	ok(w.place_machine("cnc_mill", AT, 0) == "", "Aufstellen: " + w.layout.check_machine("cnc_mill", AT, 0))
	var c = w.cnc_mill
	ok(c != null and c.MACHINE_ID == "cnc_mill", "Echte CNC-Fräsmaschine")
	ok(c.position.is_equal_approx(Vector3(AT.x, 0, AT.y)) and is_equal_approx(c.scale.x, 1.0), "Steht am Platz, nicht vergrößert")
	ok(co.owns("cnc_mill") and co.owns_kind("mill") and w.mill_huds.has("cnc_mill"), "Gehört der Firma, eigene Anzeige")
	var only := Company.new()
	only.add_machine("cnc_mill")
	ok(only.owns_kind("mill") and not only.owns_kind("lathe"), "Fräsaufträge gehen auch nur mit der CNC-Fräse")
	ok(c.tool_mount != null and c.tool_stock == co.tools["cnc_mill"] and c.skills == co.skills, "Werkzeugbestand und Halterung verbunden")
	ok(co.tools["cnc_mill"] != co.tools["mill"], "Eigener Werkzeugbestand")
	ok(w.layout.check_machine("cnc_mill", Vector2(0.5, -1.0), 0) != "", "Auf der Drehmaschine nicht erlaubt")
	ok(w.machine_busy("cnc_mill") == false, "Steht still")

	# ---------------------------------------------------- Werkbank und Werkzeuge
	ok(w.buy_equipment("bench") == "", "Werkbank kaufen")
	ok(w.place_bench("", BENCH_AT, 0) == "", "Werkbank vor der CNC-Fräse: " + w.layout.check_bench(BENCH_AT, 0))
	ok(w.layout.benches.has("cnc_mill") and w.bench_nodes.has("cnc_mill"), "Eigene Werkbank")
	ok(w.bench_nodes["cnc_mill"].machine == c, "Werkbank gehört der CNC-Fräse")
	var f12_mill: int = co.tools["mill"].count("F12")
	ok(w.buy_tool("cnc_mill", "F12", "hm") == "" and w.buy_tool("cnc_mill", "MK63", "hm") == "", "Werkzeuge für die CNC-Fräse kaufen")
	ok(co.tools["cnc_mill"].count("F12") == 1 and co.tools["cnc_mill"].has("MK63") and co.tools["mill"].count("F12") == f12_mill, "Liegen bei der CNC-Fräse, der Bestand der Fräse bleibt")
	ok(not c.has_tool("F12"), "Noch nicht an der Maschine")
	ok(w.tool_price("cnc_mill", "F12", "hm") == w.tool_price("mill", "F12", "hm"), "Preis wie an der Fräse")
	ok(w.buy_tool("cnc_mill", "F12", "hss") != "", "HSS erst mit dem Skill der Fräswerkzeuge")

	# ---------------------------------------------------- Hochfahren und Werkzeug einsetzen
	c.power_on(true)
	c.estop = false
	ok(c.is_ready(), "Hochgefahren")
	c.set_door(false, true)
	ok(c.door_open_ok() and c.clamp_blocked() == "", "Tür offen: Spannen erlaubt")
	p.set_held(c, "F12")
	c.hand_click(p)
	ok(c.has_tool("F12") and c.pocket_of("F12") > 0, "Werkzeug von Hand in die Spindel: zählt im Magazin")
	ok(c.magazine_set(3, "MK63") and c.has_tool("MK63"), "Werkzeug im Magazin zählt als vorhanden")
	var f_t: int = c.pocket_of("F12")

	# ---------------------------------------------------- Fräsauftrag annehmen
	var job_key := "mill:3"
	ok(w.accept_job(job_key) == "", "Fräsauftrag 4 annehmen")
	w.select_job(job_key)
	ok(w.mill_job_index == 3 and w.has_job("mill") and w.has_job("cnc_mill"), "Auftrag gilt für beide Fräsmaschinen")
	ok(w.job_kind("cnc_mill") == "mill" and w.job_kind("cnc_lathe") == "lathe" and w.job_kind("drill") == "drill", "Auftragsart der Maschine")
	ok(w._active_job("cnc_mill") == w._active_job("mill"), "Gemeinsamer Fräsauftrag")
	var job: Dictionary = w._active_job("cnc_mill")

	# ---------------------------------------------------- Teil einspannen nur bei offener Tür
	var sz: Array = job["size"]
	var raw := {"material": str(job["material"]), "kind": Materials.KIND_CUT, "d": 0.0, "w": float(sz[1]), "h": float(sz[2]), "l": float(sz[0])}
	c.set_door(true, true)
	p.clear_carry()
	p.clear_held()
	p.set_carry(raw.duplicate())
	var err: String = w.clamp_carried(c)
	ok(err != "" and not c.has_part and not p.carry.is_empty(), "Tür zu: Einspannen verweigert (%s)" % err)
	ok(w._clamp_precheck(c) != "", "Auch die Vorprüfung vor der Spanntiefe")
	ok(w._mill_take_part(c).contains("tür"), "Taste Neues Teil meldet die Tür")
	c.set_door(false, true)
	ok(w._clamp_precheck(c) == "", "Tür offen: Vorprüfung ohne Fehler")
	w.stock.clear()
	err = w.clamp_carried(c)
	ok(err == "" and c.has_part and p.carry.is_empty(), "Tür offen: eingespannt (%s)" % err)
	ok(c.untouched and c.material == str(job["material"]) and c.block_l == float(sz[0]), "Rohteil passend")
	ok(w._key_in(c) == job_key, "Teil gehört zum Fräsauftrag")
	# Ausspannen mit zu: verweigert
	c.set_door(true, true)
	ok(w.unclamp_part(c) != "" and c.has_part, "Tür zu: Ausspannen verweigert")
	c.set_door(false, true)

	# ---------------------------------------------------- Bedienen: Anzeige und Hinweise
	c.interact(p)
	for i in 3:
		await process_frame
	ok(p.operating == c, "Spieler bedient die CNC-Fräse")
	c.stop_operating()
	await process_frame
	ok(p.operating == null, "Wieder frei")

	# ---------------------------------------------------- Beispielprogramm TASCHE laufen lassen
	c.set_door(true, true)
	c.tool_z = 100.0
	c._sync_axes()
	for i in c.programs.size():
		if str(c.programs[i]["name"]) == "TASCHE":
			c.prog_sel = i
	ok(c.prog_sel >= 0 and str(c.selected_program()["name"]) == "TASCHE", "Beispielprogramm TASCHE vorhanden")
	c.magazine.fill("")
	c.clear_spindle()
	ok(c.magazine_set(2, "F12") and c.magazine_set(1, "MK63"), "Magazin bestückt (T1 Messerkopf, T2 Schaftfräser)")
	ok(c.nc_start(), "Programm startet")
	ok(w.machine_busy("cnc_mill"), "Läuft: Maschine ist beschäftigt")
	ok(w.place_machine("cnc_mill", AT, 0).contains("Programm"), "Umstellen bei laufendem Programm verweigert")
	ok(w.layout.machines["cnc_mill"]["pos"] == AT, "Lage unverändert")
	var frames := run_channel(c)
	ok(c.channel.state == "done", "Programm fertig nach %d Takten (%s)" % [frames, c.channel.alarm])
	c.channel.reset()
	for i in 900:
		c._physics_process(DT)
	ok(not w.machine_busy("cnc_mill"), "Fertig und ausgelaufen: nicht mehr beschäftigt")
	var res: Dictionary = c.evaluate(job)
	ok(res["ok"] == res["total"], "Tasche besteht den Auftrag (%d von %d)" % [res["ok"], res["total"]])
	ok(not c.untouched, "Teil ist bearbeitet")

	# ---------------------------------------------------- Abgeben und Vergütung
	c.set_door(true, true)
	var cash0: int = w.money
	var xp0: int = co.skills.xp
	w._on_mill_submit(c)
	ok(c.has_part and w.accepted.has(job_key), "Tür zu: Abgeben verweigert, nichts verloren")
	c.set_door(false, true)
	w._on_mill_submit(c)
	ok(not c.has_part and not w.accepted.has(job_key), "Teil ausgespannt und abgegeben")
	ok(w.money == cash0 + w._pay(float(job["reward"])), "Vergütung erhalten: %d EUR" % (w.money - cash0))
	ok(co.skills.xp > xp0, "Erfahrung gutgeschrieben")
	ok(not w.accepted.has(job_key) and w.mill_job_index != 3, "Auftrag erledigt, Auswahl rückt auf den nächsten")

	# ---------------------------------------------------- Umstellen, Werkbank folgt
	var bench_before: Vector2 = w.layout.benches["cnc_mill"]["pos"]
	var move := Vector2(-0.5, 0.0)
	ok(w.place_machine("cnc_mill", AT + move, 0) == "", "Umstellen im Stillstand: " + w.layout.check_machine("cnc_mill", AT + move, 0))
	ok(w.layout.benches["cnc_mill"]["pos"].is_equal_approx(bench_before + move), "Werkbank wandert mit")
	ok(w.place_machine("cnc_mill", AT, 0) == "", "Zurück an den Platz")

	# ---------------------------------------------------- Speichern und Laden
	c.set_door(false, true)
	c.set_datum(0, 12.5)
	c.save_program("MEIN", ["BEGIN PGM MEIN MM", "L Z+100 R0 FMAX", "END PGM MEIN MM"])
	var n_prog: int = c.programs.size()
	var sel: int = c.prog_sel
	var mag_saved: Array = Array(c.magazine)
	var tool_t_saved: int = c.tool_t
	var datum_saved: Vector3 = c.datum
	w.accepted = [job_key]
	w.mill_job_index = 3
	var saved: Dictionary = JSON.parse_string(JSON.stringify(w.save_data()))
	ok(saved["machine_states"].has("cnc_mill") and saved["tools"].has("cnc_mill"), "Maschine und Werkzeuge im Spielstand")
	ok(saved["layout"]["machines"].has("cnc_mill") and saved["layout"]["benches"].has("cnc_mill"), "Lage und Werkbank im Spielstand")
	w._apply_pending({"name": "Neu", "money": 2500})
	await process_frame
	ok(w.cnc_mill == null and not w.mill_huds.has("cnc_mill") and not w.bench_nodes.has("cnc_mill"), "Neues Spiel: keine CNC-Fräse")
	ok(not w.company.owns("cnc_mill") and w.company.tools["cnc_mill"].total() == 0, "Und kein Werkzeug")
	w._apply_pending(saved)
	await process_frame
	var c2 = w.cnc_mill
	ok(c2 != null and c2.MACHINE_ID == "cnc_mill" and w.company.owns("cnc_mill") and w.company.owns_kind("mill"), "CNC-Fräse aus dem Spielstand")
	ok(c2.position.is_equal_approx(Vector3(AT.x, 0, AT.y)), "Steht wieder am Platz")
	ok(w.layout.benches.has("cnc_mill") and w.bench_nodes.has("cnc_mill") and w.bench_nodes["cnc_mill"].machine == c2, "Werkbank steht wieder dort")
	ok(w.company.tools["cnc_mill"].has("F12") and w.company.tools["cnc_mill"].has("MK63"), "Werkzeugbestand zurück")
	ok(c2.tool_stock == w.company.tools["cnc_mill"] and c2.skills == w.company.skills, "Maschine hängt am Bestand")
	ok(Array(c2.magazine) == mag_saved and c2.tool_t == tool_t_saved, "Magazin und T-Nummer zurück")
	ok(c2.pocket_of("F12") == f_t or c2.pocket_of("F12") == 2, "Schaftfräser auf seinem Platz")
	ok(c2.programs.size() == n_prog and c2.prog_sel == sel and not c2.program("MEIN").is_empty(), "Programme zurück")
	ok(c2.datum.is_equal_approx(datum_saved), "Bezugspunkt zurück")
	ok(c2.powered and c2.is_ready() and c2.channel.state != "run", "Strom an, kein Programm läuft")
	ok(w.accepted == [job_key] and w.has_job("cnc_mill") and w.mill_job_index == 3, "Fräsauftrag bleibt angenommen")
	ok(w.mill_huds.has("cnc_mill"), "Anzeige wieder da")

	# ---------------------------------------------------- Debug-Taste und Tippen am Bildschirm
	var key := InputEventKey.new()
	key.keycode = KEY_ASCIICIRCUM
	key.physical_keycode = KEY_QUOTELEFT
	key.pressed = true
	ok(not c2.typing(), "Am Bildschirm wird nicht getippt")
	var menu_before: bool = w.debug_menu.visible
	w._input(key)
	ok(w.debug_menu.visible != menu_before, "Debug-Taste schaltet das Menü")
	w._input(key)
	ok(w.debug_menu.visible == menu_before, "und wieder zurück")
	var le := LineEdit.new()
	c2.screen_vp.add_child(le)
	le.grab_focus()
	await process_frame
	if c2.typing():
		w._input(key)
		ok(w.debug_menu.visible == menu_before, "Beim Tippen im Bildschirm bleibt das Debug-Menü zu")
	else:
		print("   Hinweis: Fokus im SubViewport ließ sich headless nicht setzen, Tipp-Sperre nicht geprüft")
	le.release_focus()
	le.queue_free()
	await process_frame
	ok(not c2.typing(), "Fokus wieder frei")

	print("CHECKS ", checks, " FAILS ", fails)
	quit(1 if fails > 0 else 0)
