class_name MenuBackdrop
extends Node3D
## Hintergrund des Hauptmenüs: filmische Nahaufnahme eines Drehmeißels, der endlos einen
## Wendelspan von einem rotierenden Werkstück abnimmt. Alles prozedural, nahtlos geloopt:
## der Meißel steht an der Schulter still (Vorschub ist im Bild nicht sichtbar), der Span
## wächst, bricht ab und fällt, ein kurzer Stummel bleibt an der Schneide stehen.

const R_RAW := 0.030            # Rohdurchmesser 60 mm
const R_CUT := 0.0265           # nach dem Schnitt (Schnitttiefe 3,5 mm)
const TIP_X := 0.085            # Schneidenposition längs der Spindelachse
const STOCK_END := 0.19
const SPIN := 2.4               # sichtbare Drehzahl (rad/s, filmisch verlangsamt)
const CHIP_SPEED := 0.034       # m/s Spanlänge (passend zur sichtbaren Drehzahl)
const CHIP_R := 0.0058          # Krümmungsradius der Spanlocke
const CHIP_PITCH := 0.004         # Steigung je Windung (zusätzlich zur Streckung)
const LIFT_DIR := Vector3(0.8, 0.45, 0.42)   # Streckrichtung der Locke (weg von der Schneide)
const CHIP_W := 0.004          # Spanbreite
const CHIP_T := 0.00045         # Spandicke
const CHIP_STEP := 0.0009       # Auflösung längs des Spans
const STUB := 0.006             # Stummel, der nach dem Abbrechen an der Schneide bleibt
const BLUE := Color(0.06, 0.18, 0.58)

var camera: Camera3D
var env: Environment

var _t := 0.0
var _spindle: Node3D
var _slide: Node3D
var _has_model := false
var _tip := Vector3(TIP_X, 0.0004, R_CUT + 0.0004)
var _chip_mi: MeshInstance3D
var _chip_mat: ShaderMaterial
var _chip_len := STUB
var _chip_max := 0.11
var _produced := 0.0            # insgesamt erzeugte Spanlänge (Materialkoordinate)
var _falling: Array = []        # [{node, vel, ang, age}]
var _heat_light: OmniLight3D
var _cam_attr: CameraAttributesPractical
var _stream_mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _e1: Vector3
var _e2: Vector3
var _e3: Vector3


func _ready() -> void:
	_rng.seed = 4711
	_build_environment()
	_build_machine()
	_build_tool()
	_build_chip()
	_build_fx()
	_build_lights()
	_build_camera()
	_chip_max = _rng.randf_range(0.09, 0.14)
	_update_camera(0.0)


# ======================================================================= Aufbau

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.018, 0.022, 0.03)
	# Studio-Himmel nur für Reflexionen: dunkel mit Lichtleisten, damit der blanke Stahl glänzt
	var sky_mat := ShaderMaterial.new()
	var sky_sh := Shader.new()
	sky_sh.code = """
shader_type sky;
void sky() {
	vec3 d = EYEDIR;
	vec3 c = vec3(0.012, 0.015, 0.022) + vec3(0.02, 0.025, 0.035) * clamp(d.y + 0.2, 0.0, 1.0);
	// Lichtleiste oben (kühl) und ein warmes Seitenlicht
	float top = smoothstep(0.82, 0.9, d.y);
	float strip = smoothstep(0.05, 0.0, abs(d.y - 0.42)) * smoothstep(0.1, 0.5, d.z);
	float warm = smoothstep(0.75, 0.95, dot(d, normalize(vec3(0.6, 0.2, -0.75))));
	c += vec3(0.9, 0.95, 1.0) * top * 0.8 + vec3(0.8, 0.88, 1.0) * strip * 0.9 + vec3(1.0, 0.55, 0.25) * warm * 0.12;
	COLOR = c;
}
"""
	sky_mat.shader = sky_sh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.4)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.065, 0.09)
	env.fog_density = 0.35
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)


