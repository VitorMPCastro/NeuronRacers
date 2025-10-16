extends CharacterBody2D
class_name Car

#CAR CHARACTERISTICS
@export var steering_angle = 15
@export var engine_power = 900       # acts like "force/accel" toward forward

@export_group("Damping (Inspector Units)")
@export var friction_ui: float = 55.0    # actual = friction_ui / 100.0   (e.g., 55 -> 0.55)
@export var drag_ui: float = 600.0       # actual = drag_ui / 10000.0     (e.g., 600 -> 0.06)

@export var braking = 450.0          # braking strength (positive)
@export var max_speed_forward = 2500 # optional forward speed cap
@export var max_speed_reverse = 250
@export var traction_curve: Curve = Curve.new()  # maps speed (px/s) to max turn rate (rad/sec)
@export var wheel_base = 65          # Distância entre eixos

# AI input features (queried via telemetry/DataBroker, like the leaderboard)
@export_group("AI Inputs")
@export var ai_feature_paths: PackedStringArray = PackedStringArray(["velocity.length()"])  # add more paths if needed

# TUNING
@export var use_auto_top_speed: bool = true
@export var target_top_speed: float = 1000.0  # desired straight-line speed (px/s)
@export var log_tuning_info: bool = true

#RUNTIME VARS
var crashed = false
var acceleration = Vector2.ZERO      # Frame-local force/accel accumulator
var steer_direction = 0.0            # Direção de esterçamento (radians)
var camera_follow = false            # Se a câmera está seguindo este carro

#CONTROLS AND AI
@export var is_player = false        # Se este carro é controlado pelo jogador
@export var use_ai = true
# Smooth the applied controls toward the last decided controls
@export_range(0.0, 60.0, 0.1) var control_smooth_hz: float = 12.0  # 0 = no smoothing
@export var input_deadzone: float = 0.05

# Cached controls (target decided on ticks; applied every physics frame)
var _ctrl_target_steer := 0.0      # -1..1
var _ctrl_target_throttle := 0.0   # -1..1
var _ctrl_steer := 0.0
var _ctrl_throttle := 0.0
var car_data = CarData.new()
var control_module
var total_speed = 0.0
var time_alive: float:
	get():
		return self.car_data.time_alive
	set(value):
		self.car_data.time_alive = value
var fitness: float:
	get():
		return self.car_data.fitness
	set(value):
		self.car_data.fitness = value
var origin_position: Vector2
var max_distance = 0.0
var last_position: Vector2

# AI gating (read-only reference to AgentManager; Pilot handles gating)
var _am: AgentManager = null

# SIGNALS AND EVENTS
signal car_death
signal car_spawn

func _on_spawn():
	self.car_data.timestamp_spawn = GameManager.global_time
	# Only create a Pilot if AgentManager didn’t set one
	if self.car_data.pilot == null:
		self.car_data.pilot = PilotFactory.create_random_pilot()
	var origin_node = get_tree().get_root().get_node("TrackScene/track/TrackOrigin")
	last_position = global_position
	RaceProgressionManager.register_car(self)
	if origin_node:
		origin_position = origin_node.global_position
	else:
		origin_position = global_position  # fallback: posição inicial

func _on_death():
	car_data.timestamp_death = GameManager.global_time
	$Sprite2D.modulate.a = 0.3
	set_physics_process(false)
	crashed = true

func _on_cross_checkpoint(checkpoint):
	self.car_data.collected_checkpoints.append(checkpoint)

func _to_string() -> String:
	return str("\ntime_alive: ", self.time_alive, "\ncrashed: ", self.crashed, "\nis_player: ", self.is_player, "\nmax_distance: ", self.max_distance, "\nuse_ai: ", self.use_ai)

func get_average_speed():
	return total_speed / time_alive if time_alive > 0.0 else 0.0

func speed_as_fraction_of_top_speed() -> float:
	var v := velocity.length()
	var vt = target_top_speed if use_auto_top_speed else max_speed_forward
	return v / vt if vt > 0.0 else 0.0

func _traction_for_speed() -> float:
	return max(0.0, traction_curve.sample_baked(max(0.0, speed_as_fraction_of_top_speed())))

