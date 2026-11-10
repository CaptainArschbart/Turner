class_name Forklift
extends CharacterBody3D
## Gabelstapler aus models/forklift.glb. Die Spielfigur steigt mit E ein, sitzt auf dem Fahrersitz und schaut
## frei herum. Gefahren wird mit WASD (Hinterradlenkung wie beim echten Stapler: der Wagen schwenkt um die
## Vorderachse). Pfeil hoch / runter heben und senken die Gabel, Pfeil links / rechts verschieben sie seitlich
## (Seitenschieber), Bild auf / Bild ab neigen das Hubgerüst nach vorn / hinten. Steht die abgesenkte
## Gabel in einem Palettenstapel, nimmt sie ihn beim Heben mit; abgesenkt setzt sie ihn am Boden oder auf
## einem anderen Stapel ab. E steigt aus, der Stapler bleibt dann als Ausstattung (Shelf "forklift") stehen.
## Koordinaten: x nach vorn (Gabel), Mitte der Grundfläche im Ursprung; rotation.y = phi, vorn = (cos phi, -sin phi).

const PATH := "res://models/forklift.glb"
## Maße im Modell (Blender-Einheiten): Boden, Mitte der Länge, Lage von Gabel und Achsen entlang Modell-z
const S := 0.0042                       # 514 Einheiten Höhe -> 2,16 m
const GROUND_U := -199.0
const CENTER_U := -137.35               # Mitte zwischen Gabelspitze (-519,7) und Heck (245)
const CARRIAGE_U := -286.0              # alles weiter vorn gehört zum Gabelträger (hebt sich mit)
const MAST_U := Vector2(-279.0, -219.0) # Hubgerüst
const TILT_PIVOT_U := Vector3(0.0, -160.0, -250.0)   # Drehpunkt der Neigung: unten am Hubgerüst
const REAR_U := 80.0                    # hinten: die gelenkten Hinterräder
const LENGTH := 3.21
const WIDTH := 1.15
const HEIGHT := 2.16
## Im Fahrzeug (Meter, x nach vorn)
const FORK_CENTER := 1.145              # Mitte der Gabelzinken
const FORK_TIP := 1.606
const FRONT_AXLE := 0.262
const WHEELBASE := 1.45
const SEAT := Vector3(-0.62, 0.36, 0.0) # Standpunkt der Figur (Augen 1,62 m darüber)
const BODY_X := Vector2(-1.60, 0.69)    # Fahrgestell bis Hubgerüst, ohne Gabel (die fährt in Paletten)
## Fahren
const MAX_V := 3.0
const MAX_REV := 1.6
const ACCEL := 2.2
const BRAKE := 4.5
const MAX_STEER := 0.75                 # rad an den Hinterrädern
const STEER_RATE := 2.2
## Gabel
const MAX_LIFT := 1.8                   # Unterkante der Gabel über dem Boden
const STAGE := 0.8                      # bis hier fährt nur der Gabelträger, darüber auch der Innenmast
const LIFT_SPEED := 0.45
const PICK_TOL_DEG := 12.0              # so schräg darf die Gabel in den Stapel fahren
const PICK_HEIGHT_TOL := 0.05           # so genau muss die Gabel auf Höhe einer Palettenunterkante stehen
const MAX_SHIFT := 0.1                  # Seitenschieber: so weit nach links und rechts (m)
const SHIFT_SPEED := 0.15
const TILT_FWD := deg_to_rad(3.0)       # Neigung nach vorn
const TILT_BACK := deg_to_rad(6.0)      # Neigung nach hinten (zum Fahrer)
const TILT_SPEED := deg_to_rad(4.0)
const DUMP_TIME := 1.6                  # so lange kippt der Behälter über dem Container
const DUMP_ANGLE := 1.25                # so weit (rad) kippt er dabei nach vorn

