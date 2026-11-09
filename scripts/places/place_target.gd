class_name PlaceTarget
extends Node
## Ziel für den Sichtstrahl an einem Ort (Tür, Kasse, Bett): fester Hinweis und eine Aktion für Interagieren
## und Linksklick, die den Spieler bekommt.

var prompt := ""
var action: Callable              # (Spieler)


func get_prompt() -> String:
	return "[%s] %s" % [Settings.binding_text("interact"), prompt]


func interact(p: Node) -> void:
	action.call(p)


func click(p: Node) -> void:
	action.call(p)
