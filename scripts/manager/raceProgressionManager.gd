extends Node
class_name RaceProgressionManager

signal checkpoints_changed
signal checkpoint_collected(car: Node, checkpoint_index: int, lap: int, t: float)
signal lap_changed(car: Node, lap: int)

# Singleton for static API compatibility
static var _singleton: RaceProgressionManager = null

# Prebaked sector gates (bases in [0, track_length))
var _sector_gates: Array = []  # [{ i:int (1-based), start: float, end: float }]

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
# NEW: we also keep:
#   "samples": Array[{p: float, t: float}]    # recent absolute progress samples (monotonic across laps)
#   "cp_history": Array[{index: int, lap: int, t: float}]  # checkpoint pass log (ordered)
var car_state: Dictionary = {}

# Tunables
const WRAP_THRESHOLD := 0.4  # fraction of track_length to consider wrap-around
const EPS := 0.001

@export var progress_updates_per_frame: int = 64
var _pending_latest: Dictionary = {}   # car -> {pos: Vector2, t: float}

@export_category("Debug")
@export var debug_sector_timing: bool = false
@export var debug_prints_per_frame: int = 4
var _dbg_prints_left: int = 0

func _dbg_print(msg: String) -> void:
	if !debug_sector_timing:
		return
	if _dbg_prints_left <= 0:
		return
	_dbg_prints_left -= 1
	print("[RPM] ", msg)

func _enter_tree() -> void:
	_singleton = self
	add_to_group("race_progression")
	_dbg_prints_left = debug_prints_per_frame
	_dbg_print("enter_tree; singleton bound")

func _exit_tree() -> void:
	if _singleton == self:
		_singleton = null
	_dbg_print("exit_tree; singleton cleared")

func _ready() -> void:
	# keep your existing _bind_track_refs/_rebuild_cache as-is
	if track and track.has_signal("track_built") and not track.track_built.is_connected(_on_track_built):
		track.track_built.connect(_on_track_built)
	_rebuild_cache()
	set_physics_process(true)

func _physics_process(_dt: float) -> void:
	_dbg_prints_left = debug_prints_per_frame
	# Drain up to budget from _pending_latest
	if _pending_latest.is_empty():
		return
	var keys: Array = _pending_latest.keys()
	var max_to_process = min(progress_updates_per_frame, keys.size())
	var processed := 0
	for i in range(max_to_process):
		var car = keys[i]
		if !car_state.has(car):
			_pending_latest.erase(car)
			continue
		var rec: Dictionary = _pending_latest.get(car, {})
		_pending_latest.erase(car)
		if rec.is_empty():
			continue
		var pos: Vector2 = rec.get("pos", Vector2.ZERO)
		var t: float = float(rec.get("t", GameManager.global_time))
		# Process a single car’s progress
		_process_progress_for(car, pos, t)
		processed += 1
	if processed > 0:
		_dbg_print("drained updates: " + str(processed) + " (pending=" + str(_pending_latest.size()) + ")")

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
	_dbg_print("track_built signal")
	_rebuild_cache()

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
	_rebuild_sector_gates()
	_dbg_print("cache rebuilt; track_length=" + str(track_length) + " sectors=" + str(_sector_gates.size()))

func _rebuild_sector_gates() -> void:
	_sector_gates.clear()
	if track_data == null or track_data.center_line == null:
		_dbg_print("no track_data/center_line; gates cleared")
		return
	var last_idx := -1
	var last_pos := Vector2.ZERO
	for i in range(0, checkpoints.size()):
		var cp := checkpoints[i]
		if i > 0:
			var seg_length := last_pos.distance_to(cp)
			if seg_length > 1.0:
				var gate_count := int(floor(seg_length / 1.0))
				var gate_step := seg_length / float(gate_count)
				for g in range(1, gate_count):
					var dist := gate_step * float(g)
					var _p = last_pos.lerp(cp, dist / seg_length)
					_sector_gates.append({ "i": last_idx + 1, "start": dist, "end": dist })
		last_idx += 1
		last_pos = cp

	if debug_sector_timing and _sector_gates.size() > 0:
		var s := []
		for g in _sector_gates:
			s.append("S" + str(g["i"]) + "(start=" + str("%.2f" % float(g["start"])) + ", end=" + str("%.2f" % float(g["end"])) + ")")
		_dbg_print("sector gates: " + ", ".join(s))

