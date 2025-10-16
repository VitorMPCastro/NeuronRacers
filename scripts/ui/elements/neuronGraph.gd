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
@export var fit_square: bool = true      # layout within the largest centered square

# NEW: auto update toggle and minimum size exported with setters
@export var auto_update: bool = true
@export var minimum_x_size: int = 200
@export var minimum_y_size: int = 200

var brain: MLP
var _in_pos: Array[Vector2] = []
var _hid_pos: Array[Vector2] = []
var _out_pos: Array[Vector2] = []

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
		# Redraw every frame so the graph stays responsive to layout/brain changes.
		queue_redraw()

func set_brain(b: MLP) -> void:
	brain = b
	_layout()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()

func _layout() -> void:
	_in_pos.clear(); _hid_pos.clear(); _out_pos.clear()
	if brain == null:
		return
	var in_n = max(1, brain.input_size)
	var hid_n = max(1, brain.hidden_size)
	var out_n = max(1, brain.output_size)
	var w: float = max(1.0, size.x)
	var h: float = max(1.0, size.y)
	var side = min(w, h)
	var sq_x = (w - side) * 0.5
	var sq_y = (h - side) * 0.5
	var margin = 0.12
	var left = sq_x + side * margin
	var right = sq_x + side * (1.0 - margin)
	var x0 = lerp(left, right, 0.0)
	var x1 = lerp(left, right, 0.5)
	var x2 = lerp(left, right, 1.0)
	var layer_positions_fit := func(y_count: int, x: float) -> Array[Vector2]:
		var arr: Array[Vector2] = []
		var top = sq_y + side * margin
		var bottom = sq_y + side * (1.0 - margin)
		if y_count <= 1:
			arr.append(Vector2(x, (top + bottom) * 0.5))
			return arr
		var span = bottom - top
		for i in range(y_count):
			var t := float(i) / float(y_count - 1)
			arr.append(Vector2(x, top + t * span))
		return arr
	var layer_positions_fixed := func(y_count: int, x: float) -> Array[Vector2]:
		var arr: Array[Vector2] = []
		var total_h := (y_count - 1) * v_gap
		var y0 = h * 0.5 - total_h * 0.5
		for i in range(y_count):
			arr.append(Vector2(x, y0 + i * v_gap))
		return arr
	if fit_square:
		_in_pos = (layer_positions_fit.call(in_n, x0) as Array[Vector2])
		_hid_pos = (layer_positions_fit.call(hid_n, x1) as Array[Vector2])
		_out_pos = (layer_positions_fit.call(out_n, x2) as Array[Vector2])
	else:
		var x0_fixed: float = h_gap * 0.5
		var x1_fixed: float = w * 0.5
		var x2_fixed: float = w - h_gap * 0.5
		_in_pos = (layer_positions_fixed.call(in_n, x0_fixed) as Array[Vector2])
		_hid_pos = (layer_positions_fixed.call(hid_n, x1_fixed) as Array[Vector2])
		_out_pos = (layer_positions_fixed.call(out_n, x2_fixed) as Array[Vector2])

func _draw() -> void:
	if brain == null:
		return
	var max_w1 := 0.0
	for i in range(brain.w1.size()): max_w1 = max(max_w1, abs(brain.w1[i]))
	var max_w2 := 0.0
	for i in range(brain.w2.size()): max_w2 = max(max_w2, abs(brain.w2[i]))
	max_w1 = max(max_w1, 1e-6)
	max_w2 = max(max_w2, 1e-6)
	var in_n = max(1, brain.input_size)
	var hid_n = max(1, brain.hidden_size)
	var out_n = max(1, brain.output_size)
	for i in range(in_n):
		for j in range(hid_n):
			var idx = i * hid_n + j
			if idx >= brain.w1.size(): continue
			var w = brain.w1[idx]
			var c = color_pos if w >= 0.0 else color_neg
			var a = clamp(abs(w) / max_w1, 0.05, 1.0)
			var col = Color(c, a)
			draw_line(_in_pos[i], _hid_pos[j], col, weight_thickness)
	for j in range(hid_n):
		for k in range(out_n):
			var idx2 = j * out_n + k
			if idx2 >= brain.w2.size(): continue
			var w2 = brain.w2[idx2]
			var c2 = color_pos if w2 >= 0.0 else color_neg
			var a2 = clamp(abs(w2) / max_w2, 0.05, 1.0)
			var col2 = Color(c2, a2)
			draw_line(_hid_pos[j], _out_pos[k], col2, weight_thickness)
	for p in _in_pos: draw_circle(p, node_radius, color_node)
	for p in _hid_pos: draw_circle(p, node_radius, color_node)
	for p in _out_pos: draw_circle(p, node_radius, color_node)
	if show_bias:
		for j in range(hid_n):
			if j < brain.b1.size():
				var b = brain.b1[j]
				var rad = node_radius + clamp(abs(b), 0.0, 6.0)
				draw_arc(_hid_pos[j], rad, 0, TAU, 20, color_bias, 1.2)
		for k in range(out_n):
			if k < brain.b2.size():
				var b2 = brain.b2[k]
				var rad2 = node_radius + clamp(abs(b2), 0.0, 6.0)
				draw_arc(_out_pos[k], rad2, 0, TAU, 20, color_bias, 1.2)

func set_brain_from_car(car: Car) -> void:
	if car and car.car_data and car.car_data.pilot and car.car_data.pilot.brain:
		set_brain(car.car_data.pilot.brain)
