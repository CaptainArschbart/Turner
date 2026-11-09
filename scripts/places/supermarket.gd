class_name Supermarket
extends Place
## Kleiner Supermarkt: ein Raum mit Regalreihen, Kühltruhe und Kasse. An der Kasse gibt es Zigaretten.

const SIZE := Vector3(14.0, 3.4, 12.0)
## Sortiment an der Kasse: Zigaretten als Schachtel oder als Stange.
const GOODS := [
	{"title": "Schachtel Zigaretten", "info": "20 Stück", "count": 20, "price": 9},
	{"title": "Stange Zigaretten", "info": "10 Schachteln, 200 Stück", "count": 200, "price": 85},
]
const SHELF_COLORS := [Color(0.85, 0.2, 0.15), Color(0.95, 0.75, 0.1), Color(0.2, 0.5, 0.85), Color(0.25, 0.65, 0.3), Color(0.9, 0.9, 0.85)]


func _ready() -> void:
	id = "supermarket"
	title = "Supermarkt"
	spawn = Vector3(-4.0, 0.05, SIZE.z * 0.5 - 1.2)
	spawn_yaw = 0.0
	room(SIZE, HallTex.concrete(), Build.mat(Color(0.93, 0.93, 0.9), 0.8), Build.mat(Color(0.96, 0.96, 0.95), 0.9))
	# Bodenfliesen als heller Belag
	Build.box(self, Vector3(SIZE.x, 0.01, SIZE.z), Vector3(0, 0.005, 0), Build.mat(Color(0.82, 0.82, 0.8), 0.5))
	for x in [-3.5, 0.0, 3.5]:
		for z in [-2.0, 2.0]:
			lamp(Vector3(x, SIZE.y - 0.05, z), 0.9, 7.0)
	# Regalreihen mit bunten Packungen
	var metal := Build.mat(Color(0.7, 0.72, 0.74), 0.4, 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for row in 3:
		var x := -4.5 + row * 3.0
		Build.box(self, Vector3(0.9, 1.8, 6.0), Vector3(x, 0.9, -1.5), metal, true)
		for side in [-1.0, 1.0]:
			for level in 4:
				var y := 0.25 + level * 0.45
				var z := -4.3
				while z < 1.3:
					var w := rng.randf_range(0.15, 0.35)
					var h := rng.randf_range(0.18, 0.35)
					var c: Color = SHELF_COLORS[rng.randi() % SHELF_COLORS.size()]
					Build.box(self, Vector3(0.22, h, w), Vector3(x + side * 0.34, y + h * 0.5, z + w * 0.5), Build.mat(c, 0.7))
					z += w + 0.05
	# Kühltruhe an der Nordwand
	Build.box(self, Vector3(6.0, 0.9, 1.0), Vector3(1.5, 0.45, -SIZE.z * 0.5 + 0.6), Build.mat(Color(0.95, 0.95, 0.97), 0.3), true)
	Build.box(self, Vector3(5.8, 0.02, 0.9), Vector3(1.5, 0.91, -SIZE.z * 0.5 + 0.6), Build.glass(Color(0.7, 0.85, 0.95, 0.35)))
	# Kasse vorn rechts mit Zigarettenregal dahinter
	var counter_x := 3.8
	var counter_z := SIZE.z * 0.5 - 2.6
	Build.box(self, Vector3(2.6, 0.95, 0.8), Vector3(counter_x, 0.475, counter_z), Build.mat(Color(0.25, 0.27, 0.3), 0.6))
	Build.box(self, Vector3(2.6, 0.03, 0.8), Vector3(counter_x, 0.965, counter_z), Build.mat(Color(0.15, 0.15, 0.16), 0.3, 0.3))
	Build.box(self, Vector3(0.35, 0.25, 0.3), Vector3(counter_x + 0.8, 1.1, counter_z), Build.mat(Color(0.1, 0.1, 0.12), 0.4))
	Build.box(self, Vector3(0.3, 1.4, 2.2), Vector3(counter_x + 2.3, 1.4, counter_z), Build.mat(Color(0.3, 0.22, 0.15), 0.6), true)
	for i in 18:
		var c := Color(0.95, 0.95, 0.92) if i % 3 else Color(0.8, 0.1, 0.1)
		Build.box(self, Vector3(0.05, 0.1, 0.08), Vector3(counter_x + 2.12, 0.85 + floorf(i / 6.0) * 0.35, counter_z - 0.8 + (i % 6) * 0.3), Build.mat(c, 0.6))
	var label := Build.label(self, "KASSE", Vector3(counter_x, 2.5, counter_z), 0.006, Color(0.8, 0.1, 0.1), 64)
	label.font = UITheme.font(700, 2)
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var till := PlaceTarget.new()
	till.prompt = "Kasse: Zigaretten kaufen"
	till.action = func(p: Node): places.world.shop_menu.open_for(p)
	add_child(till)
	var hit := Build.collider(self, Vector3(2.6, 1.3, 0.9), Vector3(counter_x, 0.65, counter_z))
	hit.set_meta("interact", till)
	exit_door(-4.0, SIZE.z * 0.5)