func _build_machine() -> void:
	var steel := Build.mat(Color(0.6, 0.61, 0.63), 0.3, 1.0)
	var dark := Build.mat(Color(0.09, 0.095, 0.1), 0.55, 0.4)
	var white := Build.mat(Color(0.88, 0.89, 0.9), 0.45)
	var blue := Build.mat(BLUE, 0.38)

	# Spindelkasten-Stirnwand (unscharf im Hintergrund): weiß mit Weiler-Blau
	Build.box(self, Vector3(0.02, 0.9, 1.2), Vector3(-0.15, 0.05, -0.1), white)
	Build.box(self, Vector3(0.021, 0.07, 1.2), Vector3(-0.149, -0.22, -0.1), blue)
	Build.box(self, Vector3(1.6, 0.04, 0.8), Vector3(0.5, -0.28, -0.05), dark)        # Bett
	Build.box(self, Vector3(1.6, 0.02, 0.05), Vector3(0.5, -0.255, 0.2), steel)       # Führung
	Build.box(self, Vector3(1.6, 0.02, 0.05), Vector3(0.5, -0.255, -0.25), steel)
	Build.cyl(self, 0.12, 0.05, Vector3(-0.125, 0, 0), dark, Build.AXIS_X, false, 48)  # Spindelnase

	_spindle = Node3D.new()
	add_child(_spindle)

	# Dreibackenfutter, Backen und Schnellwechsel-Werkzeughalter mit Schruppmeißel aus models/lathe.glb
	# (wie an der Maschine im Spiel). Ohne Modell: einfache prozedurale Ersatzteile.
	_slide = Node3D.new()
	_slide.position = Vector3(TIP_X, 0.0, R_CUT)      # Bezugspunkt = Schneidenecke des aktiven Werkzeugs
	add_child(_slide)
	var tailstock := Node3D.new()
	tailstock.visible = false
	add_child(tailstock)
	var model := LatheModel.new()
	_has_model = model.build(_spindle, _slide, tailstock, 0.0, -0.09)
	if _has_model:
		model.set_layout(["T1", "", "T3", ""], 0, 0.0)
		model.update_jaws(R_RAW * 2000.0)
		# Futterkörper und Backen sind im Modell reinweiß -> im Studiolicht als Stahl darstellen
		var body := Build.mat(Color(0.42, 0.43, 0.45), 0.34, 1.0)
		var jaw_m := Build.mat(Color(0.62, 0.63, 0.65), 0.26, 1.0)
		for mi in _spindle.find_children("*", "MeshInstance3D", true, false):
			if mi.name == "chuck_main_body" or mi.name == "Cylinder":
				mi.material_override = body
			elif str(mi.name).begins_with("Jaw") or str(mi.name).begins_with("Cube_00"):
				mi.material_override = jaw_m
			elif mi.name == "chuck_logo":
				mi.material_override = Build.mat(BLUE, 0.4)
	else:
		_proc_chuck()

	# Werkstück: rau gewalzt auf der Futterseite, blank gedreht hinter der Schneide
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.seamless = true
	ntex.width = 512
	ntex.height = 256
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.09, 0.085, 0.08))
	ramp.set_color(1, Color(0.26, 0.25, 0.24))
	ntex.color_ramp = ramp
	var raw := StandardMaterial3D.new()
	raw.albedo_texture = ntex
	raw.metallic = 0.5
	raw.roughness = 0.78
	var cut := StandardMaterial3D.new()
	cut.albedo_color = Color(0.6, 0.61, 0.63)
	cut.metallic = 1.0
	cut.roughness = 0.3
	var raw_len := TIP_X + 0.03 - 0.0015
	Build.cyl(_spindle, R_RAW, raw_len, Vector3(-0.03 + raw_len * 0.5, 0, 0), raw, Build.AXIS_X, false, 64)
	# kurzer Kegel an der Schulter (Einstellwinkel der Schneide)
	Build.cyl(_spindle, R_CUT, 0.0015, Vector3(TIP_X - 0.00075, 0, 0), cut, Build.AXIS_X, false, 64, R_RAW)
	var cut_len := STOCK_END - TIP_X - 0.002
	Build.cyl(_spindle, R_CUT, cut_len, Vector3(TIP_X + cut_len * 0.5, 0, 0), cut, Build.AXIS_X, false, 64)
	Build.cyl(_spindle, R_CUT, 0.002, Vector3(STOCK_END - 0.001, 0, 0), cut, Build.AXIS_X, false, 64, R_CUT - 0.002)


func _build_tool() -> void:
	var blue := Build.mat(BLUE, 0.38)
	var lightgrey := Build.mat(Color(0.42, 0.44, 0.46), 0.55)

	var tool := Node3D.new()
	tool.position = Vector3(TIP_X, 0.0, R_CUT)
	add_child(tool)
	if not _has_model:
		_proc_tool(tool)
	# Planschlitten (hellgrau) und blaue Schlittenabdeckung unter dem Werkzeughalter
	Build.box(tool, Vector3(0.26, 0.05, 0.36), Vector3(0.02, -0.115, 0.17), lightgrey)
	Build.box(tool, Vector3(0.4, 0.06, 0.4), Vector3(0.02, -0.17, 0.19), blue)

	_build_coolant(tool)


