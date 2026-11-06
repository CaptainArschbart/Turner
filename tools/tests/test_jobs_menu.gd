extends SceneTree
## Werkstattkasse, Auftragsmenü und Schleifaufträge.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)
func tab_press() -> InputEventAction:
	var e := InputEventAction.new()
	e.action = "job_menu"
	e.pressed = true
	return e
func labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n.text)
	for c in n.get_children():
		labels(c, out)
func text_of(n: Node) -> String:
	var t := []
	labels(n, t)
	return "\n".join(PackedStringArray(t))
func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var menu = w.job_menu
	var co = w.company

	# Geld gehört der Werkstatt, nicht der Spielfigur
	w.money = 700
	ok(co.balance == 700, "Kasse liegt in der Werkstatt")
	co.balance = 650
	ok(w.money == 650, "Alle sehen dieselbe Kasse")
	var ps: Dictionary = p.get_state()
	ok(not ps.has("money") and not str(ps).contains("650"), "Spielfigur speichert kein Geld")
	var other = co
	other.balance -= 50
	ok(w.money == 600, "Ausgabe eines anderen Spielers wirkt für alle")
	w._refresh_hud()
	ok(w.hud._money.text.contains("Werkstattkasse: 600"), "Anzeige: " + w.hud._money.text)
	ok(not w.hud._money.text.contains("Kontostand"), "Kein persönlicher Kontostand mehr")
	w.office_pc.overlay.raw.refresh()
	ok(w.office_pc.overlay.raw._money.text.contains("Werkstattkasse"), "Am PC ebenso")
	w.office_pc.overlay.site_tab.refresh()
	ok(w.office_pc.overlay.site_tab._money.text.contains("Werkstattkasse"), "Im Tab Gebäude ebenso")
	# Spielstand: Maschinenpark
	ok(co.owns("lathe") and co.owns("mill"), "Alter Stand: Dreh- und Fräsmaschine")
	ok(not co.owns("round_grinder") and not co.owns("flat_grinder"), "Noch keine Schleifmaschine")
	co.add_machine("flat_grinder")
	w._apply_pending({"name": "T", "money": 5})
	ok(co.machines.is_empty(), "Neues Spiel: keine Maschinen")
	ok(w.money == 5, "Kasse aus dem Spielstand")
	w._apply_pending({"name": "T", "money": 5, "machines": ["lathe", "round_grinder"]})
	ok(co.owns("round_grinder") and not co.owns("mill"), "Maschinenpark aus dem Spielstand")
	w._apply_pending({"name": "T", "money": 600, "unlock_all": true})

	# Tab öffnet beim Gehen, schließt wieder
	ok(not menu.visible, "Menü ist zu")
	menu._input(tab_press())
	ok(menu.visible, "Tab öffnet das Menü")
	ok(p.operating == menu, "Spielfigur steht still")
	ok(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE or DisplayServer.get_name() == "headless", "Mauszeiger frei")
	var titles := []
	for i in menu.tabs.get_tab_count():
		titles.append(menu.tabs.get_tab_title(i))
	for t in ["Drehaufträge", "Fräsaufträge", "Rundschleifaufträge", "Flachschleifaufträge", "Bohraufträge", "Erodieraufträge"]:
		ok(titles.has(t), "Kategorie " + t)
	menu._input(tab_press())
	ok(not menu.visible and p.operating == null, "Tab schließt")
	var pe := InputEventAction.new()
	pe.action = "pause"
	pe.pressed = true
	menu.open()
	menu._input(pe)
	ok(not menu.visible, "Esc schließt")
	ok(not w.pause_menu.visible, "Esc öffnet dabei nicht das Pause-Menü")
	p.pitch = 0.33
	menu.open()
	menu.close()
	ok(absf(p.pitch - 0.33) < 0.001, "Blickrichtung bleibt")

	# An einer Maschine oder am PC öffnet es nicht
	w.lathe.interact(p)
	menu._input(tab_press())
	ok(not menu.visible, "An der Drehmaschine kein Menü")
	var axis0: int = w.lathe.hw_axis
	w.lathe.stop_operating()
	await process_frame
	w.mill.interact(p)
	menu._input(tab_press())
	ok(not menu.visible, "An der Fräsmaschine kein Menü")
	w.mill.stop_operating()
	await process_frame
	w.mill.open_levers(p)
	menu._input(tab_press())
	ok(not menu.visible, "Am Bedienfeld kein Menü")
	w.mill.close_levers()
	await process_frame
	w.office_pc.interact(p)
	menu._input(tab_press())
	ok(not menu.visible, "Am PC kein Menü")
	w.office_pc.stop_using()
	await process_frame
	ok(InputMap.has_action("job_menu") and InputMap.has_action("hw_axis"), "Tab bleibt an der Maschine die Handradachse")
	ok(axis0 == w.lathe.hw_axis, "Menü-Taste hat die Achse nicht verstellt")

	# Inhalte
	w.job_index = 0
	w.mill_job_index = 0
	w.stock = []
	w.deliveries = []
	w.accepted = ["lathe:0", "mill:0"]
	w.tracked = "lathe:0"
	menu.open()
	var lathe_text := text_of(menu.pages["lathe"])
	var mill_text := text_of(menu.pages["mill"])
	ok(lathe_text.contains("Auftrag 1") and lathe_text.contains("Ø60"), "Drehauftrag steht im Menü")
	ok(mill_text.contains("Fräsauftrag 1"), "Fräsauftrag steht im Menü")
	ok(lathe_text.contains("kaufen"), "Status: Material fehlt: " + lathe_text)
	menu.close()
	# Ohne Schleifmaschine keine Schleifaufträge und keine Anforderung
	for j in Jobs.LIST:
		ok(not Jobs.describe(j, JobBoard.grind_active(j, co)).contains("Geschliffen"), "Keine Schleifanforderung ohne Maschine: " + str(j["title"]))
	for j in MillJobs.LIST:
		ok(not MillJobs.describe(j, JobBoard.grind_active(j, co)).contains("Geschliffen"), "Keine Schleifanforderung ohne Maschine: " + str(j["title"]))
	menu.open()
	var round_text := text_of(menu.pages["round_grinder"])
	ok(round_text.contains("Rundschleifmaschine") and round_text.contains("erst, wenn"), "Hinweis fehlende Maschine: " + round_text)
	ok(text_of(menu.pages["drill"]).contains("Standbohrmaschine"), "Bohren: keine Maschine")
	co.machines = ["lathe", "mill"]
	ok(text_of(menu.pages["edm"]).contains("Erodiermaschine"), "Erodieren: keine Maschine")
	menu.close()
	# Beide Schleifarten kommen in den Aufträgen vor, passend zur Fläche
	var kinds := {}
	for j in Jobs.LIST + MillJobs.LIST:
		if j.has("grind"):
			kinds[j["grind"]["type"]] = true
			ok(int(j["grind"]["reward"]) > 0 and float(j["grind"]["rz"]) > 0.0, "Schleifdaten vollständig: " + str(j["title"]))
	ok(kinds.has("round") and kinds.has("flat"), "Runde und ebene Flächen kommen vor")
	# Rundschleifmaschine: nur Rundflächen werden zu Aufträgen
	var round_job: Dictionary = Jobs.LIST[6]
	var flat_lathe: Dictionary = Jobs.LIST[1]
	var flat_mill: Dictionary = MillJobs.LIST[0]
	ok(round_job["grind"]["type"] == "round", "Präzisionswelle: Rundfläche")
	ok(flat_lathe["grind"]["type"] == "round", "Drehteile werden rund geschliffen")
	ok(flat_mill["grind"]["type"] == "flat", "Fräsauftrag: ebene Fläche")
	co.add_machine("round_grinder")
	ok(JobBoard.grind_active(round_job, co), "Rundschleifmaschine: Rundfläche wird verlangt")
	ok(not JobBoard.grind_active(flat_mill, co), "Rundschleifmaschine: ebene Fläche nicht")
	ok(Jobs.describe(round_job, JobBoard.grind_active(round_job, co)).contains("Geschliffen (Rundfläche)"), "Auftragstext nennt die Rundfläche")
	ok(JobBoard.entries("round_grinder", round_job, flat_mill, co).size() == 1, "Rundschleifauftrag entsteht")
	ok(JobBoard.entries("flat_grinder", round_job, flat_mill, co).is_empty(), "Kein Flachschleifauftrag ohne Maschine")
	ok(JobBoard.entries("round_grinder", Jobs.LIST[0], flat_mill, co).is_empty(), "Kein Schleifauftrag, wenn kein Auftrag es verlangt")
	co.add_machine("flat_grinder")
	ok(JobBoard.grind_active(flat_mill, co), "Flachschleifmaschine: ebene Fläche wird verlangt")
	ok(MillJobs.describe(flat_mill, JobBoard.grind_active(flat_mill, co)).contains("Geschliffen (ebene Fläche)"), "Fräsauftrag nennt die ebene Fläche")
	var both_flat: Array = JobBoard.entries("flat_grinder", flat_lathe, flat_mill, co)
	ok(both_flat.size() == 1, "Nur der Fräsauftrag ergibt einen Flachschleifauftrag")
	ok(JobBoard.entries("round_grinder", Jobs.LIST[0], flat_mill, co).is_empty(), "Ebene Flächen ergeben keinen Rundschleifauftrag")
	ok(str(both_flat[0]["text"]).contains("Fräsauftrag 1"), "Schleifauftrag nennt den Ursprung")
	# Sichtbar im Menü
	w.mill_job_index = 0
	menu.open()
	ok(text_of(menu.pages["flat_grinder"]).contains("Fräsauftrag 1"), "Flachschleifauftrag im Menü")
	ok(text_of(menu.pages["round_grinder"]).contains("Gerade verlangt kein Auftrag"), "Rundschleifmaschine ohne Bedarf")
	menu.close()
	w._refresh_hud()
	ok(w.mill_hud._job.text.contains("Geschliffen"), "Anzeige an der Fräse nennt die Schleifanforderung")
	# Maschine fehlt: keine Aufträge dafür
	co.machines = ["mill"]
	ok(JobBoard.entries("lathe", Jobs.LIST[0], flat_mill, co).is_empty(), "Ohne Drehmaschine keine Drehaufträge")
	co.machines = ["lathe"]
	ok(JobBoard.entries("mill", Jobs.LIST[0], flat_mill, co).is_empty(), "Ohne Fräsmaschine keine Fräsaufträge")
	co.machines = ["lathe", "mill"]
	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
