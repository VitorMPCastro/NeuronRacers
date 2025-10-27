extends CharacterBody2D
class_name Car

#CAR CHARACTERISTICS
@export var steering_angle = 15
@export var engine_power = 900       # acts like "force/accel" toward forward

@export_group("Damping (Inspector Units)")
@export var friction_ui: float = 55.0    # actual = friction_ui / 100.0   (e.g., 55 -> 0.55)
@export var drag_ui: float = 600.0       # actual = drag_ui / 10000.0     (e.g., 600 -> 0.06)

@export var braking = 450.0          # braking strength (positive)
@export var max_speed_forward = 2500.0 # optional forward speed cap
@export var max_speed_reverse = 250.0
# Add reverse options
@export var allow_reverse: bool = true
@export var reverse_power_scale: float = 0.7         # fraction of engine_power used in reverse
@export var reverse_engage_speed: float = 20.0        # px/s threshold to switch from braking to reverse drive
@export var traction_curve: Curve = Curve.new()  # maps speed (px/s) to max turn rate (rad/sec)
@export var wheel_base = 65          # Distância entre eixos

# NEW: lateral grip and reverse engage angle
@export var lateral_friction_ui: float = 250.0        # stronger sideways damping (UI units; coeff = /100)
@export var reverse_engage_angle_deg: float = 45.0    # require facing ~backwards to engage reverse

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
var avg_speed_px: float = 0.0
@export var avg_speed_smoothing: float = 0.15  # 0..1, higher = more responsive
var total_speed: float = 0.0  # keep if you already had it
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
var _heading_angle: float = 0.0

# AI gating (read-only reference to AgentManager; Pilot handles gating)
var _am: AgentManager = null
var _ai_phase: int = 0   # this car’s assigned decision phase (0..ai_phases-1)

# SIGNALS AND EVENTS
signal car_death
signal car_spawn

func _on_spawn():
	self.car_data.timestamp_spawn = GameManager.global_time
	# Only create a Pilot if AgentManager didn’t set one
	if self.car_data.pilot == null:
		self.car_data.pilot = PilotFactory.create_random_pilot()
	last_position = global_position
	RaceProgressionManager.register_car_static(self)

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

# NEW: lateral friction coeff
func lateral_friction_coeff() -> float:
	return max(0.0, lateral_friction_ui) / 100.0

@onready var _car_telemetry: CarTelemetry = get_tree().get_first_node_in_group("car_telemetry") as CarTelemetry
@onready var _rpm: RaceProgressionManager = get_tree().get_first_node_in_group("race_progression") as RaceProgressionManager

@export var rpm_update_hz: float = 15.0                 # limit how often we query track progress
@export var rpm_min_distance_px: float = 8.0            # also update when moved this much
@export var physics_sleep_below_speed: float = 0.5      # skip friction work when nearly stopped

var _rpm_accum := 0.0
var _rpm_step := 1.0
var _last_rpm_pos: Vector2 = Vector2.INF

# Progression tracking
var _prev_progress_pos: Vector2 = Vector2.ZERO
@export var rpm_feed_enabled: bool = false  # keep off; RPM polls cars itself
var _registered_with_rpm: bool = false

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
	if _rpm:
		_rpm.register_car(self)
	_rpm_step = 1.0 / max(1.0, rpm_update_hz)
	_last_rpm_pos = global_position
	_register_with_rpm()
	_prev_progress_pos = global_position

func _exit_tree() -> void:
	if _registered_with_rpm:
		RaceProgressionManager.unregister_car_static(self)
		_registered_with_rpm = false
	# Clean up logic (if any)

