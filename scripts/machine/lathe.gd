class_name Lathe
extends Node3D
## Zyklengesteuerte Drehmaschine nach Vorbild einer Weiler E50 HD.
## Das Werkstück ist ein Radiusprofil (mm, Auflösung SEG). Das aktive Werkzeug ist ein
## Plattenpolygon (siehe LatheTools); alles Material oberhalb seiner unteren Hüllkurve wird
## abgetragen. Dadurch schneiden auch schräge Schneiden (Fasen, Kopierdrehen, Radien).
## Lokales Koordinatensystem: Spindelachse = +X, Bediener steht auf +Z-Seite.
## Maschinen-Z (DRO) = Abstand von der Backen-Stirnfläche, Maschinen-X = Durchmesser.

signal message(text: String, color: Color)
signal operating_changed(on: bool)
signal submit_requested
signal new_part_requested
signal tool_changed(index: int)

const MACHINE_ID := "lathe"
const TOOL_UPRIGHT := false   # Werkzeugmodelle liegen schon waagerecht (Schaft in Z)
const MOUNT_REACH := 0.13     # so nah muss der Blick am Halterkopf vorbeigehen (m)
const AXIS_H := 1.17          # Spitzenhöhe über Boden (m)
const SEG := 0.25             # Auflösung des Profils (mm pro Segment)
const Z_MAX := 900.0          # Drehlänge; Bett und Reitstock sind darauf abgestimmt
const X_MAX := 170.0          # max. Radius Werkzeug-Bezugspunkt (mm)
const X_MIN := -95.0          # über die Drehmitte hinaus (Anzeige X -190)
const CLAMP_LEN := 30.0       # eingespannte Länge in den Backen (mm)
const JOG_FAST := 10.0         # Shift: Verfahren mit 10-fachem Vorschub
const RPM_STEPS := [40, 63, 100, 160, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3000]
const FEED_STEPS := [0.03, 0.05, 0.08, 0.1, 0.12, 0.15, 0.2, 0.25, 0.3, 0.4]
const RPM_MIN := 40.0
const RPM_MAX := 3000.0
const FEED_MIN := 0.01
const FEED_MAX := 0.5
const VC_MIN := 20.0
const VC_MAX := 400.0
const SLOTS := 4              # Vierfach-Werkzeughalter
## Werkzeughalter (gemessen am Modell, mm, axial/radial relativ zur Schneidenecke in Arbeitslage):
## Drehpunkt des Halterkopfs und Umriss von Platte + Halter.
const POST_C := Vector2(94.7, 88.1)
const HOLDER_W := 50.0
const HOLDER_L := 142.0
const CHUCK_R := 150.0
const CHUCK_DEPTH := 146.0
const RING := 48
const PIECE_LAYER := 1 << 3   # Physik-Ebene für abgestochene Teile

var demo := false             # nur Deko (Hauptmenü)

var stock_d := 60.0
var stock_len := 160.0
var profile := PackedFloat32Array()
var machined := PackedByteArray()
var rz := PackedFloat32Array()   # Rautiefe je Segment in µm
var tool_z := 200.0
var tool_x := 45.0
var tool_idx := 0
var holder: Array = ["T1", "", "T3", ""]   # Werkzeug-ID je Halterplatz
var active_slot := 0
var rpm_set := 800.0          # Solldrehzahl /min (ohne konstante Schnittgeschwindigkeit)
var feed_set := 0.15          # Vorschub mm/U
var css := false              # konstante Schnittgeschwindigkeit (G96)
var vc_set := 150.0           # m/min
var rpm_limit := 2000.0       # Drehzahlbegrenzung bei G96 /min
var spindle_on := false
var spindle_speed := 0.0
var auto_feed := false        # Längsvorschub
var auto_feed_x := false      # Planvorschub
var auto_sign_z := -1         # Richtung Längsvorschub: -1 = zum Futter (Z-), +1 = Z+
var auto_sign_x := -1         # Richtung Planvorschub: -1 = zur Mitte (X-), +1 = X+
var hw_axis := 0              # Handrad-Achse: 0 = X (Plan), 1 = Z (Längs)
var coolant := false
var estop := false
var operating := false
var player: Node = null
var last_rz := 0.0
var last_rz_hint := ""          # Hauptursache der Rautiefe des letzten Schnitts
var _hw_last_ms := 0           # Zeit der letzten Handrad-Raste (Vorschub aus Kurbeltempo)
var _hw_speed := 0.0            # mm/s aus dem Kurbeltempo am Handrad

var model: LatheModel        # Blender-Modelle (null = prozedurale Ersatzteile)
var spindle_pivot: Node3D
var workpiece_mi: MeshInstance3D
var jaws: Array[Node3D] = []
var carriage: Node3D
var cross_slide: Node3D
var tool_nodes: Array[Node3D] = []
var hw_z: Node3D
var hw_x: Node3D
var op_cam: Camera3D
var screen_vp: SubViewport       # Bildschirm am Bedienpult: Zyklensteuerung (CncScreen)
var screen: Control
var _screen_mi: MeshInstance3D
var _pult: Node3D
var _screen_drag := false
var _panel_view := false
# Einschwenk-Animation des Halterkopfs (nur Darstellung; Logik schaltet sofort um)
const INDEX_LEVER_T := 0.22     # s Spannhebel lösen bzw. klemmen
const INDEX_ROT_T := 0.38       # s je 90° Drehung
var _idx_dir := 1               # Drehrichtung des nächsten Einschwenkens (+1 / -1)
var _vis_angle := 0.0           # sichtbarer Drehwinkel des Kopfs
var _anim_t := -1.0             # < 0: keine Animation
var _anim_dur := 0.0
var _anim_from := 0.0
var _anim_to := 0.0
const SCREEN_SIZE := Vector2(0.44, 0.385)   # m
const SCREEN_UI := Vector2(640, 560)       # logische Pixel der Bedienoberfläche
const SCREEN_SCALE := 2.0                  # Renderauflösung je logischem Pixel
const SCREEN_X := -0.04                    # Bildschirmmitte im Pult (links, rechts der Tastenblock)
const PULT_W := 0.66                       # Pultgehäuse (m) und seine Mitte im Pult
const PULT_H := 0.80
const PULT_X := 0.02
const PULT_Y := -0.10
const CANOPY_LAYER := 1 << 1               # Sichtebene des Dachs (Bedienkamera blendet es von oben aus)
const CANOPY_Y := 1.585                    # Unterkante des Dachs (m)
const DOOR_X0 := -0.98                     # Schiebetür (aufgeschoben) von ... bis (m)
const DOOR_X1 := -0.16
const DOOR_CX := (DOOR_X0 + DOOR_X1) * 0.5
const PULT_Y0 := 1.40                      # Höhe des Pult-Ursprungs (Bildschirm knapp darüber)
const PULT_ANGLE := 0.55                   # Pult zum Bediener hin angewinkelt (rad)
const DOOR_TRAVEL := 0.84                  # Weg der Schiebetür von auf (über dem Spindelkasten) bis zu
const DOOR_TIME := 0.9                     # s für den ganzen Weg
const DOOR_LAYER := 1 << 2                 # Sichtebene der Tür (Bedienkamera blendet sie von innen aus)
var door_t := 0.0                          # Türlage in DOOR_TRAVEL: 0 = auf, eingerastet = am Schlitten
var door_latched := false                  # am Bettschlitten eingerastet (= Schutztür zu)
var _door_closing := false                 # schiebt sich gerade zum Schlitten
const DOOR_LATCH_DX := 0.31 - DOOR_X1      # rechter Türrand bündig mit dem rechten Schlittenende
const DOOR_MAX := 2.06 - DOOR_X1           # weiter rechts endet die Laufschiene
const HANDLE_POS := Vector3(DOOR_X1 - 0.03, 1.32, 0.57)   # Türgriff (Tür auf), Maschinenkoordinaten
const HANDLE_PICK := Vector3(0.06, 0.46, 0.06)           # Greifbereich um den Griff
var _handle_hover := false
var _door: Node3D
var periphery: Node3D                                     # Späneförderer und Spänewagen (stehen neben der Maschine)
var _telescope: Array = []                                # Teleskopabdeckung links/rechts vom Bettschlitten
var _chain: Array[MeshInstance3D] = []                    # Glieder der Energiekette
const CHAIN_LINKS := 64
const CHAIN_PITCH := 0.04                                 # m je Glied
const CHAIN_FIX := 0.05                                   # festes Ende der Kette (x, m)
const CHAIN_LEN := 1.9                                    # Länge Untertrum + Obertrum (ohne Bogen)
const CHAIN_R := 0.04                                     # Biegeradius
var nc: NcChannel                          # Zyklensteuerung
var programs: Array = []                   # NC-Programme (siehe NcCam)
var prog_sel := ""                         # für AUTO angewähltes Programm
## Werkstücknullpunkt (Z0 der NC-Programme und der Pult-Anzeige) in mm über der Backen-
## Stirnfläche. Standard: Stirnfläche des Rohteils; am Pult neu setzbar (Ankratzen).
var wcs_z := 160.0
var nc_finish := false                     # gerade läuft ein Schlichtzug der Zyklensteuerung
var nc_internal := false                   # Aufruf kommt vom NC-Kanal (Sperren für Handbedienung aus)
var chips: CPUParticles3D
var coolant_fx: CPUParticles3D
var lamp: SpotLight3D
var spindle_led: MeshInstance3D

var _dirty := true
var _rebuild_t := 0.0
var _cut_t := 0.0
var _cut_level := 0.0
var _msg_cool := 0.0
var _last_msg := ""
var _screen_t := 0.0
const CAM_YAW := 0.15
const CAM_PITCH := -0.8
const CAM_DIST := 0.7
const CAM_MIN := 0.03         # nächster Abstand zum Blickpunkt (m)
const CAM_MAX := 2.5
var cam_yaw := CAM_YAW
var cam_pitch := CAM_PITCH
var cam_dist := CAM_DIST
var cam_target := Vector3(0.12, AXIS_H, 0.0)
var cam_pan := Vector3.ZERO
var _yaw_t := CAM_YAW
var _pitch_t := CAM_PITCH
var _dist_t := CAM_DIST

var _audio: AudioStreamPlayer3D
var _pb: AudioStreamGeneratorPlayback
var _mix := 22050.0
var _ph1 := 0.0
var _ph2 := 0.0
var _ph3 := 0.0
var _lp := 0.0

var _raw_col := Color(0.42, 0.42, 0.44)
var _cut_col := Color(0.88, 0.89, 0.92)
var _rough_col := Color(0.58, 0.58, 0.6)
var _led_on: StandardMaterial3D
var _led_off: StandardMaterial3D
var _wp_mat: StandardMaterial3D
var _cos := PackedFloat32Array()
var _sin := PackedFloat32Array()


func _ready() -> void:
	for k in RING:
		_cos.append(cos(TAU * k / RING))
		_sin.append(sin(TAU * k / RING))
	nc = NcChannel.new(self)
	if programs.is_empty():
		programs = NcCam.examples()
		prog_sel = str(programs[0]["name"])
	_build()
	new_workpiece(stock_d, stock_len)
	_apply_holder()
	if demo:
		spindle_on = true
		rpm_set = 630.0
		tool_z = 120.0
		tool_x = 45.0
	else:
		_setup_audio()


func tool() -> Dictionary:
	return LatheTools.get_tool(tool_idx)


func z_min() -> float:
	return maxf(1.0, -float(tool()["zmin"]) + 0.5)


# ======================================================================= Aufbau

