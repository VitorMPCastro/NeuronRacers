extends Node
class_name RaceProgressionManager

signal checkpoints_changed
signal checkpoint_collected(car: Node, checkpoint_index: int, lap: int, t: float)
signal lap_changed(car: Node, lap: int)

# Singleton for static API compatibility
static var _singleton: RaceProgressionManager = null

# Prebaked sector gates (bases in [0, track_length))
var _sector_gates: Array = []  # [{ i:int (1-based), start: float, end: float }]
var _lap_start_sector_index: int = -1      # NEW: sector whose start is the lap line
const BASE_EPS := 1e-4

@export var track_path: NodePath
@export var track_data_path: NodePath

# Require the car to surpass this extra progress (in px) past the checkpoint to award it.
# Prevents instant CP_0 at spawn jitter and helps with sensor noise.
@export var award_progress_margin: float = 5.0
# NEW: checkpoint awarding arming (prevents burst at generation start)
@export var cp_arm_time: float = 0.05       # seconds after registration before awarding can start
@export var cp_arm_distance: float = 8.0    # px of movement after registration before awarding can start

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

var _cp_gate_pos: PackedVector2Array = []
var _cp_gate_dir: PackedVector2Array = []   # normalized tangent (forward direction)
# NEW: keep which center_line index each CP corresponds to
var _cp_point_index: PackedInt32Array = []

var _sec_start_pos: PackedVector2Array = [] # index = sector_i (1-based) -> pos
var _sec_start_dir: PackedVector2Array = []
var _sec_end_pos: PackedVector2Array = []
var _sec_end_dir: PackedVector2Array = []

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
	_bind_track_refs()  # ensure bound before cache/rebuild
	if track and track.has_signal("track_built") and not track.track_built.is_connected(_on_track_built):
		track.track_built.connect(_on_track_built)
	_rebuild_cache()
	set_physics_process(true)

func _physics_process(_dt: float) -> void:
	_dbg_prints_left = debug_prints_per_frame
	# Ensure refs are bound; bail early if not
	if track_data == null or track == null:
		_bind_track_refs()
		if track_data == null or track == null:
			_dbg_print("skipping tick: track/track_data not bound yet")
			return
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
	if debug_sector_timing:
		_dbg_print("bind refs: track=" + str(track) + " track_data=" + str(track_data))

func _on_track_built() -> void:
	_dbg_print("track_built signal")
	_rebuild_cache()

func _rebuild_cache() -> void:
	checkpoints.clear()
	_checkpoints_progress = PackedFloat32Array()
	track_length = 0.0

	if track_data == null or track == null:
		_dbg_print("rebuild skipped: missing track/track_data")
		return
	if track_data.center_line == null or track_data.center_line.points.size() < 2:
		return

	# Prepare TrackData
	if track_data.has_method("calculate_track_length"):
		track_data.calculate_track_length()
	if track_data.has_method("divide_sectors"):
		track_data.divide_sectors()
	if track_data.has_method("generate_checkpoints"):
		track_data.generate_checkpoints()

	track_length = track_data.track_length

	# Order checkpoint keys by numeric suffix
	var ordered: Array = track_data.checkpoints.keys()
	ordered.sort_custom(func(a, b):
		var ai := int(str(a).get_slice("_", 1))
		var bi := int(str(b).get_slice("_", 1))
		return ai < bi
	)

	var prog := PackedFloat32Array()
	var cp_point_indices := PackedInt32Array()  # NEW
	for k in ordered:
		var idx := int(track_data.checkpoints[k])
		idx = clamp(idx, 0, track_data.center_line.points.size() - 1)
		var p_local: Vector2 = track_data.center_line.points[idx]
		# World-space for debug/distance queries: use Track node transform
		var p_world := track.to_global(p_local)
		checkpoints.append(p_world)
		cp_point_indices.append(idx)  # NEW

		var base := 0.0
		if track_data.has_method("get_segment_length"):
			base = track_data.get_segment_length(0, idx)
		else:
			base = float(idx)
		prog.append(_norm_base(base))   # NORMALIZE HERE
	_checkpoints_progress = prog
	_cp_point_index = cp_point_indices  # NEW
	checkpoints_changed.emit()
	_rebuild_sector_gates()
	_build_checkpoint_gates()      # NEW
	_build_sector_gate_geom()      # NEW
	_dbg_print("cache rebuilt; track_length=" + str(track_length) + " sectors=" + str(_sector_gates.size()))

	# Re-sync cars: seed next cp from their current world position (gate-based)
	for car in car_state.keys():
		var st: Dictionary = car_state[car]
		if st == null: continue
		var pos_world := (car as Node2D).global_position if car is Node2D else Vector2.ZERO
		st["prev_pos_world"] = pos_world
		st["index"] = _seed_cp_index_from_pos(pos_world)
		# NEW: re-arm awarding after cache rebuild
		st["cp_armed"] = false
		st["cp_arm_t0"] = GameManager.global_time
		car_state[car] = st