func _physics_process(_delta: float) -> void:
	acceleration = Vector2.ZERO

	# Input and steering
	handle_input(_delta)
	calculate_steering(_delta)

	# Integrate physics
	_apply_friction_and_drag(_delta)
	velocity += acceleration * _delta

	# Optional: clamp speeds
	var forward_dot := velocity.dot(transform.x)
	var v2 := velocity.length_squared()
	if forward_dot >= 0.0:
		var f2 = max_speed_forward * max_speed_forward
		if v2 > f2:
			velocity = velocity.normalized() * max_speed_forward
	else:
		var r2 = max_speed_reverse * max_speed_reverse
		if v2 > r2:
			velocity = velocity.normalized() * max_speed_reverse

	move_and_slide()

	# Feed latest position to RaceProgressionManager (budgeted internally)
	if _registered_with_rpm:
		RaceProgressionManager.update_car_progress_static(self, global_position, GameManager.global_time)

	# Progress tracking (gate by time AND distance to reduce TrackData work)
	if _rpm:
		_rpm_accum += _delta
		var moved2 := (global_position - _last_rpm_pos).length_squared()
		var dist2 := rpm_min_distance_px * rpm_min_distance_px
		if _rpm_accum >= _rpm_step or moved2 >= dist2:
			_rpm.update_car_progress(self, global_position, GameManager.global_time)
			_rpm_accum = 0.0
			_last_rpm_pos = global_position

	# Stats
	var dist = global_position.distance_to(origin_position)
	if dist > max_distance:
		max_distance = dist
	total_speed += sqrt(v2)

	# Death etc...
	for i in range(get_slide_collision_count()):
		var _collision = get_slide_collision(i)
		die()

var _inputs_buf: PackedFloat32Array = PackedFloat32Array()

func get_ai_inputs() -> PackedFloat32Array:
	var rig := $RayParent as CarSensors
	var sensor_vals: PackedFloat32Array = rig.get_values(self) if rig else PackedFloat32Array()

	# Ensure buffer fits sensors + features
	var want := sensor_vals.size() + int(ai_feature_paths.size())
	if _inputs_buf.size() != want:
		_inputs_buf.resize(want)

	# Copy sensors (fast memcpy-like loop)
	for i in sensor_vals.size():
		_inputs_buf[i] = sensor_vals[i]

	# Telemetry features (numeric only)
	if _car_telemetry and _car_telemetry.data_broker:
		var k := sensor_vals.size()
		for i in ai_feature_paths.size():
			var v = _car_telemetry.data_broker.get_value(self, ai_feature_paths[i])
			match typeof(v):
				TYPE_INT, TYPE_FLOAT: _inputs_buf[k + i] = float(v)
				_: _inputs_buf[k + i] = 0.0
	else:
		# Fill zeros if broker unavailable
		var k := sensor_vals.size()
		for i in ai_feature_paths.size():
			_inputs_buf[k + i] = 0.0

	return _inputs_buf

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

		# Phase gate: only decide on our assigned phase
		var phase_ok := true
		if _am and _am.ai_phases > 1:
			phase_ok = (_am.get_current_ai_phase() == _ai_phase)

		if phase_ok and pilot.can_decide(aps):
			var inputs = get_ai_inputs()
			var act = pilot.decide(inputs)
			_ctrl_target_steer = act.steer
			_ctrl_target_throttle = act.throttle
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

		# Apply throttle/brake/reverse
		var speed := velocity.length()
		var _fwd_speed := velocity.dot(transform.x)     # >0 forward, <0 backward

		if throttle_cmd > 0.0:
			# Forward drive
			acceleration += transform.x * engine_power * throttle_cmd
		elif throttle_cmd < 0.0:
			if not allow_reverse:
				# Brake only
				if speed > 0.0:
					acceleration += -velocity.normalized() * braking * (-throttle_cmd)
			else:
				# NEW: only engage reverse when nearly stopped OR actually moving backwards
				var forward_dot := 0.0
				if speed > 0.0:
					forward_dot = transform.x.dot(velocity / speed)   # 1=forward, -1=backward, 0=sideways
				var moving_backward := forward_dot <= -cos(deg_to_rad(reverse_engage_angle_deg))
				var can_engage_reverse := (speed < reverse_engage_speed) or moving_backward

				if not can_engage_reverse:
					# While sliding forward/sideways: brake to kill velocity (prevents crab-walking)
					acceleration += -velocity.normalized() * braking * (-throttle_cmd)
				else:
					# Engage reverse drive (backward acceleration)
					var rev_power = engine_power * reverse_power_scale
					acceleration += -transform.x * rev_power * (-throttle_cmd)
	else:
		# TODO: player input
		pass

