extends Control
## Sucht-Meter im HUD: Halbkreis-Skala mit Zeiger. Rechts voll (gerade geraucht), links leer (Entzug).
## Der Zeiger folgt dem Wert gedämpft, im Entzug zittert er am Anschlag und die Skala blinkt rot.

const W := 132.0
const H := 86.0
const SWEEP := Vector2(PI, TAU)   # Winkel links (leer) bis rechts (voll), oben herum

var value := 1.0                  # Sollwert 0..1
var shown := 1.0                  # Zeigerstellung 0..1
var craving := false
var lit := false
var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	shown = lerpf(shown, value, clampf(delta * 4.0, 0.0, 1.0))
	queue_redraw()


func needle_angle() -> float:
	var v := shown
	if craving:
		v += sin(_t * 31.0) * 0.012 + 0.012
	return lerpf(SWEEP.x, SWEEP.y, clampf(v, 0.0, 1.0))


func _draw() -> void:
	var c := Vector2(W * 0.5, H - 22.0)
	var r := 50.0
	draw_style_box(UITheme.hud_style(), Rect2(Vector2.ZERO, size))
	# Skala: rot - gelb - grün
	var zones := [[0.0, Cigarette.NEED_LOW, UITheme.BAD], [Cigarette.NEED_LOW, 0.45, UITheme.WARN], [0.45, 1.0, UITheme.GOOD]]
	for z in zones:
		var col: Color = z[2]
		if craving and z[0] == 0.0:
			col = col.lerp(Color.WHITE, 0.35 * (0.5 + 0.5 * sin(_t * 8.0)))
		draw_arc(c, r, lerpf(SWEEP.x, SWEEP.y, z[0]), lerpf(SWEEP.x, SWEEP.y, z[1]), 24, col, 7.0, true)
	for i in 6:
		var a := lerpf(SWEEP.x, SWEEP.y, i / 5.0)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r - 9.0), c + d * (r - 4.0), UITheme.TEXT, 1.5, true)
	# Zeiger
	var na := needle_angle()
	var tip := c + Vector2(cos(na), sin(na)) * (r - 6.0)
	draw_line(c, tip, Color(0.95, 0.95, 0.95), 2.5, true)
	draw_circle(c, 4.5, Color(0.95, 0.95, 0.95))
	var font := UITheme.font(600, 2)
	var text := "ENTZUG" if craving else ("RAUCHT" if lit else "SUCHT")
	var tcol := UITheme.BAD if craving else (UITheme.GOOD if lit else UITheme.TEXT)
	draw_string(font, Vector2(0, H - 5.0), text, HORIZONTAL_ALIGNMENT_CENTER, W, 13, tcol)
