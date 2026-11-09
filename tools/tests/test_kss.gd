extends SceneTree
## Headless-Prüfung des KSS-Minigames „Der Chemiemeister“: Mischungsrechnung, Bewertung an den Grenzen,
## Effekte (Verschleiß, Tempo, Schaum, Strafe, Kosten), Verbrauch, leerer Tank, Speichern/Laden.
## Aufruf: godot --headless --path . -s res://tools/tests/test_kss.gd

var checks := 0
var fails := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


## Tank mit genau `pct` Prozent Konzentrat, voll (60 L) befüllt.
func full_tank(pct: float) -> KssTank:
	var t := KssTank.new()
	t.water = 0.0
	t.concentrate = 0.0
	var c := KssTank.CAPACITY * pct / 100.0
	t.add_concentrate(c)
	t.add_water(KssTank.CAPACITY - c)
	return t


func _initialize() -> void:
	await process_frame

	# --- Startwert und Rechnung
	var t := KssTank.new()
	ok(absf(t.fill_fraction() - 0.7) < 0.001 and absf(t.concentration() - 6.5) < 0.001 and t.state == KssTank.State.NEUTRAL, "Start: 70 %, 6,5 %, NEUTRAL")
	var r := KssTank.new()
	r.water = 0.0
	r.concentrate = 0.0
	r.add_water(54.0)
	r.add_concentrate(3.6)
	ok(absf(r.concentration() - 6.25) < 0.05, "54 L Wasser + 3,6 L Konzentrat = 6,25 %% (%.3f)" % r.concentration())
	var e := KssTank.new()
	e.water = 0.0
	e.concentrate = 0.0
	ok(e.concentration() == 0.0 and e.is_empty(), "Leerer Tank: 0 % und leer")

	# --- Begrenzung auf die Kapazität
	var cap := KssTank.new()
	var added := cap.add_water(1000.0)
	ok(absf(added - 18.0) < 0.001 and cap.is_full(), "Wasser wird auf 60 L begrenzt (%.2f L zugefügt)" % added)
	ok(cap.add_water(5.0) == 0.0 and cap.add_concentrate(5.0) == 0.0, "Voller Tank nimmt nichts mehr")

	# --- Bewertung an den Grenzen
	var cases := {4.9: KssTank.State.ZU_DUENN, 5.5: KssTank.State.NEUTRAL, 6.0: KssTank.State.OPTIMAL,
		7.0: KssTank.State.OPTIMAL, 7.5: KssTank.State.NEUTRAL, 8.1: KssTank.State.ZU_DICK,
		5.0: KssTank.State.NEUTRAL, 8.0: KssTank.State.NEUTRAL}
	for pct in cases:
		var tk := full_tank(float(pct))
		ok(tk.state == cases[pct], "%.1f %% -> %s (ist %s)" % [pct, KssTank.state_title(cases[pct]), KssTank.state_title(tk.state)])

	# --- Bewertung genau einmal beim Erreichen von 100 %
	var ev := KssTank.new()
	var evs: Array = []
	ev.evaluated.connect(func(s: int): evs.append(s))
	ev.add_water(5.0)
	ok(evs.is_empty(), "Unter 100 %: keine Bewertung")
	ev.add_water(13.0)
	ok(ev.is_full() and evs.size() == 1, "Bei 100 %: Tank voll (42 + 5 + 13 L), genau eine Bewertung")

	# --- Zustand bleibt, bis zur nächsten Befüllung
	var keep := full_tank(6.5)
	ok(keep.state == KssTank.State.OPTIMAL, "6,5 % ist OPTIMAL")
	keep.consume(10.0)
	ok(keep.state == KssTank.State.OPTIMAL, "Zustand bleibt nach Verbrauch")
	keep.add_water(10.0)
	ok(keep.state == KssTank.State.NEUTRAL, "Nur Wasser nachgefüllt: 5,4 %% -> neu bewertet (%s)" % KssTank.state_title(keep.state))

	# --- Effekte
	var thin := full_tank(4.0)
	var opt := full_tank(6.5)
	var thick := full_tank(9.0)
	var neutral := full_tank(5.5)
	ok(thin.wear_factor() == 2.0 and opt.wear_factor() == 1.0 and neutral.wear_factor() == 1.0, "Verschleiß x2 nur bei ZU DÜNN")
	ok(absf(opt.speed_factor() - 1.1) < 0.0001 and thin.speed_factor() == 1.0 and neutral.speed_factor() == 1.0, "Tempo x1,1 nur bei OPTIMAL")
	ok(thick.foaming() and not opt.foaming() and not thin.foaming(), "Schaum nur bei ZU DICK")
	ok(neutral.wear_factor() == 1.0 and neutral.speed_factor() == 1.0 and not neutral.foaming(), "NEUTRAL ohne Effekt")
	# Strafe: Überdosis über 6,5 % x 4 EUR x 2. 9 % von 60 L = 5,4 L, Sollwert 3,9 L -> 1,5 L -> 12 EUR
	ok(absf(thick.overdose_liters() - 1.5) < 0.001, "Überdosis 1,5 L (%.3f)" % thick.overdose_liters())
	ok(absf(thick.foam_penalty() - 12.0) < 0.01, "Schaum-Strafe 12 EUR (%.2f)" % thick.foam_penalty())
	ok(opt.foam_penalty() < 0.001, "Keine Strafe bei 6,5 %")
	ok(KssTank.state_title(KssTank.State.OPTIMAL) == "OPTIMAL" and KssTank.state_title(KssTank.State.ZU_DUENN) == "ZU DÜNN"
		and KssTank.state_title(KssTank.State.ZU_DICK) == "ZU DICK" and KssTank.state_title(KssTank.State.NEUTRAL) == "IM RAHMEN", "Titel")

	# --- Konzentratkosten und Geld-Kappung
	var paid := KssTank.new()
	paid.water = 0.0
	paid.concentrate = 0.0
	var bill := [0.0]
	paid.concentrate_added.connect(func(l: float): bill[0] += l * KssTank.PRICE_PER_L)
	paid.add_concentrate(2.0)
	ok(absf(bill[0] - 8.0) < 0.001, "2 L Konzentrat kosten 8 EUR")
	paid.add_water(5.0)
	ok(absf(bill[0] - 8.0) < 0.001, "Wasser ist gratis")
	var budget := [3.0]    # nur 3 L bezahlbar
	paid.afford = func(_l: float) -> float: return budget[0]
	var got := paid.add_concentrate(10.0)
	ok(absf(got - 3.0) < 0.001, "Zufluss wird aufs Budget gekappt (%.2f L)" % got)
	budget[0] = 0.0
	ok(paid.add_concentrate(1.0) == 0.0, "Ohne Geld kein Konzentrat")

	# --- Verbrauch anteilig
	var use := KssTank.new()
	var c0 := use.concentration()
	use.consume(10.5)
	ok(absf(use.volume() - 31.5) < 0.001 and absf(use.concentration() - c0) < 0.001, "Verbrauch anteilig: Konzentration bleibt")
	use.consume(1000.0)
	ok(use.is_empty() and use.volume() == 0.0, "Tank lässt sich leer fahren")

	# --- Speichern/Laden
	var src := full_tank(9.0)
	var dst := KssTank.new()
	dst.load_state(src.to_state())
	ok(absf(dst.water - src.water) < 0.0001 and absf(dst.concentrate - src.concentrate) < 0.0001 and dst.state == KssTank.State.ZU_DICK, "to_state/load_state")

	# --- Integration an der CNC-Drehmaschine
	var l = load("res://scripts/machine/lathe.gd").new()
	root.add_child(l)
	await process_frame
	ok(l.kss != null, "CNC-Drehmaschine hat KSS-Tank")
	if l.kss != null:
		ok(absf(l.kss.fill_fraction() - 0.7) < 0.001 and l.kss.state == KssTank.State.NEUTRAL, "Maschine startet mit 70 % und NEUTRAL")
		ok(l.kss_wear() == 1.0 and l.kss_speed() == 1.0, "Ohne Kühlung keine KSS-Faktoren")
		l.kss.load_state({"water": 40.0, "concentrate": 2.6, "state": int(KssTank.State.ZU_DUENN)})
		l.coolant = true
		ok(l.coolant, "Kühlmittel lässt sich einschalten")
		ok(l.kss_wear() == 2.0, "ZU DÜNN: Verschleiß x2 an der Maschine")
		l.kss.load_state({"water": 40.0, "concentrate": 2.6, "state": int(KssTank.State.OPTIMAL)})
		ok(absf(l.kss_speed() - 1.1) < 0.0001, "OPTIMAL: Tempo x1,1 an der Maschine")
		# Verbrauch bei drehender Spindel
		l.spindle_speed = 500.0
		var v0: float = l.kss.volume()
		l._step_kss(60.0)
		ok(absf(v0 - l.kss.volume() - KssTank.CONSUME_PER_MIN) < 0.001, "Verbrauch 0,4 L/min bei laufendem Kühlmittel")
		l.spindle_speed = 0.0
		v0 = l.kss.volume()
		l._step_kss(60.0)
		ok(absf(v0 - l.kss.volume()) < 0.0001, "Kein Verbrauch bei stehender Spindel")
		# Speichern/Laden der Maschine
		l.kss.load_state({"water": 20.0, "concentrate": 3.0, "state": int(KssTank.State.ZU_DICK)})
		var st: Dictionary = l.get_state()
		ok(st.has("kss"), "get_state hat Schlüssel kss")
		var l2 = load("res://scripts/machine/lathe.gd").new()
		root.add_child(l2)
		await process_frame
		l2.set_state(st)
		ok(absf(l2.kss.water - 20.0) < 0.001 and l2.kss.state == KssTank.State.ZU_DICK, "set_state stellt den Tank wieder her")
		var old: Dictionary = st.duplicate()
		old.erase("kss")
		l2.set_state(old)
		ok(absf(l2.kss.fill_fraction() - 0.7) < 0.001 and l2.kss.state == KssTank.State.NEUTRAL, "Alter Spielstand bekommt den Startwert")
		# Leerer Tank sperrt das Kühlmittel
		l2.coolant = false
		l2.kss.load_state({"water": 0.0, "concentrate": 0.0, "state": int(KssTank.State.ZU_DICK)})
		l2.coolant = true
		ok(not l2.coolant, "Leerer Tank: Kühlmittel lässt sich nicht einschalten")
		ok(l2.kss.state == KssTank.State.ZU_DICK, "Zustand bleibt beim leeren Tank")
		# Konventionelle Maschine hat keinen Tank
		var conv = load("res://scripts/machine/lathe.gd").new()
		conv.conventional = true
		root.add_child(conv)
		await process_frame
		ok(conv.kss == null and conv.kss_speed() == 1.0, "Konventionelle Drehmaschine ohne KSS-Tank")
		conv.coolant = true
		ok(conv.coolant, "Konventionell: Kühlmittel ohne Tank einschaltbar")
		# Station
		if l.e50:
			ok(l.kss_station != null, "E50 hat sichtbare KSS-Station")
			if l.kss_station != null:
				ok(l.kss_station.get_prompt().contains("KSS auffüllen"), "Prompt: KSS auffüllen")

	print("test_kss: %d Prüfungen, %d Fehler" % [checks, fails])
	quit(1 if fails > 0 else 0)
