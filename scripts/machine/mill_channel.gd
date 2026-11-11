class_name MillChannel
extends RefCounted
## NC-Kanal der CNC-Fräsmaschine (CncMill): arbeitet die Schrittliste ab, die MillNc.compile() liefert.
## Aufbau wie NcChannel der Drehmaschine. Zustände: idle (Reset), run, hold (NC-Stopp, Tür auf,
## Einzelsatz, programmierter Halt), done (beendet), error (Alarm).
##
## Öffentliche Schnittstelle
##   var mill: CncMill        Maschine
##   var state: String        "idle" | "run" | "hold" | "done" | "error"
##   var lines: Array         Programmtext des laufenden Programms
##   var prog_name: String    Programmname
##   var ops: Array           komplette Schrittliste (Ops von MillNc.compile), nur lesen (Grafik)
##   var op_i: int            Index des Schritts, der gerade dran ist (ops[0 .. op_i-1] sind erledigt)
##   var line: int            Zeilenindex des aktuellen Satzes in lines (-1 = keiner)
##   var single_block: bool   Einzelsatz: nach jedem Satz Halt (weiter mit nc_start)
##   var feed_ovr: float      Vorschub-Override 0 .. OVR_MAX (1,5), 0 hält den Vorschub an
##   var rapid_ovr: float     Eilgang-Override 0 .. 1
##   var run_time: float      Laufzeit des Programms (s, ohne Halt)
##   var alarm: String        Alarmtext (state == "error")
##   var hold_reason: String  Grund des Halts (state == "hold")
##   var compiled: Dictionary Ergebnis von MillNc.compile (blk, time, tools, ...)
##   func busy() -> bool                      läuft oder angehalten
##   func state_text() -> String              Zustand als Text für die Anzeige
##   func nc_start(prog_lines: Array, name := "") -> bool   starten bzw. nach Halt fortsetzen (Fehler: false + Meldung)
##   func start_ops(op_list: Array, name := "") -> bool     Schrittliste direkt starten (Tests, Wechsel)
##   func nc_stop(reason := "NC-Stopp")       anhalten, Vorschub steht
##   func reset()                             abbrechen, Zustand idle, Spindel und KSS aus
##   func step(delta: float)                  aus _physics_process der Maschine aufrufen
##   func remaining() -> Vector3              Restweg des aktuellen Verfahrsatzes (Programmkoordinaten)
##   func progress() -> float                 0..1 grober Fortschritt (Schritte)
## Signale gibt es nicht: Meldungen laufen über mill.message, Zustandsänderungen lassen sich an state ablesen.

const OVR_MAX := 1.5
const SPIN_OK := 0.9          # Vorschubbewegungen erst ab diesem Anteil der Solldrehzahl

var mill: CncMill
var state := "idle"
var lines: Array = []
var prog_name := ""
var ops: Array = []
var op_i := 0
var line := -1
var single_block := false
var feed_ovr := 1.0:
	set(v):
		feed_ovr = clampf(snappedf(v, 0.01), 0.0, OVR_MAX)
var rapid_ovr := 1.0:
	set(v):
		rapid_ovr = clampf(snappedf(v, 0.01), 0.0, 1.0)
var run_time := 0.0
var alarm := ""
var hold_reason := ""
var compiled: Dictionary = {}
var _dwell := -1.0
var _spin_want := false       # Programm will die Spindel laufen haben (nach Halt wieder anschalten)
var _sb_go := false           # Einzelsatz: der nächste Satz darf beginnen
var _blk_seen := false
var _tool_asked := false


func _init(m: CncMill) -> void:
	mill = m


func busy() -> bool:
	return state == "run" or state == "hold"


func state_text() -> String:
	match state:
		"run":
			return "läuft"
		"hold":
			return "angehalten (%s)" % hold_reason
		"done":
			return "beendet"
		"error":
			return "Alarm"
	return "Reset"


func progress() -> float:
	return 0.0 if ops.is_empty() else clampf(float(op_i) / float(ops.size()), 0.0, 1.0)


