class_name HallCrane
extends Node3D
## Hallenkran (5 t) mit Funkfernbedienung. Die Brücke fährt auf der Kranbahn in X, die Katze auf der Brücke
## in Z, das Hubwerk hebt und senkt den Haken. Die Fernbedienung hängt in ihrer Halterung an der Hallenwand
## neben dem Meisterbüro: Wer sie nimmt, läuft und schaut frei herum und steuert dabei mit den Pfeiltasten
## nach Himmelsrichtungen wie an einem echten Kran (hoch = Nord / -Z, rechts = Ost / +X), unabhängig von der
## Blickrichtung, und mit Bild auf / Bild ab den Haken. Die Joysticks der Fernbedienung bewegen sich mit. Abgelegt wird sie in der Halterung oder auf einer
## Werkbank, von dort nimmt man sie auch wieder.
## Am Haken hängt ein Spänebehälter, z. B. die Spänekiste unter dem Förderer der E50.
## Das Aussehen kommt aus models/hallenkran.glb (erzeugt mit tools/blender/hallenkran.py): Einträger-Brückenkran
## mit Kastenträger, Kopfträgern auf der Kranbahn, Einschienenkatze mit Seilzug, Unterflasche und Kettengehänge.
## Seile und Schleppleitung spannt das Spiel selbst, weil sie sich mit Haken und Katze bewegen.
## Beim Anfahren und Bremsen pendelt die Last am Seil nach (_step_sway), das ist nur Darstellung.

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
## Halterung der Fernbedienung an der Südwand der Halle, östlich neben der Bürotür: Punkt auf der Wandfläche
## (z = 8) in Höhe der Ablage
const HOLDER_POS := Vector3(9.25, 1.35, 8.0)
const HOLDER_PATH := "res://models/kran_halterung.glb"
const HOLDER_SCALE := 0.04               # 10 Modelleinheiten Breite -> 40 cm
const HOLDER_MODEL_DEPTH := 6.16         # Brett von der Wand nach vorn in Modelleinheiten
const HOLDER_WALL_X := -3.16             # Wandseite des Modells
const MODEL_PATH := "res://models/hallenkran.glb"
const ROPE_R := 0.006                    # Hubseil, 12 mm
const CABLE_LOOPS := 10                  # Schlaufen der Schleppleitung zwischen Brückenende und Katze
const CABLE_LEN := 1.6                   # Leitungslänge je Schlaufe (m)
const CABLE_SIZE := Vector2(0.03, 0.007) # Flachleitung: Breite, Dicke
const CABLE_STEPS := 20                  # Stützpunkte je Schlaufe
const SWAY_GAIN := 0.3                   # wie stark die Last dem Anfahren und Bremsen nachschwingt (1 = echtes Pendel)
const SWAY_DAMP := 0.2                   # Dämpfung des Pendelns (Anteil der kritischen Dämpfung)
const SWAY_MAX := 0.1                    # größter Ausschlag als Anteil der Seillänge

## Spielwelt: crane_find_bin(hook) -> Nummer, crane_hook(i), crane_carry(i, pos), crane_set_down(i, at) -> Fehler,
## crane_bin_height(i), crane_bin_lugs(i) -> Anschlagpunkte, hud
var world: Node
var bridge_x := -6.0
var trolley_z := -1.5
var hook_y := 2.9
var hooked := -1                          # Nummer des Spänebehälters am Haken, -1 = keiner
var held_by: Node = null                  # Spielfigur mit der Fernbedienung in der Hand
var _v := Vector3.ZERO                    # Fahrgeschwindigkeit: x Brücke, y Haken, z Katze
var _v_prev := Vector3.ZERO
var _sway := Vector2.ZERO                 # Auslenkung der Last am Seil (x, z) in m, nur Darstellung
var _sway_v := Vector2.ZERO

