class_name Mill
extends Node3D
## Konventionelle Fräsmaschine: Werkstück als Höhenkarte, Tisch fährt in X/Y, Fräskopf in Z.
## Koordinaten der Anzeige: Werkzeugmitte (X, Y) ab der vorderen linken Rohteil-Ecke,
## Z = Werkzeugspitze über der rohen Oberseite.

signal message(text: String, color: Color)
signal operating_changed(on: bool)
signal levers_changed(on: bool)
signal submit_requested
signal new_part_requested

const CELL := 0.5             # Raster der Höhenkarte (mm)
const X_TRAVEL := 300.0       # Tisch 410 mm lang: bleibt unter der Spindel
const Y_TRAVEL := 160.0
const Z_MAX := 260.0
const Z_MIN := -70.0
const JAW_DROP := 12.0        # Backen enden so weit unter der rohen Oberseite (mm)
const JAW_T := 25.0
const STEP := 0.25            # größter Rechenschritt beim Verfahren (mm)
const JOG_FAST := 10.0
const MACHINE_ID := "mill"
const TOOL_UPRIGHT := true    # Werkzeugmodelle stehen senkrecht (Achse Y)
const MOUNT_REACH := 0.12     # so nah muss der Blick an der Spindel vorbeigehen (m)
const LEVER_HIT_X := 0.056    # halbe Breite der Klickfläche eines Hebels (m)
const KNOB_GRAB := 0.02       # so nah am Griff (m) beginnt ein Klick das Ziehen
const CHIP_MAX := 900         # so viele Späne liegen höchstens in der Wanne
const LEVER_STAND := Vector3(1.0, 0.0, -0.43)    # Standplatz am Hebelfeld
const CAM_YAW := 0.3
const CAM_PITCH := -0.5
const CAM_DIST := 0.5
const CAM_MIN := 0.05
const CAM_MAX := 2.5

const HEIGHT_SHADER := """
shader_type spatial;
uniform sampler2D hmap : filter_nearest, repeat_disable;
uniform vec2 size_mm;
uniform float depth_mm;
uniform float cell;
varying float mach;

void vertex() {
	vec2 p = VERTEX.xz * 1000.0;
	bool skirt = abs(p.x) > size_mm.x * 0.5 + cell * 0.5 || abs(p.y) > size_mm.y * 0.5 + cell * 0.5;
	vec2 uv = vec2((p.x + size_mm.x * 0.5 + cell * 0.5) / size_mm.x, (size_mm.y * 0.5 - p.y + cell * 0.5) / size_mm.y);
	vec4 t = textureLod(hmap, clamp(uv, vec2(0.0), vec2(1.0)), 0.0);
	VERTEX.y = (skirt ? -depth_mm : t.r) * 0.001;
	mach = skirt ? 0.0 : t.g;
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = mix(vec3(0.42, 0.44, 0.47), vec3(0.8, 0.82, 0.85), mach);
	ROUGHNESS = mix(0.6, 0.28, mach);
	METALLIC = 0.85;
}
"""

var operating := false
var player: Node = null
var saddle: Node3D
var table: Node3D
var head: Node3D
var spindle: Node3D
var hw_x: Node3D
var hw_y: Node3D
var hw_z: Node3D
var lamp: SpotLight3D
var op_cam: Camera3D
var chips: CPUParticles3D
var coolant_fx: CPUParticles3D

# Werkstück
var block_l := 100.0
var block_w := 60.0
var block_h := 40.0
var nx := 200
var ny := 120
var data := PackedFloat32Array()   # je Zelle (Höhe in mm, bearbeitet 0/1)
var _block: Node3D
var _block_mi: MeshInstance3D
var _block_mat: ShaderMaterial
var _hmap: ImageTexture
var _jaws: Array[Node3D] = []
var _parallel: MeshInstance3D
var _dirty := false
var _rebuild_t := 0.0
var untouched := true

# Achsen und Spindel
var tool_x := -50.0
var tool_y := 30.0
var tool_z := 50.0
var tool_idx := 0
var hw_axis := 0
var rpm_set := 630.0
var feed_set := 100.0
var spindle_on := false
var spindle_speed := 0.0
var estop := false
var coolant := false
var auto_axis := -1
var auto_sign := 1
var last_ap := 0.0
var _tool_node: Node3D
var _stamp_z := INF
var _ap := 0.0
var _hw_last_ms := 0
var _cut_t := 0.0
var _cut_level := 0.0
var _msg_cool := 0.0
var _last_msg := ""
var _screen: Label3D
var _led: MeshInstance3D
var _led_on: Material
var _led_off: Material
var _screen_t := 0.0
var tool_mount: ToolMount
var panel_open := false
var _drag_lever := -1
var _lever_station: MillLeverPanel
var _lever_plate: Node3D
var _knobs: Array = []
var _lever_hover := false
var _chip_mm: MultiMesh
var chips_in_tray := 0
var _chip_next := 0
var _chip_t := 0.0

# Kamera
var cam_yaw := CAM_YAW
var cam_pitch := CAM_PITCH
var cam_dist := CAM_DIST
var cam_pan := Vector3.ZERO
var cam_target := Vector3(0, MillModel.TOP_Y, 0)
var _yaw_t := CAM_YAW
var _pitch_t := CAM_PITCH
var _dist_t := CAM_DIST
var _lever_view := false

# Audio
var _audio: AudioStreamPlayer3D
var _pb: AudioStreamGeneratorPlayback
var _ph1 := 0.0
var _ph2 := 0.0
var _lp := 0.0
const _MIX := 22050.0


