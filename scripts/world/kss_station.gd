class_name KssStation
extends Node3D
## Sichtbarer KSS-Tank („Der Chemiemeister“) seitlich an der E50: Behälter mit Schauglas, Hähnen für
## Wasser und Konzentrat und einem Kanister. [E] öffnet das Auffüll-Panel (scripts/ui/kss_panel.gd).
## Die Welt setzt `world` (Kasse, HUD); ohne Welt (Tests) fallen keine Kosten an.

const PANEL_SCRIPT := "res://scripts/ui/kss_panel.gd"
const TANK_SIZE := Vector3(0.5, 0.62, 0.36)
const GLASS_H := 0.5

var lathe: Lathe
var world: Node = null                 # World: money, hud, pause
var player: Node = null                # Spieler, solange das Panel offen ist
var tank: KssTank

var _panel: Node = null
var _layer: CanvasLayer = null
var _fill: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _foam: MeshInstance3D
var _owed := 0.0                       # noch nicht abgebuchte Bruchteile eines Euro


## `body` ist die Hülle der Maschine in Maschinenkoordinaten; der Tank steht links neben dem Spindelkasten.
func setup(l: Lathe, body: AABB) -> void:
	lathe = l
	tank = l.kss
	position = Vector3(body.position.x - 0.36, 0.0, body.get_center().z)
	_build()
	tank.changed.connect(_refresh)
	tank.concentrate_added.connect(_on_concentrate_added)
	tank.evaluated.connect(_on_evaluated)
	tank.afford = _affordable_liters
	_refresh()


func _build() -> void:
	var steel := Build.mat(Color(0.34, 0.4, 0.47), 0.45, 0.6)
	var dark := Build.mat(Color(0.12, 0.13, 0.15), 0.55, 0.3)
	# Gestell und Behälter
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Build.box(self, Vector3(0.04, 0.2, 0.04), Vector3(sx * 0.2, 0.1, sz * 0.13), dark)
	Build.box(self, TANK_SIZE, Vector3(0, 0.2 + TANK_SIZE.y * 0.5, 0), steel)
	Build.cyl(self, 0.05, 0.03, Vector3(-0.12, 0.2 + TANK_SIZE.y + 0.015, -0.05), dark)
	# Schauglas vorn (+Z) mit Füllsäule
	var gz := TANK_SIZE.z * 0.5
	var gy := 0.2 + 0.06
	Build.box(self, Vector3(0.1, GLASS_H + 0.04, 0.012), Vector3(0.12, gy + GLASS_H * 0.5, gz + 0.004), dark)
	_fill_mat = Build.mat(Color(0.7, 0.85, 0.95, 0.85), 0.2)
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill = Build.box(self, Vector3(0.07, GLASS_H, 0.01), Vector3(0.12, gy, gz + 0.012), _fill_mat)
	Build.box(self, Vector3(0.07, GLASS_H, 0.004), Vector3(0.12, gy + GLASS_H * 0.5, gz + 0.019), Build.glass(Color(0.8, 0.9, 1.0, 0.12)))
	# Schaum auf dem Tank bei zu dickem Gemisch
	_foam = Build.sphere(self, 0.16, Vector3(0.0, 0.2 + TANK_SIZE.y, 0.0), Build.mat(Color(0.97, 0.98, 1.0), 0.9))
	_foam.scale = Vector3(1.3, 0.35, 0.9)
	_foam.visible = false
	# Zwei Hähne links an der Front: Wasser blau, Konzentrat orange
	for i in 2:
		var c := Color(0.2, 0.45, 0.85) if i == 0 else Color(0.95, 0.5, 0.1)
		var hx := -0.14 - i * 0.0
		var hy := 0.52 - i * 0.14
		Build.cyl(self, 0.014, 0.06, Vector3(hx, hy, gz + 0.03), dark, Build.AXIS_Z)
		Build.cyl(self, 0.03, 0.015, Vector3(hx, hy + 0.04, gz + 0.03), Build.mat(c, 0.4), Build.AXIS_Y)
		Build.label(self, "H2O" if i == 0 else "KONZ.", Vector3(hx - 0.07, hy, gz + 0.012), 0.0014, Color(0.9, 0.92, 0.95), 48)
	# Kanister mit Konzentrat daneben
	var can := Build.mat(Color(0.95, 0.5, 0.1), 0.5)
	Build.box(self, Vector3(0.16, 0.24, 0.1), Vector3(0.38, 0.12, 0.12), can)
	Build.box(self, Vector3(0.05, 0.04, 0.05), Vector3(0.34, 0.26, 0.12), can)
	Build.cyl(self, 0.016, 0.02, Vector3(0.34, 0.3, 0.12), dark)
	Build.box(self, Vector3(0.1, 0.07, 0.002), Vector3(0.38, 0.14, 0.171), Build.mat(Color(0.95, 0.95, 0.9), 0.8))
	# Klickfläche über Tank und Kanister
	var hit := Build.collider(self, Vector3(0.95, 0.9, 0.5), Vector3(0.12, 0.45, 0.06))
	hit.set_meta("interact", self)


