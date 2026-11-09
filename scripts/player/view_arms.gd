class_name ViewArms
extends Node3D
## Ego-Ansicht: Unterarme und Hände vor der Kamera, die den Gegenstand in der Hand wirklich greifen.
## Haltungen:
##   "none"  - Hände frei, Arme unten aus dem Bild
##   "tool"  - Werkzeug in der rechten Faust, Spitze nach vorn (wie eine Taschenlampe)
##   "bar"   - Stange / Flachmaterial quer vor dem Körper, beide Hände im Obergriff
##   "box"   - Behälter / Teil mit beiden Händen an den Seitenkanten
##   "point" - kurz: rechter Zeigefinger tippt nach vorn (Linksklick mit freien Händen)
##   "grip"  - beide Hände greifen die Weltpunkte in grip_world (Griffbügel der Hubwagen-Deichsel)
## Dazu Gehwippen, Nachziehen beim Umsehen, Hochnehmen beim Greifen und Stoß beim Klicken.

## Halter für den Gegenstand (Kamerakoordinaten, wird mit dem Ganzen mitbewegt)
var item: Node3D
var mode := "none"
var grip_world: Array[Vector3] = []   # bei "grip": Weltpunkte der beiden Hände, vom Spieler jedes Bild gesetzt

var _hands: Array[WorkerHand] = []
var _forearms: Array[Node3D] = []
## je Hand: Griffmitte, Griffachse, Ellbogen, Radius - aktuell und Ziel
var _p: Array[Vector3] = [Vector3(0.3, -0.75, -0.2), Vector3(-0.3, -0.75, -0.2)]
var _g: Array[Vector3] = [Vector3(0, 0, 1), Vector3(0, 0, 1)]
var _e: Array[Vector3] = [Vector3(0.4, -0.8, 0.3), Vector3(-0.4, -0.8, 0.3)]
var _p_t: Array[Vector3] = _p.duplicate()
var _g_t: Array[Vector3] = _g.duplicate()
var _e_t: Array[Vector3] = _e.duplicate()
var _r: Array[float] = [0.0, 0.0]
var _show: Array[bool] = [false, false]

var _item_pos := Vector3(0.2, -0.2, -0.42)
var _item_rot := Vector3.ZERO
var _raise := 1.0                 # 0 = gerade erst gegriffen (unten), 1 = oben
var _jab := 0.0                   # Klickstoß, klingt ab
var _point_t := 0.0               # Restzeit der Zeigegeste
var _bob_t := 0.0
var walk_phase := 0.0             # Gehphase der Figur, vom Spieler gesetzt
var _bob_amp := 0.0
var _sway := Vector2.ZERO
var _land := 0.0
var _sprint := 0.0
var _breath := 0.0


func _ready() -> void:
	var skin := Build.mat(Color(0.86, 0.66, 0.52), 0.65)
	var sleeve := Build.mat(Color(0.3, 0.33, 0.37), 0.9)
	var cuff := Build.mat(Color(0.12, 0.17, 0.3), 0.85)
	var stripe := Build.mat(Color(0.95, 0.5, 0.08), 0.6)
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		var fa := Node3D.new()
		add_child(fa)
		# Handgelenk, enges Bündchen, Ärmel (verjüngt zum Handgelenk) mit Warnstreifen
		Build.cyl(fa, 0.026, 0.05, Vector3(0, 0, 0.02), skin, Build.AXIS_Z, false, 16, 0.029)
		Build.cyl(fa, 0.034, 0.03, Vector3(0, 0, 0.055), cuff, Build.AXIS_Z, false, 16, 0.036)
		Build.cyl(fa, 0.037, 0.46, Vector3(0, 0, 0.3), sleeve, Build.AXIS_Z, false, 16, 0.05)
		Build.cyl(fa, 0.0405, 0.025, Vector3(0, 0, 0.16), stripe, Build.AXIS_Z, false, 16, 0.0425)
		Build.box(fa, Vector3(0.004, 0.02, 0.3), Vector3(s * 0.04, 0.0, 0.3), cuff)        # Naht
		var h := WorkerHand.new(s, skin)
		add_child(h)
		_hands.append(h)
		_forearms.append(fa)
	item = Node3D.new()
	add_child(item)
	_no_shadows(self)
	_apply_hands()


func _no_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_no_shadows(c)