## KSS-Versorgung: Gelenkschlauch aus Kugel-Pfannen-Gliedern (Loc-Line-Art), Rundstrahldüse,
## klarer Strahl mit Lichtbrechung.
func _build_coolant(tool: Node3D) -> void:
	var hose_m := StandardMaterial3D.new()
	hose_m.albedo_color = Color(0.035, 0.11, 0.42)
	hose_m.roughness = 0.35
	hose_m.clearcoat_enabled = true
	hose_m.clearcoat = 0.7
	hose_m.clearcoat_roughness = 0.15
	hose_m.rim_enabled = true
	hose_m.rim = 0.1
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(1.0, 0.45, 0.05)
	orange.roughness = 0.3
	orange.clearcoat_enabled = true
	orange.clearcoat = 0.6
	var steel := Build.mat(Color(0.7, 0.71, 0.73), 0.22, 1.0)

	# Strahlrichtung und Düsenlage (lokal zum Werkzeug, Schneide ~ Ursprung)
	var aim := Vector3(0.0006, 0.0012, 0.0012)
	var dir := Vector3(-0.08, -1.0, 0.3).normalized()       # von der Düse zur Schneide
	var mouth := aim - dir * 0.036
	const NOZZLE_L := 0.016
	var nozzle_base := mouth - dir * NOZZLE_L

	# Schlauchverlauf: von oben hinten in einem ruhigen Bogen zur Düse
	var curve := Curve3D.new()
	curve.bake_interval = 0.001
	curve.add_point(Vector3(-0.05, 0.34, -0.17), Vector3.ZERO, Vector3(0.0, -0.09, 0.0))
	curve.add_point(Vector3(-0.03, 0.17, -0.09), Vector3(-0.004, 0.06, -0.03), Vector3(0.004, -0.06, 0.03))
	curve.add_point(nozzle_base, -dir * 0.05, Vector3.ZERO)
	var blen := curve.get_baked_length()

	# Ein Glied: Kugel unten, Hals, aufgeweitete Pfanne oben mit Lippe (Achse +Y)
	const PITCH := 0.0094
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ball := SphereMesh.new()
	ball.radius = 0.0041
	ball.height = 0.0082
	ball.radial_segments = 20
	ball.rings = 10
	st.append_from(ball, 0, Transform3D.IDENTITY)
	var neck := CylinderMesh.new()
	neck.bottom_radius = 0.0029
	neck.top_radius = 0.0034
	neck.height = 0.003
	neck.radial_segments = 20
	neck.rings = 1
	neck.cap_top = false
	neck.cap_bottom = false
	st.append_from(neck, 0, Transform3D(Basis(), Vector3(0, 0.0042, 0)))
	var cup := CylinderMesh.new()
	cup.bottom_radius = 0.0034
	cup.top_radius = 0.0049
	cup.height = 0.0036
	cup.radial_segments = 20
	cup.rings = 2
	cup.cap_top = false
	cup.cap_bottom = false
	st.append_from(cup, 0, Transform3D(Basis(), Vector3(0, 0.0075, 0)))
	var lip := TorusMesh.new()
	lip.inner_radius = 0.0043
	lip.outer_radius = 0.0052
	lip.rings = 20
	lip.ring_segments = 8
	st.append_from(lip, 0, Transform3D(Basis(), Vector3(0, 0.0093, 0)))
	var seg_mesh := st.commit()

	var count := int(blen / PITCH)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = seg_mesh
	mm.instance_count = count
	for i in count:
		# Kugel des Glieds i sitzt in der Pfanne des vorherigen; Glieder liegen exakt auf dem Bogen
		var d := blen - (i + 1) * PITCH
		var p := curve.sample_baked(d)
		var q := curve.sample_baked(d + PITCH)
		var t := (q - p).normalized()
		var b := Basis(Quaternion(Vector3.UP, t))
		b = b.rotated(t, i * 0.7)     # leicht verdrehte Glieder wie im echten Schlauch
		mm.set_instance_transform(i, Transform3D(b, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = hose_m
	tool.add_child(mmi)

	# Anschluss oben (Sechskant) und Rundstrahldüse (orange) mit Messingmündung
	var start := curve.sample_baked(0.0)
	Build.cyl(tool, 0.0075, 0.012, start + Vector3(0, 0.004, 0), steel, Build.AXIS_Y, false, 6)
	var nz := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.bottom_radius = 0.0047
	cone.top_radius = 0.0017
	cone.height = NOZZLE_L
	cone.radial_segments = 24
	nz.mesh = cone
	nz.material_override = orange
	nz.basis = Basis(Quaternion(Vector3.UP, dir))
	nz.position = nozzle_base + dir * NOZZLE_L * 0.5
	tool.add_child(nz)
	var tipc := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.bottom_radius = 0.0019
	tc.top_radius = 0.0016
	tc.height = 0.0022
	tc.radial_segments = 20
	tipc.mesh = tc
	tipc.material_override = Build.mat(Color(0.85, 0.66, 0.32), 0.25, 1.0)
	tipc.basis = nz.basis
	tipc.position = mouth - dir * 0.0008
	tool.add_child(tipc)

	# Strahl: glasklarer, leicht pulsierender Rundstrahl, bricht den Hintergrund
	_stream_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void vertex() {
	float w = sin(UV.y * 46.0 + TIME * 26.0 + UV.x * 6.283) * sin(UV.y * 17.0 + TIME * 11.0);
	VERTEX.xz *= 1.0 + 0.16 * w * smoothstep(0.0, 0.25, UV.y);
}
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float streak = smoothstep(0.6, 1.0, sin(UV.y * 60.0 + TIME * 48.0 + sin(UV.x * 12.566 + UV.y * 7.0) * 2.2) * 0.5 + 0.5);
	vec3 bg = textureLod(screen_tex, SCREEN_UV - NORMAL.xy * 0.01, 1.0).rgb;
	ALBEDO = vec3(0.03, 0.035, 0.04);
	EMISSION = bg * vec3(0.9, 0.96, 1.0) + vec3(0.75, 0.85, 1.0) * (streak * 0.35 + fres * 0.45);
	ROUGHNESS = 0.03;
	SPECULAR = 1.0;
	METALLIC = 0.0;
	ALPHA = clamp(0.82 + fres * 0.18, 0.0, 1.0);
}
"""
	_stream_mat.shader = sh
	var stream := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0016      # an der Düse
	cm.bottom_radius = 0.0014
	cm.height = (aim - mouth).length()
	cm.radial_segments = 16
	cm.rings = 40
	cm.cap_top = false
	cm.cap_bottom = false
	stream.mesh = cm
	stream.material_override = _stream_mat
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tool.add_child(stream)
	stream.position = (mouth + aim) * 0.5
	stream.basis = Basis(Quaternion(Vector3.UP, -dir))


func _build_chip() -> void:
	_chip_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
instance uniform float heat_scale = 1.0;
uniform float glow = 6.0;
void fragment() {
	float h = UV.x * heat_scale;
	ALBEDO = mix(COLOR.rgb, vec3(0.25, 0.08, 0.02), clamp(h * 1.5, 0.0, 1.0));
	METALLIC = 0.55;
	ROUGHNESS = 0.32 + 0.15 * UV.y;
	RIM = 0.35;
	RIM_TINT = 0.8;
	vec3 hot = mix(vec3(1.0, 0.18, 0.02), vec3(1.0, 0.72, 0.3), h * h);
	EMISSION = hot * h * h * glow + COLOR.rgb * 0.06;
}
"""
	_chip_mat.shader = sh
	_chip_mi = MeshInstance3D.new()
	_chip_mi.material_override = _chip_mat
	_chip_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_chip_mi)
	# Der Span verlässt die Spanfläche nach außen (_e1) und rollt nach oben ein (_e2);
	# _e3 ist die Wendelachse, _lift zieht die Locke als gestreckte Wendel von der Schneide weg.
	_e1 = Vector3(0.15, 0.3, 0.94).normalized()
	_e2 = Vector3(0.0, 1.0, 0.0)
	_e2 = (_e2 - _e1 * _e2.dot(_e1)).normalized()
	_e3 = _e1.cross(_e2).normalized()
	if _e3.x < 0.0:
		_e3 = -_e3


