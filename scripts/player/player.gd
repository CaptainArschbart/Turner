class_name Player
extends CharacterBody3D
## Spielfigur (Zerspanungsmechaniker) mit 1st/3rd-Person-Kamera und Interaktion.

signal material_to_machine(machine: Node, flip: bool)
signal prompt_changed(text: String)
signal held_changed(text: String)

const WALK := 3.2
const SPRINT := 5.8
const CROUCH := 1.6
const JUMP := 4.2
const GRAVITY := 9.81
const REACH := 2.6               # so weit reicht der Sichtstrahl
const BUILD_REACH := 15.0        # im Baumodus sieht man weiter

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
var build_mode := false           # Baumodus: Das Anvisierte wird nicht bedient
var _focus: Node = null
var carry: Dictionary = {}        # Rohmaterial in den Händen
var _prompt := ""
var _walk_t := 0.0
## Werkzeug in der Hand: {"machine", "id", "name"}, leer = Hand frei
var held: Dictionary = {}
var gate: Callable                # Spielwelt: ist dieses Ziel gerade gesperrt? (Ziel, nur prüfen)
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
	ray.target_position = Vector3(0, 0, -REACH)
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
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if right_click_focus():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_view"):
		third_person = not third_person
		_update_camera()
	elif event.is_action_pressed("interact") and _focus:
		get_viewport().set_input_as_handled()
		if not _blocked(_focus, false):
			_focus.interact(self)


## Linksklick auf das anvisierte Ziel. Gibt true zurück, wenn es darauf reagiert.
func _blocked(target: Node, silent: bool) -> bool:
	return gate.is_valid() and gate.call(target, silent)


## Rechtsklick auf die Maschine: Teil andersherum einspannen, aus den Händen oder das schon eingespannte.
func right_click_focus() -> bool:
	if not _focus or not _focus.has_method("get_machine") or _blocked(_focus, false):
		return false
	var machine: Node = _focus.get_machine()
	if carrying_bin() or not held.is_empty() or (carry.is_empty() and machine.get("has_part") != true):
		return false
	material_to_machine.emit(machine, true)
	return true


func click_focus() -> bool:
	if _focus and _blocked(_focus, false):
		return true
	if _focus and not carry.is_empty() and _focus.has_method("get_machine"):
		material_to_machine.emit(_focus.get_machine(), false)
		return true
	# Freie Hände auf der Maschine selbst: Spanntiefe des eingespannten Teils ändern
	if _focus and hands_free() and _focus.has_method("get_machine") and not _focus.has_method("click") and _focus.get_machine().get("has_part") == true:
		material_to_machine.emit(_focus.get_machine(), false)
		return true
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
	if ray.is_colliding():
		var c := ray.get_collider()
		if c and c.has_meta("interact"):
			target = c.get_meta("interact")
			# Maschinen lenken den Blick auf ihre Werkzeugaufnahme um, wenn er dorthin zeigt
			if target.has_method("focus_for"):
				target = target.focus_for(ray.global_position, -ray.global_transform.basis.z)
	_focus = target
	if target and _blocked(target, true):
		_set_prompt("Tag noch nicht gestartet: am PC im Programm Tagesbericht")
		return
	var text: String = target.get_prompt() if target else ""
	if target and not carry.is_empty() and target.has_method("get_machine"):
		if target.has_method("carry_prompt") and not carrying_bin():
			text = target.carry_prompt(carry)
		elif carrying_semi():
			text = "[Linksklick] Zum Schleifen einspannen    |    %s" % text
		elif carrying_bin():
			text = "[Linksklick] Spänewanne in den Behälter leeren (%d %% voll)    |    %s" % [int(target.get_machine().tray.fraction() * 100.0), text]
		else:
			text = "[Linksklick] Material einspannen    [Rechtsklick] Andersherum    |    %s" % text
	elif target and hands_free() and target.has_method("get_machine") and target.get_machine().get("has_part") == true:
		text = "%s    |    [Rechtsklick] Teil umdrehen%s" % [text, "" if target.has_method("click") else "    [Linksklick] Spanntiefe"]
	_set_prompt(text)


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
	if not carry.is_empty():
		return
	clear_held()
	held = {"machine": machine.MACHINE_ID, "id": id, "name": machine.tool_name(id)}
	var model: Node3D = machine.make_tool_model(id)
	_hand.add_child(model)
	# Kurz fassen: Werkzeug zeigt nach vorn, Mitte in der Hand
	if machine.TOOL_UPRIGHT:
		model.rotation.x = PI / 2
	model.position = -_hand.to_local(Build.bounds(model).get_center())
	held_changed.emit("In der Hand: %s" % held["name"])


