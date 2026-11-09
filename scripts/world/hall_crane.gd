class_name HallCrane
extends Node3D
## Hallenkran (5 t) mit Funkfernbedienung. Die Brücke fährt auf der Kranbahn in X, die Katze auf der Brücke
## in Z, das Hubwerk hebt und senkt den Haken. Die Fernbedienung hängt in ihrer Halterung an der Hallenwand
## neben dem Meisterbüro: Wer sie nimmt, läuft und schaut frei herum und steuert dabei mit den Pfeiltasten
## (relativ zur Blickrichtung) und Bild auf / Bild ab. Abgelegt wird sie in der Halterung oder auf einer
## Werkbank, von dort nimmt man sie auch wieder.
## Am Haken hängt ein Spänebehälter, z. B. die Spänekiste unter dem Förderer der E50.

const X_RANGE := Vector2(-11.0, 11.0)     # Fahrweg der Brücke (Hallenwände bei +-12 m)
const Z_RANGE := Vector2(-6.6, 6.6)       # Fahrweg der Katze zwischen den Kranbahnen
const BRIDGE_Y := 5.6
const TROLLEY_Y := 5.1
const HOOK_TOP := 4.6                     # höchste Hakenstellung (Unterkante Haken)
const HOOK_MIN := 0.35
const BRIDGE_SPEED := 1.6                 # m/s
const TROLLEY_SPEED := 1.2
const HOOK_SPEED := 0.7
const ACCEL := 2.5                        # sanftes Anfahren und Bremsen
const SLING := 0.55                       # Ketten zwischen Haken und Oberkante des Behälters
const RADIO_RANGE := 40.0                 # Funkreichweite: weiter weg reagiert der Kran nicht
## Halterung der Fernbedienung an der Südwand der Halle, östlich neben der Bürotür (Wandfläche bei z = 8)
const HOLDER_POS := Vector3(9.25, 1.45, 7.96)

## Spielwelt: crane_find_bin(hook) -> Nummer, crane_hook(i), crane_carry(i, pos), crane_set_down(i, at) -> Fehler,
## crane_bin_height(i), hud
var world: Node
var bridge_x := -6.0
var trolley_z := -1.5
var hook_y := 2.9
var hooked := -1                          # Nummer des Spänebehälters am Haken, -1 = keiner
var held_by: Node = null                  # Spielfigur mit der Fernbedienung in der Hand
var _v := Vector3.ZERO                    # Fahrgeschwindigkeit: x Brücke, y Haken, z Katze

var _bridge: Node3D
var _trolley: Node3D
var _rope: MeshInstance3D
var _hook: Node3D
var _chains: Node3D
var _holder: Node3D
var _remote: Node3D                       # Fernbedienung in der Halterung (versteckt, solange sie woanders ist)
var remote_bench := ""                    # Werkbank (Maschinen-id), auf der die Fernbedienung liegt, "" = nicht
var _loose: Node3D                        # die Fernbedienung auf der Werkbank (Kind der Werkbank, wandert mit)
var _lamp: MeshInstance3D
var _lamp_on: Material
var _lamp_off: Material