func _build_checkpoint_gates() -> void:
	_cp_gate_pos.clear()
	_cp_gate_dir.clear()
	if checkpoints.is_empty():
		return
	var n := checkpoints.size()
	_cp_gate_pos.resize(n)
	_cp_gate_dir.resize(n)
	for i in range(n):
		var p_world := checkpoints[i]
		var cl_idx = _cp_point_index[i] if (i < _cp_point_index.size()) else -1
		var tangent := Vector2.RIGHT
		if cl_idx >= 0 and track_data != null and track != null:
			var count := track_data.center_line.points.size()
			if count >= 2:
				var i_prev = (cl_idx - 1 + count) % count
				var i_next = (cl_idx + 1) % count
				var p_prev_w := track.to_global(track_data.center_line.points[i_prev])
				var p_next_w := track.to_global(track_data.center_line.points[i_next])
				tangent = (p_next_w - p_prev_w)
				if tangent.length_squared() < 1e-6:
					tangent = Vector2.RIGHT
		_cp_gate_pos[i] = p_world
		_cp_gate_dir[i] = tangent.normalized()

func _build_sector_gate_geom() -> void:
	_sec_start_pos.clear()
	_sec_start_dir.clear()
	_sec_end_pos.clear()
	_sec_end_dir.clear()

	if track_data == null or track_data.sectors.is_empty():
		return
	var keys := track_data.sectors.keys()
	keys.sort_custom(func(a, b):
		var ai := int(str(a).get_slice("_", 1))
		var bi := int(str(b).get_slice("_", 1))
		return ai < bi
	)

	var count := keys.size()
	_sec_start_pos.resize(count + 1) # 1-based
	_sec_start_dir.resize(count + 1)
	_sec_end_pos.resize(count + 1)
	_sec_end_dir.resize(count + 1)

	for j in range(count):
		var sector_gate_name = keys[j]
		var i1 := int(str(sector_gate_name).get_slice("_", 1))
		var sec: Sector = track_data.sectors[sector_gate_name]

		var i_prev := (sec.start_index - 1 + track_data.center_line.points.size()) % track_data.center_line.points.size()
		var i_next := (sec.start_index + 1) % track_data.center_line.points.size()
		var p_prev_w := track.to_global(track_data.center_line.points[i_prev])
		var p_cur_w := track.to_global(track_data.center_line.points[sec.start_index])
		var p_next_w := track.to_global(track_data.center_line.points[i_next])
		var tan_s := (p_next_w - p_prev_w)
		if tan_s.length_squared() < 1e-6:
			tan_s = Vector2.RIGHT

		i_prev = (sec.end_index - 1 + track_data.center_line.points.size()) % track_data.center_line.points.size()
		i_next = (sec.end_index + 1) % track_data.center_line.points.size()
		var p_prev2_w := track.to_global(track_data.center_line.points[i_prev])
		var p_end_w := track.to_global(track_data.center_line.points[sec.end_index])
		var p_next2_w := track.to_global(track_data.center_line.points[i_next])
		var tan_e := (p_next2_w - p_prev2_w)
		if tan_e.length_squared() < 1e-6:
			tan_e = Vector2.RIGHT

		_sec_start_pos[i1] = p_cur_w
		_sec_start_dir[i1] = tan_s.normalized()
		_sec_end_pos[i1] = p_end_w
		_sec_end_dir[i1] = tan_e.normalized()

