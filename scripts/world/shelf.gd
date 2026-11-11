class_name Shelf
extends Node3D
## Frei aufgestellte Ausstattung ohne eigene Funktion: Holzregale aus models/non_machine_parts.glb, dazu
## Europalette, Gasflasche, Sackkarre und Hubwagen aus models/transport_items.glb. Wird am PC gekauft (oder
## gehört zur Startausstattung) und im Baumodus aufgestellt.
## lager: darf auch im Lager stehen. shop: false = nicht im PC-Einkauf, nur Startausstattung.

const SIZES := {
	"shelf_wide": {"title": "Holzregal breit", "price": 160, "foot": Vector2(1.12, 0.52), "height": 2.28},
	"shelf_narrow": {"title": "Holzregal schmal", "price": 100, "foot": Vector2(0.6, 0.52), "height": 2.28},
	"pallet": {"title": "Europalette", "price": 15, "foot": Vector2(1.58, 1.06), "height": 0.22, "lager": true,
		"text": "Holzpalette, steht in Lager oder Werkstatt. Leere Paletten lassen sich von Hand aufnehmen und stapeln."},
	"gas_bottle": {"title": "Gasflasche", "price": 90, "foot": Vector2(0.27, 0.27), "height": 1.39, "lager": true,
		"text": "Druckgasflasche für später. Steht in Lager oder Werkstatt, noch ohne Funktion."},
	"hand_truck": {"title": "Sackkarre", "price": 0, "foot": Vector2(0.7, 0.6), "height": 1.4, "lager": true, "shop": false},
	"bucket": {"title": "Eimer", "price": 15, "foot": Vector2(0.34, 0.32), "height": 0.53, "lager": true,
		"text": "Eimer für Späne (10 kg). Mit E aufnehmen, Linksklick auf die Maschine füllt ihn, Linksklick auf einen Spänebehälter kippt ihn aus."},
	"pallet_jack": {"title": "Hubwagen", "price": 0, "foot": Vector2(2.47, 0.73), "height": 1.39, "lager": true, "shop": false},
	"forklift": {"title": "Gabelstapler", "price": 2500, "foot": Vector2(3.21, 1.15), "height": 2.16, "lager": true,
		"text": "Gabelstapler mit 1,8 m Hubhöhe. Mit E einsteigen, mit WASD fahren, Pfeil hoch / runter hebt die Gabel, Pfeil links / rechts schiebt sie seitlich, Bild auf / ab neigt das Hubgerüst. Nimmt ganze Palettenstapel auf."},
}
## Test: Ein Gabelstapler steht einmalig in der Lagerhalle (der erste freie dieser Plätze, Drehung in 90°-Schritten)
const STARTER_FORKLIFT := [[Vector2(16.0, -15.5), 0], [Vector2(19.0, -15.5), 0], [Vector2(16.0, -12.5), 0], [Vector2(15.0, -18.0), 0]]
## Startausstattung im Lager: [Teil, x, z, Drehung in 90°-Schritten]
const STARTER := [
	["pallet", 15.0, -22.3, 0], ["pallet", 16.8, -22.3, 0], ["pallet", 18.6, -22.3, 0],
	["pallet_jack", 16.5, -20.5, 0], ["hand_truck", 20.5, -22.4, 0],
]

## Möglicher Platz für den Starter-Eimer im Lager (der erste freie)
const STARTER_BUCKET := [Vector2(22.0, -21.0), Vector2(21.8, -19.6), Vector2(13.6, -21.0), Vector2(13.6, -19.6)]

## Höchstens so viele leere Paletten auf einem Stapel (rund 2,2 m)
const MAX_STACK := 10
## Hubwagen: Mitte der Last auf der Gabel (Längsrichtung vom Mittelpunkt des Modells) und Hubhöhe
const JACK_LOAD_X := 0.42
const JACK_LIFT := 0.07
## Aufbau der Europalette im Modell (Meter): Klötze 3 x 3 unter der Deckplatte, dazwischen die Öffnungen
const PALLET_BLOCK_H := 0.16                    # Höhe der Klötze, darüber beginnt die Deckplatte
const PALLET_BLOCKS_X := [[-0.77, -0.60], [-0.095, 0.095], [0.60, 0.77]]      # entlang der langen Seite
const PALLET_BLOCKS_Z := [[-0.51, -0.38], [-0.095, 0.095], [0.38, 0.51]]      # entlang der kurzen Seite

var index := 0
var size_id := "shelf_wide"
var stack := 1                    # Paletten: so viele liegen hier übereinander
var chips: ChipTray               # Eimer: Späne darin (gehört dem Eintrag in layout.shelves)
var cargo := 0                    # Hubwagen: so viele Paletten liegen auf der Gabel
var cargo_cross := false          # Hubwagen: Last liegt quer (lange Seite quer zur Gabel)
var lift := 0.0                   # Gabelstapler: Gabelhöhe
var load_rot := 0                 # Gabelstapler: Drehung der Last zur Gabel in 90°-Schritten
var fork_shift := 0.0             # Gabelstapler: Seitenschieber
var fork_tilt := 0.0              # Gabelstapler: Neigung des Hubgerüsts
var world: Node                   # Spielwelt: pallet_prompt(i), pallet_click(i) per E


static func foot(id: String) -> Vector2:
	return SIZES[id]["foot"]


