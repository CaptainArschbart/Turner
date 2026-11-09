class_name OfficeClock
extends Node3D
## Wanduhr im Meisterbüro. Sie zeigt die Spielzeit des Arbeitstags. Das Zifferblatt zeigt nach +Z.

const R := 0.16

## Spielwelt: day_time
var shop: Node = null
var day_seconds := 1200.0
var _hour: Node3D
var _minute: Node3D


func _ready() -> void:
	var rim := Build.mat(Color(0.12, 0.12, 0.13), 0.4, 0.5)
	var dark := Build.mat(Color(0.08, 0.08, 0.09), 0.5)
	Build.cyl(self, R + 0.015, 0.04, Vector3(0, 0, -0.02), rim, Build.AXIS_Z, false, 32)
	Build.cyl(self, R, 0.005, Vector3(0, 0, 0.001), Build.mat(Color(0.96, 0.96, 0.94), 0.4), Build.AXIS_Z, false, 32)
	for i in 12:
		var a := i * TAU / 12.0
		var long := i % 3 == 0
		var l := 0.03 if long else 0.016
		var r := R - 0.012 - l * 0.5
		Build.box(self, Vector3(0.008 if long else 0.004, l, 0.002), Vector3(sin(a) * r, cos(a) * r, 0.005), dark, false, Vector3(0, 0, -a))
	_hour = _hand(0.085, 0.012, dark)
	_minute = _hand(0.13, 0.007, dark)
	Build.cyl(self, 0.01, 0.012, Vector3(0, 0, 0.012), Build.mat(Color(0.8, 0.1, 0.08), 0.4), Build.AXIS_Z, false, 12)
	_update()


func _hand(length: float, width: float, m: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0, 0.007)
	add_child(pivot)
	Build.box(pivot, Vector3(width, length, 0.002), Vector3(0, length * 0.5 - 0.015, 0), m)
	return pivot


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var minutes := 7.0 * 60.0
	if shop != null:
		minutes += clampf(float(shop.day_time) / day_seconds, 0.0, 1.0) * 600.0
	# Im Uhrzeigersinn, von vorn gesehen
	_minute.rotation.z = -fmod(minutes, 60.0) / 60.0 * TAU
	_hour.rotation.z = -fmod(minutes / 60.0, 12.0) / 12.0 * TAU