func _ready() -> void:
	var parts := MillModel.build(self)
	saddle = parts["saddle"]
	table = parts["table"]
	head = parts["head"]
	spindle = parts["spindle"]
	hw_x = parts["hw_x"]
	hw_y = parts["hw_y"]
	hw_z = parts["hw_z"]
	lamp = parts["lamp"]
	_screen = parts["screen"]
	_led = parts["led"]
	_led_off = _led.material_override
	_led_on = Build.emissive(Color(0.1, 1.0, 0.2), 3.0)
	_lever_plate = parts["levers"]
	_knobs = parts["knobs"]
	_lever_station = MillLeverPanel.new()
	_lever_station.mill = self
	add_child(_lever_station)
	_build_workholding(parts["vise"])
	_build_effects()
	_build_colliders()
	op_cam = Camera3D.new()
	op_cam.fov = 55
	op_cam.near = 0.01
	add_child(op_cam)
	_setup_audio()
	new_workpiece(100.0, 60.0, 40.0)
	select_tool(0, true)
	_sync_levers()


func _build_workholding(vise: Node3D) -> void:
	var dark := Build.mat(Color(0.12, 0.13, 0.15), 0.5, 0.3)
	for i in 2:
		var jaw := Node3D.new()
		vise.add_child(jaw)
		Build.box(jaw, Vector3(MillModel.VISE_L, 0.05, JAW_T * 0.001), Vector3(0, 0, 0), dark)
		_jaws.append(jaw)
	_block = Node3D.new()
	_block.position.y = MillModel.TOP_Y - MillModel.TABLE_Y
	table.add_child(_block)
	_block_mi = MeshInstance3D.new()
	_block.add_child(_block_mi)
	_block_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = HEIGHT_SHADER
	_block_mat.shader = sh
	_block_mi.material_override = _block_mat
	_parallel = Build.box(table, Vector3(0.1, 0.01, 0.1), Vector3.ZERO, Build.mat(Color(0.5, 0.52, 0.55), 0.4, 0.8))


func _build_effects() -> void:
	chips = CPUParticles3D.new()
	chips.emitting = false
	chips.amount = 60
	chips.lifetime = 0.8
	chips.direction = Vector3(0.0, 1.0, 0.0)
	chips.spread = 75
	chips.gravity = Vector3(0, -6.0, 0)
	chips.initial_velocity_min = 0.5
	chips.initial_velocity_max = 1.4
	chips.angular_velocity_min = -720
	chips.angular_velocity_max = 720
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.004, 0.001, 0.002)
	chip_mesh.material = Build.mat(Color(0.5, 0.52, 0.6), 0.3, 1.0)
	chips.mesh = chip_mesh
	add_child(chips)

	coolant_fx = CPUParticles3D.new()
	coolant_fx.emitting = false
	coolant_fx.amount = 60
	coolant_fx.lifetime = 0.3
	coolant_fx.direction = Vector3(-0.3, -1.0, -0.3)
	coolant_fx.spread = 8
	coolant_fx.initial_velocity_min = 0.5
	coolant_fx.initial_velocity_max = 0.7
	var drop := SphereMesh.new()
	drop.radius = 0.002
	drop.height = 0.004
	var cm := Build.mat(Color(0.92, 0.95, 1.0, 0.55), 0.05)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = cm
	coolant_fx.mesh = drop
	add_child(coolant_fx)

	# Späne, die in der Wanne liegen bleiben
	var lying := BoxMesh.new()
	lying.size = Vector3(0.007, 0.0015, 0.003)
	lying.material = Build.mat(Color(0.55, 0.57, 0.62), 0.35, 0.9)
	_chip_mm = MultiMesh.new()
	_chip_mm.transform_format = MultiMesh.TRANSFORM_3D
	_chip_mm.mesh = lying
	_chip_mm.instance_count = CHIP_MAX
	_chip_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _chip_mm
	add_child(mmi)


func _build_colliders() -> void:
	var base := Build.collider(self, Vector3(1.0, 0.72, 0.98), Vector3(0, 0.36, -0.07))
	base.set_meta("interact", self)
	var bed := Build.collider(self, Vector3(0.42, 0.3, 0.3), Vector3(0, 0.95, 0))
	bed.set_meta("interact", self)
	var column := Build.collider(self, Vector3(0.38, 1.7, 0.3), Vector3(0, 1.45, -0.43))
	column.set_meta("interact", self)
	var hood := Build.collider(self, Vector3(0.24, 0.6, 0.3), Vector3(0, 1.6, -0.07))
	hood.set_meta("interact", self)
	var box := Build.collider(self, Vector3(0.45, 0.4, 0.14), Vector3(0.58, 1.48, 0.1))
	box.set_meta("interact", self)
	var levers := Build.collider(self, Vector3(0.04, 0.38, 0.25), MillModel.LEVER_POS)
	levers.set_meta("interact", _lever_station)
	# Schutzwand ringsum
	var h := MillModel.GUARD_TOP - MillModel.TRAY_TOP
	var y := MillModel.TRAY_TOP + h * 0.5
	var d := MillModel.TRAY_Z1 - MillModel.TRAY_Z0
	var cz := (MillModel.TRAY_Z0 + MillModel.TRAY_Z1) * 0.5
	for s in [-1.0, 1.0]:
		var wall := Build.collider(self, Vector3(0.02, h, d), Vector3(s * MillModel.TRAY_X, y, cz))
		wall.set_meta("interact", self)
		# Rückwand neben der Säule
		Build.collider(self, Vector3(MillModel.TRAY_X - 0.18, h, 0.02), Vector3(s * (MillModel.TRAY_X + 0.18) * 0.5, y, MillModel.TRAY_Z0))
	var front := Build.collider(self, Vector3(MillModel.TRAY_X * 2.0, h, 0.02), Vector3(0, y, MillModel.TRAY_Z1))
	front.set_meta("interact", self)


func tool() -> Dictionary:
	return MillTools.TOOLS[tool_idx]


func tool_radius() -> float:
	return float(tool()["d"]) * 0.5


## Steht die Werkzeugmitte höchstens einen Durchmesser neben dem Rohteil? Sonst keine Marke in der Draufsicht.
func tool_near_part() -> bool:
	var dx := maxf(maxf(-tool_x, 0.0), tool_x - block_l)
	var dy := maxf(maxf(-tool_y, 0.0), tool_y - block_w)
	return Vector2(dx, dy).length() <= float(tool()["d"])


