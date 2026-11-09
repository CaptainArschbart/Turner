class_name Player
extends CharacterBody3D
## Spielfigur (Zerspanungsmechaniker) mit 1st/3rd-Person-Kamera und Interaktion.

signal material_to_machine(machine: Node, flip: bool)
signal prompt_changed(text: String)
signal held_changed(text: String)
signal pin_requested(collider: Object, point: Vector3, normal: Vector3)

const WALK := 3.2
const SPRINT := 5.8
const CROUCH := 1.6
const JUMP := 4.2
const GRAVITY := 9.81
const REACH := 2.6               # so weit reicht der Sichtstrahl
const JACK_SPEED := 2.0          # Hubwagen ziehen oder schieben: langsam, ohne Rennen und Springen
const JACK_LOST_DIST := 3.0      # weiter von der Deichsel weg: Der Wagen bleibt stehen
const JACK_SPEED_LOADED := 1.6   # mit Last träger
const BUILD_REACH := 15.0        # im Baumodus sieht man weiter
const PALLET_NEAR := 0.9         # getragene Palette: so nah vor der Figur abstellen ...
const PALLET_FAR := 3.2          # ... und höchstens so weit weg
const PALLET_FLOOR := 0.0        # Bodenhöhe der Werkstatt

var head: Node3D
var cam: Camera3D
var tp_arm: SpringArm3D
var tp_cam: Camera3D
var ray: RayCast3D
var body: WorkerBody               # Figur (Außenansicht; in der Ego-Ansicht nur ihr Schatten)
var arms: ViewArms                # Unterarme und Hände vor der Kamera

var yaw := 0.0
var pitch := 0.0
var third_person := false
var operating: Node = null
var build_mode := false           # Baumodus: Das Anvisierte wird nicht bedient
var _focus: Node = null
var _on_part := false             # Blick liegt auf dem eingespannten Teil
var carry: Dictionary = {}        # Rohmaterial in den Händen
var _prompt := ""
var _last_look := Vector2.ZERO
var _was_floor := true
var _fall_speed := 0.0
var _bob_t := 0.0                 # Schrittphase des Kopfwippens
var _bob := 0.0                   # Stärke des Wippens, blendet beim Anhalten weich aus
var _dip := 0.0                   # Einfedern nach einer Landung
## Werkzeug in der Hand: {"machine", "id", "name"}, leer = Hand frei
var held: Dictionary = {}
var gate: Callable                # Spielwelt: ist dieses Ziel gerade gesperrt? (Ziel, nur prüfen)
var _hand: Node3D                 # Gegenstand in der Ego-Ansicht (sitzt in arms)
var drawing_texture: Callable     # Spielwelt: Bild der Zeichnung zu einem Auftrag
var cigarette: Cigarette          # Zigarette im Mundwinkel, die Hände bleiben frei
var machine_lookup: Callable      # Spielwelt: Maschinen-id -> Maschine
var pallet_drop: Callable         # Spielwelt: getragene Palette bei (x, z) abstellen -> Fehlertext
var jack_lift: Callable           # Spielwelt: Leertaste mit Hubwagen (Palette anheben oder absenken)
var jack_drop: Callable           # Spielwelt: Hubwagen loslassen und abstellen (E oder Q)
var jack_abandon: Callable        # Spielwelt: Hubwagen sofort an seiner Stelle abstellen (Figur zu weit weg)
var jack_cart: JackCart           # der Hubwagen selbst: eigener Körper in der Welt
var noclip := false               # Debug: fliegen und durch Wände gehen
var player_id := "local"          # wem Zuhause und Sachen gehören; im Multiplayer je Spieler eindeutig
var location := "site"            # Ort laut Places: "site", "supermarket" oder "home:<player_id>"


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	head = Node3D.new()
	head.position.y = 1.62
	add_child(head)
	cam = Camera3D.new()
	cam.near = 0.03
	head.add_child(cam)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.add_exception(self)
	ray.collision_mask = 1 | DroppedItem.LAYER
	cam.add_child(ray)
	arms = ViewArms.new()
	cam.add_child(arms)
	_hand = arms.item

	tp_arm = SpringArm3D.new()
	tp_arm.spring_length = 2.6
	tp_arm.margin = 0.15
	tp_arm.position = Vector3(0.45, 0.15, 0)
	tp_arm.add_excluded_object(get_rid())
	head.add_child(tp_arm)
	tp_cam = Camera3D.new()
	tp_arm.add_child(tp_cam)

	_build_body()
	cigarette = Cigarette.new()
	cigarette.player = self
	add_child(cigarette)
	_update_camera()
	Settings.changed.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	cam.fov = float(Settings.graphics["fov"])
	tp_cam.fov = float(Settings.graphics["fov"])


