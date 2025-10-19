extends Node2D
class_name CarSensors

@export_category("Owner")
@export var car_path: NodePath = ^".."    # by default, use parent as the car

@export_category("Casting")
@export var collision_mask: int = 1
@export var exclude_owner: bool = true
@export var rays: Array[SensorRay] = []   # SensorRay is expected to have: enabled (bool), angle/angle_deg/angle_rad, max_distance (float)

@export_category("Performance")
@export var sample_every_n_physics_frames: int = 1
@export var draw_debug: bool = false

var _frame_ctr: int = 0
var _values_norm: PackedFloat32Array = PackedFloat32Array()
var _values_raw: PackedFloat32Array = PackedFloat32Array()

@onready var _car: Node2D = get_node_or_null(car_path) as Node2D

func _ready() -> void:
	_resize_buffers()

func _physics_process(_delta: float) -> void:
	var target := _car if is_instance_valid(_car) else (get_parent() as Node2D)
	if sample_every_n_physics_frames <= 1:
		_cast(target)
	else:
		_frame_ctr = (_frame_ctr + 1) % sample_every_n_physics_frames
		if _frame_ctr == 0:
			_cast(target)
	if draw_debug:
		queue_redraw()

func _resize_buffers() -> void:
	_values_norm.resize(rays.size())
	_values_raw.resize(rays.size())

func get_enabled_ray_count() -> int:
	var count := 0
	for r in rays:
		if typeof(r) == TYPE_NIL:
			continue
		var on := true
		if "enabled" in r:
			on = bool(r.enabled)
		count += 1 if on else 0
	return count

func get_values(owner_node: Node = null, force_sample: bool = false) -> PackedFloat32Array:
	if force_sample:
		var target := (owner_node as Node2D) if owner_node is Node2D else _car
		_cast(target)
	return _values_norm

func get_values_raw(owner_node: Node = null, force_sample: bool = false) -> PackedFloat32Array:
	if force_sample:
		var target := (owner_node as Node2D) if owner_node is Node2D else _car
		_cast(target)
	return _values_raw

func _cast(owner_node: Node2D) -> void:
	if _values_norm.size() != rays.size():
		_resize_buffers()
	if owner_node == null:
		# No valid owner; return max distances normalized to 1.0
		for i in range(rays.size()):
			var r = rays[i]
			var md := (r.max_distance if r and "max_distance" in r else 200.0)
			_values_raw[i] = md
			_values_norm[i] = 1.0
		return

	var space := get_world_2d().direct_space_state
	var origin := owner_node.global_position
	var base_angle := owner_node.global_rotation

	for i in range(rays.size()):
		var r = rays[i]
		if r == null:
			_values_raw[i] = 0.0
			_values_norm[i] = 0.0
			continue
		# Enabled flag (optional)
		if "enabled" in r and not r.enabled:
			_values_raw[i] = 0.0
			_values_norm[i] = 0.0
			continue

		# Determine ray angle and length with robust fallbacks
		var ang := 0.0
		if "angle_rad" in r:
			ang = float(r.angle_rad)
		elif "angle" in r:        # assume radians
			ang = float(r.angle)
		elif "angle_deg" in r:
			ang = deg_to_rad(float(r.angle_deg))
		else:
			# fan from -60..+60 degrees as a fallback
			var n := max(1, rays.size() - 1)
			ang = deg_to_rad(-60.0 + 120.0 * float(i) / float(n))

		var max_d := 200.0
		if "max_distance" in r:
			max_d = float(r.max_distance)

		var dir := Vector2.RIGHT.rotated(base_angle + ang)
		var to := origin + dir * max_d

		var params := PhysicsRayQueryParameters2D.create(origin, to, collision_mask)
		if exclude_owner:
			params.exclude = [owner_node.get_rid()]

		var hit := space.intersect_ray(params)
		var dist_raw := max_d
		if not hit.is_empty():
			var hit_pos: Vector2 = hit.get("position", to)
			dist_raw = origin.distance_to(hit_pos)

		_values_raw[i] = dist_raw
		_values_norm[i] = clamp(dist_raw / max_d, 0.0, 1.0)

func _draw() -> void:
	if not draw_debug:
		return
	# Minimal debug: draw rays with lengths from cached raw values
	var owner_node := _car if is_instance_valid(_car) else (get_parent() as Node2D)
	if owner_node == null:
		return
	var origin := owner_node.global_position
	var base_angle := owner_node.global_rotation

	for i in range(rays.size()):
		var r = rays[i]
		if r == null:
			continue
		if "enabled" in r and not r.enabled:
			continue

		var ang := 0.0
		if "angle_rad" in r:
			ang = float(r.angle_rad)
		elif "angle" in r:
			ang = float(r.angle)
		elif "angle_deg" in r:
			ang = deg_to_rad(float(r.angle_deg))
		else:
			var n := max(1, rays.size() - 1)
			ang = deg_to_rad(-60.0 + 120.0 * float(i) / float(n))

		var max_d := (float(r.max_distance) if "max_distance" in r else 200.0)
		var used_len := clamp(_values_raw[i], 0.0, max_d)
		var dir := Vector2.RIGHT.rotated(base_angle + ang)
		var to := origin + dir * used_len

		draw_line(to_local(origin), to_local(to), Color(0.3, 1.0, 0.3, 0.8), 2.0)
