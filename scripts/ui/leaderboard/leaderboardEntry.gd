extends HBoxContainer
class_name LeaderboardEntry

var car: Car = null
var fields: Array[LeaderboardField] = []

func set_car(c: Car) -> void:
	car = c

func add_field(field: LeaderboardField) -> void:
	fields.append(field)
	add_child(field)

func remove_field(field: LeaderboardField) -> void:
	if fields.has(field):
		fields.erase(field)
		remove_child(field)

# Query only fields that have a non-empty query_path.
# Fields with empty query_path (e.g., "#") are set separately (see set_rank).
func update_entry(telemetry: CarTelemetry) -> void:
	if car == null or telemetry == null or fields.is_empty():
		return

	var paths := PackedStringArray()
	var field_to_path_idx := {} # field_index -> path_index
	var p := 0
	for i in range(fields.size()):
		var qp := fields[i].query_path.strip_edges()
		if qp != "":
			field_to_path_idx[i] = p
			paths.append(qp)
			p += 1

	if paths.is_empty():
		return

	var td: TelemetryData = telemetry.get_values_for_car(car, paths)
	if td == null or td.rows.is_empty():
		return

	var row: Array = td.rows[0]  # [car_name, v1, v2, ...]
	for i in range(fields.size()):
		if field_to_path_idx.has(i):
			var path_idx: int = int(field_to_path_idx[i])
			var value_idx := 1 + path_idx
			var value = row[value_idx] if value_idx < row.size() else null
			fields[i].render(value)
		# else: leave fields like "#" to be set via set_rank()

func set_rank(rank: int) -> void:
	var idx := find_field_index("#")
	if idx != -1:
		fields[idx].render(rank)

func find_field_index(field_name: String) -> int:
	for i in range(fields.size()):
		if fields[i].field_name == field_name or fields[i].name == field_name:
			return i
	return -1

func field_as_comparable(index: int) -> Variant:
	if index < 0 or index >= fields.size():
		return null
	return fields[index].comparable_value()