func _ready() -> void:
	var yellow := Build.mat(Color(0.95, 0.72, 0.08), 0.5)
	var anth := Build.mat(Color(0.2, 0.22, 0.25), 0.5)
	var steel := Build.mat(Color(0.3, 0.3, 0.3), 0.4, 1.0)
	var black := Build.mat(Color(0.08, 0.08, 0.09), 0.6)
	# Brücke: Kastenträger quer über die Halle, Kopfträger mit Laufrädern auf den Kranbahnen
	_bridge = Node3D.new()
	add_child(_bridge)
	Build.box(_bridge, Vector3(0.5, 0.6, 15.0), Vector3(0, BRIDGE_Y, 0), yellow)
	for z in [-7.4, 7.4]:
		Build.box(_bridge, Vector3(1.6, 0.35, 0.4), Vector3(0, 5.65, z), yellow)
		for x in [-0.6, 0.6]:
			Build.cyl(_bridge, 0.12, 0.1, Vector3(x, 5.5, z), black, Build.AXIS_Z)
	Build.label(_bridge, "5 t", Vector3(0.26, BRIDGE_Y, 2.0), 0.01, Color(0.1, 0.1, 0.1), 64, PI / 2)
	Build.label(_bridge, "5 t", Vector3(-0.26, BRIDGE_Y, -2.0), 0.01, Color(0.1, 0.1, 0.1), 64, -PI / 2)
	# Katze mit Hubwerk unter der Brücke
	_trolley = Node3D.new()
	_bridge.add_child(_trolley)
	Build.box(_trolley, Vector3(0.9, 0.45, 0.7), Vector3(0, TROLLEY_Y, 0), anth)
	Build.cyl(_trolley, 0.2, 0.6, Vector3(0, TROLLEY_Y - 0.05, 0.0), steel, Build.AXIS_X)
	_lamp_on = Build.emissive(Color(0.2, 1.0, 0.3), 3.0)
	_lamp_off = Build.mat(Color(0.1, 0.25, 0.12), 0.5)
	_lamp = Build.box(_trolley, Vector3(0.08, 0.06, 0.08), Vector3(0.46, TROLLEY_Y - 0.1, 0), _lamp_off)
	_rope = Build.cyl(self, 0.012, 1.0, Vector3.ZERO, steel)
	_hook = Node3D.new()
	add_child(_hook)
	Build.box(_hook, Vector3(0.16, 0.2, 0.08), Vector3(0, 0.22, 0), yellow)
	Build.cyl(_hook, 0.05, 0.03, Vector3(0, 0.07, 0), steel, Build.AXIS_Z)
	Build.box(_hook, Vector3(0.025, 0.1, 0.025), Vector3(0.04, 0.03, 0), steel)
	# Ketten zum Behälter, nur sichtbar, wenn etwas am Haken hängt
	_chains = Node3D.new()
	_hook.add_child(_chains)
	_chains.visible = false
	for s in [-1.0, 1.0]:
		var c := Build.box(_chains, Vector3(0.025, SLING, 0.025), Vector3(s * 0.25, -SLING * 0.5, 0), steel)
		c.rotation.z = s * 0.42
	_build_holder(yellow, anth, black)
	_sync()


## Wandhalterung: Grundplatte mit Schild, Köcher mit Haken, darin die Fernbedienung. Vorderseite zeigt nach -Z.
func _build_holder(yellow: Material, anth: Material, black: Material) -> void:
	_holder = Node3D.new()
	_holder.position = HOLDER_POS
	_holder.rotation.y = PI              # die Halterung schaut von der Südwand in die Halle
	add_child(_holder)
	var plate := Build.mat(Color(0.72, 0.74, 0.76), 0.45, 0.6)
	Build.box(_holder, Vector3(0.3, 0.5, 0.012), Vector3(0, 0.02, -0.006), plate)
	for sx in [-0.12, 0.12]:
		for sy in [-0.2, 0.24]:
			Build.cyl(_holder, 0.008, 0.006, Vector3(sx, sy, -0.014), anth, Build.AXIS_Z)
	# Köcher unten offen nach oben, Rückhaltebügel
	Build.box(_holder, Vector3(0.16, 0.012, 0.1), Vector3(0, -0.12, -0.06), anth)
	Build.box(_holder, Vector3(0.012, 0.1, 0.1), Vector3(-0.074, -0.07, -0.06), anth)
	Build.box(_holder, Vector3(0.012, 0.1, 0.1), Vector3(0.074, -0.07, -0.06), anth)
	Build.box(_holder, Vector3(0.16, 0.06, 0.012), Vector3(0, -0.09, -0.11), anth)
	Build.label(_holder, "KRAN", Vector3(0, 0.205, -0.014), 0.0016, Color(0.1, 0.1, 0.1), 64, PI)
	Build.box(_holder, Vector3(0.22, 0.06, 0.004), Vector3(0, 0.205, -0.012), yellow)
	# Fernbedienung: steht im Köcher, Antenne oben
	_remote = Node3D.new()
	_remote.position = Vector3(0, 0.0, -0.06)
	_holder.add_child(_remote)
	remote_model(_remote)
	# Nur für den Blickstrahl, die Figur läuft nicht dagegen
	var hit := Build.collider(_holder, Vector3(0.36, 0.6, 0.3), Vector3(0, 0.02, -0.12))
	hit.collision_layer = DroppedItem.LAYER
	hit.set_meta("interact", self)


