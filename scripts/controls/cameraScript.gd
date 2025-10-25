extends Camera2D

@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.1
@export var max_zoom: float = 1.0
@export var camera_change_cd = 0.5

@export var hud_path: NodePath
@export var highlight_enabled: bool = true
@export var align_rotation_to_car: bool = false

# NEW: rotation deadzone options
@export var align_use_deadzone: bool = false
@export var align_deadzone_deg: float = 10.0

@export var rotation_speed_deg: float = 120.0
@export var north_rotation: float = 0.0

# NEW: smooth switch options
@export var smooth_switch_enabled: bool = true
@export var smooth_switch_duration: float = 0.5
@export var smooth_switch_curve: Curve = Curve.new()

signal target_changed(new_target: Node2D)

var target: Node2D = null
var _hud: Node = null
var _last_highlighted: Node2D = null

# NEW: runtime state for smooth switch
var _is_switching: bool = false
var _switch_elapsed: float = 0.0
var _switch_start_pos: Vector2
var _switch_end_pos: Vector2

func _ready() -> void:
	_resolve_hud()
	# Ensure the curve is valid
	if smooth_switch_curve.get_point_count() == 0:
		smooth_switch_curve.add_point(Vector2(0, 0))
		smooth_switch_curve.add_point(Vector2(1, 1))
	set_process(true)
	set_physics_process(true)

func _process(delta: float) -> void:
	# Manual rotation (Q/E) when not aligning to car
	if !align_rotation_to_car:
		var dir := 0.0
		if Input.is_key_pressed(KEY_Q):
			dir -= 1.0
		if Input.is_key_pressed(KEY_E):
			dir += 1.0
		if dir != 0.0:
			rotation += deg_to_rad(rotation_speed_deg) * dir * delta

	# Align to car heading if enabled (with optional deadzone)
	if align_rotation_to_car and is_instance_valid(target):
		var target_angle := target.global_rotation + deg_to_rad(90)  # keep your current offset
		if align_use_deadzone:
			var err := wrapf(target_angle - rotation, -PI, PI)
			var deadzone := deg_to_rad(max(0.0, align_deadzone_deg))
			if abs(err) > deadzone:
				var step := deg_to_rad(rotation_speed_deg) * delta
				rotation += clamp(err, -step, step)
			# else: within deadzone -> do not adjust rotation
		else:
			rotation = target_angle

func _physics_process(delta: float) -> void:
	# Follow HUD-selected car if available
	var desired: Node2D = _get_hud_observed_car()
	if desired != null and desired != target:
		set_target(desired)

	# Smooth switch in world position
	if _is_switching and is_instance_valid(target):
		_switch_elapsed += delta
		var dur = max(0.0001, smooth_switch_duration)
		var t = clamp(_switch_elapsed / dur, 0.0, 1.0)
		var e := smooth_switch_curve.sample(t)
		global_position = _switch_start_pos.lerp(_switch_end_pos, e)
		if t >= 1.0:
			_is_switching = false
	else:
		if is_instance_valid(target):
			global_position = target.global_position

func _input(event: InputEvent) -> void:
	# Zoom and snap-to-north
	if event is InputEventKey and event.pressed and !event.echo:
		match event.keycode:
			KEY_UP:
				adjust_zoom(-zoom_speed)
				return
			KEY_DOWN:
				adjust_zoom(zoom_speed)
				return
			KEY_N:
				snap_north()
				return

func adjust_zoom(amount: float) -> void:
	var new_zoom := zoom + Vector2(amount, amount)
	new_zoom.x = clamp(new_zoom.x, min_zoom, max_zoom)
	new_zoom.y = clamp(new_zoom.y, min_zoom, max_zoom)
	zoom = new_zoom

func snap_north() -> void:
	rotation = north_rotation

# Public API for HUD
func spectate_car(car: Node2D) -> void:
	set_target(car)

func set_target(obj: Node2D) -> void:
	if obj == target:
		return
	if is_instance_valid(_last_highlighted) and _last_highlighted.has_method("set_highlighted"):
		_last_highlighted.set_highlighted(false)

	# NEW: prepare smooth transition
	if smooth_switch_enabled and is_instance_valid(obj):
		_switch_start_pos = global_position
		_switch_end_pos = obj.global_position
		_switch_elapsed = 0.0
		_is_switching = true
	else:
		_is_switching = false

	target = obj
	if highlight_enabled and is_instance_valid(target) and target.has_method("set_highlighted"):
		target.set_highlighted(true)
		_last_highlighted = target
	target_changed.emit(target)

# Internal helpers ------------------------------------------------------------
func _resolve_hud() -> void:
	if hud_path != NodePath():
		_hud = get_node_or_null(hud_path)
		if _hud: return
	_hud = get_tree().get_first_node_in_group("hud")
	if _hud: return
	var root := get_tree().get_root()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is CanvasLayer and (n.has_method("get_observed_car") or n.has_method("_get_observed_car")):
			_hud = n; return
		for c in n.get_children(): stack.push_back(c)

func _get_hud_observed_car() -> Node2D:
	if _hud == null or !is_instance_valid(_hud):
		_resolve_hud()
	if _hud:
		if _hud.has_method("get_observed_car"): return _hud.get_observed_car() as Node2D
		if _hud.has_method("_get_observed_car"): return _hud._get_observed_car() as Node2D
	return null
