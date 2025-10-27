extends Control
class_name NodeGraph


const REG_INPUTS := [
	{"name": "Value", "script": "res://scripts/ui/nodegraph/nodes/value_node.gd", "class": "ValueNode"},
]
const REG_MATH := [
	{"name": "Math", "script": "res://scripts/ui/nodegraph/nodes/math_node.gd", "class": "MathNode"},
]
const REG_UTILITY := [
	{"name": "Min/Max", "script": "res://scripts/ui/nodegraph/nodes/minmax_node.gd", "class": "MinMaxNode"},
	{"name": "Clamp", "script": "res://scripts/ui/nodegraph/nodes/clamp_node.gd", "class": "ClampNode"},
]
const REG_OUTPUT := [
	{"name": "Fitness", "script": "res://scripts/ui/nodegraph/nodes/fitness_node.gd", "class": "FitnessNode"},
]

var connections: Array = []

var _drag_from: NodePort = null
var _drag_pos: Vector2 = Vector2.ZERO

var broker: DataBroker = null
var provider: Object = null

@export var curve_color: Color = Color(0.9, 0.9, 0.9, 0.9)
@export var curve_thickness: float = 2.0

# caches
var _eval_cache: Dictionary = {}
var _expr_cache: Dictionary = {}

func set_data_context(b: DataBroker, p: Object) -> void:
	broker = b
	provider = p
	for n in get_children():
		if n is NodeBase:
			(n as NodeBase).set_data_context(broker, provider)

func add_node(node: NodeBase, pos: Vector2) -> void:
	add_child(node)
	node.position = pos
	node.set_graph(self)
	node.set_data_context(broker, provider)

func begin_drag_from_port(port: NodePort) -> void:
	_drag_from = port
	_drag_pos = get_local_mouse_position()
	queue_redraw()

func _find_ui_root_control() -> Control:
	var cur: Node = self
	while cur:
		var p := cur.get_parent()
		if p == null:
			break
		# If parent is a Window, the current node is the direct child of that Window.
		# Return it if it's a Control so we can parent popups to the same UI container.
		if p is Window and cur is Control:
			return cur as Control
		cur = p
	return null

func screen_to_graph_local(screen_pos: Vector2) -> Vector2:
	# Convert a viewport/screen point into this Control's local space using its global transform.
	# This handles any parent offsets, containers and anchors.
	var inv := get_global_transform().affine_inverse()
	return inv * screen_pos

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		var vp := get_viewport()
		var vp_mouse = ev.global_position
		if vp:
			vp_mouse = vp.get_mouse_position()  # viewport/screen coords

		var graph_local := screen_to_graph_local(vp_mouse)

		# compute ui_root first (avoid using ui_root before declaration)
		var ui_root := _find_ui_root_control()

		# Diagnostics (now include ui_root dump)
		print_debug("[NodeGraph] RIGHT CLICK vp_mouse=", vp_mouse, " graph_local=", graph_local, " ev.position(local)=", ev.position)
		_dump_ancestors_info(self)
		if ui_root:
			_dump_ancestors_info(ui_root)
		_dump_ancestors_info(get_tree().root)
		print_debug("viewport canvas_transform=", get_viewport().get_canvas_transform())

		var menu := NodeContextMenu.new()

		# Parent the popup to the same container that holds the NodeGraph so coords match.
		var menu_parent := get_parent() if get_parent() != null else get_tree().root
		menu_parent.add_child(menu)
		print_debug("[NodeGraph] parenting menu to menu_parent=", menu_parent)

		menu.setup(self, vp_mouse, graph_local)
		# popup_at_screen expects viewport/screen coords; parent is already set
		menu.popup_at_screen(vp_mouse)
		return

	if ev is InputEventMouseMotion and _drag_from != null:
		_drag_pos = get_local_mouse_position()
		queue_redraw()
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and !ev.pressed:
		if _drag_from != null:
			_finish_drag()
			_drag_from = null
			queue_redraw()