func height_texture() -> Texture2D:
	return _hmap


# ======================================================================= Werkzeug

func select_tool(i: int, silent := false) -> void:
	i = clampi(i, 0, MillTools.TOOLS.size() - 1)
	if i == tool_idx and _tool_node:
		return
	if not silent:
		if spindle_speed > 5.0:
			_warn("Erst Spindel stoppen, dann Werkzeug wechseln!")
			return
		if tool_z < 0.0:
			_warn("Erst den Fräskopf über das Rohteil fahren (Z > 0).")
			return
	tool_idx = i
	if _tool_node:
		spindle.remove_child(_tool_node)
		_tool_node.queue_free()
	_tool_node = MillTools.assembly(tool())
	_tool_node.position.y = -MillTools.tool_length(tool()) * 0.001
	spindle.add_child(_tool_node)
	_stamp_z = INF
	_sync_axes()
	if not silent:
		_info("Werkzeug eingewechselt: %s" % tool()["name"])


# ======================================================================= Werkzeug von Hand

func tool_list() -> Array:
	return MillTools.TOOLS


func tool_index(id: String) -> int:
	for i in MillTools.TOOLS.size():
		if MillTools.TOOLS[i]["id"] == id:
			return i
	return -1


func tool_name(id: String) -> String:
	return str(MillTools.TOOLS[maxi(tool_index(id), 0)]["name"])


func has_tool(id: String) -> bool:
	return str(tool()["id"]) == id


func make_tool_model(id: String) -> Node3D:
	return MillTools.assembly(MillTools.TOOLS[maxi(tool_index(id), 0)])


## Zeigt der Blick an der Spindel vorbei auf das Werkzeug?
func focus_for(origin: Vector3, dir: Vector3) -> Node:
	if tool_mount == null:
		return self
	var c := to_global(Vector3(0, MillModel.TOP_Y + (tool_z + MillTools.tool_length(tool()) * 0.5) * 0.001, 0))
	return tool_mount if (c - origin).cross(dir).length() <= MOUNT_REACH else self


func hand_prompt(held: Dictionary) -> String:
	if held.is_empty():
		return ""
	if held["machine"] != MACHINE_ID:
		return "%s passt nicht in diese Spindel" % held["name"]
	return "[Linksklick] %s einsetzen, %s kommt in die Hand" % [held["name"], tool()["name"]]


## Werkzeug aus der Hand in die Spindel, das bisherige kommt in die Hand. Die Spindel ist nie leer.
func hand_click(p: Node) -> void:
	var held: Dictionary = p.held
	if held.is_empty():
		return
	if held["machine"] != MACHINE_ID:
		_warn("%s passt nicht in diese Spindel." % held["name"])
		return
	var old := str(tool()["id"])
	var i := tool_index(str(held["id"]))
	select_tool(i)
	if tool_idx == i:
		p.set_held(self, old)


# ======================================================================= Werkstück

func new_workpiece(length: float, width: float, height: float) -> void:
	block_l = length
	block_w = width
	block_h = height
	nx = int(round(length / CELL))
	ny = int(round(width / CELL))
	data = PackedFloat32Array()
	data.resize(nx * ny * 2)
	data.fill(0.0)
	untouched = true
	last_ap = 0.0
	_stamp_z = INF
	_make_block()
	tool_x = -50.0
	tool_y = width * 0.5
	tool_z = maxf(tool_z, 40.0)
	auto_axis = -1
	_sync_axes()


func _make_block() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(block_l + CELL * 2.0, block_w + CELL * 2.0) * 0.001
	pm.subdivide_width = nx + 1
	pm.subdivide_depth = ny + 1
	pm.custom_aabb = AABB(Vector3(-block_l, -block_h * 2.0, -block_w) * 0.001, Vector3(block_l * 2.0, block_h * 2.5, block_w * 2.0) * 0.001)
	_block_mi.mesh = pm
	_hmap = ImageTexture.create_from_image(_height_image())
	_block_mat.set_shader_parameter("hmap", _hmap)
	_block_mat.set_shader_parameter("size_mm", Vector2(block_l, block_w))
	_block_mat.set_shader_parameter("depth_mm", block_h)
	_block_mat.set_shader_parameter("cell", CELL)
	# Backen liegen in Y links und rechts am Rohteil
	var half := block_w * 0.0005 + JAW_T * 0.0005
	var jaw_y := MillModel.TOP_Y - MillModel.TABLE_Y - JAW_DROP * 0.001 - 0.025
	_jaws[0].position = Vector3(0, jaw_y, -half)
	_jaws[1].position = Vector3(0, jaw_y, half)
	# Unterlage füllt den Platz zwischen Schraubstock und Rohteil
	var bottom := MillModel.TOP_Y - MillModel.TABLE_Y - block_h * 0.001
	var bm := _parallel.mesh as BoxMesh
	bm.size = Vector3(block_l * 0.001, maxf(bottom - 0.03, 0.002), block_w * 0.001)
	_parallel.position = Vector3(0, 0.03 + bm.size.y * 0.5, 0)


func _height_image() -> Image:
	return Image.create_from_data(nx, ny, false, Image.FORMAT_RGF, data.to_byte_array())


func height_at(x: float, y: float) -> float:
	var i := clampi(int(floor(x / CELL)), 0, nx - 1)
	var j := clampi(int(floor(y / CELL)), 0, ny - 1)
	return data[(j * nx + i) * 2]


## Tischweg (Mitte des Rohteils unter der Spindel = 0).
func _sync_axes() -> void:
	table.position.x = -(tool_x - block_l * 0.5) * 0.001
	saddle.position.z = (tool_y - block_w * 0.5) * 0.001
	head.position.y = MillModel.TOP_Y + (tool_z + MillTools.tool_length(tool())) * 0.001
	var tip_y := MillModel.TOP_Y + tool_z * 0.001
	chips.position = Vector3(0, tip_y + 0.002, 0)
	coolant_fx.position = Vector3(-0.05, tip_y + 0.08, 0.05)