## NC-Start: Programm übersetzen und starten, im Halt (NC-Stopp, Tür, Einzelsatz) fortsetzen.
func nc_start(prog_lines: Array, name := "") -> bool:
	if not mill.is_ready():
		return _refuse("Steuerung ist aus - erst einschalten.")
	if mill.estop:
		return _refuse("Not-Halt aktiv - erst quittieren.")
	if not mill.door_closed():
		return _refuse("Kabinentür offen - NC-Start nur bei geschlossener Tür.")
	if state == "hold":
		state = "run"
		hold_reason = ""
		_sb_go = true
		mill._info("NC-Start: Programm wird fortgesetzt.")
		return true
	if state == "run":
		return true
	if mill.changing:
		return _refuse("Werkzeugwechsel läuft noch.")
	if prog_lines.is_empty():
		return _refuse("Kein Programm angewählt.")
	var res := MillNc.compile(prog_lines, mill.nc_context())
	var errs: Array = res["errs"]
	if not errs.is_empty():
		return _refuse(str(errs[0]))
	compiled = res
	lines = prog_lines.duplicate()
	return _begin(res["ops"], name if name != "" else str(res["name"]))


## Schrittliste (Format von MillNc.compile) ohne Übersetzen starten.
func start_ops(op_list: Array, name := "") -> bool:
	if not mill.is_ready():
		return _refuse("Steuerung ist aus - erst einschalten.")
	if mill.estop:
		return _refuse("Not-Halt aktiv - erst quittieren.")
	if not mill.door_closed():
		return _refuse("Kabinentür offen - NC-Start nur bei geschlossener Tür.")
	if busy():
		return false
	compiled = {}
	lines = []
	return _begin(op_list, name)


func _begin(op_list: Array, name: String) -> bool:
	ops = op_list.duplicate(true)
	op_i = 0
	line = -1
	prog_name = name
	state = "run"
	alarm = ""
	hold_reason = ""
	run_time = 0.0
	_dwell = -1.0
	_spin_want = false
	_sb_go = false
	_blk_seen = false
	_tool_asked = false
	mill.auto_axis = -1
	mill._info("NC-Start: %s" % name)
	return true


func nc_stop(reason := "NC-Stopp") -> void:
	if state == "run":
		state = "hold"
		hold_reason = reason


func reset() -> void:
	if busy() or state == "error":
		mill.spindle_on = false
		mill.coolant = false
	state = "idle"
	ops = []
	op_i = 0
	line = -1
	alarm = ""
	hold_reason = ""
	_dwell = -1.0
	_spin_want = false


func _refuse(text: String) -> bool:
	mill._warn(text)
	return false


func _fail(text: String) -> void:
	state = "error"
	alarm = text
	mill.spindle_on = false
	mill.coolant = false
	mill.message.emit("Alarm: " + text, Color(1, 0.3, 0.25))


## Restweg des aktuellen Verfahrsatzes in Programmkoordinaten.
func remaining() -> Vector3:
	if not busy() or op_i >= ops.size():
		return Vector3.ZERO
	var op: Dictionary = ops[op_i]
	if str(op["op"]) != "mv":
		return Vector3.ZERO
	return (op["to"] as Vector3) - mill.pos()


# ======================================================================= Ablauf

