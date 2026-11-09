class_name CigLook
extends RefCounted
## Aussehen der Zigarette: im Code erzeugte Texturen und Materialien, einmal gebaut und geteilt.
## Filter korkfarben mit hellen Sprenkeln, schmaler Goldrand, weißes Mundstückpapier, Zigarettenpapier
## mit feiner Längsstruktur, verkohlter Rand, graue geschichtete Asche und eine flackernde Glut.
## UV der Zylinder: U läuft um den Umfang, V entlang der Länge.

const FILTER_BASE := Color(0.85, 0.52, 0.17)
const SPECK := Color(0.98, 0.86, 0.62)

static var _mats := {}


static func filter_mat() -> StandardMaterial3D:
	return _mat("filter")


## Querschnitt des Filters am Mundende: gelbliche Faserwatte.
static func filter_end_mat() -> StandardMaterial3D:
	return _mat("filter_end")


static func gold_mat() -> StandardMaterial3D:
	return _mat("gold")


## Weißer Streifen des Mundstückpapiers zwischen Filter und Zigarettenpapier.
static func band_mat() -> StandardMaterial3D:
	return _mat("band")


static func paper_mat() -> StandardMaterial3D:
	return _mat("paper")


## Verkohlter Rand zwischen Papier und Glut.
static func char_mat() -> StandardMaterial3D:
	return _mat("char")


static func ash_mat() -> StandardMaterial3D:
	return _mat("ash")


## Glut: je Zigarette ein eigenes Material, weil die Helligkeit beim Zug steigt.
static func ember_mat(energy := 1.0) -> StandardMaterial3D:
	var m := Build.emissive(Color(1.0, 0.36, 0.06), energy)
	var t := _ember_tex()
	m.albedo_texture = t
	m.emission_texture = t
	m.emission = Color(1.0, 0.45, 0.2)          # färbt die Glut-Textur, sonst strahlt sie weiß
	return m


# ------------------------------------------------------------ Texturen

static func _mat(key: String) -> StandardMaterial3D:
	if not _mats.has(key):
		_mats[key] = _make(key)
	return _mats[key]


static func _make(key: String) -> StandardMaterial3D:
	if key == "gold":
		return Build.mat(Color(0.78, 0.6, 0.25), 0.35, 0.7)
	var m := Build.mat(Color.WHITE, 0.85)
	match key:
		"filter":
			m.roughness = 0.72
			m.albedo_texture = _filter_tex()
		"filter_end":
			m.roughness = 0.95
			m.albedo_texture = _noise_tex(64, 64, Color(0.93, 0.89, 0.78), 0.07, 11)
		"band":
			m.roughness = 0.6
			m.albedo_texture = _noise_tex(64, 16, Color(0.95, 0.95, 0.91), 0.015, 5)
		"paper":
			m.albedo_texture = _paper_tex()
		"char":
			m.roughness = 1.0
			m.albedo_texture = _noise_tex(64, 8, Color(0.16, 0.11, 0.08), 0.35, 23)
		"ash":
			m.roughness = 1.0
			m.albedo_texture = _ash_tex()
	return m


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Gleichmäßige Fläche mit feinem Rauschen.
static func _noise_tex(w: int, h: int, base: Color, amount: float, seed_v: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var v := rng.randf_range(-amount, amount)
			img.set_pixel(x, y, Color(base.r + v, base.g + v, base.b + v))
	return _tex(img)


## Kork-Optik: Orange mit leichten Wolken und vielen kleinen hellen, länglichen Sprenkeln.
static func _filter_tex() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.06
	for y in h:
		for x in w:
			var n := noise.get_noise_2d(x, y) * 0.06 + rng.randf_range(-0.025, 0.025)
			img.set_pixel(x, y, Color(FILTER_BASE.r + n, FILTER_BASE.g + n * 0.9, FILTER_BASE.b + n * 0.5))
	for i in 140:
		var cx := rng.randf() * w
		var cy := rng.randf() * h
		var rx := rng.randf_range(0.8, 2.2)
		var ry := rx * rng.randf_range(0.5, 1.4)
		var a := rng.randf_range(0.55, 0.95)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var d := pow(dx / rx, 2.0) + pow(dy / ry, 2.0)
				if d > 1.0:
					continue
				var px := posmod(int(cx) + dx, w)       # nahtlos um den Umfang
				var py := clampi(int(cy) + dy, 0, h - 1)
				img.set_pixel(px, py, img.get_pixel(px, py).lerp(SPECK, a * (1.0 - d * 0.5)))
	return _tex(img)


## Zigarettenpapier: Weiß mit feinen Längsrillen (je Spalte leicht andere Helligkeit) und Faserrauschen.
static func _paper_tex() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var w := 256
	var h := 64
	var col := PackedFloat32Array()
	col.resize(w)
	for x in w:
		col[x] = rng.randf_range(-0.07, 0.025)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			# Nachbarspalten etwas mitteln, damit die Rillen weich wirken
			var c := (col[x] * 2.0 + col[(x + 1) % w] + col[(x + w - 1) % w]) * 0.25
			var v := 0.93 + c + rng.randf_range(-0.012, 0.012)
			img.set_pixel(x, y, Color(v, v, v * 0.975))
	# Klebenaht: ein etwas dunklerer, schmaler Streifen
	for y in h:
		for x in range(40, 43):
			img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.06))
	return _tex(img)


## Asche: Grau mit hellen und dunklen Lagen quer zur Länge und Körnung.
static func _ash_tex() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 17
	noise.frequency = 0.12
	for y in h:
		var band := sin(y * 1.3) * 0.05 + sin(y * 0.47) * 0.04
		for x in w:
			var v := 0.5 + band + noise.get_noise_2d(x, y * 3.0) * 0.1 + rng.randf_range(-0.06, 0.06)
			img.set_pixel(x, y, Color(v, v * 0.99, v * 0.96))
	return _tex(img)


## Glut: helles Orange mit gelben Punkten und dunkelroten Stellen.
static func _ember_tex() -> ImageTexture:
	if _mats.has("ember_tex"):
		return _mats["ember_tex"]
	var w := 32
	var h := 8
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 29
	noise.frequency = 0.25
	for y in h:
		for x in w:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var c := Color(0.45, 0.06, 0.02).lerp(Color(1.0, 0.42, 0.08), smoothstep(0.2, 0.6, n))
			c = c.lerp(Color(1.0, 0.8, 0.35), smoothstep(0.7, 0.95, n))
			img.set_pixel(x, y, c)
	var t := _tex(img)
	_mats["ember_tex"] = t
	return t
