extends BaseNode
class_name FitnessNode

signal apply_requested(graph: Node)

func _ready() -> void:
	configure_ports([{"name":"in","max":1}], []) # single input, no outputs

func on_apply_pressed() -> void:
	if get_parent() and get_parent().has_method("evaluate_fitness"):
		var res = get_parent().call("evaluate_fitness")
		# normalize result: string error or null
		var _err := ""
		if typeof(res) == TYPE_STRING and res != "":
			_err = res
		emit_signal("apply_requested", get_parent())