# Build sector gate bases (absolute progress) for interpolation-based timing
func _rebuild_sector_gates() -> void:
	_sector_gates.clear()
	_lap_start_sector_index = -1
	if track_data == null or track_data.sectors.is_empty():
		return

	var keys := track_data.sectors.keys()
	keys.sort_custom(func(a, b):
		var ai := int(str(a).get_slice("_", 1))
		var bi := int(str(b).get_slice("_", 1))
		return ai < bi
	)

	var min_base := INF
	var min_idx := -1
	for j in range(keys.size()):
		var sector_gate_name = keys[j]
		var i1 := int(str(sector_gate_name).get_slice("_", 1))
		var sec: Sector = track_data.sectors[sector_gate_name]

		var s_base := 0.0
		var e_base := 0.0
		if track_data.has_method("get_segment_length"):
			s_base = track_data.get_segment_length(0, clampi(sec.start_index, 0, track_data.center_line.points.size() - 1))
			e_base = track_data.get_segment_length(0, clampi(sec.end_index, 0, track_data.center_line.points.size() - 1))
		else:
			s_base = float(sec.start_index)
			e_base = float(sec.end_index)

		s_base = _norm_base(s_base)
		e_base = _norm_base(e_base)

		_sector_gates.append({ "i": i1, "start": s_base, "end": e_base })
		if s_base < min_base:
			min_base = s_base
			min_idx = i1

	_lap_start_sector_index = min_idx

# Detect sector start/end gate crossings using world positions between p0->p1 and cache last sector time
func _update_sector_crossings_pos(st: Dictionary, p0: Vector2, p1: Vector2, t0: float, t1: float) -> void:
	if p0 == p1:
		return
	if _sec_start_pos.size() == 0 or _sec_end_pos.size() == 0:
		return

	var pass_map: Dictionary = st.get("sector_pass", {})
	var count = max(_sec_start_pos.size(), _sec_end_pos.size()) - 1 # arrays are 1-based sized

	for i in range(1, count + 1):
		var gpos_s := _sec_start_pos[i]
		var gdir_s := _sec_start_dir[i]
		var s0 := gdir_s.dot(p0 - gpos_s)
		var s1 := gdir_s.dot(p1 - gpos_s)
		var t_s := -1.0
		if s0 < 0.0 and s1 >= 0.0 and s1 > s0:
			var u_s = clamp(-s0 / (s1 - s0), 0.0, 1.0)
			t_s = lerp(t0, t1, u_s)

		var gpos_e := _sec_end_pos[i]
		var gdir_e := _sec_end_dir[i]
		var e0 := gdir_e.dot(p0 - gpos_e)
		var e1 := gdir_e.dot(p1 - gpos_e)
		var t_e := -1.0
		if e0 < 0.0 and e1 >= 0.0 and e1 > e0:
			var u_e = clamp(-e0 / (e1 - e0), 0.0, 1.0)
			t_e = lerp(t0, t1, u_e)

		if !pass_map.has(i):
			pass_map[i] = { "last_start_t": -1.0, "last_end_t": -1.0, "last_time": -1.0 }
		var rec: Dictionary = pass_map[i]
		var before_time := float(rec.get("last_time", -1.0))

		if t_s >= 0.0:
			rec["last_start_t"] = t_s
			_dbg_print("S" + str(i) + " start@" + str("%.2f" % t_s))
		if t_e >= 0.0:
			rec["last_end_t"] = t_e
		if float(rec.get("last_start_t", -1.0)) >= 0.0 and float(rec.get("last_end_t", -1.0)) >= float(rec.get("last_start_t", -1.0)):
			rec["last_time"] = float(rec["last_end_t"]) - float(rec["last_start_t"])
			if debug_sector_timing and rec["last_time"] != before_time:
				_dbg_print("S" + str(i) + " time=" + str("%.3f" % float(rec["last_time"])) + "s")
		pass_map[i] = rec

	st["sector_pass"] = pass_map

func register_car(car: Node) -> void:
	# Idempotent registration
	if car_state.has(car):
		var st: Dictionary = car_state[car]
		var pos_world := (car as Node2D).global_position if car is Node2D else Vector2.ZERO
		st["prev_pos_world"] = pos_world
		st["prev_time"] = GameManager.global_time  # seed time
		if _cp_gate_pos.size() > 0:
			st["index"] = _seed_cp_index_from_pos(pos_world)
		# Prime S1 start if needed (first lap)
		_prime_first_sector_start_if_needed(st, pos_world, st["prev_time"])
		# NEW: disarm awarding until next tick (prevents initial burst)
		st["cp_armed"] = false
		st["cp_arm_t0"] = st["prev_time"]
		car_state[car] = st
		_dbg_print("register_car (refresh): " + str(car))
		return

	# Fresh state
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
		"sector_pass": {},
		"prev_pos_world": (car as Node2D).global_position if car is Node2D else Vector2.ZERO,
		"prev_time": GameManager.global_time,
		# NEW: disarm awarding until after first tick
		"cp_armed": false,
		"cp_arm_t0": GameManager.global_time
	}
	if _cp_gate_pos.size() > 0 and car is Node2D:
		var pos_world := (car as Node2D).global_position
		car_state[car]["index"] = _seed_cp_index_from_pos(pos_world)
		# Prime S1 start if needed (first lap)
		var st2: Dictionary = car_state[car]
		_prime_first_sector_start_if_needed(st2, pos_world, st2["prev_time"])
		car_state[car] = st2
	_dbg_print("register_car: " + str(car))

