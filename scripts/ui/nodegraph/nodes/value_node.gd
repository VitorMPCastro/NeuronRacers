extends BaseNode
class_name ValueNode

@export var variable_name: String = "value"

func _ready() -> void:
	configure_ports([], [{"name":"out","max":-1}])
	# UI: label showing variable_name (left as TODO for scene)
	pass

func evaluate() -> Variant:
	# TODO: Retrieve from Data API; sanitize
	var val := 0.0
	# Example safe cast:
	if typeof(val) in [TYPE_INT, TYPE_FLOAT]:
		return val
	return 0.0
