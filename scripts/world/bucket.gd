class_name Bucket
extends RefCounted
## Eimer für Späne: Modell aus models/bucket.glb, dazu die Späne darin je nach Füllstand. Der Inhalt ist ein
## ChipTray (CAPACITY kg), damit Sorte und Wert beim Entsorgen stimmen. Der Eimer steht als Shelf
## ("bucket") aufrecht am Boden oder hängt am Henkel in der Hand der Spielfigur.

const CAPACITY := 10.0            # kg Späne
const HEIGHT := 0.53              # mit Henkel
const BODY_HEIGHT := 0.33         # nur der Topf
const INNER_R := 0.12             # Radius der Späne im Topf


## Eimer mit Spänen als Knoten (Boden bei y = 0). hang = true: Ursprung am Henkel oben, der Eimer hängt nach unten.
static func make(fraction: float, hang := false, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Eimer"
	var model := Props.make("bucket")
	root.add_child(model)
	var fill := Build.cyl(root, INNER_R, 1.0, Vector3.ZERO, Build.mat(Color(0.62, 0.64, 0.68), 0.35, 0.85), Build.AXIS_Y, false, 16, INNER_R * 0.55)
	fill.name = "Fill"
	set_fill(root, fraction)
	root.scale = Vector3.ONE * scale
	if hang:
		model.position.y = -HEIGHT
		fill.position.y -= HEIGHT
		root.set_meta("hang", true)
	return root


## Füllstand 0..1 anzeigen: Zylinderstumpf, der mit der Füllung wächst und oben flach abschließt.
static func set_fill(root: Node3D, fraction: float) -> void:
	var fill := root.get_node_or_null("Fill") as MeshInstance3D
	if fill == null:
		return
	fill.visible = fraction > 0.001
	var h := maxf((BODY_HEIGHT - 0.06) * clampf(fraction, 0.0, 1.0), 0.01)
	fill.scale.y = h
	fill.position.y = 0.04 + h * 0.5 - (HEIGHT if root.has_meta("hang") else 0.0)


## Hinweistext zum Inhalt, z. B. "4 von 10 kg Stahlspäne".
static func describe(chips: ChipTray) -> String:
	var t := "%d von %d kg" % [int(round(chips.kg)), int(chips.capacity)]
	if not chips.is_empty():
		t += " %sspäne" % ChipTray.SORT_TITLES[chips.sort()]
	return t


## ChipTray aus einem Spielstand-Dictionary oder einem schon vorhandenen ChipTray.
static func chips_of(v) -> ChipTray:
	if v is ChipTray:
		return v
	var c := ChipTray.new(CAPACITY)
	if v is Dictionary:
		c.load_state(v)
	return c