func _seed_cp_index_from_pos(pos_world: Vector2) -> int:
	var n := _cp_gate_pos.size()
	if n == 0: return 0
	# Pick the first gate where dot(dir, pos - gate_pos) < 0 (i.e., car is "behind" the gate)
	for i in range(n):
		var s := (_cp_gate_dir[i].dot(pos_world - _cp_gate_pos[i]))
		if s < 0.0:
			return i
	# If car is ahead of all gates (very near finish), next is 0
	return 0

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


# Prime Sector 1 start on lap 0 if the car is already on the front side of its start gate
func _prime_first_sector_start_if_needed(st: Dictionary, pos_world: Vector2, t: float) -> void:
	if _lap_start_sector_index == -1:
		return
	# Need prebuilt sector gate geometry
	if _sec_start_pos.size() == 0 or _sec_start_dir.size() == 0:
		return
	var pass_map: Dictionary = st.get("sector_pass", {})
	if !pass_map.has(_lap_start_sector_index):
		pass_map[_lap_start_sector_index] = {"last_start_t": -1.0, "last_end_t": -1.0, "last_time": -1.0}
	var rec: Dictionary = pass_map[_lap_start_sector_index]
	# Only prime if not set and we are on/after the start gate plane
	if float(rec.get("last_start_t", -1.0)) < 0.0:
		var gpos := _sec_start_pos[_lap_start_sector_index]
		var gdir := _sec_start_dir[_lap_start_sector_index]
		if gdir != Vector2.ZERO:
			var s := gdir.dot(pos_world - gpos)
			if s >= 0.0:
				rec["last_start_t"] = t
				pass_map[_lap_start_sector_index] = rec
				st["sector_pass"] = pass_map
				if debug_sector_timing:
					_dbg_print("prime S" + str(_lap_start_sector_index) + " start@" + str("%.2f" % t))

func _process_progress_for(car: Node, new_pos: Vector2, t: float) -> void:
	if track == null or _cp_gate_pos.size() == 0 or !car_state.has(car):
		return
	var st: Dictionary = car_state[car]
	var prev_pos: Vector2 = st.get("prev_pos_world", new_pos)
	var prev_t: float = st.get("prev_time", t)

	# Prime S1 start on first tick if needed (covers lap 0)
	_prime_first_sector_start_if_needed(st, prev_pos, prev_t)

	# Skip if no actual motion
	if prev_pos == new_pos:
		st["prev_pos_world"] = new_pos
		st["prev_time"] = t
		car_state[car] = st
		return

	# 1) Sector crossings using world positions
	_update_sector_crossings_pos(st, prev_pos, new_pos, prev_t, t)

	# NEW: arm awarding only after the first post-spawn tick
	var armed := bool(st.get("cp_armed", false))
	var just_armed := false
	if !armed:
		var moved := prev_pos.distance_to(new_pos)
		var dt = max(0.0, t - float(st.get("cp_arm_t0", prev_t)))
		if moved >= cp_arm_distance or dt >= cp_arm_time:
			armed = true
			just_armed = true
			st["cp_armed"] = true

	# 2) Checkpoint by oriented gate crossing (only if armed and not just armed this tick)
	if armed and !just_armed:
		var p0 := prev_pos
		var p1 := new_pos
		var t0 := prev_t
		var t1 := t
		var n := _cp_gate_pos.size()
		var idx := wrapi(int(st.get("index", 0)), 0, n)
		var safety := 0
		while safety < n:
			var gpos := _cp_gate_pos[idx]
			var gdir := _cp_gate_dir[idx]  # forward tangent
			var s0 := gdir.dot(p0 - gpos)
			var s1 := gdir.dot(p1 - gpos)
			# Forward crossing: from back side (s<0) to front side (s>=0)
			if s0 < 0.0 and s1 >= 0.0 and s1 > s0:
				var u = clamp(-s0 / (s1 - s0), 0.0, 1.0)
				var t_cross = lerp(t0, t1, u)

				# award once
				var lap_before := int(st.get("lap", 0))
				var hist: Array = st.get("cp_history", [])
				hist.append({ "index": idx, "lap": lap_before, "t": t_cross })
				if hist.size() > 256: hist.pop_front()
				st["cp_history"] = hist
				st["checkpoints"] = int(st.get("checkpoints", 0)) + 1
				st["time_collected"] = t_cross
				checkpoint_collected.emit(car, idx, lap_before, t_cross)

				# next gate
				var was_last := (idx == n - 1)
				idx = (idx + 1) % n
				st["index"] = idx

				# Lap++ when wrapping to 0; stamp sector-1 start time here
				if was_last:
					var new_lap := lap_before + 1
					st["lap"] = new_lap
					if _lap_start_sector_index != -1:
						var pass_map: Dictionary = st.get("sector_pass", {})
						if !pass_map.has(_lap_start_sector_index):
							pass_map[_lap_start_sector_index] = {"last_start_t": -1.0, "last_end_t": -1.0, "last_time": -1.0}
						var rec: Dictionary = pass_map[_lap_start_sector_index]
						rec["last_start_t"] = t_cross
						pass_map[_lap_start_sector_index] = rec
						st["sector_pass"] = pass_map
					lap_changed.emit(car, new_lap)

				# Continue in case multiple gates were crossed this frame
				safety += 1
				p0 = p0.lerp(p1, u)
				t0 = t_cross
				continue
			break

	# 3) store prev for next frame
	st["prev_pos_world"] = new_pos
	st["prev_time"] = t
	car_state[car] = st

