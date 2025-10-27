extends NodeBase
class_name ClampNode

@export var min_value: float = 0.0
@export var max_value: float = 1.0

func _ready() -> void:
	title = "Clamp"
	_build_ui()
	add_input_port("Values", 1024)
	add_output_port("Result", true)
	var hb := HBoxContainer.new()
	var l1 := Label.new(); l1.text = "Min"
	var sb1 := SpinBox.new(); sb1.min_value = -1e9; sb1.max_value = 1e9; sb1.value = min_value
	sb1.connect("value_changed", func(v): min_value = v)
	var l2 := Label.new(); l2.text = "Max"
	var sb2 := SpinBox.new(); sb2.min_value = -1e9; sb2.max_value = 1e9; sb2.value = max_value
	sb2.connect("value_changed", func(v): max_value = v)
	hb.add_child(l1); hb.add_child(sb1); hb.add_child(l2); hb.add_child(sb2)
	add_internal_field(hb)

func evaluate_output(_port_index: int) -> float:
	var vals := get_input_values(0)
	var v := 0.0
	if vals.size() > 0:
		v = _sanitize_number(vals.max())
	return clampf(v, min(min_value, max_value), max(min_value, max_value))

func compile_output_expression(_port_index: int) -> String:
	var exprs := graph.compile_port_expr(self, 0)
	var v := "0"
	if exprs.size() > 0:
		if exprs.size() == 1:
			v = "(" + exprs[0] + ")"
		else:
			var acc := "max(" + exprs[0] + ", " + exprs[1] + ")"
			for i in range(2, exprs.size()):
				acc = "max(" + acc + ", " + exprs[i] + ")"
			v = "(" + acc + ")"
	var mn := str(min(min_value, max_value))
	var mx := str(max(min_value, max_value))
	return "min(max(" + v + ", " + mn + "), " + mx + ")"