# ======================================================================= Zerspanung

## Verfahren in mm mit Geschwindigkeit speed (mm/s). Lange Wege werden in kleine Schritte geteilt.
func move_tool(dx: float, dy: float, dz: float, speed: float) -> void:
	if estop:
		return
	var dist := Vector3(dx, dy, dz).length()
	if dist < 0.000001:
		return
	var n := int(ceil(dist / STEP))
	for k in n:
		if not _step_tool(dx / n, dy / n, dz / n, speed):
			break
	_sync_axes()


func _step_tool(sx: float, sy: float, sz: float, speed: float) -> bool:
	var x := clampf(tool_x + sx, block_l * 0.5 - X_TRAVEL * 0.5, block_l * 0.5 + X_TRAVEL * 0.5)
	var y := clampf(tool_y + sy, block_w * 0.5 - Y_TRAVEL * 0.5, block_w * 0.5 + Y_TRAVEL * 0.5)
	var z := clampf(tool_z + sz, Z_MIN, Z_MAX)
	var ex := x - tool_x
	var ey := y - tool_y
	var ez := z - tool_z
	if absf(ex) + absf(ey) + absf(ez) < 0.0000001:
		return false
	var clash := _clash(x, y, z)
	if clash != "":
		_crash(clash)
		return false
	tool_x = x
	tool_y = y
	tool_z = z
	var lateral := absf(ex) + absf(ey) > 0.000001
	if z < 0.0:
		_ap = 0.0
		# Rein seitlich auf gleicher Höhe genügt der Randbereich des Schneidkreises
		_stamp(x, y, z, lateral and absf(ez) < 0.000001 and absf(_stamp_z - z) < 0.000001)
		_stamp_z = z
		if _ap > 0.0:
			return _on_cut(_ap, lateral, ez, speed)
	return true


## Prüft die Werkzeugspitze gegen Schraubstock und Unterlage.
func _clash(x: float, y: float, z: float) -> String:
	var r := tool_radius()
	var over_x := x + r > block_l * 0.5 - MillModel.VISE_L * 500.0 and x - r < block_l * 0.5 + MillModel.VISE_L * 500.0
	if z < -JAW_DROP and over_x:
		if (y - r < 0.0 and y + r > -JAW_T) or (y + r > block_w and y - r < block_w + JAW_T):
			return "KOLLISION! Werkzeug im Schraubstock - Not-Halt."
	if z < -block_h and x + r > 0.0 and x - r < block_l and y + r > 0.0 and y - r < block_w:
		return "KOLLISION! Werkzeug in der Unterlage - Not-Halt."
	return ""


## Schneidet die Zellen unter dem Schneidkreis auf Höhe z. _ap = größte abgetragene Tiefe.
func _stamp(x: float, y: float, z: float, ring: bool) -> void:
	var rr := tool_radius() / CELL
	var cx := x / CELL
	var cy := y / CELL
	var j0 := maxi(int(floor(cy - rr)), 0)
	var j1 := mini(int(ceil(cy + rr)), ny - 1)
	var inner := rr - 2.0
	for j in range(j0, j1 + 1):
		var dy := j + 0.5 - cy
		var h2 := rr * rr - dy * dy
		if h2 < 0.0:
			continue
		var c := sqrt(h2)
		var i0 := maxi(int(ceil(cx - c - 0.5)), 0)
		var i1 := mini(int(floor(cx + c - 0.5)), nx - 1)
		var h2i := inner * inner - dy * dy if inner > 0.0 else -1.0
		if ring and h2i > 0.0:
			var ci := sqrt(h2i)
			_cut_span(j, i0, mini(int(floor(cx - ci - 0.5)), nx - 1), z)
			_cut_span(j, maxi(int(ceil(cx + ci - 0.5)), 0), i1, z)
		else:
			_cut_span(j, i0, i1, z)


func _cut_span(j: int, a: int, b: int, z: float) -> void:
	var k := (j * nx + a) * 2
	for i in range(a, b + 1):
		var h := data[k]
		if h > z:
			_ap = maxf(_ap, h - z)
			data[k] = z
			data[k + 1] = 1.0
		k += 2


func _on_cut(ap: float, lateral: bool, dz: float, speed: float) -> bool:
	var t := tool()
	var kind := str(t["kind"])
	last_ap = ap
	untouched = false
	_dirty = true
	if spindle_speed < 30.0:
		_crash("KOLLISION! Werkzeug im Material bei stehender Spindel - Not-Halt.")
		return false
	if ap > float(t["ap_max"]):
		_crash("WERKZEUGBRUCH! Schnitttiefe %.1f mm ist zu groß für %s (max. %.1f)." % [ap, t["name"], float(t["ap_max"])])
		return false
	if kind == "drill" and lateral:
		_crash("WERKZEUGBRUCH! Der Bohrer verträgt keine seitliche Bewegung im Material.")
		return false
	if kind == "face_mill" and dz < -0.000001:
		_crash("WERKZEUGBRUCH! Der Messerkopf kann nicht eintauchen - außerhalb des Rohteils zustellen.")
		return false
	var fz := speed * 60.0 / maxf(spindle_speed * int(t["z"]), 1.0)
	if fz > float(t["fz_max"]) * 1.5:
		_crash("WERKZEUGBRUCH! Vorschub je Schneide %.3f mm ist zu hoch für %s." % [fz, t["name"]])
		return false
	if fz > float(t["fz_max"]):
		_warn("Vorschub zu hoch für %s (fz %.3f mm, max. %.3f)." % [t["name"], fz, float(t["fz_max"])])
	_cut_t = 0.15
	_cut_level = minf(_cut_level + 0.1, 1.0)
	return true


func _crash(text: String) -> void:
	estop = true
	spindle_on = false
	auto_axis = -1
	message.emit(text, Color(1, 0.3, 0.25))