func _build() -> void:
	# Farbgebung der E50 HD: weiße Verkleidung, Weiler-Blau, lichtgraues Bett, dunkelgrauer Unterbau
	var w := Build.mat(Color(0.90, 0.91, 0.91), 0.42)          # Verkleidung weiß
	var g := Build.mat(Color(0.74, 0.76, 0.77), 0.5)           # Bett / Schlitten lichtgrau
	var a := Build.mat(Color(0.25, 0.27, 0.29), 0.55)          # Unterbau dunkelgrau
	var blue := Build.mat(Color(0.06, 0.18, 0.58), 0.38)       # Weiler-Blau
	var dark := Build.mat(Color(0.07, 0.07, 0.08), 0.75)
	var steel := Build.mat(Color(0.72, 0.73, 0.75), 0.28, 1.0)
	var ways := Build.mat(Color(0.80, 0.81, 0.83), 0.22, 1.0)  # geschliffene Führungen
	var chrome := Build.mat(Color(0.86, 0.87, 0.89), 0.12, 1.0)
	var chuck_m := Build.mat(Color(0.55, 0.56, 0.58), 0.35, 1.0)
	var red := Build.mat(Color(0.85, 0.08, 0.05), 0.4)
	var green := Build.mat(Color(0.1, 0.65, 0.2), 0.4)
	var yellow := Build.mat(Color(0.95, 0.78, 0.05), 0.5)
	var seam := Build.mat(Color(0.12, 0.13, 0.14), 0.7)
	var bed_m := Build.mat(Color(0.47, 0.49, 0.51), 0.62)        # Grauguss lackiert (Bett, Reitstockfuß)
	var saddle_m := Build.mat(Color(0.55, 0.57, 0.59), 0.45, 0.3)
	var beige := Build.mat(Color(0.84, 0.80, 0.66), 0.8)         # Innenraum: cremefarben gesprenkelt
	var stainless := Build.mat(Color(0.74, 0.75, 0.76), 0.3, 1.0)
	var ts_w := Build.mat(Color(0.88, 0.88, 0.85), 0.55)         # Reitstock: gebrochenes Weiß

	# Unterbau: Standfuß unter dem Spindelkasten, Fuß rechts, dazwischen die Spänewanne
	Build.box(self, Vector3(0.88, 0.58, 0.86), Vector3(-0.62, 0.33, 0.0), a)
	Build.box(self, Vector3(0.62, 0.58, 0.86), Vector3(1.75, 0.33, 0.0), a)
	Build.box(self, Vector3(3.08, 0.04, 0.8), Vector3(0.51, 0.02, 0.0), dark)         # Sockelleiste
	for x in [-0.62, 1.75]:                                                           # Doppeltüren
		Build.box(self, Vector3(0.006, 0.5, 0.004), Vector3(x, 0.33, 0.431), seam)
		for s in [-1.0, 1.0]:
			Build.box(self, Vector3(0.012, 0.09, 0.02), Vector3(x + s * 0.04, 0.45, 0.44), dark)
	Build.box(self, Vector3(1.34, 0.06, 0.95), Vector3(0.75, 0.2, 0.06), stainless)
	Build.box(self, Vector3(1.34, 0.25, 0.03), Vector3(0.75, 0.33, 0.52), a)
	Build.box(self, Vector3(1.34, 0.02, 0.07), Vector3(0.75, 0.455, 0.5), g)          # Wannenkante
	Build.box(self, Vector3(1.34, 0.4, 0.03), Vector3(0.75, 0.42, -0.41), a)

	# Bett (Grauguss) mit geschliffenen Führungen: vorne Prisma, hinten Flachbahn. Die E50 HD hat
	# keine Leit-/Zugspindel - die Bettfront deckt ein Edelstahlblech ab. Hinten neben dem Bett
	# Teleskopabdeckung über dem Kugelgewindetrieb und dahinter die Energiekette zum Bettschlitten.
	Build.box(self, Vector3(3.07, 0.28, 0.56), Vector3(0.48, 0.76, 0.0), bed_m)
	Build.box(self, Vector3(3.07, 0.03, 0.5), Vector3(0.48, 0.635, 0.0), a)
	for s in [-1.0, 1.0]:                                                             # Prisma vorne
		Build.box(self, Vector3(3.02, 0.032, 0.05), Vector3(0.48, 0.912, 0.21 + s * 0.017), ways, false, Vector3(s * 0.75, 0, 0))
	Build.box(self, Vector3(3.02, 0.03, 0.08), Vector3(0.48, 0.915, -0.21), ways)     # Flachbahn hinten
	Build.box(self, Vector3(3.02, 0.02, 0.05), Vector3(0.48, 0.91, 0.0), ways)
	Build.box(self, Vector3(3.02, 0.01, 0.1), Vector3(0.48, 0.912, 0.0), dark)         # Bettschlitz
	Build.box(self, Vector3(3.02, 0.11, 0.006), Vector3(0.48, 0.82, 0.283), stainless)  # Bettfrontblech
	Build.box(self, Vector3(3.02, 0.012, 0.02), Vector3(0.48, 0.885, 0.285), ways)
	for i in 11:                                                                      # Blechschrauben
		Build.cyl(self, 0.004, 0.004, Vector3(-0.05 + i * 0.2, 0.85, 0.287), dark, Build.AXIS_Z, false, 8)
	Build.box(self, Vector3(3.02, 0.26, 0.11), Vector3(0.48, 0.75, -0.335), bed_m)     # Rückwange
	Build.box(self, Vector3(3.02, 0.004, 0.11), Vector3(0.48, 0.881, -0.335), beige)
	_telescope = []
	for side in 2:
		var plates: Array[MeshInstance3D] = []
		for i in 6:
			var tp := Build.box(self, Vector3(1, 0.012, 0.05 - i * 0.002), Vector3(0, 0.92 - i * 0.004, -0.305), stainless)
			plates.append(tp)
			Build.box(tp, Vector3(1, 0.004, 0.006), Vector3(0, 0.007, 0.022 - i * 0.001), steel)   # Lamellenkante
		_telescope.append(plates)
	var link_m := Build.mat(Color(0.62, 0.6, 0.55), 0.45, 0.6)
	_chain = []
	for i in CHAIN_LINKS:
		var lk := Build.box(self, Vector3(CHAIN_PITCH * 0.92, 0.03, 0.05), Vector3.ZERO, link_m)
		Build.box(lk, Vector3(CHAIN_PITCH * 0.3, 0.032, 0.052), Vector3(CHAIN_PITCH * 0.35, 0, 0), a)
		_chain.append(lk)
	# Schalthebel links am Bett (Spindel Ein/Aus wie an der konventionellen Maschine)
	Build.box(self, Vector3(0.05, 0.05, 0.05), Vector3(-0.15, 0.69, 0.31), dark)
	Build.cyl(self, 0.008, 0.2, Vector3(-0.15, 0.69, 0.42), steel, Build.AXIS_Z)
	Build.sphere(self, 0.018, Vector3(-0.15, 0.69, 0.53), dark)
	# Auffangfläche für abgestochene Teile (eigene Physik-Ebene)
	var pan := Build.collider(self, Vector3(1.34, 0.06, 0.95), Vector3(0.75, 0.2, 0.06))
	pan.collision_layer = PIECE_LAYER
	pan.collision_mask = 0
	for z in [-0.42, 0.53]:
		var wall := Build.collider(self, Vector3(1.34, 0.4, 0.04), Vector3(0.75, 0.4, z))
		wall.collision_layer = PIECE_LAYER
		wall.collision_mask = 0

	# Spindelkasten: weiße Kabine bis unters Dach. Zum Arbeitsraum hin eine Stirnwand mit
	# hellgrau gerahmter Abdeckplatte, aus der die Spindelnase mit dem Futter kommt.
	Build.box(self, Vector3(0.86, 0.82, 0.76), Vector3(-0.62, 1.31, -0.02), w)
	Build.box(self, Vector3(0.87, 0.02, 0.77), Vector3(-0.62, 1.73, -0.02), g)
	var fx := -0.187
	Build.box(self, Vector3(0.003, 0.66, 0.74), Vector3(fx - 0.0015, 1.25, -0.02), beige)   # Stirnwand innen
	Build.box(self, Vector3(0.004, 0.40, 0.52), Vector3(fx, AXIS_H + 0.03, 0.0), Build.mat(Color(0.80, 0.77, 0.66), 0.6))
	for s in [-1.0, 1.0]:
		Build.box(self, Vector3(0.012, 0.035, 0.6), Vector3(fx + 0.004, AXIS_H + 0.03 + s * 0.2, 0.0), g)
		Build.box(self, Vector3(0.012, 0.44, 0.035), Vector3(fx + 0.004, AXIS_H + 0.03, s * 0.28), g)
	for i in 5:                                                                       # Schraubenreihe
		Build.cyl(self, 0.005, 0.006, Vector3(fx + 0.003, AXIS_H + 0.2, -0.2 + i * 0.1), dark, Build.AXIS_X, false, 8)
	Build.cyl(self, 0.085, 0.07, Vector3(-0.175, AXIS_H, 0), steel, Build.AXIS_X, false, 32)
	Build.cyl(self, 0.11, 0.012, Vector3(-0.19, AXIS_H, 0), g, Build.AXIS_X, false, 40)

	# Rotierende Teile: Futter, Backen, Werkstück
	spindle_pivot = Node3D.new()
	spindle_pivot.position = Vector3(0, AXIS_H, 0)
	add_child(spindle_pivot)
	# Reitstock + Bettschlitten/Planschlitten vorab anlegen, damit das Modell eingehängt werden kann
	var ts := Node3D.new()
	ts.position = Vector3(1.73, 0, 0)
	add_child(ts)
	carriage = Node3D.new()
	add_child(carriage)
	cross_slide = Node3D.new()
	carriage.add_child(cross_slide)
	model = LatheModel.new()
	if not model.build(spindle_pivot, cross_slide, ts, AXIS_H, 1.07):
		model = null
		Build.cyl(spindle_pivot, 0.16, 0.11, Vector3(-0.085, 0, 0), chuck_m, Build.AXIS_X, false, 48)
		Build.cyl(spindle_pivot, 0.12, 0.012, Vector3(-0.024, 0, 0), dark, Build.AXIS_X, false, 48)
		for i in 3:
			var jp := Node3D.new()
			jp.rotation.x = i * TAU / 3.0
			spindle_pivot.add_child(jp)
			var j := Build.box(jp, Vector3(0.03, 0.05, 0.028), Vector3(-0.015, 0.05, 0), Build.mat(Color(0.3, 0.31, 0.33), 0.4, 1.0))
			Build.box(jp, Vector3(0.02, 0.012, 0.03), Vector3(-0.04, 0.0, 0), dark).reparent(j, false)
			jaws.append(jp)
	workpiece_mi = MeshInstance3D.new()
	_wp_mat = StandardMaterial3D.new()
	_wp_mat.vertex_color_use_as_albedo = true
	_wp_mat.metallic = 1.0
	_wp_mat.roughness = 0.28
	_wp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	workpiece_mi.material_override = _wp_mat
	spindle_pivot.add_child(workpiece_mi)

	# Futterschutz: Schiebetür mit Sichtfenster zwischen zwei blauen Pfosten, Kopfteil und Griff.
	# Aufgeschoben steht sie über dem Spindelkasten, zugeschoben (door_t = 1) deckt sie den
	# Arbeitsraum ab. Fest vor dem Spindelkasten: das weiße Feld mit WEILER-Schriftzug und oben die
	# Laufschiene. Am linken Pfosten hängt das Bedienpult und fährt mit.
	var guard := Build.glass(Color(0.8, 0.85, 0.9, 0.22))
	Build.box(self, Vector3(DOOR_X1 - DOOR_X0, 0.46, 0.18), Vector3(DOOR_CX, 0.85, 0.47), w)
	Build.box(self, Vector3(DOOR_X1 - DOOR_X0, 0.014, 0.19), Vector3(DOOR_CX, 1.087, 0.47), g)
	_logo(self, Vector3(DOOR_X0 + 0.12, 0.86, 0.561), 0.06, blue)
	Build.label(self, "WEILER", Vector3(DOOR_CX + 0.07, 0.86, 0.561), 0.0017, Color(0.06, 0.18, 0.58), 64)
	# Laufschiene (Alu-Profil mit schwarzer Abdeckleiste) über die ganze Maschinenlänge
	Build.box(self, Vector3(3.16, 0.03, 0.04), Vector3(0.51, 1.735, 0.45), Build.mat(Color(0.78, 0.79, 0.8), 0.3, 0.8))
	Build.box(self, Vector3(3.16, 0.012, 0.03), Vector3(0.51, 1.756, 0.45), seam)
	_door = Node3D.new()
	add_child(_door)
	var door_parts: Array[GeometryInstance3D] = []
	for x in [DOOR_X0 + 0.03, DOOR_X1 - 0.03]:
		door_parts.append(Build.box(_door, Vector3(0.06, 0.56, 0.07), Vector3(x, 1.37, 0.525), blue))
	door_parts.append(Build.box(_door, Vector3(DOOR_X1 - DOOR_X0 - 0.12, 0.54, 0.008), Vector3(DOOR_CX, 1.37, 0.535), guard))
	door_parts.append(Build.box(_door, Vector3(DOOR_X1 - DOOR_X0 - 0.12, 0.025, 0.03), Vector3(DOOR_CX, 1.105, 0.54), w))
	door_parts.append(Build.box(_door, Vector3(DOOR_X1 - DOOR_X0, 0.07, 0.24), Vector3(DOOR_CX, 1.685, 0.44), w))
	door_parts.append(Build.box(_door, Vector3(DOOR_X1 - DOOR_X0, 0.004, 0.004), Vector3(DOOR_CX, 1.648, 0.561), seam))
	# Türgriff: bleibt auch sichtbar, wenn die Kamera die Tür ausblendet - an ihm zieht man die Tür
	Build.box(_door, Vector3(0.018, 0.42, 0.02), HANDLE_POS, dark)
	for n in door_parts:
		n.layers = DOOR_LAYER

	# Reitstock wie an der E50 HD: grauer Fuß auf den Bettbahnen mit schwarzen Klemmleisten, darauf
	# ein gebrochen weißes, kantiges Oberteil mit gefasten Längskanten. Vorne die verchromte Pinole,
	# hinten das Scheibenhandrad mit Kurbelgriff, oben Pinolen- und Reitstockklemmhebel.
	Build.box(ts, Vector3(0.40, 0.06, 0.46), Vector3(0, 0.96, 0), bed_m)
	for zz in [-0.215, 0.215]:
		for xx in [-0.17, 0.17]:
			Build.box(ts, Vector3(0.035, 0.03, 0.03), Vector3(xx, 0.945, zz), dark)
	Build.box(ts, Vector3(0.40, 0.004, 0.46), Vector3(0, 0.991, 0), seam)            # Trennfuge Fuß/Oberteil
	Build.box(ts, Vector3(0.36, 0.09, 0.30), Vector3(0.0, 1.04, 0), ts_w)           # Unterteil
	Build.box(ts, Vector3(0.2, 0.06, 0.16), Vector3(0.06, 1.11, 0), ts_w)            # Steg
	Build.box(ts, Vector3(0.44, 0.13, 0.17), Vector3(-0.02, AXIS_H, 0), ts_w)       # Pinolengehäuse
	Build.box(ts, Vector3(0.44, 0.03, 0.11), Vector3(-0.02, AXIS_H + 0.07, 0), ts_w)
	for sz in [-1.0, 1.0]:
		Build.box(ts, Vector3(0.44, 0.045, 0.03), Vector3(-0.02, AXIS_H + 0.062, sz * 0.068), ts_w, false, Vector3(sz * 0.785, 0, 0))
	Build.box(ts, Vector3(0.08, 0.06, 0.15), Vector3(-0.2, 1.07, 0), ts_w, false, Vector3(0, 0, -0.5))   # Schräge vorne
	Build.cyl(ts, 0.05, 0.012, Vector3(-0.246, AXIS_H, 0), stainless, Build.AXIS_X, false, 32)
	Build.cyl(ts, 0.036, 0.1, Vector3(-0.29, AXIS_H, 0), chrome, Build.AXIS_X, false, 32)  # Pinole
	if model == null:
		Build.cyl(ts, 0.025, 0.05, Vector3(-0.365, AXIS_H, 0), steel, Build.AXIS_X, false, 16, 0.002)
	for c in [Vector2(-0.16, 1.12), Vector2(-0.03, 1.06)]:                          # Lagerstopfen seitlich
		Build.cyl(ts, 0.022, 0.006, Vector3(c.x, c.y, 0.152), stainless, Build.AXIS_Z, false, 24)
		Build.cyl(ts, 0.004, 0.007, Vector3(c.x, c.y, 0.153), dark, Build.AXIS_Z, false, 8)
	Build.box(ts, Vector3(0.07, 0.05, 0.004), Vector3(0.12, 1.05, 0.151), Build.mat(Color(0.7, 0.7, 0.68), 0.6))   # Tasche mit Mutter
	Build.cyl(ts, 0.012, 0.02, Vector3(0.12, 1.045, 0.15), dark, Build.AXIS_Y, false, 6)
	Build.box(ts, Vector3(0.05, 0.02, 0.001), Vector3(0.12, AXIS_H + 0.0855, 0.04), Build.mat(Color(0.95, 0.95, 0.93), 0.6))  # Skalenschild
	# Pinolenklemmung: verchromter Hebel mit schwarzem Griff
	var ql := Node3D.new()
	ql.position = Vector3(-0.17, AXIS_H + 0.085, 0.05)
	ql.rotation = Vector3(0.0, 0.5, 0.55)
	ts.add_child(ql)
	Build.cyl(ql, 0.012, 0.02, Vector3.ZERO, chrome)
	Build.cyl(ql, 0.006, 0.17, Vector3(0.0, 0.0, 0.0), chrome, Build.AXIS_X).position.x = 0.085
	Build.cyl(ql, 0.012, 0.06, Vector3(0.19, 0.0, 0.0), dark, Build.AXIS_X, false, 16, 0.009)
	# Reitstockklemmung: gebogener Hebel hinten oben
	var cl := Node3D.new()
	cl.position = Vector3(0.12, AXIS_H + 0.08, -0.05)
	cl.rotation = Vector3(0.3, 0.0, -0.35)
	ts.add_child(cl)
	Build.cyl(cl, 0.007, 0.16, Vector3(0, 0.08, 0), chrome)
	Build.cyl(cl, 0.013, 0.07, Vector3(0, 0.19, 0), dark, Build.AXIS_Y, false, 16, 0.009)
	# Scheibenhandrad hinten
	Build.cyl(ts, 0.042, 0.02, Vector3(0.21, AXIS_H, 0), stainless, Build.AXIS_X, false, 32)
	Build.cyl(ts, 0.05, 0.012, Vector3(0.226, AXIS_H, 0), steel, Build.AXIS_X, false, 40)   # Skalenring
	var tw := Node3D.new()
	tw.position = Vector3(0.24, AXIS_H, 0)
	tw.rotation.y = PI / 2
	ts.add_child(tw)
	var rim := MeshInstance3D.new()
	var rt := TorusMesh.new()
	rt.inner_radius = 0.082
	rt.outer_radius = 0.1
	rt.rings = 48
	rim.mesh = rt
	rim.material_override = chrome
	rim.rotation.x = PI / 2
	tw.add_child(rim)
	Build.cyl(tw, 0.086, 0.012, Vector3(0, 0, -0.004), dark, Build.AXIS_Z, false, 40)
	Build.cyl(tw, 0.028, 0.03, Vector3(0, 0, 0.004), chrome, Build.AXIS_Z, false, 24)
	Build.cyl(tw, 0.011, 0.04, Vector3(0, 0.072, 0.024), dark, Build.AXIS_Z, false, 16)       # Kurbelgriff

	# Bettschlitten mit Schlosskasten: blaues Bedienfeld, Handrad links
	Build.box(carriage, Vector3(0.42, 0.09, 0.76), Vector3(0.1, 0.975, 0.0), saddle_m)
	for z in [0.385, -0.385]:
		Build.box(carriage, Vector3(0.44, 0.05, 0.02), Vector3(0.1, 0.95, z), dark)  # Abstreifer
	# Schlosskasten wie im Foto: Weiler-blau, hellgraues Tastenfeld, rechts der Vorschub-Drehknopf
	Build.box(carriage, Vector3(0.5, 0.34, 0.09), Vector3(0.1, 0.76, 0.42), blue)
	Build.box(carriage, Vector3(0.502, 0.006, 0.092), Vector3(0.1, 0.928, 0.42), saddle_m)
	Build.box(carriage, Vector3(0.3, 0.24, 0.02), Vector3(0.17, 0.78, 0.47), blue)
	Build.box(carriage, Vector3(0.27, 0.21, 0.004), Vector3(0.17, 0.78, 0.481), Build.mat(Color(0.83, 0.84, 0.85), 0.5))
	Build.cyl(carriage, 0.016, 0.01, Vector3(0.155, 0.745, 0.486), dark, Build.AXIS_Z, false, 16)   # Kreuzschalthebel
	Build.cyl(carriage, 0.005, 0.06, Vector3(0.155, 0.745, 0.515), steel, Build.AXIS_Z)
	Build.sphere(carriage, 0.012, Vector3(0.155, 0.745, 0.548), dark)
	Build.cyl(carriage, 0.03, 0.03, Vector3(0.22, 0.625, 0.48), dark, Build.AXIS_Z, false, 32)     # Vorschub-Drehknopf
	Build.cyl(carriage, 0.032, 0.006, Vector3(0.22, 0.625, 0.468), chrome, Build.AXIS_Z, false, 32)
	# gelber Schraubendreher auf dem Schlosskasten
	Build.cyl(carriage, 0.012, 0.09, Vector3(0.22, 0.942, 0.425), yellow, Build.AXIS_X, false, 12)
	Build.cyl(carriage, 0.003, 0.11, Vector3(0.12, 0.942, 0.425), steel, Build.AXIS_X, false, 8)
	var abtn := [[0.08, 0.86, red], [0.12, 0.86, green], [0.16, 0.86, dark], [0.20, 0.86, dark],
		[0.08, 0.815, dark], [0.12, 0.815, yellow], [0.16, 0.815, dark]]
	for b in abtn:
		Build.cyl(carriage, 0.011, 0.012, Vector3(b[0], b[1], 0.488), b[2], Build.AXIS_Z, false, 16)
	Build.cyl(carriage, 0.02, 0.01, Vector3(0.1, 0.725, 0.487), yellow, Build.AXIS_Z)   # Not-Halt
	Build.cyl(carriage, 0.015, 0.02, Vector3(0.1, 0.725, 0.497), red, Build.AXIS_Z)
	for k in [Vector2(0.2, 0.73), Vector2(0.26, 0.82), Vector2(0.26, 0.73)]:
		Build.cyl(carriage, 0.018, 0.02, Vector3(k.x, k.y, 0.49), dark, Build.AXIS_Z, false, 20)
		Build.box(carriage, Vector3(0.004, 0.014, 0.004), Vector3(k.x, k.y + 0.008, 0.501), w)
	hw_z = Node3D.new()
	hw_z.position = Vector3(-0.06, 0.74, 0.48)
	carriage.add_child(hw_z)
	_handwheel(hw_z, 0.085, chrome, dark)
	Build.cyl(carriage, 0.03, 0.03, Vector3(-0.06, 0.74, 0.47), chrome, Build.AXIS_Z)   # Skalenring
	Build.cyl(carriage, 0.008, 0.08, Vector3(0.33, 0.65, 0.5), dark, Build.AXIS_Z)      # Schlossmutterhebel
	Build.sphere(carriage, 0.016, Vector3(0.33, 0.65, 0.545), red)

	# Planschlitten mit Schnellwechsel-Werkzeughalter
	Build.box(cross_slide, Vector3(0.22, 0.05, 0.36), Vector3(0.07, 1.045, 0.15), Build.mat(Color(0.56, 0.58, 0.6), 0.4, 0.3))
	if model == null:
		Build.box(cross_slide, Vector3(0.14, 0.035, 0.16), Vector3(0.03, 1.088, 0.14), g)
		# Schnellwechsel-Stahlhalter (Multifix-Art)
		var post_m := Build.mat(Color(0.45, 0.47, 0.5), 0.35, 0.8)
		Build.box(cross_slide, Vector3(0.07, 0.06, 0.06), Vector3(0.006, 1.135, 0.185), post_m)
		Build.cyl(cross_slide, 0.01, 0.03, Vector3(0.006, 1.18, 0.185), chrome)
		Build.cyl(cross_slide, 0.004, 0.07, Vector3(0.006, 1.19, 0.22), dark, Build.AXIS_Z)
	for i in LatheTools.count():
		var tn := _build_tool_visual(LatheTools.get_tool(i))
		cross_slide.add_child(tn)
		tool_nodes.append(tn)
	hw_x = Node3D.new()
	hw_x.position = Vector3(0.07, 1.045, 0.36)
	cross_slide.add_child(hw_x)
	_handwheel(hw_x, 0.06, chrome, dark)
	# KSS-Düse am Gelenkschlauch, der hinter dem Werkzeughalter hochkommt
	_hose(cross_slide, [Vector3(0.11, 1.07, -0.09), Vector3(0.11, 1.26, -0.09), Vector3(0.09, 1.36, -0.06),
		Vector3(0.04, 1.40, -0.02), Vector3(-0.01, 1.38, 0.03), Vector3(-0.03, 1.33, 0.06)],
		0.007, Build.mat(Color(0.62, 0.63, 0.65), 0.35, 0.9))
	Build.cyl(cross_slide, 0.005, 0.08, Vector3(-0.03, AXIS_H + 0.11, 0.07), Build.mat(Color(0.15, 0.4, 0.8), 0.5), Build.AXIS_Y)
	Build.cyl(cross_slide, 0.004, 0.06, Vector3(-0.03, AXIS_H + 0.07, 0.05), Build.mat(Color(0.95, 0.5, 0.1), 0.5), Build.AXIS_Y, false, 12, 0.002)

	# Späne
	chips = CPUParticles3D.new()
	chips.position = Vector3(0.0, AXIS_H + 0.004, 0.002)
	chips.emitting = false
	chips.amount = 70
	chips.lifetime = 1.0
	chips.direction = Vector3(0.3, 1.0, 0.7)
	chips.spread = 35
	chips.initial_velocity_min = 0.6
	chips.initial_velocity_max = 1.6
	chips.angular_velocity_min = -720
	chips.angular_velocity_max = 720
	chips.scale_amount_min = 0.6
	chips.scale_amount_max = 1.4
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.006, 0.0015, 0.003)
	chip_mesh.material = Build.mat(Color(0.35, 0.4, 0.62), 0.3, 1.0)
	chips.mesh = chip_mesh
	cross_slide.add_child(chips)

	coolant_fx = CPUParticles3D.new()
	coolant_fx.position = Vector3(-0.03, AXIS_H + 0.04, 0.04)
	coolant_fx.emitting = false
	coolant_fx.amount = 80
	coolant_fx.lifetime = 0.35
	coolant_fx.direction = Vector3(0.4, -1.0, -0.5)
	coolant_fx.spread = 8
	coolant_fx.initial_velocity_min = 0.5
	coolant_fx.initial_velocity_max = 0.7
	var drop := SphereMesh.new()
	drop.radius = 0.0025
	drop.height = 0.005
	var cm := Build.mat(Color(0.92, 0.95, 1.0, 0.55), 0.05)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = cm
	coolant_fx.mesh = drop
	cross_slide.add_child(coolant_fx)

	# Verkleidung: Rückwand, rechte Stirnwand, Dach mit LED-Leuchten
	Build.box(self, Vector3(2.24, 0.74, 0.02), Vector3(0.94, 1.29, -0.40), beige)
	Build.box(self, Vector3(2.24, 0.004, 0.004), Vector3(0.94, 1.2, -0.388), Build.mat(Color(0.7, 0.66, 0.53), 0.8))
	Build.box(self, Vector3(0.05, 1.14, 0.84), Vector3(2.06, 1.15, 0.0), w)             # Stirnwand
	Build.box(self, Vector3(0.004, 0.72, 0.76), Vector3(2.033, 1.29, -0.02), beige)      # innen cremefarben
	Build.box(self, Vector3(0.055, 0.004, 0.84), Vector3(2.06, 0.95, 0.0), seam)
	# Dach: liegt auf eigener Sichtebene, damit die Bedienkamera von oben hindurchsehen kann
	var canopy: Array[GeometryInstance3D] = [
		Build.box(self, Vector3(2.30, 0.03, 0.44), Vector3(0.93, 1.705, -0.2), w),
		Build.box(self, Vector3(2.30, 0.13, 0.03), Vector3(0.93, 1.655, 0.02), w),
		Build.box(self, Vector3(2.30, 0.006, 0.006), Vector3(0.93, 1.592, 0.036), seam),
	]
	var led := Build.emissive(Color(0.95, 0.97, 1.0), 2.5)
	var alu := Build.mat(Color(0.72, 0.73, 0.75), 0.35, 0.8)
	for x in [0.42, 1.38]:                          # zwei LED-Leuchten unter dem Dach
		canopy.append(Build.box(self, Vector3(0.66, 0.022, 0.06), Vector3(x, 1.678, -0.05), alu))
		canopy.append(Build.box(self, Vector3(0.62, 0.006, 0.04), Vector3(x, 1.665, -0.05), led))
	canopy.append(Build.label(self, "E50", Vector3(1.46, 1.655, 0.037), 0.0015, Color(0.06, 0.18, 0.58), 64))
	canopy.append(Build.label(self, "HD", Vector3(1.585, 1.678, 0.037), 0.0008, Color(0.35, 0.75, 0.2), 64))
	for n in canopy:
		n.layers = CANOPY_LAYER
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Schaltschrank hinter dem Spindelkasten
	Build.box(self, Vector3(0.75, 1.7, 0.35), Vector3(-0.65, 0.85, -0.6), w)
	Build.box(self, Vector3(0.752, 0.06, 0.352), Vector3(-0.65, 0.03, -0.6), red)
	Build.box(self, Vector3(0.006, 1.6, 0.01), Vector3(-0.65, 0.87, -0.42), seam)
	Build.box(self, Vector3(0.12, 0.1, 0.01), Vector3(-0.45, 1.45, -0.42), yellow)
	Build.cyl(self, 0.04, 0.03, Vector3(-0.9, 1.1, -0.41), dark, Build.AXIS_Z)
	Build.collider(self, Vector3(0.75, 1.7, 0.35), Vector3(-0.65, 0.85, -0.6))

	# Bedienpult (Zyklensteuerung) senkrecht und angewinkelt am linken Türpfosten: Bildschirm
	# mit Softkeys und Tastenblock, Maschinentastenfeld darunter, Tastaturablage unten
	var hinge := Vector3(DOOR_X0, PULT_Y0, 0.56)
	Build.box(_door, Vector3(0.04, 0.72, 0.05), hinge + Vector3(-0.015, -0.06, -0.02), g)   # Halteschiene
	for y in [0.2, -0.36]:
		Build.box(_door, Vector3(0.06, 0.06, 0.06), hinge + Vector3(-0.02, y, -0.01), dark)
	var cp := Node3D.new()
	cp.rotation.y = PULT_ANGLE
	cp.position = hinge - cp.basis * Vector3(PULT_X + PULT_W * 0.5, 0, -0.04)
	_door.add_child(cp)
	_pult = cp
	var pg := Build.mat(Color(0.82, 0.84, 0.85), 0.45)
	Build.box(cp, Vector3(PULT_W, PULT_H, 0.08), Vector3(PULT_X, PULT_Y, 0), pg)
	Build.box(cp, Vector3(PULT_W - 0.03, 0.5, 0.004), Vector3(PULT_X, 0.03, 0.041), Build.mat(Color(0.30, 0.32, 0.35), 0.5))
	Build.box(cp, Vector3(SCREEN_SIZE.x + 0.02, SCREEN_SIZE.y + 0.02, 0.004), Vector3(SCREEN_X, 0.05, 0.044), Build.mat(Color(0.03, 0.03, 0.035), 0.6))
	_build_screen(cp, Vector3(SCREEN_X, 0.05, 0.0465))
	_logo(cp, Vector3(0.215, 0.258, 0.044), 0.016, w)
	Build.label(cp, "WEILER", Vector3(0.27, 0.258, 0.044), 0.00045, Color(0.95, 0.95, 0.95), 48)
	var key_m := Build.mat(Color(0.75, 0.77, 0.79), 0.5)
	for r in 9:                                         # Tastenblock rechts
		for c in 3:
			var km := yellow if r == 0 and c == 2 else key_m
			Build.box(cp, Vector3(0.022, 0.018, 0.008), Vector3(0.235 + c * 0.03, 0.2 - r * 0.033, 0.046), km)
	for i in 10:                                        # Softkeys unter dem Bildschirm
		Build.box(cp, Vector3(0.03, 0.014, 0.008), Vector3(SCREEN_X - 0.2 + i * 0.0445, -0.185, 0.046), key_m)
	# Maschinentastenfeld
	Build.box(cp, Vector3(PULT_W - 0.03, 0.22, 0.004), Vector3(PULT_X, -0.36, 0.041), Build.mat(Color(0.88, 0.89, 0.9), 0.5))
	for r in 3:
		for c in 8:
			if r == 2 and c < 2:
				continue
			Build.cyl(cp, 0.011, 0.012, Vector3(-0.16 + c * 0.055, -0.28 - r * 0.055, 0.047), dark, Build.AXIS_Z, false, 16)
	Build.cyl(cp, 0.018, 0.02, Vector3(-0.25, -0.29, 0.045), green, Build.AXIS_Z)
	Build.cyl(cp, 0.018, 0.02, Vector3(-0.25, -0.345, 0.045), dark, Build.AXIS_Z)
	Build.cyl(cp, 0.035, 0.012, Vector3(-0.235, -0.425, 0.045), yellow, Build.AXIS_Z)
	Build.cyl(cp, 0.026, 0.035, Vector3(-0.235, -0.425, 0.06), red, Build.AXIS_Z)
	Build.cyl(cp, 0.03, 0.02, Vector3(-0.08, -0.395, 0.045), chrome, Build.AXIS_Z)
	_led_on = Build.emissive(Color(0.1, 1.0, 0.2), 3.0)
	_led_off = Build.mat(Color(0.05, 0.2, 0.05), 0.5)
	spindle_led = Build.cyl(cp, 0.007, 0.01, Vector3(-0.2, -0.29, 0.045), _led_off, Build.AXIS_Z)
	# Tastaturablage
	var shelf := Build.box(cp, Vector3(PULT_W, 0.035, 0.24), Vector3(PULT_X, -0.52, 0.1), pg)
	shelf.rotation.x = 0.08
	Build.box(shelf, Vector3(0.36, 0.006, 0.12), Vector3(-0.07, 0.019, 0.02), Build.mat(Color(0.32, 0.34, 0.37), 0.6))
	Build.box(shelf, Vector3(0.12, 0.004, 0.1), Vector3(0.19, 0.019, 0.02), Build.mat(Color(0.7, 0.72, 0.74), 0.3))

	_build_details()

	# Arbeitsleuchte im Dach (die LED-Streifen sind nur Deko)
	lamp = SpotLight3D.new()
	lamp.position = Vector3(0.0, 1.64, -0.12)
	lamp.light_energy = 2.5
	lamp.spot_range = 2.2
	lamp.spot_angle = 40
	lamp.light_color = Color(1.0, 0.97, 0.93)
	lamp.shadow_enabled = true
	add_child(lamp)
	lamp.look_at(to_global(Vector3(0.15, AXIS_H, 0.05)))

	# Kollision + Interaktion
	var hit := Build.collider(self, Vector3(3.07, 1.62, 1.0), Vector3(0.48, 0.81, 0.08))
	hit.set_meta("interact", self)
	var hit2 := Build.collider(cp, Vector3(PULT_W, PULT_H, 0.1), Vector3(PULT_X, PULT_Y, 0))
	var pt := PultTarget.new()
	pt.lathe = self
	add_child(pt)
	hit2.set_meta("interact", pt)   # E aufs Pult: gleich in die Pultansicht
	# Tür und schwarzer Hebel: Linksklick mit dem Fadenkreuz (stehen etwas vor der Maschinenhülle,
	# damit der Blickstrahl sie zuerst trifft; der Hebel noch vor der Tür)
	var dt := DoorTarget.new()
	dt.lathe = self
	add_child(dt)
	var dhit := Build.collider(_door, Vector3(DOOR_X1 - DOOR_X0, 0.62, 0.06), Vector3(DOOR_CX, 1.40, 0.57))
	dhit.set_meta("interact", dt)
	var lt := DoorTarget.new()
	lt.lathe = self
	lt.lever = true
	add_child(lt)
	var lhit := Build.collider(_door, Vector3(0.06, 0.46, 0.06), HANDLE_POS + Vector3(0, 0, 0.03))
	lhit.set_meta("interact", lt)

	op_cam = Camera3D.new()
	op_cam.fov = 55
	op_cam.near = 0.002
	add_child(op_cam)


