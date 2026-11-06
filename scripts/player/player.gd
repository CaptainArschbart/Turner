class_name Player
extends CharacterBody3D
## Spielfigur (Zerspanungsmechaniker) mit 1st/3rd-Person-Kamera und Interaktion.

signal prompt_changed(text: String)
signal held_changed(text: String)

const WALK := 3.2
const SPRINT := 5.8
const CROUCH := 1.6
const JUMP := 4.2
const GRAVITY := 9.81

var head: Node3D
var cam: Camera3D
var tp_arm: SpringArm3D
var tp_cam: Camera3D
var ray: RayCast3D
var body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []

var yaw := 0.0
var pitch := 0.0
var third_person := false
var operating: Node = null
var _focus: Node = null
var _prompt := ""
var _walk_t := 0.0
## Werkzeug in der Hand: {"machine", "id", "name"}, leer = Hand frei
var held: Dictionary = {}
var _hand: Node3D


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
	ray.target_position = Vector3(0, 0, -2.6)
	ray.add_exception(self)
	cam.add_child(ray)
	_hand = Node3D.new()
	_hand.position = Vector3(0.26, -0.24, -0.5)
	cam.add_child(_hand)

	tp_arm = SpringArm3D.new()
	tp_arm.spring_length = 2.6
	tp_arm.margin = 0.15
	tp_arm.position = Vector3(0.45, 0.15, 0)
	tp_arm.add_excluded_object(get_rid())
	head.add_child(tp_arm)
	tp_cam = Camera3D.new()
	tp_arm.add_child(tp_cam)

	_build_body()
	_update_camera()
	Settings.changed.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	cam.fov = float(Settings.graphics["fov"])
	tp_cam.fov = float(Settings.graphics["fov"])


func _build_body() -> void:
	body = Node3D.new()
	add_child(body)
	var overall := Build.mat(Color(0.12, 0.2, 0.38), 0.85)
	var hi_vis := Build.mat(Color(0.95, 0.55, 0.1), 0.7)
	var skin := Build.mat(Color(0.85, 0.66, 0.52), 0.7)
	var boots := Build.mat(Color(0.12, 0.1, 0.08), 0.7)
	var glasses := Build.glass(Color(0.3, 0.4, 0.5, 0.5))
	# Rumpf
	var torso := MeshInstance3D.new()
	var tc := CapsuleMesh.new()
	tc.radius = 0.22
	tc.height = 0.75
	torso.mesh = tc
	torso.material_override = overall
	torso.position.y = 1.22
	body.add_child(torso)
	Build.box(body, Vector3(0.46, 0.05, 0.3), Vector3(0, 1.35, 0), hi_vis)
	# Kopf
	Build.sphere(body, 0.13, Vector3(0, 1.7, 0), skin)
	Build.box(body, Vector3(0.22, 0.05, 0.03), Vector3(0, 1.72, -0.12), glasses)
	# Kappe
	Build.cyl(body, 0.135, 0.07, Vector3(0, 1.8, 0), overall)
	Build.box(body, Vector3(0.2, 0.015, 0.12), Vector3(0, 1.78, -0.16), overall)
	# Beine
	for x in [-0.1, 0.1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(x, 0.88, 0)
		body.add_child(pivot)
		Build.box(pivot, Vector3(0.15, 0.82, 0.17), Vector3(0, -0.42, 0), overall)
		Build.box(pivot, Vector3(0.16, 0.1, 0.27), Vector3(0, -0.83, -0.05), boots)
		_legs.append(pivot)
	# Arme
	for x in [-0.29, 0.29]:
		var pivot := Node3D.new()
		pivot.position = Vector3(x, 1.48, 0)
		body.add_child(pivot)
		Build.box(pivot, Vector3(0.11, 0.6, 0.12), Vector3(0, -0.3, 0), overall)
		Build.sphere(pivot, 0.06, Vector3(0, -0.64, 0), skin)
		_arms.append(pivot)


func _update_camera() -> void:
	if operating:
		return
	if third_person:
		tp_cam.make_current()
	else:
		cam.make_current()
	body.visible = third_person
	_hand.visible = not third_person


# ------------------------------------------------------------ Eingabe

func _unhandled_input(event: InputEvent) -> void:
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
	elif event.is_action_pressed("toggle_view"):
		third_person = not third_person
		_update_camera()
	elif event.is_action_pressed("interact") and _focus:
		get_viewport().set_input_as_handled()
		_focus.interact(self)


## Linksklick auf das anvisierte Ziel. Gibt true zurück, wenn es darauf reagiert.
func click_focus() -> bool:
	if _focus and _focus.has_method("click"):
		_focus.click(self)
		return true
	return false


func _physics_process(delta: float) -> void:
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
	var crouch := Input.is_action_pressed("crouch")
	head.position.y = lerpf(head.position.y, 1.0 if crouch else 1.62, 10.0 * delta)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := WALK
	if crouch:
		speed = CROUCH
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = lerpf(velocity.x, dir.x * speed, accel * delta)
	velocity.z = lerpf(velocity.z, dir.z * speed, accel * delta)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP
	move_and_slide()
	_animate(delta)
	_update_focus()


func _animate(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_walk_t += delta * hspeed * 2.6
	var swing := sin(_walk_t) * clampf(hspeed / WALK, 0.0, 1.0) * 0.6
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_arms[0].rotation.x = -swing * 0.8
	_arms[1].rotation.x = swing * 0.8


func _update_focus() -> void:
	var target: Node = null
	if ray.is_colliding():
		var c := ray.get_collider()
		if c and c.has_meta("interact"):
			target = c.get_meta("interact")
			# Maschinen lenken den Blick auf ihre Werkzeugaufnahme um, wenn er dorthin zeigt
			if target.has_method("focus_for"):
				target = target.focus_for(ray.global_position, -ray.global_transform.basis.z)
	_focus = target
	_set_prompt(target.get_prompt() if target else "")


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
	_hand.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func stop_operating() -> void:
	operating = null
	_update_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------ Werkzeug in der Hand

## Werkzeug id der Maschine in die Hand nehmen.
func set_held(machine: Node, id: String) -> void:
	clear_held()
	held = {"machine": machine.MACHINE_ID, "id": id, "name": machine.tool_name(id)}
	var model: Node3D = machine.make_tool_model(id)
	_hand.add_child(model)
	# Kurz fassen: Werkzeug zeigt nach vorn, Mitte in der Hand
	if machine.TOOL_UPRIGHT:
		model.rotation.x = PI / 2
	model.position = -_hand.to_local(Build.bounds(model).get_center())
	held_changed.emit("In der Hand: %s" % held["name"])


func clear_held() -> void:
	held = {}
	for c in _hand.get_children():
		_hand.remove_child(c)
		c.queue_free()
	held_changed.emit("")


# ------------------------------------------------------------ Speichern

func get_state() -> Dictionary:
	return {"pos": [global_position.x, global_position.y, global_position.z], "yaw": yaw, "pitch": pitch,
		"third_person": third_person,
		"held": {"machine": held["machine"], "id": held["id"]} if not held.is_empty() else {}}


func set_state(d: Dictionary) -> void:
	var p = d.get("pos", null)
	if p is Array and p.size() == 3:
		global_position = Vector3(float(p[0]), float(p[1]) + 0.05, float(p[2]))
	yaw = float(d.get("yaw", 0.0))
	pitch = float(d.get("pitch", 0.0))
	third_person = bool(d.get("third_person", false))
	rotation.y = yaw
	_update_camera()
