extends Node2D
class_name CarSensors

@export_category("Casting")
@export var collision_mask: int = 1
@export var exclude_owner: bool = true
@export var rays: Array[SensorRay] = []

@export_category("Output")
@export var normalize_output: bool = true          # true -> 0..1 (1=no hit within max)
@export var no_hit_value: float = 1.0              # value used when no hit (if normalized)
@export var clamp_output: bool = true              # clamp to [0..1] when normalized

@export_category("Authoring helpers")
@export var auto_generate_on_ready: bool = true
@export var default_ray_count: int = 7
@export var default_fov_deg: float = 120.0
@export var default_max_length_px: float = 1200.0  # was 800; higher default but still clamps absurd per-ray lengths

@export_category("Sampling/LOD")
@export var update_hz: float = 15.0                # how often to update sensor rays
var _lod_factor := 1.0                             # 1.0 = normal; >1.0 = slower; <1.0 = faster

@export_category("Debug draw")
@export var draw_debug: bool = false
@export var hit_color: Color = Color(0.2, 1.0, 0.2, 0.9)
@export var miss_color: Color = Color(1.0, 0.3, 0.3, 0.6)
@export var hit_thickness: float = 2.0
@export var miss_thickness: float = 1.0

@export_category("Throughput")
@export var rays_per_tick: int = -1                  # -1 = all rays; otherwise update this many per tick (round-robin)
@export var use_dynamic_lod: bool = true             # adapt update rate by speed
@export var lod_speed_thresholds_px: Vector2 = Vector2(100.0, 400.0)  # <x => slower, >y => faster

var _last_segments: Array = []              # Array[{from:Vector2, to:Vector2, hit:bool}]
var _last_values_norm: PackedFloat32Array   # cached normalized values (size == enabled rays)
var _last_values_raw: PackedFloat32Array    # cached raw distances in pixels

# Budgeted sampling state
var _accum := 0.0
var _query := PhysicsRayQueryParameters2D.new()

@export var use_phased_updates: bool = true
var _phase_mod: int = 0
var _phase_total: int = 1

var _rr_index: int = 0  # round-robin cursor across enabled rays

func set_phase(mod_index: int, total: int) -> void:
	_phase_mod = clampi(mod_index, 0, max(1, total) - 1)
	_phase_total = max(1, total)

func _ready() -> void:
	# Authoring helper: generate rays if none provided
	if rays.is_empty() and auto_generate_on_ready:
		generate_even_rays(default_ray_count, default_fov_deg, default_max_length_px)

	# Prepare reusable ray query
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_query.collision_mask = collision_mask
	if exclude_owner and get_owner():
		_query.exclude = [get_owner()]

	# Desynchronize sampling to avoid bursts when many cars spawn at once
	var step = 1.0 / max(1.0, update_hz)
	_accum = randf() * step

	# Clamp absurd per-ray lengths (scene may contain 1e6px)
	_clamp_ray_lengths()

	# Enable periodic sampling and prime caches once
	set_physics_process(true)
	_cast_all_rays()

func set_lod_factor(f: float) -> void:
	_lod_factor = max(0.25, f)

func _physics_process(_delta: float) -> void:
	if use_phased_updates and _phase_total > 1:
		if int(Engine.get_physics_frames() % _phase_total) != _phase_mod:
			return

	# Optional dynamic LOD: slower cars sample less frequently
	if use_dynamic_lod:
		var sp := 0.0
		var own := get_owner()
		if own != null:
			if own.has_method("get_speed_px"):
				sp = own.get_speed_px()
			elif "velocity" in own:
				sp = (own.velocity as Vector2).length()
		var lo := lod_speed_thresholds_px.x
		var hi = max(lo + 1.0, lod_speed_thresholds_px.y)
		# Map speed to LOD factor in [2.0 .. 1.0] (slow -> fewer updates)
		var t = clamp((sp - lo) / (hi - lo), 0.0, 1.0)
		_lod_factor = lerp(2.0, 1.0, t)

	var step = (1.0 / max(1.0, update_hz)) * _lod_factor
	_accum += _delta
	if _accum < step:
		return
	_accum = 0.0
	_cast_all_rays()
	if draw_debug:
		queue_redraw()

func _clamp_ray_lengths() -> void:
	for r in rays:
		if r and r.enabled:
			r.max_length_px = min(r.max_length_px, default_max_length_px)

