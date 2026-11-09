class_name Surroundings
extends RefCounted
## Hintergrund der Welt: Wiese, Straße, Hecken, Nachbarhallen, Laternen und Außenhaut der Gebäude. Alles liegt
## außerhalb der Flächen, die sich als Kacheln kaufen lassen, und hat keine Kollision.


static func build(root: Node3D) -> void:
	var n := Node3D.new()
	n.name = "Umgebung"
	root.add_child(n)
	_ground(n)
	_road(n)
	_shell(n)
	_neighbours(n)
	_hedges(n)
	_lamps(n)
	_cars(n)
	_outdoor(n)
	# Bäume nach _outdoor: Sie bekommen die Außenebene, werfen aber Schatten (Platzhalter bis zum Blender-Modell)
	var trees := Node3D.new()
	trees.name = "Bäume"
	n.add_child(trees)
	_trees(trees)
	for g in trees.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = Site.OUTDOOR_LAYER


## Nur die Sonne trifft die Außenebene.
static func _outdoor(n: Node) -> void:
	if n is GeometryInstance3D:
		n.layers = Site.OUTDOOR_LAYER
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_outdoor(c)


static func _ground(n: Node3D) -> void:
	var grass := Build.mat(Color(0.32, 0.45, 0.22), 0.95)
	Build.box(n, Vector3(600.0, 0.1, 600.0), Vector3(0, -0.16, 0), grass)
	# Hellere und dunklere Flecken, damit die Wiese nicht wie eine Fläche wirkt
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var light := Build.mat(Color(0.38, 0.5, 0.26), 0.95)
	var dark := Build.mat(Color(0.27, 0.39, 0.19), 0.95)
	for i in 40:
		var at := Vector3(rng.randf_range(-120.0, 120.0), -0.105, rng.randf_range(-120.0, 120.0))
		if at.x > -42.0 and at.x < 42.0 and at.z > -46.0 and at.z < 20.0:
			continue
		Build.box(n, Vector3(rng.randf_range(6.0, 22.0), 0.004 + i * 0.0002, rng.randf_range(6.0, 22.0)), at, light if i % 2 == 0 else dark)


static func _road(n: Node3D) -> void:
	var asphalt := HallTex.asphalt(Color(0.36, 0.36, 0.37), Vector2(25.0, 29.0))
	var white := Build.mat(Color(0.85, 0.85, 0.82), 0.85)
	white.metallic_specular = 0.2
	var kerb := HallTex.concrete()
	Build.box(n, Vector3(400.0, 0.04, 8.0), Vector3(0, -0.09, 27.0), asphalt)
	for z in [22.8, 31.2]:
		Build.box(n, Vector3(400.0, 0.1, 0.4), Vector3(0, -0.06, z), kerb)
	var x := -190.0
	while x < 190.0:
		Build.box(n, Vector3(3.0, 0.006, 0.15), Vector3(x, -0.067, 27.0), white)
		x += 7.0
	# Zufahrt vom Hof zur Straße
	Build.box(n, Vector3(7.0, 0.04, 11.0), Vector3(23.0, -0.09, 17.5), asphalt)


