class_name ToolPreview
extends SubViewportContainer
## Sich drehende 3D-Vorschau eines Werkzeugs aus MillTools oder einer ganzen Maschine.
## Maschinen werden erst gebaut, wenn die Vorschau zum ersten Mal sichtbar ist: Die echte Maschine wird kurz
## erzeugt, ihre Meshes werden als starres Modell übernommen, dann wird sie wieder gelöscht.

const SPIN := 0.6
const FOV := 32.0
## Schräglage je Modell. wide = die Breite des Bilds ausnutzen (lange, liegende Werkzeuge),
## dist = Kameraabstand relativ zur Modellgröße.
const VIEWS := {
	"end_mills": {"tilt": Vector3(0.0, 0.0, -1.2), "wide": true, "dist": 1.25},
	"face_mill": {"tilt": Vector3(0.8, 0.0, 0.0), "wide": false, "dist": 0.72},
	"face_mill_arbor": {"tilt": Vector3(0.0, 0.0, 1.2), "wide": true, "dist": 1.0},
	"inserts": {"tilt": Vector3(0.85, 0.0, 0.0), "wide": true, "dist": 1.0},
	"drill": {"tilt": Vector3(0.0, 0.0, -1.2), "wide": true, "dist": 1.0},
	"holders": {"tilt": Vector3(0.2, 0.0, 0.0), "wide": true, "dist": 1.2},
	"mill_machine": {"tilt": Vector3(0.12, 0.0, 0.0), "wide": false, "dist": 0.8},
	"mill_cnc": {"tilt": Vector3(0.2, 0.0, 0.0), "wide": true, "dist": 0.9},
	"lathe_cnc": {"tilt": Vector3(0.22, 0.0, 0.0), "wide": true, "dist": 0.95},
	"lathe_conv": {"tilt": Vector3(0.22, 0.0, 0.0), "wide": true, "dist": 0.95},
	"band_saw": {"tilt": Vector3(0.25, 0.0, 0.0), "wide": true, "dist": 0.8},
	"round_grinder": {"tilt": Vector3(0.22, 0.0, 0.0), "wide": true, "dist": 1.1},
	"flat_grinder": {"tilt": Vector3(0.18, 0.0, 0.0), "wide": false, "dist": 0.7},
	"drill_press": {"tilt": Vector3(0.12, 0.0, 0.0), "wide": false, "dist": 0.66},
}
## Maschinen der Übersicht: Skript und Eigenschaften, die vor dem Einhängen gesetzt werden.
const MACHINES := {
	"lathe_cnc": ["res://scripts/machine/lathe.gd", {"conventional": false, "demo": true}],
	"mill_cnc": ["res://scripts/machine/cnc_mill.gd", {}],
	"lathe_conv": ["res://scripts/machine/lathe.gd", {"conventional": true, "demo": true}],
	"band_saw": ["res://scripts/machine/band_saw.gd", {}],
	"round_grinder": ["res://scripts/machine/round_grinder.gd", {"demo": true}],
	"flat_grinder": ["res://scripts/machine/flat_grinder.gd", {}],
	"drill_press": ["res://scripts/machine/drill_press.gd", {}],
}
## Pro Bild wird höchstens eine Maschine gebaut, damit das Öffnen der Übersicht nicht lange hängt.
static var _built_frame := -1

var model_id := ""
var _spin: Node3D
var _tilt: Node3D
var _vp: SubViewport
var _pending := false


func _ready() -> void:
	stretch = true
	custom_minimum_size.y = 170.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vp := SubViewport.new()
	_vp = vp
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.21, 0.23)
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	vp.add_child(we)

	for a in [Vector3(-0.8, 0.6, 0.0), Vector3(-0.3, -2.2, 0.0)]:
		var light := DirectionalLight3D.new()
		light.rotation = a
		light.light_energy = 1.3
		vp.add_child(light)

	_tilt = Node3D.new()
	vp.add_child(_tilt)
	_spin = Node3D.new()
	_tilt.add_child(_spin)
	if MACHINES.has(model_id):
		_pending = true
	else:
		_show(MillTools.build(model_id))


## Modell einhängen, mittig ausrichten und die Kamera passend dazu setzen.
func _show(model: Node3D) -> void:
	_spin.add_child(model)
	var box := _bounds(model)
	model.position = -box.get_center()
	var view: Dictionary = VIEWS.get(model_id, {"tilt": Vector3.ZERO, "wide": false, "dist": 1.0})
	_tilt.rotation = view["tilt"]

	var cam := Camera3D.new()
	cam.fov = FOV
	cam.keep_aspect = Camera3D.KEEP_WIDTH if view["wide"] else Camera3D.KEEP_HEIGHT
	var dist := box.size.length() * 0.55 * float(view["dist"]) / tan(deg_to_rad(FOV * 0.5))
	cam.position = Vector3(0, 0, dist)
	cam.near = dist * 0.1
	cam.far = dist * 4.0
	_vp.add_child(cam)


func _process(delta: float) -> void:
	if not _spin or not is_visible_in_tree():
		return
	if _pending and _built_frame != Engine.get_process_frames():
		_built_frame = Engine.get_process_frames()
		_pending = false
		_show(machine_model(model_id, _vp))
	_spin.rotation.y += SPIN * delta


## Starres Abbild einer Maschine: Die Maschine wird in host kurz gebaut, ihre sichtbaren Meshes und Schriften werden
## kopiert, dann wird sie gelöscht. Anzeigen, die in eigene Viewports rendern, bleiben dunkel.
static func machine_model(id: String, host: Node) -> Node3D:
	var root := Node3D.new()
	var spec: Array = MACHINES[id]
	var m: Node3D = load(spec[0]).new()
	for key in spec[1]:
		m.set(key, spec[1][key])
	host.add_child(m)
	var inv := m.global_transform.affine_inverse()
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.06, 0.08, 0.1)
	screen.roughness = 0.2
	for n in m.find_children("*", "", true, false):
		if not (n is MeshInstance3D or n is Label3D) or not n.is_visible_in_tree():
			continue
		var copy: Node3D
		if n is MeshInstance3D:
			if n.mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = n.mesh
			mi.material_override = _no_viewport(n.material_override, screen)
			for i in n.get_surface_override_material_count():
				mi.set_surface_override_material(i, _no_viewport(n.get_surface_override_material(i), screen))
			copy = mi
		else:
			copy = n.duplicate(0)
		copy.transform = inv * n.global_transform
		root.add_child(copy)
	host.remove_child(m)
	m.free()
	return root


static func _no_viewport(mat: Material, screen: Material) -> Material:
	if mat is BaseMaterial3D and mat.albedo_texture is ViewportTexture:
		return screen
	return mat


func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var b: AABB = n.global_transform * (n as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box
