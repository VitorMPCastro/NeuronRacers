extends Resource
class_name MLP

var input_size: int
var output_size: int

# New: multiple hidden layers. If empty, treated as [hidden_size] for legacy.
var hidden_sizes: PackedInt32Array = PackedInt32Array()

# New: per-layer weights/biases. weights[l] maps layer l -> l+1 and is sized (next * prev), row-major by next neuron.
var weights: Array = []              # Array[PackedFloat32Array]
var biases: Array = []               # Array[PackedFloat32Array]

# Legacy compatibility (single hidden layer). These mirror first/last layers when hidden_sizes.size() == 1; otherwise left empty.
var hidden_size: int
var w1: PackedFloat32Array
var b1: PackedFloat32Array
var w2: PackedFloat32Array
var b2: PackedFloat32Array

func _to_string() -> String:
	return str(
		"\ninput: ", input_size,
		"\nhidden_sizes: ", hidden_sizes,
		"\noutput: ", output_size,
		"\nweights_layers: ", weights.size()
	)

# Accept either an int (single hidden layer) or an Array/PackedInt32Array of hidden sizes.
func _init(p_input_size: int, p_hidden, p_output_size: int):
	input_size = p_input_size
	output_size = p_output_size

	if typeof(p_hidden) == TYPE_INT:
		hidden_size = int(p_hidden)
		hidden_sizes = PackedInt32Array([hidden_size])
	elif typeof(p_hidden) == TYPE_PACKED_INT32_ARRAY:
		hidden_sizes = p_hidden
		hidden_size = hidden_sizes[0] if hidden_sizes.size() > 0 else 0
	elif typeof(p_hidden) == TYPE_ARRAY:
		hidden_sizes = PackedInt32Array(p_hidden)
		hidden_size = hidden_sizes[0] if hidden_sizes.size() > 0 else 0
	else:
		hidden_sizes = PackedInt32Array()
		hidden_size = 0

	# Init new structure
	weights.clear()
	biases.clear()
	var sizes := _layer_sizes()
	for l in range(sizes.size() - 1):
		var prev := sizes[l]
		var nxt := sizes[l + 1]
		var w := PackedFloat32Array()
		var b := PackedFloat32Array()
		for i in range(nxt * prev):
			w.append(randf_range(-1.0, 1.0))
		for j in range(nxt):
			b.append(randf_range(-1.0, 1.0))
		weights.append(w)
		biases.append(b)

	# Populate legacy fields if exactly one hidden layer, else leave them empty
	_sync_legacy_fields()

func _layer_sizes() -> PackedInt32Array:
	var arr := PackedInt32Array()
	arr.push_back(input_size)
	for n in hidden_sizes:
		arr.push_back(n)
	arr.push_back(output_size)
	return arr

func _sync_legacy_fields() -> void:
	w1 = PackedFloat32Array()
	b1 = PackedFloat32Array()
	w2 = PackedFloat32Array()
	b2 = PackedFloat32Array()
	if hidden_sizes.size() == 1 and weights.size() == 2 and biases.size() == 2:
		hidden_size = hidden_sizes[0]
		w1 = (weights[0] as PackedFloat32Array).duplicate()
		b1 = (biases[0] as PackedFloat32Array).duplicate()
		w2 = (weights[1] as PackedFloat32Array).duplicate()
		b2 = (biases[1] as PackedFloat32Array).duplicate()

static func activate(x: float) -> float:
	return tanh(x)

static func activate_deriv_from_output(y: float) -> float:
	# tanh' = 1 - tanh(x)^2; y here is tanh(x)
	return 1.0 - y * y

func forward(inputs: Array) -> Array:
	# General forward for any number of layers. Falls back to legacy if needed.
	if weights.size() == 0:
		# Legacy path if weights not initialized
		return _forward_legacy(inputs)

	var a_prev := PackedFloat32Array()
	for v in inputs:
		a_prev.push_back(float(v))

	for l in range(weights.size()):
		var prev = input_size if l == 0 else hidden_sizes[l - 1]
		var nxt = output_size if l == weights.size() - 1 else hidden_sizes[l]
		var w: PackedFloat32Array = weights[l]
		var b: PackedFloat32Array = biases[l]
		var a_curr := PackedFloat32Array()
		a_curr.resize(nxt)

		for j in range(nxt):
			var sum := b[j]
			for i in range(prev):
				sum += a_prev[i] * w[j * prev + i]
			a_curr[j] = activate(sum)
		a_prev = a_curr
	# Return as Array
	return a_prev

