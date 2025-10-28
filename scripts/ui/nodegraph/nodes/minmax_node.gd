extends BaseNode
class_name MinMaxNode

@export var mode_max: bool = true # true=max, false=min

func _ready() -> void:
	configure_ports([{}], [{"name":"out","max":-1}])

func evaluate() -> Variant:
	var vals := []
	for i in inputs:
		for c in i["connections"]:
			if c.node and c.node.has_method("evaluate"):
				vals.append(c.node.evaluate())
	if vals.size() == 0:
		return 0.0
	var nums := []
	for v in vals:
		nums.append(float(v))
	return (nums.max() if mode_max else nums.min())
