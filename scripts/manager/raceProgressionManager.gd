extends Node
class_name RaceProgressionManager

signal checkpoint_collected(car: Node, checkpoint_index: int, lap: int, t: float)
signal lap_changed(car: Node, lap: int)

@export var track_data_path: NodePath
@onready var track_data: TrackData = get_node_or_null(track_data_path) as TrackData

const WRAP_THRESHOLD := 0.4
const EPS := 0.001

var checkpoints_points: Array[Vector2] = []
var checkpoints_progress: PackedFloat32Array = PackedFloat32Array()
var track_length: float = 0.0

var car_state: Dictionary = {}  # car -> { index, checkpoints, time_collected, last_progress, lap, collected_ids: Array[int] }

func _ready() -> void:
	add_to_group("race_progression")
	_recache()

func _recache() -> void:
	checkpoints_points.clear()
	checkpoints_progress = PackedFloat32Array()
	track_length = 0.0
	if track_data == null or track_data.center_line == null:
		return

	if track_data.checkpoints.is_empty():
		# ensure data prepared (call your generation methods if available)
		if track_data.has_method("calculate_track_length"):
			track_data.calculate_track_length()
		if track_data.has_method("generate_checkpoints"):
			track_data.generate_checkpoints()

	track_length = track_data.track_length
	var ordered := track_data.checkpoints.keys()
	ordered.sort_custom(func(a, b):
		var ai := int(str(a).get_slice("_", 1))
		var bi := int(str(b).get_slice("_", 1))
		return ai < bi
	)
	for k in ordered:
		var idx := int(track_data.checkpoints[k])
		idx = clamp(idx, 0, track_data.center_line.points.size() - 1)
		checkpoints_points.append(track_data.center_line.points[idx])
		if track_data.has_method("get_segment_length"):
			checkpoints_progress.append(track_data.get_segment_length(0, idx))
		else:
			checkpoints_progress.append(float(idx))  # fallback monotonic

func register_car(car: Node) -> void:
	car_state[car] = {
		"index": 0,
		"checkpoints": 0,
		"time_collected": 0.0,
		"last_progress": 0.0,
		"lap": 0,
		"collected_ids": []
	}

func unregister_car(car: Node) -> void:
	car_state.erase(car)

func update_car_progress(car: Node, new_pos: Vector2, t: float) -> void:
	if track_data == null or track_length <= 0.0 or checkpoints_progress.is_empty():
		return
	if not car_state.has(car):
		return

	var st = car_state[car]
	var last := float(st["last_progress"])
	var lap := int(st["lap"])

	var cur := 0.0
	if track_data.has_method("get_point_progress"):
		cur = clamp(track_data.get_point_progress(new_pos), 0.0, track_length)
	else:
		# cheap fallback using nearest point index
		cur = last

	# wrap detection
	if track_length > 0.0 and cur < last and (last - cur) > WRAP_THRESHOLD * track_length:
		lap += 1
		emit_signal("lap_changed", car, lap)

	var mprog := lap * track_length + cur
	var idx := int(st["index"])
	var count := checkpoints_progress.size()
	var collected: Array = st["collected_ids"]

	while count > 0:
		var target := lap * track_length + float(checkpoints_progress[idx])
		if target < mprog - (track_length * 0.5):
			target += track_length
		if mprog + EPS >= target:
			collected.append(idx)
			st["checkpoints"] = int(st["checkpoints"]) + 1
			st["time_collected"] = t
			emit_signal("checkpoint_collected", car, idx, lap, t)
			idx = (idx + 1) % count
			continue
		break

	st["index"] = idx
	st["last_progress"] = cur
	st["lap"] = lap
	st["collected_ids"] = collected
	car_state[car] = st

func get_next_checkpoint_position(car: Node) -> Vector2:
	if not car_state.has(car): return Vector2.ZERO
	var idx := int(car_state[car]["index"])
	if idx < 0 or idx >= checkpoints_points.size(): return Vector2.ZERO
	return checkpoints_points[idx]