func _warn(text: String) -> void:
	if text == _last_msg and _msg_cool > 0.0:
		return
	_last_msg = text
	_msg_cool = 1.5
	message.emit(text, Color(1.0, 0.75, 0.2))


func _info(text: String) -> void:
	_last_msg = text
	_msg_cool = 0.5
	message.emit(text, Color(0.7, 0.95, 1.0))


# ======================================================================= Ablauf

static func _step_index(steps: Array, v: float) -> int:
	var i := 0
	for k in steps.size():
		if absf(float(steps[k]) - v) < absf(float(steps[i]) - v):
			i = k
	return i


## Hebel k (0 Drehzahl, 1 Vorschub) eine Stufe verstellen. Geht nur bei stehender Spindel.
func lever_step(k: int, dir: int) -> void:
	lever_set(k, lever_index(k) + dir)


func lever_index(k: int) -> int:
	return _step_index(MillModel.RPM_STEPS, rpm_set) if k == 0 else _step_index(MillModel.FEED_STEPS, feed_set)


## Hebel k auf Stufe i stellen.
func lever_set(k: int, i: int) -> void:
	if spindle_on or spindle_speed > 5.0:
		_warn("Hebel nur bei stehender Spindel schalten!")
		return
	var s: Array = MillModel.RPM_STEPS if k == 0 else MillModel.FEED_STEPS
	i = clampi(i, 0, s.size() - 1)
	if i == lever_index(k):
		return
	if k == 0:
		rpm_set = float(s[i])
		_info("Drehzahl: %d /min" % int(rpm_set))
	else:
		feed_set = float(s[i])
		_info("Vorschub: %d mm/min" % int(feed_set))
	_sync_levers()


func _sync_levers() -> void:
	(_knobs[0] as Node3D).position.y = MillModel.lever_y(_step_index(MillModel.RPM_STEPS, rpm_set), MillModel.RPM_STEPS.size())
	(_knobs[1] as Node3D).position.y = MillModel.lever_y(_step_index(MillModel.FEED_STEPS, feed_set), MillModel.FEED_STEPS.size())


## Punkt, an dem ein Sichtstrahl das Hebelfeld trifft (lokal). Null, wenn er von hinten kommt.
func _plate_point(origin: Vector3, dir: Vector3) -> Variant:
	var inv := _lever_plate.global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * dir
	if d.z >= -0.00001:
		return null
	return o + d * (-o.z / d.z)


## Klickfläche eines Hebels auf einem Sichtstrahl: {"lever", "up", "grab"} oder leer.
func lever_at(origin: Vector3, dir: Vector3) -> Dictionary:
	var p = _plate_point(origin, dir)
	if p == null or absf(p.y) > MillModel.LEVER_H * 0.5 + 0.02:
		return {}
	for k in MillModel.LEVER_X.size():
		if absf(p.x - float(MillModel.LEVER_X[k])) <= LEVER_HIT_X:
			var ky: float = (_knobs[k] as Node3D).position.y
			return {"lever": k, "up": p.y > ky, "grab": absf(p.y - ky) <= KNOB_GRAB}
	return {}


## Beim Ziehen: Griff rastet auf die nächste Stufe zur Mausposition.
func _drag_to(origin: Vector3, dir: Vector3) -> void:
	var p = _plate_point(origin, dir)
	if p == null:
		return
	var n: int = (MillModel.RPM_STEPS if _drag_lever == 0 else MillModel.FEED_STEPS).size()
	lever_set(_drag_lever, int(round((p.y + MillModel.LEVER_H * 0.5) / MillModel.LEVER_H * (n - 1))))


## Vorschub in Richtung sign auf der gewählten Achse (Knöpfe Vorschub + und -).
func feed_selected(sign: int) -> void:
	set_auto(hw_axis, sign)


## Zufällige Lage eines Spans auf dem Wannenboden, links oder rechts neben der Führung.
func chip_position() -> Vector3:
	var side := -1.0 if randf() < 0.5 else 1.0
	var x := side * lerpf(MillModel.PEDESTAL_X + 0.012, MillModel.TRAY_X - 0.025, pow(randf(), 1.6))
	var z := randf_range(MillModel.TRAY_Z0 + 0.025, MillModel.TRAY_Z1 - 0.025)
	return Vector3(x, MillModel.TRAY_FLOOR + 0.001 + randf() * 0.006, z)


func _drop_chip() -> void:
	var b := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, randf_range(-0.3, 0.3))
	_chip_mm.set_instance_transform(_chip_next, Transform3D(b, chip_position()))
	_chip_next = (_chip_next + 1) % CHIP_MAX
	chips_in_tray = mini(chips_in_tray + 1, CHIP_MAX)
	_chip_mm.visible_instance_count = chips_in_tray


func toggle_spindle() -> void:
	if estop:
		_warn("Not-Halt aktiv - mit [%s] quittieren." % Settings.binding_text("emergency_stop"))
	else:
		spindle_on = not spindle_on


func toggle_coolant() -> void:
	coolant = not coolant
	_info("Kühlung: %s" % ("EIN" if coolant else "AUS"))


func toggle_estop() -> void:
	if estop:
		estop = false
		_info("Not-Halt quittiert.")
	else:
		_crash("NOT-HALT betätigt.")


func cycle_hw_axis() -> void:
	hw_axis = (hw_axis + 1) % 3
	_info("Handrad: %s" % axis_name(hw_axis))


func axis_name(axis: int) -> String:
	return ["X (Tisch)", "Y (Kreuzschlitten)", "Z (Fräskopf)"][axis]


## Auto-Vorschub: axis 0..2, sign ±1. Dieselbe Richtung nochmal oder axis -1 schaltet ab.
func set_auto(axis: int, sign: int) -> void:
	if axis < 0 or (axis == auto_axis and sign == auto_sign):
		auto_axis = -1
		return
	if not spindle_on or estop:
		_warn("Vorschub nur bei laufender Spindel.")
		return
	auto_axis = axis
	auto_sign = signi(sign)


