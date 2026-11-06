class_name ToolPreview
extends SubViewportContainer
## Sich drehende 3D-Vorschau eines Werkzeugs aus MillTools.

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
}

var model_id := ""
var _spin: Node3D


func _ready() -> void:
	stretch = true
	custom_minimum_size.y = 170.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vp := SubViewport.new()
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

	var tilt := Node3D.new()
	vp.add_child(tilt)
	_spin = Node3D.new()
	tilt.add_child(_spin)
	var model := MillTools.build(model_id)
	_spin.add_child(model)

	var box := _bounds(model)
	model.position = -box.get_center()
	var view: Dictionary = VIEWS.get(model_id, {"tilt": Vector3.ZERO, "wide": false, "dist": 1.0})
	tilt.rotation = view["tilt"]

	var cam := Camera3D.new()
	cam.fov = FOV
	cam.keep_aspect = Camera3D.KEEP_WIDTH if view["wide"] else Camera3D.KEEP_HEIGHT
	var dist := box.size.length() * 0.55 * float(view["dist"]) / tan(deg_to_rad(FOV * 0.5))
	cam.position = Vector3(0, 0, dist)
	cam.near = dist * 0.1
	cam.far = dist * 4.0
	vp.add_child(cam)


func _process(delta: float) -> void:
	if _spin and is_visible_in_tree():
		_spin.rotation.y += SPIN * delta


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
