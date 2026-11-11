class_name ToolMount
extends Node
## Werkzeugaufnahme einer Maschine als Ziel für den Sichtstrahl: Linksklick setzt das Werkzeug aus
## der Hand ein oder nimmt eines heraus (Drehmaschine: öffnet das Fenster mit allen Halterplätzen),
## E bedient wie gewohnt die Maschine.

var machine: Node
var player: Node
## Fenster mit allen Halterplätzen (Drehmaschine), sonst null: Linksklick spannt direkt ein bzw. aus
var dialog: Node


func get_prompt() -> String:
	var hand: String = "[Linksklick] Werkzeughalter: Werkzeuge ein- und ausspannen" if dialog != null else machine.hand_prompt(player.held)
	return machine.get_prompt() if hand == "" else "%s    |    %s" % [machine.get_prompt(), hand]


func get_machine() -> Node:
	return machine


func interact(p: Node) -> void:
	machine.interact(p)


func click(p: Node) -> void:
	if dialog != null:
		dialog.open(machine)
	else:
		machine.hand_click(p)
