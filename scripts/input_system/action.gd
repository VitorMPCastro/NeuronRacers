extends Resource
class_name Action

enum ActionType { BUTTON, AXIS }

@export var action_name: String = "PLACEHOLDER"				# name for this action
@export var action_type: ActionType = ActionType.BUTTON
@export var cooldown: float = 0.0						# seconds
@export var is_hold: bool = false						# true = can hold, false = one-shot

# ONLY when ActionType is BUTTON
@export var input_button: Array[InputEvent]
# ONLY when ActionType is AXIS
@export var input_axis_pos: Array[InputEvent]
@export var input_axis_neg: Array[InputEvent]

var last_trigger_time: float = -1000

func _init(act_name: String, act_type: ActionType = ActionType.BUTTON, cd: float = 0.0, hold: bool = false) -> void:
	self.action_name = act_name
	self.action_type = act_type
	self.cooldown = cd
	self.is_hold = hold

func can_trigger(global_time: float) -> bool:
	return global_time - last_trigger_time >= cooldown

func trigger(global_time: float) -> void:
	last_trigger_time = global_time

func get_axis_value() -> float:
	if action_type != ActionType.AXIS:
		return 0.0

	var value := 0.0

	# Positive direction
	for ev in input_axis_pos:
		value += _get_event_strength(ev)

	# Negative direction
	for ev in input_axis_neg:
		value -= _get_event_strength(ev)

	return clamp(value, -1.0, 1.0)


func _is_event_active(ev: InputEvent) -> bool:
	# Handle keyboard
	if ev is InputEventKey:
		return Input.is_key_pressed(ev.physical_keycode)

	# Handle mouse buttons and scroll
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return ev.pressed
		return Input.is_mouse_button_pressed(ev.button_index)
	
	return false

func _get_event_strength(ev: InputEvent) -> float:
	# Keyboard: digital → strength is 1.0 if pressed
	if ev is InputEventKey:
		return 1.0 if Input.is_key_pressed(ev.physical_keycode) else 0.0

	# Mouse buttons: digital → same as keyboard
	if ev is InputEventMouseButton:
		# Wheel is one-shot → only 1.0 on the frame of event
		if ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return 1.0 if ev.pressed else 0.0
		return 1.0 if Input.is_mouse_button_pressed(ev.button_index) else 0.0

	# Joypad motion: analog → use axis value directly
	if ev is InputEventJoypadMotion:
		var raw_strength = Input.get_joy_axis(ev.device, ev.axis)
		# Godot gives -1..1, but we only want magnitude in the correct direction
		if ev.axis_value > 0.0:
			return max(0.0, raw_strength)
		else:
			return abs(min(0.0, raw_strength))

	# Joypad button: digital
	if ev is InputEventJoypadButton:
		return 1.0 if Input.is_joy_button_pressed(ev.device, ev.button_index) else 0.0

	return 0.0