var phi := 0.0
var speed := 0.0
var steer := 0.0
var lift := 0.0
var load_n := 0                         # Paletten auf der Gabel
var load_rot := 0                       # ihre Drehung zur Gabel in 90°-Schritten
var shift := 0.0                        # Seitenschieber in Fahrzeug-z (+ = rechts, Blick nach vorn)
var tilt := 0.0                         # Neigung des Hubgerüsts: + = nach hinten
var load_bin := -1                      # Spänebehälter auf der Gabel (Nummer in layout.bins), -1 = keiner
var dump_t := 0.0                       # läuft beim Auskippen herunter (Kippbewegung des Behälters)
var _tipped := false                    # Hubgerüst steht ganz vorn: nur einmal auskippen
## Spielwelt: forklift_pick(f) -> {"n", "rot"} oder {}, forklift_base(f) -> {"h", ...}, forklift_drop(f) -> Fehler
var world: Node
var driver: Node = null
var parts := {}                          # build_model: carriage, inner, rear, load
var _blocked_msg := 0.0


func _init() -> void:
	collision_layer = 0                  # nur der Stapler prüft gegen die Welt
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func _ready() -> void:
	parts = build_model(self)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(BODY_X.y - BODY_X.x, 1.4, WIDTH)
	cs.shape = bx
	cs.position = Vector3((BODY_X.x + BODY_X.y) * 0.5, 0.75, 0)
	add_child(cs)
	pose(parts, lift, load_n, load_rot, steer, shift, tilt)


## Modell in parent aufbauen und die beweglichen Teile zurückgeben.
static func build_model(parent: Node3D) -> Dictionary:
	var out := {}
	var scene := load(PATH) as PackedScene
	if scene == null:
		Build.box(parent, Vector3(BODY_X.y - BODY_X.x, 1.2, WIDTH), Vector3((BODY_X.x + BODY_X.y) * 0.5, 0.6, 0), Build.mat(Color(0.95, 0.6, 0.05), 0.5))
		var fallback := Node3D.new()
		parent.add_child(fallback)
		out["carriage"] = fallback
		out["load"] = Node3D.new()
		fallback.add_child(out["load"])
		(out["load"] as Node3D).position = Vector3(FORK_CENTER, 0, 0)
		return out
	var pivot := Node3D.new()
	pivot.rotation.y = -PI / 2.0           # Modell-vorn (-Z) zeigt nach +X
	parent.add_child(pivot)
	var m := scene.instantiate() as Node3D
	m.scale = Vector3.ONE * S
	m.position = Vector3(0, -GROUND_U * S, -CENTER_U * S)
	pivot.add_child(m)
	# Teile nach ihrer Lage im Modell sortieren: Gabelträger, Hubgerüst, Hinterräder. Hubgerüst, Innenmast
	# und Gabelträger hängen an einem Drehpunkt unten am Gerüst und neigen sich gemeinsam.
	var tilt_n := Node3D.new()
	tilt_n.name = "Neigung"
	tilt_n.position = TILT_PIVOT_U
	m.add_child(tilt_n)
	var mast := Node3D.new()
	mast.name = "Hubgeruest"
	mast.position = -TILT_PIVOT_U
	tilt_n.add_child(mast)
	var carriage := Node3D.new()
	carriage.name = "Gabeltraeger"
	carriage.position = -TILT_PIVOT_U
	carriage.set_meta("base", -TILT_PIVOT_U)
	tilt_n.add_child(carriage)
	var inner := Node3D.new()
	inner.name = "Innenmast"
	inner.position = -TILT_PIVOT_U
	inner.set_meta("base", -TILT_PIVOT_U)
	tilt_n.add_child(inner)
	var rear := Node3D.new()
	rear.name = "Hinterachse"
	m.add_child(rear)
	var rear_box := AABB()
	var rear_first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		var bb: AABB = node.transform * node.mesh.get_aabb()
		if bb.end.z <= CARRIAGE_U:
			_move(node, carriage)
		elif bb.position.z >= MAST_U.x and bb.end.z <= MAST_U.y:
			# Innenmast: Kopie des Hubgerüsts, etwas schmaler, fährt im zweiten Hub mit hoch
			var copy := node.duplicate() as MeshInstance3D
			copy.transform = Transform3D(Basis.from_scale(Vector3(0.9, 1.0, 1.0)), Vector3.ZERO) * node.transform
			copy.transform.origin.z -= 3.0
			inner.add_child(copy)
			_move(node, mast)
		elif bb.position.z >= REAR_U:
			rear_box = bb if rear_first else rear_box.merge(bb)
			rear_first = false
			_move(node, rear)
	_texture(m)
	# Hinterachse dreht sich zum Lenken um ihre Mitte
	if not rear_first:
		var c := rear_box.get_center()
		rear.position = Vector3(c.x, 0, c.z)
		for ch in rear.get_children():
			(ch as Node3D).position -= Vector3(c.x, 0, c.z)
	# Last sitzt mittig auf den Zinken und hängt am Gabelträger (hebt, schiebt und neigt sich mit). Der
	# Gabelträger liegt in Modelleinheiten und gedreht: zurückrechnen in Meter und Fahrzeugrichtung.
	var load := Node3D.new()
	load.name = "Last"
	carriage.add_child(load)
	load.scale = Vector3.ONE / S
	load.rotation.y = PI / 2.0
	load.position = Vector3(0.0, GROUND_U, CENTER_U - FORK_CENTER / S)
	out["tilt"] = tilt_n
	out["carriage"] = carriage
	out["inner"] = inner
	out["rear"] = rear
	out["load"] = load
	return out


