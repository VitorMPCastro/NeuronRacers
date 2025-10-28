extends BaseNode
class_name ClampNode

@export var clamp_min: float = 0.0
@export var clamp_max: float = 1.0

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
	var max_val := float(vals[0])
	for v in vals:
		max_val = max(max_val, float(v))
	return clamp(max_val, clamp_min, clamp_max)
