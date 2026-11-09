class_name HallTex
extends RefCounted
## Prozedurale Oberflächen der Halle: Sandwichpaneele für die Wände, Betonsockel, Trapezblech an der
## Decke und ein beschichteter Hallenboden. Die Texturen entstehen einmal beim Start aus Rauschen und
## liegen über Weltkoordinaten (Triplanar) auf den Quadern, damit sie auf jeder Wandlänge gleich groß sind.

const SIZE := 256

static var _cache := {}


## Weiße Sandwichpaneele: liegende Paneele mit 1 m Höhe, flache Sicken und eine Fuge je Paneel.
static func wall() -> StandardMaterial3D:
	if not _cache.has("wall"):
		var noise := _noise(7, 0.02)
		var fine := _noise(11, 0.25)
		var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var height := PackedFloat32Array()
		height.resize(SIZE * SIZE)
		for y in SIZE:
			var v := float(y) / SIZE
			# Fuge oben, Sicken alle 12,5 cm
			var groove := smoothstep(0.012, 0.0, minf(v, 1.0 - v))
			var rib := 0.5 + 0.5 * cos(v * TAU * 8.0)
			for x in SIZE:
				var n := _tile(noise, x, y) * 0.5 + 0.5
				var f := _tile(fine, x, y) * 0.5 + 0.5
				var h := rib * 0.25 - groove
				height[y * SIZE + x] = h
				var c := Color(0.87, 0.88, 0.87).lerp(Color(0.78, 0.8, 0.8), n * 0.6)
				c = c.darkened(f * 0.03 + groove * 0.45 - rib * 0.02)
				albedo.set_pixel(x, y, c)
		_cache["wall"] = _material(albedo, height, 2.0, 0.75, 0.0, Vector3(1, 1, 1))
	return _cache["wall"]


## Sichtbeton für den Sockel: Wolken, Poren und Schalungsfugen alle 1,2 m.
static func concrete() -> StandardMaterial3D:
	if not _cache.has("concrete"):
		var noise := _noise(3, 0.012)
		var pores := _noise(5, 0.4)
		var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var height := PackedFloat32Array()
		height.resize(SIZE * SIZE)
		for y in SIZE:
			for x in SIZE:
				var n := _tile(noise, x, y) * 0.5 + 0.5
				var p := _tile(pores, x, y)
				var pore := 1.0 if p > 0.62 else 0.0
				var u := float(x) / SIZE
				var seam := smoothstep(0.006, 0.0, minf(u, 1.0 - u))
				height[y * SIZE + x] = n * 0.3 - pore * 0.5 - seam * 0.6
				var c := Color(0.5, 0.5, 0.49).lerp(Color(0.62, 0.62, 0.6), n)
				c = c.darkened(pore * 0.25 + seam * 0.35)
				albedo.set_pixel(x, y, c)
		_cache["concrete"] = _material(albedo, height, 3.0, 0.92, 0.0, Vector3(1.0 / 1.2, 1.0 / 1.2, 1.0 / 1.2))
	return _cache["concrete"]


## Trapezblech unter dem Dach, Rippen alle 25 cm in Z-Richtung.
static func ceiling() -> StandardMaterial3D:
	if not _cache.has("ceiling"):
		var noise := _noise(9, 0.03)
		var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var height := PackedFloat32Array()
		height.resize(SIZE * SIZE)
		for y in SIZE:
			var v := fposmod(float(y) / SIZE * 4.0, 1.0)
			var rib := smoothstep(0.25, 0.35, v) * smoothstep(0.75, 0.65, v)
			for x in SIZE:
				var n := _tile(noise, x, y) * 0.5 + 0.5
				height[y * SIZE + x] = rib
				albedo.set_pixel(x, y, Color(0.5, 0.52, 0.54).lerp(Color(0.6, 0.62, 0.64), n * 0.5).darkened(0.12 * (1.0 - rib)))
		_cache["ceiling"] = _material(albedo, height, 6.0, 0.55, 0.6, Vector3(1, 1, 1))
	return _cache["ceiling"]