func register_car(car: Node) -> void:
	car_state[car] = {
		"index": 0,
		"checkpoints": 0,
		"time_collected": 0.0,
		"last_progress": 0.0,
		"lap": 0,
		"collected_ids": [],
		"seg_index": 0,
		"samples": [],
		"cp_history": [],
		# NEW: per-sector pass cache: { i:int -> { "last_start_t": float, "last_end_t": float, "last_time": float } }
		"sector_pass": {}
	}
	_dbg_print("register_car: " + str(car))

func unregister_car(car: Node) -> void:
	car_state.erase(car)
	_dbg_print("unregister_car: " + str(car))

func update_car_progress(car: Node, pos: Vector2, t: float = -INF) -> void:
	if car == null:
		return
	if t < 0.0:
		t = GameManager.global_time
	_pending_latest[car] = { "pos": pos, "t": t }
	# Debug: first few enqueues per frame
	_dbg_print("enqueue: " + str(car) + " pos=" + str(Vector2i(pos)) + " t=" + str("%.2f" % t))


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

	# Get previous sample (if any)
	var prev_p := -1.0
	var prev_t := -1.0
	var samples: Array = st.get("samples", [])
	if samples.size() > 0:
		prev_p = float(samples.back()["p"])
		prev_t = float(samples.back()["t"])

	# Append current sample first so buffers are consistent
	samples.append({ "p": mprog, "t": t })
	if samples.size() > 64:
		samples.pop_front()
	st["samples"] = samples
	_dbg_print("sample p=" + str("%.2f" % float(mprog)) + " t=" + str("%.2f" % t))


	# Detect sector boundary crossings between previous and current sample, and cache sector times
	if prev_p >= 0.0 and prev_t >= 0.0 and track_length > 0.0 and not _sector_gates.is_empty():
		_update_sector_crossings(st, prev_p, prev_t, mprog, t)

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
				# NEW: log checkpoint history (bounded)
				var hist: Array = st.get("cp_history", [])
				hist.append({ "index": idx, "lap": lap, "t": t })
				if hist.size() > 256:
					hist.pop_front()
				st["cp_history"] = hist
				checkpoint_collected.emit(car, idx, lap, t)
				idx = (idx + 1) % count
				continue
			break

	# Store updated state
	st["index"] = idx
	st["last_progress"] = cur
	st["lap"] = lap
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

static func update_car_progress_static(car: Node, pos: Vector2, t: float = -INF) -> void:
	if _singleton:
		_singleton.update_car_progress(car, pos, t)

static func get_next_checkpoint_position_static(car: Node) -> Vector2:
	return _singleton.get_next_checkpoint_position(car) if _singleton else Vector2.ZERO

static func get_distance_to_next_checkpoint_static(car: Node) -> float:
	return _singleton.get_distance_to_next_checkpoint(car) if _singleton else 0.0

# ---- Data API helpers ----

func get_checkpoint_count(car: Node) -> int:
	if not car_state.has(car): return 0
	return int(car_state[car].get("checkpoints", 0))

func get_last_checkpoint_time(car: Node, cp_index: int) -> float:
	if not car_state.has(car): return -1.0
	var hist: Array = car_state[car].get("cp_history", [])
	for i in range(hist.size() - 1, -1, -1):
		var e = hist[i]
		if int(e["index"]) == cp_index:
			return float(e["t"])
	return -1.0

func get_time_between_indices(car: Node, idx_a: int, idx_b: int) -> float:
	if track_length <= 0.0 or not car_state.has(car) or track_data == null:
		return -1.0
	var st = car_state[car]
	var samples: Array = st.get("samples", [])
	if samples.size() < 2:
		return -1.0
	var base_a := track_data.get_segment_length(0, clampi(idx_a, 0, track_data.center_line.points.size() - 1))
	var base_b := track_data.get_segment_length(0, clampi(idx_b, 0, track_data.center_line.points.size() - 1))
	var last_p := float(samples.back()["p"])
	# Choose latest lap where A has occurred
	var lap_a := int(floor((last_p - base_a) / track_length))
	var target_a := lap_a * track_length + base_a
	var t_a := _interp_crossing_time(samples, target_a)
	if t_a < 0.0:
		# Try previous lap if we haven't crossed A yet within buffer
		lap_a -= 1
		target_a = lap_a * track_length + base_a
		t_a = _interp_crossing_time(samples, target_a)
		if t_a < 0.0:
			return -1.0
	# B must come after A in the same lap; if its base is behind, wrap to next lap
	var target_b := lap_a * track_length + base_b
	if target_b < target_a:
		target_b += track_length
	var t_b := _interp_crossing_time(samples, target_b)
	return (t_b - t_a) if t_b >= 0.0 else -1.0

