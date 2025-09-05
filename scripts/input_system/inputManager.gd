extends Node
class_name InputManager

# CONTEXT MANAGEMENT
@export var contexts_intake: Array[InputContext] = []
static var contexts: Dictionary[String, InputContext] = {}						# context_name -> InputContext
static var active_context: String = ""

func _ready() -> void:
	for context in contexts_intake:
		if context:
			contexts[context.context_name] = context

func register_contexts_from_node(config: Node):
	for context in config.contexts:
		contexts[context.context_name] = context

# PUBLIC API
# Checks if action is pressed (holds)
func is_action_pressed(action_name: String) -> bool:
	var action = get_active_action(action_name)
	if not action:
		return false
	for key in action.default_keys:
		if Input.is_key_pressed(key):
			return true
	return false

# Checks if action is just triggered (one-shot)
static func is_action_just_triggered(action_name: String) -> bool:
	var action = get_active_action(action_name)
	if not action:
		return false
	for key in action.default_keys:
		if Input.is_key_pressed(key):
			if action.can_trigger(GameManager.global_time):
				action.trigger(GameManager.global_time)
				return true
	return false

# Change key bindings
func remap_action(action_name: String, new_keys: Array) -> void:
	var action = get_active_action(action_name)
	if action:
		action.default_keys = new_keys

# Switch active context
static func set_active_context(context_name: String) -> void:
	if contexts.has(context_name):
		active_context = context_name
	else:
		push_error("Context not found: " + context_name)

# INTERNAL
static func get_active_action(action_name: String) -> Action:
	if not active_context or not contexts.has(active_context):
		return null
	return contexts[active_context].get_action_by_name(action_name)
