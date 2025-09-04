extends Resource
class_name InputContext

@export var context_name: String = "Default"	# Context name
@export var actions: Array[Action] = []					# Array of Action resources

func get_action_by_name(action_name: String) -> Action:
	for action in actions:
		if action.name == action_name:
			return action
	return null
