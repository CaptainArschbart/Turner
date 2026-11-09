class_name Place
extends Node3D
## Ein Ort außerhalb des Werkstattgeländes (Supermarkt, Zuhause). Jeder Ort steht weit weg von der Werkstatt
## in derselben Szene: So können später mehrere Spieler gleichzeitig an verschiedenen Orten sein.
## Ursprung = Raummitte am Boden, der Ausgang liegt an der Südwand (+Z).

var places: Node                   # Places: Reisen, Spielwelt (ohne Typ, sonst hängen Place und Places im Kreis)
var id := ""                       # eindeutig, z. B. "supermarket" oder "home:local"
var title := ""
var spawn := Vector3(0, 0.05, 0)   # lokal: hier kommt man herein
var spawn_yaw := 0.0


## Eintrittspunkt in Weltkoordinaten.
func spawn_point() -> Vector3:
	return to_global(spawn)


# ------------------------------------------------------------ Bauhilfen

## Einfacher geschlossener Raum mit Boden, Decke und vier Wänden, alles mit Kollision.
func room(size: Vector3, floor_mat: Material, wall_mat: Material, ceil_mat: Material) -> void:
	Build.box(self, Vector3(size.x, 0.2, size.z), Vector3(0, -0.1, 0), floor_mat, true)
	Build.box(self, Vector3(size.x, 0.2, size.z), Vector3(0, size.y + 0.1, 0), ceil_mat, true)
	Build.box(self, Vector3(size.x, size.y, 0.2), Vector3(0, size.y * 0.5, -size.z * 0.5 - 0.1), wall_mat, true)
	Build.box(self, Vector3(size.x, size.y, 0.2), Vector3(0, size.y * 0.5, size.z * 0.5 + 0.1), wall_mat, true)
	Build.box(self, Vector3(0.2, size.y, size.z), Vector3(-size.x * 0.5 - 0.1, size.y * 0.5, 0), wall_mat, true)
	Build.box(self, Vector3(0.2, size.y, size.z), Vector3(size.x * 0.5 + 0.1, size.y * 0.5, 0), wall_mat, true)


## Deckenleuchte mit Lichtquelle.
func lamp(pos: Vector3, energy := 1.2, range_m := 8.0, col := Color(1.0, 0.96, 0.9)) -> void:
	Build.box(self, Vector3(1.2, 0.05, 0.25), pos + Vector3(0, 0.02, 0), Build.emissive(col, 1.5))
	var l := OmniLight3D.new()
	l.position = pos - Vector3(0, 0.3, 0)
	l.light_color = col
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	add_child(l)


## Ausgangstür an der Südwand: Interagieren öffnet das Reisemenü.
func exit_door(x: float, wall_z: float) -> void:
	var d := Node3D.new()
	d.position = Vector3(x, 0, wall_z - 0.02)
	add_child(d)
	Build.box(d, Vector3(1.1, 2.2, 0.06), Vector3(0, 1.1, 0), Build.mat(Color(0.42, 0.3, 0.2), 0.6))
	Build.box(d, Vector3(1.24, 2.3, 0.04), Vector3(0, 1.15, 0.02), Build.mat(Color(0.85, 0.85, 0.82), 0.6))
	Build.box(d, Vector3(0.14, 0.025, 0.05), Vector3(0.4, 1.05, -0.05), Build.mat(Color(0.75, 0.75, 0.72), 0.3, 0.8))
	var label := Build.label(d, "AUSGANG", Vector3(0, 2.45, -0.03), 0.004, Color(0.1, 0.6, 0.25), 64, PI)
	label.font = UITheme.font(700, 2)
	var t := PlaceTarget.new()
	t.prompt = "Ausgang: woanders hingehen"
	t.action = func(p: Node): places.world.travel_menu.open_for(p)
	add_child(t)
	var hit := Build.collider(d, Vector3(1.1, 2.2, 0.1), Vector3(0, 1.1, -0.05))
	hit.set_meta("interact", t)


