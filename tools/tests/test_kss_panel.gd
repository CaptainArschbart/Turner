extends SceneTree
## Headless-Prüfung des KSS-Panels (Der Chemiemeister): Ventile, Zeiger, Sperre, Banner, Schließen.
## Benutzt das echte KssTank (scripts/machine/kss_tank.gd) mit gesetzten Füllständen.
## Aufruf: godot --headless --path . -s res://tools/tests/test_kss_panel.gd

var checks := 0
var fails := 0
var closed_count := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


func _tank(w := 0.0, c := 0.0) -> KssTank:
	var t := KssTank.new()
	t.water = w
	t.concentrate = c
	return t


func _run(p: KssPanel, secs: float) -> void:
	for i in int(secs / 0.05):
		p._process(0.05)


func _make(tank: KssTank) -> KssPanel:
	var p := KssPanel.new()
	root.add_child(p)
	p.setup(tank, "CNC-Drehmaschine E50")
	p.closed.connect(func() -> void: closed_count += 1)
	return p


func _initialize() -> void:
	await process_frame
	# --- Leerer Tank, Wasser laufen lassen
	var t := _tank()
	var p := _make(t)
	ok(p._state_label.text.begins_with("Aktueller Zustand:"), "zeigt aktuellen Zustand")
	p.set_valve(KssPanel.WATER, true)
	_run(p, 0.5)
	var w1: float = t.water
	ok(w1 > 0.5 and w1 < 3.0, "Wasser rampt an (%.2f L nach 0,5 s)" % w1)
	_run(p, 1.0)
	ok(t.water > w1 + 4.0, "Wasser fließt voll ~6 L/s (%.2f L)" % t.water)
	p.set_valve(KssPanel.WATER, false)
	_run(p, 0.5)
	var w2: float = t.water
	_run(p, 0.5)
	ok(is_equal_approx(t.water, w2), "Wasserhahn zu: kein Durchfluss mehr")
	ok(p._stats.text.contains("Wasser"), "Anzeige aktualisiert sich: " + p._stats.text)

	# --- Feindosieren
	var t2 := _tank()
	var pf := _make(t2)
	pf.fine = true
	pf.set_valve(KssPanel.WATER, true)
	_run(pf, 2.0)
	var tn := _tank()
	var pn := _make(tn)
	pn.set_valve(KssPanel.WATER, true)
	_run(pn, 2.0)
	ok(t2.water < tn.water * 0.4, "Feindosierung deutlich langsamer (%.2f vs %.2f)" % [t2.water, tn.water])

	# --- Zeiger folgt der Konzentration
	var t3 := _tank()
	var p3 := _make(t3)
	p3.set_valve(KssPanel.WATER, true)
	_run(p3, 1.5)
	p3.set_valve(KssPanel.WATER, false)
	_run(p3, 0.5)
	p3.set_valve(KssPanel.CONC, true)
	_run(p3, 1.2)
	p3.set_valve(KssPanel.CONC, false)
	_run(p3, 1.5)
	ok(t3.concentration() > 1.0, "Konzentration steigt (%.2f %%)" % t3.concentration())
	ok(absf(p3.needle_value() - t3.concentration()) < 0.05, "Zeiger folgt (%.2f vs %.2f)" % [p3.needle_value(), t3.concentration()])
	ok(p3._digital.text.contains(","), "Digitalwert mit Dezimalkomma: " + p3._digital.text)

	# --- Optimal: 6,5 % Mischung, mit Wasser auffüllen bleibt ~OPTIMAL (3,9 / 60 = 6,5 %)
	var t4 := _tank(16.1, 3.9)
	var p4 := _make(t4)
	ok(not p4.is_locked(), "nicht gesperrt bei 20 L")
	p4.set_valve(KssPanel.WATER, true)
	_run(p4, 10.0)
	ok(t4.is_full(), "Tank voll")
	ok(p4.is_locked(), "Sperre nach Voll")
	ok(p4._btn[0].disabled and p4._btn[1].disabled, "Ventilknöpfe gesperrt")
	ok(p4.banner_text().contains("OPTIMAL") and p4.banner_text().contains("+10 %"), "Banner optimal: " + p4.banner_text())
	var before: float = t4.water
	p4.set_valve(KssPanel.WATER, true)
	_run(p4, 1.0)
	ok(t4.water == before, "gesperrt: kein weiterer Zufluss")

	# --- Zu dünn
	var p5 := _make(_tank(20.0, 0.0))
	p5.set_valve(KssPanel.WATER, true)
	_run(p5, 10.0)
	ok(p5.banner_text().contains("ZU DÜNN") and p5.banner_text().contains("Doppelter"), "Banner zu dünn: " + p5.banner_text())

	# --- Zu dick
	var p6 := _make(_tank(20.0, 10.0))
	p6.set_valve(KssPanel.WATER, true)
	_run(p6, 10.0)
	ok(p6.banner_text().contains("ZU DICK") and p6.banner_text().contains("schäumt"), "Banner zu dick: " + p6.banner_text())

	# --- Neutral: 3,3 L auf 60 L = 5,5 %
	var p7 := _make(_tank(20.0, 3.3))
	p7.set_valve(KssPanel.WATER, true)
	_run(p7, 10.0)
	ok(p7.banner_text().contains("IM RAHMEN") and p7.banner_text().contains("kein Bonus"), "Banner neutral: " + p7.banner_text())

	# --- Schon voller Tank beim Öffnen
	var p8 := _make(_tank(60.0, 0.0))
	ok(p8.is_locked() and p8._hint.text.contains("voll"), "Tank beim Öffnen voll: Hinweis und Sperre")

	# --- Kein Geld
	var t9 := _tank(10.0, 0.0)
	t9.afford = func(_l: float) -> float: return 0.0
	var p9 := _make(t9)
	p9.set_valve(KssPanel.CONC, true)
	_run(p9, 1.0)
	ok(p9._warn.text.contains("Kein Geld"), "Warnung Kein Geld: " + p9._warn.text)

	# --- Fertig und Esc schließen
	var n0 := closed_count
	p.close()
	ok(closed_count == n0 + 1, "closed bei Fertig")
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	p9._input(ev)
	ok(closed_count == n0 + 2, "closed bei Esc (pause)")

	print("kss_panel: %d Prüfungen, %d Fehler" % [checks, fails])
	quit(1 if fails > 0 else 0)