## Neue Haltung. info: bei "tool" {"r": Griffradius}, bei "bar" {"half": halbe Länge, "r": Radius},
## bei "box" {"half": halbe Breite, "top": Oberkante über der Mitte}.
func set_mode(m: String, info := {}) -> void:
	mode = m
	_point_t = 0.0
	_raise = 0.0 if m != "none" else _raise
	_layout(info)
	if m != "none":
		# aus dem Bild unten herein: Hände dort beginnen lassen
		for i in 2:
			_p[i] = _p_t[i] + Vector3(0, -0.35, 0.1)
			_g[i] = _g_t[i]
			_e[i] = _e_t[i]
		for h in _hands:
			h.snap()


func _layout(info: Dictionary) -> void:
	var r := float(info.get("r", 0.012))
	match mode:
		"tool":
			_item_pos = Vector3(0.21, -0.23, -0.42)
			_item_rot = Vector3(0.28, 0.32, 0.1)
			var b := Basis.from_euler(_item_rot)
			_set_hand(0, true, _item_pos, -b.z, Vector3(0.5, -0.4, 0.12), r)   # Handrücken oben rechts
			_set_hand(1, false, Vector3(-0.35, -0.8, -0.1), Vector3(0, 0, -1), Vector3(-0.45, -0.85, 0.3), 0.0)
		"bar":
			_item_pos = Vector3(0, -0.27 + minf(r, 0.04) * 0.5, -0.45)
			_item_rot = Vector3(0, 0.05, -0.03)
			var half := clampf(float(info.get("half", 0.2)) - 0.04, 0.06, 0.17)
			var b := Basis.from_euler(_item_rot)
			# Untergriff: Handflächen oben, die Finger legen sich vorn über die Stange
			_set_hand(0, true, _item_pos + b * Vector3(half, 0, 0), -b.x, Vector3(0.32, -0.5, 0.12), r)
			_set_hand(1, true, _item_pos + b * Vector3(-half, 0, 0), -b.x, Vector3(-0.32, -0.5, 0.12), r)
		"box":
			_item_pos = Vector3(0, -0.4, -0.46)
			_item_rot = Vector3(0.08, 0, 0)
			var half := float(info.get("half", 0.17))
			var top := float(info.get("top", 0.1))
			var b := Basis.from_euler(_item_rot)
			_set_hand(0, true, _item_pos + b * Vector3(half, top - 0.008, 0.02), b.z, Vector3(0.34, -0.55, 0.12), 0.008)
			_set_hand(1, true, _item_pos + b * Vector3(-half, top - 0.008, 0.02), -b.z, Vector3(-0.34, -0.55, 0.12), 0.008)
		"grip":
			_set_hand(0, true, Vector3(0.18, -0.45, -0.5), Vector3(-1, 0, 0), Vector3(0.34, -0.55, 0.12), 0.012)
			_set_hand(1, true, Vector3(-0.18, -0.45, -0.5), Vector3(-1, 0, 0), Vector3(-0.34, -0.55, 0.12), 0.012)
		"point":
			_set_hand(0, true, Vector3(0.16, -0.16, -0.42), Vector3(0.15, -0.35, 1).normalized(), Vector3(0.34, -0.55, 0.1), 0.0)
			_set_hand(1, false, Vector3(-0.35, -0.8, -0.1), Vector3(0, 0, -1), Vector3(-0.45, -0.85, 0.3), 0.0)
		_:
			_set_hand(0, false, Vector3(0.3, -0.75, -0.2), Vector3(0, 0, 1), Vector3(0.4, -0.8, 0.3), 0.0)
			_set_hand(1, false, Vector3(-0.3, -0.75, -0.2), Vector3(0, 0, -1), Vector3(-0.4, -0.8, 0.3), 0.0)
	if mode == "point":
		_hands[0].point()
		_hands[1].grip(0.0)
	else:
		for i in 2:
			_hands[i].grip(_r[i] if _show[i] else 0.0)


func _set_hand(i: int, show: bool, p: Vector3, g: Vector3, e: Vector3, r: float) -> void:
	_show[i] = show
	_p_t[i] = p
	_g_t[i] = g.normalized()
	_e_t[i] = e
	_r[i] = r
	if not show:
		_p_t[i] = Vector3(signf(p.x) * 0.32, -0.85, -0.15)


## Linksklick: mit Gegenstand ein kurzer Stoß nach vorn, mit freien Händen tippt der Zeigefinger.
func poke(hands_free: bool) -> void:
	_jab = 1.0
	if hands_free:
		mode = "point"
		_layout({})
		_point_t = 0.35


