extends Resource
class_name Action

enum ActionType { BUTTON, AXIS }

@export var name: String = "PLACEHOLDER"				# name for this action
var _action_type: ActionType = ActionType.BUTTON
@export var action_type: ActionType:
	set(value):
		_action_type = value
		notify_property_list_changed()
@export var cooldown: float = 0.0						# seconds
@export var is_hold: bool = false						# true = can hold, false = one-shot

# ONLY when ActionType is BUTTON
@export var keys_button: Array[InputEvent]
# ONLY when ActionType is AXIS
@export var keys_axis_pos: Array[InputEvent]
@export var keys_axis_neg: Array[InputEvent]

var last_trigger_time: float = -1000

func _init(name: String, action_type: ActionType = ActionType.BUTTON, cooldown: float = 0.0, is_hold: bool = false) -> void:
	self.name = name
	self.action_type = action_type
	self.cooldown = cooldown
	self.is_hold = is_hold

func can_trigger(global_time: float) -> bool:
	return global_time - last_trigger_time >= cooldown

func trigger(global_time: float) -> void:
	last_trigger_time = global_time

func get_axis_value() -> float:
	if action_type != ActionType.AXIS:
		return 0.0

	var value := 0.0
	
	for key in keys_axis_pos:
		if key is InputEventKey and Input.is_key_pressed(key.physical_keycode):
			value += 1.0
	for key in keys_axis_neg:
		if key is InputEventKey and Input.is_key_pressed(key.physical_keycode):
			value -= 1.0
	return clamp(value, -1.0, 1.0)
