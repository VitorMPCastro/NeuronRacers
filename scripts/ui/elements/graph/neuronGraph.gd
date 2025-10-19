extends Control
class_name NeuronGraph

@export var node_radius: float = 6.0
@export var h_gap: float = 160.0
@export var v_gap: float = 28.0
@export var weight_thickness: float = 1.5
@export var color_pos: Color = Color(0.2, 1.0, 0.3, 0.9)
@export var color_neg: Color = Color(1.0, 0.3, 0.3, 0.9)
@export var color_node: Color = Color(0.9, 0.9, 0.9, 1.0)
@export var color_bias: Color = Color(0.6, 0.6, 1.0, 0.8)
@export var show_bias: bool = false
@export var fit_square: bool = true

# NEW: auto update toggle and minimum size exported with setters
@export var auto_update: bool = true
@export var minimum_x_size: int = 200
@export var minimum_y_size: int = 200

var brain: MLP
var _layer_positions: Array = []   # Array[Array[Vector2]] layer -> neuron positions

func _ready() -> void:
	_apply_min_size()
	set_process(auto_update)

func set_auto_update(v: bool) -> void:
	auto_update = v
	set_process(v)

func set_minimum_x_size(v: int) -> void:
	minimum_x_size = v
	_apply_min_size()

func set_minimum_y_size(v: int) -> void:
	minimum_y_size = v
	_apply_min_size()

func _apply_min_size() -> void:
	custom_minimum_size = Vector2(float(minimum_x_size), float(minimum_y_size))

func _process(_delta: float) -> void:
	if auto_update:
		queue_redraw()

func set_brain(b: MLP) -> void:
	brain = b
	_layout()
	queue_redraw()

func set_brain_from_car(car: Car) -> void:
	if car and car.car_data and car.car_data.pilot and car.car_data.pilot.brain:
		set_brain(car.car_data.pilot.brain)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()

func _layer_sizes() -> PackedInt32Array:
	if brain == null:
		return PackedInt32Array()
	var sizes := PackedInt32Array()
	sizes.push_back(brain.input_size)
	if brain.hidden_sizes.size() > 0:
		for n in brain.hidden_sizes: sizes.push_back(n)
	else:
		# Legacy single hidden layer fallback
		if brain.hidden_size > 0:
			sizes.push_back(brain.hidden_size)
	sizes.push_back(brain.output_size)
	return sizes

func _layout() -> void:
	_layer_positions.clear()
	if brain == null:
		return

	var sizes := _layer_sizes()
	if sizes.size() < 2:
		return

	var w = max(1.0, size.x)
	var h = max(1.0, size.y)

	# Centered square draw area
	var side = min(w, h)
	var sq_x = (w - side) * 0.5
	var sq_y = (h - side) * 0.5
	var margin := 0.12
	var left = sq_x + side * margin
	var right = sq_x + side * (1.0 - margin)
	var top = sq_y + side * margin
	var bottom = sq_y + side * (1.0 - margin)

	var L := sizes.size()
	for l in range(L):
		var x_t := 0.0 if L <= 1 else float(l) / float(L - 1)
		var x = lerp(left, right, x_t)
		var count = max(1, sizes[l])
		var arr: Array[Vector2] = []
		if count <= 1:
			arr.append(Vector2(x, (top + bottom) * 0.5))
		else:
			var span = bottom - top
			for i in range(count):
				var t := float(i) / float(count - 1)
				arr.append(Vector2(x, top + t * span))
		_layer_positions.append(arr)

func _draw() -> void:
	if brain == null or _layer_positions.size() == 0:
		return

	# Prefer multi-layer arrays; fallback to legacy w1/w2 if empty
	if brain.weights.size() > 0 and brain.biases.size() == brain.weights.size():
		_draw_multilayer()
	else:
		_draw_legacy()