## Pro Bild: Bewegung der Figur (Geschwindigkeit, Boden, Sprint) und Drehung des Blicks.
func update(delta: float, hspeed: float, on_floor: bool, sprinting: bool, look_delta: Vector2, landed: float) -> void:
	if mode == "point":
		_point_t -= delta
		if _point_t <= 0.0:
			mode = "none"
			_layout({})
	_raise = move_toward(_raise, 1.0, delta * 4.0)
	_jab = move_toward(_jab, 0.0, delta * 5.0)
	_land = maxf(_land, landed)
	_land = move_toward(_land, 0.0, delta * 3.0)
	_breath += delta
	var moving := clampf(hspeed / 3.2, 0.0, 1.8) if on_floor else 0.0
	_bob_amp = lerpf(_bob_amp, moving, clampf(delta * 8.0, 0.0, 1.0))
	_bob_t = walk_phase
	_sprint = lerpf(_sprint, 1.0 if sprinting and moving > 0.5 else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	# Blick zieht die Arme leicht nach (Trägheit)
	_sway = _sway.lerp(Vector2(clampf(look_delta.x * 1.2, -0.12, 0.12), clampf(look_delta.y * 1.2, -0.1, 0.1)), clampf(delta * 10.0, 0.0, 1.0))
	_sway = _sway.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))

	var ease_raise := 1.0 - pow(1.0 - _raise, 3.0)
	# Im Takt der Schritte: tief beim Fersenaufsatz, seitlich mit dem Gewicht
	var bob := Vector3(cos(_bob_t) * 0.01, -absf(sin(_bob_t)) * 0.014, 0.0) * _bob_amp
	bob.y += sin(_breath * 1.6) * 0.003
	var jab_v := sin(_jab * PI) if _jab > 0.0 else 0.0
	position = bob + Vector3(0, -(1.0 - ease_raise) * 0.3 - _land * 0.04 - _sprint * 0.06, -jab_v * 0.06 + (1.0 - ease_raise) * 0.1)
	rotation = Vector3(-_sway.y - (1.0 - ease_raise) * 0.5 - _sprint * 0.35, _sway.x + _sprint * 0.25, -_sway.x * 0.6 + _sprint * 0.2)

	var k := clampf(delta * 12.0, 0.0, 1.0)
	if mode == "grip" and grip_world.size() == 2:
		_aim_grip()
		k = clampf(delta * 25.0, 0.0, 1.0)
	for i in 2:
		_p[i] = _p[i].lerp(_p_t[i], k)
		# Fast gleiche Richtungen nicht per slerp drehen: die Drehachse wäre dann nicht sauber normiert
		var gd := _g[i].dot(_g_t[i])
		if gd > 0.9995:
			_g[i] = _g[i].lerp(_g_t[i], k).normalized()
		elif gd > -0.99:
			_g[i] = _g[i].slerp(_g_t[i], k).normalized()
		else:
			_g[i] = _g_t[i]
		_e[i] = _e[i].lerp(_e_t[i], k)
	item.position = _item_pos
	item.rotation = _item_rot
	_apply_hands()


## Beide Hände an die Weltpunkte in grip_world legen (rechte Hand an den rechten Punkt, in Blickrichtung gesehen).
func _aim_grip() -> void:
	var inv := global_transform.affine_inverse()
	var a: Vector3 = inv * grip_world[0]
	var b: Vector3 = inv * grip_world[1]
	if a.x < b.x:
		var t := a
		a = b
		b = t
	var bar := (b - a).normalized()                    # Griffachse von rechts nach links
	for i in 2:
		var pt := a if i == 0 else b
		var s := 1.0 if i == 0 else -1.0
		_set_hand(i, true, pt, bar, pt + Vector3(s * 0.12, -0.3, 0.32), 0.012)


func _apply_hands() -> void:
	for i in 2:
		var h := _hands[i]
		var fa := _forearms[i]
		var vis := _show[i] or _p[i].y > -0.7
		h.visible = vis
		fa.visible = vis
		if not vis:
			continue
		var p := _p[i]
		var g := _g[i]
		var e := _e[i]
		var off := WorkerHand.grip_offset(_r[i] if _show[i] else 0.015)
		var w := p + (e - p).normalized() * 0.08
		var b := Basis.IDENTITY
		for it in 3:
			var a := (e - w).normalized()
			var z := a - a.dot(g) * g
			if z.length() < 0.01:
				z = Vector3(0, -1, 0).cross(g)
			z = z.normalized()
			var y := z.cross(g)
			b = Basis(g, y, z)
			w = p - b * off
		h.transform = Transform3D(b, w)
		fa.transform = Transform3D(Basis.looking_at(w - e, b.y), w)