## Außenhaut und Dach der Werkstatt mit Wellblech-Rippen, dazu Dachränder.
static func _shell(n: Node3D) -> void:
	var skin := Build.mat(Color(0.74, 0.77, 0.78), 0.8, 0.1)
	var rib := Build.mat(Color(0.66, 0.69, 0.7), 0.7, 0.2)
	var roof := Build.mat(Color(0.33, 0.35, 0.37), 0.9)
	var edge := Build.mat(Color(0.2, 0.28, 0.36), 0.6, 0.3)
	var w := Workshop.W
	var d := Workshop.D
	var h := Workshop.H
	Build.box(n, Vector3(w + 0.8, 0.12, d + 0.8), Vector3(0, h + 0.38, 0), roof)
	Build.box(n, Vector3(w + 0.9, 0.3, 0.06), Vector3(0, h + 0.3, -d * 0.5 - 0.45), edge)
	Build.box(n, Vector3(w + 0.9, 0.3, 0.06), Vector3(0, h + 0.3, d * 0.5 + 0.45), edge)
	Build.box(n, Vector3(0.06, 0.3, d + 0.9), Vector3(w * 0.5 + 0.45, h + 0.3, 0), edge)
	Build.box(n, Vector3(0.06, 0.3, d + 0.9), Vector3(-w * 0.5 - 0.45, h + 0.3, 0), edge)
	# Nord- und Südseite, die Südseite hat den Büroanbau davor
	Build.box(n, Vector3(w, h, 0.02), Vector3(0, h * 0.5, -d * 0.5 - 0.31), skin)
	# Dort, wo das Büro anschließt, gibt es unten keine Außenhaut: Sonst stünde sie im Raum und vor der Tür
	var ax0 := Workshop.QM_X.x - 0.3     # Qualitätsmanagement und Büro stehen nebeneinander
	var ax1 := Workshop.OFFICE_X.y + 0.3
	var ay := Workshop.OFFICE_H + 0.25
	Build.box(n, Vector3(ax0 + w * 0.5, h, 0.02), Vector3((ax0 - w * 0.5) * 0.5, h * 0.5, d * 0.5 + 0.31), skin)
	Build.box(n, Vector3(w * 0.5 - ax1, h, 0.02), Vector3((ax1 + w * 0.5) * 0.5, h * 0.5, d * 0.5 + 0.31), skin)
	Build.box(n, Vector3(ax1 - ax0, h - ay, 0.02), Vector3((ax0 + ax1) * 0.5, (h + ay) * 0.5, d * 0.5 + 0.31), skin)
	var x := -w * 0.5 + 0.25
	while x < w * 0.5:
		var y0 := ay if x > ax0 and x < ax1 else 0.0
		Build.box(n, Vector3(0.05, h - y0, 0.03), Vector3(x, (h + y0) * 0.5, d * 0.5 + 0.33), rib)
		x += 1.0
	# Rippen an der Hofseite, die Toröffnung bleibt frei
	var z := -d * 0.5 + 0.25
	var door0 := Workshop.DOOR_Z - RollDoor.WIDTH * 0.5 - 0.5
	var door1 := Workshop.DOOR_Z + RollDoor.WIDTH * 0.5 + 0.9
	while z < d * 0.5:
		var hh := RollDoor.HEIGHT + 0.5 if z > door0 and z < door1 else 0.0
		Build.box(n, Vector3(0.03, h - hh, 0.05), Vector3(w * 0.5 + 0.33, (h + hh) * 0.5, z), rib)
		z += 1.0


## Nachbarhallen hinter der Straße und im Norden.
static func _neighbours(n: Node3D) -> void:
	var list := [
		[Vector3(-30.0, 0, 46.0), Vector3(28.0, 8.0, 14.0), Color(0.62, 0.64, 0.66)],
		[Vector3(8.0, 0, 50.0), Vector3(22.0, 6.5, 16.0), Color(0.7, 0.66, 0.58)],
		[Vector3(46.0, 0, 44.0), Vector3(30.0, 9.0, 12.0), Color(0.56, 0.6, 0.66)],
		[Vector3(70.0, 0, -18.0), Vector3(14.0, 7.0, 34.0), Color(0.66, 0.62, 0.58)],
		[Vector3(-68.0, 0, -6.0), Vector3(16.0, 7.5, 30.0), Color(0.6, 0.63, 0.6)],
		[Vector3(-8.0, 0, -70.0), Vector3(44.0, 10.0, 16.0), Color(0.64, 0.64, 0.68)],
		[Vector3(44.0, 0, -72.0), Vector3(26.0, 8.0, 14.0), Color(0.7, 0.68, 0.62)],
	]
	var roof := Build.mat(Color(0.28, 0.29, 0.31), 0.9)
	var glass := Build.mat(Color(0.32, 0.42, 0.5), 0.2, 0.3)
	var door := Build.mat(Color(0.45, 0.47, 0.5), 0.6, 0.2)
	for b in list:
		var at: Vector3 = b[0]
		var s: Vector3 = b[1]
		Build.box(n, s, at + Vector3(0, s.y * 0.5, 0), Build.mat(b[2], 0.85))
		Build.box(n, Vector3(s.x + 0.6, 0.25, s.z + 0.6), at + Vector3(0, s.y + 0.12, 0), roof)
		# Fensterband auf der Seite zur Werkstatt, dazu ein Tor
		var facing := -signf(at.z) if absf(at.z) > absf(at.x) else -signf(at.x)
		if absf(at.z) > absf(at.x):
			Build.box(n, Vector3(s.x * 0.8, 1.2, 0.06), at + Vector3(0, s.y * 0.7, facing * s.z * 0.5), glass)
			Build.box(n, Vector3(4.5, 4.0, 0.06), at + Vector3(s.x * 0.25, 2.0, facing * s.z * 0.5), door)
		else:
			Build.box(n, Vector3(0.06, 1.2, s.z * 0.8), at + Vector3(facing * s.x * 0.5, s.y * 0.7, 0), glass)
			Build.box(n, Vector3(0.06, 4.0, 4.5), at + Vector3(facing * s.x * 0.5, 2.0, s.z * 0.25), door)


