class_name Home
extends Place
## Zuhause eines Spielers: eine kleine Wohnung mit Bett, Tisch und Schrank. Jeder Spieler (owner_id) hat
## sein eigenes, Places legt es an. Im Bett wird nach Feierabend geschlafen, das beginnt den nächsten Tag.

const SIZE := Vector3(7.0, 2.6, 6.0)
const BED := Vector3(-2.2, 0, -1.6)          # Mitte des Betts, Kopfende an der Nordwand

var owner_id := ""


func _ready() -> void:
	id = "home:" + owner_id
	title = "Zuhause"
	spawn = Vector3(1.8, 0.05, SIZE.z * 0.5 - 1.0)
	spawn_yaw = 0.0
	room(SIZE, Build.mat(Color(0.55, 0.4, 0.27), 0.7), Build.mat(Color(0.9, 0.87, 0.8), 0.9), Build.mat(Color(0.95, 0.94, 0.92), 0.9))
	lamp(Vector3(0, SIZE.y - 0.05, 0), 0.8, 7.0, Color(1.0, 0.88, 0.7))
	var wood := Build.mat(Color(0.48, 0.33, 0.2), 0.6)
	# Bett: Rahmen, Matratze, Decke, Kissen
	Build.box(self, Vector3(1.5, 0.35, 2.1), BED + Vector3(0, 0.175, 0), wood)
	Build.box(self, Vector3(1.4, 0.18, 2.0), BED + Vector3(0, 0.44, 0), Build.mat(Color(0.95, 0.95, 0.93), 0.9))
	Build.box(self, Vector3(1.44, 0.06, 1.4), BED + Vector3(0, 0.55, 0.3), Build.mat(Color(0.25, 0.38, 0.6), 0.9))
	Build.box(self, Vector3(0.6, 0.12, 0.35), BED + Vector3(0, 0.6, -0.75), Build.mat(Color(0.98, 0.98, 0.97), 0.9))
	Build.box(self, Vector3(1.5, 0.9, 0.08), BED + Vector3(0, 0.45, -1.06), wood)
	# Nachttisch, Tisch mit Stuhl, Schrank
	Build.box(self, Vector3(0.45, 0.5, 0.4), BED + Vector3(1.05, 0.25, -0.75), wood, true)
	Build.box(self, Vector3(1.2, 0.05, 0.8), Vector3(1.8, 0.75, -1.5), wood)
	for x in [-0.5, 0.5]:
		for z in [-0.3, 0.3]:
			Build.box(self, Vector3(0.05, 0.75, 0.05), Vector3(1.8 + x, 0.375, -1.5 + z), wood)
	Build.box(self, Vector3(1.2, 0.8, 0.8), Vector3(1.8, 0.4, -1.5), wood, true).visible = false
	Build.box(self, Vector3(0.45, 0.05, 0.45), Vector3(1.8, 0.45, -0.8), wood, true)
	Build.box(self, Vector3(1.0, 2.1, 0.6), Vector3(SIZE.x * 0.5 - 0.5, 1.05, 0.5), Build.mat(Color(0.82, 0.8, 0.75), 0.7), true)
	var bed := PlaceTarget.new()
	bed.prompt = "Bett: schlafen"
	bed.action = func(p: Node): places.world.sleep_in_bed(p)
	add_child(bed)
	var hit := Build.collider(self, Vector3(1.5, 0.7, 2.1), BED + Vector3(0, 0.35, 0))
	hit.set_meta("interact", bed)
	exit_door(-1.0, SIZE.z * 0.5)


## Hier steht man nach dem Aufwachen: neben dem Bett.
func wake_point() -> Vector3:
	return to_global(BED + Vector3(1.4, 0.05, 0.6))
