class_name SimpleMachine
extends Node3D
## Gekaufte Maschine, die schon aufgestellt werden kann, aber noch keine Bedienung hat.

var id := ""


func _ready() -> void:
	var spec: Dictionary = Layout.SPECS[id]
	var foot: Rect2 = spec["foot"]
	var center := foot.get_center()
	var h := 1.5
	var body := Build.mat(Color(0.72, 0.74, 0.76), 0.5, 0.2)
	var dark := Build.mat(Color(0.2, 0.22, 0.25), 0.6)
	Build.box(self, Vector3(foot.size.x, 0.3, foot.size.y), Vector3(center.x, 0.15, center.y), dark)
	Build.box(self, Vector3(foot.size.x, h - 0.3, foot.size.y), Vector3(center.x, 0.3 + (h - 0.3) * 0.5, center.y), body)
	Build.label(self, str(spec["title"]), Vector3(center.x, h - 0.2, foot.end.y + 0.005), 0.0025, Color(0.1, 0.1, 0.12), 48)
	var hit := Build.collider(self, Vector3(foot.size.x, h, foot.size.y), Vector3(center.x, h * 0.5, center.y))
	hit.set_meta("interact", self)


func get_prompt() -> String:
	return "%s: lässt sich noch nicht bedienen" % Layout.SPECS[id]["title"]


func interact(_p: Node) -> void:
	pass
