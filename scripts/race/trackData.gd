extends Node
class_name TrackData

var track = self.get_parent() as Track
var track_length: float = 0.0
var center_line: Line2D = null
var sectors: Dictionary[String, Sector] = {}
var checkpoints: Dictionary[String, int ] = {}
var cumulative_length: PackedFloat32Array = PackedFloat32Array() # O(1) prefix lengths

# NEW: baked segment data for fast projection/walk
var _seg_dir: PackedVector2Array = PackedVector2Array()     # direction per segment (a->b) normalized
var _seg_len: PackedFloat32Array = PackedFloat32Array()     # length per segment
var _seg_ab: PackedVector2Array = PackedVector2Array()      # raw ab = b - a per segment


func get_telemetry_dictionary() -> Dictionary:
	var data := {
		"track_length": track_length,
		"sectors": sectors,
		"sectors_in_track": track.track_sectors,
		"checkpoints": checkpoints,
		"checkpoints_in_track": track.track_checkpoints
	}
	return data

func calculate_track_length() -> float:
	if center_line == null or center_line.points.size() < 2:
		track_length = 0.0
		cumulative_length = PackedFloat32Array()
		return 0.0

	var n := center_line.points.size()
	cumulative_length.resize(n)
	cumulative_length[0] = 0.0

	var length := 0.0
	for i in range(n - 1):
		length += (center_line.points[i + 1] - center_line.points[i]).length()
		cumulative_length[i + 1] = length

	if center_line.closed:
		# Add the closing segment (last -> first)
		length += (center_line.points[0] - center_line.points[n - 1]).length()

	track_length = length
	# After computing track_length and cumulative_length, bake per-segment data.
	_bake_segments()
	return track_length

# NEW: compute per-segment vectors/lengths once
func _bake_segments() -> void:
	_seg_dir = PackedVector2Array()
	_seg_len = PackedFloat32Array()
	_seg_ab = PackedVector2Array()
	if center_line == null:
		return
	var pts := center_line.points
	var n := pts.size()
	if n < 2:
		return
	var seg_count := (n if center_line.closed else n - 1)
	_seg_dir.resize(seg_count)
	_seg_len.resize(seg_count)
	_seg_ab.resize(seg_count)
	for i in range(seg_count):
		var a := pts[i]
		var j := (i + 1) % n
		var b := pts[j]
		var ab := b - a
		var segment_length := ab.length()
		_seg_ab[i] = ab
		_seg_len[i] = segment_length
		_seg_dir[i] = (ab / segment_length) if segment_length > 1e-6 else Vector2.ZERO

func get_segment_length(from_idx: int, to_idx: int) -> float:
	# O(1) using cumulative_length (from start to to_idx)
	if cumulative_length.size() == 0:
		# Fallback to legacy path (kept for safety)
		var length := 0.0
		var i := from_idx
		while i != to_idx:
			var next_i := (i + 1) % center_line.points.size()
			length += (center_line.points[next_i] - center_line.points[i]).length()
			i = next_i
			if not center_line.closed and next_i == 0:
				break
		return length
	return cumulative_length[to_idx]

func index_from_progress_linear(progress: float) -> int:
	# Fast approximation: map progress proportionally to index
	var n := center_line.points.size()
	if n <= 1 or track_length <= 0.0:
		return 0
	var t = clamp(progress / track_length, 0.0, 0.999999)
	return int(t * float(n))

func _closest_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	var ab := b - a
	var ab2 := ab.dot(ab)
	if ab2 <= 1e-9:
		return { "t": 0.0, "point": a, "dist2": p.distance_squared_to(a) }
	var t = clamp((p - a).dot(ab) / ab2, 0.0, 1.0)
	var q = a + ab * t
	return { "t": t, "point": q, "dist2": p.distance_squared_to(q) }

# NEW: project onto a specific segment index (local space)
func _project_on_segment_idx(p_local: Vector2, idx: int) -> Dictionary:
	var n := center_line.points.size()
	var seg_count := (n if center_line.closed else n - 1)
	if seg_count <= 0:
		return {"t": 0.0, "point": p_local, "dist2": 0.0}
	idx = (idx % seg_count + seg_count) % seg_count
	var a := center_line.points[idx]
	var ab := _seg_ab[idx]
	var ab2 := ab.dot(ab)
	if ab2 <= 1e-9:
		return {"t": 0.0, "point": a, "dist2": p_local.distance_squared_to(a)}
	var t = clamp((p_local - a).dot(ab) / ab2, 0.0, 1.0)
	var q = a + ab * t
	return {"t": t, "point": q, "dist2": p_local.distance_squared_to(q)}