func _build_body() -> void:
	body = WorkerBody.new()
	add_child(body)


func _update_camera() -> void:
	if operating:
		return
	if third_person:
		tp_cam.make_current()
	else:
		cam.make_current()
	body.visible = true
	body.set_shadow_only(not third_person)
	arms.visible = not third_person
	_hand.visible = true


# ------------------------------------------------------------ Eingabe

func _unhandled_input(event: InputEvent) -> void:
	# Rauchen geht überall, auch beim Bedienen einer Maschine
	if event.is_action_pressed("smoke") and not event.is_echo():
		get_viewport().set_input_as_handled()
		cigarette.toggle()
		return
	if operating:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := float(Settings.mouse["sensitivity"]) * 0.01
		var inv := -1.0 if bool(Settings.mouse["invert_y"]) else 1.0
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s * inv, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if click_focus():
			get_viewport().set_input_as_handled()
			arms.poke(hands_free())
			if hands_free():
				body.poke()
		# Nichts anvisiert und eine brennt: Linksklick nimmt einen Zug
		elif cigarette.take_drag():
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if right_click_focus():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop") and not event.is_echo():
		if drop():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_view"):
		third_person = not third_person
		_update_camera()
	elif event.is_action_pressed("interact") and driving_jack() and not build_mode:
		get_viewport().set_input_as_handled()
		if jack_drop.is_valid():
			jack_drop.call()
	elif event.is_action_pressed("jump") and not event.is_echo() and driving_jack() and not build_mode:
		get_viewport().set_input_as_handled()
		if jack_lift.is_valid():
			jack_lift.call()
	elif event.is_action_pressed("interact") and _focus:
		get_viewport().set_input_as_handled()
		if not _blocked(_focus, false):
			_focus.interact(self)


## Linksklick auf das anvisierte Ziel. Gibt true zurück, wenn es darauf reagiert.
func _blocked(target: Node, silent: bool) -> bool:
	return gate.is_valid() and gate.call(target, silent)


## Rechtsklick auf die Maschine: Teil andersherum einspannen, aus den Händen oder das schon eingespannte.
func right_click_focus() -> bool:
	if driving_jack():
		return false
	# Zeichnung in der Hand: wieder weglegen
	if carrying_drawing():
		clear_carry()
		return true
	if not _focus or not _focus.has_method("get_machine") or _blocked(_focus, false):
		return false
	var machine: Node = _focus.get_machine()
	if carrying_bin() or not held.is_empty() or (carry.is_empty() and machine.get("has_part") != true):
		return false
	material_to_machine.emit(machine, true)
	return true


func click_focus() -> bool:
	# Hubwagen: Linksklick tut nichts, E nimmt Paletten auf und setzt sie ab, Q stellt den Hubwagen ab
	if driving_jack():
		return true
	# Palette in den Händen: Linksklick tut nichts, abgestellt wird mit Q, aufgelegt mit E
	if carrying_pallet():
		return true
	# Zeichnung in der Hand: an die anvisierte Fläche pinnen, egal was es ist
	if carrying_drawing():
		if ray.is_colliding():
			pin_requested.emit(ray.get_collider(), ray.get_collision_point(), ray.get_collision_normal())
		return true
	if _focus and _blocked(_focus, false):
		return true
	if _focus and not carry.is_empty() and _focus.has_method("get_machine"):
		material_to_machine.emit(_focus.get_machine(), false)
		return true
	# Freie Hände auf dem eingespannten Teil: ausspannen, umspannen oder die Spanntiefe ändern
	if _focus and hands_free() and _on_part:
		material_to_machine.emit(_focus.get_machine(), false)
		return true
	if _focus and _focus.has_method("click"):
		_focus.click(self)
		return true
	return false