func collect_telemetry():
	self.top_speed = velocity.length()

func friction_coeff() -> float:
	return max(0.0, friction_ui) / 100.0

func drag_coeff() -> float:
	return max(0.0, drag_ui) / 10000.0

@onready var _car_telemetry: CarTelemetry = get_tree().get_first_node_in_group("car_telemetry") as CarTelemetry

func _ready() -> void:
	car_spawn.connect(_on_spawn)
	car_death.connect(_on_death)
	car_spawn.emit()
	_am = get_parent() as AgentManager
	# Auto-tune damping to reach target top speed (optional)
	if use_auto_top_speed:
		_retune_for_target_top_speed()
		if log_tuning_info:
			var v := _expected_terminal_speed()
			print("Car damping tuned. friction_ui=", friction_ui, " (", friction_coeff(), "), drag_ui=", drag_ui, " (", drag_coeff(), "), expected_top_speed≈", v)

func _physics_process(delta: float) -> void:
	acceleration = Vector2.ZERO
	handle_input(delta)
	calculate_steering(delta)

	RaceProgressionManager.update_car_progress(self, last_position, global_position)
	last_position = global_position

	_apply_friction_and_drag(delta)
	velocity += acceleration * delta

	# Optional: clamp speeds
	if velocity.dot(transform.x) >= 0.0 and velocity.length() > max_speed_forward:
		velocity = velocity.normalized() * max_speed_forward
	elif velocity.dot(transform.x) < 0.0 and velocity.length() > max_speed_reverse:
		velocity = velocity.normalized() * max_speed_reverse

	move_and_slide()

	var dist = global_position.distance_to(origin_position)
	if dist > max_distance:
		max_distance = dist
	
	total_speed += velocity.length()
	
	for i in range(get_slide_collision_count()):
		var _collision = get_slide_collision(i)
		die()

func get_ai_inputs() -> Array:
	# Ray sensors (normalized)
	var inputs: Array = []
	var rig := $RayParent as CarSensors
	if rig:
		var packed: PackedFloat32Array = rig.get_values(self)
		# Convert to Array to match MLP.forward signature
		for i in packed.size():
			inputs.append(packed[i])

	# Telemetry features (queried via DataBroker, like leaderboard columns)
	inputs.append_array(_get_telemetry_inputs())
	return inputs

func ai_input_size() -> int:
	var ray_count := 0
	var rig := $RayParent as CarSensors
	if rig:
		ray_count = rig.get_enabled_ray_count()
	# Count telemetry features as additional inputs
	return ray_count + int(ai_feature_paths.size())

func _get_telemetry_inputs() -> Array:
	var out: Array = []
	if _car_telemetry == null or _car_telemetry.data_broker == null:
		# Fallback zeros if telemetry is not available
		for _i in ai_feature_paths.size():
			out.append(0.0)
		return out

	for path in ai_feature_paths:
		var v = _car_telemetry.data_broker.get_value(self, path)
		# Ensure numeric; non-numeric values become 0.0
		match typeof(v):
			TYPE_INT, TYPE_FLOAT:
				out.append(float(v))
			_:
				out.append(0.0)
	return out

# 📥 Input (AI is delegated to Pilot)
func handle_input(delta: float) -> void:
	if use_ai:
		var pilot = car_data.pilot
		if pilot == null:
			return

		var aps := (_am.ai_actions_per_second if _am else 0.0)

		# Update targets on ai_tick; keep applying every frame
		if pilot.can_decide(aps):
			var inputs = get_ai_inputs()  # <— use the declared inputs
			var act = pilot.decide(inputs)
			_ctrl_target_steer = clamp(float(act.get("steer", 0.0)), -1.0, 1.0)
			_ctrl_target_throttle = clamp(float(act.get("throttle", 0.0)), -1.0, 1.0)
			pilot.consume_decision(aps)

		# Smooth application each frame
		var hz = max(0.0, control_smooth_hz)
		var alpha = 1.0 if hz <= 0.0 else (1.0 - pow(2.0, -delta * hz))
		_ctrl_steer = lerp(_ctrl_steer, _ctrl_target_steer, alpha)
		_ctrl_throttle = lerp(_ctrl_throttle, _ctrl_target_throttle, alpha)

		# Deadzone
		var steer_cmd = _ctrl_steer if abs(_ctrl_steer) > input_deadzone else 0.0
		var throttle_cmd = _ctrl_throttle if abs(_ctrl_throttle) > input_deadzone else 0.0

		# Apply steer continuously
		var max_steer_rad = deg_to_rad(steering_angle)
		steer_direction = steer_cmd * max_steer_rad

		# Apply throttle/brake continuously (no extra delta here)
		if throttle_cmd > 0.0:
			acceleration += transform.x * engine_power * throttle_cmd
		elif throttle_cmd < 0.0 and velocity != Vector2.ZERO:
			# Brake opposite to current motion
			acceleration += -velocity.normalized() * braking * (-throttle_cmd)
	else:
		# TODO: player input
		pass