func _forward_legacy(inputs: Array) -> Array:
	# Maintain old single-hidden-layer behavior using legacy fields
	var hidden_out: Array = []
	for h in range(hidden_size):
		var sum = b1[h]
		for i in range(input_size):
			sum += inputs[i] * w1[h * input_size + i]
		hidden_out.append(activate(sum))
	var outputs: Array = []
	for o in range(output_size):
		var sum2 = b2[o]
		for h in range(hidden_size):
			sum2 += hidden_out[h] * w2[o * hidden_size + h]
		outputs.append(activate(sum2))
	return outputs

# One SGD step with backprop. Returns MSE loss for this sample.
func backprop_step(inputs: Array, targets: Array, learning_rate: float) -> float:
	if weights.size() == 0:
		# Initialize a single hidden layer if legacy fields were directly loaded.
		if hidden_size > 0 and w1.size() > 0 and w2.size() > 0:
			hidden_sizes = PackedInt32Array([hidden_size])
			weights = [w1.duplicate(), w2.duplicate()]
			biases = [b1.duplicate(), b2.duplicate()]
		else:
			return 0.0

	# Forward pass with activation cache
	var acts: Array = []  # Array[PackedFloat32Array], acts[0] = input
	var a0 := PackedFloat32Array()
	for v in inputs:
		a0.push_back(float(v))
	acts.append(a0)

	for l in range(weights.size()):
		var prev = input_size if l == 0 else hidden_sizes[l - 1]
		var nxt = output_size if l == weights.size() - 1 else hidden_sizes[l]
		var w: PackedFloat32Array = weights[l]
		var b: PackedFloat32Array = biases[l]
		var a_prev: PackedFloat32Array = acts[l]
		var a_curr := PackedFloat32Array()
		a_curr.resize(nxt)
		for j in range(nxt):
			var sum := b[j]
			for i in range(prev):
				sum += a_prev[i] * w[j * prev + i]
			a_curr[j] = activate(sum)
		acts.append(a_curr)

	# Loss (MSE) and initial delta at output
	var y: PackedFloat32Array = acts.back()
	var t := PackedFloat32Array()
	for v in targets:
		t.push_back(float(v))
	var loss = 0.0
	for k in range(output_size):
		var diff = y[k] - (t[k] if k < t.size() else 0.0)
		loss += diff * diff
	loss /= max(1, output_size)

	# Backward deltas
	var deltas: Array = []  # Array[PackedFloat32Array], aligned with acts[1..]
	deltas.resize(weights.size())
	# Output delta
	var delta_L := PackedFloat32Array()
	delta_L.resize(output_size)
	for k in range(output_size):
		var diff = y[k] - (t[k] if k < t.size() else 0.0)
		var d_act := activate_deriv_from_output(y[k])
		delta_L[k] = diff * d_act
	deltas[weights.size() - 1] = delta_L

	# Hidden deltas
	for l in range(weights.size() - 2, -1, -1):
		var _prev = input_size if l == 0 else hidden_sizes[l - 1]
		var nxt = output_size if l == weights.size() - 1 else hidden_sizes[l]
		var a_l: PackedFloat32Array = acts[l + 1]  # activation at this hidden layer
		var w_next: PackedFloat32Array = weights[l + 1]
		var delta_next: PackedFloat32Array = deltas[l + 1]
		var delta_here := PackedFloat32Array()
		delta_here.resize(nxt)  # wait—nxt at l is size of current layer's output; acts[l+1].size()
		# Correct: current layer size is nxt (acts[l+1].size)
		for i in range(nxt):
			var sum := 0.0
			var next_size = output_size if (l + 1) == weights.size() - 1 else hidden_sizes[l + 1]
			for j in range(next_size):
				# weight from current i to next j is at row j, col i
				sum += w_next[j * nxt + i] * delta_next[j]
			delta_here[i] = sum * activate_deriv_from_output(a_l[i])
		deltas[l] = delta_here

	# Gradients and SGD update
	for l in range(weights.size()):
		var a_prev: PackedFloat32Array = acts[l]
		var delta: PackedFloat32Array = deltas[l]
		var prev := a_prev.size()
		var nxt := delta.size()
		var w: PackedFloat32Array = weights[l]
		var b: PackedFloat32Array = biases[l]

		# Update weights: w[j, i] -= lr * delta[j] * a_prev[i]
		for j in range(nxt):
			for i in range(prev):
				var idx := j * prev + i
				w[idx] -= learning_rate * (delta[j] * a_prev[i])
		# Update biases: b[j] -= lr * delta[j]
		for j in range(nxt):
			b[j] -= learning_rate * delta[j]

		weights[l] = w
		biases[l] = b

	# Keep legacy fields synced when single hidden layer
	_sync_legacy_fields()
	return loss

