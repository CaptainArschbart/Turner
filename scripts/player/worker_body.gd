class_name WorkerBody
extends Node3D
## Spielfigur in der Außenansicht: Zerspanungsmechaniker in Latzhose (dunkelblau, orange Akzente),
## grauem Langarmshirt, Sicherheitsschuhen, Schutzbrille und Gehörschutz um den Hals.
## Keine Handschuhe - an der Drehmaschine verboten. Gelenke: Hüfte, Knie, Knöchel, Schulter, Ellbogen,
## Rumpf und Kopf; pose() bewegt alles für Gehen, Rennen, Hocken, Springen, Tragen und Werkzeug halten.
## Vorne ist -Z, die Füße stehen bei y = 0.

## Halter am rechten Handgriff (Werkzeug) und vor der Brust (Getragenes)
## Linke Hand am Mund: Schulter (x vor, z nach innen) und Ellbogen
const SMOKE_SH := Vector3(0.75, 0, 1.25)
const SMOKE_EL := 2.3
const LEG := 0.9                  # Beinlänge Hüfte bis Sohle

## Phase des Gehzyklus (0..2π je zwei Schritte); die Ego-Kamera wippt im selben Takt.
func walk_phase() -> float:
	return _walk_t

var tool_grip: Node3D
var carry_hold: Node3D

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _thigh: Array[Node3D] = []
var _knee: Array[Node3D] = []
var _ankle: Array[Node3D] = []
var _shoulder: Array[Node3D] = []
var _elbow: Array[Node3D] = []
var _hands: Array[WorkerHand] = []
var _walk_t := 0.0
var _crouch := 0.0
var _carry := 0.0                 # 0 Hände frei, 1 trägt mit beiden Händen
var _tool := 0.0                  # 1 Werkzeug in der Rechten
var _air := 0.0
var _poke := 0.0
var _breath := 0.0
var _carry_wide := 0.2            # halbe Breite des Getragenen (Hände an den Seiten)
var _shadow_only := false
var smoke_hand := 0.0            # 0..1 linke Hand an den Mund (Zug an der Zigarette)
var smoke_chin := 0.0            # 0..1 Kinn leicht heben (Ausatmen)


