extends Node
class_name BrainFactory

static func create(input_size: int, hidden: PackedInt32Array, output_size: int) -> MLP:
	var mlp := MLP.new(input_size, hidden, output_size)
	mlp.validate(false)
	return mlp

static func clone_and_mutate(src: MLP, mutate_chance: float, weight: float) -> MLP:
	var m := (src.clone() if src.has_method("clone") else src.duplicate()) as MLP
	# deep mutate across all layers (fallback to legacy mirrored arrays if needed)
	if m.weights.size() == 0 and m.hidden_size > 0 and !m.w1.is_empty() and !m.w2.is_empty():
		m.weights = [m.w1.duplicate(), m.w2.duplicate()]
		m.biases = [m.b1.duplicate(), m.b2.duplicate()]

	for l in range(m.weights.size()):
		var w: PackedFloat32Array = m.weights[l]
		for i in range(w.size()):
			if randf() < mutate_chance:
				w[i] += randf_range(-weight, weight)
		m.weights[l] = w
	for l in range(m.biases.size()):
		var b: PackedFloat32Array = m.biases[l]
		for i in range(b.size()):
			if randf() < mutate_chance:
				b[i] += randf_range(-weight, weight)
		m.biases[l] = b

	m.validate(false)
	return m