## Modell der Funkfernbedienung (Mitte im Ursprung, Tasten nach -Z), auch für die Hand der Spielfigur.
static func remote_model(holder: Node3D) -> void:
	var yellow := Build.mat(Color(0.95, 0.72, 0.08), 0.5)
	var black := Build.mat(Color(0.08, 0.08, 0.09), 0.6)
	Build.box(holder, Vector3(0.085, 0.22, 0.05), Vector3.ZERO, yellow)
	Build.box(holder, Vector3(0.07, 0.03, 0.04), Vector3(0, -0.12, 0), black)
	Build.cyl(holder, 0.006, 0.07, Vector3(0.03, 0.145, 0), black)
	Build.cyl(holder, 0.02, 0.014, Vector3(0, 0.075, -0.027), Build.mat(Color(0.85, 0.1, 0.06), 0.4), Build.AXIS_Z)
	for i in 3:
		for j in 2:
			Build.box(holder, Vector3(0.022, 0.02, 0.01), Vector3(-0.016 + j * 0.032, 0.025 - i * 0.04, -0.027), black)


# ------------------------------------------------------------ Bedienung

## Taste einer Aktion als Text (Autoload über den Baum, damit das Skript auch ohne Autoloads kompiliert).
func _key(action: String) -> String:
	var st := get_node_or_null("/root/Settings")
	return str(st.binding_text(action)) if st else action

## Die Spielfigur erkennt daran die Halterung: Mit der Fernbedienung in der Hand legt E sie hier ab.
func remote_holder() -> bool:
	return true


func get_prompt() -> String:
	if held_by != null:
		if is_instance_valid(held_by) and held_by.carrying_pendant():
			return "[%s] Fernbedienung in die Halterung legen    |    Hallenkran 5 t" % _key("interact")
		return "Halterung leer    |    Hallenkran 5 t"
	if remote_bench != "":
		return "Halterung leer: Die Fernbedienung liegt auf einer Werkbank    |    Hallenkran 5 t"
	return "[%s] Kran-Fernbedienung nehmen    |    Hallenkran 5 t" % _key("interact")


func interact(p: Node) -> void:
	if held_by == p:
		release()
	elif remote_bench == "":
		grab(p)


func click(p: Node) -> void:
	interact(p)


func grab(p: Node) -> void:
	if held_by != null:
		return
	if not p.hands_free():
		world.hud.show_message("Für die Fernbedienung eine Hand frei machen.", Color(1, 0.75, 0.2))
		return
	_clear_loose()
	held_by = p
	p.set_carry({"kind": "pendant", "title": "Kran-Fernbedienung"})
	_sync()
	world.hud.show_message(hint(), Color(0.7, 0.95, 1.0))


func hint() -> String:
	return "Kran: [Pfeiltasten] Brücke und Katze fahren   [%s / %s] Haken heben / senken   [Linksklick] Last ein- / aushängen   Ablegen an der Halterung neben dem Meisterbüro" % [
		_key("crane_up"), _key("crane_down")]


## Fernbedienung zurück in die Halterung (auch beim Laden eines Spielstands).
func release() -> void:
	if held_by == null:
		return
	var p := held_by
	held_by = null
	if is_instance_valid(p) and p.carrying_pendant():
		p.clear_carry()
	_v = Vector3.ZERO
	_sync()