func request_new_part() -> void:
	if spindle_speed > 5.0:
		_warn("Erst Spindel stoppen!")
	else:
		new_part_requested.emit()


func request_submit() -> void:
	if spindle_speed > 5.0:
		_warn("Erst Spindel stoppen!")
	else:
		submit_requested.emit()


func cutting_speed() -> float:
	return PI * float(tool()["d"]) * spindle_speed / 1000.0


func feed_per_tooth() -> float:
	return feed_set / maxf(maxf(spindle_speed, rpm_set) * int(tool()["z"]), 1.0)


func _physics_process(delta: float) -> void:
	_msg_cool -= delta
	var target := rpm_set if spindle_on and not estop else 0.0
	var ramp := 2500.0 if target > spindle_speed else (6000.0 if estop else 1800.0)
	spindle_speed = move_toward(spindle_speed, target, ramp * delta)
	spindle.rotate_y(-spindle_speed / 60.0 * TAU * delta)

	# Tippbetrieb im eingestellten Vorschub, Shift = 10-fach
	if operating and not estop:
		var ax := Vector3(Input.get_axis("lathe_z_minus", "lathe_z_plus"), Input.get_axis("lathe_x_out", "lathe_x_in"),
			Input.get_axis("mill_z_down", "mill_z_up"))
		if ax != Vector3.ZERO:
			auto_axis = -1
			var spd := feed_set / 60.0 * (JOG_FAST if Input.is_action_pressed("lathe_rapid") else 1.0)
			var v := ax.normalized() * spd * delta
			move_tool(v.x, v.y, v.z, spd)
			_turn_wheels(v.x, v.y, v.z)
	# Auto-Vorschub läuft auch weiter, wenn niemand an der Maschine steht (wie die Spindel)
	if auto_axis >= 0:
		if estop or spindle_speed <= 30.0:
			auto_axis = -1
		else:
			var d := auto_sign * feed_set / 60.0 * delta
			var before := Vector3(tool_x, tool_y, tool_z)
			var m := Vector3.ZERO
			m[auto_axis] = d
			move_tool(m.x, m.y, m.z, feed_set / 60.0)
			_turn_wheels(m.x, m.y, m.z)
			if before.is_equal_approx(Vector3(tool_x, tool_y, tool_z)) and auto_axis >= 0:
				_info("Auto-Vorschub angehalten (Anschlag).")
				auto_axis = -1

	_cut_t -= delta
	_cut_level = move_toward(_cut_level, 0.0, delta * 2.5)
	chips.emitting = _cut_t > 0.0
	if _cut_t > 0.0:
		_chip_t -= delta
		if _chip_t <= 0.0:
			_chip_t = 0.05
			_drop_chip()
	coolant_fx.emitting = coolant and spindle_speed > 10.0
	_led.material_override = _led_on if spindle_speed > 5.0 else _led_off

	_rebuild_t -= delta
	if _dirty and _rebuild_t <= 0.0:
		_rebuild_t = 0.06
		_dirty = false
		_hmap.update(_height_image())


func _turn_wheels(dx: float, dy: float, dz: float) -> void:
	hw_x.rotation.z -= dx * 0.25
	hw_y.rotation.z -= dy * 0.25
	hw_z.rotation.z -= dz * 0.25


func _process(delta: float) -> void:
	if operating or panel_open:
		_update_camera(delta)
	_screen_t -= delta
	if _screen_t <= 0.0:
		_screen_t = 0.1
		var state := "NOT-HALT" if estop else ("SPINDEL EIN" if spindle_speed > 5.0 else "BEREIT")
		_screen.text = "X %9.3f\nY %9.3f\nZ %9.3f\n%s  %s" % [tool_x, tool_y, tool_z, tool()["id"], state]
	_fill_audio()


func _update_camera(delta: float) -> void:
	if Input.is_action_pressed("zoom_in"):
		_dist_t = maxf(_dist_t * pow(0.3, delta), CAM_MIN)
	if Input.is_action_pressed("zoom_out"):
		_dist_t = minf(_dist_t / pow(0.3, delta), CAM_MAX)
	var k := clampf(12.0 * delta, 0.0, 1.0)
	cam_dist = lerpf(cam_dist, _dist_t, k)
	cam_yaw = lerpf(cam_yaw, _yaw_t, k)
	cam_pitch = lerpf(cam_pitch, _pitch_t, k)
	var want := Vector3(0, MillModel.TOP_Y + maxf(tool_z, 0.0) * 0.0005, 0) + cam_pan
	if _lever_view:
		want = MillModel.LEVER_POS
	cam_target = cam_target.lerp(want, clampf(8.0 * delta, 0.0, 1.0))
	var b := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	op_cam.transform = Transform3D(b, cam_target + b * Vector3(0, 0, cam_dist))


func set_view(view: String) -> void:
	_lever_view = view == "levers"
	match view:
		"levers":
			_yaw_t = PI / 2.0
			_pitch_t = -0.08
			_dist_t = 0.5
		"top":
			_yaw_t = 0.0
			_pitch_t = -PI / 2.0
		"front":
			_yaw_t = 0.0
			_pitch_t = -0.05
		_:
			_yaw_t = CAM_YAW
			_pitch_t = CAM_PITCH
			_dist_t = CAM_DIST
			cam_pan = Vector3.ZERO


# ======================================================================= Bedienung

func get_prompt() -> String:
	return "[%s] Fräsmaschine bedienen" % Settings.binding_text("interact")


func interact(p: Node) -> void:
	if operating or panel_open:
		return
	player = p
	operating = true
	p.start_operating(self, to_global(Vector3(0.0, 0.0, 0.85)), global_rotation.y)
	set_view("reset")
	_activate_camera()
	operating_changed.emit(true)


func stop_operating() -> void:
	if not operating:
		return
	operating = false
	if player:
		player.stop_operating()
	operating_changed.emit(false)