func _build_fx() -> void:
	# Funken: wenige, kurz, additiv (werden vom Glow erfasst)
	var spark_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	ALBEDO = COLOR.rgb * 6.0 * COLOR.a;
}
"""
	spark_mat.shader = sh
	var sparks := CPUParticles3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.00018
	sm.bottom_radius = 0.00018
	sm.height = 0.0045
	sm.radial_segments = 4
	sm.rings = 1
	sm.material = spark_mat
	sparks.mesh = sm
	sparks.amount = 18
	sparks.lifetime = 0.55
	sparks.randomness = 0.6
	sparks.position = _tip + Vector3(0.0, 0.001, 0.0)
	sparks.direction = Vector3(0.5, 0.8, 1.0)
	sparks.spread = 38
	sparks.initial_velocity_min = 0.25
	sparks.initial_velocity_max = 0.8
	sparks.gravity = Vector3(0, -3.0, 0)
	sparks.particle_flag_align_y = true
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	g.add_point(0.4, Color(1.0, 0.45, 0.1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(0.8, 0.15, 0.02, 0.0))
	sparks.color_ramp = g
	add_child(sparks)

	# KSS: gestreckte Spritzer an der Schneide, feiner Nebel, Tropfen unter dem Werkstück
	var drop_m := StandardMaterial3D.new()
	drop_m.albedo_color = Color(0.82, 0.88, 0.95, 0.5)
	drop_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_m.roughness = 0.02
	drop_m.metallic = 0.2
	drop_m.rim_enabled = true
	drop_m.rim = 0.6
	drop_m.vertex_color_use_as_albedo = true
	var dm := SphereMesh.new()
	dm.radius = 0.0006
	dm.height = 0.0028
	dm.radial_segments = 8
	dm.rings = 4
	dm.material = drop_m
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var splash := CPUParticles3D.new()
	splash.mesh = dm
	splash.amount = 70
	splash.lifetime = 0.6
	splash.position = _tip + Vector3(0.002, 0.0025, 0.002)
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	splash.emission_sphere_radius = 0.0015
	splash.direction = Vector3(0.45, 0.55, 1.0)
	splash.spread = 55
	splash.initial_velocity_min = 0.1
	splash.initial_velocity_max = 0.4
	splash.gravity = Vector3(0, -9.8, 0)
	splash.scale_amount_min = 0.4
	splash.scale_amount_max = 1.3
	splash.particle_flag_align_y = true
	splash.color_ramp = fade
	add_child(splash)

	# Nebel: weiche, kaum sichtbare Schwaden um die Schneide (fangen das Gegenlicht)
	var mist_m := ShaderMaterial.new()
	var msh := Shader.new()
	msh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void vertex() {
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = mv * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	float a = smoothstep(1.0, 0.0, length(UV - 0.5) * 2.0);
	ALBEDO = vec3(0.8, 0.88, 1.0) * a * a * COLOR.a;
}
"""
	mist_m.shader = msh
	var qm := QuadMesh.new()
	qm.size = Vector2(0.012, 0.012)
	qm.material = mist_m
	var mist := CPUParticles3D.new()
	mist.mesh = qm
	mist.amount = 26
	mist.lifetime = 1.6
	mist.position = _tip + Vector3(0.003, 0.004, 0.003)
	mist.direction = Vector3(0.4, 0.6, 0.8)
	mist.spread = 70
	mist.initial_velocity_min = 0.01
	mist.initial_velocity_max = 0.04
	mist.gravity = Vector3(0, 0.004, 0)
	mist.damping_min = 0.01
	mist.damping_max = 0.02
	mist.angle_min = -180
	mist.angle_max = 180
	mist.scale_amount_min = 0.6
	mist.scale_amount_max = 1.5
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 1.6))
	mist.scale_amount_curve = grow
	var mc := Gradient.new()
	mc.set_color(0, Color(0.85, 0.9, 1.0, 0.0))
	mc.add_point(0.2, Color(0.85, 0.9, 1.0, 0.12))
	mc.set_color(mc.get_point_count() - 1, Color(0.85, 0.9, 1.0, 0.0))
	mist.color_ramp = mc
	add_child(mist)

	var drip := CPUParticles3D.new()
	drip.mesh = dm
	drip.amount = 20
	drip.lifetime = 0.9
	drip.position = Vector3(TIP_X + 0.03, -R_CUT - 0.001, 0.0)
	drip.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drip.emission_box_extents = Vector3(0.03, 0.0, 0.004)
	drip.direction = Vector3(0, -1, 0)
	drip.spread = 3
	drip.initial_velocity_min = 0.0
	drip.initial_velocity_max = 0.04
	drip.gravity = Vector3(0, -9.8, 0)
	drip.scale_amount_min = 0.8
	drip.scale_amount_max = 1.5
	drip.particle_flag_align_y = true
	add_child(drip)


