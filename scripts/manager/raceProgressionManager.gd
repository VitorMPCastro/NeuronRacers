extends Node
class_name RaceProgressionManager

signal checkpoints_changed
signal checkpoint_collected(car: Node, checkpoint_index: int, lap: int, t: float)
signal lap_changed(car: Node, lap: int)

# Singleton for static API compatibility
static var _singleton: RaceProgressionManager = null

@export var track_path: NodePath
@export var track_data_path: NodePath

# Require the car to surpass this extra progress (in px) past the checkpoint to award it.
# Prevents instant CP_0 at spawn jitter and helps with sensor noise.
@export var award_progress_margin: float = 5.0

@onready var track: Track = get_node_or_null(track_path) as Track
@onready var track_data: TrackData = get_node_or_null(track_data_path) as TrackData

# Cached from TrackData
var track_length: float = 0.0
var checkpoints: Array[Vector2] = []                   # checkpoint world positions (for UI/debug)
var _checkpoints_progress: PackedFloat32Array = []     # each cp absolute progress [0..track_length]

# Per-car progression state (instance)
# car_state[car] = { "index": int, "checkpoints": int, "time_collected": float,
#                    "last_progress": float, "lap": int, "collected_ids": Array[int] }
var car_state: Dictionary = {}

# Tunables
const WRAP_THRESHOLD := 0.4  # fraction of track_length to consider wrap-around
const EPS := 0.001

@export var progress_updates_per_frame: int = 32
var _pending_latest: Dictionary = {}   # car -> {pos: Vector2, t: float}

func _enter_tree() -> void:
	_singleton = self

func _ready() -> void:
	add_to_group("race_progression")
	_bind_track_refs()
	_rebuild_cache()
	if track and track.has_signal("track_built") and not track.track_built.is_connected(_on_track_built):
		track.track_built.connect(_on_track_built)
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	# Drain up to budget latest updates; skip crashed cars
	var budget = max(1, progress_updates_per_frame)
	if _pending_latest.is_empty():
		return
	# Copy keys to avoid mutating while iterating
	var cars_to_process := _pending_latest.keys()
	var processed := 0
	for c in cars_to_process:
		if processed >= budget:
			break
		var pack = _pending_latest.get(c, null)
		_pending_latest.erase(c) # remove first to keep the queue bounded
		if pack == null:
			continue
		if c == null or !is_instance_valid(c):
			continue
		if "crashed" in c and c.crashed:
			continue
		_process_progress_for(c, pack.pos, pack.t)
		processed += 1

func _exit_tree() -> void:
	if _singleton == self:
		_singleton = null

func _bind_track_refs() -> void:
	# If not provided via exports, try to bind from scene
	if track == null:
		var gm := get_tree().get_root().find_child("GameManager", true, false)
		if gm:
			track = gm.find_child("Track", true, false) as Track
	if track_data == null:
		if track:
			track_data = (track as Node).find_child("TrackData", true, false) as TrackData
		if track_data == null:
			track_data = get_tree().get_first_node_in_group("track_data") as TrackData

func _on_track_built() -> void:
	_rebuild_cache()
	# Reset per-car last_progress to avoid false wrap on freshly rebuilt tracks
	for car in car_state.keys():
		var st = car_state[car]
		st["last_progress"] = 0.0
		st["lap"] = 0
		car_state[car] = st

func _rebuild_cache() -> void:
	checkpoints.clear()
	_checkpoints_progress = PackedFloat32Array()
	track_length = 0.0

	if track_data == null:
		return
	if track_data.center_line == null or track_data.center_line.points.size() < 2:
		return

	# Ensure TrackData prepared its structures (use provided tools if available)
	if track_data.has_method("calculate_track_length"):
		track_data.calculate_track_length()
	if track_data.has_method("divide_sectors"):
		track_data.divide_sectors()
	if track_data.has_method("generate_checkpoints"):
		track_data.generate_checkpoints()

	track_length = track_data.track_length

	# Order checkpoint keys by numeric suffix: "Checkpoint_1".."Checkpoint_N"
	var ordered: Array = track_data.checkpoints.keys()
	ordered.sort_custom(func(a, b):
		var ai := int(str(a).get_slice("_", 1))
		var bi := int(str(b).get_slice("_", 1))
		return ai < bi
	)

	var prog := PackedFloat32Array()
	for k in ordered:
		var idx := int(track_data.checkpoints[k])
		idx = clamp(idx, 0, track_data.center_line.points.size() - 1)
		var p_local: Vector2 = track_data.center_line.points[idx]
		# Convert to world-space position for UI and distance queries
		var p_world := track_data.track.to_global(p_local) if track_data.track else p_local
		checkpoints.append(p_world)

		# Absolute progress (always use local)
		if track_data.has_method("get_segment_length"):
			prog.append(track_data.get_segment_length(0, idx)) # now O(1) via cumulative_length
		elif track_data.has_method("get_point_progress"):
			prog.append(track_data.get_point_progress(track_data.center_line.points[idx]))
		else:
			prog.append(float(idx))  # fallback monotonic

	_checkpoints_progress = prog
	checkpoints_changed.emit()