func _physics_process(delta: float) -> void:
	# Teleport, Ortswechsel oder Noclip: Entfernt sich die Figur von ihrem Wagen, lässt sie ihn stehen
	if jack_cart and Vector2(global_position.x, global_position.z).distance_to(jack_cart.pivot()) > JACK_LOST_DIST:
		if jack_abandon.is_valid():
			jack_abandon.call()
		else:
			clear_carry()
	# Im Noclip bleibt die Figur auch in einem offenen Menü in der Luft stehen
	if noclip and operating:
		velocity = Vector3.ZERO
		_set_prompt("")
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if operating:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_set_prompt("")
		return

	rotation.y = yaw
	head.rotation.x = pitch
	head.rotation.z = 0.0
	if cigarette.craving:
		# Entzug: Der Blick zittert leicht
		var t := Time.get_ticks_msec() * 0.001
		head.rotation.x += (sin(t * 23.0) + sin(t * 37.0)) * 0.0025
		head.rotation.z = sin(t * 17.0) * 0.004
	var crouch := Input.is_action_pressed("crouch") and not driving_jack()
	head.position.y = lerpf(head.position.y, 1.0 if crouch else 1.62, 10.0 * delta)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if noclip:
		_fly(delta, input)
		return
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := WALK
	if driving_jack():
		speed = JACK_SPEED_LOADED if jack_load() > 0 else JACK_SPEED
	elif crouch:
		speed = CROUCH
	elif Input.is_action_pressed("sprint") and not cigarette.craving:
		speed = SPRINT
	speed *= cigarette.work_factor()
	var accel := 12.0 if is_on_floor() else 3.0
	if driving_jack() and jack_load() > 0:
		accel = 5.0            # mit Last träger anfahren
	velocity.x = lerpf(velocity.x, dir.x * speed, accel * delta)
	velocity.z = lerpf(velocity.z, dir.z * speed, accel * delta)
	if Input.is_action_just_pressed("jump") and is_on_floor() and not driving_jack():
		velocity.y = JUMP
	_fall_speed = -velocity.y
	move_and_slide()
	_drive_jack()
	_animate(delta)
	_update_focus()