func train_sample(inputs: Array, targets: Array, learning_rate: float) -> float:
	return backprop_step(inputs, targets, learning_rate)

func clone() -> MLP:
	var copy = MLP.new(self.input_size, self.hidden_sizes, self.output_size)
	# Deep copy all layers
	copy.weights = []
	copy.biases = []
	for l in range(weights.size()):
		copy.weights.append((weights[l] as PackedFloat32Array).duplicate())
	for l in range(biases.size()):
		copy.biases.append((biases[l] as PackedFloat32Array).duplicate())
	copy._sync_legacy_fields()
	return copy

func to_dict() -> Dictionary:
	# New format includes hidden_sizes/weights/biases; legacy fields included for backward compat.
	var d := {
		"input_size": input_size,
		"hidden_sizes": hidden_sizes,
		"output_size": output_size,
		"weights": [],
		"biases": []
	}
	for l in range(weights.size()):
		d["weights"].append((weights[l] as PackedFloat32Array).duplicate())
	for l in range(biases.size()):
		d["biases"].append((biases[l] as PackedFloat32Array).duplicate())

	# Legacy mirror when possible
	if hidden_sizes.size() == 1 and weights.size() == 2:
		d["hidden_size"] = hidden_sizes[0]
		d["w1"] = (weights[0] as PackedFloat32Array).duplicate()
		d["b1"] = (biases[0] as PackedFloat32Array).duplicate()
		d["w2"] = (weights[1] as PackedFloat32Array).duplicate()
		d["b2"] = (biases[1] as PackedFloat32Array).duplicate()
	return d

static func from_dict(d: Dictionary) -> MLP:
	var in_sz := int(d.get("input_size", 0))
	var out_sz := int(d.get("output_size", 0))

	# Prefer new format
	if d.has("hidden_sizes") and d.has("weights") and d.has("biases"):
		var h_sizes := PackedInt32Array(d.get("hidden_sizes", PackedInt32Array()))
		var m := MLP.new(in_sz, h_sizes, out_sz)
		m.weights = []
		m.biases = []
		for w in d.get("weights", []):
			m.weights.append(PackedFloat32Array(w))
		for b in d.get("biases", []):
			m.biases.append(PackedFloat32Array(b))
		m._sync_legacy_fields()
		return m

	# Legacy format fallback
	var hid_sz := int(d.get("hidden_size", d.get("hidden", 0)))
	var m2 := MLP.new(in_sz, hid_sz, out_sz)
	if d.has("w1"): m2.w1 = PackedFloat32Array(d["w1"])
	if d.has("b1"): m2.b1 = PackedFloat32Array(d["b1"])
	if d.has("w2"): m2.w2 = PackedFloat32Array(d["w2"])
	if d.has("b2"): m2.b2 = PackedFloat32Array(d["b2"])
	# Ensure new arrays mirror legacy
	m2.weights = [m2.w1.duplicate(), m2.w2.duplicate()]
	m2.biases = [m2.b1.duplicate(), m2.b2.duplicate()]
	m2.hidden_sizes = PackedInt32Array([hid_sz])
	m2.hidden_size = hid_sz
	return m2
