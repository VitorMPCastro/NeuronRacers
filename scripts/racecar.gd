extends CharacterBody2D
class_name Car

#CAR CHARACTERISTICS
@export var steering_angle = 15      # Ângulo máximo de esterçamento
@export var engine_power = 900       # Potência do motor
@export var friction = -55           # Atrito do carro
@export var drag = -0.06             # Arrasto do ar
@export var braking = -450           # Potência de frenagem
@export var max_speed_reverse = 250  # Velocidade máxima em ré
@export var slip_speed = 400         # Velocidade onde a tração diminui (drift)
@export var traction_fast = 2.5      # Tração em alta velocidade
@export var traction_slow = 10       # Tração em baixa velocidade
@export var wheel_base = 65          # Distância entre eixos

#RUNTIME VARS
var crashed = false
var acceleration = Vector2.ZERO      # Vetor de aceleração
var steer_direction = 0.0            # Direção de esterçamento
var camera_follow = false            # Se a câmera está seguindo este carro

#CONTROLS AND AI
@export var is_player = false        # Se este carro é controlado pelo jogador
@export var use_ai = true            # Se este carro é controlado por IA
var control_module
var brain: MLP
var total_speed = 0.0
var time_alive = 0.0
var fitness = 0.0
var origin_position: Vector2
var max_distance = 0.0
var last_position: Vector2

func _to_string() -> String:
	return str("\nbrain: ", self.brain, "\nuse_ai: ", self.use_ai)

func get_average_speed():
	return total_speed / time_alive if time_alive > 0.0 else 0.0

func _ready() -> void:
	var origin_node = get_tree().get_root().get_node("TrackScene/track/TrackOrigin")
	last_position = global_position
	RaceProgressionManager.register_car(self)
	if origin_node:
		origin_position = origin_node.global_position
	else:
		origin_position = global_position  # fallback: posição inicial
	if use_ai:
		brain = MLP.new(5, 8, 2) # 5 sensores, 8 neurônios ocultos, 2 saídas (steering, throttle)

func _physics_process(delta: float) -> void:
	handle_input()
	calculate_steering(delta)
		
	RaceProgressionManager.update_car_progress(self, last_position, global_position)
	last_position = global_position
	
	var distNextCheckpoint = RaceProgressionManager.get_distance_to_next_checkpoint(self)

	# Física geral
	velocity += acceleration * delta
	apply_friction(delta)
	move_and_slide()
	
	var dist = global_position.distance_to(origin_position)
	if dist > max_distance:
		max_distance = dist
	
	total_speed += velocity.length()
	time_alive += delta
	
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		die()

# 📥 Input do jogador
func handle_input() -> void:
	
	if use_ai:
		var sensors = get_sensor_data()
		var outputs = brain.forward(sensors)
		var steering = outputs[0] # -1 a 1
		var throttle = outputs[1] # -1 a 1
		
		steer_direction = steering * deg_to_rad(steering_angle)
		if throttle > 0.1:
			acceleration = transform.x * engine_power * throttle
		elif throttle < -0.1:
			acceleration = transform.x * braking * abs(throttle)
	else:
		acceleration = Vector2.ZERO
		var turn = Input.get_axis("ui_left", "ui_right")
		steer_direction = turn * deg_to_rad(steering_angle)

		if Input.is_action_pressed("ui_up"):
			acceleration = transform.x * engine_power
		elif Input.is_action_pressed("ui_down"):
			acceleration = transform.x * braking

# 🛑 Atrito
func apply_friction(delta: float) -> void:
	if acceleration == Vector2.ZERO and velocity.length() < 50:
		velocity = Vector2.ZERO
	var friction_force = velocity * friction * delta
	var drag_force = velocity * velocity.length() * drag * delta
	acceleration += drag_force + friction_force

# 🔄 Cálculo do esterçamento
func calculate_steering(delta: float) -> void:
	var rear_wheel = position - transform.x * wheel_base / 2.0
	var front_wheel = position + transform.x * wheel_base / 2.0
	rear_wheel += velocity * delta
	front_wheel += velocity.rotated(steer_direction) * delta
	var new_heading = rear_wheel.direction_to(front_wheel)

	var traction = traction_slow if velocity.length() <= slip_speed else traction_fast
	var d = new_heading.dot(velocity.normalized())

	if d > 0:
		velocity = lerp(velocity, new_heading * velocity.length(), traction * delta)
	else:
		velocity = -new_heading * min(velocity.length(), max_speed_reverse)

	rotation = new_heading.angle()

func get_sensor_data() -> Array:
	var data: Array = []
	for child in $RayParent.get_children():
		if child is RayCast2D:
			var ray = child as RayCast2D
			var dist = ray.target_position.length()
			if ray.is_colliding():
				dist = ray.get_collision_point().distance_to(global_position)
			data.append(dist / ray.target_position.length())
	return data

func die():
	$Sprite2D.modulate.a = 0.3
	set_physics_process(false)
	crashed = true