func get_checkpoints_progress() -> PackedFloat32Array:
	return _checkpoints_progress.duplicate()

func register_car(car: Node) -> void:
	car_state[car] = {
		"index": 0,
		"checkpoints": 0,
		"time_collected": 0.0,
		"last_progress": 0.0,
		"lap": 0,
		"collected_ids": [],
		"seg_index": 0,               # NEW: last known center_line segment index (hint)
	}

func unregister_car(car: Node) -> void:
	car_state.erase(car)

func update_car_progress(car: Node, new_pos: Vector2, t: float) -> void:
	if not _can_progress():
		return
	if not car_state.has(car):
		return
	_pending_latest[car] = { "pos": new_pos, "t": t }

func _process_progress_for(car: Node, new_pos: Vector2, t: float) -> void:
	var st = car_state[car]
	var last := float(st["last_progress"])
	var lap := int(st["lap"])

	# Compute progress in Track local space
	var query_pos := new_pos
	if track_data and track_data.track:
		query_pos = track_data.track.to_local(new_pos)

	# Walk along from last known segment index (very few steps)
	var hint_seg := int(st.get("seg_index", 0))
	if hint_seg == 0 and track_data and track_data.track_length > 0.0:
		hint_seg = track_data.index_from_progress_linear(last)
	var result := track_data.get_point_progress_walk(query_pos, hint_seg, 8)
	var cur = clamp(float(result["progress"]), 0.0, max(0.0, track_length))
	st["seg_index"] = int(result["index"])

	# Wrap and monotonic progress across laps
	if track_length > 0.0 and cur < last and (last - cur) > WRAP_THRESHOLD * track_length:
		lap += 1
		lap_changed.emit(car, lap)
	var mprog = lap * track_length + cur

	# Checkpoint collection (unchanged)
	var idx := int(st["index"])
	var collected: Array = st["collected_ids"]
	var count := _checkpoints_progress.size()
	if count > 0:
		while true:
			var target_prog := lap * track_length + float(_checkpoints_progress[idx])
			if target_prog < mprog - (track_length * 0.5):
				target_prog += track_length
			var target_with_margin = target_prog + max(0.0, award_progress_margin)
			if mprog + EPS >= target_with_margin:
				collected.append(idx)
				st["checkpoints"] = int(st["checkpoints"]) + 1
				st["time_collected"] = t
				checkpoint_collected.emit(car, idx, lap, t)
				idx = (idx + 1) % count
				continue
			break

	# Store updated state
	st["index"] = idx
	st["last_progress"] = cur
	st["lap"] = lap
	st["collected_ids"] = collected
	car_state[car] = st

func get_next_checkpoint_position(car: Node) -> Vector2:
	if not _can_progress() or not car_state.has(car):
		return Vector2.ZERO
	var st = car_state[car]
	var idx := int(st["index"])
	if idx < 0 or idx >= checkpoints.size():
		return Vector2.ZERO
	return checkpoints[idx]

func get_distance_to_next_checkpoint(car: Node) -> float:
	if not car:
		return 0.0
	var pos := (car as Node2D).global_position if car is Node2D else Vector2.ZERO
	var next := get_next_checkpoint_position(car)
	if next == Vector2.ZERO:
		return 0.0
	return pos.distance_to(next)

func _can_progress() -> bool:
	return track_data != null and track_length > 0.0 and _checkpoints_progress.size() > 0

# -------- Static proxy API (backward compatible with previous usage) --------

static func register_car_static(car: Node) -> void:
	if _singleton: _singleton.register_car(car)

static func unregister_car_static(car: Node) -> void:
	if _singleton: _singleton.unregister_car(car)

static func update_car_progress_static(car: Node, _old_pos: Vector2, new_pos: Vector2) -> void:
	# Keep old signature, use current global time if available
	if _singleton:
		var now := (GameManager.global_time if "global_time" in GameManager else 0.0)
		_singleton.update_car_progress(car, new_pos, now)

static func get_next_checkpoint_position_static(car: Node) -> Vector2:
	return _singleton.get_next_checkpoint_position(car) if _singleton else Vector2.ZERO

static func get_distance_to_next_checkpoint_static(car: Node) -> float:
	return _singleton.get_distance_to_next_checkpoint(car) if _singleton else 0.0
