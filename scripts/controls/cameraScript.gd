extends Camera2D

@export var zoom_speed: float = 0.1		# Velocidade de zoom
@export var min_zoom: float = 0.1		# Zoom mínimo
@export var max_zoom: float = 1.0		# Zoom máximo
@export var camera_change_cd = 0.5

var camera_change_cd_tracker = 0.0
static var always_target_best: bool = false
var target: Node2D = null
@onready var agent_manager = $"../GameManager/AgentManager"

func _physics_process(delta: float) -> void:
	
	if target:
		global_position = target.global_position
	
	if always_target_best:

		camera_change_cd_tracker = 0
		target_best()

func _input(event: InputEvent) -> void:
	if InputManager.get_active_action("Always Track Best Car"):
		always_target_best = not always_target_best
	
	#action is somehow called here and only here (e.g) pressing spacebar in a context where tracking the best car does not matter will not trigger unintended behaviour
	
	if event is InputEventMouseButton: # change these to action sometime
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			adjust_zoom(zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			adjust_zoom(-zoom_speed)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			always_target_best = true
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			target_best()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			always_target_best = false

func adjust_zoom(amount: float) -> void:
	var new_zoom = zoom + Vector2(amount, amount)
	new_zoom.x = clamp(new_zoom.x, min_zoom, max_zoom)
	new_zoom.y = clamp(new_zoom.y, min_zoom, max_zoom)
	zoom = new_zoom

func set_target(obj: Node2D) -> void:
	target = obj

func target_random() -> void:
	set_target(agent_manager.cars[randi() % agent_manager.cars.size()])

func target_best():
	set_target(agent_manager.get_best_car())
