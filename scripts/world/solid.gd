class_name Solid
extends RefCounted
## Genaue Kollision für lose Gegenstände. Maschinen, Behälter und Möbel haben für die Spielfigur und die
## Fahrzeuge grobe Hüllen (Quader auf Ebene 1): daran läuft man entlang und darauf zielt man. Fallende Teile
## sollen aber auf dem liegen, was man sieht: auf dem Maschinenbett, in der Spänewanne, im Spänebehälter.
## add() gibt deshalb jedem sichtbaren Netz unter einem Knoten einen eigenen Körper auf DETAIL_LAYER
## (Quader und Zylinder als solche, fertige Modelle als Dreiecksnetz). Lose Gegenstände (DroppedItem) stoßen
## nur an diese Körper und nicht mehr an die Hüllen desselben Knotens.

const DETAIL_LAYER := 1 << 6
const HULL_GROUP := "solid_hull"          # grobe Hüllen, durch die lose Gegenstände hindurchfallen
const DETAIL_GROUP := "solid_detail"
const ITEM_GROUP := "dropped_item"        # = DroppedItem.GROUP, als Text: Solid muss ohne Autoloads kompilieren
const ITEM_LAYER := 1 << 4                # = DroppedItem.LAYER
const SKIP_META := "no_solid"             # Knoten (samt allem darunter) ohne genaue Kollision
const MIN_SIZE := 0.03                    # kleinere Netze (Schrauben, Knöpfe) zählen nicht
const MAX_FACES := 60000                  # größere Netze bleiben bei der Hülle

static var _shapes := {}                  # Schlüssel aus Netz und Maßstab -> Shape3D


## Genaue Kollision für alles Sichtbare unter root anlegen und die groben Hüllen unter root für lose
## Gegenstände durchlässig machen. root muss im Baum hängen. Liefert die Zahl der neuen Körper.
## moving: root wird getragen oder gefahren (Spänebehälter am Kran, auf der Gabel). Die Körper nehmen dann
## mit, was auf ihnen liegt.
static func add(root: Node3D, moving := false) -> int:
	if root == null or not root.is_inside_tree():
		return 0
	var made := 0
	var hulls: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_meta(SKIP_META) or n.is_in_group(DETAIL_GROUP):
			continue
		if n is CollisionObject3D:
			if n is StaticBody3D and ((n as StaticBody3D).collision_layer & 1) != 0 and not n.is_in_group(HULL_GROUP):
				n.add_to_group(HULL_GROUP)
				hulls.append(n)
			# Quader, die selbst der Körper sind (Build.box mit Kollision): Ihr Netz hängt darunter
			stack.append_array(n.get_children())
			continue
		if n is Node3D and not (n as Node3D).visible:
			continue
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and not n.has_meta("soft"):
			if _add_body(n as MeshInstance3D, moving):
				made += 1
	if not hulls.is_empty():
		for it in root.get_tree().get_nodes_in_group(ITEM_GROUP):
			for h in hulls:
				(it as PhysicsBody3D).add_collision_exception_with(h)
	return made


## Körper für ein Netz. Hängt am Netz und fährt mit ihm mit. Der Maßstab des Knotens steckt in der Form,
## der Körper selbst bleibt unskaliert.
static func _add_body(mi: MeshInstance3D, moving := false) -> bool:
	var scale := mi.global_transform.basis.get_scale()
	if scale.x < 0.0001 or scale.y < 0.0001 or scale.z < 0.0001:
		return false
	var box := mi.mesh.get_aabb()
	var size := box.size * scale
	if maxf(size.x, maxf(size.y, size.z)) < MIN_SIZE:
		return false
	var shape := _shape_for(mi.mesh, scale)
	if shape == null:
		return false
	var body: StaticBody3D = StaticBody3D.new()
	if moving:
		# Bewegter Körper, der mit seinem Elternknoten fährt (sync_to_physics folgt nur eigenen Bewegungen)
		var carried := AnimatableBody3D.new()
		carried.sync_to_physics = false
		body = carried
	body.name = "Solid"
	body.add_to_group(DETAIL_GROUP)
	body.collision_layer = DETAIL_LAYER
	# Getragene Körper sehen die losen Gegenstände: So wecken sie, was auf ihnen ruht, und nehmen es mit
	body.collision_mask = ITEM_LAYER if moving else 0
	body.transform = Transform3D(Basis.from_scale(Vector3.ONE / scale), Vector3.ZERO)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# Quader und Zylinder sitzen um ihre Mitte, das Netz kann versetzt sein (nur bei Dreiecksnetzen nicht nötig)
	if not shape is ConcavePolygonShape3D:
		cs.position = box.get_center() * scale
	body.add_child(cs)
	mi.add_child(body)
	return true