func _finish_drag() -> void:
	var mouse_global := get_viewport().get_mouse_position()
	var best: NodePort = null
	for node in get_children():
		if !(node is NodeBase):
			continue
		for vbox in node.get_children():
			if !(vbox is Container):
				continue
			for hb in vbox.get_children():
				if !(hb is HBoxContainer):
					continue
				for ch in hb.get_children():
					if ch is NodePort:
						var p := ch as NodePort
						if _drag_from.is_input == p.is_input:
							continue
						if !_drag_from.is_input and !p.is_input:
							continue
						if p.get_global_rect().has_point(mouse_global) and _drag_from.can_connect_to(p):
							best = p
							break

	if best == null:
		# drag-away to disconnect
		if _drag_from.connections.size() > 0:
			if _drag_from.is_input:
				_drag_from.disconnect_from(_drag_from.connections[0])
			else:
				_drag_from.disconnect_from(_drag_from.connections.back())
		return

	var out_port := _drag_from if !_drag_from.is_input else best
	var in_port := best if best.is_input else _drag_from

	out_port.connect_to(in_port)

	if in_port.max_connections == 1 and in_port.connections.size() > 1:
		while in_port.connections.size() > 1:
			var drop := in_port.connections[0]
			in_port.disconnect_from(drop)

func _to_local(p: Vector2) -> Vector2:
	# Convert a global canvas position to this Control's local position
	# using the node's global transform (affine inverse)
	var gt := get_global_transform()
	return gt.affine_inverse() * p

func _draw_curve_between(a_global: Vector2, b_global: Vector2, ghost: bool = false) -> void:
	var a := _to_local(a_global)
	var b := _to_local(b_global)
	var dx = abs(b.x - a.x)
	var c1 := a + Vector2(dx * 0.5, 0)
	var c2 := b - Vector2(dx * 0.5, 0)

	# approximate cubic with samples
	var segments := PackedVector2Array()
	var STEPS := 20
	for i in range(STEPS + 1):
		var t := float(i) / float(STEPS)
		var p0 := a.lerp(c1, t)
		var p1 := c1.lerp(c2, t)
		var p2 := c2.lerp(b, t)
		var q0 := p0.lerp(p1, t)
		var q1 := p1.lerp(p2, t)
		var r := q0.lerp(q1, t)
		segments.append(r)
	var col := curve_color
	if ghost:
		col.a *= 0.5
	draw_polyline(segments, col, curve_thickness, true)

func _draw() -> void:
	for node in get_children():
		if !(node is NodeBase):
			continue
		var nb := node as NodeBase
		for out_port in nb.outputs:
			for in_port in out_port.connections:
				_draw_curve_between(out_port.get_anchor_global_pos(), in_port.get_anchor_global_pos())
	if _drag_from != null:
		_draw_curve_between(_drag_from.get_anchor_global_pos(), get_viewport().get_mouse_position(), true)

# Evaluation -------------------------------------------------------------

func clear_caches() -> void:
	_eval_cache.clear()
	_expr_cache.clear()

func evaluate_node_output(node: NodeBase, output_idx: int) -> float:
	if broker and node.data_broker == null:
		node.set_data_context(broker, provider)
	var cache = _eval_cache.get(node, {})
	if cache.has(output_idx):
		return float(cache[output_idx])
	var v := node.evaluate_output(output_idx)
	cache[output_idx] = v
	_eval_cache[node] = cache
	return v

func compile_node_output_expr(node: NodeBase, output_idx: int) -> String:
	var cache = _expr_cache.get(node, {})
	if cache.has(output_idx):
		return String(cache[output_idx])
	var expr := node.compile_output_expression(output_idx)
	cache[output_idx] = expr
	_expr_cache[node] = cache
	return expr

func compile_port_expr(node: NodeBase, input_index: int) -> Array[String]:
	if input_index < 0 or input_index >= node.inputs.size():
		return []
	var port := node.inputs[input_index]
	var exprs: Array[String] = []
	for other in port.connections:
		var other_node := other._get_node_base()
		if other_node == null:
			continue
		var out_idx := other_node.outputs.find(other)
		if out_idx >= 0:
			exprs.append(compile_node_output_expr(other_node, out_idx))
	return exprs

func evaluate_fitness() -> void:
	# Fitness node will publish equation to AgentManager
	_expr_cache.clear()
	for node in get_children():
		if node is NodeBase and node.has_method("apply_fitness"):
			node.apply_fitness(self)

