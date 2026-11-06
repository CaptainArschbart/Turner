class_name ToolMount
extends Node
## Werkzeugaufnahme einer Maschine als Ziel für den Sichtstrahl: Linksklick setzt das Werkzeug aus
## der Hand ein oder nimmt eines heraus, E bedient wie gewohnt die Maschine.

var machine: Node
var player: Node


func get_prompt() -> String:
	var hand: String = machine.hand_prompt(player.held)
	return machine.get_prompt() if hand == "" else "%s    |    %s" % [machine.get_prompt(), hand]


func interact(p: Node) -> void:
	machine.interact(p)


func click(p: Node) -> void:
	machine.hand_click(p)