func get_sector_time(car: Node, sector_index_1based: int) -> float:
	if not car_state.has(car):
		if debug_sector_timing:
			_dbg_print("get_sector_time: car not registered")
		return -1.0
	var st = car_state[car]
	var pass_map: Dictionary = st.get("sector_pass", {})
	if pass_map.has(sector_index_1based):
		var lt := float(pass_map[sector_index_1based].get("last_time", -1.0))
		if lt >= 0.0:
			return lt
		else:
			if debug_sector_timing:
				_dbg_print("get_sector_time: S" + str(sector_index_1based) + " cached=-1, falling back")
	# Fallback (interpolation)
	if track_data == null or track_data.sectors.is_empty():
		return -1.0
	var key := "Sector_%d" % sector_index_1based
	if not track_data.sectors.has(key):
		return -1.0
	var sec: Sector = track_data.sectors[key]
	var v := (get_time_between_indices(car, sec.start_index, sec.end_index))
	if debug_sector_timing and v < 0.0:
		_dbg_print("get_sector_time: S" + str(sector_index_1based) + " fallback=-1 (not enough samples yet)")
	return v

func _interp_crossing_time(samples: Array, target: float) -> float:
	# Samples are ordered by time; find segment that crosses target (prev.p <= target <= cur.p)
	for k in range(1, samples.size()):
		var prev = samples[k - 1]
		var cur = samples[k]
		var p0 := float(prev["p"])
		var p1 := float(cur["p"])
		if p0 <= target and p1 >= target and p1 > p0:
			var t0 := float(prev["t"])
			var t1 := float(cur["t"])
			var u := (target - p0) / (p1 - p0)
			return t0 + u * (t1 - t0)
	return -1.0

# ---- Static proxies for DataBroker/UI ----
static func get_checkpoint_count_static(car: Node) -> int:
	return _singleton.get_checkpoint_count(car) if _singleton else 0

static func get_last_checkpoint_time_static(car: Node, cp_index: int) -> float:
	return _singleton.get_last_checkpoint_time(car, cp_index) if _singleton else -1.0

static func get_time_between_indices_static(car: Node, idx_a: int, idx_b: int) -> float:
	return _singleton.get_time_between_indices(car, idx_a, idx_b) if _singleton else -1.0

static func get_sector_time_static(car: Node, sector_index_1based: int) -> float:
	return _singleton.get_sector_time(car, sector_index_1based) if _singleton else -1.0

# NEW: detect sector gate crossings and cache last sector time
func _update_sector_crossings(st: Dictionary, p0: float, t0: float, p1: float, t1: float) -> void:
	if p1 <= p0:
		return
	var L := track_length
	var pass_map: Dictionary = st.get("sector_pass", {})
	for g in _sector_gates:
		var idx := int(g["i"])
		var s_base := float(g["start"])
		var e_base := float(g["end"])
		var t_s := _gate_crossing_time(p0, t0, p1, t1, s_base, L)
		var t_e := _gate_crossing_time(p0, t0, p1, t1, e_base, L)
		if !pass_map.has(idx):
			pass_map[idx] = { "last_start_t": -1.0, "last_end_t": -1.0, "last_time": -1.0 }
		var rec: Dictionary = pass_map[idx]
		var before_time := float(rec.get("last_time", -1.0))

		if t_s >= 0.0:
			rec["last_start_t"] = t_s
			_dbg_print("S" + str(idx) + " start@" + str("%.2f" % t_s))
		if t_e >= 0.0:
			rec["last_end_t"] = t_e
			if float(rec.get("last_start_t", -1.0)) >= 0.0 and float(rec["last_end_t"]) >= float(rec["last_start_t"]):
				rec["last_time"] = float(rec["last_end_t"]) - float(rec["last_start_t"])
				if debug_sector_timing and rec["last_time"] != before_time:
					_dbg_print("S" + str(idx) + " time=" + str("%.3f" % float(rec["last_time"])) + "s")
		pass_map[idx] = rec
	st["sector_pass"] = pass_map

# Compute first crossing time of a gate 'base' (in [0,L)) between p0 and p1 (absolute monotonic progress)
func _gate_crossing_time(p0: float, t0: float, p1: float, t1: float, base: float, L: float) -> float:
	if p1 <= p0 or L <= 0.0:
		return -1.0
	# Find the smallest k such that gate = base + k*L lies in [p0, p1]
	var k := int(ceil((p0 - base) / L))
	var gate := base + float(k) * L
	if gate < p0 - 1e-6 or gate > p1 + 1e-6:
		return -1.0
	var u := (gate - p0) / (p1 - p0)
	return t0 + u * (t1 - t0)
