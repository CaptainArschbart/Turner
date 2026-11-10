extends SceneTree
## Bearbeitete Teile im Recyclingcontainer entsorgen: richtige Sorte, Gewicht, Rückfrage bei offenem
## Auftrag, vorbearbeitete Teile, voller Container. Dazu das Schild an der Hallenwand.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 5000, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	w.start_day()
	var steel: String = w.lathe.material
	var st: int = w.CONTAINER_SORTS.find("stahl")
	var alu: int = w.CONTAINER_SORTS.find("aluminium")
	ok(str(ChipTray.SORTS.get(str(Materials.group_of(steel)["id"]), "")) == "stahl", "Drehteil aus Stahl: " + steel)

	# ------------------------------------------------ Teil ohne Auftrag
	var part := {"kind": "part", "key": "", "machine": "lathe", "material": steel, "part": {}, "res": {},
		"title": "Teil ohne Auftrag", "shape": "round", "d": 40.0, "l": 100.0}
	p.set_carry(part.duplicate(true))
	ok(p.carrying_part(), "Teil in den Händen")
	var kg: float = w._scrap_kg(p.carry)
	ok(absf(kg - 0.985) < 0.05, "Gewicht Ø40 x 100 Stahl etwa 1 kg: %.3f" % kg)
	ok(w.container_prompt(alu).contains("gehört in den Container Stahl"), "Falscher Container: " + w.container_prompt(alu))
	w.container_click(alu)
	ok(p.carrying_part() and w.containers[alu].is_empty(), "Im Aluminium-Container nicht entsorgt")
	ok(w.container_prompt(st).contains("entsorgen"), "Hinweis am Stahl-Container: " + w.container_prompt(st))
	var before: float = w.containers[st].kg
	w.container_click(st)
	ok(not p.carrying_part() and p.hands_free(), "Teil ist weg, Hände frei")
	ok(absf(w.containers[st].kg - before - kg) < 0.001, "Gewicht im Container: %.2f -> %.2f kg" % [before, w.containers[st].kg])

	# ------------------------------------------------ Teil zu einem offenen Auftrag: erst Rückfrage
	var job_part := part.duplicate(true)
	job_part["key"] = "lathe:test"
	job_part["res"] = {"ok": true}
	job_part["title"] = "Welle"
	w.accepted.append("lathe:test")
	p.set_carry(job_part)
	before = w.containers[st].kg
	w.container_click(st)
	ok(p.carrying_part() and is_equal_approx(w.containers[st].kg, before), "Erster Klick: nur Rückfrage")
	ok(w.container_prompt(st).contains("Wirklich entsorgen"), "Hinweis fragt nach: " + w.container_prompt(st))
	w.container_click(st)
	ok(not p.carrying_part() and w.containers[st].kg > before, "Zweiter Klick: entsorgt")
	ok(w.accepted.has("lathe:test"), "Auftrag bleibt offen")
	w.accepted.erase("lathe:test")

	# ------------------------------------------------ Vorbearbeitetes Teil (Schleifen) und Fräsblock
	var semi := {"kind": "semi", "key": "", "type": "flat", "title": "Platte", "part": {"material": steel}, "material": steel,
		"d": 0.0, "l": 100.0, "w": 50.0, "h": 20.0}
	p.set_carry(semi)
	ok(p.carrying_semi(), "Vorbearbeitetes Teil in den Händen")
	w.container_click(st)
	ok(p.hands_free(), "Vorbearbeitetes Teil entsorgt")
	var block := {"kind": "part", "key": "", "machine": "mill", "material": steel, "part": {}, "res": {},
		"title": "Teil ohne Auftrag", "shape": "block", "l": 80.0, "w": 60.0, "h": 30.0}
	p.set_carry(block)
	ok(absf(w._scrap_kg(p.carry) - 1.13) < 0.05, "Fräsblock 80 x 60 x 30 etwa 1,1 kg: %.3f" % w._scrap_kg(p.carry))
	w.container_click(st)
	ok(p.hands_free(), "Fräsblock entsorgt")

	# ------------------------------------------------ Voller Container
	var c: ChipTray = w.containers[st]
	c.add(str(Materials.group_of(steel)["id"]), c.capacity)
	p.set_carry(part.duplicate(true))
	w.container_click(st)
	ok(p.carrying_part(), "Voller Container nimmt nichts mehr")
	p.clear_carry()

	# ------------------------------------------------ Schild
	var sign: Node3D = w.find_child("TimoSchild", true, false)
	ok(sign != null, "Schild hängt in der Halle")
	if sign:
		var labels := sign.find_children("*", "Label3D", true, false)
		ok(labels.size() == 1 and labels[0].text == "Timo kann keinen Freistisch drehen", "Text auf dem Schild")
		ok(labels[0].auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED, "Schild wird nicht übersetzt")
		ok(absf(sign.global_position.z + 7.98) < 0.05 and sign.global_position.y > 2.0, "An der Nordwand über Kopfhöhe: %s" % sign.global_position)

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