func step(delta: float) -> void:
	if not busy():
		return
	if mill.estop:
		_fail("Not-Halt - Programm abgebrochen.")
		return
	if not mill.is_ready():
		_fail("Steuerung ausgeschaltet - Programm abgebrochen.")
		return
	if not mill.door_closed():
		if state == "run":
			state = "hold"
			hold_reason = "Kabinentür offen"
			mill._warn("Kabinentür offen - Vorschub und Spindel gestoppt.")
		mill.spindle_on = false
		return
	if state != "run":
		return
	run_time += delta
	var t_left := delta
	var guard := 0
	while t_left > 0.0 and state == "run" and op_i < ops.size() and guard < 400:
		guard += 1
		var op: Dictionary = ops[op_i]
		match str(op["op"]):
			"blk":
				var n := int(op.get("n", 0))
				if single_block and _blk_seen and n != line and not _sb_go:
					state = "hold"
					hold_reason = "Einzelsatz"
					return
				_sb_go = false
				_blk_seen = true
				line = n
				op_i += 1
			"tool":
				if not _do_tool(op):
					return
			"spindle":
				_spin_want = bool(op["on"])
				mill.spindle_on = _spin_want
				op_i += 1
			"coolant":
				mill.coolant = bool(op["on"])
				op_i += 1
			"mv":
				t_left = _do_move(op, t_left)
			"dwell":
				if _dwell < 0.0:
					_dwell = float(op["t"])
				_dwell -= t_left
				if _dwell <= 0.0:
					t_left = -_dwell
					_dwell = -1.0
					op_i += 1
				else:
					t_left = 0.0
			"stop":
				op_i += 1
				state = "hold"
				hold_reason = "Programmierter Halt"
			"end":
				op_i += 1
				mill.spindle_on = false
				mill.coolant = false
				_spin_want = false
				state = "done"
				line = -1
				@warning_ignore("integer_division")
				mill._info("Programm %s beendet (%d:%02d min)." % [prog_name, int(run_time) / 60, int(run_time) % 60])
			_:
				op_i += 1


## Werkzeugwechsel abwarten bzw. anstoßen. false = in diesem Bild nichts mehr tun.
func _do_tool(op: Dictionary) -> bool:
	var t := int(op["t"])
	if mill.tool_t == t and not mill.changing:
		if float(op.get("s", 0.0)) > 0.0:
			mill.set_rpm(float(op["s"]))
		_tool_asked = false
		op_i += 1
		return true
	if mill.changing:
		return false
	mill.spindle_on = false
	_spin_want = false
	if mill.spindle_speed > 5.0:
		return false        # Spindel erst auslaufen lassen
	if _tool_asked:
		# Wechsel ist durch, aber das Werkzeug stimmt nicht: Abbruch
		_tool_asked = false
		_fail("Werkzeugwechsel auf T%d nicht möglich." % t)
		return false
	var err := mill.tool_change(t)
	if err != "":
		_fail(err)
		return false
	_tool_asked = true
	return false


## Einen Verfahrsatz abarbeiten; gibt die übrige Zeit dieses Bildes zurück.
func _do_move(op: Dictionary, t_left: float) -> float:
	var rapid := bool(op["rapid"])
	if _spin_want and not mill.spindle_on:
		mill.spindle_on = true       # nach Halt oder Tür wieder hochlaufen lassen
	var spd: float
	if rapid:
		spd = MillNc.RAPID / 60.0 * rapid_ovr
	else:
		if _spin_want and mill.spindle_speed < mill.rpm_set * SPIN_OK:
			return 0.0
		spd = float(op["f"]) / 60.0 * feed_ovr
	if spd <= 0.0:
		return 0.0
	var tgt: Vector3 = (op["to"] as Vector3) + mill.datum
	var here := Vector3(mill.tool_x, mill.tool_y, mill.tool_z)
	var d := tgt - here
	var dist := d.length()
	if dist < 0.0005:
		op_i += 1
		return t_left
	var travel := minf(dist, spd * t_left)
	var dv := d / dist * travel
	mill.move_tool(dv.x, dv.y, dv.z, spd)
	if mill.estop:
		_fail("Kollision - Programm abgebrochen.")
		return 0.0
	var moved := Vector3(mill.tool_x, mill.tool_y, mill.tool_z) - here
	if moved.length() < travel * 0.5 - 0.001:
		var p := mill.pos()
		_fail("Bewegung blockiert bei X%.3f Y%.3f Z%.3f (Verfahrgrenze oder Meldung beachten)." % [p.x, p.y, p.z])
		return 0.0
	if travel >= dist - 0.00001:
		mill.tool_x = tgt.x
		mill.tool_y = tgt.y
		mill.tool_z = tgt.z
		mill._sync_axes()
		op_i += 1
	return t_left - travel / spd