static func _shape_for(mesh: Mesh, scale: Vector3) -> Shape3D:
	var key := "%d|%.4f|%.4f|%.4f" % [mesh.get_instance_id(), scale.x, scale.y, scale.z]
	if _shapes.has(key):
		return _shapes[key]
	var shape: Shape3D = null
	if mesh is BoxMesh:
		var b := BoxShape3D.new()
		b.size = (mesh as BoxMesh).size * scale
		shape = b
	elif mesh is CylinderMesh and is_equal_approx((mesh as CylinderMesh).top_radius, (mesh as CylinderMesh).bottom_radius) \
			and absf(scale.x - scale.z) < 0.001:
		var c := CylinderShape3D.new()
		c.radius = (mesh as CylinderMesh).top_radius * scale.x
		c.height = (mesh as CylinderMesh).height * scale.y
		shape = c
	elif mesh is SphereMesh and absf(scale.x - scale.y) < 0.001 and absf(scale.x - scale.z) < 0.001:
		var s := SphereShape3D.new()
		s.radius = (mesh as SphereMesh).radius * scale.x
		shape = s
	elif mesh is QuadMesh or mesh is PlaneMesh:
		shape = null                         # Schilder und Anzeigen
	elif mesh.resource_path != "":
		# Nur fertige Modelle. Netze, die das Spiel selbst baut (Werkstück, Späne), ändern sich laufend.
		var faces := mesh.get_faces()
		if faces.size() >= 3 and faces.size() <= MAX_FACES * 3:
			if not scale.is_equal_approx(Vector3.ONE):
				for i in faces.size():
					faces[i] = faces[i] * scale
			var tri := ConcavePolygonShape3D.new()
			tri.backface_collision = true      # dünne Bleche halten von beiden Seiten
			tri.set_faces(faces)
			shape = tri
	_shapes[key] = shape
	return shape


## Hüllpunkte eines Modells für eine konvexe Kollisionsform: je Richtung der äußerste Punkt aller Netze
## unter model, im Koordinatensystem von frame. So bleibt die Form klein (höchstens 26 Punkte) und folgt
## trotzdem dem Umriss: Ein Quader behält seine acht Ecken, ein Meißel wird zum Keil.
static func hull_points(model: Node3D, frame: Transform3D) -> PackedVector3Array:
	var dirs: Array[Vector3] = []
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x != 0 or y != 0 or z != 0:
					dirs.append(Vector3(x, y, z).normalized())
	var best: Array[Vector3] = []
	var far: Array[float] = []
	best.resize(dirs.size())
	far.resize(dirs.size())
	far.fill(-INF)
	var inv := frame.affine_inverse()
	var any := false
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			for v in arr[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = xf * v
				any = true
				for d in dirs.size():
					var w := p.dot(dirs[d])
					if w > far[d]:
						far[d] = w
						best[d] = p
	var out := PackedVector3Array()
	if not any:
		return out
	for p in best:
		var dup := false
		for q in out:
			if q.distance_squared_to(p) < 0.000001:
				dup = true
				break
		if not dup:
			out.append(p)
	return out