## Graue Flächen des Modells bekommen Texturen: Gabel und Hubgerüst Stahl, Reifen Gummi mit Profil,
## Felgen und das dunkle Fahrgestell Pulverlack. Die Textur liegt im Modell (nicht in der Welt), damit sie
## beim Fahren nicht über die Teile wandert.
static func _texture(m: Node3D) -> void:
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.mesh == null:
			continue
		var bb: AABB = node.transform * node.mesh.get_aabb()
		for i in node.mesh.get_surface_count():
			var mat := node.mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null:
				continue
			# Grau = kaum Farbsättigung (Godot rechnet die Modellfarben in sRGB um: 0,8 -> 0,91, 0,23 -> 0,52)
			var c := mat.albedo_color
			if maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) > 0.08:
				continue
			if c.r > 0.75:
				# hellgrau: Reifen (berühren den Boden), Felgen (in den Rädern), sonst Gabel / Hubgerüst
				if bb.position.y < GROUND_U + 12.0:
					node.set_surface_override_material(i, _tex("rubber"))
				elif bb.end.y < -40.0 and (bb.position.z > 80.0 or bb.end.z < -120.0):
					node.set_surface_override_material(i, _tex("rim"))
				else:
					node.set_surface_override_material(i, _tex("steel"))
			else:
				node.set_surface_override_material(i, _tex("dark"))


static var _tex_cache := {}


static func _tex(kind: String) -> Material:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var base: StandardMaterial3D
	var per_m := 1.0                     # Textur-Wiederholungen je Meter
	match kind:
		"steel":
			base = HallTex.powder(Color(0.42, 0.43, 0.45), 0.4)
			per_m = 1.2
		"rim":
			base = HallTex.powder(Color(0.62, 0.63, 0.6), 0.3)
			per_m = 2.0
		"dark":
			base = HallTex.powder(Color(0.23, 0.235, 0.25), 0.3)
			per_m = 1.0
		_:
			base = _rubber()
			per_m = 3.0
	var m := base.duplicate() as StandardMaterial3D
	if kind == "steel":
		m.metallic = 0.55
		m.roughness = 0.45
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE * per_m * S
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tex_cache[kind] = m
	return m


## Reifengummi: fast schwarz, feines Korn und Profilrillen.
static func _rubber() -> StandardMaterial3D:
	var size := 128
	var noise := FastNoiseLite.new()
	noise.seed = 71
	noise.frequency = 0.3
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var height := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		var groove := fposmod(float(y) / size * 6.0, 1.0) < 0.22
		for x in size:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var v := 0.05 + n * 0.035 - (0.02 if groove else 0.0)
			albedo.set_pixel(x, y, Color(v, v, v * 1.05))
			var hv := 0.3 if groove else 0.7 + n * 0.1
			height.set_pixel(x, y, Color(hv, hv, hv))
	albedo.generate_mipmaps()
	height.bump_map_to_normal_map(6.0)
	height.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(albedo)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(height)
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _move(node: Node3D, to: Node3D) -> void:
	var xf := node.transform
	node.owner = null
	node.get_parent().remove_child(node)
	to.add_child(node)
	node.transform = xf