func _animate(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var crouch := Input.is_action_pressed("crouch") and not driving_jack()
	var sprint := Input.is_action_pressed("sprint") and not crouch and not driving_jack()
	var grounded := is_on_floor()
	var landed := 0.0
	if grounded and not _was_floor:
		landed = clampf(_fall_speed / 6.0, 0.2, 1.0)
	_was_floor = grounded
	var look := Vector2(yaw, pitch)
	var dl := look - _last_look
	_last_look = look
	body.pose(delta, hspeed, grounded, crouch, sprint, pitch)
	arms.walk_phase = body.walk_phase()
	arms.update(delta, hspeed, grounded, sprint, dl, landed)
	_head_bob(delta, hspeed, grounded, sprint, landed)


## Debug-Noclip: in Blickrichtung fliegen, ohne Schwerkraft und Kollision. Springen hoch, Ducken runter.
func _fly(delta: float, input: Vector2) -> void:
	var dir := cam.global_basis * Vector3(input.x, 0, input.y)
	if Input.is_action_pressed("jump"):
		dir.y += 1.0
	if Input.is_action_pressed("crouch"):
		dir.y -= 1.0
	var speed := 18.0 if Input.is_action_pressed("sprint") else 6.0
	velocity = Vector3.ZERO
	global_position += dir.limit_length(1.0) * speed * delta
	cam.position = Vector3.ZERO
	cam.rotation.z = 0.0
	_update_focus()


## Laufanimation der Ego-Kamera: Der Kopf hebt und senkt sich je Schritt, pendelt beim Gehen leicht zur Seite
## und rollt mit. Rennen schwingt weiter aus, nach einer Landung federt der Kopf kurz ein.
func _head_bob(delta: float, hspeed: float, grounded: bool, sprint: bool, landed: float) -> void:
	var moving := clampf(hspeed / WALK, 0.0, 1.6) if grounded else 0.0
	_bob = move_toward(_bob, moving, delta * 4.0)
	# Gleicher Takt wie der Gehzyklus der Figur: zwei Schritte je Periode. Oben über dem Standbein,
	# unten beim Fersenaufsatz, seitlich mit dem Gewicht aufs Standbein.
	_bob_t = body.walk_phase()
	var run := 1.0 if sprint and hspeed > WALK + 0.5 else 0.0
	var up := (absf(cos(_bob_t)) - 0.6) * (0.04 + run * 0.02) * _bob
	var side := cos(_bob_t) * (0.016 + run * 0.006) * _bob
	if landed > 0.0:
		_dip = maxf(_dip, landed * 0.09)
	_dip = move_toward(_dip, 0.0, delta * 0.45)
	cam.position = Vector3(side, up - 0.02 * _bob - _dip, 0.0)
	cam.rotation.z = -cos(_bob_t) * 0.006 * _bob


func set_build_mode(on: bool) -> void:
	build_mode = on
	ray.target_position.z = -BUILD_REACH if on else -REACH
	_focus = null


func _update_focus() -> void:
	if build_mode:
		_focus = null
		_set_prompt("")
		return
	var target: Node = null
	_on_part = false
	if ray.is_colliding():
		var c := ray.get_collider()
		if c and c.has_meta("interact"):
			target = c.get_meta("interact")
			# Blick aufs eingespannte Teil: Das Teil geht vor der Werkzeugaufnahme
			if hands_free() and target.has_method("get_machine") and _aims_at_part(target.get_machine()):
				target = target.get_machine()
				_on_part = true
			# Maschinen lenken den Blick auf ihre Werkzeugaufnahme um, wenn er dorthin zeigt
			elif target.has_method("focus_for"):
				target = target.focus_for(ray.global_position, -ray.global_transform.basis.z)
	# Mit dem Hubwagen zählen nur Leertaste (heben, senken) sowie E und Q (loslassen, abstellen)
	if driving_jack():
		_focus = null
		var act := "Palette absenken" if jack_load() > 0 else "Palette anheben (Zinken darunter)"
		_set_prompt("[%s] %s    [%s] Hubwagen loslassen" % [Settings.binding_text("jump"), act, Settings.binding_text("interact")])
		return
	# Mit einer Palette in den Händen zählen nur Palettenstapel und der Boden
	if carrying_pallet():
		if not (target is Shelf and (target as Shelf).is_pallet()):
			target = null
		_focus = target
		if target:
			_set_prompt(target.get_prompt())
		else:
			_set_prompt("[%s] Palette am Zielpunkt abstellen" % Settings.binding_text("drop"))
		return
	_focus = target
	if carrying_drawing():
		var where := "an diese Fläche" if ray.is_colliding() else "(auf eine Fläche zielen)"
		_set_prompt("[Linksklick] Zeichnung %s pinnen    [Rechtsklick] Weglegen" % where)
		return
	if target and _blocked(target, true):
		_set_prompt("Tag noch nicht gestartet: am Whiteboard im Büro")
		return
	var text: String = target.get_prompt() if target else ""
	if target and carrying_part() and target.has_method("get_machine") and not target.has_method("carry_prompt"):
		text = "[Linksklick] Teil wieder einspannen    [Rechtsklick] Andersherum    |    %s" % text
	elif target and not carry.is_empty() and target.has_method("get_machine"):
		if target.has_method("carry_prompt") and not carrying_bin():
			text = target.carry_prompt(carry)
		elif carrying_semi():
			text = "[Linksklick] Zum Schleifen einspannen    |    %s" % text
		else:
			text = "[Linksklick] Material einspannen    [Rechtsklick] Andersherum    |    %s" % text
	elif _on_part:
		text = "[Linksklick] Teil: Ausspannen, Umspannen, Spanntiefe    [Rechtsklick] Umdrehen    |    %s" % text
	_set_prompt(text)


## Zeigt der Blickstrahl auf das eingespannte Teil der Maschine?
func _aims_at_part(machine: Node) -> bool:
	if machine == null or machine.get("has_part") != true:
		return false
	var mi: Node3D = machine.get("workpiece_mi") if machine is Lathe else machine.get("_block_mi")
	if mi == null or not mi.is_visible_in_tree():
		return false
	var box := Build.bounds(mi).grow(0.015)
	var from := ray.global_position
	var to := ray.to_global(ray.target_position)
	return box.intersects_segment(from, to) != null


func _set_prompt(t: String) -> void:
	if t != _prompt:
		_prompt = t
		prompt_changed.emit(t)


# ------------------------------------------------------------ Maschinenbedienung

func start_operating(machine: Node, stand_pos: Vector3, face_yaw: float) -> void:
	operating = machine
	global_position = stand_pos
	yaw = face_yaw
	rotation.y = yaw
	pitch = -0.3
	body.visible = false
	arms.visible = false
	_hand.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func stop_operating() -> void:
	operating = null
	_update_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------ Werkzeug in der Hand

## Werkzeug id der Maschine in die Hand nehmen.
func set_held(machine: Node, id: String) -> void:
	if not carry.is_empty():
		return
	clear_held()
	held = {"machine": machine.MACHINE_ID, "id": id, "name": machine.tool_name(id)}
	var r := _mount_tool(_hand, machine.make_tool_model(id), machine.TOOL_UPRIGHT)
	arms.set_mode("tool", {"r": r})
	_mount_tool(body.tool_grip, machine.make_tool_model(id), machine.TOOL_UPRIGHT)
	body.set_holding("tool")
	held_changed.emit("In der Hand: %s" % held["name"])


## Werkzeugmodell so in den Halter setzen, dass die Faust das hintere Drittel des Schafts greift und
## die Schneide nach vorn (-Z des Halters) zeigt. Gibt den Griffradius zurück.
## Achtung: bei gekipptem Halter liegt die Kante nicht genau in der Faust - reicht fürs Auge.
func _mount_tool(holder: Node3D, model: Node3D, upright: bool) -> float:
	holder.add_child(model)
	if upright:
		model.rotation.x = PI / 2
	var bb: AABB = holder.global_transform.affine_inverse() * Build.bounds(model)
	var len := bb.size.z
	var grip_z := bb.end.z - clampf(len * 0.3, 0.025, 0.06)
	var c := bb.get_center()
	var r := minf(bb.size.x, bb.size.y) * 0.5
	if r <= 0.02:
		model.position -= Vector3(c.x, c.y, grip_z)
		return maxf(r, 0.008)
	# Dicker Halterblock: an der oberen rechten Kante fassen, damit Schneide und Halter sichtbar bleiben
	model.position -= Vector3(bb.end.x - 0.012, bb.end.y - 0.012, grip_z)
	return 0.012


## Trägt die Spielfigur gerade einen Spänebehälter?
func carrying_bin() -> bool:
	return str(carry.get("kind", "")) == "chip_bin"


## Trägt die Spielfigur eine leere Europalette?
func carrying_pallet() -> bool:
	return str(carry.get("kind", "")) == "pallet"


## Hat die Spielfigur gerade die Deichsel des Hubwagens in den Händen?
## carry: {"kind": "jack", "title", "load": Paletten auf der Gabel, "cross": quer?}, beim Speichern dazu "pos" und "rot".
func driving_jack() -> bool:
	return str(carry.get("kind", "")) == "jack"


func jack_load() -> int:
	return jack_cart.load_n if jack_cart else 0


## Liegt die Last quer zur Gabel (lange Palettenseite quer)?
func jack_cross() -> bool:
	return jack_cart != null and jack_cart.cross


## Last auf der Gabel ändern (aufgenommen oder abgesenkt): Die Gabel hebt oder senkt sich dabei.
func set_jack_load(n: int, cross := false) -> void:
	if jack_cart == null:
		return
	jack_cart.set_load(n, cross)
	carry["load"] = n
	carry["cross"] = cross and n > 0


## Gabelrichtung (x, z) als Einheitsvektor.
func jack_forward() -> Vector2:
	return jack_cart.forward() if jack_cart else Vector2(-sin(yaw), -cos(yaw))


## Bodenpunkt der Lastmitte auf der Gabel.
func jack_spot() -> Vector2:
	return jack_cart.load_spot() if jack_cart else Vector2(global_position.x, global_position.z)


## Mitte (Ursprung) des Hubwagens.
func jack_center() -> Vector2:
	return jack_cart.origin2() if jack_cart else Vector2(global_position.x, global_position.z)


## Wie weit der Wagen (plus extra) von einem 90°-Winkel entfernt steht (rad, immer >= 0), für das Einrasten.
func jack_snap_error(extra := 0.0) -> float:
	if jack_cart == null:
		return 0.0
	var a := jack_cart.phi + extra
	return absf(a - round(a / (PI / 2.0)) * (PI / 2.0))


## Drehung des Hubwagens in 90°-Schritten (Modell: Gabel zeigt entlang +X, wie Shelf.rotation.y).
func jack_rot() -> int:
	return posmod(int(round((jack_cart.phi if jack_cart else 0.0) / (PI / 2.0))), 4)


## Drehung (90°-Schritte) der Last auf der Gabel, wie sie beim Absenken am Boden steht.
func jack_load_rot() -> int:
	return posmod(jack_rot() + (1 if jack_cross() else 0), 4)


## Hubwagen übernehmen: Der Wagen ist ein eigener Körper in der Welt, die Figur hält den Griff der Deichsel.
## item darf "pos" [x, z] und "rot" (Drehung um Y) enthalten (Laden), sonst steht er vor der Figur.
func _set_carry_jack(item: Dictionary) -> void:
	clear_held()
	carry = item
	carry["load"] = clampi(int(carry.get("load", 0)), 0, Shelf.MAX_STACK)
	jack_cart = JackCart.new()
	(get_parent() if get_parent() else self).add_child(jack_cart)
	jack_cart.add_collision_exception_with(self)       # die eigene Figur sperrt den Wagen nicht
	add_collision_exception_with(jack_cart)
	var f := Vector2(-sin(yaw), -cos(yaw))
	var origin := Vector2(global_position.x, global_position.z) + f * (JackCart.HOLD - JackCart.PIVOT_X)
	var phi := yaw + PI / 2.0
	var pos = carry.get("pos", null)
	if pos is Array and pos.size() == 2:
		origin = Vector2(float(pos[0]), float(pos[1]))
		phi = float(carry.get("rot", phi))
	jack_cart.place(origin, phi)
	jack_cart.set_load(int(carry["load"]), bool(carry.get("cross", false)), true)
	arms.set_mode("grip")
	body.set_holding("none")
	held_changed.emit("Hubwagen")


## Pro Bild beim Fahren: Der Wagen folgt den Händen, die Figur bleibt an der Deichsel.
func _drive_jack() -> void:
	if jack_cart == null:
		return
	var q := Vector2(global_position.x, global_position.z)
	var back := jack_cart.step(q)
	var d := back - q
	if d.length() > 0.0005:
		move_and_collide(Vector3(d.x, 0, d.y))
	_aim_hands()


func _aim_hands() -> void:
	if jack_cart == null:
		return
	var pts := jack_cart.grip_points()
	arms.grip_world = pts
	body.set_grab(pts)


func _remove_jack() -> void:
	if jack_cart:
		jack_cart.get_parent().remove_child(jack_cart)
		jack_cart.queue_free()
	jack_cart = null
	arms.grip_world = []
	if body:
		body.set_grab([])


## Wohin die Ablegen-Taste die getragene Palette stellt: der Bodenpunkt, auf den die Kamera
## (also die Maus) zielt, mit 0,9 bis 3,2 m Abstand zur Figur.
func pallet_spot() -> Vector2:
	var me := Vector2(global_position.x, global_position.z)
	var fwd3 := -global_basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	var c: Camera3D = tp_cam if third_person else cam
	if c == null:
		return me + fwd * 1.3
	var from := c.global_position
	var dir := -c.global_basis.z
	# Blick nach oben oder waagerecht: so weit wie erlaubt geradeaus
	if dir.y > -0.02:
		return me + fwd * PALLET_FAR
	var hit := from + dir * ((PALLET_FLOOR - from.y) / dir.y)
	var off := Vector2(hit.x, hit.z) - me
	# Zielpunkt hinter der Figur (Schulterkamera steil nach unten): dicht vor ihr abstellen
	if off.dot(fwd) <= 0.0:
		return me + fwd * PALLET_NEAR
	return me + off.normalized() * clampf(off.length(), PALLET_NEAR, PALLET_FAR)


## Palettenstapel, auf den die getragene Palette gerade zielt (null = Boden).
func pallet_target() -> Shelf:
	if carrying_pallet() and _focus is Shelf and (_focus as Shelf).is_pallet():
		return _focus as Shelf
	return null


## Drehung der abgestellten Palette in 90°-Schritten: Die lange Seite liegt quer zur Blickrichtung
## (bei yaw 0 verläuft sie entlang X, die Figur blickt nach -Z).
func pallet_rot() -> int:
	return posmod(int(round(yaw / (PI / 2.0))), 4)


## Zeigt der Blickstrahl auf freien Boden (flache Fläche ohne Ziel)?
func _aims_at_floor() -> bool:
	if not ray.is_colliding() or ray.get_collision_normal().y < 0.8:
		return false
	var c := ray.get_collider()
	return c != null and not c.has_meta("interact") and ray.get_collision_point().y < 0.15


## Leere Europalette in die Hände nehmen: hochkant vor dem Körper, mit beiden Händen an den Seiten.
func _set_carry_pallet(item: Dictionary) -> void:
	clear_held()
	carry = item
	var holders := _carry_holders()
	for k in holders.size():
		_pallet_model(holders[k], 0.42 if k == 0 else 1.0)
	arms.set_mode("box", {"half": 0.38, "top": 0.12})
	body.set_holding("carry", 0.35)
	held_changed.emit("In den Händen: Europalette")


func _pallet_model(holder: Node3D, scale := 1.0) -> void:
	var p := Props.make("pallet")
	var h := Props.bounds(p).size.y
	p.rotation.x = PI / 2.0
	p.scale = Vector3.ONE * scale
	p.position = Vector3(0, 0, -h * 0.5 * scale)
	holder.add_child(p)


## Spänebehälter in die Hände nehmen. item: {"kind": "chip_bin", "bin": Nummer, "title": Name}
func _set_carry_bin(item: Dictionary) -> void:
	clear_held()
	carry = item
	for holder in _carry_holders():
		_bin_model(holder)
	arms.set_mode("box", {"half": 0.17, "top": 0.11})
	body.set_holding("carry", 0.17)
	held_changed.emit("In den Händen: %s" % str(item.get("title", "Spänebehälter")))


## Trägt die Spielfigur ein vorbearbeitetes Teil zur Schleifmaschine?
func carrying_semi() -> bool:
	return str(carry.get("kind", "")) == "semi"


## Ausgespanntes Teil in den Händen? {"kind": "part", "shape": "round"/"block", ...}
func carrying_part() -> bool:
	return str(carry.get("kind", "")) == "part"


## Ausgedruckte Zeichnung in der Hand? {"kind": "drawing", "job": Auftrag}
func carrying_drawing() -> bool:
	return str(carry.get("kind", "")) == "drawing"


## Rohmaterial in die Hände nehmen.
func set_carry(item: Dictionary) -> void:
	if str(item.get("kind", "")) == "chip_bin":
		_set_carry_bin(item)
		return
	if str(item.get("kind", "")) == "pallet":
		_set_carry_pallet(item)
		return
	if str(item.get("kind", "")) == "jack":
		_set_carry_jack(item)
		return
	clear_held()
	carry = item
	var holders := _carry_holders()
	for k in holders.size():
		item_model(holders[k], item)
		if k == 1 and carrying_drawing():
			holders[k].get_child(0).rotation.y = PI      # an der Figur zeigt das Blatt vom Körper weg
	match str(item.get("kind", "")):
		"drawing":
			arms.set_mode("tool", {"r": 0.004})
			body.set_holding("tool")
			held_changed.emit("In der Hand: Zeichnung %s" % str(item["job"].get("title", "")))
		"part":
			var half := clampf(minf(float(item["l"]) * 0.001, 0.5) * 0.5, 0.05, 0.25)
			arms.set_mode("box", {"half": half, "top": 0.04})
			body.set_holding("carry", half)
			held_changed.emit("In den Händen: %s" % str(item.get("title", "Teil")))
		"semi":
			arms.set_mode("box", {"half": 0.07, "top": 0.045})
			body.set_holding("carry", 0.07)
			held_changed.emit("In den Händen: %s, muss noch geschliffen werden" % str(item["title"]))
		_:
			# quer vor dem Körper, mit beiden Händen im Obergriff
			var l := minf(float(item["l"]) * 0.001, 0.9)
			var rad := minf(float(item["d"]) * 0.0005, 0.06) if str(item["kind"]) == Materials.KIND_ROUND else minf(float(item["h"]) * 0.001, 0.12) * 0.5
			arms.set_mode("bar", {"half": l * 0.5, "r": rad})
			body.set_holding("carry", minf(l * 0.5, 0.3))
			held_changed.emit("In den Händen: %s  %s" % [Materials.label(str(item["material"])), RawMaterialTab.describe(item)])


## Modell des Getragenen in holder bauen, Längsachse X, Mitte im Ursprung. full = in voller Länge
## (liegt am Boden), sonst gekürzt, damit es vor der Kamera nicht das Bild füllt.
func item_model(holder: Node3D, item: Dictionary, full := false) -> void:
	match str(item.get("kind", "")):
		"chip_bin":
			_bin_model(holder, item)
		"pallet":
			_pallet_model(holder)
		"drawing":
			var tex: Texture2D = drawing_texture.call(item["job"]) if drawing_texture.is_valid() else null
			var s := PinnedDrawing.sheet(holder, tex, Vector2(0.24, 0.1414))
			if full:
				s.rotation.x = -PI / 2      # liegt flach, Bild nach oben
			else:
				s.position = Vector3(-0.1, 0.05, 0)
		"part":
			var m := Build.mat(Materials.cut_color(str(item["material"])), 0.3, 0.6)
			var l := float(item["l"]) * 0.001 if full else minf(float(item["l"]) * 0.001, 0.5)
			if str(item.get("shape", "")) == "round":
				_part_model(holder, item, m, l, full)
			else:
				var h := float(item["h"]) * 0.001 if full else minf(float(item["h"]) * 0.001, 0.12)
				var w := float(item["w"]) * 0.001 if full else minf(float(item["w"]) * 0.001, 0.2)
				Build.box(holder, Vector3(l, h, w), Vector3.ZERO, m)
		"semi":
			Build.box(holder, Vector3(0.14, 0.09, 0.2), Vector3.ZERO, Build.mat(Materials.cut_color(str(item["part"]["material"])), 0.45, 0.3))
		_:
			var id := str(item["material"])
			var m := Build.mat(Materials.raw_color(id).lerp(Materials.cut_color(id), 0.25), 0.55, 0.2)
			var l := float(item["l"]) * 0.001 if full else minf(float(item["l"]) * 0.001, 0.9)
			if str(item["kind"]) == Materials.KIND_ROUND:
				var rad := float(item["d"]) * 0.0005 if full else minf(float(item["d"]) * 0.0005, 0.06)
				Build.cyl(holder, rad, l, Vector3.ZERO, m, Build.AXIS_X)
				# Sägeschnitt an den Stirnseiten heller
				for e in [-1.0, 1.0]:
					Build.cyl(holder, rad * 0.98, 0.002, Vector3(e * l * 0.5, 0, 0), Build.mat(Materials.cut_color(id), 0.35, 0.4), Build.AXIS_X)
			else:
				var h := float(item["h"]) * 0.001 if full else minf(float(item["h"]) * 0.001, 0.12)
				var w := float(item["w"]) * 0.001 if full else minf(float(item["w"]) * 0.001, 0.2)
				Build.box(holder, Vector3(l, h, w), Vector3.ZERO, m)


## Was in Hand oder Händen ist, vor der Figur fallen lassen. Gibt den liegenden Gegenstand zurück, null = nichts.
func drop() -> DroppedItem:
	if operating or hands_free():
		return null
	# Der Hubwagen wird mit samt Last abgestellt
	if driving_jack():
		if jack_drop.is_valid():
			jack_drop.call()
		return null
	# Paletten fallen nicht, sie werden vor der Figur abgestellt
	if carrying_pallet():
		# Auf einen Stapel gezielt: dort auflegen, sonst am Zielpunkt auf den Boden
		var stack := pallet_target()
		if stack:
			stack.interact(self)
		elif pallet_drop.is_valid():
			pallet_drop.call(pallet_spot())
		return null
	var item: Dictionary
	if not held.is_empty():
		item = {"kind": "tool", "machine": held["machine"], "id": held["id"], "name": held["name"]}
	else:
		item = carry
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var chest := global_position + Vector3(0, 1.05, 0)
	var at := chest + fwd * 0.55
	# Nicht durch Wand oder Maschine hindurch
	var q := PhysicsRayQueryParameters3D.create(chest, at + fwd * 0.2)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		at = chest + fwd * maxf(chest.distance_to(hit["position"]) - 0.3, 0.0)
	if not held.is_empty():
		clear_held()
	else:
		clear_carry()
	# Leicht nach vorn fallen lassen, mit dem eigenen Schwung
	var v := Vector3(velocity.x, maxf(velocity.y, 0.0), velocity.z) + fwd * 1.2 + Vector3(0, 0.6, 0)
	return DroppedItem.spawn(get_parent(), self, item, at, yaw, v)


func clear_carry() -> void:
	carry = {}
	clear_held()


## Hände frei? Weder Werkzeug noch Material.
func hands_free() -> bool:
	return held.is_empty() and carry.is_empty()


func clear_held() -> void:
	held = {}
	_remove_jack()
	for holder in [_hand, body.tool_grip, body.carry_hold]:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
	arms.set_mode("none")
	body.set_holding("none")
	held_changed.emit("")


## Gedrehtes Teil grob nach seiner Kontur: Absätze als Zylinder entlang X.
func _part_model(holder: Node3D, item: Dictionary, m: Material, shown: float, full := false) -> void:
	var prof = item.get("part", {}).get("profile", [])
	var steps := 16
	for k in steps:
		var r := float(item["d"]) * 0.5
		if prof is Array and not prof.is_empty():
			var i := clampi(int((k + 0.5) / steps * prof.size()), 0, prof.size() - 1)
			r = float(prof[i])
		if r <= 0.05:
			continue
		var seg := shown / steps
		Build.cyl(holder, r * 0.001 if full else minf(r * 0.001, 0.06), seg, Vector3(-shown * 0.5 + seg * (k + 0.5), 0, 0), m, Build.AXIS_X)


## Je ein leerer Knoten für das Getragene in der Ego-Ansicht und an der Figur.
func _carry_holders() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for parent in [_hand, body.carry_hold]:
		var n := Node3D.new()
		parent.add_child(n)
		out.append(n)
	return out


## Spänekiste aus dem Modell, verkleinert, mit ein paar Spänen.
func _bin_model(holder: Node3D, _item := {}) -> void:
	var box := Props.make("chip_box", Vector3(0.36, 0.22, 0.26))
	box.position.y = -0.11
	holder.add_child(box)
	Build.box(holder, Vector3(0.2, 0.05, 0.2), Vector3(-0.04, -0.03, 0), Build.mat(Color(0.62, 0.6, 0.56), 0.35, 0.8))


# ------------------------------------------------------------ Speichern

func get_state() -> Dictionary:
	return {"pos": [global_position.x, global_position.y, global_position.z], "yaw": yaw, "pitch": pitch,
		"third_person": third_person,
		"held": {"machine": held["machine"], "id": held["id"]} if not held.is_empty() else {},
		"carry": _carry_state(), "cigarette": cigarette.get_state(), "id": player_id, "location": location}


## carry für den Spielstand: Beim Hubwagen gehört seine Lage dazu.
func _carry_state() -> Dictionary:
	var c := carry.duplicate(true)
	if driving_jack() and jack_cart:
		c["pos"] = [jack_cart.global_position.x, jack_cart.global_position.z]
		c["rot"] = jack_cart.phi
		c["load"] = jack_cart.load_n
		c["cross"] = jack_cart.cross
	return c


func set_state(d: Dictionary) -> void:
	var p = d.get("pos", null)
	if p is Array and p.size() == 3:
		global_position = Vector3(float(p[0]), float(p[1]) + 0.05, float(p[2]))
	yaw = float(d.get("yaw", 0.0))
	pitch = float(d.get("pitch", 0.0))
	third_person = bool(d.get("third_person", false))
	player_id = str(d.get("id", player_id))
	location = str(d.get("location", "site"))
	var c = d.get("carry", {})
	if c is Dictionary and not c.is_empty():
		set_carry(c)
	var cig = d.get("cigarette", {})
	if cig is Dictionary:
		cigarette.set_state(cig)
	rotation.y = yaw
	_update_camera()