var _bridge: Node3D
var _trolley: Node3D
var _ropes: Array[MeshInstance3D] = []
var _rope_top: Array[Vector3] = []        # Seilabgang an der Katze: x und z von der Katze aus, y über dem Boden
var _rope_end: Array[Vector3] = []        # Seilende an der Unterflasche, von der Hakenunterkante aus
var _carriers: Array[Node3D] = []         # Leitungswagen der Schleppleitung auf der Kabelschiene
var _loops: Array[MeshInstance3D] = []    # Schlaufen dazwischen, alle gleich weit
var _loop_mesh: ArrayMesh
var _cable_from := Vector3.ZERO           # festes Ende der Leitung an der Brücke
var _cable_to := Vector3.ZERO             # Mitnehmer an der Katze (von der Katze aus)
var _cable_rail := Vector3.ZERO           # Lage der Kabelschiene (x, y)
var _cable_step := INF                    # Abstand der Wagen, für den die Schlaufe zuletzt gebaut wurde
var _sling: MultiMeshInstance3D           # Kettenstränge vom Aufhängeglied zu den Kranösen des Behälters
var _chain_start := Vector3.ZERO          # unten im Aufhängeglied, von der Hakenunterkante aus
var _chain_pitch := 0.026                 # Teilung der Kette: Abstand zweier Glieder
var _links: Array[Transform3D] = []       # Lage der Kettenglieder, von der Hakenunterkante aus
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
	_lamp_on = Build.emissive(Color(0.2, 1.0, 0.3), 3.0)
	_lamp_off = Build.mat(Color(0.1, 0.25, 0.12), 0.5)
	_bridge = Node3D.new()
	add_child(_bridge)
	_trolley = Node3D.new()
	_bridge.add_child(_trolley)
	_hook = Node3D.new()
	add_child(_hook)
	# Ketten zum Behälter, nur sichtbar, wenn etwas am Haken hängt
	_chains = Node3D.new()
	_hook.add_child(_chains)
	_chains.visible = false
	if not _build_model(steel):
		_build_simple(yellow, anth, steel, black)
	_build_holder(yellow, anth, black)
	_sync()


## Kran aus models/hallenkran.glb. Kranbahn, Brücke, Katze, Meldeleuchte, Unterflasche und Kettengehänge sind
## eigene Objekte mit dem Ursprung im Hallen-Nullpunkt (Unterflasche und Gehänge: an der Hakenunterkante),
## sie kommen unter die Knoten, die das Spiel verschiebt. Leere Objekte im Modell markieren, wo die Seile und
## die Schleppleitung ansetzen. Liefert false, wenn das Modell fehlt oder unvollständig ist.
func _build_model(steel: Material) -> bool:
	if not ResourceLoader.exists(MODEL_PATH):
		return false
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		return false
	var m: Node3D = scene.instantiate()
	var homes := {"Kranbahn": self, "Bruecke": _bridge, "Katze": _trolley, "Lampe": _trolley,
		"Unterflasche": _hook, "Gehaenge": _chains}
	var parts := {}
	for n in homes:
		parts[n] = m.find_child(n, true, false) as Node3D
	var wagon := m.find_child("Kabelwagen", true, false) as Node3D
	var link := m.find_child("Kettenglied", true, false) as MeshInstance3D
	if parts.values().has(null) or wagon == null or link == null or not parts["Lampe"] is MeshInstance3D:
		m.free()
		return false
	for n in homes:
		_adopt(parts[n], homes[n])
	_lamp = parts["Lampe"] as MeshInstance3D
	# Hubseil: ein Strang von der Trommel zur Seilrolle der Unterflasche, einer zurück zum Festpunkt
	for pair in [["Seil_Trommel", "Seil_A"], ["Seil_Festpunkt", "Seil_B"]]:
		_rope_top.append(_mark(parts["Katze"], pair[0]))
		_rope_end.append(_mark(parts["Unterflasche"], pair[1]))
		_ropes.append(Build.cyl(self, ROPE_R, 1.0, Vector3.ZERO, steel, Build.AXIS_Y, false, 8))
	# Schleppleitung: Leitungswagen auf der Kabelschiene, dazwischen hängt die Flachleitung in Schlaufen
	_cable_rail = _mark(parts["Bruecke"], "Kabelschiene")
	_cable_from = _mark(parts["Bruecke"], "Kabel_Fest")
	_cable_to = _mark(parts["Katze"], "Kabel_Katze")
	_adopt(wagon, _bridge)
	_carriers.append(wagon)
	for i in CABLE_LOOPS - 2:
		var c := wagon.duplicate() as Node3D
		_bridge.add_child(c)
		_carriers.append(c)
	# Kettengehänge: Das Aufhängeglied hängt im Haken, die Stränge entstehen beim Einhängen (_fit_sling)
	_chain_start = _mark(parts["Gehaenge"], "Kette_Start")
	_chain_pitch = maxf(_mark(link, "Kette_Teilung").y, 0.01)
	_sling = MultiMeshInstance3D.new()
	_sling.multimesh = MultiMesh.new()
	_sling.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_sling.multimesh.mesh = link.mesh
	_chains.add_child(_sling)
	m.free()
	_loop_mesh = ArrayMesh.new()
	var cable := Build.mat(Color(0.05, 0.05, 0.05), 0.8)
	cable.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in CABLE_LOOPS:
		var mi := MeshInstance3D.new()
		mi.mesh = _loop_mesh
		mi.material_override = cable
		_bridge.add_child(mi)
		_loops.append(mi)
	return true