## Station am Hebelfeld: eigene Ansicht, nur die Hebel sind bedienbar.
func open_levers(p: Node) -> void:
	if operating or panel_open:
		return
	player = p
	panel_open = true
	p.start_operating(self, to_global(LEVER_STAND), global_rotation.y + PI / 2.0)
	set_view("levers")
	_activate_camera()
	levers_changed.emit(true)


func close_levers() -> void:
	if not panel_open:
		return
	panel_open = false
	_lever_view = false
	_drag_lever = -1
	_set_lever_hover(false)
	if player:
		player.stop_operating()
	levers_changed.emit(false)


func _activate_camera() -> void:
	op_cam.fov = float(Settings.graphics["fov"]) * 0.75
	cam_dist = _dist_t
	cam_yaw = _yaw_t
	cam_pitch = _pitch_t
	cam_target = MillModel.LEVER_POS if _lever_view else Vector3(0, MillModel.TOP_Y, 0)
	_update_camera(1.0)
	op_cam.make_current()


func _levers_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var o := op_cam.project_ray_origin(event.position)
		var d := op_cam.project_ray_normal(event.position)
		if _drag_lever >= 0:
			_drag_to(o, d)
		else:
			_set_lever_hover(not lever_at(o, d).is_empty())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_drag_lever = -1
			return
		var hit := lever_at(op_cam.project_ray_origin(event.position), op_cam.project_ray_normal(event.position))
		if hit.is_empty():
			return
		get_viewport().set_input_as_handled()
		# Griff festhalten und ziehen, daneben klicken verstellt eine Stufe
		if hit["grab"]:
			_drag_lever = hit["lever"]
		else:
			lever_step(hit["lever"], 1 if hit["up"] else -1)
	elif event.is_action_pressed("interact"):
		close_levers()
		get_viewport().set_input_as_handled()


func _set_lever_hover(on: bool) -> void:
	if on != _lever_hover:
		_lever_hover = on
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if on else Input.CURSOR_ARROW)


## Mausrad-Rasten = Handrad der gewählten Achse. Rad hoch: X+, Y+, Z- (zustellen).
func _handwheel_turn(notches: float) -> void:
	if bool(Settings.mouse.get("handwheel_invert", false)):
		notches = -notches
	var d := notches * Settings.handwheel_step()
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _hw_last_ms) / 1000.0, 0.03, 1.0)
	_hw_last_ms = now
	var spd := absf(d) / dt
	auto_axis = -1
	match hw_axis:
		0:
			move_tool(d, 0.0, 0.0, spd)
			_turn_wheels(d, 0.0, 0.0)
		1:
			move_tool(0.0, d, 0.0, spd)
			_turn_wheels(0.0, d, 0.0)
		_:
			move_tool(0.0, 0.0, -d, spd)
			_turn_wheels(0.0, 0.0, -d)


func _unhandled_input(event: InputEvent) -> void:
	if panel_open:
		_levers_input(event)
		return
	if not operating:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var dir := 0.0
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dir = 1.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dir = -1.0
		if dir != 0.0:
			if mb.ctrl_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				_dist_t = clampf(_dist_t * (0.82 if dir > 0.0 else 1.0 / 0.82), CAM_MIN, CAM_MAX)
			else:
				_handwheel_turn(dir * (mb.factor if mb.factor > 0.0 else 1.0))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var inv := -1.0 if bool(Settings.mouse["invert_y"]) else 1.0
		_yaw_t = clampf(_yaw_t - event.relative.x * 0.005, -PI * 0.75, PI * 0.75)
		_pitch_t = clampf(_pitch_t - event.relative.y * 0.005 * inv, -PI / 2.0, 0.25)
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var b := op_cam.transform.basis
		cam_pan += (-b.x * event.relative.x + b.y * event.relative.y) * cam_dist * 0.0015
		cam_pan = cam_pan.limit_length(0.5)
		return
	for v in [["cam_top", "top"], ["cam_front", "front"], ["cam_reset", "reset"]]:
		if event.is_action_pressed(v[0]):
			set_view(v[1])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interact"):
		stop_operating()
	elif event.is_action_pressed("emergency_stop"):
		toggle_estop()
	elif event.is_action_pressed("spindle_toggle"):
		toggle_spindle()
	elif event.is_action_pressed("hw_axis"):
		cycle_hw_axis()
	elif event.is_action_pressed("hw_step"):
		Settings.cycle_handwheel_step()
		_info("Handrad-Schritt: %s pro Raste" % Settings.handwheel_step_name())
	elif event.is_action_pressed("auto_feed"):
		if auto_axis >= 0:
			set_auto(-1, 0)
		else:
			set_auto(hw_axis, -1 if hw_axis == 2 else 1)
	elif event.is_action_pressed("coolant"):
		toggle_coolant()
	elif event.is_action_pressed("new_workpiece"):
		request_new_part()
	elif event.is_action_pressed("submit_part"):
		request_submit()
	else:
		return
	get_viewport().set_input_as_handled()


# ======================================================================= Prüfung

func evaluate(job: Dictionary) -> Dictionary:
	var lines: Array[String] = []
	var ok := 0
	var total := 0
	var covered := PackedByteArray()
	covered.resize(nx * ny)
	covered.fill(0)
	for f in job["features"]:
		total += 1
		var pass_f: bool
		if str(f["type"]) == "hole":
			pass_f = _check_hole(f, lines, covered)
		else:
			pass_f = _check_area(f, lines, covered)
		if pass_f:
			ok += 1
	if job.has("rest"):
		total += 1
		var want := float(job["rest"])
		var mn := 1.0e9
		var mx := -1.0e9
		for k in nx * ny:
			if covered[k] == 0:
				var h := data[k * 2]
				mn = minf(mn, h)
				mx = maxf(mx, h)
		var pass_r := mn >= want - 0.25 and mx <= want + 0.25
		if pass_r:
			ok += 1
		lines.append("%s  Übrige Fläche:  Z %.2f ... %.2f  (Soll %.1f +/-0,25)" % [_mark(pass_r), mn, mx, want])
	return {"score": float(ok) / maxf(total, 1), "ok": ok, "total": total, "lines": lines}


