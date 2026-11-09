extends SceneTree
## Ausspannen, Kiste, Qualitätsmanagement, Wiedereinspannen und angepinnte Zeichnungen.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func machined_part(l) -> void:
	l.new_workpiece(60.0, 160.0)
	l.profile.fill(28.0)
	for i in l.machined.size():
		l.machined[i] = 1


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var l = w.lathe
	w.money = 100000
	if not w.day_started:
		w.start_day()
	var err := ""
	if not w.accepted.has("lathe:0"):
		err = w.accept_job("lathe:0")
	ok(err == "" and w.accepted.has("lathe:0"), "Drehauftrag angenommen: " + err)
	w.select_job("lathe:0")

	# ---------------------------------------------------- Abgabetaste an der Maschine verkauft nichts mehr
	machined_part(l)
	var money0: int = w.money
	w._submit_hint()
	ok(w.money == money0 and l.has_part, "Abgabetaste verkauft nichts")

	# ---------------------------------------------------- Ausspannen über das Fenster
	w.ask_clamp(l, false)
	ok(w.clamp_dialog.visible and w.clamp_dialog.clamped and w.clamp_dialog._out.visible, "Linksklick aufs Teil: Fenster mit Ausspannen")
	w.clamp_dialog.take_out()
	ok(not w.clamp_dialog.visible and not l.has_part and p.carrying_part(), "Ausgespannt, Teil in den Händen")
	ok(str(p.carry["key"]) == "lathe:0" and float(p.carry["res"]["score"]) >= 0.999, "Prüfergebnis hängt am Teil")
	ok(w.money == money0, "Ausspannen allein bringt kein Geld")

	# ---------------------------------------------------- In die Kiste und wieder heraus
	if not w.layout.benches.has("lathe"):
		w.inventory["bench"] = 1
		w.place_bench("", Vector2(0.6, 0.35), 2)
	var b: Dictionary = w.layout.benches["lathe"]
	w.inventory["crate_m"] = 1
	err = w.place_crate(-1, "crate_m", b["pos"], int(b["rot"]))
	ok(err == "", "Kiste auf die Werkbank gestellt: " + err)
	var ci: int = w.layout.crates.size() - 1
	ok(ci >= 0 and w.layout.crate_is_on_top(w.layout.crates[ci]), "Kiste steht auf der Platte")
	ok(w.crate_prompt(ci).contains("legen"), "Hinweis: Teil in die Kiste legen")
	ok(w.crate_put(ci) == "" and p.carry.is_empty() and w.layout.crates[ci]["items"].size() == 1, "Fertigteil liegt in der Kiste")
	ok(w.crate_nodes[ci]._content.get_child_count() == 1, "Teil in der Kiste zu sehen")
	ok(w.crate_prompt(ci).contains("nehmen"), "Hinweis: Teil nehmen")
	ok(w.crate_take(ci) == "" and p.carrying_part(), "Wieder in den Händen")
	ok(w.store_carried() != "", "Fertigteile gehören nicht ins Regal")

	# ---------------------------------------------------- Abgabe im Qualitätsmanagement
	ok(w.qm_prompt().contains("abgeben"), "QM bietet die Abgabe an")
	var reward: int = int(JobBoard.job_of("lathe:0")["reward"])
	ok(w.qm_submit() == "", "Im QM abgegeben")
	ok(w.money == money0 + reward and p.carry.is_empty(), "QM bezahlt, Hände frei")
	ok(not w.accepted.has("lathe:0"), "Auftrag erledigt")

	# ---------------------------------------------------- Unbearbeitet ausspannen gibt Rohmaterial
	l.new_workpiece(60.0, 160.0)
	ok(w.unclamp_part(l) == "" and str(p.carry["kind"]) == Materials.KIND_ROUND and bool(p.carry.get("sawn", false)), "Rohteil bleibt Rohmaterial")
	ok(w.finish_clamp(l, false, 8.0) == "" and l.has_part and p.carry.is_empty(), "Rohteil wieder eingespannt")

	# ---------------------------------------------------- Teil wieder einspannen behält die Kontur
	machined_part(l)
	l.profile[0] = 20.0
	ok(w.unclamp_part(l) == "" and p.carrying_part() and str(p.carry["key"]) == "", "Ohne Auftrag ausgespannt")
	ok(w.finish_clamp(w.mill, false, 10.0) != "" and p.carrying_part(), "Rundes Teil nicht in den Schraubstock")
	ok(w.finish_clamp(l, false, 12.0) == "" and l.has_part and not l.is_untouched(), "Teil wieder im Futter")
	ok(absf(l.profile[0] - 20.0) < 0.01 and l.clamp_depth == 12.0, "Kontur und Spanntiefe stimmen")
	ok(w.unclamp_part(l) == "" and p.carrying_part(), "Erneut ausgespannt")
	ok(w.qm_prompt().contains("verschrotten"), "QM: ohne Auftrag nur verschrotten")
	var money1: int = w.money
	ok(w.qm_submit() == "" and p.carry.is_empty() and w.money == money1, "Verschrottet, kein Geld")
	l.clear_workpiece()

	# ---------------------------------------------------- Fräsen: Teil mit Lage und Unterseite
	var m = w.mill
	m.new_workpiece(100.0, 60.0, 40.0)
	m.untouched = false
	m.reclamp(20.0, true)
	ok(m.flipped, "Kopfüber gespannt")
	ok(w.unclamp_part(m) == "" and p.carrying_part() and str(p.carry["shape"]) == "block", "Frästeil ausgespannt")
	ok(w.finish_clamp(l, false, 10.0) != "", "Eckiges Teil nicht ins Futter")
	ok(w.finish_clamp(m, false, 20.0) == "" and m.has_part and m.flipped, "Wieder eingespannt, Lage bleibt")
	m.clear_workpiece()

	# ---------------------------------------------------- Zeichnung in die Hand und anpinnen
	var job: Dictionary = JobBoard.job_of("lathe:1")
	ok(w.take_drawing(job) == "" and p.carrying_drawing(), "Zeichnung in der Hand")
	ok(w.take_drawing(job) != "", "Nur eine Zeichnung zur Zeit")
	var anchor := StaticBody3D.new()
	w.add_child(anchor)
	anchor.global_position = Vector3(0, 1.4, -1.0)
	w.pin_drawing(anchor, Vector3(0, 1.4, -0.9), Vector3(0, 0, 1))
	ok(w.pins.size() == 1 and p.carry.is_empty(), "Zeichnung angepinnt, Hände frei")
	var pin = w.pins[0]
	ok(pin.global_transform.basis.z.is_equal_approx(Vector3(0, 0, 1)) and pin.global_transform.basis.y.is_equal_approx(Vector3.UP), "Blatt hängt aufrecht an der Fläche")
	anchor.position.x += 0.3
	await process_frame
	ok(absf(pin.global_position.x - 0.3) < 0.01, "Blatt fährt mit der Fläche mit (z. B. Maschinentür)")
	w.pin_drawing(anchor, Vector3(0, 0, 0), Vector3.UP)
	ok(w.pins.size() == 1, "Ohne Zeichnung in der Hand passiert nichts")
	ok(w.take_drawing(job) == "", "Zweite Zeichnung")
	w.pin_drawing(null, Vector3(1, 0.9, 1), Vector3.UP)
	ok(w.pins.size() == 2 and absf(w.pins[1].global_transform.basis.z.dot(Vector3.UP) - 1.0) < 0.001, "Auch auf waagrechte Flächen")
	var states: Array = JSON.parse_string(JSON.stringify(w._pin_states()))
	ok(states.size() == 2 and states[0]["xf"].size() == 12 and str(states[0]["job"]["title"]) == str(job["title"]), "Angepinnte Zeichnungen im Spielstand")
	ok(w.pin_prompt(pin).contains("Abnehmen"), "Hinweis am Blatt")
	w.pin_click(pin)
	ok(w.pins.size() == 1 and p.carrying_drawing(), "Wieder abgenommen")
	ok(p.right_click_focus() and p.carry.is_empty(), "Rechtsklick legt die Zeichnung weg")

	print("CHECKS ", checks, " FAILS ", fails)
	quit(1 if fails > 0 else 0)
