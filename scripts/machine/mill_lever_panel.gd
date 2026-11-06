class_name MillLeverPanel
extends Node
## Hebelfeld der Fräsmaschine als eigene Station: wird wie eine Maschine anvisiert und mit E bedient.

var mill: Mill


func get_prompt() -> String:
	return "[%s] Hebelfeld bedienen" % Settings.binding_text("interact")


func interact(p: Node) -> void:
	mill.open_levers(p)
