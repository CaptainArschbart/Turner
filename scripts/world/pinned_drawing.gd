class_name PinnedDrawing
extends Node3D
## Ausgedruckte Zeichnung, mit einer Reißzwecke an eine Fläche gepinnt. Sie hängt an dem Körper, an den sie
## gepinnt wurde (zum Beispiel die Schutztür der E50) und fährt mit ihm mit. Das Blatt zeigt nach +Z.

const SIZE := Vector2(0.42, 0.2475)   # Seitenverhältnis wie die Zeichnung auf dem Bildschirm

## Spielwelt: drawing_texture(job), pin_prompt(pin), pin_click(pin), drawing
var world: Node
var job: Dictionary = {}
var anchor: Node3D = null            # Körper, an dem das Blatt hängt
var local := Transform3D.IDENTITY    # Lage relativ zum Körper
var body: StaticBody3D


## Papierblatt mit Zeichnung, auch für die Hand. Gibt den Knoten zurück.
static func sheet(parent: Node3D, tex: Texture2D, size := SIZE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.albedo_texture = tex
	m.roughness = 0.9
	mi.material_override = m
	parent.add_child(mi)
	# Rückseite weiß
	var back := MeshInstance3D.new()
	back.mesh = q
	back.rotation.y = PI
	back.position.z = -0.0005
	back.material_override = Build.mat(Color(0.93, 0.93, 0.9), 0.9)
	mi.add_child(back)
	return mi


func _ready() -> void:
	sheet(self, world.drawing_texture(job) if world else null)
	Build.sphere(self, 0.007, Vector3(0, SIZE.y * 0.5 - 0.015, 0.006), Build.mat(Color(0.85, 0.1, 0.08), 0.4))
	body = Build.collider(self, Vector3(SIZE.x, SIZE.y, 0.006), Vector3(0, 0, 0.003))
	body.set_meta("interact", self)


func _process(_delta: float) -> void:
	if anchor != null and is_instance_valid(anchor) and anchor.is_inside_tree():
		global_transform = anchor.global_transform * local


## An einen Körper hängen, die Lage bleibt dabei, wo sie ist.
func attach(to: Node3D) -> void:
	anchor = to
	if to != null:
		local = to.global_transform.affine_inverse() * global_transform


func get_prompt() -> String:
	return world.pin_prompt(self)


func interact(_p: Node) -> void:
	world.drawing.show_job(job)


func click(_p: Node) -> void:
	world.pin_click(self)