func _build_lights() -> void:
	var key := SpotLight3D.new()
	key.position = _tip + Vector3(0.12, 0.42, 0.24)
	key.light_color = Color(0.92, 0.96, 1.0)
	key.light_energy = 3.2
	key.spot_range = 1.5
	key.spot_angle = 13
	key.spot_angle_attenuation = 0.8
	key.shadow_enabled = int(Settings.graphics["quality"]) >= 1
	key.shadow_blur = 1.5
	add_child(key)
	key.look_at(_tip)
	var rim := SpotLight3D.new()
	rim.position = _tip + Vector3(0.35, 0.16, -0.3)
	rim.light_color = Color(1.0, 0.62, 0.32)
	rim.light_energy = 4.0
	rim.spot_range = 1.2
	rim.spot_angle = 9
	add_child(rim)
	rim.look_at(_tip)
	var fill := OmniLight3D.new()
	fill.position = _tip + Vector3(0.12, -0.05, 0.25)
	fill.light_color = Color(0.35, 0.5, 1.0)
	fill.light_energy = 0.35
	fill.omni_range = 0.35
	add_child(fill)
	_heat_light = OmniLight3D.new()
	_heat_light.position = _tip + Vector3(0.003, 0.008, 0.004)
	_heat_light.light_color = Color(1.0, 0.45, 0.12)
	_heat_light.light_energy = 0.5
	_heat_light.omni_range = 0.03
	add_child(_heat_light)
	# Werkstattlichter weit hinten: werden durch die Tiefenunschärfe zu Bokeh-Kreisen
	var bokeh_cols := [Color(1.0, 0.7, 0.4), Color(0.6, 0.75, 1.0), Color(1.0, 0.9, 0.75)]
	for i in 16:
		var p := Vector3(_rng.randf_range(-2.8, -0.6), _rng.randf_range(-0.2, 1.2), _rng.randf_range(-3.5, -1.2))
		var c: Color = bokeh_cols[i % bokeh_cols.size()]
		Build.sphere(self, _rng.randf_range(0.01, 0.025), p, Build.emissive(c, _rng.randf_range(2.0, 6.0)))


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 32
	camera.near = 0.004
	camera.far = 30.0
	_cam_attr = CameraAttributesPractical.new()
	var dof := int(Settings.graphics["quality"]) >= 1
	_cam_attr.dof_blur_far_enabled = dof
	_cam_attr.dof_blur_near_enabled = dof
	_cam_attr.dof_blur_amount = 0.09
	camera.attributes = _cam_attr
	add_child(camera)
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)