func _ready() -> void:
	var navy := Build.mat(Color(0.11, 0.16, 0.29), 0.9)
	var navy_dark := Build.mat(Color(0.07, 0.1, 0.18), 0.9)
	var orange := Build.mat(Color(0.95, 0.48, 0.08), 0.65)
	var shirt := Build.mat(Color(0.3, 0.33, 0.37), 0.95)
	var skin := Build.mat(Color(0.86, 0.66, 0.52), 0.65)
	var lip := Build.mat(Color(0.7, 0.45, 0.4), 0.6)
	var hair := Build.mat(Color(0.25, 0.17, 0.1), 0.95)
	var eye := Build.mat(Color(0.08, 0.08, 0.1), 0.3)
	var white := Build.mat(Color(0.95, 0.95, 0.93), 0.5)
	var boot := Build.mat(Color(0.1, 0.09, 0.08), 0.6)
	var sole := Build.mat(Color(0.18, 0.18, 0.18), 0.9)
	var steel_cap := Build.mat(Color(0.35, 0.35, 0.33), 0.5, 0.4)
	var frame := Build.mat(Color(0.1, 0.1, 0.12), 0.4)
	var lens := Build.glass(Color(0.75, 0.85, 0.95, 0.35))
	var ear := Build.mat(Color(0.85, 0.15, 0.1), 0.5)
	var yellow := Build.mat(Color(0.95, 0.8, 0.15), 0.6)

	_hips = Node3D.new()
	_hips.position.y = 0.93
	add_child(_hips)
	# Becken der Latzhose
	_capsule(_hips, 0.16, 0.36, Vector3(0, 0.0, 0), navy, Vector3(1.0, 0.55, 0.62))
	Build.box(_hips, Vector3(0.34, 0.035, 0.2), Vector3(0, 0.06, 0), navy_dark)                    # Bund

	# Beine
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var th := Node3D.new()
		th.position = Vector3(s * 0.095, -0.02, 0)
		_hips.add_child(th)
		_capsule(th, 0.078, 0.48, Vector3(0, -0.22, 0), navy)
		# Oberschenkeltasche mit Zollstock (rechts) bzw. Knieschutztasche
		Build.box(th, Vector3(0.01, 0.15, 0.11), Vector3(s * 0.078, -0.2, 0), navy_dark)
		if s > 0:
			Build.box(th, Vector3(0.014, 0.05, 0.02), Vector3(0.083, -0.11, 0.02), yellow)
		var kn := Node3D.new()
		kn.position.y = -0.44
		th.add_child(kn)
		Build.box(kn, Vector3(0.13, 0.13, 0.03), Vector3(0, -0.04, -0.066), navy_dark)             # Kniepolster
		Build.box(kn, Vector3(0.135, 0.02, 0.035), Vector3(0, 0.02, -0.066), orange)
		_capsule(kn, 0.066, 0.44, Vector3(0, -0.21, 0), navy)
		Build.cyl(kn, 0.07, 0.04, Vector3(0, -0.38, 0), orange, Build.AXIS_Y, false, 16)            # Reflexstreifen
		var an := Node3D.new()
		an.position.y = -0.42
		kn.add_child(an)
		# Sicherheitsschuh: Schaft, Schuh, Stahlkappe, Sohle
		Build.cyl(an, 0.06, 0.1, Vector3(0, 0.0, 0.0), boot, Build.AXIS_Y, false, 16)
		Build.box(an, Vector3(0.12, 0.09, 0.25), Vector3(0, -0.04, -0.045), boot)
		Build.box(an, Vector3(0.118, 0.06, 0.06), Vector3(0, -0.05, -0.15), steel_cap)
		Build.box(an, Vector3(0.13, 0.025, 0.28), Vector3(0, -0.092, -0.045), sole)
		_thigh.append(th)
		_knee.append(kn)
		_ankle.append(an)

	# Rumpf (dreht sich in der Hüfte)
	_torso = Node3D.new()
	_torso.position.y = 0.06
	_hips.add_child(_torso)
	_capsule(_torso, 0.19, 0.6, Vector3(0, 0.28, 0), shirt, Vector3(1.0, 1.0, 0.64))
	# Latz mit Brusttasche, Stift und orangem Rand, Träger über die Schultern
	Build.box(_torso, Vector3(0.3, 0.3, 0.02), Vector3(0, 0.17, -0.118), navy)
	Build.box(_torso, Vector3(0.3, 0.02, 0.022), Vector3(0, 0.32, -0.118), orange)
	Build.box(_torso, Vector3(0.12, 0.1, 0.012), Vector3(0.04, 0.22, -0.13), navy_dark)
	Build.cyl(_torso, 0.005, 0.07, Vector3(0.07, 0.27, -0.135), Build.mat(Color(0.85, 0.1, 0.1), 0.5))
	Build.box(_torso, Vector3(0.3, 0.12, 0.2), Vector3(0, 0.03, 0), navy)                          # Hosenbund rundum
	for s in [-1.0, 1.0]:
		# Träger: vorn vom Latz hoch, über die Schulter, hinten runter
		Build.box(_torso, Vector3(0.045, 0.2, 0.012), Vector3(s * 0.1, 0.42, -0.108), navy, false, Vector3(-0.22, 0, 0))
		Build.box(_torso, Vector3(0.045, 0.012, 0.2), Vector3(s * 0.1, 0.535, 0.0), navy)
		Build.box(_torso, Vector3(0.045, 0.3, 0.012), Vector3(s * 0.08, 0.37, 0.108), navy, false, Vector3(0.18, 0, s * 0.2))
		Build.cyl(_torso, 0.012, 0.012, Vector3(s * 0.1, 0.33, -0.13), Build.mat(Color(0.7, 0.7, 0.68), 0.3, 0.8), Build.AXIS_Z)  # Knopf
	# Rückenschild
	Build.box(_torso, Vector3(0.16, 0.06, 0.005), Vector3(0, 0.38, 0.122), orange)
	# Hals mit Gehörschutz (Kapseln hängen vorn)
	Build.cyl(_torso, 0.056, 0.09, Vector3(0, 0.58, 0.005), skin, Build.AXIS_Y, false, 16)
	Build.cyl(_torso, 0.07, 0.03, Vector3(0, 0.56, 0.005), shirt, Build.AXIS_Y, false, 16)       # Kragen
	Build.box(_torso, Vector3(0.19, 0.016, 0.03), Vector3(0, 0.575, 0.065), Build.mat(Color(0.15, 0.15, 0.15), 0.5))
	for s in [-1.0, 1.0]:
		Build.cyl(_torso, 0.036, 0.028, Vector3(s * 0.09, 0.55, -0.01), ear, Build.AXIS_X, false, 16)

	# Kopf
	_head = Node3D.new()
	_head.position.y = 0.6
	_torso.add_child(_head)
	var skull := Build.sphere(_head, 0.112, Vector3(0, 0.11, 0), skin)
	skull.scale = Vector3(0.9, 1.08, 1.0)
	Build.box(_head, Vector3(0.12, 0.06, 0.09), Vector3(0, 0.035, -0.04), skin)                   # Kiefer
	Build.box(_head, Vector3(0.024, 0.04, 0.03), Vector3(0, 0.1, -0.112), skin, false, Vector3(-0.25, 0, 0))   # Nase
	Build.box(_head, Vector3(0.045, 0.008, 0.01), Vector3(0, 0.045, -0.1), lip)                   # Mund
	for s in [-1.0, 1.0]:
		var ear_m := Build.sphere(_head, 0.024, Vector3(s * 0.1, 0.11, 0.0), skin)
		ear_m.scale = Vector3(0.45, 1.0, 0.75)
		Build.sphere(_head, 0.013, Vector3(s * 0.036, 0.125, -0.096), white)
		Build.sphere(_head, 0.007, Vector3(s * 0.036, 0.125, -0.107), eye)
		Build.box(_head, Vector3(0.035, 0.008, 0.01), Vector3(s * 0.037, 0.152, -0.103), hair)      # Augenbraue
		# Schutzbrille: Gläser mit Rahmen und Bügeln
		Build.box(_head, Vector3(0.05, 0.034, 0.004), Vector3(s * 0.036, 0.125, -0.117), lens)
		Build.box(_head, Vector3(0.054, 0.006, 0.006), Vector3(s * 0.036, 0.143, -0.117), frame)
		Build.box(_head, Vector3(0.004, 0.006, 0.11), Vector3(s * 0.093, 0.138, -0.062), frame)
	Build.box(_head, Vector3(0.022, 0.006, 0.006), Vector3(0, 0.133, -0.12), frame)
	# Kurze Haare: Oberkopf und Hinterkopf, Ansatz über der Stirn
	var top := Build.sphere(_head, 0.117, Vector3(0, 0.15, 0.01), hair)
	top.scale = Vector3(0.94, 0.74, 1.0)
	var back := Build.sphere(_head, 0.1, Vector3(0, 0.1, 0.03), hair)
	back.scale = Vector3(1.0, 0.9, 0.9)

	# Arme
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var sh := Node3D.new()
		sh.position = Vector3(s * 0.215, 0.47, 0)
		_torso.add_child(sh)
		var cap := Build.sphere(sh, 0.054, Vector3(-s * 0.012, 0.0, 0), shirt)
		cap.scale = Vector3(1.0, 0.8, 1.0)
		_capsule(sh, 0.049, 0.32, Vector3(0, -0.14, 0), shirt)
		var el := Node3D.new()
		el.position.y = -0.29
		sh.add_child(el)
		_capsule(el, 0.043, 0.27, Vector3(0, -0.12, 0), shirt)
		Build.cyl(el, 0.045, 0.02, Vector3(0, -0.1, 0), orange, Build.AXIS_Y, false, 16)
		Build.cyl(el, 0.04, 0.03, Vector3(0, -0.235, 0), navy_dark, Build.AXIS_Y, false, 16)        # Bündchen
		var h := WorkerHand.new(s, skin)
		h.position.y = -0.26
		# Finger nach unten, Handfläche zum Körper, Daumen nach vorn
		var z := Vector3(0, 1, 0)
		var y := Vector3(s, 0, 0)
		h.basis = Basis(y.cross(z), y, z)
		el.add_child(h)
		h.grip(0.0)
		h.snap()
		_shoulder.append(sh)
		_elbow.append(el)
		_hands.append(h)
	# rechte Hand (i = 1): Werkzeug liegt in der Griffachse (lokal X der Hand)
	tool_grip = Node3D.new()
	tool_grip.position = WorkerHand.grip_offset(0.012)
	tool_grip.rotation.y = PI / 2        # Spitze zur Daumenseite
	_hands[1].add_child(tool_grip)
	carry_hold = Node3D.new()
	carry_hold.position = Vector3(0, 0.2, -0.4)
	_torso.add_child(carry_hold)


