extends Resource
class_name InputContext

@export var context_name: String = "Default"	# Context name
@export var actions_intake: Array[Action] = []					# Array of Action resources
var actions: Dictionary[String, Action] = {}

func _ready() -> void:
	for action in actions_intake:
		if action:
			actions[action.action_name] = action

func get_action_by_name(action_name: String) -> Action:
	print(actions_intake)
	if not actions.has(action_name):
		return null
	return actions[action_name]