# ======================================================================= Ablauf

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	_spindle.rotation.x = fmod(_spindle.rotation.x + SPIN * delta, TAU)
	_chip_len += CHIP_SPEED * delta
	_produced += CHIP_SPEED * delta
	if _chip_len >= _chip_max:
		_break_chip()
	_chip_mi.mesh = _chip_mesh(0.0, _chip_len)
	_update_falling(delta)
	_heat_light.light_energy = 0.18 + 0.08 * sin(_t * 23.0) * sin(_t * 7.3)
	_update_camera(_t)


func _update_camera(t: float) -> void:
	var target := _tip + Vector3(0.008, 0.006, 0.004)
	var yaw := 0.55 + 0.2 * sin(t * 0.085)
	var pitch := 0.78 + 0.07 * sin(t * 0.11 + 1.3)
	var dist := 0.21 + 0.025 * sin(t * 0.06 + 0.4)
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	camera.look_at(target)
	camera.h_offset = -0.045
	camera.v_offset = 0.008
	_cam_attr.dof_blur_far_distance = dist + 0.03
	_cam_attr.dof_blur_far_transition = 0.18
	_cam_attr.dof_blur_near_distance = maxf(dist - 0.1, 0.01)
	_cam_attr.dof_blur_near_transition = 0.07


## Bahn des Spans: Abstand s von der Schneide -> Punkt. Die Form ist fest, das Material
## wandert entlang der Wendel (entspricht einer Schraubbewegung der ganzen Locke).
func _chip_point(s: float) -> Vector3:
	var a := s / CHIP_R
	var wob := 0.06 * sin(_t * 0.7)
	var r := CHIP_R * (1.0 + 2.5 * s)            # Locke weitet sich leicht auf
	var p := _tip + _e1 * (sin(a) * r) + _e2 * ((1.0 - cos(a)) * r) \
		+ _e3 * (a / TAU * CHIP_PITCH) + LIFT_DIR * (s * 0.36)
	p.y -= 0.9 * s * s * (1.0 + wob)          # leichtes Durchhängen langer Locken
	return p


func _chip_mesh(s0: float, s1: float, base_shift := 0.0) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := maxi(2, int((s1 - s0) / CHIP_STEP) + 1)
	for i in n:
		var s := lerpf(s0, s1, float(i) / float(n - 1))
		var p := _chip_point(s) - Vector3.ONE * 0.0 + Vector3(0, 0, 0)
		var t := (_chip_point(s + 0.0005) - _chip_point(maxf(s - 0.0005, 0.0))).normalized()
		var w := (_e3 - t * _e3.dot(t)).normalized()
		var nn := t.cross(w).normalized()
		var m := _produced - s + base_shift     # Materialkoordinate (haftet am Span)
		var width := CHIP_W * (0.85 + 0.15 * sin(m * 900.0) * sin(m * 337.0))
		if s < 0.0015:
			width *= 0.6 + 0.4 * s / 0.0015
		var heat := clampf(1.0 - s / 0.022, 0.0, 1.0)
		var col := _temper(s)
		# Span liegt komplett auf der gedrehten Seite neben der Schulter (nicht im Rohmaterial)
		p += w * (width * 0.5 + 0.00015)
		var hw := w * width * 0.5
		var ht := nn * CHIP_T * 0.5
		var corners := [p + hw + ht, p - hw + ht, p - hw - ht, p + hw - ht]
		for k in 4:
			corners[k] = _outside_stock(corners[k])
		var side_n := [nn, -w, -nn, w]
		for f in 4:
			verts.append(corners[f])
			verts.append(corners[(f + 1) % 4])
			norms.append(side_n[f])
			norms.append(side_n[f])
			for _k in 2:
				cols.append(col)
				uvs.append(Vector2(heat, 0.5 + 0.5 * sin(m * 2400.0)))
	for i in n - 1:
		for f in 4:
			var a := i * 8 + f * 2
			var b := a + 8
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Schiebt einen Punkt radial aus dem Werkstück heraus (Rohteil, Schulterkegel, gedrehter Teil).
func _outside_stock(v: Vector3) -> Vector3:
	var req := R_CUT
	if v.x < TIP_X - 0.0015:
		req = R_RAW
	elif v.x < TIP_X:
		req = lerpf(R_RAW, R_CUT, (v.x - (TIP_X - 0.0015)) / 0.0015)
	req += 0.00012
	var rho := Vector2(v.y, v.z).length()
	if rho < req and rho > 0.0:
		var k := req / rho
		v.y *= k
		v.z *= k
	return v


