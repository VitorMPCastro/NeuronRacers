extends Resource
class_name MLP

var input_size: int
var output_size: int
var hidden_sizes: PackedInt32Array = PackedInt32Array()
var weights: Array = []              # Array[PackedFloat32Array]
var biases: Array = []               # Array[PackedFloat32Array]

# Legacy fields (read-only when multi-layer is present)
var hidden_size: int
var w1: PackedFloat32Array
var b1: PackedFloat32Array
var w2: PackedFloat32Array
var b2: PackedFloat32Array

func _init(p_input: int = 0, p_hidden = PackedInt32Array(), p_output: int = 0) -> void:
	input_size = p_input
	output_size = p_output
	if typeof(p_hidden) == TYPE_INT:
		hidden_size = int(p_hidden)
		hidden_sizes = PackedInt32Array([hidden_size])
	elif typeof(p_hidden) == TYPE_ARRAY:
		hidden_sizes = PackedInt32Array(p_hidden)
		hidden_size = hidden_sizes[0] if hidden_sizes.size() > 0 else 0
	else:
		hidden_sizes = (p_hidden if typeof(p_hidden) == TYPE_PACKED_INT32_ARRAY else PackedInt32Array())
		hidden_size = hidden_sizes[0] if hidden_sizes.size() > 0 else 0
	_init_params()
	_sync_legacy_fields()

func _init_params() -> void:
	weights.clear()
	biases.clear()
	var sizes := _layer_sizes()
	for l in range(sizes.size() - 1):
		var prev := sizes[l]
		var nxt := sizes[l + 1]
		var w := PackedFloat32Array(); w.resize(prev * nxt)
		var b := PackedFloat32Array(); b.resize(nxt)
		for i in range(w.size()): w[i] = randf_range(-1.0, 1.0)
		for j in range(b.size()): b[j] = randf_range(-1.0, 1.0)
		weights.append(w)
		biases.append(b)

func _layer_sizes() -> PackedInt32Array:
	var arr := PackedInt32Array([input_size])
	for n in hidden_sizes: arr.push_back(n)
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

func validate(raise_errors := true) -> bool:
	var ok := true
	var sizes := _layer_sizes()
	if sizes.size() < 2: ok = false
	if weights.size() != sizes.size() - 1: ok = false
	if biases.size() != sizes.size() - 1: ok = false
	for l in range(weights.size()):
		var prev := sizes[l]
		var nxt := sizes[l + 1]
		if (weights[l] as PackedFloat32Array).size() != prev * nxt: ok = false
		if (biases[l] as PackedFloat32Array).size() != nxt: ok = false
	if not ok and raise_errors:
		push_error("MLP.validate failed: layer sizes/params mismatch. sizes=%s w=%d b=%d" % [sizes, weights.size(), biases.size()])
	return ok

static func _act(x: float) -> float:
	return tanh(x)

static func _act_deriv_from_y(y: float) -> float:
	return 1.0 - y * y

func forward(inputs: Array) -> Array:
	# Accept Array (floats); returns Array
	if weights.is_empty():
		# Legacy path if needed
		return _forward_legacy(inputs)

	var a_prev := PackedFloat32Array()
	for v in inputs: a_prev.push_back(float(v))

	for l in range(weights.size()):
		var prev := input_size if l == 0 else hidden_sizes[l - 1]
		var nxt := output_size if l == weights.size() - 1 else hidden_sizes[l]
		var w: PackedFloat32Array = weights[l]
		var b: PackedFloat32Array = biases[l]
		var a_curr := PackedFloat32Array(); a_curr.resize(nxt)
		for j in range(nxt):
			var s := b[j]
			for i in range(prev): s += a_prev[i] * w[j * prev + i]
			a_curr[j] = _act(s)
		a_prev = a_curr
	return a_prev

func _forward_legacy(inputs: Array) -> Array:
	if hidden_size <= 0 or w1.is_empty() or w2.is_empty():
		return []
	var hidden_out: Array = []
	for h in range(hidden_size):
		var sum := b1[h] if h < b1.size() else 0.0
		for i in range(input_size):
			var idx := h * input_size + i
			var wi := w1[idx] if idx < w1.size() else 0.0
			sum += float(inputs[i]) * wi
		hidden_out.append(_act(sum))
	var outputs: Array = []
	for o in range(output_size):
		var sum2 := b2[o] if o < b2.size() else 0.0
		for h in range(hidden_size):
			var idx2 := o * hidden_size + h
			var w2v := w2[idx2] if idx2 < w2.size() else 0.0
			sum2 += float(hidden_out[h]) * w2v
		outputs.append(_act(sum2))
	return outputs

