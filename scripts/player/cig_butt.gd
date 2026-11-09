class_name CigButt
extends Node3D
## Zigarettenstummel: fällt im Bogen, springt kurz auf und bleibt liegen. Die Glut verglimmt.
## Eigene einfache Flugbahn statt Physikkörper: So kleine Körper sinken sonst in den Boden ein.

const GRAVITY := 9.8
const MAX_BUTTS := 25

var vel := Vector3.ZERO
var spin := Vector3.ZERO
var resting := false
var _r := 0.0042
var _bounces := 0
var _ember_mat: StandardMaterial3D
var _ember: MeshInstance3D


## Stummel mit Filterlänge filter und Resttabak stub (m), Radius r. Ursprung in der Mitte.
func build(r: float, filter: float, stub: float) -> void:
	_r = r
	var len := filter + stub
	var z0 := len * 0.5
	var f := Build.cyl(self, r, filter, Vector3(0, 0, z0 - filter * 0.5), CigLook.filter_mat(), Build.AXIS_Z)
	var e := Build.cyl(self, r * 0.93, 0.0004, Vector3(0, 0, z0 + 0.0002), CigLook.filter_end_mat(), Build.AXIS_Z)
	var g := Build.cyl(self, r * 1.006, 0.0006, Vector3(0, 0, z0 - filter + 0.0003), CigLook.gold_mat(), Build.AXIS_Z)
	var p := Build.cyl(self, r, stub, Vector3(0, 0, z0 - filter - stub * 0.5), CigLook.paper_mat(), Build.AXIS_Z)
	var c := Build.cyl(self, r * 1.004, 0.0014, Vector3(0, 0, -z0 + 0.0007), CigLook.char_mat(), Build.AXIS_Z)
	_ember_mat = CigLook.ember_mat(1.5)
	_ember = Build.cyl(self, r * 1.01, 0.0025, Vector3(0, 0, -z0 - 0.001), _ember_mat, Build.AXIS_Z)
	for mi in [f, e, g, p, c, _ember]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_to_group("cig_butt")


func _ready() -> void:
	# Die Glut verglimmt langsam, dann bleibt ein grauer Rand
	var tw := create_tween()
	tw.tween_property(_ember_mat, "emission_energy_multiplier", 0.0, 6.0)
	tw.tween_callback(func(): _ember.material_override = Build.mat(Color(0.25, 0.24, 0.23), 1.0))
	# Nicht unbegrenzt viele Kippen liegen lassen
	var all := get_tree().get_nodes_in_group("cig_butt")
	if all.size() > MAX_BUTTS:
		all[0].queue_free()


func _physics_process(delta: float) -> void:
	if resting:
		return
	vel.y -= GRAVITY * delta
	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to - Vector3(0, _r, 0))
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		rotate(spin.normalized() if spin.length() > 0.01 else Vector3.UP, spin.length() * delta)
		if global_position.y < -5.0:
			queue_free()
		return
	var n: Vector3 = hit["normal"]
	global_position = hit["position"] + n * _r
	_bounces += 1
	if _bounces >= 2 or vel.length() < 1.2 or n.y < 0.5:
		_settle(n)
		return
	# Kurz aufspringen, etwas weiterrollen
	vel = vel.bounce(n) * 0.3
	vel.x *= 0.6
	vel.z *= 0.6
	spin *= 0.4


## Flach hinlegen: Längsachse in der Fläche, in der bisherigen Flugrichtung.
func _settle(n: Vector3) -> void:
	resting = true
	vel = Vector3.ZERO
	if n.y < 0.5:
		n = Vector3.UP
	var z := global_basis.z
	z = (z - n * z.dot(n))
	if z.length() < 0.01:
		z = n.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := n.cross(z).normalized()
	global_basis = Basis(x, n, z)