## Trägt die Spielfigur gerade einen Spänebehälter?
func carrying_bin() -> bool:
	return str(carry.get("kind", "")) == "chip_bin"


## Spänebehälter in die Hände nehmen. item: {"kind": "chip_bin", "bin": Nummer, "title": Name}
func _set_carry_bin(item: Dictionary) -> void:
	clear_held()
	carry = item
	var steel := Build.mat(Color(0.24, 0.3, 0.38), 0.6, 0.2)
	Build.box(_hand, Vector3(0.34, 0.22, 0.3), Vector3(-0.1, -0.04, -0.2), steel)
	held_changed.emit("In den Händen: %s" % str(item.get("title", "Spänebehälter")))


## Trägt die Spielfigur ein vorbearbeitetes Teil zur Schleifmaschine?
func carrying_semi() -> bool:
	return str(carry.get("kind", "")) == "semi"


## Rohmaterial in die Hände nehmen.
func set_carry(item: Dictionary) -> void:
	if str(item.get("kind", "")) == "chip_bin":
		_set_carry_bin(item)
		return
	if str(item.get("kind", "")) == "semi":
		clear_held()
		carry = item
		var mat_id := str(item["part"]["material"])
		Build.box(_hand, Vector3(0.14, 0.09, 0.2), Vector3(-0.1, -0.02, -0.2), Build.mat(Materials.cut_color(mat_id), 0.45, 0.3))
		held_changed.emit("In den Händen: %s, muss noch geschliffen werden" % str(item["title"]))
		return
	clear_held()
	carry = item
	var id := str(item["material"])
	var m := Build.mat(Materials.raw_color(id).lerp(Materials.cut_color(id), 0.25), 0.55, 0.2)
	var l := minf(float(item["l"]) * 0.001, 0.7)
	if str(item["kind"]) == Materials.KIND_ROUND:
		Build.cyl(_hand, minf(float(item["d"]) * 0.0005, 0.06), l, Vector3(-0.1, 0, -0.2), m, Build.AXIS_Z)
	else:
		Build.box(_hand, Vector3(minf(float(item["w"]) * 0.001, 0.2), minf(float(item["h"]) * 0.001, 0.12), l), Vector3(-0.1, 0, -0.2), m)
	held_changed.emit("In den Händen: %s  %s" % [Materials.label(id), RawMaterialTab.describe(item)])


func clear_carry() -> void:
	carry = {}
	clear_held()


## Hände frei? Weder Werkzeug noch Material.
func hands_free() -> bool:
	return held.is_empty() and carry.is_empty()


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
		"held": {"machine": held["machine"], "id": held["id"]} if not held.is_empty() else {},
		"carry": carry}


func set_state(d: Dictionary) -> void:
	var p = d.get("pos", null)
	if p is Array and p.size() == 3:
		global_position = Vector3(float(p[0]), float(p[1]) + 0.05, float(p[2]))
	yaw = float(d.get("yaw", 0.0))
	pitch = float(d.get("pitch", 0.0))
	third_person = bool(d.get("third_person", false))
	var c = d.get("carry", {})
	if c is Dictionary and not c.is_empty():
		set_carry(c)
	rotation.y = yaw
	_update_camera()