func _apply_friction_and_drag(_delta: float) -> void:
	# If nearly stopped and no input, snap to rest
	if acceleration == Vector2.ZERO and velocity.length() < 1.0:
		velocity = Vector2.ZERO
		return

	var v := velocity
	var speed := v.length()
	if speed <= 0.0:
		return

	var dir := v / speed
	var b := friction_coeff()
	var a := drag_coeff()
	# Linear damping (rolling resistance, drivetrain losses)
	var linear = -dir * b * speed
	# Quadratic damping (air drag)
	var quadratic = -dir * a * speed * speed
	# Add to this frame's acceleration (no extra delta here)
	acceleration += linear + quadratic

# 🔄 Steering: preserve speed, rotate velocity by a max angular step
func calculate_steering(delta: float) -> void:
	if velocity == Vector2.ZERO and _ctrl_throttle == 0.0:
		return

	# Bicycle model to compute a target heading
	var rear_wheel = position - transform.x * wheel_base * 0.5
	var front_wheel = position + transform.x * wheel_base * 0.5
	rear_wheel += velocity * delta
	front_wheel += velocity.rotated(steer_direction) * delta
	var target_heading := rear_wheel.direction_to(front_wheel)

	var speed := velocity.length()
	if speed <= 0.0:
		rotation = target_heading.angle()
		return

	var current_ang := velocity.angle()
	var target_ang := target_heading.angle()
	var delta_ang := wrapf(target_ang - current_ang, -PI, PI)

	var traction := _traction_for_speed()     # rad/sec
	var max_turn := traction * delta
	var apply_turn = clamp(delta_ang, -max_turn, max_turn)

	velocity = velocity.rotated(apply_turn)   # preserve magnitude, change direction
	rotation = velocity.angle()

func get_sensor_data() -> Array:
	var rig := $RayParent as CarSensors
	if rig:
		# Ask CarSensors for already-normalized values; convert to Array for MLP
		var packed: PackedFloat32Array = rig.get_values(self)
		var result: Array = []
		result.resize(packed.size())
		for i in range(packed.size()):
			result[i] = packed[i]
		return result
	# Legacy fallback removed; ensure a CarSensors is present under RayParent
	return []

func die():
	car_death.emit()

# Compute expected terminal speed for current engine_power, friction, drag
func _expected_terminal_speed(F: float = engine_power, b: float = -1.0, a: float = -1.0) -> float:
	if b < 0.0:
		b = friction_coeff()
	if a < 0.0:
		a = drag_coeff()
	if a <= 0.0:
		return F / max(0.000001, b) if b > 0.0 else INF
	var disc := b * b + 4.0 * a * F
	return max(0.0, (-b + sqrt(disc)) / (2.0 * a))

# Choose drag (and adjust friction if necessary) so that F = b*V + a*V^2 at V = target_top_speed
func _retune_for_target_top_speed() -> void:
	var V = max(1.0, target_top_speed)
	var F = max(0.0, engine_power)
	var b = max(0.0, friction_coeff())
	var a = (F - b * V) / (V * V)
	if a <= 0.0:
		# If friction is too high to reach V, reduce friction to 10% of F/V
		b = 0.1 * F / V
		friction_ui = b * 100.0
		b = friction_coeff()
		a = (F - b * V) / (V * V)
	# Write back UI-scaled values
	drag_ui = max(a, 1e-6) * 10000.0