## Anlauffarben je Abstand zur Schneide: strohgelb -> braun -> violett -> blau
func _temper(s: float) -> Color:
	var stops := [
		[0.0, Color(0.85, 0.66, 0.3)], [0.02, Color(0.72, 0.45, 0.16)], [0.04, Color(0.45, 0.2, 0.14)],
		[0.06, Color(0.3, 0.12, 0.38)], [0.08, Color(0.1, 0.18, 0.55)], [0.12, Color(0.14, 0.28, 0.58)]]
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if s <= b[0]:
			return (a[1] as Color).lerp(b[1], (s - a[0]) / (b[0] - a[0]))
	return stops[stops.size() - 1][1]


func _break_chip() -> void:
	var mesh := _chip_mesh(STUB, _chip_len)
	var aabb := mesh.get_aabb()
	var c := aabb.get_center()
	var pivot := Node3D.new()
	pivot.position = c
	add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _chip_mat
	mi.position = -c
	pivot.add_child(mi)
	var vel := Vector3(_rng.randf_range(0.02, 0.12), _rng.randf_range(0.0, 0.06), _rng.randf_range(0.08, 0.2))
	var ang := Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-3, 3), _rng.randf_range(-4, 4))
	_falling.append({"node": pivot, "mi": mi, "vel": vel, "ang": ang, "age": 0.0})
	_chip_len = STUB
	_chip_max = _rng.randf_range(0.09, 0.14)


func _update_falling(delta: float) -> void:
	for i in range(_falling.size() - 1, -1, -1):
		var f: Dictionary = _falling[i]
		var node: Node3D = f["node"]
		f["age"] += delta
		f["vel"] += Vector3(0, -9.8, 0) * delta
		node.position += f["vel"] * delta
		node.rotate(Vector3(f["ang"]).normalized(), Vector3(f["ang"]).length() * delta)
		(f["mi"] as MeshInstance3D).set_instance_shader_parameter("heat_scale", maxf(0.0, 1.0 - f["age"] * 2.0))
		if f["age"] > 2.5 or node.position.y < -0.6:
			node.queue_free()
			_falling.remove_at(i)


# ======================================================================= Ersatzteile ohne Modell

func _proc_chuck() -> void:
	var steel := Build.mat(Color(0.6, 0.61, 0.63), 0.3, 1.0)
	var dark := Build.mat(Color(0.09, 0.095, 0.1), 0.55, 0.4)
	var chuck_m := Build.mat(Color(0.5, 0.51, 0.53), 0.32, 1.0)
	Build.cyl(_spindle, 0.085, 0.085, Vector3(-0.058, 0, 0), chuck_m, Build.AXIS_X, false, 64)
	Build.cyl(_spindle, 0.083, 0.004, Vector3(-0.0145, 0, 0), dark, Build.AXIS_X, false, 64)
	for k in 3:
		var a := TAU * k / 3.0
		var jaw := Node3D.new()
		jaw.rotation.x = a
		_spindle.add_child(jaw)
		Build.box(jaw, Vector3(0.026, 0.036, 0.022), Vector3(-0.004, R_RAW + 0.018, 0), steel)
		Build.box(jaw, Vector3(0.014, 0.02, 0.022), Vector3(-0.012, R_RAW + 0.044, 0), steel)  # Stufe
		Build.box(jaw, Vector3(0.012, 0.05, 0.026), Vector3(-0.022, R_RAW + 0.03, 0), dark)    # Grundbacke
		for s in [-1.0, 1.0]:
			Build.cyl(jaw, 0.0035, 0.004, Vector3(-0.008 + s * 0.0, R_RAW + 0.024 + s * 0.01, 0.0112),
				dark, Build.AXIS_Z, false, 12)
		var hole := Node3D.new()
		hole.rotation.x = a + PI / 3.0
		_spindle.add_child(hole)
		Build.cyl(hole, 0.006, 0.004, Vector3(-0.0135, 0.066, 0), dark, Build.AXIS_X, false, 16)  # Schlüsselloch


