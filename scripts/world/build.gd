class_name Build
extends RefCounted
## Hilfsfunktionen, um Geometrie prozedural zu erzeugen.

enum { AXIS_X, AXIS_Y, AXIS_Z }

## Jeder Quader bekommt ein winziges eigenes Übermaß. Liegen zwei Flächen genau aufeinander, flimmern sie
## sonst, weil die Grafikkarte nicht entscheiden kann, welche vorne ist.
const OVERSIZE := [0.0002, 0.0005, 0.0008, 0.0011, 0.0014]
static var _next_oversize := 0


static func mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func emissive(c: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func glass(c := Color(0.75, 0.85, 0.9, 0.18)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Glas ist kein Metall: Die Spiegelung kommt allein über Specular und Fresnel, ohne Farbstich
	m.roughness = 0.04
	m.metallic = 0.0
	m.metallic_specular = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, collide := false, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	_next_oversize = (_next_oversize + 1) % OVERSIZE.size()
	bm.size = size + Vector3.ONE * float(OVERSIZE[_next_oversize])
	mi.mesh = bm
	mi.material_override = m
	if collide:
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation = rot
		parent.add_child(body)
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
	else:
		mi.position = pos
		mi.rotation = rot
		parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, axis := AXIS_Y,
		collide := false, segments := 24, r_top := -1.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r
	cm.top_radius = r if r_top < 0.0 else r_top
	cm.height = h
	cm.radial_segments = segments
	cm.rings = 1
	var rot := Vector3.ZERO
	if axis == AXIS_X:
		rot = Vector3(0, 0, PI / 2)
	elif axis == AXIS_Z:
		rot = Vector3(PI / 2, 0, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	if collide:
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation = rot
		parent.add_child(body)
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = maxf(r, cm.top_radius)
		sh.height = h
		cs.shape = sh
		body.add_child(cs)
	else:
		mi.position = pos
		mi.rotation = rot
		parent.add_child(mi)
	return mi


## Offene Wanne mit schrägen Wänden: unten bottom, oben top (Länge x, Breite z), Höhe h, Boden bei pos.
static func tub(parent: Node3D, bottom: Vector2, top: Vector2, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := [Vector3(-bottom.x, 0, -bottom.y) * 0.5, Vector3(bottom.x, 0, -bottom.y) * 0.5, Vector3(bottom.x, 0, bottom.y) * 0.5, Vector3(-bottom.x, 0, bottom.y) * 0.5]
	var d := [Vector3(-top.x * 0.5, h, -top.y * 0.5), Vector3(top.x * 0.5, h, -top.y * 0.5), Vector3(top.x * 0.5, h, top.y * 0.5), Vector3(-top.x * 0.5, h, top.y * 0.5)]
	for i in 4:
		var k := (i + 1) % 4
		for v in [c[i], d[i], c[k], c[k], d[i], d[k]]:
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func label(parent: Node3D, text: String, pos: Vector3, px := 0.004, color := Color.WHITE,
		font_size := 64, rot_y := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation.y = rot_y
	l.pixel_size = px
	l.font_size = font_size
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	parent.add_child(l)
	return l


static func collider(parent: Node3D, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	return body


## Hüllquader aller Meshes unter root in Weltkoordinaten (root muss im Baum hängen).
static func bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh:
			var b: AABB = n.global_transform * n.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box
