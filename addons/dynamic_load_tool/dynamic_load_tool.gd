@tool
extends EditorInspectorPlugin

func _can_handle(object) -> bool:
	return object is Action

func _parse_property(object, type, path, hint, hint_text, usage, wide):
	if path == "keys_axis_pos" and object.action_type != Action.ActionType.AXIS:
		return true
	if path == "keys_axis_neg" and object.action_type != Action.ActionType.AXIS:
		return true
	return true
