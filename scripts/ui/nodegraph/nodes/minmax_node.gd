extends NodeBase
class_name MinMaxNode

@export_enum("Max", "Min") var mode: String = "Max"

func _ready() -> void:
	title = "Min/Max"
	_build_ui()
	add_input_port("Values", 1024)
	add_output_port("Result", true)

func evaluate_output(_port_index: int) -> float:
	var vals := get_input_values(0)
	if vals.is_empty():
		return 0.0
	var res := _sanitize_number(vals[0])
	for i in range(1, vals.size()):
		var v := _sanitize_number(vals[i])
		if mode == "Max":
			if v > res: res = v
		else:
			if v < res: res = v
	return res

func compile_output_expression(_port_index: int) -> String:
	var exprs := graph.compile_port_expr(self, 0)
	if exprs.is_empty():
		return "0"
	if exprs.size() == 1:
		return "(" + exprs[0] + ")"
	var acc := "(" + exprs[0] + ")"
	if mode == "Max":
		for i in range(1, exprs.size()):
			acc = "max(" + acc + ", " + exprs[i] + ")"
	else:
		for i in range(1, exprs.size()):
			acc = "min(" + acc + ", " + exprs[i] + ")"
	return "(" + acc + ")"