## Q mit der Fernbedienung: Sie wird nicht fallen gelassen, sie gehört in ihre Halterung oder auf eine Werkbank.
func drop_hint() -> void:
	world.hud.show_message("Die Fernbedienung nicht fallen lassen: mit [%s] in die Halterung neben dem Meisterbüro oder auf eine Werkbank legen." % _key("interact"), Color(1, 0.75, 0.2))


## Fernbedienung aus der Hand auf die Werkbank bench (Maschinen-id id) legen, at = Punkt auf der Platte.
func put_on_bench(id: String, bench: Node3D, at: Vector3, yaw: float) -> void:
	if held_by != null:
		var p := held_by
		held_by = null
		if is_instance_valid(p) and p.carrying_pendant():
			p.clear_carry()
	_clear_loose()
	_loose = Node3D.new()
	_loose.name = "Kranfernbedienung"
	bench.add_child(_loose)
	_loose.global_position = at + Vector3(0, 0.026, 0)
	_loose.global_rotation = Vector3(0, yaw, 0)
	var lying := Node3D.new()
	lying.rotation.x = -PI / 2.0            # liegt flach, Tasten nach oben
	_loose.add_child(lying)
	remote_model(lying)
	var pick := RemotePickup.new()
	pick.crane = self
	_loose.add_child(pick)
	var hit := Build.collider(_loose, Vector3(0.14, 0.08, 0.28), Vector3(0, 0.01, 0))
	hit.collision_layer = DroppedItem.LAYER
	hit.set_meta("interact", pick)
	remote_bench = id
	_v = Vector3.ZERO
	_sync()


func _clear_loose() -> void:
	if is_instance_valid(_loose):
		if _loose.get_parent():
			_loose.get_parent().remove_child(_loose)
		_loose.queue_free()
	_loose = null
	remote_bench = ""


## Die Werkbank wird abgebaut: Die Fernbedienung darauf kommt zurück in die Halterung.
func bench_gone(id: String) -> void:
	if remote_bench == id:
		_clear_loose()
		_sync()


## Die Fernbedienung auf der Werkbank: anvisieren und mit E oder Linksklick nehmen.
class RemotePickup extends Node:
	var crane: HallCrane

	func get_prompt() -> String:
		return "[%s] Kran-Fernbedienung nehmen" % crane._key("interact")

	func interact(p: Node) -> void:
		crane.grab(p)

	func click(p: Node) -> void:
		crane.grab(p)


## Linksklick mit dem Taster in der Hand: Last am Haken einhängen oder abgesenkt aushängen.
func hook_click() -> void:
	if hooked >= 0:
		if _bin_bottom() > 0.06:
			world.hud.show_message("Erst ganz absenken: Der Behälter muss auf dem Boden stehen.", Color(1, 0.75, 0.2))
			return
		var err: String = world.crane_set_down(hooked, Vector2(bridge_x, trolley_z))
		if err != "":
			world.hud.show_message(err, Color(1, 0.75, 0.2))
			return
		hooked = -1
		_chains.visible = false
		world.hud.show_message("Behälter abgesetzt und ausgehängt.", Color(0.7, 0.95, 1.0))
		return
	var i: int = world.crane_find_bin(hook_pos())
	if i < 0:
		world.hud.show_message("Kein Spänebehälter am Haken: Haken genau über den Behälter fahren und bis kurz über ihn absenken.", Color(1, 0.75, 0.2))
		return
	hooked = i
	_chains.visible = true
	world.crane_hook(i)
	world.hud.show_message("Behälter eingehängt. Mit [%s] anheben." % _key("crane_up"), Color(0.7, 0.95, 1.0))


## Last vom Haken lösen, ohne sie abzusetzen (Umbau, Laden): Sie bleibt auf ihrem Stellplatz.
func drop_hook() -> void:
	hooked = -1
	_chains.visible = false


func hook_pos() -> Vector3:
	return Vector3(bridge_x, hook_y, trolley_z)


func _bin_bottom() -> float:
	if hooked < 0:
		return 0.0
	return hook_y - SLING - float(world.crane_bin_height(hooked))


