# Requires your DraggablePanel (assumed class_name DraggablePanel)
extends DraggablePanel
class_name NodeBase

var graph: NodeGraph = null
var data_broker: DataBroker = null
var data_provider: Object = null

var inputs: Array[NodePort] = []
var outputs: Array[NodePort] = []
var internal_fields: Array[Control] = []

@export var node_title: String = "Node"

var _left_v: VBoxContainer
var _right_v: VBoxContainer
var _body_v: VBoxContainer

func _ready() -> void:
	_build_ui()

func _clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

func _build_ui() -> void:
	_clear_children(self)
	add_theme_constant_override("separation", 4)
	var root := HBoxContainer.new()
	add_child(root)
	_left_v = VBoxContainer.new()
	_left_v.custom_minimum_size = Vector2(120, 0)
	root.add_child(_left_v)
	_body_v = VBoxContainer.new()
	_body_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_body_v)
	_right_v = VBoxContainer.new()
	_right_v.custom_minimum_size = Vector2(120, 0)
	root.add_child(_right_v)

	var title_lbl := Label.new()
	title_lbl.text = node_title
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_v.add_child(title_lbl)

func add_input_port(text: String, max_conn: int = 1) -> NodePort:
	var h := HBoxContainer.new()
	var p := preload("res://scripts/ui/nodegraph/node_port.gd").new() as NodePort
	p.is_input = true
	p.label = text
	p.max_connections = max(1, max_conn)
	p.unlimited = false
	p.custom_minimum_size = Vector2(16, 16)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.connect("request_connect", Callable(self, "_on_port_request_connect"))
	h.add_child(p)
	var lbl := Label.new()
	lbl.text = text
	h.add_child(lbl)
	_left_v.add_child(h)
	inputs.append(p)
	return p

func add_output_port(text: String, unlimited: bool = true, max_conn: int = 1000000) -> NodePort:
	var h := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	h.add_child(lbl)
	var p := preload("res://scripts/ui/nodegraph/node_port.gd").new() as NodePort
	p.is_input = false
	p.label = text
	p.unlimited = unlimited
	p.max_connections = max_conn
	p.custom_minimum_size = Vector2(16, 16)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.connect("request_connect", Callable(self, "_on_port_request_connect"))
	h.add_child(p)
	_right_v.add_child(h)
	outputs.append(p)
	return p

func add_internal_field(ctrl: Control) -> void:
	_body_v.add_child(ctrl)
	internal_fields.append(ctrl)

func set_graph(g: NodeGraph) -> void:
	graph = g

func set_data_context(broker: DataBroker, provider: Object) -> void:
	data_broker = broker
	data_provider = provider

# Runtime evaluation -----------------------------------------------------

func evaluate_output(port_index: int) -> float:
	if port_index != 0:
		return 0.0
	var vals := get_input_values_merged()
	return _sanitize_number(vals.max() if vals.size() > 0 else 0.0)

func get_input_values_merged() -> Array:
	var out: Array = []
	for i in range(inputs.size()):
		var arr := get_input_values(i)
		for v in arr:
			out.append(v)
	return out

func get_input_values(input_index: int) -> Array:
	if input_index < 0 or input_index >= inputs.size():
		return []
	var port := inputs[input_index]
	var vals: Array = []
	for other in port.connections:
		var other_node = other._get_node_base()
		if other_node == null:
			continue
		var out_idx = other_node.outputs.find(other)
		if out_idx >= 0:
			var v := graph.evaluate_node_output(other_node, out_idx)
			vals.append(_sanitize_number(v))
	return vals

func _sanitize_number(v: Variant) -> float:
	var f := 0.0
	match typeof(v):
		TYPE_BOOL: f = ( 1.0 if v else 0.0)
		TYPE_FLOAT, TYPE_INT: f = float(v)
		_: f = float(str(v).to_float())
	if is_nan(f) or is_inf(f):
		return 0.0
	return clampf(f, -1.0e9, 1.0e9)

func _on_port_request_connect(port: NodePort) -> void:
	if graph:
		graph.begin_drag_from_port(port)

# Expression compilation -------------------------------------------------

func compile_output_expression(port_index: int) -> String:
	var exprs := graph.compile_port_expr(self, port_index)
	if exprs.is_empty():
		return "0"
	if exprs.size() == 1:
		return "(" + exprs[0] + ")"
	var acc := "max(" + exprs[0] + ", " + exprs[1] + ")"
	for i in range(2, exprs.size()):
		acc = "max(" + acc + ", " + exprs[i] + ")"
	return "(" + acc + ")"
