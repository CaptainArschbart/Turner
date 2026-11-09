extends SceneTree
## Eimer: aufnehmen, aufrecht abstellen, Späne aus der Maschinenwanne schöpfen (bis 10 kg), in Spänebehälter
## und Container kippen, Kapazitätsgrenzen, Speichern und Laden in der Hand und abgestellt.
var checks := 0
var fails := 0
func ok(c: bool, w: String) -> void:
	checks += 1
	if not c:
		fails += 1
		print("FAIL ", w)


func idx_of(w, id: String) -> int:
	for i in w.layout.shelves.size():
		if str(w.layout.shelves[i]["size"]) == id:
			return i
	return -1


func _initialize() -> void:
	await process_frame
	root.get_node("GameState").pending = {"name": "Test", "money": 250, "job": 0, "parts": 0, "play_time": 0.0, "starter": true}
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)
	for i in 5:
		await process_frame
	var p = w.player
	var bi := idx_of(w, "bucket")
	ok(bi >= 0, "Starter-Eimer steht in der Werkstatt oder im Lager")
	ok(w.layout.shelves[bi]["chips"] is ChipTray and (w.layout.shelves[bi]["chips"] as ChipTray).capacity == Bucket.CAPACITY, "Eimer hat 10 kg Kapazität")
	ok(w.bucket_prompt(bi).contains("aufnehmen"), "Hinweis auf dem Eimer: " + w.bucket_prompt(bi))
	var n_before: int = w.layout.shelves.size()

	# Aufnehmen mit E: Hände belegt, Eintrag aus dem Layout, Eimer in Ego und an der Figur
	(w.shelf_nodes[bi] as Shelf).interact(p)
	ok(p.carrying_bucket() and not p.hands_free(), "Eimer in der Hand")
	ok(w.layout.shelves.size() == n_before - 1 and idx_of(w, "bucket") == -1, "Eimer nicht mehr am Boden")
	ok(p.arms.item.get_child_count() > 0 and p._bucket_body != null and p._bucket_body.is_inside_tree(), "Eimer in Ego-Ansicht und an der Figur")
	# Mit belegten Händen lässt sich nichts anderes aufnehmen
	ok(not p.hands_free(), "Hände belegt")

	# Spänewanne der Drehmaschine: 12 kg, der Eimer nimmt 10 kg
	var lathe = w.lathe
	lathe.tray.clear()
	lathe.tray.add("baustahl", 12.0)
	w.bucket_scoop(lathe)
	ok(absf(p.bucket_chips().kg - 10.0) < 0.01, "10 kg im Eimer: %f" % p.bucket_chips().kg)
	ok(absf(lathe.tray.kg - 2.0) < 0.01, "2 kg bleiben in der Wanne: %f" % lathe.tray.kg)
	ok(p.bucket_chips().sort() == "stahl" and p.bucket_chips().value() > 0, "Eimer führt Sorte und Wert")
	w.bucket_scoop(lathe)
	ok(absf(p.bucket_chips().kg - 10.0) < 0.01 and absf(lathe.tray.kg - 2.0) < 0.01, "Voller Eimer nimmt nichts mehr")
	# Fräse und Säge haben auch eine Wanne
	var mill = w.mill
	ok(mill.get("tray") is ChipTray, "Fräse hat eine Spänewanne")

	# Sorte mischen geht nicht
	var alu := ChipTray.new(Bucket.CAPACITY)
	ok(alu.add("aluminium", 3.0) > 0.0 and not p.bucket_chips().takes("aluminium"), "Aluminium passt nicht zu Stahlspänen")

	# Prompt und Haltetext
	await process_frame
	ok(Bucket.describe(p.bucket_chips()).contains("10 von 10"), "Füllstand im Text: " + Bucket.describe(p.bucket_chips()))

	# Speichern in der Hand
	var ps: Dictionary = p.get_state()
	ok(ps["carry"]["chips"] is Dictionary and absf(float(ps["carry"]["chips"]["kg"]) - 10.0) < 0.01, "Spielstand enthält den Füllstand")
	p.clear_carry()
	ok(p.hands_free() and p._bucket_body == null, "Eimer losgelassen")
	p.set_state(ps)
	ok(p.carrying_bucket() and absf(p.bucket_chips().kg - 10.0) < 0.01, "Eimer samt Inhalt nach dem Laden in der Hand")

	# Spänebehälter (drinnen): kippen, so viel hineinpasst
	var bin_chips := ChipTray.new(float(ChipBin.SIZES["bin_s"]["kg"]))
	bin_chips.add("baustahl", 20.0)
	w.layout.bins.append({"size": "bin_s", "pos": Vector2(15.0, -17.0), "rot": 0, "chips": bin_chips, "out": false})
	w._rebuild_stands()
	var bn: int = w.layout.bins.size() - 1
	ok(w.bin_prompt(bn).contains("Eimer leeren"), "Hinweis auf dem Behälter: " + w.bin_prompt(bn))
	w.bin_click(bn)
	ok(absf(bin_chips.kg - 25.0) < 0.01 and absf(p.bucket_chips().kg - 5.0) < 0.01, "Behälter nimmt nur 5 kg: %f / %f" % [bin_chips.kg, p.bucket_chips().kg])
	w.bin_click(bn)
	ok(absf(bin_chips.kg - 25.0) < 0.01 and absf(p.bucket_chips().kg - 5.0) < 0.01, "Voller Behälter nimmt nichts")
	var empty_bin := ChipTray.new(float(ChipBin.SIZES["bin_l"]["kg"]))
	w.layout.bins.append({"size": "bin_l", "pos": Vector2(15.0, -14.0), "rot": 0, "chips": empty_bin, "out": false})
	w._rebuild_stands()
	w.bin_click(w.layout.bins.size() - 1)
	ok(absf(empty_bin.kg - 5.0) < 0.01 and p.bucket_chips().is_empty(), "Rest in den zweiten Behälter")
	ok(w.bin_prompt(w.layout.bins.size() - 1).contains("in den Eimer nehmen"), "Leerer Eimer: Hinweis Späne nehmen")
	w.bin_click(w.layout.bins.size() - 1)
	ok(empty_bin.is_empty() and absf(p.bucket_chips().kg - 5.0) < 0.01, "Leerer Eimer nimmt Späne aus dem Behälter")
	w.bin_click(bn)
	ok(absf(bin_chips.kg - 25.0) < 0.01 and absf(p.bucket_chips().kg - 5.0) < 0.01, "Voller Eimer nimmt nicht nach, kippt in vollen Behälter nichts")
	w.bin_click(w.layout.bins.size() - 1)
	ok(absf(empty_bin.kg - 5.0) < 0.01 and p.bucket_chips().is_empty(), "Wieder ausgekippt")
	bin_chips.clear()
	bin_chips.add("baustahl", 22.0)
	w.bin_click(bn)
	ok(absf(p.bucket_chips().kg - 10.0) < 0.01 and absf(bin_chips.kg - 12.0) < 0.01, "Höchstens 10 kg aus dem Behälter: %f / %f" % [p.bucket_chips().kg, bin_chips.kg])
	w.bin_click(bn)
	ok(absf(bin_chips.kg - 22.0) < 0.01 and p.bucket_chips().is_empty(), "Voller Eimer kippt wieder aus: %f / %f" % [p.bucket_chips().kg, bin_chips.kg])
	bin_chips.clear()
	bin_chips.add("baustahl", 25.0)

	# Container im Hof
	lathe.tray.clear()
	lathe.tray.add("baustahl", 8.0)
	w.bucket_scoop(lathe)
	var ci := -1
	for k in w.containers.size():
		if (w.containers[k] as ChipTray).only == "stahl":
			ci = k
	ok(ci >= 0, "Stahl-Container im Hof")
	var before := (w.containers[ci] as ChipTray).kg
	w.container_click(ci)
	ok(absf((w.containers[ci] as ChipTray).kg - before - 8.0) < 0.01 and p.bucket_chips().is_empty(), "In den Container gekippt")

	# Abstellen: aufrecht am Boden, samt Inhalt
	lathe.tray.add("baustahl", 4.0)
	w.bucket_scoop(lathe)
	var spot := Vector2(21.0, -12.0)
	ok(w.bucket_drop(Vector2(-200.0, -200.0)) != "" and p.carrying_bucket(), "Außerhalb nicht abstellbar")
	ok(w.bucket_drop(spot) == "", "Eimer abgestellt")
	ok(p.hands_free() and p._bucket_body == null, "Hände frei")
	bi = idx_of(w, "bucket")
	ok(bi >= 0 and absf((w.layout.shelves[bi]["chips"] as ChipTray).kg - 4.0) < 0.01, "Eintrag mit Inhalt 4 kg")
	ok(int(w.layout.shelves[bi]["rot"]) == 0, "Eimer steht aufrecht (Drehung 0)")
	await process_frame
	var node: Shelf = w.shelf_nodes[bi]
	ok(node.chips != null and node.find_child("Fill", true, false) != null and (node.find_child("Fill", true, false) as Node3D).visible, "Späne im Eimer sichtbar")

	# Speichern abgestellt
	var saved: Dictionary = w.layout.to_state()
	var found := false
	for s in saved["shelves"]:
		if str(s["size"]) == "bucket" and absf(float(s["chips"]["kg"]) - 4.0) < 0.01:
			found = true
	ok(found and bool(saved["starter_bucket"]), "Spielstand: Eimer mit Füllstand, Starter-Flag gesetzt")
	var restored = Bucket.chips_of(saved["shelves"][saved["shelves"].size() - 1].get("chips", {}))
	ok(restored is ChipTray, "Füllstand lässt sich laden")

	# Q mit dem Eimer in der Hand stellt ihn ab (über die Figur)
	p.global_position = Vector3(18.0, 0.05, -12.0)
	(w.shelf_nodes[bi] as Shelf).interact(p)
	ok(p.carrying_bucket() and absf(p.bucket_chips().kg - 4.0) < 0.01, "Wieder aufgenommen, Inhalt bleibt")
	p.drop()
	ok(not p.carrying_bucket() and idx_of(w, "bucket") >= 0, "Ablegen-Taste stellt den Eimer ab")

	print("CHECKS %d FAILS %d" % [checks, fails])
	quit()
