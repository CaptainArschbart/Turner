class_name QualityStation
extends Node3D
## Qualitätsmanagement im eigenen Raum neben dem Büro: Messtisch aus Granit mit Abgabekiste, Prüfplatz mit
## Bildschirm und Prüfmittelschrank. Ausgespannte Teile werden hier abgegeben und geprüft.
## Die Vorderseite zeigt nach -Z zum Durchgang, die Rückwand des Raums liegt bei lokal z = 0.7.

const POS := Vector3(3.3, 0.0, 11.9)
const TABLE_Y := 0.9

## Spielwelt: qm_prompt(), qm_click()
var world: Node
var _screen: Label3D


func _ready() -> void:
	var granite := Build.mat(Color(0.16, 0.17, 0.18), 0.35, 0.1)
	var steel := Build.mat(Color(0.28, 0.32, 0.36), 0.55, 0.4)
	var chrome := Build.mat(Color(0.82, 0.83, 0.85), 0.15, 1.0)
	var green := Build.mat(Color(0.1, 0.62, 0.32), 0.6)
	var white := Build.mat(Color(0.92, 0.93, 0.92), 0.6)
	var dark := Build.mat(Color(0.08, 0.09, 0.1), 0.5)
	var blue := Build.mat(Color(0.12, 0.32, 0.7), 0.55)

	# Grüne Markierung vor dem Messtisch: Hier stehen und abgeben
	Build.box(self, Vector3(1.6, 0.004, 0.06), Vector3(-0.2, 0.004, -0.75), green)

	# Messtisch: Granitplatte auf Stahlgestell
	var tc := Vector3(-0.2, 0, 0.1)
	Build.box(self, Vector3(1.4, 0.12, 0.8), Vector3(tc.x, TABLE_Y - 0.06, tc.z), granite)
	for sx in [-0.62, 0.62]:
		for sz in [-0.32, 0.32]:
			Build.box(self, Vector3(0.06, TABLE_Y - 0.12, 0.06), Vector3(tc.x + sx, (TABLE_Y - 0.12) * 0.5, tc.z + sz), steel)
	Build.box(self, Vector3(1.3, 0.04, 0.7), Vector3(tc.x, 0.25, tc.z), steel)
	# Höhenmessgerät
	Build.box(self, Vector3(0.12, 0.04, 0.1), Vector3(tc.x - 0.5, TABLE_Y + 0.02, tc.z + 0.15), dark)
	Build.box(self, Vector3(0.02, 0.36, 0.03), Vector3(tc.x - 0.5, TABLE_Y + 0.22, tc.z + 0.15), chrome)
	Build.box(self, Vector3(0.09, 0.03, 0.02), Vector3(tc.x - 0.46, TABLE_Y + 0.18, tc.z + 0.15), chrome)
	Build.box(self, Vector3(0.05, 0.07, 0.02), Vector3(tc.x - 0.5, TABLE_Y + 0.3, tc.z + 0.13), white)
	# Bügelmessschraube in der Schachtel
	Build.box(self, Vector3(0.24, 0.03, 0.1), Vector3(tc.x - 0.15, TABLE_Y + 0.015, tc.z + 0.25), Build.mat(Color(0.25, 0.2, 0.15), 0.8))
	Build.cyl(self, 0.012, 0.13, Vector3(tc.x - 0.15, TABLE_Y + 0.04, tc.z + 0.25), chrome, Build.AXIS_X)
	# Abgabekiste vorne rechts
	var tray := Vector3(tc.x + 0.38, TABLE_Y, tc.z - 0.12)
	Build.box(self, Vector3(0.4, 0.012, 0.3), tray + Vector3(0, 0.006, 0), blue)
	for e in [-1.0, 1.0]:
		Build.box(self, Vector3(0.4, 0.09, 0.012), tray + Vector3(0, 0.045, e * 0.144), blue)
		Build.box(self, Vector3(0.012, 0.09, 0.3), tray + Vector3(e * 0.194, 0.045, 0), blue)
	Build.label(self, "ABGABE", tray + Vector3(0, 0.05, -0.152), 0.0012, Color(1, 1, 1), 48, PI)

	# Prüfplatz mit Bildschirm für das letzte Prüfprotokoll
	var dc := Vector3(1.1, 0, 0.3)
	Build.box(self, Vector3(1.0, 0.04, 0.6), Vector3(dc.x, 0.76, dc.z), white)
	for sx in [-0.46, 0.46]:
		Build.box(self, Vector3(0.04, 0.74, 0.56), Vector3(dc.x + sx, 0.37, dc.z), steel)
	Build.box(self, Vector3(0.06, 0.25, 0.04), Vector3(dc.x, 0.9, dc.z + 0.15), dark)
	Build.box(self, Vector3(0.62, 0.38, 0.03), Vector3(dc.x, 1.15, dc.z + 0.13), dark)
	Build.box(self, Vector3(0.58, 0.34, 0.004), Vector3(dc.x, 1.15, dc.z + 0.113), Build.emissive(Color(0.05, 0.12, 0.1), 0.6))
	_screen = Build.label(self, "", Vector3(dc.x, 1.15, dc.z + 0.11), 0.0009, Color(0.5, 1.0, 0.7), 28, PI)
	_screen.shaded = false
	_screen.width = 600.0
	_screen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Build.box(self, Vector3(0.42, 0.015, 0.14), Vector3(dc.x, 0.785, dc.z - 0.12), dark)

	# Prüfmittelschrank
	var cab := Vector3(-1.5, 0, 0.42)
	Build.box(self, Vector3(0.7, 1.9, 0.45), Vector3(cab.x, 0.95, cab.z), Build.mat(Color(0.55, 0.58, 0.6), 0.5, 0.3), true)
	Build.box(self, Vector3(0.005, 1.8, 0.005), Vector3(cab.x, 0.95, cab.z - 0.226), dark)
	Build.label(self, "Prüfmittel", Vector3(cab.x, 1.7, cab.z - 0.228), 0.0014, Color(0.1, 0.12, 0.16), 48, PI)

	# Schild an der Wand
	Build.box(self, Vector3(2.6, 0.42, 0.02), Vector3(0.2, 2.35, 0.69), green)
	Build.label(self, "QUALITÄTSMANAGEMENT", Vector3(0.2, 2.35, 0.675), 0.0029, Color(1, 1, 1), 64, PI)

	# Messtisch und Prüfplatz sind das Ziel für die Abgabe
	for b in [[Vector3(1.4, TABLE_Y + 0.1, 0.8), Vector3(tc.x, (TABLE_Y + 0.1) * 0.5, tc.z)],
			[Vector3(1.0, 1.35, 0.6), Vector3(dc.x, 0.675, dc.z)]]:
		Build.collider(self, b[0], b[1]).set_meta("interact", self)
	show_result("Bereit.\nTeile ausspannen und hier abgeben.")


## Kurzfassung des letzten Prüfprotokolls auf dem Bildschirm.
func show_result(text: String) -> void:
	if _screen:
		_screen.text = "PRÜFPLATZ\n\n" + text


func get_prompt() -> String:
	return world.qm_prompt()


func interact(_p: Node) -> void:
	pass


func click(_p: Node) -> void:
	world.qm_click()