## Teile nach den Fotos der E50 HD im Betrieb: aufgeklappter Futterschutz, Späneförderer mit
## Spänewagen, Holzrost vor der Maschine, Spiral-Luftschlauch, Gelenkleuchte und Aushang.
func _build_details() -> void:
	var w := Build.mat(Color(0.90, 0.91, 0.91), 0.42)
	var beige := Build.mat(Color(0.84, 0.80, 0.66), 0.8)
	var dark := Build.mat(Color(0.07, 0.07, 0.08), 0.75)
	var steel := Build.mat(Color(0.72, 0.73, 0.75), 0.28, 1.0)
	var conv_m := Build.mat(Color(0.33, 0.35, 0.37), 0.6, 0.2)

	# Futterschutz: weiße Haube, innen cremefarben, nach hinten oben aufgeklappt. Eigene Sichtebene
	# wie die Tür, damit er der Bedienkamera nicht im Weg steht.
	var hood := Node3D.new()
	hood.position = Vector3(-0.08, AXIS_H + 0.22, -0.12)
	hood.rotation.x = -0.55
	add_child(hood)
	var hood_parts: Array[GeometryInstance3D] = [
		Build.box(hood, Vector3(0.22, 0.01, 0.34), Vector3(0, 0.0, 0.17), w),
		Build.box(hood, Vector3(0.21, 0.004, 0.33), Vector3(0, -0.007, 0.17), beige),
		Build.box(hood, Vector3(0.22, 0.25, 0.01), Vector3(0, -0.125, 0.34), w),
		Build.box(hood, Vector3(0.21, 0.24, 0.004), Vector3(0, -0.125, 0.333), beige),
		Build.box(hood, Vector3(0.02, 0.012, 0.016), Vector3(0, -0.2, 0.352), dark),
		Build.cyl(hood, 0.012, 0.22, Vector3.ZERO, steel, Build.AXIS_X),
	]
	for sx in [-0.105, 0.105]:
		hood_parts.append(Build.box(hood, Vector3(0.01, 0.12, 0.34), Vector3(sx, -0.06, 0.17), w))
		hood_parts.append(Build.box(hood, Vector3(0.01, 0.25, 0.08), Vector3(sx, -0.125, 0.3), w))
	for n in hood_parts:
		n.layers = DOOR_LAYER

	# Späneförderer: steigt am rechten Maschinenende schräg an und wirft in den Spänewagen
	periphery = Node3D.new()
	periphery.name = "Peripherie"
	add_child(periphery)
	var conv := Build.box(periphery, Vector3(1.13, 0.16, 0.36), Vector3(2.5, 0.6, 0.05), conv_m, false, Vector3(0, 0, 0.666))
	Build.box(conv, Vector3(1.13, 0.012, 0.3), Vector3(0, 0.086, 0), Build.mat(Color(0.42, 0.44, 0.46), 0.5, 0.3))
	for x in [-0.3, 0.1, 0.45]:
		Build.box(conv, Vector3(0.012, 0.165, 0.365), Vector3(x, 0, 0), Build.mat(Color(0.2, 0.21, 0.22), 0.6))
	Build.box(periphery, Vector3(0.26, 0.24, 0.38), Vector3(3.0, 0.98, 0.05), conv_m)
	Build.box(periphery, Vector3(0.2, 0.14, 0.3), Vector3(3.1, 0.82, 0.05), conv_m)
	Build.cyl(periphery, 0.065, 0.16, Vector3(2.98, 1.0, 0.32), Build.mat(Color(0.2, 0.32, 0.55), 0.5), Build.AXIS_Z)   # Antrieb
	for x in [2.3, 2.75]:
		var leg_h: float = 0.25 + (float(x) - 2.06) * 0.78
		Build.box(periphery, Vector3(0.04, leg_h, 0.04), Vector3(x, leg_h * 0.5, -0.1), dark)
		Build.box(periphery, Vector3(0.04, leg_h, 0.04), Vector3(x, leg_h * 0.5, 0.2), dark)
	Build.collider(periphery, Vector3(0.95, 1.1, 0.4), Vector3(2.55, 0.55, 0.05))

	# Spänewagen mit Gabeltaschen, voll mit Wirrspänen
	var bin := Node3D.new()
	bin.position = Vector3(3.22, 0, 0.05)
	periphery.add_child(bin)
	var bin_m := Build.mat(Color(0.30, 0.32, 0.34), 0.55, 0.3)
	Build.box(bin, Vector3(0.64, 0.02, 0.76), Vector3(0, 0.1, 0), bin_m)
	for sx in [-1.0, 1.0]:
		Build.box(bin, Vector3(0.02, 0.62, 0.76), Vector3(sx * 0.31, 0.41, 0), bin_m)
		Build.box(bin, Vector3(0.64, 0.62, 0.02), Vector3(0, 0.41, sx * 0.37), bin_m)
		Build.box(bin, Vector3(0.12, 0.09, 0.78), Vector3(sx * 0.18, 0.045, 0), dark)       # Gabeltaschen
	Build.box(bin, Vector3(0.66, 0.025, 0.025), Vector3(0, 0.72, 0.38), bin_m)
	var chip_m := Build.mat(Color(0.56, 0.57, 0.6), 0.35, 1.0)
	Build.box(bin, Vector3(0.6, 0.02, 0.72), Vector3(0, 0.52, 0), Build.mat(Color(0.38, 0.39, 0.41), 0.6, 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 50
	var curl := TorusMesh.new()
	curl.inner_radius = 0.012
	curl.outer_radius = 0.016
	curl.rings = 10
	curl.ring_segments = 4
	for i in 70:
		var c := MeshInstance3D.new()
		c.mesh = curl
		c.material_override = chip_m
		c.position = Vector3(rng.randf_range(-0.27, 0.27), 0.53 + rng.randf() * 0.04, rng.randf_range(-0.33, 0.33))
		c.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		c.scale = Vector3(1.0, rng.randf_range(1.0, 3.0), 1.0)
		bin.add_child(c)
	Build.collider(bin, Vector3(0.64, 0.74, 0.76), Vector3(0, 0.37, 0))

	# Holzrost vor der Maschine
	var grate_m := Build.mat(Color(0.17, 0.15, 0.13), 0.9)
	for i in 8:
		Build.box(self, Vector3(1.9, 0.022, 0.07), Vector3(0.6, 0.027, 0.66 + i * 0.1), grate_m)
	for i in 7:
		Build.box(self, Vector3(0.05, 0.016, 0.78), Vector3(-0.3 + i * 0.3, 0.008, 1.01), grate_m)

	# Spiral-Luftschlauch mit Blaspistole vorne rechts am Bett
	var air := Build.mat(Color(0.12, 0.32, 0.8), 0.4)
	Build.box(self, Vector3(0.03, 0.03, 0.03), Vector3(1.9, 0.88, 0.3), dark)
	_rod(self, Vector3(1.9, 0.88, 0.31), Vector3(1.9, 0.88, 0.5), 0.005, air)
	var coil := TorusMesh.new()
	coil.inner_radius = 0.045
	coil.outer_radius = 0.054
	coil.rings = 20
	coil.ring_segments = 6
	for i in 15:
		var r := MeshInstance3D.new()
		r.mesh = coil
		r.material_override = air
		r.position = Vector3(1.9 + sin(i * 0.7) * 0.004, 0.86 - i * 0.026, 0.5)
		r.rotation = Vector3(0.18, 0.0, 0.12 * (1.0 if i % 2 == 0 else -1.0))
		add_child(r)
	_rod(self, Vector3(1.9, 0.47, 0.5), Vector3(1.88, 0.38, 0.52), 0.005, air)
	Build.box(self, Vector3(0.03, 0.08, 0.025), Vector3(1.88, 0.34, 0.52), Build.mat(Color(0.55, 0.56, 0.58), 0.4, 0.8))
	Build.cyl(self, 0.004, 0.09, Vector3(1.88, 0.255, 0.52), steel)

	# Gelenkleuchte auf dem Spindelkasten und Aushang an der Seite
	_rod(self, Vector3(-0.95, 1.74, 0.28), Vector3(-0.98, 2.02, 0.22), 0.012, dark)
	_rod(self, Vector3(-0.98, 2.02, 0.22), Vector3(-0.86, 2.12, 0.3), 0.01, dark)
	Build.sphere(self, 0.018, Vector3(-0.98, 2.02, 0.22), dark)
	Build.cyl(self, 0.04, 0.03, Vector3(-0.95, 1.745, 0.28), dark)
	Build.cyl(self, 0.028, 0.08, Vector3(-0.83, 2.1, 0.32), dark, Build.AXIS_X, false, 16, 0.02)
	var paper := Build.box(self, Vector3(0.002, 0.30, 0.21), Vector3(-1.052, 1.45, 0.16), Build.mat(Color(0.96, 0.96, 0.94), 0.9))
	for i in 9:
		Build.box(paper, Vector3(0.002, 0.006, 0.15 - (i % 3) * 0.03), Vector3(-0.0005, 0.11 - i * 0.025, -0.01), Build.mat(Color(0.35, 0.35, 0.38), 0.9))


## Gerader Stab von p0 nach p1.
func _rod(parent: Node3D, p0: Vector3, p1: Vector3, r: float, m: Material) -> MeshInstance3D:
	var d := p1 - p0
	var seg := Build.cyl(parent, r, d.length(), (p0 + p1) * 0.5, m, Build.AXIS_Y, false, 12)
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	seg.basis = Basis(x, y, x.cross(y))
	return seg


## Teleskopabdeckung und Energiekette hinter dem Bett an die Lage des Bettschlittens anpassen.
func _layout_bed_covers() -> void:
	if _telescope.size() < 2 or carriage == null:
		return
	var cx := carriage.position.x
	var spans := [Vector2(-0.18, cx - 0.11), Vector2(cx + 0.31, 2.03)]
	for side in 2:
		var sp: Vector2 = spans[side]
		var plates: Array = _telescope[side]
		var n := plates.size()
		var length := maxf(sp.y - sp.x, 0.06)
		var pl := maxf(length / n * 1.25, 0.06)
		for i in n:
			var tp := plates[i] as MeshInstance3D
			# höchste Lamelle am Schlitten, die kleineren schieben sich darunter
			var k := (n - 1 - i) if side == 0 else i
			var x0 := sp.x + (length - pl) * float(k) / float(n - 1)
			tp.scale.x = pl
			tp.position.x = x0 + pl * 0.5
	# Energiekette: Untertrum liegt ab CHAIN_FIX in der Rinne, Obertrum hängt am Schlitten
	if _chain.is_empty():
		return
	var m := cx + 0.31
	var loop := (CHAIN_FIX + m + CHAIN_LEN) * 0.5
	var y_lo := 0.895
	var y_hi := y_lo + 2.0 * CHAIN_R
	var lower := loop - CHAIN_FIX
	var arc := PI * CHAIN_R
	for i in _chain.size():
		var s := i * CHAIN_PITCH
		var lk := _chain[i]
		var p: Vector3
		var ang := 0.0
		if s < lower:
			p = Vector3(CHAIN_FIX + s, y_lo, -0.36)
		elif s < lower + arc:
			ang = (s - lower) / CHAIN_R
			p = Vector3(loop + sin(ang) * CHAIN_R, y_lo + CHAIN_R - cos(ang) * CHAIN_R, -0.36)
		else:
			ang = PI
			p = Vector3(loop - (s - lower - arc), y_hi, -0.36)
		lk.visible = p.x >= m - 0.02 or s < lower + arc
		lk.position = p
		lk.rotation.z = ang


## Bildschirm am Bedienpult: Bedienoberfläche der Zyklensteuerung (CncScreen), in einem
## SubViewport gerendert und auf eine Fläche im Pult gelegt. Mausklicks auf die Fläche leitet
## _screen_input weiter, Tastatureingaben in Eingabefelder _input.
func _build_screen(cp: Node3D, pos: Vector3) -> void:
	screen_vp = SubViewport.new()
	screen_vp.size = Vector2i(SCREEN_UI * SCREEN_SCALE)
	screen_vp.transparent_bg = false
	screen_vp.gui_embed_subwindows = true       # Auswahllisten öffnen im Bildschirm, nicht als Fenster
	screen_vp.handle_input_locally = true
	screen_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(screen_vp)
	screen = load("res://scripts/ui/cnc_screen.gd").new()
	screen.lathe = self
	screen.size = SCREEN_UI
	screen.scale = Vector2.ONE * SCREEN_SCALE
	screen_vp.add_child(screen)

	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = screen_vp.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material = m
	_screen_mi = MeshInstance3D.new()
	_screen_mi.mesh = quad
	_screen_mi.position = pos
	_screen_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cp.add_child(_screen_mi)


## Mausposition (Fenster) -> Pixel auf dem Pult-Bildschirm, oder (-1, -1) wenn daneben.
## clamp: Position auf den Rand begrenzen (Schieber ziehen über den Rand hinaus).
func screen_pixel(mouse_pos: Vector2, clamp := false) -> Vector2:
	if _screen_mi == null or op_cam == null or not _screen_mi.is_inside_tree():
		return Vector2(-1, -1)
	var inv := _screen_mi.global_transform.affine_inverse()
	var o := inv * op_cam.project_ray_origin(mouse_pos)
	var d := inv.basis * op_cam.project_ray_normal(mouse_pos)
	if absf(d.z) < 1e-6:
		return Vector2(-1, -1)
	var t := -o.z / d.z
	if t <= 0.0:
		return Vector2(-1, -1)
	var p := o + d * t
	var uv := Vector2(p.x / SCREEN_SIZE.x + 0.5, 0.5 - p.y / SCREEN_SIZE.y)
	if clamp:
		uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
	elif uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv * Vector2(screen_vp.size)


## Linke Maustaste und Mausbewegung über dem Pult-Bildschirm an dessen Menü weitergeben.
## Gibt true zurück, wenn das Ereignis dort verbraucht wurde.
func _screen_input(event: InputEvent) -> bool:
	if screen_vp == null or not (event is InputEventMouse):
		return false
	var me := event as InputEventMouse
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		return false
	var mb := event as InputEventMouseButton
	var is_left := mb != null and mb.button_index == MOUSE_BUTTON_LEFT
	var is_wheel := mb != null and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN)
	if mb != null and not is_left and not is_wheel:
		return false
	if is_wheel and mb.ctrl_pressed:
		return false
	var px := screen_pixel(me.position, _screen_drag)
	if px.x < 0.0:
		if is_left and mb.pressed:
			screen_vp.gui_release_focus()    # Klick daneben beendet die Eingabe
		return false
	if is_left:
		_screen_drag = event.is_pressed()
	push_screen_event(event, px)
	return is_left or is_wheel or _screen_drag


## Tastatur in ein Eingabefeld des Pult-Bildschirms, solange dort eines bearbeitet wird.
func _input(event: InputEvent) -> void:
	if not operating or screen_vp == null or not (event is InputEventKey):
		return
	var f := screen_vp.gui_get_focus_owner()
	if not (f is LineEdit):
		return
	var k := event as InputEventKey
	if k.pressed and k.keycode == KEY_ESCAPE:
		screen_vp.gui_release_focus()
	else:
		screen_vp.push_input(event, true)
	get_viewport().set_input_as_handled()


## Ereignis an Pixelposition px in das Pult-Menü geben (auch für Tests).
func push_screen_event(event: InputEvent, px: Vector2) -> void:
	var ev := event.duplicate() as InputEventMouse
	ev.position = px
	ev.global_position = px
	screen_vp.push_input(ev, true)


## Kamera auf das Bedienpult richten (bildschirmfüllend), bzw. zurück zur letzten Ansicht.
func toggle_panel_view() -> void:
	if _panel_view:
		set_view("back")
		return
	set_view("panel")


func _build_tool_visual(t: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.visible = false
	var poly: PackedVector2Array = t["poly"]
	var insert := MeshInstance3D.new()
	insert.mesh = LatheTools.extrude(poly, AXIS_H - 0.0045, AXIS_H)
	insert.material_override = Build.mat(t["color"], 0.3, 1.0)
	n.add_child(insert)
	# Klemmhalter-Schaft bis in den Schnellwechselhalter
	var zmin: float = t["zmin"]
	var zmax: float = t["zmax"]
	var top: float = t["top"]
	var w := clampf(zmax - zmin, 3.0, 18.0)
	var zc := (zmin + zmax) * 0.5
	w = minf(w, 12.0)
	var start := top * 0.55
	var holder := Build.mat(Color(0.32, 0.34, 0.38), 0.4, 0.8)
	var hn: Node3D = null
	if model:
		var sp := _shank_span(t)
		hn = model.make_holder(AXIS_H, (sp.x + sp.y) * 0.5, float(t["ext"]))
		if hn:
			# Schaft in den Maßen des Modell-Plattenhalters, im Klemmhalter aus dem Modell.
			# Vorne liegt er unter der Platte, dahinter so hoch wie der Modell-Schaft.
			var sb: AABB = model.shank_box
			var sw := sp.y - sp.x
			var sx := (sp.x + sp.y) * 0.5 * 0.001
			var y0 := AXIS_H + sb.position.y * 0.001
			var seat := AXIS_H - 0.0045
			var front := minf(top + 2.0, sb.end.z - 5.0)
			Build.box(n, Vector3(sw * 0.001, seat - y0, (front - start) * 0.001),
				Vector3(sx, (y0 + seat) * 0.5, (start + front) * 0.5 * 0.001), holder)
			var y1 := AXIS_H + sb.end.y * 0.001
			var back := sb.end.z + float(t["ext"])
			Build.box(n, Vector3(sw * 0.001, y1 - y0, (back - front) * 0.001),
				Vector3(sx, (y0 + y1) * 0.5, (front + back) * 0.5 * 0.001), holder)
			n.add_child(hn)
	if hn == null:
		var length := (model.shank_end_mm if model else 175.0) + float(t["ext"]) - start
		Build.box(n, Vector3(w * 0.001, 0.012, length * 0.001), Vector3(zc * 0.001, AXIS_H - 0.0105, (start + length * 0.5) * 0.001), holder)
	# Spannpratze über der Platte
	if t["id"] != "T6":
		Build.box(n, Vector3(w * 0.0008, 0.004, 0.006), Vector3(zc * 0.001, AXIS_H + 0.002, (top * 0.7) * 0.001), holder)
	return n


## Vereinfachtes Firmenzeichen: Quadratrahmen mit Schrägbalken (size = Kantenlänge, m).
func _logo(parent: Node3D, pos: Vector3, size: float, m: Material) -> void:
	var t := size * 0.14
	for s in [-1.0, 1.0]:
		Build.box(parent, Vector3(size, t, 0.002), pos + Vector3(0, s * (size - t) * 0.5, 0), m)
		Build.box(parent, Vector3(t, size, 0.002), pos + Vector3(s * (size - t) * 0.5, 0, 0), m)
	Build.box(parent, Vector3(size * 1.25, t, 0.002), pos, m).rotation.z = PI / 4


## Gelenkschlauch (KSS) aus Gliedern entlang der Punkte pts.
func _hose(parent: Node3D, pts: Array, r: float, m: Material) -> void:
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var d := p1 - p0
		var seg := Build.cyl(parent, r, d.length(), (p0 + p1) * 0.5, m, Build.AXIS_Y, false, 10)
		var y := d.normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		seg.basis = Basis(x, y, x.cross(y))
		var n := int(d.length() / 0.02)
		for k in n:
			Build.sphere(parent, r * 1.2, p0 + d * (float(k) + 0.5) / n, m)


func _handwheel(parent: Node3D, r: float, ring_m: Material, knob_m: Material) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.008
	tm.outer_radius = r
	ring.mesh = tm
	ring.material_override = ring_m
	ring.rotation.x = PI / 2
	parent.add_child(ring)
	Build.cyl(parent, 0.018, 0.03, Vector3.ZERO, ring_m, Build.AXIS_Z)
	for i in 3:
		var sp := Build.box(parent, Vector3(0.008, r, 0.006), Vector3.ZERO, ring_m)
		sp.rotation.z = i * TAU / 3.0
		sp.position = Vector3(cos(i * TAU / 3.0 + PI / 2), sin(i * TAU / 3.0 + PI / 2), 0) * r * 0.5
	Build.cyl(parent, 0.007, 0.05, Vector3(0, -r + 0.01, 0.03), knob_m, Build.AXIS_Z)


# ======================================================================= Werkzeug

## Halterplatz einschwenken (Kopf indexieren). Gibt false zurück, wenn es nicht geht.
## Von Hand (nicht silent) wird das Einschwenken animiert: Spannhebel lösen, Kopf 90° bzw. 180°
## drehen, klemmen. Bei 180° dreht der Kopf in die Richtung, in der unterwegs nichts anstößt.
func index_slot(slot: int, silent := false) -> bool:
	slot = posmod(slot, SLOTS)
	if slot == active_slot and not silent:
		return true
	if str(holder[slot]) == "":
		if not silent:
			_warn("Platz %d ist leer - erst ein Werkzeug einspannen." % (slot + 1))
		return false
	var steps := posmod(slot - active_slot, SLOTS)
	var dir := 1 if steps <= 2 else -1
	if not silent:
		if _nc_locked():
			return false
		if is_indexing():
			_warn("Werkzeugwechsel läuft noch.")
			return false
		if spindle_speed > 5.0:
			_warn("Werkzeugwechsel nur bei stehender Spindel!")
			return false
		var nc := _coord_after(str(holder[slot]))
		var clash := holder_clash(holder, slot, nc.x, nc.y, true)
		if clash != "":
			_warn("Einschwenken nicht möglich: %s. Erst freifahren." % clash)
			return false
		if steps == 2:
			var ca := holder_clash(holder, posmod(active_slot + 1, SLOTS), tool_z, tool_x, true)
			if ca != "":
				if holder_clash(holder, posmod(active_slot - 1, SLOTS), tool_z, tool_x, true) == "":
					dir = -1
				else:
					_warn("Einschwenken nicht möglich: beim Drehen %s. Erst freifahren." % ca)
					return false
	_idx_dir = dir
	active_slot = slot
	_apply_holder(not silent, not silent, not silent)
	return true


## Werkzeug in einen Halterplatz einspannen (id "" = Platz leeren). Ein Werkzeug sitzt höchstens
## in einem Platz; steckt es schon woanders, wird es umgesetzt.
func mount_tool(slot: int, id: String) -> bool:
	slot = posmod(slot, SLOTS)
	if _nc_locked():
		return false
	if is_indexing():
		_warn("Werkzeugwechsel läuft noch.")
		return false
	if spindle_speed > 5.0:
		_warn("Werkzeuge nur bei stehender Spindel umspannen!")
		return false
	if str(holder[slot]) == id:
		return true
	if id == "" and slot == active_slot:
		_warn("Das eingeschwenkte Werkzeug kann nicht ausgebaut werden - erst anderen Platz einschwenken.")
		return false
	var other := holder.find(id) if id != "" else -1
	if other == active_slot:
		_warn("%s ist eingeschwenkt - erst anderen Platz einschwenken." % id)
		return false
	var next := holder.duplicate()
	if other >= 0:
		next[other] = ""
	next[slot] = id
	var mc := _coord_after(id) if slot == active_slot and id != "" else Vector2(tool_z, tool_x)
	var clash := holder_clash(next, active_slot, mc.x, mc.y, true)
	if clash != "":
		_warn("Einspannen nicht möglich: %s. Erst freifahren." % clash)
		return false
	holder = next
	_apply_holder(slot == active_slot, false, slot == active_slot)
	if slot != active_slot:
		if id == "":
			_info("Platz %d geleert." % (slot + 1))
		else:
			var t := LatheTools.get_tool(LatheTools.index_of(id))
			_info("%s %s in Platz %d eingespannt." % [id, t["name"], slot + 1])
	return true


## Alter Weg (Spielstände, Tests): Werkzeug i einschwenken, notfalls in den aktiven Platz einspannen.
func select_tool(i: int, silent := false) -> void:
	var id := str(LatheTools.get_tool(posmod(i, LatheTools.count()))["id"])
	var s := holder.find(id)
	if s >= 0:
		index_slot(s, silent)
	elif silent:
		holder[active_slot] = id
		_apply_holder(false)
	else:
		mount_tool(active_slot, id)


## Halterbestückung/-stellung übernehmen. Der Halterkopf sitzt fest auf dem Planschlitten und
## dreht beim Einschwenken nur. keep_post (Werkzeugwechsel an der Maschine): Der Schlitten bleibt
## stehen, die Anzeige springt auf die Schneide des neuen Werkzeugs - Nullpunktverschiebung um die
## Differenz der Werkzeugkorrekturen (wie T/D-Anwahl bei SINUMERIK). Ohne keep_post (Laden,
## Neustart) bleiben die Schneidenkoordinaten und der Schlitten wird passend gesetzt.
func _apply_holder(announce := false, animate := false, keep_post := false) -> void:
	var old_off := tool_offset(tool())
	if str(holder[active_slot]) == "":
		for k in LatheTools.count():
			var free_id := str(LatheTools.get_tool(k)["id"])
			if holder.find(free_id) < 0:
				holder[active_slot] = free_id
				break
	tool_idx = maxi(LatheTools.index_of(str(holder[active_slot])), 0)
	var t := tool()
	if model:
		model.set_layout(holder, active_slot, AXIS_H, _zc(t))
	for k in tool_nodes.size():
		var id := str(LatheTools.get_tool(k)["id"])
		tool_nodes[k].visible = holder.find(id) >= 0 and not (model != null and model.has_tool(id))
	if keep_post:
		# Schlitten (Bezugspunkt F) bleibt stehen; die Schneide liegt jetzt um die
		# Korrekturdifferenz woanders
		var d := tool_offset(t) - old_off
		tool_z = clampf(tool_z + d.x, z_min(), Z_MAX)
		tool_x = clampf(tool_x + d.y, X_MIN, X_MAX)
	var target := active_slot * PI * 0.5
	if animate:
		var old := posmod(roundi(_vis_angle / (PI * 0.5)), SLOTS)
		var steps := posmod((active_slot - old) * _idx_dir, SLOTS)
		_anim_from = _vis_angle
		_anim_to = _vis_angle + _idx_dir * steps * PI * 0.5
		_anim_dur = 2.0 * INDEX_LEVER_T + INDEX_ROT_T * steps
		_anim_t = 0.0
		_pose(_anim_from, _head_pos(), 0.0)
	else:
		_anim_t = -1.0
		_vis_angle = target
		_pose(target, _head_pos(), 0.0)
	auto_feed = false
	auto_feed_x = false
	tool_z = maxf(tool_z, z_min())
	# Kollisionsfrei freifahren, falls die neue Platte im Material stecken würde
	var moved := false
	while tool_x < X_MAX and _engagement(tool_z, tool_x) > 0.0:
		tool_x += 0.5
		moved = true
	_sync_slides()
	if announce:
		var o := tool_offset(t)
		_info("Platz %d: %s D1 %s eingeschwenkt - Korrektur L1 %.3f  L2 %.3f%s" % [active_slot + 1, t["id"],
			t["name"], o.y, o.x, " - in X freigefahren" if moved else ""])
	tool_changed.emit(tool_idx)


## Werkzeugkorrektur (SINUMERIK-Art, Schneide D1) in mm: Vektor vom Werkzeugträger-Bezugspunkt F
## zur Schneidenecke P, wenn das Werkzeug eingeschwenkt ist. x = L2 (Z, axial), y = L1 (X, im
## Radius). F ist die Drehachse des Schnellwechselkopfs auf Spitzenhöhe; er sitzt fest auf dem
## Planschlitten. Die Längen folgen aus der Lage der Platte im Halter, dem Halterplatz und der
## Auskraglänge, deshalb hat jedes Werkzeug eigene Werte.
func tool_offset(t: Dictionary) -> Vector2:
	var p := -_post_pos(t) * 1000.0
	return Vector2(p.x, p.z)


## Korrekturdaten wie in der Werkzeugliste: T, D, L1 (X), L2 (Z), Schneidenradius R, Schneidenlage SL.
func tool_data(t: Dictionary) -> Dictionary:
	var o := tool_offset(t)
	return {"t": str(t["id"]), "d": 1, "l1": o.y, "l2": o.x, "r": float(t["nose"]), "sl": int(t["sl"])}


## Maschinenkoordinaten (MKS) des Bezugspunkts F: Z, X in mm (X im Radius). Die Anzeige X/Z
## (WKS) gilt für die Schneide P = F + Korrektur.
func machine_pos() -> Vector2:
	return Vector2(tool_z, tool_x) - tool_offset(tool())


## Drehachse des Halterkopfs im Planschlitten (m): feste Lage, für jedes Werkzeug gleich.
func _head_pos() -> Vector3:
	return _post_pos(LatheTools.get_tool(maxi(LatheTools.index_of("T1"), 0)))


## Schlitten aus der Schneidenposition stellen: Schlitten = Schneide - Korrektur des aktiven
## Werkzeugs (bezogen auf das Bezugswerkzeug T1, auf das der Planschlitten aufgebaut ist).
func _sync_slides() -> void:
	if carriage == null:
		return
	var tip := _head_pos() - _post_pos(tool())   # Schneide im Planschlitten (m)
	carriage.position.x = tool_z * 0.001 - tip.x
	cross_slide.position.z = tool_x * 0.001 - tip.z
	if chips:
		chips.position.x = tip.x
		chips.position.z = tip.z + 0.002
	_layout_bed_covers()
	if door_latched:
		door_t = _latch_t()
		_place_door()


## Läuft gerade die Einschwenk-Animation?
func is_indexing() -> bool:
	return _anim_t >= 0.0


## Halterkopf (Modell und prozedurale Werkzeuge) auf Drehwinkel angle, Drehpunkt pc stellen.
## Platz s zeigt bei angle = s·90° zum Werkstück. lever 0..1 = Spannhebel gelöst / Kopf angehoben.
func _pose(angle: float, pc: Vector3, lever: float) -> void:
	if model:
		model.set_pose(angle, pc, lever)
	var lift := lever * LatheModel.LIFT
	for k in tool_nodes.size():
		var tk := LatheTools.get_tool(k)
		var s := holder.find(str(tk["id"]))
		if s < 0:
			continue
		# um den Drehpunkt des Halterkopfs in den eigenen Platz schwenken
		var ref := _post_pos(tk)
		tool_nodes[k].transform = Transform3D(Basis.IDENTITY, Vector3(pc.x, lift, pc.z)) \
			* Transform3D(Basis(Vector3.UP, angle - s * PI * 0.5), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, Vector3(-ref.x, 0, -ref.z))


## Einschwenk-Animation weiterführen: Hebel lösen, drehen (weich an- und auslaufend), klemmen.
func _step_index_anim(delta: float) -> void:
	if _anim_t < 0.0:
		return
	_anim_t += delta
	if _anim_t >= _anim_dur:
		_anim_t = -1.0
		_vis_angle = fposmod(_anim_to, TAU)
		_pose(_vis_angle, _head_pos(), 0.0)
		return
	var rot_t := _anim_dur - 2.0 * INDEX_LEVER_T
	var lever := 1.0
	var k := 0.0
	if _anim_t < INDEX_LEVER_T:
		lever = _anim_t / INDEX_LEVER_T
	elif _anim_t < INDEX_LEVER_T + rot_t:
		k = (_anim_t - INDEX_LEVER_T) / rot_t
	else:
		lever = (_anim_dur - _anim_t) / INDEX_LEVER_T
		k = 1.0
	k = smoothstep(0.0, 1.0, k)
	_vis_angle = lerpf(_anim_from, _anim_to, k)
	_pose(_vis_angle, _head_pos(), smoothstep(0.0, 1.0, lever))


## Schaft eines Werkzeugs axial (mm relativ zur Schneide): Rechtsmeißel schließen zur Futterseite
## bündig mit der Platte ab, Linksmeißel zur Reitstockseite, mittige Platten sitzen mittig.
func _shank_span(t: Dictionary) -> Vector2:
	var w := model.shank_box.size.x if model and model.shank_box.size.x > 1.0 else 20.0
	var zmin: float = t["zmin"]
	var zmax: float = t["zmax"]
	w = maxf(w, zmax - zmin)
	match str(t["ref"]):
		"right":
			return Vector2(zmax - w, zmax)
		"center":
			var c := (zmin + zmax) * 0.5
			return Vector2(c - w * 0.5, c + w * 0.5)
	return Vector2(zmin, zmin + w)


func _zc(t: Dictionary) -> float:
	var sp := _shank_span(t)
	return (sp.x + sp.y) * 0.5


## Drehpunkt des Halterkopfs relativ zur Schneide (m, Planschlitten-Achsen), wenn Werkzeug t
## eingeschwenkt ist. Negativ genommen ist das die Werkzeugkorrektur (tool_offset).
func _post_pos(t: Dictionary) -> Vector3:
	if model:
		return model.post_pos(str(t["id"]), AXIS_H, _zc(t), float(t["ext"]))
	return Vector3(POST_C.x * 0.001 + _zc(t) * 0.001, AXIS_H, (POST_C.y + float(t["ext"])) * 0.001)


## Umriss (axial, radial in mm, Maschinenkoordinaten) von Platte + Halter in Platz slot,
## wenn Platz active (mit Werkzeug active_id, "" = laut Bestückung) eingeschwenkt ist und dessen
## Schneidenecke bei (z, x) steht. Gedreht wird um die Kopfachse F; deren Lage zur jeweiligen
## Schneide folgt aus der Werkzeugkorrektur (POST_C gilt für das Bezugswerkzeug T1).
func slot_rect(id: String, slot: int, active: int, z: float, x: float, active_id := "") -> Rect2:
	var t := LatheTools.get_tool(maxi(LatheTools.index_of(id), 0))
	if active_id == "":
		active_id = str(holder[posmod(active, SLOTS)])
	var ta := LatheTools.get_tool(maxi(LatheTools.index_of(active_id), 0))
	var ref := tool_offset(LatheTools.get_tool(maxi(LatheTools.index_of("T1"), 0)))
	var pa := POST_C - (tool_offset(ta) - ref)   # Kopfachse relativ zur aktiven Schneide
	var ps := POST_C - (tool_offset(t) - ref)    # Kopfachse relativ zur Schneide in Platz slot
	var sp := _shank_span(t)
	var a0 := minf(minf(float(t["zmin"]), sp.x), -2.0)
	var a1 := maxf(maxf(float(t["zmax"]), sp.y), HOLDER_W)
	var phi := (active - slot) * PI * 0.5
	var c := roundf(cos(phi))
	var s := roundf(sin(phi))
	var r := Rect2()
	var hl := HOLDER_L + float(t["ext"])
	var corners := [Vector2(a0, 0.0), Vector2(a1, 0.0), Vector2(a1, hl), Vector2(a0, hl)]
	for k in corners.size():
		var q: Vector2 = corners[k] - ps
		var w := pa + Vector2(q.x * c + q.y * s, -q.x * s + q.y * c) + Vector2(z, x)
		r = Rect2(w, Vector2.ZERO) if k == 0 else r.expand(w)
	return r


## Prüft, ob ein nicht eingeschwenktes Werkzeug Futter oder Werkstück trifft. "" = frei.
func holder_clash(slots: Array, active: int, z: float, x: float, with_slot := false) -> String:
	for s in SLOTS:
		var id := str(slots[s])
		if s == active or id == "":
			continue
		var hit := _slot_hit(id, s, active, z, x, str(slots[active]))
		if hit != "":
			return "%s %s" % ["%s in Platz %d" % [id, s + 1] if with_slot else id, hit]
	return ""


func _slot_hit(id: String, s: int, active: int, z: float, x: float, active_id := "") -> String:
	var rc := slot_rect(id, s, active, z, x, active_id)
	if rc.position.x < 0.0 and rc.end.x > -CHUCK_DEPTH and rc.position.y < CHUCK_R and rc.end.y > -CHUCK_R:
		return "trifft das Futter"
	var rr := max_radius(rc.position.x, rc.end.x)
	if rr > 0.05 and rc.position.y < rr and rc.end.y > -rr:
		return "trifft das Werkstück"
	return ""


## Anzeige im Bedienpult: Zustand eines Halterplatzes an der aktuellen Position und beim
## Längsdrehen von hier bis zum Futter (gleiches X).
func slot_status(slot: int) -> Dictionary:
	var id := str(holder[slot])
	if id == "":
		return {"text": "leer", "level": 0}
	if slot == active_slot:
		return {"text": "eingeschwenkt", "level": 0}
	var hit := _slot_hit(id, slot, active_slot, tool_z, tool_x)
	if hit != "":
		return {"text": hit.replace("trifft", "berührt"), "level": 2}
	var z := tool_z
	while z > z_min() + 0.01:
		z = maxf(z - 5.0, z_min())
		hit = _slot_hit(id, slot, active_slot, z, tool_x)
		if hit != "":
			return {"text": "%s ab Z %d" % [hit, int(z)], "level": 1}
	return {"text": "frei", "level": 0}


## Größter Werkstückradius zwischen z0 und z1 (mm).
func max_radius(z0: float, z1: float) -> float:
	var a := maxi(int(floor(z0 / SEG)), 0)
	var b := mini(int(floor(z1 / SEG)), profile.size() - 1)
	var m := 0.0
	for i in range(a, b + 1):
		m = maxf(m, profile[i])
	return m


# ======================================================================= Werkzeug von Hand

var tool_mount: ToolMount


func tool_list() -> Array:
	var list := []
	for i in LatheTools.count():
		var t := LatheTools.get_tool(i)
		list.append({"id": t["id"], "name": "%s %s" % [t["id"], t["short"]]})
	return list


func tool_name(id: String) -> String:
	var t := LatheTools.get_tool(maxi(LatheTools.index_of(id), 0))
	return "%s %s" % [t["id"], t["name"]]


func has_tool(id: String) -> bool:
	return holder.find(id) >= 0


func make_tool_model(id: String) -> Node3D:
	var n := _build_tool_visual(LatheTools.get_tool(maxi(LatheTools.index_of(id), 0)))
	n.visible = true
	return n


## Mitte des Halterkopfs in Weltkoordinaten.
func _post_center() -> Vector3:
	if model and model._post_root:
		return model._post_root.global_position
	return cross_slide.to_global(_head_pos())


## Zeigt der Blick auf den Halterkopf?
func focus_for(origin: Vector3, dir: Vector3) -> Node:
	if tool_mount == null:
		return self
	return tool_mount if (_post_center() - origin).cross(dir).length() <= MOUNT_REACH else self


func _free_slot() -> int:
	return holder.find("")


## Platz, aus dem eine freie Hand ein Werkzeug nimmt: der nächste belegte nach dem eingeschwenkten.
func _removable_slot() -> int:
	for k in range(1, SLOTS):
		var s := posmod(active_slot + k, SLOTS)
		if str(holder[s]) != "":
			return s
	return -1


func hand_prompt(held: Dictionary) -> String:
	if held.is_empty():
		var r := _removable_slot()
		return "" if r < 0 else "[Linksklick] %s aus Platz %d nehmen" % [tool_name(str(holder[r])), r + 1]
	if held["machine"] != MACHINE_ID:
		return "%s passt nicht in den Halter" % held["name"]
	var f := _free_slot()
	if f >= 0:
		return "[Linksklick] %s in Platz %d einspannen" % [held["name"], f + 1]
	return "[Linksklick] %s einspannen, %s kommt in die Hand" % [held["name"], tool_name(str(holder[active_slot]))]


## Werkzeug von Hand: in den freien Platz, sonst Tausch mit dem eingeschwenkten. Freie Hand nimmt
## ein nicht eingeschwenktes Werkzeug heraus.
func hand_click(p: Node) -> void:
	var held: Dictionary = p.held
	if held.is_empty():
		var r := _removable_slot()
		if r < 0:
			_warn("Das eingeschwenkte Werkzeug kann nicht ausgebaut werden.")
			return
		var out := str(holder[r])
		if mount_tool(r, ""):
			p.set_held(self, out)
		return
	if held["machine"] != MACHINE_ID:
		_warn("%s passt nicht in den Halter." % held["name"])
		return
	var id := str(held["id"])
	var f := _free_slot()
	if f >= 0:
		if mount_tool(f, id):
			p.clear_held()
		return
	var old := str(holder[active_slot])
	if mount_tool(active_slot, id):
		p.set_held(self, old)


# ======================================================================= Werkstück

func new_workpiece(d: float, length: float) -> void:
	stock_d = d
	stock_len = length
	var n := int(ceil(length / SEG))
	profile = PackedFloat32Array()
	profile.resize(n)
	profile.fill(d * 0.5)
	machined = PackedByteArray()
	machined.resize(n)
	machined.fill(0)
	rz = PackedFloat32Array()
	rz.resize(n)
	rz.fill(0.0)
	auto_feed = false
	auto_feed_x = false
	tool_x = maxf(tool_x, d * 0.5 + 10.0)
	tool_z = maxf(tool_z, length + 15.0)
	wcs_z = length                 # Werkstücknullpunkt an der Stirnfläche des Rohteils
	_update_jaws()
	_dirty = true
	if workpiece_mi:
		workpiece_mi.mesh = _make_mesh(0, profile.size() - 1, true)


func _update_jaws() -> void:
	if model:
		model.update_jaws(stock_d)
		return
	var r := stock_d * 0.0005
	for jp in jaws:
		var j := jp.get_child(0) as Node3D
		j.position = Vector3(-0.015, r + 0.025, 0)


func _seg_color(i: int) -> Color:
	if machined[i] == 0:
		return _raw_col
	# Rautiefe grob quantisieren -> raue Flächen matter/dunkler
	var q := clampf(snappedf(rz[i], 1.0) / 25.0, 0.0, 1.0)
	return _cut_col.lerp(_rough_col, q)


## Rotationskörper aus den Segmenten i0..i1 (optional mit eingespanntem Bereich).
func _make_mesh(i0: int, i1: int, with_clamp: bool) -> ArrayMesh:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	if with_clamp:
		var r0 := stock_d * 0.5
		pts.append(Vector2(-CLAMP_LEN, 0.0)); cols.append(_raw_col)
		pts.append(Vector2(-CLAMP_LEN, r0)); cols.append(_raw_col)
		pts.append(Vector2(0.0, r0)); cols.append(_raw_col)
	else:
		pts.append(Vector2(i0 * SEG, 0.0)); cols.append(_cut_col)
		pts.append(Vector2(i0 * SEG, profile[i0])); cols.append(_cut_col)
	var last := -1
	for i in range(i0, i1 + 1):
		var r := profile[i]
		if r <= 0.02:
			break
		var p := Vector2((i + 0.5) * SEG, r)
		var c := _seg_color(i)
		# kollineare Punkte zusammenfassen
		var n := pts.size()
		if n >= 2 and cols[n - 1] == c and cols[n - 2] == c:
			var d1 := pts[n - 1] - pts[n - 2]
			var d2 := p - pts[n - 1]
			if absf(d1.cross(d2)) < 0.00005 and d1.dot(d2) > 0.0:
				pts[n - 1] = p
				last = i
				continue
		pts.append(p)
		cols.append(c)
		last = i
	if last >= 0:
		var ze := (last + 1) * SEG
		var end_col := _raw_col if (ze >= stock_len - 0.01 and machined[last] == 0) else _cut_col
		pts.append(Vector2(ze, profile[last])); cols.append(cols[cols.size() - 1])
		pts.append(Vector2(ze, 0.0)); cols.append(end_col)

	var s := 0.001
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var vcols := PackedColorArray()
	var idx := PackedInt32Array()
	var band_n: Array[Vector2] = []
	for k in range(pts.size() - 1):
		var d := pts[k + 1] - pts[k]
		band_n.append(Vector2(-d.y, d.x).normalized() if d.length() > 0.000001 else Vector2(0, 1))
	var prev_ring := -1
	for k in range(pts.size() - 1):
		var na := band_n[k]
		var nb := band_n[k]
		var smooth_a := k > 0 and band_n[k - 1].dot(band_n[k]) > 0.85
		var smooth_b := k + 1 < band_n.size() and band_n[k + 1].dot(band_n[k]) > 0.85
		if smooth_a:
			na = (band_n[k - 1] + band_n[k]).normalized()
		if smooth_b:
			nb = (band_n[k + 1] + band_n[k]).normalized()
		var ra := prev_ring if (smooth_a and prev_ring >= 0) else _ring(verts, norms, vcols, pts[k], na, cols[k + 1], s)
		var rb := _ring(verts, norms, vcols, pts[k + 1], nb, cols[k + 1], s)
		for q in RING:
			var q2 := (q + 1) % RING
			idx.append(ra + q); idx.append(rb + q); idx.append(rb + q2)
			idx.append(ra + q); idx.append(rb + q2); idx.append(ra + q2)
		prev_ring = rb if smooth_b else -1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = vcols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _ring(verts: PackedVector3Array, norms: PackedVector3Array, vcols: PackedColorArray,
		p: Vector2, n2: Vector2, c: Color, s: float) -> int:
	var base := verts.size()
	for q in RING:
		verts.append(Vector3(p.x * s, _cos[q] * p.y * s, _sin[q] * p.y * s))
		norms.append(Vector3(n2.x, _cos[q] * n2.y, _sin[q] * n2.y))
		vcols.append(c)
	return base


func part_length() -> float:
	for i in range(profile.size() - 1, -1, -1):
		if profile[i] > 0.05:
			return (i + 1) * SEG
	return 0.0


func is_untouched() -> bool:
	for m in machined:
		if m:
			return false
	return true


func radius_at(z: float) -> float:
	var i := int(floor(z / SEG))
	if i < 0 or i >= profile.size():
		return 0.0
	return profile[i]


# ======================================================================= Zerspanung

func _seg_range(z: float) -> Vector2i:
	var t := tool()
	var a := int(floor((z + float(t["zmin"])) / SEG + 0.0004))   # Rundung: Schneide genau auf der Segmentgrenze
	var b := int(floor((z + float(t["zmax"])) / SEG))
	return Vector2i(maxi(a, 0), mini(b, profile.size() - 1))


## Größte radiale Eingriffstiefe der Platte an Position (z, x). 0 = kein Kontakt.
func _engagement(z: float, x: float) -> float:
	var t := tool()
	var rg := _seg_range(z)
	var m := 0.0
	for i in range(rg.x, rg.y + 1):
		var r := profile[i]
		if r <= 0.0:
			continue
		var e := LatheTools.env_min(t, i * SEG - z, (i + 1) * SEG - z)
		if e == INF:
			continue
		if x + float(t["top"]) <= 0.0:
			continue   # Platte ganz hinter der Drehmitte (siehe _back_contact)
		m = maxf(m, r - maxf(x + e, 0.0))
	return m


## Hinter der Drehmitte (X < 0) läuft das Werkstück von unten gegen die Platte: jede Berührung
## dort ist ein Plattenbruch. Material belegt radial [-r, r], die Platte [x + Hüllkurve, x + Höhe].
func _back_contact(z: float, x: float) -> bool:
	if x >= 0.0:
		return false
	var t := tool()
	var rg := _seg_range(z)
	var hi := x + float(t["top"])
	for i in range(rg.x, rg.y + 1):
		var r := profile[i]
		if r <= 0.05:
			continue
		var e := LatheTools.env_min(t, i * SEG - z, (i + 1) * SEG - z)
		if e == INF:
			continue
		if x + e < -0.05 and r > -hi:
			return true
	return false


func move_tool(dz: float, dx: float, rapid := false, speed := -1.0) -> void:
	if estop:
		return
	var steps := maxi(1, int(ceil(maxf(absf(dz), absf(dx)) / 0.2)))
	var sz := dz / steps
	var sx := dx / steps
	for s in steps:
		if not _step_tool(sz, sx, rapid, speed):
			break


func _step_tool(sz: float, sx: float, rapid: bool, speed: float) -> bool:
	var nz := clampf(tool_z + sz, z_min(), Z_MAX)
	var nx := clampf(tool_x + sx, X_MIN, X_MAX)
	var t := tool()
	if _back_contact(nz, nx):
		if spindle_speed < 30.0:
			_warn("Werkzeug berührt das Werkstück hinter der Drehmitte.")
		else:
			_crash("Schneide hinter der Drehmitte im Material - das Werkstück läuft gegen die Plattenunterseite. NOT-HALT!")
		return false
	var clash := holder_clash(holder, active_slot, nz, nx, true)
	if clash != "" and holder_clash(holder, active_slot, tool_z, tool_x) == "":
		if spindle_speed < 30.0:
			_warn("Werkzeughalter: %s." % clash)
		else:
			_crash("Kollision: %s! NOT-HALT ausgelöst." % clash)
		return false
	var depth := _engagement(nz, nx)
	if depth > 0.0001:
		if spindle_speed < 30.0:
			_warn("Spindel steht! Werkzeug berührt das Werkstück.")
			return false
		if rapid:
			_crash("Kollision im Eilgang! NOT-HALT ausgelöst.")
			return false
		var side := absf(sz) > absf(sx)
		var limit: float = t["max_dz"] if side else t["max_dx"]
		# Schlichtzug der Zyklensteuerung: fährt längs ins dünne Planaufmaß vor einer Schulter
		# (Spanbreite = Schulterhöhe, Spandicke = Vorschub) - das schafft die Schlichtplatte
		if depth > limit + 0.05 and not (nc_finish and side):
			if t["id"] == "T6" and side:
				_warn("Stechmeißel nur radial einsetzen (seitlich max. 0,3 mm)!")
			else:
				_warn("Spanabnahme zu groß für %s (max. %.1f mm)." % [t["short"], limit])
			return false
		# Schnitttiefe beim Längsdrehen: unberührtes Material direkt vor der Schneide bis zur Schneide
		var ap := depth
		if side:
			ap = maxf(ap, radius_at(nz + signf(sz) * SEG * 1.5) - nx)
		_cut(nz, nx, speed, ap, side)
	if nz <= z_min() + 0.01 and sz < 0.0:
		_warn("Achtung: Spannbacken!")
	tool_z = nz
	tool_x = nx
	return true


## Erreichbare Rautiefe Rz (µm) und Hauptursache für Werkzeug t bei Vorschub f (mm/U),
## Schnitttiefe ap (mm), Schnittgeschwindigkeit vc (m/min). manual = von Hand gekurbelt.
## Grundlage ist die kinematische Rautiefe f²/(8 r), real etwa 1,6-fach. Dazu:
## - Aufbauschneide bei zu niedrigem vc (bis 3-fach), Verschleiß bei sehr hohem vc
## - zu kleiner Vorschub oder Span: Platte quetscht/schmiert statt zu schneiden
## - zu große Zustellung für die Platte: Rattern
## - ohne Kühlschmierstoff etwas schlechter, Handvorschub ungleichmäßig
static func surface_rz(t: Dictionary, f: float, ap: float, vc: float, kss: bool, manual: bool) -> Dictionary:
	var r_eps: float = t["nose"]
	var max_ap: float = t["max_dz"] if ap > 0.0 else 1.0
	var rz := 1.6 * f * f / (8.0 * r_eps) * 1000.0
	# Plattengeometrie: Schrupp-Platten (große Zustellung) erreichen nicht die Güte von Schlichtplatten
	rz = maxf(rz, 0.6 + 0.3 * float(t["max_dz"]))
	var hint := ""
	var worst := 0.0
	# Schnittgeschwindigkeit
	var vf := 1.0
	if vc < 120.0:
		vf = lerpf(3.0, 1.0, clampf((vc - 30.0) / 90.0, 0.0, 1.0))
	elif vc > 320.0:
		vf = 1.0 + (vc - 320.0) / 160.0
	rz *= vf
	if vf > 1.3:
		hint = "Aufbauschneide - vc zu niedrig" if vc < 120.0 else "Verschleiß - vc zu hoch"
		worst = vf
	if not kss:
		rz *= 1.25
	# Mindestspandicke: zu kleiner Vorschub quetscht die Oberfläche
	if f < 0.04:
		var add := (0.04 - f) / 0.04 * 6.0
		rz += add
		if add / maxf(rz, 0.1) > 0.3 and add > worst:
			hint = "Vorschub zu klein - Platte quetscht"
			worst = add
	# sehr kleine Zustellung: Schneide reibt nur (unterhalb etwa des halben Eckenradius)
	if ap > 0.0 and ap < r_eps * 0.25:
		var add2 := (1.0 - ap / (r_eps * 0.25)) * 4.0
		rz += add2
		if add2 > worst and add2 > 1.0:
			hint = "Zustellung zu klein - Schneide reibt"
			worst = add2
	# Rattern bei großer Zustellung
	if ap > max_ap * 0.6:
		var add3 := (ap / max_ap - 0.6) * 40.0
		rz += add3
		if add3 > worst and add3 > 1.0:
			hint = "Rattern - Zustellung zu groß"
			worst = add3
	if manual:
		rz += 2.0
		if hint == "":
			hint = "Handvorschub ungleichmäßig"
	if hint == "" and f * f / (8.0 * r_eps) * 1000.0 * 1.6 > 6.0:
		hint = "Vorschub hoch für den Eckenradius"
	return {"rz": clampf(rz, 0.3, 200.0), "hint": hint}


func _cut(z: float, x: float, speed: float, depth := 0.0, axial := true) -> void:
	var t := tool()
	var rg := _seg_range(z)
	# Vorschub pro Umdrehung aus der Verfahrgeschwindigkeit; Handrad: aus dem Kurbeltempo
	var manual := speed <= 0.0
	var f := 0.05
	if speed > 0.0:
		f = speed / maxf(spindle_speed / 60.0, 0.1)
	elif _hw_speed > 0.0:
		f = _hw_speed / maxf(spindle_speed / 60.0, 0.1)
	var vc := PI * maxf(x * 2.0, 0.0) * spindle_speed / 1000.0
	var sr := surface_rz(t, f, depth if axial else 0.0, vc, coolant, manual)
	var rz_val: float = sr["rz"]
	var removed := 0.0
	for i in range(rg.x, rg.y + 1):
		var r := profile[i]
		if r <= 0.0:
			continue
		var e := LatheTools.env_min(t, i * SEG - z, (i + 1) * SEG - z)
		if e == INF:
			continue
		if x + float(t["top"]) <= 0.0:
			continue
		var lim := maxf(x + e, 0.0)
		if lim < 0.3:
			lim = 0.0   # Restzapfen in der Drehmitte bricht ab
		if lim < r:
			removed += r * r - lim * lim
			profile[i] = lim
			machined[i] = 1
			rz[i] = rz_val
	if removed <= 0.0:
		return
	last_rz = rz_val
	last_rz_hint = str(sr["hint"])
	_cut_t = 0.15
	_cut_level = clampf(_cut_level + removed * 0.0015, 0.0, 1.0)
	_dirty = true
	# Abstechen: durchtrennte Verbindung -> Rest fällt in die Spänewanne
	for i in range(rg.x, rg.y + 1):
		if profile[i] <= 0.05 and i + 1 < profile.size() and profile[i + 1] > 0.05:
			_drop_piece(i + 1)
			break


func _drop_piece(i0: int) -> void:
	var i1 := i0
	var rmax := 0.0
	while i1 + 1 < profile.size() and profile[i1 + 1] > 0.05:
		i1 += 1
	for i in range(i0, i1 + 1):
		rmax = maxf(rmax, profile[i])
	var mesh := _make_mesh(i0, i1, false)
	for i in range(i0, profile.size()):
		profile[i] = 0.0
	if rmax < 1.0:
		return   # dünner Restring (z. B. beim Planen über die Mitte) - geht mit den Spänen weg
	_info("Teil abgestochen.")
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
	if demo or host == null:
		return
	var body := RigidBody3D.new()
	body.collision_layer = PIECE_LAYER
	body.collision_mask = PIECE_LAYER
	body.mass = 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _wp_mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	var zc := (i0 + i1 + 1) * 0.5 * SEG
	sh.radius = maxf(rmax * 0.001, 0.003)
	sh.height = maxf((i1 + 1 - i0) * SEG * 0.001, 0.002)
	cs.shape = sh
	cs.rotation.z = PI / 2
	cs.position.x = zc * 0.001
	body.add_child(cs)
	host.add_child(body)
	body.global_transform = spindle_pivot.global_transform
	body.angular_velocity = spindle_pivot.global_basis.x * (spindle_speed / 60.0 * TAU) * 0.3
	get_tree().create_timer(25.0).timeout.connect(body.queue_free)


func _crash(text: String) -> void:
	estop = true
	spindle_on = false
	auto_feed = false
	auto_feed_x = false
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

## Solldrehzahl /min. Mit konstanter Schnittgeschwindigkeit aus vc und dem Durchmesser an der
## Schneide, begrenzt auf rpm_limit (an der Drehmitte läuft sie sonst gegen unendlich).
func rpm() -> float:
	if css:
		var d := absf(tool_x) * 2.0
		var n := vc_set * 1000.0 / (PI * maxf(d, 0.1))
		return clampf(n, RPM_MIN, rpm_limit)
	return rpm_set


func feed() -> float:
	return feed_set


func set_rpm(v: float) -> void:
	rpm_set = clampf(roundf(v), RPM_MIN, RPM_MAX)


func set_feed(v: float) -> void:
	feed_set = clampf(snappedf(v, 0.01), FEED_MIN, FEED_MAX)


func set_vc(v: float) -> void:
	vc_set = clampf(roundf(v), VC_MIN, VC_MAX)


func set_rpm_limit(v: float) -> void:
	rpm_limit = clampf(roundf(v), RPM_MIN, RPM_MAX)


func set_css(on: bool) -> void:
	css = on
	_info("Konstante Schnittgeschwindigkeit %s" % ("EIN (vc %d m/min, max. %d /min)" % [int(vc_set), int(rpm_limit)] if on else "AUS"))


## Tasten: Drehzahl stufenweise (bei G96 die Schnittgeschwindigkeit in 10er-Schritten).
func step_rpm(dir: int) -> void:
	if css:
		set_vc(vc_set + 10.0 * dir)
		return
	set_rpm(_next_step(RPM_STEPS, rpm_set, dir))


func step_feed(dir: int) -> void:
	set_feed(_next_step(FEED_STEPS, feed_set, dir))


static func _next_step(steps: Array, v: float, dir: int) -> float:
	if dir > 0:
		for s in steps:
			if float(s) > v + 0.0001:
				return float(s)
		return float(steps[steps.size() - 1])
	for i in range(steps.size() - 1, -1, -1):
		if float(steps[i]) < v - 0.0001:
			return float(steps[i])
	return float(steps[0])


func toggle_spindle() -> void:
	if _nc_locked():
		return
	if estop:
		_warn("Not-Halt aktiv - mit [%s] quittieren." % Settings.binding_text("emergency_stop"))
	elif is_indexing() and not spindle_on:
		_warn("Werkzeugwechsel läuft - Spindel erst nach dem Einschwenken starten.")
	else:
		spindle_on = not spindle_on


func toggle_estop() -> void:
	if estop:
		estop = false
		_info("Not-Halt quittiert.")
	else:
		_crash("NOT-HALT betätigt.")


## Auto-Vorschub (alter Weg, Taste): axis 0 = plan zur Mitte (X-), 1 = längs in
## Schnittrichtung des Werkzeugs, -1 = aus.
func set_auto_feed(axis: int) -> void:
	if axis < 0:
		set_auto_dir(-1, 0)
	elif axis == 0:
		set_auto_dir(0, -1)
	else:
		set_auto_dir(1, int(tool()["feed_dir"]))


## Auto-Vorschub in eine Richtung (Kreuzschalter): axis 0 = X, 1 = Z, -1 = aus; sign ±1.
## Dieselbe Richtung nochmal schaltet ab.
func set_auto_dir(axis: int, sign: int) -> void:
	if axis < 0:
		auto_feed = false
		auto_feed_x = false
		return
	if _nc_locked():
		return
	if auto_dir() == Vector2i(sign if axis == 1 else 0, sign if axis == 0 else 0):
		set_auto_dir(-1, 0)
		return
	if not spindle_on or estop:
		_warn("Vorschub nur bei laufender Spindel.")
		return
	auto_feed = axis == 1
	auto_feed_x = axis == 0
	if axis == 1:
		auto_sign_z = signi(sign)
	else:
		auto_sign_x = signi(sign)


## Aktive Auto-Vorschubrichtung als (Z, X), z. B. (-1, 0) = Z-; (0, 0) = aus.
func auto_dir() -> Vector2i:
	return Vector2i(auto_sign_z if auto_feed else 0, auto_sign_x if auto_feed_x else 0)


## Verfahrgeschwindigkeit im Tippbetrieb (mm/s): eingestellter Vorschub bei laufender bzw.
## (Spindel steht) eingestellter Drehzahl; fast = Shift, 10-fach.
func jog_speed(fast := false) -> float:
	var n := spindle_speed if spindle_speed > 30.0 else rpm()
	return feed() * n / 60.0 * (JOG_FAST if fast else 1.0)


func set_handwheel_axis(axis: int) -> void:
	hw_axis = clampi(axis, 0, 1)


func request_new_part() -> void:
	if _nc_locked():
		return
	if spindle_speed > 5.0:
		_warn("Erst Spindel stoppen!")
	else:
		new_part_requested.emit()


func request_submit() -> void:
	if _nc_locked():
		return
	if spindle_speed > 5.0:
		_warn("Erst Spindel stoppen!")
	else:
		submit_requested.emit()


func cutting_speed() -> float:
	var d := maxf(tool_x * 2.0, 0.0)
	return PI * d * spindle_speed / 1000.0


## Wird am Pult gerade in ein Eingabefeld geschrieben?
func typing() -> bool:
	return screen_vp != null and screen_vp.gui_get_focus_owner() is LineEdit


## Handbedienung gesperrt, solange ein Programm läuft oder angehalten ist (Meldung einmalig).
func _nc_locked() -> bool:
	if nc == null or nc_internal or not nc.busy():
		return false
	_warn("Automatikbetrieb - erst RESET am Pult.")
	return true


# ======================================================================= Schiebetür

## Schutztür ganz geschlossen (und nicht gerade beim Öffnen)?
## Werkstücknullpunkt Z0 neu setzen (mm über der Backen-Stirnfläche).
func set_wcs(z: float) -> void:
	if _nc_locked():
		return
	wcs_z = z
	_info("Werkstücknullpunkt gesetzt: Z0 = Maschine Z %.3f." % z)


## Z0 an die aktuelle Stirnfläche des Werkstücks legen.
func set_wcs_face() -> void:
	set_wcs(part_length())


## Z0 an die Schneide legen (Stirnfläche angekratzt).
func set_wcs_tool() -> void:
	set_wcs(tool_z)


func door_closed() -> bool:
	return door_latched


## Türlage (Anteil von DOOR_TRAVEL), in der die Tür am Bettschlitten einrastet: ihr rechter Rand
## steht bündig mit dem rechten Ende des Schlittens.
func _latch_t() -> float:
	if carriage == null:
		return 1.0
	var off := clampf(carriage.position.x + DOOR_LATCH_DX, 0.0, DOOR_MAX)
	return off / DOOR_TRAVEL


## Tür nach rechts zum Bettschlitten schieben; dort rastet sie ein und fährt mit ihm mit.
func close_door() -> void:
	if door_latched or _door_closing:
		return
	_door_closing = true
	_info("Schutztür wird zum Schlitten geschoben.")


## Schwarzen Hebel ziehen: Tür vom Schlitten lösen und aufschieben.
func open_door() -> void:
	if not door_latched and not _door_closing:
		return
	door_latched = false
	_door_closing = false
	_info("Schutztür gelöst und aufgeschoben.")


## Tür zu- bzw. aufschieben (läuft sie gerade zu, kehrt sie um).
func toggle_door() -> void:
	if door_latched or _door_closing:
		open_door()
	else:
		close_door()


## Mausstrahl (Fensterposition) in Maschinenkoordinaten: [Ursprung, Richtung].
func _mouse_ray(mouse_pos: Vector2) -> Array:
	var inv := global_transform.affine_inverse()
	return [inv * op_cam.project_ray_origin(mouse_pos), inv.basis * op_cam.project_ray_normal(mouse_pos)]


## Liegt die Maus über dem schwarzen Hebel (Türgriff)?
func handle_hit(mouse_pos: Vector2) -> bool:
	if op_cam == null or _door == null:
		return false
	var r := _mouse_ray(mouse_pos)
	var c := HANDLE_POS + Vector3(_door.position.x, 0, 0)
	var box := AABB(c - HANDLE_PICK * 0.5, HANDLE_PICK)
	return box.intersects_ray(r[0], r[1]) != null


## Liegt die Maus über der Tür (Fenster, Pfosten, Kopfteil)? Nur von vorn, wo man sie sieht.
func door_hit(mouse_pos: Vector2) -> bool:
	if op_cam == null or _door == null or op_cam.position.z <= 0.64:
		return false
	var r := _mouse_ray(mouse_pos)
	var x0 := DOOR_X0 + _door.position.x
	var box := AABB(Vector3(x0, 1.09, 0.48), Vector3(DOOR_X1 - DOOR_X0, 0.63, 0.1))
	return box.intersects_ray(r[0], r[1]) != null


## Linke Maustaste: auf die Tür geklickt schiebt sie sich zum Schlitten und rastet ein, ein
## Klick auf den schwarzen Hebel löst sie wieder und schiebt sie auf.
func _door_input(event: InputEvent) -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		return false
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return false
		if handle_hit(mb.position):
			if door_latched or _door_closing:
				open_door()
			else:
				close_door()
			return true
		if door_hit(mb.position) and not door_latched and not _door_closing:
			close_door()
			return true
		return false
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var hov := handle_hit(mm.position) or (not door_latched and door_hit(mm.position))
		if hov != _handle_hover:
			_handle_hover = hov
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hov else Input.CURSOR_ARROW)
	return false


## Tür sofort in eine Lage setzen (Laden, Tests, Render): zu = am Schlitten eingerastet.
func set_door(closed: bool) -> void:
	door_latched = closed
	_door_closing = false
	door_t = _latch_t() if closed else 0.0
	_place_door()


func _step_door(delta: float) -> void:
	if door_latched:
		door_t = _latch_t()           # fährt mit dem Schlitten
	elif _door_closing:
		var lt := _latch_t()
		door_t = move_toward(door_t, lt, delta / DOOR_TIME)
		if is_equal_approx(door_t, lt):
			_door_closing = false
			door_latched = true
			_info("Schutztür am Schlitten eingerastet.")
	elif door_t > 0.0:
		door_t = move_toward(door_t, 0.0, delta / DOOR_TIME)
	_place_door()


func _place_door() -> void:
	if _door:
		_door.position.x = door_t * DOOR_TRAVEL


func _physics_process(delta: float) -> void:
	_msg_cool -= delta
	var target := rpm() if spindle_on and not estop else 0.0
	var ramp := 2500.0 if target > spindle_speed else (6000.0 if estop else 1800.0)
	spindle_speed = move_toward(spindle_speed, target, ramp * delta)
	# Rechtslauf (M3): Die Werkstückoberfläche läuft an der Schneide (Bedienerseite, Spanfläche
	# oben) nach unten in die Platte hinein.
	spindle_pivot.rotate_x(spindle_speed / 60.0 * TAU * delta)
	_step_door(delta)
	nc.step(delta)

	# Tippbetrieb (WASD): im eingestellten Vorschub, Shift = 10-fach. Nicht im Automatikbetrieb
	# und nicht, solange am Pult in ein Eingabefeld geschrieben wird.
	if operating and not estop and not nc.busy() and not typing():
		var ax := Vector2(Input.get_axis("lathe_z_minus", "lathe_z_plus"), Input.get_axis("lathe_x_in", "lathe_x_out"))
		if ax.x != 0.0:
			auto_feed = false
		if ax.y != 0.0:
			auto_feed_x = false
		if ax != Vector2.ZERO:
			var spd := jog_speed(Input.is_action_pressed("lathe_rapid"))
			var v := ax.normalized() * spd
			move_tool(v.x * delta, v.y * delta, false, spd)
			hw_z.rotation.z -= v.x * delta * 0.08
			hw_x.rotation.z -= v.y * delta * 0.25
	# Auto-Vorschub läuft auch weiter, wenn niemand an der Maschine steht (wie die Spindel)
	if (auto_feed or auto_feed_x) and not estop and spindle_speed > 30.0:
		var vf := feed() * spindle_speed / 60.0
		var before := Vector2(tool_z, tool_x)
		if auto_feed:
			var dz2 := auto_sign_z * vf * delta
			move_tool(dz2, 0.0, false, vf)
			hw_z.rotation.z -= dz2 * 0.08
		if auto_feed_x:
			var dx2 := auto_sign_x * vf * delta
			move_tool(0.0, dx2, false, vf)
			hw_x.rotation.z -= dx2 * 0.25
		if before.distance_to(Vector2(tool_z, tool_x)) < 0.000001:
			if auto_feed or auto_feed_x:
				_info("Auto-Vorschub angehalten (Anschlag oder Hindernis).")
			auto_feed = false
			auto_feed_x = false
		if auto_feed_x and auto_sign_x < 0 and tool_x <= 0.001:
			auto_feed_x = false
			_info("Planvorschub an der Drehmitte angehalten.")
	elif spindle_speed <= 30.0:
		auto_feed = false
		auto_feed_x = false

	_sync_slides()

	_cut_t -= delta
	_cut_level = move_toward(_cut_level, 0.0, delta * 2.5)
	chips.emitting = _cut_t > 0.0
	coolant_fx.emitting = coolant and spindle_speed > 10.0
	spindle_led.material_override = _led_on if spindle_speed > 5.0 else _led_off

	_rebuild_t -= delta
	if _dirty and _rebuild_t <= 0.0:
		_rebuild_t = 0.06
		_dirty = false
		workpiece_mi.mesh = _make_mesh(0, profile.size() - 1, true)


func _process(delta: float) -> void:
	_step_index_anim(delta)
	if operating:
		_update_camera(delta)
	_screen_t -= delta
	if _screen_t <= 0.0:
		_screen_t = 0.1
		_update_screen()
	_fill_audio()


## Orbit-Kamera um einen Blickpunkt. Weit weg: Übersicht über Werkstück und Schlitten,
## nah dran: Blickpunkt wandert auf die Schneide. Basis aus Gier/Nick -> auch exakt senkrecht
## von oben ohne Kippen (kein look_at). In der Pultansicht ist der Blickpunkt der Pult-Bildschirm.
func _update_camera(delta: float) -> void:
	if Input.is_action_pressed("zoom_in"):
		_dist_t = maxf(_dist_t * pow(0.3, delta), CAM_MIN)
	if Input.is_action_pressed("zoom_out"):
		_dist_t = minf(_dist_t / pow(0.3, delta), CAM_MAX)
	var k := clampf(12.0 * delta, 0.0, 1.0)
	cam_dist = lerpf(cam_dist, _dist_t, k)
	cam_yaw = lerpf(cam_yaw, _yaw_t, k)
	cam_pitch = lerpf(cam_pitch, _pitch_t, k)
	var want: Vector3
	if _panel_view:
		want = screen_center()
	else:
		var tz := clampf(tool_z * 0.001, 0.0, 0.5)
		var overview := Vector3(tz * 0.8 + 0.04, AXIS_H, 0.03)
		var tip := Vector3(tool_z * 0.001, AXIS_H, tool_x * 0.001)
		var near_t := clampf((0.45 - cam_dist) / 0.35, 0.0, 1.0)
		want = overview.lerp(tip, near_t) + cam_pan
	cam_target = cam_target.lerp(want, clampf(8.0 * delta, 0.0, 1.0))
	var b := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	op_cam.transform = Transform3D(b, cam_target + b * Vector3(0, 0, cam_dist))
	# Über der Dachunterkante würde das Dach die Sicht auf den Arbeitsraum verdecken
	op_cam.set_cull_mask_value(2, op_cam.position.y < CANOPY_Y - 0.02 or op_cam.position.z > 0.3)
	# Die Tür nur zeigen, wenn die Kamera vor ihr steht (sonst steckt sie in Kopfteil oder Pfosten)
	op_cam.set_cull_mask_value(3, op_cam.position.z > 0.64 or _panel_view)


## Mitte des Pult-Bildschirms im Maschinen-Koordinatensystem.
func screen_center() -> Vector3:
	if _pult == null or _screen_mi == null:
		return Vector3(-1.2, PULT_Y0 + 0.05, 0.8)
	return _door.transform * _pult.transform * _screen_mi.position


var _pre_panel: Array = []


func set_view(view: String) -> void:
	if view == "panel":
		if not _panel_view:
			_pre_panel = [_yaw_t, _pitch_t, _dist_t, cam_pan]
		_panel_view = true
		_yaw_t = _pult.rotation.y if _pult else 0.4
		_pitch_t = -0.1
		# Abstand so, dass der Bildschirm (mit etwas Rand) das Bild füllt
		var vfov := deg_to_rad(op_cam.fov if op_cam else 55.0)
		var vs := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
		var aspect := vs.x / maxf(vs.y, 1.0)
		var th := tan(vfov * 0.5)
		_dist_t = maxf((SCREEN_SIZE.y + 0.05) * 0.5 / th, (SCREEN_SIZE.x + 0.05) * 0.5 / (th * aspect))
		return
	var was_panel := _panel_view
	_panel_view = false
	match view:
		"top":
			_yaw_t = 0.0
			_pitch_t = -PI / 2.0
		"front":
			_yaw_t = 0.0
			_pitch_t = -0.05
		"back":
			if was_panel and _pre_panel.size() == 4:
				_yaw_t = _pre_panel[0]
				_pitch_t = _pre_panel[1]
				_dist_t = _pre_panel[2]
				cam_pan = _pre_panel[3]
			else:
				set_view("reset")
		_:
			_yaw_t = CAM_YAW
			_pitch_t = CAM_PITCH
			_dist_t = CAM_DIST
			cam_pan = Vector3.ZERO


func _zoom_step(dir: float) -> void:
	_dist_t = clampf(_dist_t * (0.82 if dir > 0.0 else 1.0 / 0.82), CAM_MIN, CAM_MAX)


func _update_screen() -> void:
	if screen_vp == null:
		return
	# Außerhalb der Bedienung reicht ein Bild alle 0,1 s
	screen_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if operating else SubViewport.UPDATE_ONCE


# ======================================================================= Bedienung

func get_prompt() -> String:
	return "[%s] Weiler E50 HD bedienen" % Settings.binding_text("interact")


## Ziel für [E] auf dem Bedienpult: Maschine bedienen und direkt auf den Pult-Bildschirm schauen.
class PultTarget extends Node:
	var lathe: Lathe

	func get_prompt() -> String:
		return "[%s] Bedienpult (Zyklensteuerung)" % Settings.binding_text("interact")

	func interact(p: Node) -> void:
		lathe.interact(p, true)


## Ziel für das Fadenkreuz auf der Schutztür bzw. ihrem schwarzen Hebel: Linksklick auf die Tür
## schiebt sie zum Schlitten (rastet ein), Linksklick auf den Hebel löst sie. [E] bedient die Maschine.
class DoorTarget extends Node:
	var lathe: Lathe
	var lever := false

	func get_prompt() -> String:
		var e := "[%s] Maschine bedienen" % Settings.binding_text("interact")
		if lathe.door_latched or lathe._door_closing:
			if lever:
				return "[Linksklick] Hebel: Schutztür lösen   " + e
			return "Schutztür am Schlitten eingerastet - schwarzer Hebel löst sie   " + e
		return "[Linksklick] Schutztür zum Schlitten schieben   " + e

	func click(_p: Node) -> void:
		if lever:
			lathe.toggle_door()
		else:
			lathe.close_door()

	func interact(p: Node) -> void:
		lathe.interact(p)


## Wird gerade auf den Pult-Bildschirm geschaut? (HUD blendet dann die Dreh-Anzeigen aus)
func in_panel_view() -> bool:
	return _panel_view


func interact(p: Node, panel := false) -> void:
	if demo or operating:
		return
	player = p
	operating = true
	var stand := to_global(Vector3(0.25, 0.0, 1.05))
	p.start_operating(self, stand, global_rotation.y)
	op_cam.fov = float(Settings.graphics["fov"]) * 0.75
	cam_dist = maxf(_dist_t, 0.5)
	if panel:
		set_view("panel")
		cam_yaw = _yaw_t
		cam_pitch = _pitch_t
		cam_dist = _dist_t
		cam_target = screen_center()
	_update_camera(1.0)
	op_cam.make_current()
	operating_changed.emit(true)


func stop_operating() -> void:
	if not operating:
		return
	operating = false
	_screen_drag = false
	if _handle_hover:
		_handle_hover = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if _panel_view:
		set_view("back")
	# Auto-Vorschub läuft weiter (wie die Spindel)
	if player:
		player.stop_operating()
	operating_changed.emit(false)


func hw_axis_name() -> String:
	return "X (Planschlitten)" if hw_axis == 0 else "Z (Bettschlitten)"


## Eine (oder mehrere) Mausrad-Rasten = Handrad der gewählten Achse um je einen Schritt.
## X wird wie an der Anzeige im Durchmesser verfahren. Rad hoch = zustellen bzw. zum Futter.
func _handwheel_turn(notches: float) -> void:
	if _nc_locked() or estop:
		return
	if bool(Settings.mouse.get("handwheel_invert", false)):
		notches = -notches
	var d := notches * Settings.handwheel_step()
	# Kurbeltempo -> Vorschubgeschwindigkeit (für die Oberfläche): schnelles Kurbeln = grober Vorschub
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _hw_last_ms) / 1000.0, 0.03, 1.0)
	_hw_last_ms = now
	_hw_speed = absf(d) * (0.5 if hw_axis == 0 else 1.0) / dt
	if hw_axis == 0:
		auto_feed_x = false
		move_tool(0.0, -d * 0.5)
		hw_x.rotation.z += notches * 0.15
	else:
		auto_feed = false
		move_tool(-d, 0.0)
		hw_z.rotation.z += notches * 0.15