func _apply_friction_and_drag(_delta: float) -> void:
	# Skip when almost stopped and no input
	if acceleration == Vector2.ZERO and velocity.length_squared() < physics_sleep_below_speed * physics_sleep_below_speed:
		velocity = Vector2.ZERO
		return

	var v := velocity
	var speed := v.length()
	if speed <= 0.0:
		return

	# Linear/quadratic drag without extra normalizations
	var b := friction_coeff()
	var a := drag_coeff()
	var linear := -b * v                  # -b * v (no normalize)
	var quadratic := -a * v * speed       # -a * v * |v|

	# Lateral damping (side slip) using projection onto sideways axis
	var side_speed := v.dot(transform.y)
	var side_linear := -transform.y * lateral_friction_coeff() * side_speed

	acceleration += linear + quadratic + side_linear

# 🔄 Steering: preserve speed, rotate velocity by a max angular step
func calculate_steering(delta: float) -> void:
	# Speed and forward direction (from heading, not velocity)
	var speed := velocity.length()
	var _fwd := Vector2.RIGHT.rotated(_heading_angle)

	# Bicycle-model curvature k = tan(delta)/wheel_base
	var steer_rad = steer_direction               # already in radians (-max..+max)
	var curvature := 0.0
	if wheel_base > 0.0:
		curvature = tan(steer_rad) / float(wheel_base)   # 1/px

	# Yaw rate (rad/sec) := v * k, then clamp by traction curve (max turn rate)
	var desired_yaw_rate := speed * curvature
	var yaw_limit := _traction_for_speed()         # rad/sec from curve
	var applied_yaw = clamp(desired_yaw_rate, -yaw_limit, yaw_limit)

	# Integrate heading
	_heading_angle = wrapf(_heading_angle + applied_yaw * delta, -PI, PI)
	rotation = _heading_angle

	# Rotate velocity toward the heading (preserve magnitude, stable when speed ~0)
	if speed > 0.0001:
		var v_ang := velocity.angle()
		var tgt_ang := _heading_angle
		var err := wrapf(tgt_ang - v_ang, -PI, PI)

		# Limit how fast velocity aligns to heading (helps stability at low speed)
		var align_rate := 10.0  # rad/sec, tweak as needed
		var max_align := align_rate * delta
		var align_turn = clamp(err, -max_align, max_align)

		velocity = velocity.rotated(align_turn)

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

var _highlight_aura: HighlightAura = null
var _highlighted: bool = false
const HIGHLIGHT_Z := 1000

func set_highlighted(on: bool) -> void:
	_highlighted = on
	z_as_relative = false
	z_index = HIGHLIGHT_Z if on else 0
	# Ensure an aura exists only when needed
	if on:
		if _highlight_aura == null:
			_highlight_aura = HighlightAura.new()
			_highlight_aura.z_index = HIGHLIGHT_Z + 1
			add_child(_highlight_aura)
		_highlight_aura.visible = true
	else:
		if _highlight_aura:
			_highlight_aura.visible = false

func die() -> void:
	# Idempotent: only run once
	if crashed:
		return
	crashed = true
	set_physics_process(false)
	set_process(false)
	velocity = Vector2.ZERO
	car_death.emit()
	# Optional: keep car registered so final sector/checkpoint events can still be read.
	# If you want to drop it entirely, call _unregister_from_rpm() here instead.
	var sensors := get_node_or_null("CarSensors")
	if sensors:
		sensors.set_physics_process(false)