func get_enabled_ray_count() -> int:
	var n := 0
	for r in rays:
		if r != null and r.enabled:
			n += 1
	return n

# Main API: returns PackedFloat32Array (normalized if normalize_output==true)
# NOTE: uses cached values (no raycast here). If called before first physics tick, we prime once.
func get_values(_owner_node: Node = null) -> PackedFloat32Array:
	if _last_values_norm.size() == 0 and _last_values_raw.size() == 0:
		_cast_all_rays()
	return _last_values_norm if normalize_output else _last_values_raw

# Raw distances in pixels (always)
func get_values_raw(_owner_node: Node = null) -> PackedFloat32Array:
	if _last_values_raw.size() == 0:
		_cast_all_rays()
	return _last_values_raw

# Backward-compatible alias (returns Array[float])
func sample(owner_node: Node = null) -> Array:
	var p := get_values(owner_node)
	var a: Array = p
	return a

# Authoring helper: generate evenly spaced rays across FOV
func generate_even_rays(count: int, fov_deg: float, max_len: float) -> void:
	rays.clear()
	if count <= 1:
		var r := SensorRay.new()
		r.angle_deg = 0.0
		r.max_length_px = max(1.0, max_len)
		rays.append(r)
	else:
		var half := fov_deg * 0.5
		for i in range(count):
			var t := float(i) / float(max(1, count - 1))
			var angle := -half + t * fov_deg
			var r := SensorRay.new()
			r.angle_deg = angle
			r.max_length_px = max(1.0, max_len)
			rays.append(r)

func _cast_all_rays() -> void:
	_last_segments.clear()

	var space := get_world_2d().direct_space_state
	if space == null:
		_last_values_raw = PackedFloat32Array()
		_last_values_norm = PackedFloat32Array()
		return

	var origin := global_position
	var basis_rot := global_rotation

	# Build enabled-ray index list once
	var enabled_indices: Array[int] = []
	for i in range(rays.size()):
		var r = rays[i]
		if r != null and r.enabled:
			enabled_indices.append(i)
	var enabled := enabled_indices.size()

	# Prepare buffers with exact enabled-ray count (reuse if sizes match)
	if _last_values_raw.size() != enabled:
		_last_values_raw.resize(enabled)
	if normalize_output and _last_values_norm.size() != enabled:
		_last_values_norm.resize(enabled)
	if enabled == 0:
		return

	# Choose how many rays to update this tick
	var quota := enabled if rays_per_tick <= 0 else clampi(rays_per_tick, 1, enabled)
	if _rr_index >= enabled:
		_rr_index = 0

	# Update a subset in round-robin to spread cost over multiple ticks
	for j in range(quota):
		var k := (_rr_index + j) % enabled                # slot in enabled-ray order
		var ray_i := enabled_indices[k]                   # index into 'rays' array
		var ray_def: SensorRay = rays[ray_i]

		var dir := Vector2.RIGHT.rotated(deg_to_rad(ray_def.angle_deg) + basis_rot)
		var max_len = min(max(1.0, ray_def.max_length_px), default_max_length_px)
		var from := origin
		var to = origin + dir * max_len

		_query.from = from
		_query.to = to

		var hit := space.intersect_ray(_query)

		if hit.is_empty():
			_last_values_raw[k] = max_len
			if normalize_output:
				_last_values_norm[k] = no_hit_value
			if draw_debug:
				_last_segments.append({ "from": from, "to": to, "hit": false })
		else:
			var hit_pos: Vector2 = hit["position"]
			var dist := from.distance_to(hit_pos)
			_last_values_raw[k] = dist
			if normalize_output:
				var v = dist / max_len
				_last_values_norm[k] = clamp(v, 0.0, 1.0) if clamp_output else v
			if draw_debug:
				_last_segments.append({ "from": from, "to": hit_pos, "hit": true })

	# Advance cursor for next tick
	_rr_index = (_rr_index + quota) % enabled

func _draw() -> void:
	if !draw_debug:
		return
	for seg in _last_segments:
		var from: Vector2 = seg["from"]
		var to: Vector2 = seg["to"]
		var hit: bool = seg["hit"]
		draw_line(to_local(from), to_local(to), hit_color if hit else miss_color, hit_thickness if hit else miss_thickness)
