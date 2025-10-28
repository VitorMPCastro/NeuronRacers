# TODO: If you have a DraggablePanel base class, change 'extends Control' to extend that instead.
extends Control
class_name BaseNode

# Base reusable node class (minimal, parser-friendly)
var inputs: Array = []
var outputs: Array = []
var fields: Array = []
var node_id: String = ""

func _ready() -> void:
	pass

func configure_ports(p_inputs: Array, p_outputs: Array) -> void:
	inputs = []
	for pi in p_inputs:
		var name: String
		var maxc: int
		if typeof(pi) == TYPE_DICTIONARY:
			if "name" in pi:
				name = str(pi["name"])
			else:
				name = str(pi)
			if "max" in pi:
				maxc = int(pi["max"])
			else:
				maxc = 1
		else:
			name = str(pi)
			maxc = 1
		inputs.append({"name": name, "max": maxc, "connections": []})
	outputs = []
	for po in p_outputs:
		var name2: String
		var maxc2: int
		if typeof(po) == TYPE_DICTIONARY:
			if "name" in po:
				name2 = str(po["name"])
			else:
				name2 = str(po)
			if "max" in po:
				maxc2 = int(po["max"])
			else:
				maxc2 = -1
		else:
			name2 = str(po)
			maxc2 = -1
		outputs.append({"name": name2, "max": maxc2, "connections": []})

# Simple checks
func can_connect_output(out_idx: int, target_node: BaseNode, in_idx: int) -> bool:
	if target_node == null or target_node == self:
		return false
	if out_idx < 0 or out_idx >= outputs.size():
		return false
	var out_info = outputs[out_idx]
	if out_info["max"] != -1 and out_info["connections"].size() >= out_info["max"]:
		return false
	if in_idx < 0 or in_idx >= target_node.inputs.size():
		return false
	var in_info = target_node.inputs[in_idx]
	if in_info["connections"].size() >= in_info["max"]:
		return false
	return true

func connect_to(out_idx: int, target_node: BaseNode, in_idx: int) -> bool:
	if not can_connect_output(out_idx, target_node, in_idx):
		return false
	outputs[out_idx]["connections"].append({"node": target_node, "in_idx": in_idx})
	target_node.inputs[in_idx]["connections"].append({"node": self, "out_idx": out_idx})
	return true

func disconnect_output(out_idx: int, target_node: BaseNode, in_idx: int) -> void:
	# safe removal using loops (dictionaries used for storage)
	if out_idx >= 0 and out_idx < outputs.size():
		for i in outputs[out_idx]["connections"].duplicate():
			if i.has("node") and i["node"] == target_node and i.has("in_idx") and int(i["in_idx"]) == in_idx:
				outputs[out_idx]["connections"].erase(i)
	if target_node and in_idx >= 0 and in_idx < target_node.inputs.size():
		for j in target_node.inputs[in_idx]["connections"].duplicate():
			if j.has("node") and j["node"] == self and j.has("out_idx") and int(j["out_idx"]) == out_idx:
				target_node.inputs[in_idx]["connections"].erase(j)

func evaluate() -> Variant:
	return null
