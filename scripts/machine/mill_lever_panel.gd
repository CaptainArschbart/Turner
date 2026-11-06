class_name MillLeverPanel
extends Node
## Bedienfeld der Fräsmaschine als eigene Station: wird wie eine Maschine anvisiert und mit E bedient.

var mill: Mill


func get_prompt() -> String:
	return "[%s] Bedienfeld benutzen" % Settings.binding_text("interact")


func interact(p: Node) -> void:
	mill.open_levers(p)