## Hallenboden: grüngraue Epoxidbeschichtung mit Einstreuung, Wolken und abgelaufenen Stellen.
static func floor_mat(tiles: Vector2) -> StandardMaterial3D:
	var noise := _noise(13, 0.008)
	var speck := _noise(17, 0.9)
	var wear := _noise(19, 0.02)
	var size := SIZE
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rough := Image.create(size, size, false, Image.FORMAT_RGB8)
	var height := PackedFloat32Array()
	height.resize(size * size)
	for y in size:
		for x in size:
			var n := _tile(noise, x, y) * 0.5 + 0.5
			var s := _tile(speck, x, y)
			var w := clampf((_tile(wear, x, y) - 0.15) * 3.0, 0.0, 1.0)
			var c := Color(0.37, 0.41, 0.40).lerp(Color(0.46, 0.50, 0.49), n)
			if s > 0.55:
				c = c.lightened(0.12)
			elif s < -0.6:
				c = c.darkened(0.15)
			c = c.lerp(Color(0.52, 0.53, 0.5), w * 0.35)
			albedo.set_pixel(x, y, c)
			var r := 0.35 + w * 0.35 + n * 0.08
			rough.set_pixel(x, y, Color(r, r, r))
			height[y * size + x] = n * 0.4 + (0.15 if s > 0.55 else 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(_mip(albedo))
	m.roughness_texture = ImageTexture.create_from_image(_mip(rough))
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(_normal(height, size, 1.5))
	m.normal_scale = 0.5
	m.uv1_scale = Vector3(tiles.x, tiles.y, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Hallenboden für Kacheln aus Quadern: gleiche Beschichtung wie die Grundhalle (3 m je Kachelung), aber über
## Weltkoordinaten gelegt, damit Box-UVs sie nicht zerstückeln und die Kacheln nahtlos aneinanderpassen.
static func floor_world() -> StandardMaterial3D:
	if not _cache.has("floor_world"):
		var m := floor_mat(Vector2.ONE)
		m.uv1_scale = Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_triplanar_sharpness = 8.0
		_cache["floor_world"] = m
	return _cache["floor_world"]


## Geglätteter Industrieestrich fürs Lager: hellgrau, Wolken, Reifenspuren und Dehnfugen alle 3,8 m.
static func screed() -> StandardMaterial3D:
	if not _cache.has("screed"):
		var noise := _noise(23, 0.01)
		var fine := _noise(29, 0.5)
		var tyre := _noise(31, 0.04)
		var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var height := PackedFloat32Array()
		height.resize(SIZE * SIZE)
		for y in SIZE:
			for x in SIZE:
				var n := _tile(noise, x, y) * 0.5 + 0.5
				var f := _tile(fine, x, y)
				var t := clampf((_tile(tyre, x, y) - 0.3) * 4.0, 0.0, 1.0)
				var u := float(x) / SIZE
				var v := float(y) / SIZE
				var joint := smoothstep(0.004, 0.0, minf(minf(u, 1.0 - u), minf(v, 1.0 - v)))
				var c := Color(0.5, 0.5, 0.49).lerp(Color(0.6, 0.6, 0.58), n)
				c = c.darkened(f * 0.025 + t * 0.08 + joint * 0.45)
				albedo.set_pixel(x, y, c)
				height[y * SIZE + x] = n * 0.2 - joint
		var m := _material(albedo, height, 2.0, 0.6, 0.0, Vector3(1.0 / 3.8, 1.0 / 3.8, 1.0 / 3.8))
		m.metallic_specular = 0.35
		_cache["screed"] = m
	return _cache["screed"]


## Asphalt als Shader, damit sich nichts sichtbar wiederholt: Das Splittmuster (2 m) wird zweimal gelesen, das
## zweite Mal gedreht und anders skaliert, und großflächiges Rauschen (37 m und 113 m) blendet zwischen beiden und
## hellt oder dunkelt ab. Dazu Risse, Flickstellen und, wenn lanes gesetzt ist (Z-Mitten der Fahrstreifen),
## dunkle, glattere Fahrspuren. Sehr rau und mit wenig Glanz, damit die Sonne keine Spiegelfläche malt.
static func asphalt(tint := Color(0.25, 0.25, 0.26), lanes := Vector2.ZERO, cracks := 1.0) -> Material:
	var key := "asphalt_%s_%s_%.2f" % [tint.to_html(), lanes, cracks]
	if not _cache.has(key):
		if not _cache.has("asphalt_tex"):
			_cache["asphalt_tex"] = _asphalt_textures()
		var tex: Array = _cache["asphalt_tex"]
		var sh := Shader.new()
		sh.code = ASPHALT_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("detail", tex[0])
		m.set_shader_parameter("detail_n", tex[1])
		m.set_shader_parameter("macro", tex[2])
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("lanes", lanes)
		m.set_shader_parameter("cracks", cracks)
		_cache[key] = m
	return _cache[key]


## Splitt (Albedo und Normalen, grau um 0,5) und ein großes Rauschbild: R Flecken, G Mischmaske, B Rissfeld,
## A Flickstellen. Alles kachelbar.
static func _asphalt_textures() -> Array:
	var grit := _noise(41, 0.9)
	var fines := _noise(37, 0.05)
	var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var g := _tile(grit, x, y)
			var f := _tile(fines, x, y) * 0.5 + 0.5
			var v := 0.45 + f * 0.08
			if g > 0.4:
				v += 0.3 * (g - 0.4) * 1.7
			elif g < -0.45:
				v -= 0.1
			albedo.set_pixel(x, y, Color(v, v, v * 1.01))
			height[y * SIZE + x] = g * 0.6 + f * 0.15
	var blot := _noise(83, 0.012)
	var mask := _noise(89, 0.02)
	var crack := _noise(97, 0.018)
	crack.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var patch := _noise(101, 0.01)
	var macro := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			macro.set_pixel(x, y, Color(_tile(blot, x, y) * 0.5 + 0.5, _tile(mask, x, y) * 0.5 + 0.5,
					_tile(crack, x, y) * 0.5 + 0.5, 1.0 if _tile(patch, x, y) > 0.42 else 0.0))
	return [ImageTexture.create_from_image(_mip(albedo)), ImageTexture.create_from_image(_normal(height, SIZE, 2.5)),
			ImageTexture.create_from_image(_mip(macro))]


const ASPHALT_SHADER := """
shader_type spatial;
uniform sampler2D detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.25, 0.25, 0.26, 1.0);
uniform vec2 lanes = vec2(0.0);
uniform float cracks = 1.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	vec2 uv1 = p * 0.5;
	vec2 uv2 = rot * p * 0.31 + vec2(0.37, 0.11);
	vec4 m = texture(macro, p / 37.0);
	vec4 m2 = texture(macro, rot * p / 113.0 + vec2(0.5));
	float w = smoothstep(0.3, 0.7, m.g);
	vec3 d = mix(texture(detail, uv1).rgb, texture(detail, uv2).rgb, w);
	vec3 n = mix(texture(detail_n, uv1).rgb, texture(detail_n, uv2).rgb, w);
	float shade = 1.0 + (m.r - 0.5) * 0.35 + (m2.r - 0.5) * 0.3;
	// Flickstellen: etwas dunkler und feiner, mit klarer Kante
	float patch = texture(macro, p / 23.0 + vec2(0.2, 0.7)).a;
	shade *= 1.0 - patch * 0.12;
	// Haarrisse aus dem Rissfeld, nur in Teilen der Fläche
	float c = 1.0 - smoothstep(0.0, 0.004, abs(texture(macro, p / 6.0).b - 0.62));
	c *= smoothstep(0.62, 0.75, m2.g) * (1.0 - patch) * cracks;
	// Fahrspuren: je Streifen zwei Reifenbahnen, dunkler und etwas glatter
	float track = 0.0;
	if (lanes.x != lanes.y) {
		for (int i = 0; i < 2; i++) {
			float lz = i == 0 ? lanes.x : lanes.y;
			track += 1.0 - smoothstep(0.15, 0.45, abs(abs(p.y - lz) - 0.9));
		}
		track *= 0.7 + 0.3 * m.r;
	}
	shade *= 1.0 - track * 0.2;
	// Splitt-Textur ist sRGB, ihr Mittel (0,5) liegt linear bei 0,214: auf die Grundfarbe normieren
	vec3 grit = d / 0.214;
	ALBEDO = tint.rgb * grit * shade * (1.0 - c * 0.45);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = clamp(0.95 - track * 0.12, 0.0, 1.0);
	SPECULAR = 0.12;
	METALLIC = 0.0;
}
"""


## Pulverbeschichteter Stahl (Zaunpfosten, Container): feine Orangenhaut, Schmutzwolken unten, einzelne Kratzer.
static func powder(c: Color, dirt := 0.15) -> StandardMaterial3D:
	var key := "powder_%s_%.2f" % [c.to_html(), dirt]
	if not _cache.has(key):
		var noise := _noise(47, 0.02)
		var fine := _noise(53, 0.6)
		var scratch := _noise(59, 0.08)
		var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var height := PackedFloat32Array()
		height.resize(SIZE * SIZE)
		for y in SIZE:
			for x in SIZE:
				var n := _tile(noise, x, y) * 0.5 + 0.5
				var f := _tile(fine, x, y)
				var s := absf(_tile(scratch, x, y))
				var col := c.darkened(n * dirt + f * 0.03)
				if s < 0.012:
					col = col.lerp(Color(0.55, 0.56, 0.57), 0.6)
				albedo.set_pixel(x, y, col)
				height[y * SIZE + x] = f * 0.15
		_cache[key] = _material(albedo, height, 1.5, 0.55, 0.0, Vector3(1, 1, 1))
	return _cache[key]


## Stabgitter-Zaunfeld (Doppelstab 6/5/6): senkrechte Stäbe alle 5 cm, waagerechte Doppelstäbe alle 20 cm.
## Die Lücken sind durchsichtig; in der Ferne mischen die Mipmaps das Gitter zu einem leichten Schleier.
static func fence_mesh(c: Color) -> StandardMaterial3D:
	var key := "fence_%s" % c.to_html()
	if not _cache.has(key):
		var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var noise := _noise(61, 0.05)
		for y in SIZE:
			var v := fposmod(float(y) / SIZE * 5.0, 1.0)
			var horiz := v < 0.03 or (v > 0.06 and v < 0.09)
			for x in SIZE:
				var u := fposmod(float(x) / SIZE * 20.0, 1.0)
				var vert := u < 0.11
				if vert or horiz:
					var col := c.darkened((_tile(noise, x, y) * 0.5 + 0.5) * 0.15 + (0.08 if horiz else 0.0))
					albedo.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))
				else:
					albedo.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(_mip(albedo))
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.6
		m.metallic = 0.2
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_triplanar_sharpness = 16.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_cache[key] = m
	return _cache[key]


