extends NodeBase
class_name MathNode

enum Op { ADD, SUB, MUL, DIV, POW, AVG }
enum RoundMode { NONE, ROUND, FLOOR, CEIL }

@export var op: Op = Op.ADD
@export var rounding: RoundMode = RoundMode.NONE
@export var decimals: int = 2

var _op_select: OptionButton
var _round_select: OptionButton
var _dec_spin: SpinBox

func _ready() -> void:
	title = "Math"
	_build_ui()
	add_input_port("Values", 1024)
	add_output_port("Result", true)

	_op_select = OptionButton.new()
	_op_select.add_item("Add", Op.ADD)
	_op_select.add_item("Sub", Op.SUB)
	_op_select.add_item("Mul", Op.MUL)
	_op_select.add_item("Div", Op.DIV)
	_op_select.add_item("Pow", Op.POW)
	_op_select.add_item("Avg", Op.AVG)
	_op_select.selected = int(op)
	_op_select.connect("item_selected", func(i): op = i)
	add_internal_field(_op_select)

	_round_select = OptionButton.new()
	_round_select.add_item("None", RoundMode.NONE)
	_round_select.add_item("Round", RoundMode.ROUND)
	_round_select.add_item("Floor", RoundMode.FLOOR)
	_round_select.add_item("Ceil", RoundMode.CEIL)
	_round_select.selected = int(rounding)
	_round_select.connect("item_selected", func(i): rounding = i)
	add_internal_field(_round_select)

	_dec_spin = SpinBox.new()
	_dec_spin.min_value = 0
	_dec_spin.max_value = 6
	_dec_spin.step = 1
	_dec_spin.value = decimals
	_dec_spin.connect("value_changed", func(v): decimals = int(v))
	add_internal_field(_dec_spin)

func evaluate_output(_port_index: int) -> float:
	var vals := get_input_values(0)
	if vals.is_empty():
		vals = [0.0]
	for i in range(vals.size()):
		vals[i] = _sanitize_number(vals[i])

	var res := 0.0
	match op:
		Op.ADD:
			for v in vals: res += v
		Op.SUB:
			res = vals[0]
			for i in range(1, vals.size()): res -= vals[i]
		Op.MUL:
			res = 1.0
			for v in vals: res *= v
		Op.DIV:
			res = vals[0]
			for i in range(1, vals.size()):
				var d = vals[i]
				res = res / (d if abs(d) > 1e-9 else 1.0)
		Op.POW:
			res = vals[0]
			for i in range(1, vals.size()):
				res = pow(res, clampf(vals[i], -16.0, 16.0))
		Op.AVG:
			for v in vals: res += v
			res = res / max(1, vals.size())

	match rounding:
		RoundMode.NONE:
			pass
		RoundMode.ROUND:
			var m := pow(10.0, clampf(decimals, 0, 6))
			res = round(res * m) / m
		RoundMode.FLOOR:
			var m2 := pow(10.0, clampf(decimals, 0, 6))
			res = floor(res * m2) / m2
		RoundMode.CEIL:
			var m3 := pow(10.0, clampf(decimals, 0, 6))
			res = ceil(res * m3) / m3

	return _sanitize_number(res)

func compile_output_expression(_port_index: int) -> String:
	var exprs := graph.compile_port_expr(self, 0)
	if exprs.is_empty():
		exprs = ["0"]

	var base := ""
	match op:
		Op.ADD:
			base = "(" + " + ".join(exprs) + ")"
		Op.SUB:
			base = "(" + exprs[0] + ("" if exprs.size() == 1 else " - " + " - ".join(exprs.slice(1, exprs.size()))) + ")"
		Op.MUL:
			base = "(" + " * ".join(exprs) + ")"
		Op.DIV:
			if exprs.size() == 1:
				base = "(" + exprs[0] + ")"
			else:
				base = "(" + exprs[0] + ")"
				for i in range(1, exprs.size()):
					base = "(" + base + " / max(1e-9, " + exprs[i] + "))"
		Op.POW:
			if exprs.size() == 1:
				base = "(" + exprs[0] + ")"
			else:
				base = "(" + exprs[0] + ")"
				for i in range(1, exprs.size()):
					base = "pow(" + base + ", clamp(" + exprs[i] + ", -16.0, 16.0))"
		Op.AVG:
			base = "((" + " + ".join(exprs) + ") / " + str(max(1, exprs.size())) + ")"

	match rounding:
		RoundMode.NONE:
			return base
		RoundMode.ROUND:
			var m := "pow(10.0, " + str(clampi(decimals, 0, 6)) + ")"
			return "(round(" + base + " * " + m + ") / " + m + ")"
		RoundMode.FLOOR:
			var m2 := "pow(10.0, " + str(clampi(decimals, 0, 6)) + ")"
			return "(floor(" + base + " * " + m2 + ") / " + m2 + ")"
		RoundMode.CEIL:
			var m3 := "pow(10.0, " + str(clampi(decimals, 0, 6)) + ")"
			return "(ceil(" + base + " * " + m3 + ") / " + m3 + ")"
	return base