func _check_area(f: Dictionary, lines: Array[String], covered: PackedByteArray) -> bool:
	var x0 := float(f["x0"])
	var x1 := float(f["x1"])
	var y0 := float(f["y0"])
	var y1 := float(f["y1"])
	var want := float(f["z"])
	var tol := float(f["tol"])
	var mn := 1.0e9
	var mx := -1.0e9
	for j in ny:
		var y := (j + 0.5) * CELL
		if y < y0 - 1.0 or y > y1 + 1.0:
			continue
		for i in nx:
			var x := (i + 0.5) * CELL
			if x < x0 - 1.0 or x > x1 + 1.0:
				continue
			covered[j * nx + i] = 1
			# Rand 1 mm: Übergang zwischen Fläche und Umgebung nicht messen
			if x > x0 + 1.0 or x0 <= 0.0:
				if x < x1 - 1.0 or x1 >= block_l:
					if y > y0 + 1.0 or y0 <= 0.0:
						if y < y1 - 1.0 or y1 >= block_w:
							var h := data[(j * nx + i) * 2]
							mn = minf(mn, h)
							mx = maxf(mx, h)
	var pass_f := mn >= want - tol and mx <= want + tol
	lines.append("%s  X %d-%d  Y %d-%d:  Z %.2f ... %.2f  (Soll %.1f +/-%.2f)" % [_mark(pass_f), int(x0), int(x1), int(y0), int(y1), mn, mx, want, tol])
	return pass_f


func _check_hole(f: Dictionary, lines: Array[String], covered: PackedByteArray) -> bool:
	var cx := float(f["cx"])
	var cy := float(f["cy"])
	var r := float(f["d"]) * 0.5
	var want := float(f["z"])
	var tol := float(f["tol"])
	var around := float(f["around"])
	var mn := 1.0e9
	var mx := -1.0e9
	var wall := true
	for j in ny:
		for i in nx:
			var dist := Vector2((i + 0.5) * CELL - cx, (j + 0.5) * CELL - cy).length()
			if dist > r + 2.5:
				continue
			covered[j * nx + i] = 1
			var h := data[(j * nx + i) * 2]
			if dist < r - 1.0:
				mn = minf(mn, h)
				mx = maxf(mx, h)
			elif dist > r + 1.0 and absf(h - around) > 0.5:
				wall = false
	var pass_f := mn >= want - tol and mx <= want + tol and wall
	lines.append("%s  Bohrung Ø%d bei X %d Y %d:  Z %.2f ... %.2f  (Soll %.1f +/-%.2f)%s" % [
		_mark(pass_f), int(f["d"]), int(cx), int(cy), mn, mx, want, tol, "" if wall else "  Rand beschädigt"])
	return pass_f


func _mark(ok: bool) -> String:
	return "OK  " if ok else "FEHL"


# ======================================================================= Speichern

func get_state() -> Dictionary:
	var raw := data.to_byte_array()
	return {"size": [block_l, block_w, block_h], "x": tool_x, "y": tool_y, "z": tool_z, "tool": tool_idx,
		"rpm": rpm_set, "feed": feed_set, "coolant": coolant, "untouched": untouched,
		"data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_ZSTD))}


func set_state(d: Dictionary) -> void:
	var s = d.get("size", [100.0, 60.0, 40.0])
	new_workpiece(float(s[0]), float(s[1]), float(s[2]))
	var enc := str(d.get("data", ""))
	if enc != "":
		var raw := Marshalls.base64_to_raw(enc).decompress(nx * ny * 8, FileAccess.COMPRESSION_ZSTD)
		if raw.size() == nx * ny * 8:
			data = raw.to_float32_array()
			_hmap.update(_height_image())
	select_tool(int(d.get("tool", 0)), true)
	tool_x = float(d.get("x", tool_x))
	tool_y = float(d.get("y", tool_y))
	tool_z = float(d.get("z", tool_z))
	rpm_set = float(d.get("rpm", rpm_set))
	feed_set = float(d.get("feed", feed_set))
	coolant = bool(d.get("coolant", false))
	untouched = bool(d.get("untouched", true))
	_sync_axes()
	_sync_levers()


# ======================================================================= Audio

func _setup_audio() -> void:
	_audio = AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _MIX
	gen.buffer_length = 0.15
	_audio.stream = gen
	_audio.bus = "SFX"
	_audio.position = Vector3(0, 1.4, 0)
	_audio.unit_size = 4.0
	_audio.max_db = 3.0
	add_child(_audio)
	_audio.play()
	_pb = _audio.get_stream_playback() as AudioStreamGeneratorPlayback


func _fill_audio() -> void:
	if _pb == null:
		return
	var frames := _pb.get_frames_available()
	if frames <= 0:
		return
	var motor := clampf(spindle_speed / 2500.0, 0.0, 1.0)
	var on := 1.0 if spindle_speed > 1.0 else 0.0
	var cut := clampf(_cut_level * 1.5 + (0.3 if _cut_t > 0.0 else 0.0), 0.0, 1.0)
	var f1 := 40.0 + spindle_speed * 0.08
	var f2 := spindle_speed / 60.0 * int(tool()["z"]) + 200.0
	var cool := 1.0 if (coolant and spindle_speed > 10.0) else 0.0
	for i in frames:
		_ph1 = fmod(_ph1 + f1 / _MIX, 1.0)
		_ph2 = fmod(_ph2 + f2 / _MIX, 1.0)
		var n := randf() * 2.0 - 1.0
		_lp = lerpf(_lp, n, 0.3)
		var s := sin(TAU * _ph1) * 0.4 * (0.25 + motor * 0.75) * on * 0.3
		s += sin(TAU * _ph2) * cut * 0.1 + _lp * cut * 0.25
		s += n * cool * 0.04
		_pb.push_frame(Vector2(s, s))