func save_to_file(path: String) -> bool:
	var out := {
		"nodes": [],
		"connections": []
	}
	# serialize nodes
	for node in get_children():
		if not (node is NodeBase):
			continue
		var n := node as NodeBase
		var sn := {
			"id": str(n.get_instance_id()),
			"script": n.get_script().resource_path if n.get_script() else "",
			"pos": [n.position.x, n.position.y],
			"title": n.title,
			"props": {}
		}
		# store known node-specific properties
		if n is ValueNode:
			sn["props"]["data_path"] = n.data_path
		elif n is MathNode:
			sn["props"]["op"] = int(n.op)
			sn["props"]["rounding"] = int(n.rounding)
			sn["props"]["decimals"] = n.decimals
		elif n is ClampNode:
			sn["props"]["min_value"] = n.min_value
			sn["props"]["max_value"] = n.max_value
		elif n is MinMaxNode:
			sn["props"]["mode"] = n.mode
		out["nodes"].append(sn)
	# serialize connections
	for node in get_children():
		if not (node is NodeBase):
			continue
		var n := node as NodeBase
		for out_idx in range(n.outputs.size()):
			var pout := n.outputs[out_idx]
			for connected in pout.connections:
				var other_node := connected._get_node_base()
				if other_node == null:
					continue
				var conn := {
					"from_id": str(n.get_instance_id()),
					"from_out": out_idx,
					"to_id": str(other_node.get_instance_id()),
					"to_in": other_node.inputs.find(connected)
				}
				out["connections"].append(conn)
	# write file
	var json := JSON.stringify(out)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open file for writing: " + path)
		return false
	file.store_string(json)
	file.close()
	return true

func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file for reading: " + path)
		return false
	var json := file.get_as_text()
	file.close()
	var result = JSON.parse_string(json)
	if result.error != OK:
		push_error("Failed to parse node graph JSON: " + str(result.error))
		return false
	var data = result.result
	# clear existing graph nodes
	for c in get_children().duplicate():
		if c is NodeBase:
			remove_child(c)
			c.queue_free()
	# instantiate nodes, keep id -> instance map
	var id_map := {}
	for sn in data.get("nodes", []):
		var script_path = sn.get("script", "")
		if script_path == "":
			continue
		var scr := load(script_path)
		if scr == null:
			push_warning("Could not load node script: " + script_path)
			continue
		var node := scr.new() as NodeBase
		add_child(node)
		node.position = Vector2(sn["pos"][0], sn["pos"][1])
		node.set_graph(self)
		node.set_data_context(broker, provider)
		node.title = sn.get("title", node.title)
		var props = sn.get("props", {})
		if node is ValueNode and props.has("data_path"): node.data_path = props["data_path"]
		if node is MathNode:
			if props.has("op"): node.op = MathNode.Op[props["op"]]
			if props.has("rounding"): node.rounding = MathNode.RoundMode[props["rounding"]]
			if props.has("decimals"): node.decimals = int(props["decimals"])
		if node is ClampNode:
			if props.has("min_value"): node.min_value = float(props["min_value"])
			if props.has("max_value"): node.max_value = float(props["max_value"])
		if node is MinMaxNode and props.has("mode"):
			node.mode = props["mode"]
		id_map[sn["id"]] = node
	# recreate connections
	for conn in data.get("connections", []):
		var from_node = id_map.get(conn["from_id"], null)
		var to_node = id_map.get(conn["to_id"], null)
		if from_node == null or to_node == null:
			continue
		var out_idx := int(conn["from_out"])
		var in_idx := int(conn["to_in"])
		if out_idx < 0 or out_idx >= from_node.outputs.size(): continue
		if in_idx < 0 or in_idx >= to_node.inputs.size(): continue
		var out_port = from_node.outputs[out_idx]
		var in_port = to_node.inputs[in_idx]
		if out_port and in_port:
			out_port.connect_to(in_port)
	clear_caches()
	return true

func get_node_registry() -> Dictionary:
	return {
		"Inputs": REG_INPUTS,
		"Math": REG_MATH,
		"Utility": REG_UTILITY,
		"Output": REG_OUTPUT,
	}

func spawn_node_from_entry(entry: Dictionary, at_global: Vector2) -> void:
	var script_path = entry.get("script", "")
	if script_path == "":
		return
	var scr := load(script_path)
	if scr == null:
		push_error("Node script not found: " + script_path)
		return
	var node := scr.new() as NodeBase
	if node == null:
		push_error("Failed to instantiate node from: " + script_path)
		return
	var local_pos := _to_local(at_global)
	add_node(node, local_pos)

