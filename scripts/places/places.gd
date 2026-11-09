class_name Places
extends Node3D
## Alle Orte außerhalb des Werkstattgeländes und das Reisen dorthin. Ortsnamen:
##   "site"            Werkstattgelände (die eigentliche Spielwelt, Eingang am Hoftor)
##   "supermarket"     der Supermarkt, für alle gemeinsam
##   "home:<owner_id>" das Zuhause eines Spielers, je Spieler eines
## Jeder Ort steht an eigenen, weit entfernten Koordinaten in derselben Szene. Damit können später im
## Multiplayer mehrere Spieler gleichzeitig an verschiedenen Orten sein, ohne die Szene zu wechseln.
## Alles, was reist, bekommt den Spieler als Parameter, nichts hängt an "dem einen" Spieler.

signal travelled(player: Node, place_id: String)

const SITE := "site"
const SUPERMARKET := "supermarket"
const SUPERMARKET_ORIGIN := Vector3(2000.0, 0.0, 0.0)
const HOME_ORIGIN := Vector3(-2000.0, 0.0, 0.0)
const HOME_SPACING := 50.0                    # Abstand der Wohnungen, je Spieler eine

## Spielwelt: site_entry(), site_entry_yaw()
var world: Node
var supermarket: Supermarket
var homes: Dictionary = {}                    # owner_id -> Home
var home_slots: Dictionary = {}               # owner_id -> Platznummer, bleibt im Spielstand gleich


static func home_id(owner_id: String) -> String:
	return "home:" + owner_id


func _ready() -> void:
	supermarket = Supermarket.new()
	supermarket.places = self
	supermarket.position = SUPERMARKET_ORIGIN
	add_child(supermarket)


## Zuhause dieses Spielers, wird beim ersten Mal angelegt.
func home_of(owner_id: String) -> Home:
	if homes.has(owner_id):
		return homes[owner_id]
	if not home_slots.has(owner_id):
		home_slots[owner_id] = _free_slot()
	var h := Home.new()
	h.owner_id = owner_id
	h.places = self
	h.position = HOME_ORIGIN + Vector3(0, 0, float(home_slots[owner_id]) * HOME_SPACING)
	add_child(h)
	homes[owner_id] = h
	return h


func _free_slot() -> int:
	var used: Array = home_slots.values()
	var i := 0
	while used.has(i):
		i += 1
	return i


## Ort zu einem Namen, null für das Gelände oder Unbekanntes.
func place(place_id: String) -> Place:
	if place_id == SUPERMARKET:
		return supermarket
	if place_id.begins_with("home:"):
		return home_of(place_id.substr(5))
	return null


## Ziele, die ein Spieler von seinem Ort aus erreichen kann: [{"id", "title"}].
func destinations(p: Node) -> Array:
	var out := []
	for d in [[SITE, "Zur Werkstatt"], [SUPERMARKET, "Zum Supermarkt"], [home_id(p.player_id), "Nach Hause"]]:
		if d[0] != p.location:
			out.append({"id": d[0], "title": d[1]})
	return out


## Spieler an einen Ort bringen. Gibt einen Fehlertext zurück, leer = angekommen.
func travel(p: Node, place_id: String) -> String:
	if not p.carry.is_empty():
		return "Erst das Material ablegen, das du trägst."
	var target: Vector3
	var yaw := 0.0
	if place_id == SITE:
		target = world.site_entry()
		yaw = world.site_entry_yaw()
	else:
		var pl := place(place_id)
		if pl == null:
			return "Diesen Ort gibt es nicht."
		target = pl.spawn_point()
		yaw = pl.spawn_yaw
	p.global_position = target
	p.velocity = Vector3.ZERO
	p.yaw = yaw
	p.rotation.y = yaw
	p.location = place_id
	travelled.emit(p, place_id)
	return ""


func to_state() -> Dictionary:
	return {"home_slots": home_slots.duplicate()}


func from_state(d: Dictionary) -> void:
	var slots = d.get("home_slots", {})
	if slots is Dictionary:
		for k in slots:
			home_slots[str(k)] = int(slots[k])
	# Schon angelegte Wohnungen an ihren gespeicherten Platz rücken
	for k in homes:
		homes[k].position = HOME_ORIGIN + Vector3(0, 0, float(home_slots.get(k, 0)) * HOME_SPACING)