# Award next checkpoints whose gates fall within [p0, p1]
func _award_checkpoints_between(car: Node, st: Dictionary, p0: float, p1: float, t: float) -> void:
	if p1 <= p0:
		return
	var n := _checkpoints_progress.size()
	if n == 0:
		return

	var idx := int(st.get("index", 0))
	if idx < 0 or idx >= n:
		idx = _find_next_cp_index(float(st.get("last_progress", 0.0)))

	var last_aw_idx := int(st.get("last_awarded_idx", -1))
	var last_aw_k := int(st.get("last_awarded_gate_k", -1))

	var safety := 0
	while safety < n:
		var base := float(_checkpoints_progress[idx])  # in [0, L)
		# first occurrence of this CP gate strictly after p0
		var k := int(floor((p0 - base) / track_length)) + 1
		var gate := base + float(k) * track_length

		# Do not push the lap-line CP past wrap with margin
		var eff_margin := award_progress_margin
		if (track_length - base) <= (award_progress_margin + BASE_EPS):
			eff_margin = 0.0

		# If we already awarded this exact CP at this absolute gate, skip (idempotent)
		if idx == last_aw_idx and k == last_aw_k:
			idx = (idx + 1) % n
			safety += 1
			continue

		if gate <= p1 + eff_margin + EPS:
			# award (idempotent by (idx,k) pair)
			var hist: Array = st.get("cp_history", [])
			var lap_at_gate := int(floor(gate / track_length))
			hist.append({ "index": idx, "lap": lap_at_gate, "t": t })
			if hist.size() > 256:
				hist.pop_front()
			st["cp_history"] = hist
			st["checkpoints"] = int(st.get("checkpoints", 0)) + 1
			st["time_collected"] = t

			# FIX: emit the car node, not the state dictionary
			checkpoint_collected.emit(car, idx, lap_at_gate, t)

			# Update duplicate guard and advance
			last_aw_idx = idx
			last_aw_k = k
			idx = (idx + 1) % n
			safety += 1
			continue
		break

	st["index"] = idx
	st["last_awarded_idx"] = last_aw_idx
	st["last_awarded_gate_k"] = last_aw_k

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

func _norm_base(v: float) -> float:
	if track_length <= 0.0:
		return v
	if v >= track_length:
		return max(0.0, track_length - BASE_EPS)
	if v < 0.0:
		return 0.0
	return v

func get_checkpoints_progress() -> PackedFloat32Array:
	return _checkpoints_progress

# Find the first checkpoint strictly ahead of the given base progress (0..track_length)
func _find_next_cp_index(cur_base: float) -> int:
	var n := _checkpoints_progress.size()
	if n == 0:
		return 0
	var target = cur_base + max(0.0, award_progress_margin)
	var lo := 0
	var hi := n
	while lo < hi:
		var mid := (lo + hi) >> 1
		if float(_checkpoints_progress[mid]) <= target:
			lo = mid + 1
		else:
			hi = mid
	return lo % n