## Knoten n aus dem geladenen Modell unter den Knoten to hängen (Lage im Modell bleibt).
static func _adopt(n: Node, to: Node) -> void:
	n.get_parent().remove_child(n)
	_disown(n)
	to.add_child(n)


static func _disown(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_disown(c)


## Lage eines leeren Markierungsobjekts im Modellteil part.
static func _mark(part: Node3D, marker: String) -> Vector3:
	var n := part.find_child(marker, true, false) as Node3D
	return part.transform * n.position if n else Vector3.ZERO


## Ersatz ohne Modell: Brücke, Katze und Haken aus Quadern.
func _build_simple(yellow: Material, anth: Material, steel: Material, black: Material) -> void:
	# Brücke: Kastenträger quer über die Halle, Kopfträger mit Laufrädern auf den Kranbahnen
	Build.box(_bridge, Vector3(0.5, 0.6, 15.0), Vector3(0, BRIDGE_Y, 0), yellow)
	for z in [-7.4, 7.4]:
		Build.box(_bridge, Vector3(1.6, 0.35, 0.4), Vector3(0, 5.65, z), yellow)
		for x in [-0.6, 0.6]:
			Build.cyl(_bridge, 0.12, 0.1, Vector3(x, 5.5, z), black, Build.AXIS_Z)
	Build.label(_bridge, "5 t", Vector3(0.26, BRIDGE_Y, 2.0), 0.01, Color(0.1, 0.1, 0.1), 64, PI / 2)
	Build.label(_bridge, "5 t", Vector3(-0.26, BRIDGE_Y, -2.0), 0.01, Color(0.1, 0.1, 0.1), 64, -PI / 2)
	# Katze mit Hubwerk unter der Brücke
	Build.box(_trolley, Vector3(0.9, 0.45, 0.7), Vector3(0, TROLLEY_Y, 0), anth)
	Build.cyl(_trolley, 0.2, 0.6, Vector3(0, TROLLEY_Y - 0.05, 0.0), steel, Build.AXIS_X)
	_lamp = Build.box(_trolley, Vector3(0.08, 0.06, 0.08), Vector3(0.46, TROLLEY_Y - 0.1, 0), _lamp_off)
	_ropes.append(Build.cyl(self, 0.012, 1.0, Vector3.ZERO, steel))
	_rope_top.append(Vector3(0, TROLLEY_Y - 0.25, 0))
	_rope_end.append(Vector3(0, 0.3, 0))
	Build.box(_hook, Vector3(0.16, 0.2, 0.08), Vector3(0, 0.22, 0), yellow)
	Build.cyl(_hook, 0.05, 0.03, Vector3(0, 0.07, 0), steel, Build.AXIS_Z)
	Build.box(_hook, Vector3(0.025, 0.1, 0.025), Vector3(0.04, 0.03, 0), steel)
	for s in [-1.0, 1.0]:
		var c := Build.box(_chains, Vector3(0.025, SLING, 0.025), Vector3(s * 0.25, -SLING * 0.5, 0), steel)
		c.rotation.z = s * 0.42


## Wandkonsole aus models/kran_halterung.glb: Ablagebrett mit zwei Dreiecksstützen, darauf liegt die
## Fernbedienung. Im Modell liegt das Brett bei y = 0 (6 x 10 Einheiten), die Stützen stehen an der Wandseite
## (x = -3,16) und reichen 3,95 nach oben, die Streben laufen zur Vorderkante des Bretts.
func _build_holder(yellow: Material, anth: Material, _black: Material) -> void:
	_holder = Node3D.new()
	_holder.position = HOLDER_POS            # Punkt auf der Wandfläche in Höhe der Brettoberseite
	add_child(_holder)
	var depth := HOLDER_MODEL_DEPTH * HOLDER_SCALE
	if ResourceLoader.exists(HOLDER_PATH):
		var m: Node3D = (load(HOLDER_PATH) as PackedScene).instantiate()
		# Modell-x (von der Wand weg) zeigt in die Halle (-Z), Modell-z läuft an der Wand entlang
		m.rotation.y = PI / 2.0
		m.scale = Vector3.ONE * HOLDER_SCALE
		m.position = Vector3(0, 0, HOLDER_WALL_X * HOLDER_SCALE)   # Wandseite genau auf der Wandfläche
		_holder.add_child(m)
		var steel := Build.mat(Color(0.62, 0.64, 0.66), 0.4, 0.8)
		steel.cull_mode = BaseMaterial3D.CULL_DISABLED   # das Brett ist eine einzelne Fläche
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = anth if str(mi.name) != "Plane" else steel
	else:
		# Ersatz ohne Modell: Brett und zwei Stützen
		Build.box(_holder, Vector3(0.4, 0.008, depth), Vector3(0, -0.004, -depth * 0.5), anth)
		for x in [-0.19, 0.19]:
			Build.box(_holder, Vector3(0.01, 0.16, 0.01), Vector3(x, 0.08, -0.005), anth)
	# Schild über der Konsole
	var sign_y := 3.95 * HOLDER_SCALE + 0.08     # über den Stützen
	Build.box(_holder, Vector3(0.24, 0.07, 0.004), Vector3(0, sign_y, -0.002), yellow)
	Build.label(_holder, "KRAN", Vector3(0, sign_y, -0.005), 0.0016, Color(0.1, 0.1, 0.1), 64, PI)
	# Fernbedienung liegt flach auf dem Brett: Sticks nach oben, Bedienerseite zur Halle (-Z)
	_remote = Node3D.new()
	_remote.position = Vector3(0, 0.047, -depth * 0.5)
	_remote.rotation.y = PI
	_holder.add_child(_remote)
	remote_model(_remote)
	# Nur für den Blickstrahl, die Figur läuft nicht dagegen
	var hit := Build.collider(_holder, Vector3(10.0 * HOLDER_SCALE + 0.04, 0.22, depth + 0.04), Vector3(0, 0.07, -depth * 0.5))
	hit.collision_layer = DroppedItem.LAYER
	hit.set_meta("interact", self)


## Modell der Funkfernbedienung (CraneRemote: Mitte im Ursprung, Sticks nach +Y, Bedienerseite nach +Z),
## auch für die Hand der Spielfigur. Liefert das Modell, damit man es ausrichten kann.
static func remote_model(holder: Node3D) -> CraneRemote:
	var r := CraneRemote.new()
	holder.add_child(r)
	return r


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
	lying.position.y = 0.019                # liegt flach auf der Platte, Sticks nach oben
	_loose.add_child(lying)
	remote_model(lying)
	var pick := RemotePickup.new()
	pick.crane = self
	_loose.add_child(pick)
	var hit := Build.collider(_loose, Vector3(0.28, 0.1, 0.14), Vector3(0, 0.03, 0))
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
	_fit_sling()
	world.hud.show_message("Behälter eingehängt. Mit [%s] anheben." % _key("crane_up"), Color(0.7, 0.95, 1.0))


## Kettenstränge vom Aufhängeglied zu den Kranösen des eingehängten Behälters legen: Glied an Glied,
## abwechselnd um 90 Grad gedreht. Der Behälter hängt starr unter dem Haken, das passt bis zum Aushängen.
func _fit_sling() -> void:
	if _sling == null or hooked < 0:
		return
	var down := Vector3(0, -(SLING + float(world.crane_bin_height(hooked))), 0)
	_links.clear()
	for lug in world.crane_bin_lugs(hooked):
		var d: Vector3 = down + lug - _chain_start
		var count := maxi(1, roundi(d.length() / _chain_pitch))
		var step := d / count
		var along := d.normalized()
		var side := along.cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.001 else Vector3.RIGHT
		var flat := side.cross(along)
		var grow := along * (step.length() / _chain_pitch)
		for i in count:
			var b := Basis(side, grow, flat) if i % 2 == 0 else Basis(flat, grow, -side)
			_links.append(Transform3D(b, _chain_start + step * (i + 0.5)))
	var mm := _sling.multimesh
	mm.instance_count = _links.size()
	for i in _links.size():
		mm.set_instance_transform(i, _links[i])


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
	var stick := Vector3.ZERO                 # Ausschlag der Joysticks an der Fernbedienung
	if held_by != null:
		if not is_instance_valid(held_by) or not held_by.carrying_pendant():
			held_by = null
		elif held_by.operating == null and not held_by.build_mode and _in_range(held_by):
			var iv := Input.get_vector("crane_left", "crane_right", "crane_forward", "crane_back")
			var lift := Input.get_action_strength("crane_up") - Input.get_action_strength("crane_down")
			stick = Vector3(iv.x, lift, iv.y)
			# Himmelsrichtungen wie am echten Kran: hoch = Nord (-Z), rechts = Ost (+X), egal wohin man schaut
			target = Vector3(iv.x * BRIDGE_SPEED, lift * HOOK_SPEED, iv.y * TROLLEY_SPEED)
	CraneRemote.input = stick
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
	_step_sway(delta)
	_sync()


## Seillänge von der Katze bis zur Unterflasche.
func _rope_len() -> float:
	var top := _rope_top[0].y if not _rope_top.is_empty() else TROLLEY_Y
	return maxf(top - hook_y, 0.5)


## Die Last pendelt am Seil nach, wenn Brücke oder Katze anfahren und bremsen: ein gedämpftes Pendel, dessen
## Takt mit der Seillänge langsamer wird. Abgeschwächt (SWAY_GAIN), damit sich der Haken noch setzen lässt.
## Es ist nur Darstellung: Ein- und ausgehängt wird weiter senkrecht unter der Katze (hook_pos).
func _step_sway(delta: float) -> void:
	var acc := Vector2(_v.x - _v_prev.x, _v.z - _v_prev.z) / maxf(delta, 0.001)
	_v_prev = _v
	# Am Fahrwegende steht die Brücke schlagartig: kein Schlag, der die Last meterweit wirft
	acc = acc.limit_length(ACCEL * 2.0)
	if hooked >= 0 and _bin_bottom() < 0.03:
		# Die Last steht auf dem Boden
		_sway = _sway.lerp(Vector2.ZERO, minf(delta * 12.0, 1.0))
		_sway_v = Vector2.ZERO
		return
	var length := _rope_len()
	var w := sqrt(9.81 / length)
	var steps := maxi(1, ceili(delta / 0.01))
	var dt := delta / steps
	for i in steps:
		_sway_v += (-_sway * w * w - acc * SWAY_GAIN - _sway_v * (2.0 * SWAY_DAMP * w)) * dt
		_sway += _sway_v * dt
	if _sway.length() > length * SWAY_MAX:
		_sway = _sway.limit_length(length * SWAY_MAX)
		_sway_v *= 0.5
	if _sway.length() < 0.0005 and _sway_v.length() < 0.0005:
		_sway = Vector2.ZERO
		_sway_v = Vector2.ZERO


func _in_range(p: Node3D) -> bool:
	return Vector2(p.global_position.x - bridge_x, p.global_position.z - trolley_z).length() <= RADIO_RANGE


## Brücke, Katze, Seil, Haken, Last und Fernbedienung an die aktuelle Stellung setzen.
func _sync() -> void:
	_bridge.position.x = bridge_x
	_trolley.position.z = trolley_z
	# Haken und Last hängen um die Pendelauslenkung versetzt, die Seile laufen schräg dorthin
	var length := _rope_len()
	var swing := Vector3(_sway.x, length - sqrt(maxf(length * length - _sway.length_squared(), 0.0)), _sway.y)
	var hp := hook_pos() + swing
	for i in _ropes.size():
		var top := _rope_top[i]
		_line(_ropes[i], Vector3(bridge_x + top.x, top.y, trolley_z + top.z), hp + _rope_end[i])
	_hook.position = hp
	_sync_cable()
	_lamp.material_override = _lamp_on if held_by != null else _lamp_off
	if hooked >= 0:
		world.crane_carry(hooked, Vector3(bridge_x, _bin_bottom(), trolley_z) + swing)
	_remote.visible = held_by == null and remote_bench == ""


## Schleppleitung: Die Leitungswagen verteilen sich gleichmäßig zwischen dem festen Ende an der Brücke und
## dem Mitnehmer der Katze. Fährt die Katze heran, rücken sie zusammen und die Schlaufen hängen tiefer.
func _sync_cable() -> void:
	if _loops.is_empty():
		return
	var z0 := _cable_from.z
	var step := (trolley_z + _cable_to.z - z0) / CABLE_LOOPS
	if absf(step - _cable_step) > 0.0002:
		_cable_step = step
		_build_loop(absf(step))
	for i in _carriers.size():
		_carriers[i].position = Vector3(_cable_rail.x, _cable_rail.y, z0 + step * (i + 1))
	for i in _loops.size():
		_loops[i].position = Vector3(_cable_from.x, _cable_from.y, z0 + step * (i + 0.5))


## Netz einer Schlaufe: Flachleitung der Länge CABLE_LEN, die zwischen zwei Wagen im Abstand span durchhängt
## (Kettenlinie). Ursprung in der Mitte zwischen den Aufhängepunkten, die Leitung läuft entlang z.
func _build_loop(span: float) -> void:
	var half := CABLE_LEN * 0.5
	var w := clampf(span, 0.02, CABLE_LEN * 0.98) * 0.5
	# Formwert a der Kettenlinie aus w = a * asinh(half / a), durch Halbieren
	var lo := 0.0005
	var hi := 100.0
	for i in 40:
		var mid := sqrt(lo * hi)
		if mid * asinh(half / mid) < w:
			lo = mid
		else:
			hi = mid
	var a := sqrt(lo * hi)
	var base := sqrt(a * a + half * half)
	var hw := CABLE_SIZE.x * 0.5
	var ht := CABLE_SIZE.y * 0.5
	var pts: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	for k in CABLE_STEPS + 1:
		# Bogenlänge von der tiefsten Stelle aus, unten dichter gesetzt als an den geraden Enden
		var u := 2.0 * k / CABLE_STEPS - 1.0
		var arc := half * signf(u) * pow(absf(u), 1.6)
		var r := sqrt(a * a + arc * arc)
		pts.append(Vector3(0, r - base, a * asinh(arc / a)))
		nrm.append(Vector3(0, a / r, -arc / r))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var side := Vector3(hw, 0, 0)
	for strip in 4:
		var first := verts.size()
		for k in pts.size():
			var up := nrm[k] * ht
			var n := nrm[k]
			match strip:
				0:
					verts.append(pts[k] + up + side)
					verts.append(pts[k] + up - side)
				1:
					verts.append(pts[k] - up - side)
					verts.append(pts[k] - up + side)
					n = -nrm[k]
				2:
					verts.append(pts[k] - up + side)
					verts.append(pts[k] + up + side)
					n = Vector3.RIGHT
				_:
					verts.append(pts[k] + up - side)
					verts.append(pts[k] - up - side)
					n = Vector3.LEFT
			normals.append(n)
			normals.append(n)
		for k in pts.size() - 1:
			var i := first + k * 2
			idx.append_array(PackedInt32Array([i, i + 2, i + 1, i + 1, i + 2, i + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	_loop_mesh.clear_surfaces()
	_loop_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


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