# NEW: single-pass walk from previous segment index (typical 0–3 steps)
func get_point_progress_walk(point_local: Vector2, prev_idx: int, max_steps: int = 6) -> Dictionary:
	if center_line == null or center_line.points.size() < 2:
		return {"progress": 0.0, "index": 0}
	var n := center_line.points.size()
	var seg_count := (n if center_line.closed else n - 1)
	if seg_count <= 0:
		return {"progress": 0.0, "index": 0}

	var idx = clamp(prev_idx, 0, seg_count - 1)
	var step := 0
	while true:
		var hit := _project_on_segment_idx(point_local, idx)
		var t := float(hit["t"])
		# In-range: done
		if t > 0.0 and t < 1.0:
			var local_base = cumulative_length[idx] if cumulative_length.size() > 0 else 0.0
			var prog = local_base + t * _seg_len[idx]
			return {"progress": prog, "index": idx}
		# At ends: try walking forward/backward
		if step >= max_steps:
			var base2 = cumulative_length[idx] if cumulative_length.size() > 0 else 0.0
			var t2 = clamp(t, 0.0, 1.0)
			var prog2 = base2 + t2 * _seg_len[idx]
			return {"progress": prog2, "index": idx}
		if t >= 1.0:
			idx = idx + 1
			if idx >= seg_count:
				if center_line.closed: idx = 0
				else: idx = seg_count - 1; break
		elif t <= 0.0:
			idx = idx - 1
			if idx < 0:
				if center_line.closed: idx = seg_count - 1
				else: idx = 0; break
		step += 1

	# Fallback (should rarely hit)
	var base := cumulative_length[idx] if cumulative_length.size() > 0 else 0.0
	return {"progress": base, "index": idx}

# Optional: keep the original API delegating to walk from a coarse hint
func get_point_progress_fast(point_local: Vector2, hint_idx: int, search_radius: int = 16) -> Dictionary:
	# Use the new walker but keep signature compatibility
	return get_point_progress_walk(point_local, hint_idx, min(search_radius, 12))

func get_point_progress(point: Vector2) -> float:
	# Keep API; use fast path with a coarse hint from proportional index
	if center_line == null or center_line.points.size() < 2:
		return 0.0
	var hint := index_from_progress_linear(clamp(progress_as_percentage(point) * track_length, 0.0, track_length))
	return get_point_progress_fast(point, hint)["progress"]

func progress_as_percentage(point: Vector2) -> float:
	if track_length == 0.0:
		return 0.0
	return clamp(get_point_progress(point) / track_length, 0.0, 1.0)

func divide_sectors() -> Dictionary[String, Sector]:
	var colors_to_assign: Array[Color] = [ Color.RED, Color.GREEN, Color.BLUE]

	if center_line == null or center_line.points.size() < 2 or track.track_sectors <= 0:
		return {}
	
	var points_per_sector = center_line.points.size() / track.track_sectors
	
	for i in range(track.track_sectors):
		var start_index = int(i * points_per_sector)
		var end_index = int(((i + 1) * points_per_sector) % center_line.points.size())
		var sector_length = get_segment_length(start_index, end_index)
		var sector_name = "Sector_%d" % (i + 1)
		if i == track.track_sectors - 1:
			end_index = center_line.points.size() - 1
			sector_length = get_segment_length(start_index, end_index)
		sectors[sector_name] = Sector.new(start_index, end_index, sector_length, colors_to_assign[i % colors_to_assign.size()])
		self.add_child(sectors[sector_name])

	return sectors

func generate_checkpoints() -> Dictionary[String, int]:
	if center_line == null or center_line.points.size() < 2 or track.track_checkpoints <= 0:
		return {}
	
	var points_per_checkpoint = center_line.points.size() / track.track_checkpoints
	
	for i in range(track.track_checkpoints):
		var index = int(i * points_per_checkpoint) % center_line.points.size()
		var checkpoint_name = "Checkpoint_%d" % (i + 1)
		checkpoints[checkpoint_name] = index

	return checkpoints
