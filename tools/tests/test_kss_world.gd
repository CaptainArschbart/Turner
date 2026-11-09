extends SceneTree
## Headless-Prüfung des KSS-Tanks in einer echten Welt: Konzentrat-Kosten, Kappung bei zu wenig Geld,
## einmalige Schaum-Strafe, NC-Alarm bei leerem Tank, Station öffnen und schließen.
## Aufruf: godot --headless --path . -s res://tools/tests/test_kss_world.gd
var checks := 0
var fails := 0


func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"unlock_all": true}
	var w = load("res://scenes/world.tscn").instantiate()
	w.autosave = false
	root.add_child(w)
	for i in 5:
		await process_frame
	w.money = 100000
	w.buy_equipment("cnc_lathe")
	ok(w.place_machine("cnc_lathe", Vector2(-1.0, 4.0), 0) == "", "CNC-Drehmaschine aufgestellt")
	var cnc = w.cnc_lathe
	await physics_frame
	var st = cnc.kss_station
	var tank: KssTank = cnc.kss
	ok(st != null and tank != null and st.world == w, "Station an der Welt angeschlossen")
	ok(st.get_prompt().contains("KSS auffüllen"), "Prompt")

	# --- Kosten: 2 L Konzentrat = 8 EUR, Wasser gratis
	tank.water = 20.0
	tank.concentrate = 0.0
	var m0: int = w.money
	tank.add_concentrate(2.0)
	ok(w.money == m0 - 8, "2 L Konzentrat kosten 8 EUR (%d)" % (m0 - w.money))
	m0 = w.money
	tank.add_water(5.0)
	ok(w.money == m0, "Wasser ist gratis")
	# Bruchteile: 0,1 L = 0,4 EUR, erst nach drei Zugaben ein voller Euro
	m0 = w.money
	for i in 3:
		tank.add_concentrate(0.1)
	ok(m0 - w.money == 1, "Bruchteile sammeln sich bis zum vollen Euro (%d)" % (m0 - w.money))

	# --- Kappung bei wenig Geld
	tank.water = 10.0
	tank.concentrate = 0.0
	tank.state = KssTank.State.NEUTRAL
	st._owed = 0.0
	w.money = 6
	var got := tank.add_concentrate(10.0)
	ok(absf(got - 1.5) < 0.001 and w.money == 0, "Mit 6 EUR gibt es nur 1,5 L (%.2f L, Kasse %d)" % [got, w.money])
	ok(tank.add_concentrate(1.0) == 0.0, "Ohne Geld kein Konzentrat")

	# --- Schaum-Strafe: einmalig, nur für neu zugegebene Überdosis
	w.money = 10000
	st._owed = 0.0
	tank.water = 30.0
	tank.concentrate = 0.0
	tank.state = KssTank.State.NEUTRAL
	tank.added_since_eval = 0.0
	tank.add_concentrate(5.4)
	var before: int = w.money
	tank.add_water(24.6)
	ok(tank.state == KssTank.State.ZU_DICK, "9 % ist ZU DICK")
	ok(before - w.money == 12, "Strafe 12 EUR beim Vollfüllen (%d)" % (before - w.money))
	tank.consume(6.0)
	before = w.money
	tank.add_water(6.0)
	ok(tank.state == KssTank.State.ZU_DICK, "Zustand bleibt ZU DICK")
	ok(w.money == before, "Reines Wasser-Nachfüllen kostet nichts (%d)" % (before - w.money))

	# --- NC-Alarm bei leerem Tank
	tank.load_state({"water": 0.0, "concentrate": 0.0, "state": 0})
	cnc.coolant = false
	var nc = cnc.nc
	cnc.door_latched = true
	nc.state = "run"
	nc._ops = [{"op": "kss", "on": true}]
	nc.step(0.01)
	ok(nc.state == "error" and nc.alarm.contains("KSS-Tank leer"), "M08 bei leerem Tank: NC-Alarm (%s / %s)" % [nc.state, nc.alarm])
	nc.reset()
	tank.load_state({"water": 0.2, "concentrate": 0.0, "state": 0})
	cnc.coolant = true
	ok(cnc.coolant, "Kühlung mit Restmenge an")
	nc.state = "run"
	nc._ops = [{"op": "kss", "on": true}]
	cnc.spindle_speed = 500.0
	cnc._step_kss(1000.0)
	ok(not cnc.coolant and nc.state == "error" and nc.alarm.contains("KSS-Tank leer"), "Tank leer im Lauf: Alarm und Stopp (%s)" % nc.state)
	nc.reset()
	cnc.spindle_speed = 0.0

	# --- Station öffnen und schließen
	var p = w.player
	ok(p.operating == null, "Spieler frei")
	st.interact(p)
	ok(p.operating == st and st._panel != null, "Station offen: Spieler gesperrt, Panel da")
	st._panel.close()
	await process_frame
	ok(p.operating == null and st._panel == null and st.player == null, "Panel zu: Spieler frei")
	st.interact(p)
	ok(p.operating == st, "Zweites Öffnen geht")
	st._panel.close()

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
