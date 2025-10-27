extends NodeBase
class_name FitnessNode

func _ready() -> void:
	title = "Fitness"
	_build_ui()
	add_input_port("Value", 1)

	# Apply button inline on the node
	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.size_flags_horizontal = Control.SIZE_FILL
	apply_btn.connect("pressed", Callable(self, "_on_apply_pressed"))
	add_internal_field(apply_btn)

func evaluate_output(_port_index: int) -> float:
	return 0.0

# Legacy apply hook used by NodeGraph.evaluate_fitness(); keep for compatibility
func apply_fitness(_graph_ref: NodeGraph) -> void:
	var exprs := graph.compile_port_expr(self, 0)
	if exprs.is_empty():
		return
	var eq := exprs[0] if exprs.size() == 1 else "(" + " + ".join(exprs) + ")"
	var am := get_tree().get_first_node_in_group("AgentManager")
	if am and am.has_method("set_custom_fitness_equation"):
		am.set_custom_fitness_equation(eq)

# Called when the node's Apply button is pressed
func _on_apply_pressed() -> void:
	if graph:
		graph.evaluate_fitness()

	# Build status message from AgentManager parse state
	var am := get_tree().get_first_node_in_group("AgentManager")
	var msg := ""
	var col := Color(0.8, 0.8, 0.2)
	if am == null:
		msg = "Applied (AgentManager not found)"
		col = Color(1, 0.6, 0.2)
	elif "use_custom_fitness" in am:
		if am.use_custom_fitness:
			msg = "Applied: equation parsed successfully"
			col = Color(0.4, 1, 0.4)
		else:
			var eq = am.custom_fitness_equation if "custom_fitness_equation" in am else "<unknown>"
			msg = "Parse error — equation rejected: " + eq
			col = Color(1, 0.4, 0.4)
	else:
		msg = "Applied (no parse status available)"
		col = Color(0.8, 0.8, 0.2)

	# Try to find a parent popup (the NodeEditorPopup) and set its status label.
	# Fallback to printing if not found.
	var p := graph
	var dispatched := false
	while p:
		if p.has_method("set_status"):
			p.set_status(msg, col)
			dispatched = true
			break
		p = p.get_parent()
	if not dispatched:
		print(msg)