func _min_hook() -> float:
	if hooked < 0:
		return HOOK_MIN
	return SLING + float(world.crane_bin_height(hooked))


# ------------------------------------------------------------ Fahren

func _physics_process(delta: float) -> void:
	var target := Vector3.ZERO
	if held_by != null:
		if not is_instance_valid(held_by) or not held_by.carrying_pendant():
			held_by = null
		elif held_by.operating == null and not held_by.build_mode and _in_range(held_by):
			var iv := Input.get_vector("crane_left", "crane_right", "crane_forward", "crane_back")
			# Relativ zur Blickrichtung: Pfeil hoch fährt dorthin, wohin die Figur schaut
			var d := Basis(Vector3.UP, float(held_by.yaw)) * Vector3(iv.x, 0, iv.y)
			var lift := Input.get_action_strength("crane_up") - Input.get_action_strength("crane_down")
			target = Vector3(d.x * BRIDGE_SPEED, lift * HOOK_SPEED, d.z * TROLLEY_SPEED)
	_v = _v.move_toward(target, ACCEL * delta)
	var nx := clampf(bridge_x + _v.x * delta, X_RANGE.x, X_RANGE.y)
	var nz := clampf(trolley_z + _v.z * delta, Z_RANGE.x, Z_RANGE.y)
	var ny := clampf(hook_y + _v.y * delta, _min_hook(), HOOK_TOP)
	if nx != bridge_x + _v.x * delta:
		_v.x = 0.0
	if nz != trolley_z + _v.z * delta:
		_v.z = 0.0
	if ny != hook_y + _v.y * delta:
		_v.y = 0.0
	bridge_x = nx
	trolley_z = nz
	hook_y = ny
	_sync()


func _in_range(p: Node3D) -> bool:
	return Vector2(p.global_position.x - bridge_x, p.global_position.z - trolley_z).length() <= RADIO_RANGE


## Brücke, Katze, Seil, Haken, Last und Fernbedienung an die aktuelle Stellung setzen.
func _sync() -> void:
	_bridge.position.x = bridge_x
	_trolley.position.z = trolley_z
	var top := Vector3(bridge_x, TROLLEY_Y - 0.25, trolley_z)
	var hp := hook_pos()
	_line(_rope, top, hp + Vector3(0, 0.3, 0))
	_hook.position = hp
	_lamp.material_override = _lamp_on if held_by != null else _lamp_off
	if hooked >= 0:
		world.crane_carry(hooked, Vector3(bridge_x, _bin_bottom(), trolley_z))
	_remote.visible = held_by == null and remote_bench == ""


## Dünnen Zylinder (Länge 1 entlang Y) zwischen a und b spannen.
static func _line(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		mi.visible = false
		return
	mi.visible = true
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


# ------------------------------------------------------------ Speichern

func get_state() -> Dictionary:
	var st := {"x": bridge_x, "z": trolley_z, "y": hook_y}
	if remote_bench != "" and is_instance_valid(_loose):
		var g := _loose.global_position
		st["remote"] = {"bench": remote_bench, "pos": [g.x, g.y - 0.026, g.z], "yaw": _loose.global_rotation.y}
	return st


func set_state(d: Dictionary) -> void:
	drop_hook()
	release()
	_clear_loose()
	var r = d.get("remote", null)
	if r is Dictionary:
		var bench: Node3D = world.bench_nodes.get(str(r.get("bench", "")), null)
		var pos = r.get("pos", [])
		if bench and pos is Array and pos.size() == 3:
			put_on_bench(str(r["bench"]), bench, Vector3(float(pos[0]), float(pos[1]), float(pos[2])), float(r.get("yaw", 0.0)))
	bridge_x = clampf(float(d.get("x", bridge_x)), X_RANGE.x, X_RANGE.y)
	trolley_z = clampf(float(d.get("z", trolley_z)), Z_RANGE.x, Z_RANGE.y)
	hook_y = clampf(float(d.get("y", hook_y)), HOOK_MIN, HOOK_TOP)
	_v = Vector3.ZERO
	_sync()