func open_context_menu(at_global: Vector2) -> void:
	var menu := preload("res://scripts/ui/nodegraph/context/node_context_menu.gd").new() as NodeContextMenu
	get_tree().root.add_child(menu)
	var vp := get_viewport()
	var screen_pos := at_global
	var canvas_pos := Vector2(screen_pos)
	if vp:
		# convert screen/global -> viewport canvas global coords (used for graph transforms)
		canvas_pos = vp.get_canvas_transform().affine_inverse() * screen_pos
	# setup and show the context menu at the clicked position
	menu.setup(self, screen_pos, canvas_pos)
	menu.popup_at(screen_pos)
func _on_graph_right_click(ev: InputEventMouseButton) -> void:
	if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		var menu := NodeContextMenu.new()
		get_tree().root.add_child(menu)
		# ev.position is local to this Control; compute screen and canvas positions
		var screen_pos := get_screen_position() + ev.position
		var vp := get_viewport()
		var canvas_pos := Vector2(screen_pos)
		if vp:
			canvas_pos = vp.get_canvas_transform().affine_inverse() * screen_pos
		menu.setup(self, screen_pos, canvas_pos)
		# Place the root menu at the screen position of the click
		menu.popup_at(screen_pos)

func _dump_ancestors_info(node: Node) -> void:
	var cur: Node = node
	print_debug("--- ancestor dump for ", node, " ---")
	while cur:
		var info := str(cur, " class=", cur.get_class())
		if cur is CanvasItem:
			var tf := (cur as CanvasItem).get_global_transform()
			info += str(" global_origin=", tf.origin)
			if "position" in cur:
				info += str(" position=", cur.position)
			if "rect_size" in cur:
				info += str(" rect_size=", cur.rect_size)
		print_debug(info)
		cur = cur.get_parent()
	print_debug("--- end dump ---")

func dump_full_env_info(screen_pos: Vector2) -> void:
	print_debug("=== dump_full_env_info ===")
	print_debug("NodeGraph path=", get_path(), " class=", get_class())
	# NodeGraph transforms
	if self is CanvasItem:
		var gt := (self as CanvasItem).get_global_transform()
		print_debug(" NodeGraph global_transform.origin=", gt.origin, " get_global_position=", (self as CanvasItem).get_global_position() if (self as CanvasItem).has_method("get_global_position") else "N/A", " position=", (self as CanvasItem).position if "position" in self else "N/A")
	# Ancestors
	var cur := self.get_parent()
	while cur:
		if cur is CanvasItem:
			print_debug(" ancestor:", cur.get_path(), " class=", cur.get_class(), " global_origin=", (cur as CanvasItem).get_global_transform().origin, " position=",
				(cur.position if "position" in cur else "N/A"), " rect_size=", (cur.rect_size if "rect_size" in cur else "N/A"))
		else:
			print_debug(" ancestor:", cur.get_path(), " class=", cur.get_class())
		cur = cur.get_parent()
	# Root children
	var root := get_tree().root
	print_debug("Root class=", root.get_class(), " children:")
	for c in root.get_children():
		print_debug("  - ", c.get_path(), " class=", c.get_class(), " is_window=", (c is Window))
	# Viewport / canvas
	var vp := get_viewport()
	print_debug(" viewport exists=", vp != null, " canvas_transform=", (vp.get_canvas_transform() if vp else "N/A"), " mouse_pos=", (vp.get_mouse_position() if vp else "N/A"))
	# Project setting that affects popup behavior
	var embed = ProjectSettings.get_setting("display/window/subwindows/embed_subwindows")
	print_debug(" ProjectSettings.display/window/subwindows/embed_subwindows=", embed)
	# If you already created a popup, show its class + global transform
	for c in root.get_children():
		if c is PopupPanel or c is Window:
			print_debug(" popup candidate:", c.get_path(), " class=", c.get_class(), " parent=", c.get_parent(), " global_origin=",
				(c.get_global_transform().origin if c is CanvasItem else "N/A"), " position=", (c.position if "position" in c else "N/A"))
	print_debug(" requested click screen_pos=", screen_pos)
	print_debug("=== end dump ===")