func _refresh() -> void:
	if tank == null or _fill == null:
		return
	var f := maxf(tank.fill_fraction(), 0.001)
	_fill.scale = Vector3(1, f, 1)
	_fill.position.y = 0.26 + GLASS_H * f * 0.5
	# Dünn bläulich-klar, dick milchig
	var t := clampf(tank.concentration() / 10.0, 0.0, 1.0)
	_fill_mat.albedo_color = Color(0.65, 0.85, 0.98, 0.7).lerp(Color(0.98, 0.97, 0.9, 0.95), t)
	_foam.visible = tank.foaming() and tank.fill_fraction() > 0.9


func get_prompt() -> String:
	return "[%s] KSS auffüllen (Füllstand %d %%, %s %%)" % [Settings.binding_text("interact"),
		int(round(tank.fill_fraction() * 100.0)), ("%.1f" % tank.concentration()).replace(".", ",")]


func interact(p: Node) -> void:
	if player != null or tank == null:
		return
	var script: Script = load(PANEL_SCRIPT)
	if script == null:
		_say("KSS-Panel nicht verfügbar.")
		return
	player = p
	_panel = script.new()
	_panel.setup(tank, "KSS-Tank - %s" % lathe.machine_title())
	_panel.closed.connect(_close)
	# Vollbild-Overlay wie der PC: das Panel ist ein Control, also in eine eigene Canvas-Ebene.
	# Esc und E behandelt allein das Panel (close -> closed).
	_layer = CanvasLayer.new()
	add_child(_layer)
	_layer.add_child(_panel)
	var stand := to_global(Vector3(0.1, 0.0, 0.95))
	stand.y = p.global_position.y
	p.start_operating(self, stand, global_transform.basis.get_euler().y)
	p.pitch = -0.2
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Panel zu: Spieler freigeben, Panel abbauen.
func _close() -> void:
	if player == null:
		return
	player.stop_operating()
	player = null
	var layer := _layer
	_panel = null
	_layer = null
	if is_instance_valid(layer):
		layer.queue_free()
	# Euro-Bruchteile aufrunden und abbuchen
	if world != null and _owed > 0.0:
		world.money = maxi(int(world.money) - 1, 0)
		_owed = 0.0


# ======================================================================= Kosten

func _price() -> float:
	return KssTank.PRICE_PER_L


## Höchstens bezahlbare Konzentratmenge; ohne Welt unbegrenzt.
func _affordable_liters(_wanted: float) -> float:
	if world == null:
		return INF
	var spendable := maxf(float(world.money) - _owed, 0.0)
	var l := spendable / _price()
	if l <= 0.0:
		_say("Nicht genug Geld für Konzentrat (%d EUR/L)." % int(_price()))
	return l


## Konzentrat wird verbraucht: Euro abbuchen, Bruchteile sammeln sich bis zum nächsten vollen Euro.
func _on_concentrate_added(liters: float) -> void:
	if world == null:
		return
	_owed += liters * _price()
	var whole := int(_owed)
	if whole > 0:
		world.money = int(world.money) - whole
		_owed -= float(whole)


func _on_evaluated(s: int) -> void:
	var title := KssTank.state_title(s as KssTank.State)
	var c := ("%.1f" % tank.concentration()).replace(".", ",")
	match s:
		KssTank.State.OPTIMAL:
			_say("KSS %s: %s %% Konzentrat. Schnellere Bearbeitung (+10 %%)." % [title, c], Color(0.5, 1.0, 0.6))
		KssTank.State.ZU_DUENN:
			_say("KSS %s: nur %s %%. Werkzeug verschleißt doppelt so schnell!" % [title, c], Color(1.0, 0.5, 0.4))
		KssTank.State.ZU_DICK:
			var pen := int(ceil(tank.foam_penalty() - 0.001))
			if world != null:
				pen = mini(pen, maxi(int(world.money), 0))
				world.money = int(world.money) - pen
			_say("KSS %s: %s %%. Schaum! Verschwendetes Konzentrat kostet %d EUR." % [title, c, pen], Color(1.0, 0.6, 0.3))
		_:
			_say("KSS %s: %s %% Konzentrat. Weder Vor- noch Nachteil." % [title, c], Color(0.9, 0.95, 1.0))


func _say(text: String, color := Color(1.0, 0.75, 0.2)) -> void:
	if world != null and world.get("hud") != null:
		world.hud.show_message(text, color)
	elif lathe != null:
		lathe.message.emit(text, color)