func _draw_multilayer() -> void:
	# Compute per-matrix normalization
	var max_abs: Array[float] = []
	for l in range(brain.weights.size()):
		var w: PackedFloat32Array = brain.weights[l]
		var m := 0.0
		for i in range(w.size()): m = max(m, abs(w[i]))
		max_abs.append(max(m, 1e-6))

	var sizes := _layer_sizes()
	for l in range(brain.weights.size()):
		var prev := sizes[l]
		var nxt := sizes[l + 1]
		var w_mat: PackedFloat32Array = brain.weights[l]
		var norm := max_abs[l]
		for j in range(nxt):
			for i in range(prev):
				var idx := j * prev + i
				if idx >= w_mat.size(): continue
				var w := w_mat[idx]
				var c := color_pos if w >= 0.0 else color_neg
				var a = clamp(abs(w) / norm, 0.05, 1.0)
				draw_line(_layer_positions[l][i], _layer_positions[l + 1][j], Color(c, a), weight_thickness)

	# Draw neurons
	for l in range(_layer_positions.size()):
		for p in _layer_positions[l]:
			draw_circle(p, node_radius, color_node)

	# Optional biases (skip input layer)
	if show_bias:
		for l in range(brain.biases.size()):
			var b = brain.biases[l]
			var layer_pos = _layer_positions[l + 1]  # biases correspond to layer outputs
			for j in range(min(b.size(), layer_pos.size())):
				var rad = node_radius + clamp(abs(b[j]), 0.0, 6.0)
				draw_arc(layer_pos[j], rad, 0, TAU, 20, color_bias, 1.2)

func _draw_legacy() -> void:
	# Legacy: single hidden layer using w1/w2
	var hid = max(1, brain.hidden_size)
	var in_n = max(1, brain.input_size)
	var out_n = max(1, brain.output_size)

	# Build simple positions if layout wasn’t prepared
	if _layer_positions.size() < 3:
		var w = max(1.0, size.x)
		var h = max(1.0, size.y)
		var side = min(w, h)
		var sq_x = (w - side) * 0.5
		var sq_y = (h - side) * 0.5
		var margin := 0.12
		var left = sq_x + side * margin
		var right = sq_x + side * (1.0 - margin)
		var top = sq_y + side * margin
		var bottom = sq_y + side * (1.0 - margin)
		# Build column positions explicitly to avoid calling a local func via a variable
		var left_arr: Array[Vector2] = []
		if in_n <= 1:
			left_arr.append(Vector2(left, (top + bottom) * 0.5))
		else:
			var span_left = bottom - top
			for i in range(in_n):
				var t := float(i) / float(in_n - 1)
				left_arr.append(Vector2(left, top + t * span_left))

		var mid_arr: Array[Vector2] = []
		var mid_x = lerp(left, right, 0.5)
		if hid <= 1:
			mid_arr.append(Vector2(mid_x, (top + bottom) * 0.5))
		else:
			var span_mid = bottom - top
			for i in range(hid):
				var t := float(i) / float(hid - 1)
				mid_arr.append(Vector2(mid_x, top + t * span_mid))

		var right_arr: Array[Vector2] = []
		if out_n <= 1:
			right_arr.append(Vector2(right, (top + bottom) * 0.5))
		else:
			var span_right = bottom - top
			for i in range(out_n):
				var t := float(i) / float(out_n - 1)
				right_arr.append(Vector2(right, top + t * span_right))

		_layer_positions = [
			left_arr,
			mid_arr,
			right_arr
		]

	# Normalize
	var max_w1 := 0.0
	for i in range(brain.w1.size()): max_w1 = max(max_w1, abs(brain.w1[i]))
	max_w1 = max(max_w1, 1e-6)
	var max_w2 := 0.0
	for i in range(brain.w2.size()): max_w2 = max(max_w2, abs(brain.w2[i]))
	max_w2 = max(max_w2, 1e-6)

	for i in range(in_n):
		for j in range(hid):
			var idx = j * in_n + i
			if idx >= brain.w1.size(): continue
			var w1 := brain.w1[idx]
			var c1 := color_pos if w1 >= 0.0 else color_neg
			var a1 = clamp(abs(w1) / max_w1, 0.05, 1.0)
			draw_line(_layer_positions[0][i], _layer_positions[1][j], Color(c1, a1), weight_thickness)

	for j in range(hid):
		for k in range(out_n):
			var idx2 = k * hid + j
			if idx2 >= brain.w2.size(): continue
			var w2 := brain.w2[idx2]
			var c2 := color_pos if w2 >= 0.0 else color_neg
			var a2 = clamp(abs(w2) / max_w2, 0.05, 1.0)
			draw_line(_layer_positions[1][j], _layer_positions[2][k], Color(c2, a2), weight_thickness)

	for p in _layer_positions[0]: draw_circle(p, node_radius, color_node)
	for p in _layer_positions[1]: draw_circle(p, node_radius, color_node)
	for p in _layer_positions[2]: draw_circle(p, node_radius, color_node)