## Laub für Platzhalter-Bäume: Blattbüschel als helle und dunkle Flecken mit kräftiger Normalenkarte, damit
## eine Kugelkrone nach vielen Blättern aussieht statt nach glatter Fläche. Liegt über Weltkoordinaten.
static func foliage(c: Color) -> StandardMaterial3D:
	var key := "foliage_%s" % c.to_html()
	if not _cache.has(key):
		var clumps := _noise(67, 0.08)
		var leaves := _noise(71, 0.45)
		var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var height := PackedFloat32Array()
		height.resize(SIZE * SIZE)
		for y in SIZE:
			for x in SIZE:
				var k := _tile(clumps, x, y)
				var l := _tile(leaves, x, y)
				var col := c.lerp(c.lightened(0.25), clampf(k * 0.8 + 0.4, 0.0, 1.0) * 0.6)
				col = col.darkened(clampf(-l, 0.0, 1.0) * 0.45)
				if l > 0.45:
					col = col.lightened(0.12)
				albedo.set_pixel(x, y, col)
				height[y * SIZE + x] = k * 0.6 + l * 0.8
		var m := _material(albedo, height, 5.0, 0.85, 0.0, Vector3(0.6, 0.6, 0.6))
		m.metallic_specular = 0.2
		m.uv1_triplanar_sharpness = 2.0
		_cache[key] = m
	return _cache[key]


