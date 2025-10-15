extends Resource
class_name MLP

var input_size: int
var hidden_size: int
var output_size: int

var w1: PackedFloat32Array
var b1: PackedFloat32Array
var w2: PackedFloat32Array
var b2: PackedFloat32Array

func _to_string() -> String:
	return str("\ninput: ", input_size, "\nhidden: ", hidden_size, "\noutput: ", output_size, "\nw1: ", w1, "\nb1: ", b1, "\nw2: ", w2, "\nb2: ", b2)
 
func _init(p_input_size: int, p_hidden_size: int, p_output_size: int):
	self.input_size = p_input_size
	self.hidden_size = p_hidden_size
	self.output_size = p_output_size
	
	# Inicializa pesos com valores aleatórios
	w1 = PackedFloat32Array()
	b1 = PackedFloat32Array()
	w2 = PackedFloat32Array()
	b2 = PackedFloat32Array()
	
	for i in range(input_size * hidden_size):
		w1.append(randf_range(-1, 1))
	for i in range(hidden_size):
		b1.append(randf_range(-1, 1))
	for i in range(hidden_size * output_size):
		w2.append(randf_range(-1, 1))
	for i in range(output_size):
		b2.append(randf_range(-1, 1))

func activate(x: float) -> float:
	return tanh(x)

func forward(inputs: Array) -> Array:
	var hidden: Array = []
	for h in range(hidden_size):
		var sum = b1[h]
		for i in range(input_size):
			sum += inputs[i] * w1[h * input_size + i]
		hidden.append(activate(sum))
	
	var outputs: Array = []
	for o in range(output_size):
		var sum = b2[o]
		for h in range(hidden_size):
			sum += hidden[h] * w2[o * hidden_size + h]
		outputs.append(activate(sum))
	return outputs

func clone() -> MLP:
	var copy = MLP.new(self.input_size, self.hidden_size, self.output_size)
	
	copy.w1 = w1.duplicate()
	copy.b1 = b1.duplicate()
	copy.w2 = w2.duplicate()
	copy.b2 = b2.duplicate()
	
	return copy

func to_dict() -> Dictionary:
	# Convert PackedFloat32Array -> Array for JSON
	return {
		"input_size": input_size,
		"hidden_size": hidden_size,
		"output_size": output_size,
		"w1": w1.duplicate(),
		"b1": b1.duplicate(),
		"w2": w2.duplicate(),
		"b2": b2.duplicate(),
	}

static func from_dict(d: Dictionary) -> MLP:
	var in_sz := int(d.get("input_size", 0))
	var hid_sz := int(d.get("hidden_size", 0))
	var out_sz := int(d.get("output_size", 0))
	var m := MLP.new(in_sz, hid_sz, out_sz)
	if d.has("w1"): m.w1 = PackedFloat32Array(d["w1"])
	if d.has("b1"): m.b1 = PackedFloat32Array(d["b1"])
	if d.has("w2"): m.w2 = PackedFloat32Array(d["w2"])
	if d.has("b2"): m.b2 = PackedFloat32Array(d["b2"])
	return m