## Hecken hinter dem Hofzaun. Bäume kommen später als eigenes Modell aus Blender.
## Platzhalter-Bäume, bis die Modelle aus Blender kommen: Laubbäume, Birken und Nadelbäume, verstreut in der
## Landschaft und als Reihe zwischen Hecke und Straße. Kaufbare Flächen, Straße und Nachbarhallen bleiben frei.
static func _trees(n: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var spots: Array[Vector2] = []
	var guard := 0
	while spots.size() < 46 and guard < 600:
		guard += 1
		var x := rng.randf_range(-95.0, 95.0)
		var z := rng.randf_range(-95.0, 95.0)
		if x > -42.0 and x < 40.0 and z > -46.0 and z < 22.0:
			continue
		if z > 21.0 and z < 33.0:
			continue
		if z > 34.0 and z < 62.0 or z < -60.0 or absf(x) > 58.0 and absf(z) < 40.0:
			continue
		spots.append(Vector2(x, z))
	# Straßenbäume vor der Hecke, die Zufahrt zum Hof bleibt frei
	for x in [-38.0, -30.0, -22.0, -14.0, -6.0, 2.0, 10.0, 34.0, 42.0]:
		spots.append(Vector2(x + rng.randf_range(-0.8, 0.8), 19.6))
	for i in spots.size():
		var at := Vector3(spots[i].x, 0, spots[i].y)
		var kind := rng.randf()
		if spots[i].y > 19.0 and spots[i].y < 20.0:
			_leaf_tree(n, at, rng, 0.85)
		elif kind < 0.55:
			_leaf_tree(n, at, rng, 1.0)
		elif kind < 0.75:
			_birch(n, at, rng)
		else:
			_conifer(n, at, rng)


## Laubbaum: leicht schräger, nach oben dünner Stamm mit zwei, drei Ästen und einer Krone aus mehreren
## gestauchten, gegeneinander versetzten Laubballen in zwei Grüntönen.
static func _leaf_tree(n: Node3D, at: Vector3, rng: RandomNumberGenerator, size: float) -> void:
	var h := rng.randf_range(3.2, 5.0) * size
	var r := rng.randf_range(2.0, 3.0) * size
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
	var trunk := Build.cyl(n, 0.24 * size, h + r * 0.5, at + Vector3(0, (h + r * 0.5) * 0.5, 0), HallTex.bark(), Build.AXIS_Y, false, 10, 0.13 * size)
	trunk.rotation = lean
	var top := at + Vector3(lean.z, 0, -lean.x) * h + Vector3(0, h, 0)
	for b in rng.randi_range(2, 3):
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var branch := Build.cyl(n, 0.08 * size, r * 0.9, top + dir * r * 0.3 + Vector3(0, r * 0.15, 0), HallTex.bark(), Build.AXIS_Y, false, 6, 0.04 * size)
		branch.rotation = Vector3(dir.z * 0.9, 0, -dir.x * 0.9)
	var greens := [Color(0.2, 0.36, 0.14), Color(0.26, 0.42, 0.16), Color(0.18, 0.31, 0.15), Color(0.3, 0.44, 0.18)]
	var base: Color = greens[rng.randi_range(0, greens.size() - 1)]
	var lobes := rng.randi_range(5, 7)
	var crown := top + Vector3(0, r * 0.55, 0)
	Build.sphere(n, r * 0.85, crown, HallTex.foliage(base)).scale = Vector3(1.0, 0.85, 1.0)
	for i in lobes:
		var a := TAU * i / lobes + rng.randf_range(-0.3, 0.3)
		var out := r * rng.randf_range(0.45, 0.7)
		var up := rng.randf_range(-0.35, 0.45) * r
		var lr := r * rng.randf_range(0.5, 0.7)
		var m := HallTex.foliage(base.lightened(0.06) if i % 2 == 0 else base.darkened(0.08))
		var ball := Build.sphere(n, lr, crown + Vector3(cos(a) * out, up, sin(a) * out), m)
		ball.scale = Vector3(1.0, rng.randf_range(0.7, 0.9), 1.0)
	# Obenauf ein kleinerer Ballen, damit die Krone nicht flach endet
	Build.sphere(n, r * 0.5, crown + Vector3(rng.randf_range(-0.3, 0.3), r * 0.65, rng.randf_range(-0.3, 0.3)), HallTex.foliage(base.lightened(0.1)))


## Birke: schlanker weißer Stamm, schmale hohe Krone aus lockeren, hellgrünen Ballen.
static func _birch(n: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(6.0, 8.5)
	Build.cyl(n, 0.14, h, at + Vector3(0, h * 0.5, 0), HallTex.bark(true), Build.AXIS_Y, false, 10, 0.06)
	var leaf := HallTex.foliage(Color(0.36, 0.5, 0.2))
	var count := 6
	for i in count:
		var t := float(i) / (count - 1)
		var a := rng.randf() * TAU
		var r := lerpf(1.3, 0.7, t)
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 0.5)
		Build.sphere(n, r, at + off + Vector3(0, lerpf(h * 0.45, h - 0.2, t), 0), leaf).scale = Vector3(1.0, 1.3, 1.0)


## Nadelbaum: kurzer Stamm, vier bis sechs übereinander gestaffelte Kegel in dunklem Grün, nach oben schmaler.
static func _conifer(n: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(7.0, 11.0)
	var w := h * rng.randf_range(0.2, 0.26)
	Build.cyl(n, 0.2, h * 0.3, at + Vector3(0, h * 0.15, 0), HallTex.bark(), Build.AXIS_Y, false, 8, 0.12)
	var needles := HallTex.foliage(Color(0.11, 0.24, 0.14))
	var tiers := rng.randi_range(4, 6)
	for i in tiers:
		var t := float(i) / tiers
		var tr := w * lerpf(1.0, 0.3, t)
		var th := h * 0.32
		var y := h * 0.18 + t * h * 0.68
		var cone := Build.cyl(n, tr, th, at + Vector3(0, y + th * 0.5, 0), needles, Build.AXIS_Y, false, 14, 0.0)
		cone.rotation.y = rng.randf() * TAU


static func _hedges(n: Node3D) -> void:
	# Hecke hinter dem Hofzaun
	var hedge := Build.mat(Color(0.2, 0.36, 0.17), 0.95)
	Build.box(n, Vector3(1.2, 2.2, 24.0), Vector3(36.0, 1.1, 2.0), hedge)
	Build.box(n, Vector3(22.0, 1.8, 1.0), Vector3(23.0 - 14.0, 0.9, 16.0), hedge)


static func _lamps(n: Node3D) -> void:
	var pole := Build.mat(Color(0.3, 0.32, 0.34), 0.5, 0.5)
	var lamp := Build.emissive(Color(1.0, 0.86, 0.62), 0.8)
	var x := -80.0
	while x <= 80.0:
		Build.cyl(n, 0.08, 7.0, Vector3(x, 3.5, 21.8), pole, Build.AXIS_Y, false, 8)
		Build.box(n, Vector3(0.08, 0.08, 1.4), Vector3(x, 7.0, 22.4), pole)
		var head := Build.box(n, Vector3(0.25, 0.08, 0.5), Vector3(x, 6.94, 23.0), lamp)
		# Nachts an (DayCycle): warmweißer Lichtkegel auf die Straße, nur die nahen Laternen werfen echtes Licht
		head.add_to_group("night_glow")
		head.set_meta("energy", 6.0)
		if absf(x) < 60.0:
			night_spot(n, Vector3(x, 6.85, 23.0), Vector3(x, 0.0, 25.0), Color(1.0, 0.82, 0.58), 3.5, 16.0, 62.0)
		x += 32.0


## Scheinwerfer für die Nacht (Gruppe "night_light", DayCycle schaltet ihn), trifft nur die Außenebene.
static func night_spot(parent: Node3D, at: Vector3, target: Vector3, c: Color, energy: float, reach: float, angle: float) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = c
	l.light_energy = 0.0
	l.spot_range = reach
	l.spot_angle = angle * 0.5
	l.spot_angle_attenuation = 0.8
	l.light_cull_mask = Site.OUTDOOR_LAYER
	l.set_meta("energy", energy)
	l.add_to_group("night_light")
	parent.add_child(l)
	l.look_at_from_position(at, target, Vector3.UP if absf((target - at).normalized().y) < 0.99 else Vector3.FORWARD)
	return l


static func _cars(n: Node3D) -> void:
	var cars := [[Vector3(-9.0, 0, 25.0), Color(0.55, 0.12, 0.1)], [Vector3(30.0, 0, 29.0), Color(0.15, 0.25, 0.45)]]
	var dark := Build.mat(Color(0.08, 0.08, 0.09), 0.5)
	var glass := Build.mat(Color(0.2, 0.28, 0.33), 0.15, 0.4)
	for c in cars:
		var at: Vector3 = c[0]
		var body := Build.mat(c[1], 0.35, 0.3)
		Build.box(n, Vector3(4.2, 0.6, 1.8), at + Vector3(0, 0.55, 0), body)
		Build.box(n, Vector3(2.2, 0.5, 1.6), at + Vector3(-0.2, 1.08, 0), glass)
		for sx in [-1.3, 1.3]:
			for sz in [-0.85, 0.85]:
				Build.cyl(n, 0.32, 0.2, at + Vector3(sx, 0.22, sz), dark, Build.AXIS_Z, false, 14)