## Rinde: senkrechte Furchen, für Birken helle Rinde mit dunklen Querstreifen.
static func bark(birch := false) -> StandardMaterial3D:
	var key := "bark_birch" if birch else "bark"
	if not _cache.has(key):
		var furrow := _noise(73, 0.05)
		var spots := _noise(79, 0.12)
		var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var height := PackedFloat32Array()
		height.resize(SIZE * SIZE)
		for y in SIZE:
			for x in SIZE:
				# Furchen laufen senkrecht: das Rauschen wird in Y stark gestreckt
				var f := furrow.get_noise_2d(float(x) * 4.0, float(y) * 0.4)
				var s := _tile(spots, x, y)
				var col: Color
				if birch:
					col = Color(0.86, 0.85, 0.8).darkened(0.08 * (f * 0.5 + 0.5))
					if s > 0.35 and absf(f) < 0.35:
						col = Color(0.12, 0.12, 0.11)
				else:
					col = Color(0.33, 0.25, 0.18).darkened(clampf(-f, 0.0, 1.0) * 0.5)
				albedo.set_pixel(x, y, col)
				height[y * SIZE + x] = f
		_cache[key] = _material(albedo, height, 4.0, 0.95, 0.0, Vector3(1.5, 1.5, 1.5))
	return _cache[key]


