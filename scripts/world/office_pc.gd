class_name OfficePC
extends Node3D
## PC im Meisterbüro: öffnet per Interaktion die Maschinenübersicht.

signal using_changed(on: bool)

const STAND := Vector3(0.0, 0.0, -0.8)

var overlay: PCOverlay
var player: Node = null


func _ready() -> void:
	# Liegt um den Monitor, leicht größer, damit er sich gut anvisieren lässt
	var hit := Build.collider(self, Vector3(0.7, 0.46, 0.1), Vector3.ZERO)
	hit.set_meta("interact", self)
	overlay = PCOverlay.new()
	overlay.closed.connect(stop_using)
	add_child(overlay)


func get_prompt() -> String:
	return "[%s] PC bedienen" % Settings.binding_text("interact")


func interact(p: Node) -> void:
	if player:
		return
	player = p
	var stand := to_global(STAND)
	stand.y = p.global_position.y
	p.start_operating(self, stand, PI)
	# Blick auf den Monitor, damit er nach dem Verlassen weiter anvisiert ist
	p.pitch = -0.66
	overlay.open()
	using_changed.emit(true)


func stop_using() -> void:
	if not player:
		return
	player.stop_operating()
	player = null
	using_changed.emit(false)
