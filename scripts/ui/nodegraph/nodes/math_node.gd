extends BaseNode
class_name MathNode

enum Op { ADD, SUB, MUL, DIV }
enum RoundMode { NONE, FLOOR, CEIL, ROUND }

@export var operation: int = Op.ADD
@export var rounding: int = RoundMode.NONE

func _ready() -> void:
	configure_ports([], [{"name":"out","max":-1}]) # inputs can be dynamic via UI

func evaluate() -> Variant:
	var vals := []
	for i in inputs:
		for c in i["connections"]:
			if c.has("node") and is_instance_valid(c["node"]) and c["node"].has_method("evaluate"):
				vals.append(c["node"].evaluate())
	if vals.size() == 0:
		return 0.0
	var result := 0.0
	match operation:
		Op.ADD:
			for v in vals:
				result += float(v)
		Op.SUB:
			result = float(vals[0])
			for idx in range(1, vals.size()):
				result -= float(vals[idx])
		Op.MUL:
			result = 1.0
			for v in vals:
				result *= float(v)
		Op.DIV:
			result = float(vals[0])
			for idx in range(1, vals.size()):
				var divisor = float(vals[idx])
				if divisor == 0.0:
					continue
				result /= divisor

	match rounding:
		RoundMode.FLOOR:
			result = floor(result)
		RoundMode.CEIL:
			result = ceil(result)
		RoundMode.ROUND:
			result = int(round(result))
		_:
			# NONE -> do nothing
			pass
	return result