# Single-sample SGD with MSE loss
func backprop_step(inputs: Array, targets: Array, lr: float) -> float:
	if weights.is_empty():
		# Try to bootstrap from legacy fields if present
		if hidden_size > 0 and !w1.is_empty() and !w2.is_empty():
			hidden_sizes = PackedInt32Array([hidden_size])
			weights = [w1.duplicate(), w2.duplicate()]
			biases = [b1.duplicate(), b2.duplicate()]
		else:
			return 0.0

	# Forward with cache
	var acts: Array = []  # Array[PackedFloat32Array], acts[0] = input
	var a0 := PackedFloat32Array()
	for v in inputs: a0.push_back(float(v))
	acts.append(a0)

	for l in range(weights.size()):
		var prev := input_size if l == 0 else hidden_sizes[l - 1]
		var nxt := output_size if l == weights.size() - 1 else hidden_sizes[l]
		var w: PackedFloat32Array = weights[l]
		var b: PackedFloat32Array = biases[l]
		var a_prev: PackedFloat32Array = acts[l]
		var a_curr := PackedFloat32Array(); a_curr.resize(nxt)
		for j in range(nxt):
			var s := b[j]
			for i in range(prev): s += a_prev[i] * w[j * prev + i]
			a_curr[j] = _act(s)
		acts.append(a_curr)

	# Loss
	var y: PackedFloat32Array = acts.back()
	var t := PackedFloat32Array()
	for v in targets: t.push_back(float(v))
	var loss := 0.0
	for k in range(output_size):
		var diff := y[k] - (t[k] if k < t.size() else 0.0)
		loss += diff * diff
	loss /= max(1, output_size)

	# Backward
	var deltas: Array = []  # Array[PackedFloat32Array]
	deltas.resize(weights.size())
	# Output delta
	var dL := PackedFloat32Array(); dL.resize(output_size)
	for k in range(output_size):
		var diff := y[k] - (t[k] if k < t.size() else 0.0)
		dL[k] = diff * _act_deriv_from_y(y[k])
	deltas[weights.size() - 1] = dL

	# Hidden deltas
	for l in range(weights.size() - 2, -1, -1):
		var prev := input_size if l == 0 else hidden_sizes[l - 1]
		var nxt := output_size if l == weights.size() - 1 else hidden_sizes[l]
		var a_l: PackedFloat32Array = acts[l + 1]   # activation of current layer
		var w_next: PackedFloat32Array = weights[l + 1]
		var delta_next: PackedFloat32Array = deltas[l + 1]
		var next_size := output_size if l + 1 == weights.size() - 1 else hidden_sizes[l + 1]
		var delta_here := PackedFloat32Array(); delta_here.resize(nxt)
		for i in range(nxt):
			var s := 0.0
			for j in range(next_size):
				s += w_next[j * nxt + i] * delta_next[j]
			delta_here[i] = s * _act_deriv_from_y(a_l[i])
		deltas[l] = delta_here

	# SGD update
	for l in range(weights.size()):
		var a_prev: PackedFloat32Array = acts[l]
		var delta: PackedFloat32Array = deltas[l]
		var prev := a_prev.size()
		var nxt := delta.size()
		var w: PackedFloat32Array = weights[l]
		var b: PackedFloat32Array = biases[l]
		for j in range(nxt):
			for i in range(prev):
				var idx := j * prev + i
				w[idx] -= lr * (delta[j] * a_prev[i])
			b[j] -= lr * delta[j]
		weights[l] = w
		biases[l] = b

	_sync_legacy_fields()
	return loss

func train_sample(inputs: Array, targets: Array, learning_rate: float) -> float:
	return backprop_step(inputs, targets, learning_rate)

func clone() -> MLP:
	var m := MLP.new(input_size, hidden_sizes, output_size)
	m.weights = []
	m.biases = []
	for l in range(weights.size()):
		m.weights.append((weights[l] as PackedFloat32Array).duplicate())
	for l in range(biases.size()):
		m.biases.append((biases[l] as PackedFloat32Array).duplicate())
	m._sync_legacy_fields()
	return m

func to_dict() -> Dictionary:
	var d := {
		"input_size": input_size,
		"hidden_sizes": hidden_sizes,
		"output_size": output_size,
		"weights": [],
		"biases": []
	}
	for l in range(weights.size()): d["weights"].append((weights[l] as PackedFloat32Array).duplicate())
	for l in range(biases.size()): d["biases"].append((biases[l] as PackedFloat32Array).duplicate())
	# Legacy mirror when single hidden layer
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
	if d.has("hidden_sizes") and d.has("weights") and d.has("biases"):
		var h := PackedInt32Array(d.get("hidden_sizes", PackedInt32Array()))
		var m := MLP.new(in_sz, h, out_sz)
		m.weights = []; m.biases = []
		for w in d.get("weights", []): m.weights.append(PackedFloat32Array(w))
		for b in d.get("biases", []): m.biases.append(PackedFloat32Array(b))
		m._sync_legacy_fields()
		return m
	# Legacy fallback
	var hid := int(d.get("hidden_size", d.get("hidden", 0)))
	var m2 := MLP.new(in_sz, hid, out_sz)
	if d.has("w1"): m2.w1 = PackedFloat32Array(d["w1"])
	if d.has("b1"): m2.b1 = PackedFloat32Array(d["b1"])
	if d.has("w2"): m2.w2 = PackedFloat32Array(d["w2"])
	if d.has("b2"): m2.b2 = PackedFloat32Array(d["b2"])
	m2.weights = [m2.w1.duplicate(), m2.w2.duplicate()]
	m2.biases = [m2.b1.duplicate(), m2.b2.duplicate()]
	m2.hidden_sizes = PackedInt32Array([hid])
	m2.hidden_size = hid
	return m2