func _proc_tool(tool: Node3D) -> void:
	var anth := Build.mat(Color(0.11, 0.115, 0.125), 0.4, 0.6)
	var insert_m := Build.mat(Color(0.16, 0.15, 0.13), 0.28, 0.9)
	var gold := Build.mat(Color(0.78, 0.62, 0.28), 0.25, 1.0)
	var steel := Build.mat(Color(0.62, 0.63, 0.65), 0.3, 1.0)
	# Wendeschneidplatte CNMG (80°-Raute), Ecke an der Schneide, Spanfläche auf Spitzenhöhe
	var bis := Vector2(-0.35, -1.0).normalized()     # Winkelhalbierende der Ecke in (x, z)
	var back := -bis
	var l := 0.0127
	var p1 := back.rotated(deg_to_rad(40)) * l
	var p3 := back.rotated(deg_to_rad(-40)) * l
	var pts := PackedVector2Array([Vector2.ZERO, p1, p1 + p3, p3])
	var ins := MeshInstance3D.new()
	ins.mesh = _prism(pts, 0.0048, 0.0006)
	ins.material_override = insert_m
	ins.position.y = -0.0048
	tool.add_child(ins)
	var gold_edge := MeshInstance3D.new()                     # goldene Flanke (TiN)
	gold_edge.mesh = _prism(pts, 0.0035, 0.0006)
	gold_edge.material_override = gold
	gold_edge.position.y = -0.0049
	gold_edge.scale = Vector3(1.002, 1.0, 1.002)
	tool.add_child(gold_edge)
	var center := (p1 + p3) * 0.5
	Build.cyl(tool, 0.0028, 0.0012, Vector3(center.x, 0.0004, center.y), anth, Build.AXIS_Y, false, 20)
	Build.cyl(tool, 0.0012, 0.0014, Vector3(center.x, 0.0006, center.y), Build.mat(Color(0.02, 0.02, 0.02), 0.6), Build.AXIS_Y, false, 6)

	# Klemmhalter 25x25 mit Kopf
	var hw := 0.025
	Build.box(tool, Vector3(hw, hw, 0.22), Vector3(0.012, -0.0048 - hw * 0.5, 0.012 + 0.11), anth)
	Build.box(tool, Vector3(0.028, 0.012, 0.024), Vector3(0.011, -0.0048 - 0.006 - 0.0006, 0.012), anth, false, Vector3(0, 0.3, 0))
	# Vierfach-Werkzeughalter, Querschlitten (hellgrau) und blaue Abdeckung
	Build.box(tool, Vector3(0.11, 0.09, 0.11), Vector3(0.02, -0.06, 0.25), steel)
	Build.box(tool, Vector3(0.112, 0.012, 0.112), Vector3(0.02, -0.009, 0.25), anth)
	Build.cyl(tool, 0.009, 0.05, Vector3(0.02, 0.0, 0.25), steel, Build.AXIS_Y, false, 24)


## Prisma aus einem Polygon in der xz-Ebene (Höhe in +y), mit kleiner Fase an der Oberkante.
func _prism(pts: PackedVector2Array, h: float, chamfer: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p + (c - p).normalized() * chamfer)
	var n := pts.size()
	# Oberseite (eingezogen), Fase, Seiten, Unterseite
	for i in range(1, n - 1):
		_tri(st, Vector3(inner[0].x, h, inner[0].y), Vector3(inner[i + 1].x, h, inner[i + 1].y), Vector3(inner[i].x, h, inner[i].y))
		_tri(st, Vector3(pts[0].x, 0, pts[0].y), Vector3(pts[i].x, 0, pts[i].y), Vector3(pts[i + 1].x, 0, pts[i + 1].y))
	for i in n:
		var j := (i + 1) % n
		var a := Vector3(pts[i].x, 0, pts[i].y)
		var b := Vector3(pts[j].x, 0, pts[j].y)
		var a2 := Vector3(pts[i].x, h - chamfer, pts[i].y)
		var b2 := Vector3(pts[j].x, h - chamfer, pts[j].y)
		var a3 := Vector3(inner[i].x, h, inner[i].y)
		var b3 := Vector3(inner[j].x, h, inner[j].y)
		_quad(st, a, b, b2, a2)
		_quad(st, a2, b2, b3, a3)
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, c, b)
	_tri(st, a, d, c)