func _unhandled_input(event: InputEvent) -> void:
	if not operating:
		return
	# Klicks auf den Bildschirm am Bedienpult bedienen dessen Menü
	if _screen_input(event):
		get_viewport().set_input_as_handled()
		return
	if _door_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cam_panel"):
		toggle_panel_view()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var dir := 0.0
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dir = 1.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dir = -1.0
		if dir != 0.0:
			# Rechte Maustaste (Kamera-Modus) oder Strg: Zoom, sonst Handrad
			if mb.ctrl_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				_zoom_step(dir)
			else:
				_handwheel_turn(dir * (mb.factor if mb.factor > 0.0 else 1.0))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var inv := -1.0 if bool(Settings.mouse["invert_y"]) else 1.0
		_yaw_t = clampf(_yaw_t - event.relative.x * 0.005, -PI * 0.6, PI * 0.6)
		_pitch_t = clampf(_pitch_t - event.relative.y * 0.005 * inv, -PI / 2.0, 0.25)
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var b := op_cam.transform.basis
		cam_pan += (-b.x * event.relative.x + b.y * event.relative.y) * cam_dist * 0.0015
		cam_pan = cam_pan.limit_length(0.6)
		return
	for v in [["cam_top", "top"], ["cam_front", "front"], ["cam_reset", "reset"]]:
		if event.is_action_pressed(v[0]):
			set_view(v[1])
			get_viewport().set_input_as_handled()
			return
	# Halterplatz mit Zifferntasten 1-4 einschwenken
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc >= KEY_1 and kc < KEY_1 + SLOTS:
			index_slot(kc - KEY_1)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("interact"):
		stop_operating()
	elif event.is_action_pressed("emergency_stop"):
		toggle_estop()
	elif event.is_action_pressed("door_toggle"):
		toggle_door()
	elif event.is_action_pressed("spindle_toggle"):
		toggle_spindle()
	elif event.is_action_pressed("hw_axis"):
		hw_axis = 1 - hw_axis
		_info("Handrad: %s" % hw_axis_name())
	elif event.is_action_pressed("hw_step"):
		Settings.cycle_handwheel_step()
		_info("Handrad-Schritt: %s pro Raste" % Settings.handwheel_step_name())
	elif event.is_action_pressed("rpm_up"):
		step_rpm(1)
	elif event.is_action_pressed("rpm_down"):
		step_rpm(-1)
	elif event.is_action_pressed("feed_up"):
		step_feed(1)
	elif event.is_action_pressed("feed_down"):
		step_feed(-1)
	elif event.is_action_pressed("auto_feed"):
		if auto_feed or auto_feed_x:
			set_auto_feed(-1)
		else:
			set_auto_feed(0 if hw_axis == 0 else 1)
	elif event.is_action_pressed("coolant"):
		coolant = not coolant
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
	var rz_req := float(job.get("rz", 0.0))
	if job.has("length"):
		total += 1
		var l := part_length()
		var want := float(job["length"])
		var pass_l := absf(l - want) <= 0.5
		if pass_l:
			ok += 1
		lines.append("%s  Gesamtlänge %.2f mm  (Soll %.1f +/-0,5)" % [_mark(pass_l), l, want])
	for f in job.get("features", []):
		total += 1
		var pass_f := false
		match str(f.get("type", "dia")):
			"dia":
				var margin := float(f.get("margin", 1.0))
				var a := clampi(int(floor((float(f["z0"]) + margin) / SEG)), 0, profile.size() - 1)
				var b := clampi(int(ceil((float(f["z1"]) - margin) / SEG)) - 1, a, profile.size() - 1)
				var mn := 1.0e9
				var mx := 0.0
				var rz_sum := 0.0
				for i in range(a, b + 1):
					mn = minf(mn, profile[i] * 2.0)
					mx = maxf(mx, profile[i] * 2.0)
					rz_sum += rz[i] if machined[i] else 50.0
				var rz_avg := rz_sum / float(b - a + 1)
				var want_d := float(f["d"])
				var tol := float(f.get("tol", 0.3))
				pass_f = absf(mn - want_d) <= tol and absf(mx - want_d) <= tol
				var rz_txt := "Rz %.1f µm" % rz_avg
				if rz_req > 0.0:
					rz_txt += " (max %.1f)" % rz_req
					pass_f = pass_f and rz_avg <= rz_req
				lines.append("%s  Z %d-%d:  Ø %.2f ... %.2f  (Soll Ø%.1f +/-%.2f)  %s" % [
					_mark(pass_f), int(f["z0"]), int(f["z1"]), mn, mx, want_d, tol, rz_txt])
			"chamfer":
				var c := float(f["size"])
				var zc := float(f["z"]) - c * 0.5
				var meas := radius_at(zc) * 2.0
				var exp_d := float(f["d"]) - c
				var tol_c := float(f.get("tol", 0.4))
				pass_f = absf(meas - exp_d) <= tol_c
				lines.append("%s  Fase %.1f x 45° an Z %d (Ø%d):  Ø %.2f bei Z %.2f  (Soll Ø%.2f +/-%.1f)" % [
					_mark(pass_f), c, int(f["z"]), int(f["d"]), meas, zc, exp_d, tol_c])
			"point":
				var meas_p := radius_at(float(f["z"])) * 2.0
				var tol_p := float(f.get("tol", 0.2))
				pass_f = absf(meas_p - float(f["d"])) <= tol_p
				lines.append("%s  Nutgrund bei Z %.1f:  Ø %.2f  (Soll Ø%.1f +/-%.2f)" % [
					_mark(pass_f), float(f["z"]), meas_p, float(f["d"]), tol_p])
		if pass_f:
			ok += 1
	var score := float(ok) / maxf(total, 1)
	return {"score": score, "ok": ok, "total": total, "lines": lines}