## Regalstütze: Lackierter Stahl mit Lochung (Doppelreihe Langlöcher im 50-mm-Raster).
static func upright(c: Color) -> StandardMaterial3D:
	var key := "upright_%s" % c.to_html()
	if not _cache.has(key):
		var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var height := PackedFloat32Array()
		height.resize(SIZE * SIZE)
		for y in SIZE:
			# Textur deckt 0,4 m ab: 8 Lochreihen
			var v := fposmod(float(y) / SIZE * 8.0, 1.0)
			for x in SIZE:
				var u := fposmod(float(x) / SIZE * 5.0, 1.0)
				var hole := v > 0.2 and v < 0.6 and u > 0.35 and u < 0.65
				albedo.set_pixel(x, y, Color(0.05, 0.06, 0.08) if hole else c)
				height[y * SIZE + x] = -1.0 if hole else 0.0
		_cache[key] = _material(albedo, height, 4.0, 0.5, 0.0, Vector3(2.5, 2.5, 2.5))
	return _cache[key]


static func _material(albedo: Image, height: PackedFloat32Array, bump: float, rough: float, metal: float, scale: Vector3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(_mip(albedo))
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(_normal(height, SIZE, bump))
	m.roughness = rough
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Kachelbares Rauschen: vier versetzte Abtastungen, über die Fläche überblendet.
static func _tile(n: FastNoiseLite, x: int, y: int) -> float:
	var u := float(x) / SIZE
	var v := float(y) / SIZE
	var a := n.get_noise_2d(x, y)
	var b := n.get_noise_2d(x - SIZE, y)
	var c := n.get_noise_2d(x, y - SIZE)
	var d := n.get_noise_2d(x - SIZE, y - SIZE)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


static func _noise(seed: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = 4
	return n


static func _mip(img: Image) -> Image:
	img.generate_mipmaps()
	return img


## Normalenkarte aus einem Höhenfeld (kachelbar, Nachbarn wickeln um).
static func _normal(h: PackedFloat32Array, size: int, strength: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var dx := h[y * size + (x + 1) % size] - h[y * size + (x - 1 + size) % size]
			var dy := h[((y + 1) % size) * size + x] - h[((y - 1 + size) % size) * size + x]
			var n := Vector3(-dx * strength, -dy * strength, 1.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return _mip(img)