func _register_with_rpm() -> void:
	if !_registered_with_rpm:
		RaceProgressionManager.register_car_static(self)
		_registered_with_rpm = true
		if RaceProgressionManager and RaceProgressionManager._singleton and RaceProgressionManager._singleton.debug_sector_timing:
			print("[Car] registered in RPM: ", self)

func _unregister_from_rpm() -> void:
	if _registered_with_rpm:
		RaceProgressionManager.unregister_car_static(self)
		_registered_with_rpm = false
		if RaceProgressionManager and RaceProgressionManager._singleton and RaceProgressionManager._singleton.debug_sector_timing:
			print("[Car] unregistered from RPM: ", self)

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

# Returns normalized control axes dict:
# { throttle: 0..1, brake: 0..1, steer: -1..1 }
func get_control_axes() -> Dictionary:
	# Use the car's internal control state directly (no typed-array callables)
	var steer = clamp(_ctrl_steer, -1.0, 1.0)
	var t = clamp(_ctrl_throttle, -1.0, 1.0)
	var throttle = max(0.0, t)
	var brake = max(0.0, -t)

	return {
		"throttle": throttle,
		"brake": brake,
		"steer": steer,
	}

func reset_for_spawn(spawn_pos: Vector2, spawn_rot: float = 0.0) -> void:
	# Reset transforms and dynamics
	global_position = spawn_pos
	global_rotation = spawn_rot
	_heading_angle = spawn_rot
	velocity = Vector2.ZERO
	acceleration = Vector2.ZERO
	steer_direction = 0.0

	# Reset control state
	_ctrl_target_steer = 0.0
	_ctrl_target_throttle = 0.0
	_ctrl_steer = 0.0
	_ctrl_throttle = 0.0

	# Restore visuals
	if has_node("Sprite2D"):
		$Sprite2D.modulate.a = 1.0
	# Clear highlight
	_highlighted = false
	z_as_relative = true
	z_index = 0
	if _highlight_aura:
		_highlight_aura.visible = false

	# Reset runtime flags and stats
	crashed = false
	total_speed = 0.0
	max_distance = 0.0
	origin_position = spawn_pos
	last_position = spawn_pos
	car_data.collected_checkpoints = []
	car_data.timestamp_death = -1.0
	fitness = 0.0
	time_alive = 0.0

	# Re-enable processing
	set_physics_process(true)
	set_process(true)
	visible = true

	# Reset progression cadence
	_rpm_accum = 0.0
	_rpm_step = 1.0 / max(1.0, rpm_update_hz)
	_last_rpm_pos = global_position

	# Re-run spawn logic (timestamp, RP registration, etc.)
	car_spawn.emit()
	# Assign a random decision phase to spread load
	if _am and _am.ai_phases > 1:
		_ai_phase = randi() % _am.ai_phases
	else:
		_ai_phase = 0

func prepare_for_pool() -> void:
	# Make the car inert and hidden before pooling
	set_physics_process(false)
	set_process(false)
	velocity = Vector2.ZERO
	acceleration = Vector2.ZERO
	visible = false
	# Reset fitness/telemetry so pooled cars don't carry over UI values
	fitness = 0.0
	time_alive = 0.0
	total_speed = 0.0
	car_data.collected_checkpoints = []
	# Keep alpha restored so next spawn doesn't look "dead"
	if has_node("Sprite2D"):
		$Sprite2D.modulate.a = 1.0
	_unregister_from_rpm()

func total_checkpoints() -> int:
	return RaceProgressionManager.get_checkpoint_count_static(self)

func get_last_checkpoint_time(cp_index: int) -> float:
	return RaceProgressionManager.get_last_checkpoint_time_static(self, cp_index)

func get_time_between_indices(idx_a: int, idx_b: int) -> float:
	return RaceProgressionManager.get_time_between_indices_static(self, idx_a, idx_b)

func get_sector_time(sector_index_1based: int) -> float:
	return RaceProgressionManager.get_sector_time_static(self, sector_index_1based)