## Gabelhöhe, Seitenschieber, Neigung, Last und Lenkung auf das Modell übertragen.
static func pose(p: Dictionary, lift_m: float, n: int, rot: int, steer_rad := 0.0, shift_m := 0.0, tilt_rad := 0.0) -> void:
	if p.is_empty():
		return
	var c: Node3D = p["carriage"]
	if p.has("inner"):
		# Modell: Einheiten, Fahrzeug-z = Modell-x
		c.position = (c.get_meta("base") as Vector3) + Vector3(shift_m, lift_m, 0.0) / S
		var inn: Node3D = p["inner"]
		inn.position = (inn.get_meta("base") as Vector3) + Vector3(0.0, maxf(lift_m - STAGE, 0.0) / S, 0.0)
		(p["tilt"] as Node3D).rotation.x = tilt_rad
	else:
		c.position = Vector3(0.0, lift_m, shift_m)
	if p.has("rear"):
		(p["rear"] as Node3D).rotation.y = -steer_rad
	var holder: Node3D = p["load"]
	if holder.get_child_count() != n or int(holder.get_meta("rot", -1)) != rot:
		for ch in holder.get_children():
			holder.remove_child(ch)
			ch.queue_free()
		if n > 0:
			var stack := Node3D.new()
			stack.rotation.y = rot * PI / 2.0
			holder.add_child(stack)
			Shelf.add_pallets(stack, n)
		holder.set_meta("rot", rot)


# ------------------------------------------------------------ Fahren

func forward() -> Vector2:
	return Vector2(cos(phi), -sin(phi))


func origin2() -> Vector2:
	return Vector2(global_position.x, global_position.z)


## Seitenrichtung des Fahrzeugs (lokal +z, Blick nach vorn rechts) in (x, z).
func side() -> Vector2:
	return Vector2(sin(phi), cos(phi))


## Mitte der Gabelzinken am Boden (x, z), mit Seitenschieber.
func fork_spot() -> Vector2:
	return origin2() + forward() * FORK_CENTER + side() * shift


func place(at: Vector2, angle: float) -> void:
	phi = angle
	rotation.y = phi
	global_position = Vector3(at.x, 0.0, at.y)


func seat_point() -> Vector3:
	return to_global(SEAT)


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer_in := 0.0
	var lift_in := 0.0
	var shift_in := 0.0
	var tilt_in := 0.0
	if driver != null and is_instance_valid(driver) and not driver.build_mode:
		throttle = Input.get_axis("move_back", "move_forward")
		steer_in = Input.get_axis("move_right", "move_left")
		lift_in = Input.get_axis("fork_down", "fork_up")
		shift_in = Input.get_axis("fork_left", "fork_right")
		tilt_in = Input.get_axis("fork_tilt_fwd", "fork_tilt_back")
	drive(delta, throttle, steer_in, lift_in, shift_in, tilt_in)