## Grundfläche des Hubwagens in seinen Koordinaten (x entlang der Gabel), mit Last breiter und länger.
static func jack_rect(load_n: int, cross: bool) -> Rect2:
	var f: Vector2 = SIZES["pallet_jack"]["foot"]
	var r := Rect2(-f * 0.5, f)
	if load_n > 0:
		var pf: Vector2 = SIZES["pallet"]["foot"]
		if cross:
			pf = Vector2(pf.y, pf.x)
		r = r.merge(Rect2(Vector2(JACK_LOAD_X - pf.x * 0.5, -pf.y * 0.5), pf))
	return r


func _ready() -> void:
	_build()
	# Lose Gegenstände liegen auf den Böden, den Paletten und dem Material, nicht auf der Hülle
	Solid.add(self)


func _build() -> void:
	var s: Dictionary = SIZES[size_id]
	var h := float(s["height"])
	var n := maxi(stack, 1) if size_id == "pallet" else 1
	var f: Vector2 = s["foot"]
	if size_id == "pallet_jack":
		add_child(Props.make(size_id))
		var load_h := 0.0
		if cargo > 0:
			var holder := Node3D.new()
			holder.position = Vector3(JACK_LOAD_X, JACK_LIFT, 0)
			holder.rotation.y = PI / 2.0 if cargo_cross else 0.0
			add_child(holder)
			add_pallets(holder, cargo)
			load_h = JACK_LIFT + float(SIZES["pallet"]["height"]) * cargo
		# Gleiche Fläche wie der Stellplan (Layout.shelf_rect), mit Last also breiter
		var jr := jack_rect(cargo, cargo_cross)
		var jh := maxf(h, load_h)
		var jack_hit := Build.collider(self, Vector3(jr.size.x, jh, jr.size.y), Vector3(jr.get_center().x, jh * 0.5, jr.get_center().y))
		jack_hit.set_meta("interact", self)
		return
	if size_id == "pallet":
		add_pallets(self, n)
		_pallet_colliders(n)
		return
	if size_id == "forklift":
		Forklift.pose(Forklift.build_model(self), lift, cargo, load_rot, 0.0, fork_shift, fork_tilt)
		var fk_hit := Build.collider(self, Vector3(Forklift.BODY_X.y - Forklift.BODY_X.x, h, f.y), Vector3((Forklift.BODY_X.x + Forklift.BODY_X.y) * 0.5, h * 0.5, 0))
		fk_hit.set_meta("interact", self)
		return
	if size_id == "bucket":
		add_child(Bucket.make(chips.fraction() if chips else 0.0))
	else:
		add_child(Props.make(size_id))
	var hit := Build.collider(self, Vector3(f.x, h, f.y), Vector3(0, h * 0.5, 0))
	hit.set_meta("interact", self)


## Kollision einer Palette nach ihrer Form: Deckplatte oben, darunter die neun Klötze, dazwischen offen,
## damit die Zinken des Hubwagens von allen vier Seiten einfahren. Gestapelt: Nur die unterste Palette hat
## Öffnungen, darüber genügt ein Quader. Der Sichtstrahl trifft Deckplatte und Klötze (Meta "interact") selbst.
func _pallet_colliders(n: int) -> void:
	var h := float(SIZES["pallet"]["height"])
	var f: Vector2 = SIZES["pallet"]["foot"]
	var body := StaticBody3D.new()
	add_child(body)
	body.set_meta("interact", self)
	_box(body, Vector3(f.x, h - PALLET_BLOCK_H, f.y), Vector3(0, PALLET_BLOCK_H + (h - PALLET_BLOCK_H) * 0.5, 0))
	for bx in PALLET_BLOCKS_X:
		for bz in PALLET_BLOCKS_Z:
			_box(body, Vector3(bx[1] - bx[0], PALLET_BLOCK_H, bz[1] - bz[0]),
					Vector3((bx[0] + bx[1]) * 0.5, PALLET_BLOCK_H * 0.5, (bz[0] + bz[1]) * 0.5))
	if n > 1:
		_box(body, Vector3(f.x, h * (n - 1), f.y), Vector3(0, h + h * (n - 1) * 0.5, 0))


static func _box(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)


## n Paletten übereinander in parent (Mitte über dem Ursprung).
static func add_pallets(parent: Node3D, n: int) -> void:
	var h := float(SIZES["pallet"]["height"])
	for k in maxi(n, 1):
		var part := Props.make("pallet")
		part.position.y = h * k
		# Gestapelte Paletten liegen nie ganz genau übereinander
		if k > 0:
			part.position += Vector3(sin(k * 2.3) * 0.015, 0, cos(k * 1.7) * 0.012)
			part.rotation.y = sin(k * 3.1) * 0.012
		parent.add_child(part)


func is_pallet() -> bool:
	return size_id == "pallet"


func get_prompt() -> String:
	if is_pallet() and world:
		return world.pallet_prompt(index)
	if size_id == "pallet_jack" and world:
		return world.jack_prompt(index)
	if size_id == "bucket" and world:
		return world.bucket_prompt(index)
	if size_id == "forklift" and world:
		return world.forklift_prompt(index)
	return "%s   |   im Baumenü umstellen" % SIZES[size_id]["title"]


static func in_shop(id: String) -> bool:
	return bool(SIZES[id].get("shop", true))


## E auf einen Palettenstapel: oberste Palette aufnehmen oder die getragene drauflegen.
func interact(_p: Node) -> void:
	if is_pallet() and world:
		world.pallet_click(index)
	elif size_id == "pallet_jack" and world:
		world.jack_click(index)
	elif size_id == "bucket" and world:
		world.bucket_click(index)
	elif size_id == "forklift" and world:
		world.forklift_click(index)


func click(_p: Node) -> void:
	pass