func _mark(ok: bool) -> String:
	return "OK  " if ok else "FEHL"


# ======================================================================= Speichern

func get_state() -> Dictionary:
	var mach: Array = []
	for m in machined:
		mach.append(m)
	return {"seg": SEG, "stock_d": stock_d, "stock_len": stock_len, "profile": Array(profile),
		"machined": mach, "rz": Array(rz), "tool_z": tool_z, "tool_x": tool_x, "tool": tool_idx,
		"holder": holder.duplicate(), "active_slot": active_slot,
		"rpm": rpm_set, "feed": feed_set, "css": css, "vc": vc_set, "rpm_limit": rpm_limit,
		"coolant": coolant, "door": door_latched, "programs": programs.duplicate(true), "prog_sel": prog_sel,
		"wcs_z": wcs_z}


func set_state(d: Dictionary) -> void:
	new_workpiece(float(d.get("stock_d", 60.0)), float(d.get("stock_len", 160.0)))
	var old_seg := float(d.get("seg", 0.5))
	var p = d.get("profile", [])
	var m = d.get("machined", [])
	var r = d.get("rz", [])
	if p is Array and p.size() > 0:
		for i in profile.size():
			var j := clampi(int(floor((i + 0.5) * SEG / old_seg)), 0, p.size() - 1)
			profile[i] = float(p[j])
			if m is Array and j < m.size():
				machined[i] = int(m[j])
			if r is Array and j < r.size():
				rz[i] = float(r[j])
			elif machined[i]:
				rz[i] = 10.0
	tool_z = float(d.get("tool_z", tool_z))
	tool_x = float(d.get("tool_x", tool_x))
	# ältere Spielstände speichern nur Stufen-Indizes
	if d.has("rpm"):
		set_rpm(float(d["rpm"]))
	elif d.has("rpm_idx"):
		set_rpm(float(RPM_STEPS[clampi(int(d["rpm_idx"]), 0, RPM_STEPS.size() - 1)]))
	if d.has("feed"):
		set_feed(float(d["feed"]))
	elif d.has("feed_idx"):
		set_feed(float(FEED_STEPS[clampi(int(d["feed_idx"]), 0, FEED_STEPS.size() - 1)]))
	css = bool(d.get("css", false))
	set_vc(float(d.get("vc", vc_set)))
	set_rpm_limit(float(d.get("rpm_limit", rpm_limit)))
	coolant = bool(d.get("coolant", false))
	set_door(bool(d.get("door", false)))
	var pr = d.get("programs", null)
	if pr is Array and not pr.is_empty():
		programs = pr.duplicate(true)
		prog_sel = str(d.get("prog_sel", ""))
		# ältere Spielstände: Programm-Z ab Backen-Stirnfläche -> WKS (Nullpunkt Rohteil-Stirnfläche)
		for prog in programs:
			NcCam.migrate_to_wks(prog, stock_len)
	wcs_z = float(d.get("wcs_z", stock_len))
	var h = d.get("holder", null)
	if h is Array and h.size() == SLOTS:
		for s in SLOTS:
			var id := str(h[s])
			holder[s] = id if LatheTools.index_of(id) >= 0 and holder.slice(0, s).find(id) < 0 else ""
		active_slot = clampi(int(d.get("active_slot", 0)), 0, SLOTS - 1)
		_apply_holder()
	else:
		select_tool(int(d.get("tool", 0)), true)
	workpiece_mi.mesh = _make_mesh(0, profile.size() - 1, true)