## Ein Schritt mit den Eingaben -1..1: vor/zurück, links/rechts lenken, heben/senken, Seitenschieber
## (+ = nach rechts), Neigung (+ = nach hinten). Auch für Tests.
func drive(delta: float, throttle: float, steer_in: float, lift_in: float, shift_in := 0.0, tilt_in := 0.0) -> void:
	_blocked_msg = maxf(_blocked_msg - delta, 0.0)
	var target := throttle * (MAX_V if throttle > 0.0 else MAX_REV)
	var rate := ACCEL if absf(target) > absf(speed) and signf(target) == signf(speed) or is_zero_approx(speed) else BRAKE
	speed = move_toward(speed, target, rate * delta)
	steer = move_toward(steer, steer_in * MAX_STEER, STEER_RATE * delta)
	if absf(speed) > 0.001:
		# Hinterradlenkung: Die Vorderachse rollt geradeaus, das Heck schwenkt aus
		var f := forward()
		var axle := origin2() + f * FRONT_AXLE + f * speed * delta
		phi += speed * tan(steer) / WHEELBASE * delta
		var nf := forward()
		var new_origin := axle - nf * FRONT_AXLE
		var move := new_origin - origin2()
		rotation.y = phi
		velocity = Vector3(move.x, 0.0, move.y) / delta
		move_and_slide()
		if get_slide_collision_count() > 0:
			speed *= 0.2
		global_position.y = 0.0
	_lift(delta, lift_in)
	shift = clampf(shift + shift_in * SHIFT_SPEED * delta, -MAX_SHIFT, MAX_SHIFT)
	tilt = clampf(tilt + tilt_in * TILT_SPEED * delta, -TILT_FWD, TILT_BACK)
	pose(parts, lift, load_n, load_rot, steer, shift, tilt)
	# Spänebehälter: ganz nach vorn geneigt über einem Container wird er ausgekippt
	if load_bin >= 0 and world:
		if tilt <= -TILT_FWD + 0.0005 and not _tipped:
			_tipped = true
			if world.forklift_dump(self):
				dump_t = DUMP_TIME
		elif tilt > -TILT_FWD + 0.01:
			_tipped = false
		dump_t = maxf(dump_t - delta, 0.0)
		world.forklift_carry_bin(load_bin, (parts["load"] as Node3D).global_transform, load_rot, dump_angle())


## Wie weit der Behälter gerade nach vorn gekippt ist (rad): hoch und wieder zurück.
func dump_angle() -> float:
	if dump_t <= 0.0:
		return 0.0
	return DUMP_ANGLE * sin(PI * (1.0 - dump_t / DUMP_TIME))


func _lift(delta: float, lift_in: float) -> void:
	if is_zero_approx(lift_in):
		return
	var was := lift
	var floor_h := 0.0
	if load_n > 0 and world:
		floor_h = float(world.forklift_base(self).get("h", 0.0))
	lift = clampf(lift + lift_in * LIFT_SPEED * delta, floor_h if load_n > 0 else 0.0, MAX_LIFT)
	# Leere Gabel hebt an: Steckt sie in der k-ten Palette eines Stapels (Gabel auf Höhe ihrer Unterkante),
	# kommen diese und alle darüber mit. Ganz unten nimmt sie auch einen Spänebehälter.
	if load_n == 0 and load_bin < 0 and lift > was and world:
		var ph := float(Shelf.SIZES["pallet"]["height"])
		var k := roundi(was / ph)
		if absf(was - k * ph) <= PICK_HEIGHT_TOL:
			var got: Dictionary = world.forklift_pick(self, k)
			if got.has("n"):
				load_n = int(got["n"])
				load_rot = int(got["rot"])
			elif got.has("bin"):
				load_bin = int(got["bin"])
				load_rot = int(got["rot"])
	# Mit Last ganz abgesenkt: auf Boden oder Stapel absetzen
	if (load_n > 0 or load_bin >= 0) and lift_in < 0.0 and lift <= floor_h + 0.001 and world:
		var err: String = world.forklift_drop(self)
		if err == "":
			load_n = 0
			load_bin = -1
			lift = floor_h
		elif _blocked_msg <= 0.0:
			world.hud.show_message(err, Color(1, 0.75, 0.2))
			_blocked_msg = 2.0


## Wie weit die Gabel zur Palette schräg steht (Grad, 0..45), und die Drehung der Palette zur Gabel.
func align_to(pallet_rot: int) -> Array:
	var quarter := phi / (PI / 2.0)
	var nearest := roundi(quarter)
	var off := absf(quarter - nearest) * 90.0
	return [off, posmod(pallet_rot - nearest, 4)]


func get_state() -> Dictionary:
	return {"pos": [global_position.x, global_position.z], "angle": phi, "lift": lift, "load": load_n, "load_rot": load_rot,
		"shift": shift, "tilt": tilt}