func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, sc := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.scale = sc
	parent.add_child(mi)
	return mi


## Nur der Schatten (Ego-Ansicht) oder ganz sichtbar (Außenansicht).
func set_shadow_only(on: bool) -> void:
	_shadow_only = on
	_set_cast(self, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func _set_cast(n: Node, mode: int) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = mode
		_set_cast(c, mode)


## Was die Hände halten: "none", "tool" oder "carry" (halbe Breite des Getragenen).
func set_holding(kind: String, half_width := 0.2) -> void:
	grab = []
	_carry_wide = half_width
	set_shadow_only(_shadow_only)      # neu Gehaltenes wie der Rest der Figur
	_hands[0].grip(0.012 if kind == "carry" else 0.0)
	_hands[1].grip(0.012 if kind != "none" else 0.0)
	_target_carry = 1.0 if kind == "carry" else 0.0
	_target_tool = 1.0 if kind == "tool" else 0.0


var _target_carry := 0.0
var _target_tool := 0.0
var _bucket_hold: Node3D               # Eimer am Henkel in der rechten Faust (hängt am Arm, schwingt beim Gehen mit)


## Eimer (oder anderes Hängendes) in die rechte Hand geben, null = loslassen. Der Knoten hängt nach unten.
func set_bucket(model: Node3D) -> void:
	if _bucket_hold:
		_bucket_hold.get_parent().remove_child(_bucket_hold)
		_bucket_hold.queue_free()
		_bucket_hold = null
	if model == null:
		return
	_bucket_hold = Node3D.new()
	_bucket_hold.position = Vector3(0, -0.28, 0.02)       # Faust am Ende des Unterarms
	_elbow[1].add_child(_bucket_hold)
	_bucket_hold.add_child(model)
	_hands[1].grip(0.012)
	set_shadow_only(_shadow_only)
var grab: Array[Vector3] = []          # Weltpunkte, die beide Hände greifen (Griffbügel der Deichsel)
var _grab_w := 0.0


## Beide Hände an Weltpunkte legen (leer = Arme wieder frei). Die Arme werden per Zwei-Knochen-IK gebeugt.
func set_grab(points: Array[Vector3]) -> void:
	var was := grab.size() == 2
	grab = points
	if (grab.size() == 2) != was:
		for h in _hands:
			h.grip(0.012 if grab.size() == 2 else 0.0)


## IK für Schulter und Ellbogen: Hand an das Ziel, Ellbogen nach unten und leicht nach außen.
func _apply_grab() -> void:
	var inv := _torso.global_transform.affine_inverse()
	var pts: Array[Vector3] = [inv * grab[0], inv * grab[1]]
	if pts[0].x > pts[1].x:
		pts = [pts[1], pts[0]]
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var sh := _shoulder[i]
		var l1 := 0.29
		var l2 := 0.31
		var from := sh.position
		var d: Vector3 = pts[i] - from
		var dist := clampf(d.length(), 0.08, (l1 + l2) * 0.998)
		var dn := d.normalized()
		var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
		var ang := acos(ca)
		var pole := Vector3(s * 0.35, -1.0, 0.25)
		var perp := (pole - dn * pole.dot(dn)).normalized()
		var elbow := from + dn * (l1 * ca) + perp * (l1 * sin(ang))
		var wrist := from + dn * dist
		var up := Quaternion(Vector3(0, -1, 0), (elbow - from).normalized())
		var sh_basis := Basis(up)
		var fa_local := sh_basis.inverse() * (wrist - elbow).normalized()
		var fa := Quaternion(Vector3(0, -1, 0), fa_local)
		var old_s := sh.basis.get_rotation_quaternion()
		var old_e := _elbow[i].basis.get_rotation_quaternion()
		sh.basis = Basis(old_s.slerp(up, _grab_w))
		_elbow[i].basis = Basis(old_e.slerp(fa, _grab_w))


## Linksklick mit freien Händen: rechter Arm tippt nach vorn.
func poke() -> void:
	_poke = 1.0


## Pro Bild: Geschwindigkeit, Bodenkontakt, Hocken, Rennen und Blickneigung (Kopf folgt).
func pose(delta: float, hspeed: float, on_floor: bool, crouching: bool, sprinting: bool, pitch: float) -> void:
	var k := clampf(delta * 8.0, 0.0, 1.0)
	_crouch = lerpf(_crouch, 1.0 if crouching else 0.0, k)
	_carry = lerpf(_carry, _target_carry, k)
	_tool = lerpf(_tool, _target_tool, k)
	_air = lerpf(_air, 0.0 if on_floor else 1.0, k)
	_poke = move_toward(_poke, 0.0, delta * 3.0)
	_breath += delta
	var amt := clampf(hspeed / 3.2, 0.0, 1.8) if on_floor else 0.0
	var run := clampf(amt - 1.0, 0.0, 1.0) if sprinting else 0.0
	var stride := 0.52 * minf(amt, 1.0) + 0.28 * maxf(amt - 1.0, 0.0)
	# Schrittfrequenz aus der Schrittlänge: Ein Zyklus (zwei Schritte) legt 4 * Beinlänge * sin(stride)
	# zurück, so bleiben die Füße beim Aufsetzen am Boden stehen statt zu rutschen.
	var cycle := 4.0 * LEG * sin(maxf(stride, 0.3))
	_walk_t = fmod(_walk_t + delta * hspeed * TAU / cycle, TAU * 64.0)
	var ph := _walk_t
	var gait := minf(amt, 1.5)

	# Beine: Hüfte schwingt, Knie beugt sich in der Schwungphase (Bein bewegt sich nach vorn),
	# in der Standphase bleibt es fast gestreckt, der Fuß rollt von der Ferse über die Spitze ab.
	for i in 2:
		var p := ph + (PI if i == 1 else 0.0)
		var swing := sin(p) * stride
		var fwd := cos(p)                               # > 0: Bein schwingt nach vorn
		var lift := maxf(0.0, fwd) * sin(maxf(0.0, fwd) * PI * 0.5 + 0.6) * stride * (1.9 + run * 1.4)
		var flex := maxf(0.0, -fwd) * 0.08 * gait       # leichtes Federn im Standbein
		var hip := swing + _crouch * 1.35 + _air * 0.5 * (1.0 if i == 0 else 0.2)
		var knee := -lift - flex - _crouch * 2.1 - _air * (0.9 if i == 0 else 0.4)
		_thigh[i].rotation = Vector3(hip, 0, 0)
		_knee[i].rotation = Vector3(knee, 0, 0)
		# Ferse vorn auf, Spitze hinten ab
		var roll := (0.25 * maxf(0.0, swing) - 0.35 * maxf(0.0, -swing)) * minf(amt, 1.0)
		_ankle[i].rotation = Vector3(-(hip + knee) * 0.9 + roll, 0, 0)
	# Becken: oben, wenn das Standbein senkrecht steht, unten beim Fersenaufsatz; verlagert das
	# Gewicht seitlich aufs Standbein und dreht mit dem schwingenden Bein nach vorn.
	var bounce := (absf(cos(ph)) - 0.6) * 0.035 * gait
	_hips.position.y = 0.93 - _crouch * 0.42 + bounce - 0.015 * amt
	_hips.position.x = cos(ph) * 0.022 * minf(amt, 1.0) * (1.0 - run * 0.5)
	_hips.position.z = _crouch * 0.12
	var hip_yaw := -sin(ph) * 0.2 * stride
	_hips.rotation = Vector3(0, hip_yaw, -cos(ph) * 0.035 * gait)
	# Oberkörper dreht gegen das Becken (Schultern gegen die Hüfte) und neigt sich beim Rennen vor
	var lean := 0.05 * amt + run * 0.22 + _crouch * 0.45
	_torso.rotation = Vector3(-lean, -hip_yaw * 1.8, cos(ph) * 0.05 * gait)
	_torso.position.y = 0.06 + sin(_breath * 1.6) * 0.004
	# Kopf bleibt ruhig nach vorn gerichtet
	_head.rotation = Vector3(clampf(pitch, -1.0, 1.0) * 0.7 + lean * 0.8, hip_yaw * 0.8, -cos(ph) * 0.015 * gait)
	_head.rotation.x += smoke_chin * 0.22

	# Arme: Gegenschwung zum Bein, beim Tragen nach vorn, Werkzeug in der Rechten vorgestreckt
	for i in 2:
		var p := ph + (0.0 if i == 1 else PI)
		var s := -1.0 if i == 0 else 1.0
		var swing := sin(p) * stride * 0.9 * (1.0 - _carry) * (1.0 - (_tool if i == 1 else 0.0))
		var sh_x := swing + 0.05
		var el_x := 0.15 + maxf(0.0, swing) * 0.6 + run * 1.0
		var sh_z := s * 0.08
		# Tragen: Oberarme nach vorn-unten, Unterarme waagerecht, Hände an den Seiten des Getragenen
		var spread := clampf((0.225 - _carry_wide) / 0.3, -0.3, 0.6)
		sh_x = lerpf(sh_x, 0.45, _carry)
		el_x = lerpf(el_x, 1.1, _carry)
		sh_z = lerpf(sh_z, -s * spread, _carry)
		if i == 1:
			sh_x = lerpf(sh_x, 0.35, _tool)
			el_x = lerpf(el_x, 1.2, _tool)
			sh_z = lerpf(sh_z, 0.0, _tool)
			var pk := sin(_poke * PI)
			sh_x += pk * 1.1
			el_x = lerpf(el_x, 0.2, pk)
		if i == 0 and smoke_hand > 0.0:
			var sk := smoke_hand * (1.0 - _carry)
			sh_x = lerpf(sh_x, SMOKE_SH.x, sk)
			sh_z = lerpf(sh_z, SMOKE_SH.z, sk)
			el_x = lerpf(el_x, SMOKE_EL, sk)
		_shoulder[i].rotation = Vector3(sh_x, 0, sh_z)
		_elbow[i].rotation = Vector3(el_x, 0, 0)
	_grab_w = move_toward(_grab_w, 1.0 if grab.size() == 2 else 0.0, delta * 6.0)
	if _grab_w > 0.001 and grab.size() == 2:
		_apply_grab()
	carry_hold.visible = _target_carry > 0.5