# ======================================================================= Audio

func _setup_audio() -> void:
	_audio = AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _mix
	gen.buffer_length = 0.15
	_audio.stream = gen
	_audio.bus = "SFX"
	_audio.position = Vector3(-0.3, AXIS_H, 0.2)
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
	var motor := clampf(spindle_speed / 2000.0, 0.0, 1.0)
	var on := 1.0 if spindle_speed > 1.0 else 0.0
	var cut := clampf(_cut_level * 1.5 + (0.3 if _cut_t > 0.0 else 0.0), 0.0, 1.0)
	var f1 := 35.0 + spindle_speed * 0.1
	var f2 := f1 * 2.97
	var f3 := 900.0 + spindle_speed * 0.4
	var cool := 1.0 if (coolant and spindle_speed > 10.0) else 0.0
	for i in frames:
		_ph1 = fmod(_ph1 + f1 / _mix, 1.0)
		_ph2 = fmod(_ph2 + f2 / _mix, 1.0)
		_ph3 = fmod(_ph3 + f3 / _mix, 1.0)
		var n := randf() * 2.0 - 1.0
		_lp = lerpf(_lp, n, 0.3)
		var s := (sin(TAU * _ph1) * 0.45 + sin(TAU * _ph2) * 0.15) * (0.25 + motor * 0.75) * on * 0.3
		s += sin(TAU * _ph3) * cut * 0.06 * (0.6 + 0.4 * sin(TAU * _ph1))
		s += (_lp * 0.6 + n * 0.25) * cut * 0.3
		s += n * cool * 0.04
		_pb.push_frame(Vector2(s, s))


## Schneidenkoordinaten (Z, X), wenn Werkzeug id eingeschwenkt wird und der Halterkopf dabei
## an seinem Platz bleibt.
func _coord_after(id: String) -> Vector2:
	var tn := LatheTools.get_tool(maxi(LatheTools.index_of(id), 0))
	var d := tool_offset(tn) - tool_offset(tool())
	return Vector2(clampf(tool_z + d.x, z_min(), Z_MAX), clampf(tool_x + d.y, X_MIN, X_MAX))
