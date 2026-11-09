class_name YardGate
extends Node3D
## Zweiflügeliges Hoftor im Südzaun. Ursprung = Tormitte am Boden, das Tor liegt entlang X, +Z zeigt zur
## Straße. Die Torgruppe (Führungsfelder und zwei Flügel) kommt aus models/fence.glb; fehlt das Modell, wird ein Stabgittertor gebaut.
## Interagieren öffnet das Menü zum Verlassen des Geländes.

const HEIGHT := 2.2
const POST := 0.12
const TUBE := 0.06

var world: Node                    # Spielwelt: travel_menu
var width := 5.0
var title := "Hoftor"


func _ready() -> void:
	# Torgruppe aus dem Modell (Führungsfelder + Flügel); ohne Modell ein Stabgittertor über die ganze Breite
	var leaves := Site.gate_model(self, width)
	if leaves.size == Vector3.ZERO:
		_build_fallback()
		leaves = AABB(Vector3(-width * 0.5, 0, -0.06), Vector3(width, HEIGHT, 0.12))
	# Schild am rechten Flügel, zur Straße hin und zum Hof
	var sx := leaves.position.x + leaves.size.x * 0.75
	for side in [-1.0, 1.0]:
		var z: float = leaves.end.z + 0.005 if side > 0.0 else leaves.position.z - 0.005
		var sign_mat := Build.mat(Color(0.95, 0.95, 0.93), 0.6)
		Build.box(self, Vector3(0.7, 0.3, 0.01), Vector3(sx, 1.5, z), sign_mat)
		var l := Build.label(self, "AUSFAHRT\nFREIHALTEN", Vector3(sx, 1.5, z + side * 0.007), 0.0011, Color(0.75, 0.08, 0.06), 96)
		l.rotation.y = 0.0 if side > 0.0 else PI
		l.font = UITheme.font(700, 2)
		l.shaded = true
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = Site.OUTDOOR_LAYER
	var z0 := minf(leaves.position.z, -0.06)
	var z1 := maxf(leaves.end.z, 0.06)
	var hit := Build.collider(self, Vector3(width, HEIGHT + 0.2, z1 - z0), Vector3(0, (HEIGHT + 0.2) * 0.5, (z0 + z1) * 0.5))
	hit.set_meta("interact", self)


## Ersatz ohne Modell: Pfosten, zwei Flügel aus Vierkantrohr mit Stabgitter, Schlosskasten und Bodenriegel.
func _build_fallback() -> void:
	var steel := HallTex.powder(Site.FENCE_GREEN, 0.12)
	var mesh := HallTex.fence_mesh(Site.FENCE_GREEN.lightened(0.05))
	var foot := Build.mat(Color(0.45, 0.46, 0.46), 0.8)
	var dark := Build.mat(Color(0.12, 0.13, 0.14), 0.5, 0.4)
	var half := width * 0.5
	for sx in [-1.0, 1.0]:
		var x: float = sx * (half - POST * 0.5)
		Build.box(self, Vector3(POST, HEIGHT + 0.2, POST), Vector3(x, (HEIGHT + 0.2) * 0.5, 0), steel)
		Build.box(self, Vector3(POST + 0.02, 0.02, POST + 0.02), Vector3(x, HEIGHT + 0.21, 0), steel)
		Build.box(self, Vector3(0.24, 0.012, 0.24), Vector3(x, 0.006, 0), foot)
	var leaf_w := half - POST - 0.03
	var y0 := 0.06
	var y1 := HEIGHT - 0.05
	for sx in [-1.0, 1.0]:
		var cx: float = sx * (half - POST - 0.015 - leaf_w * 0.5)
		Build.box(self, Vector3(leaf_w, TUBE, TUBE), Vector3(cx, y0 + TUBE * 0.5, 0), steel)
		Build.box(self, Vector3(leaf_w, TUBE, TUBE), Vector3(cx, y1 - TUBE * 0.5, 0), steel)
		Build.box(self, Vector3(leaf_w, TUBE * 0.7, TUBE * 0.7), Vector3(cx, (y0 + y1) * 0.5, 0), steel)
		for ex in [-1.0, 1.0]:
			Build.box(self, Vector3(TUBE, y1 - y0, TUBE), Vector3(cx + ex * (leaf_w - TUBE) * 0.5, (y0 + y1) * 0.5, 0), steel)
		Build.box(self, Vector3(leaf_w - TUBE, y1 - y0 - TUBE, 0.008), Vector3(cx, (y0 + y1) * 0.5, 0), mesh)
		for y in [0.35, y1 - 0.3]:
			Build.box(self, Vector3(0.08, 0.1, 0.05), Vector3(sx * (half - POST - 0.02), y, 0.05), dark)
	Build.box(self, Vector3(0.16, 0.24, 0.09), Vector3(-0.1, 1.05, 0), steel)
	for z in [-1.0, 1.0]:
		Build.box(self, Vector3(0.14, 0.025, 0.025), Vector3(-0.2, 1.1, z * 0.07), dark)
	Build.box(self, Vector3(0.03, 0.4, 0.03), Vector3(0.12, 0.25, 0.05), dark)
	Build.box(self, Vector3(0.12, 0.012, 0.12), Vector3(0.12, 0.006, 0.05), foot)


func get_prompt() -> String:
	return "[%s] %s: Gelände verlassen (Supermarkt, Zuhause)" % [Settings.binding_text("interact"), title]


func interact(p: Node) -> void:
	if world != null:
		world.travel_menu.open_for(p)


func click(p: Node) -> void:
	interact(p)
