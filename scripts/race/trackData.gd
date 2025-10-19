extends Node
class_name TrackData

var track = self.get_parent() as Track
var track_length: float = 0.0
var center_line: Line2D = null
var sectors: Dictionary[String, Sector] = {}
var checkpoints: Dictionary[String, int ] = {}

func _ready() -> void:
	add_to_group("track_data")

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
	if center_line == null || center_line.points.size() < 2:
		return 0.0
	track_length = get_segment_length(0, center_line.points.size() - 1)
	return track_length

func find_closest_point_on_center_line(point: Vector2) -> Vector2:
	if center_line == null or center_line.points.size() < 2:
		return point
	
	var closest_point := center_line.points[0]
	var closest_distance := (point - closest_point).length()
	
	for i in range(1, center_line.points.size()):
		var current_point := center_line.points[i]
		var current_distance := (point - current_point).length()
		
		if current_distance < closest_distance:
			closest_distance = current_distance
			closest_point = current_point
	
	return closest_point

func index_in_center_line(point: Vector2) -> int:
	if center_line == null or center_line.points.size() < 2:
		return -1
	
	return center_line.points.find(point)

func get_segment_length(start_index: int, end_index: int) -> float:
	if center_line == null or center_line.points.size() < 2:
		return 0.0
	
	if start_index < 0 or end_index < 0 or start_index >= center_line.points.size() or end_index >= center_line.points.size():
		return 0.0
	
	if start_index == end_index:
		return 0.0
	
	var length := 0.0
	var i := start_index
	while i != end_index:
		var next_i := (i + 1) % center_line.points.size()
		length += (center_line.points[next_i] - center_line.points[i]).length()
		i = next_i
		if not center_line.closed and next_i == 0:
			break
	
	return length

func get_point_progress(point: Vector2) -> float:
	if center_line == null or center_line.points.size() < 2:
		return 0.0
	
	var closest_point = find_closest_point_on_center_line(point)
	return get_segment_length(0, index_in_center_line(closest_point))

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
