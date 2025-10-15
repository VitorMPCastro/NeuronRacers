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

func update_entry(telemetry: CarTelemetry) -> void:
	if car == null or telemetry == null or fields.is_empty():
		return
	var paths := PackedStringArray()
	for f in fields:
		paths.append(f.query_path)

	# NEW: use TelemetryData
	var td: TelemetryData = telemetry.get_values_for_car(car, paths)
	if td == null or td.rows.is_empty():
		return

	# Each row: [car_name, value1, value2, ...] in same order as td.header/paths
	var row: Array = td.rows[0]
	for i in range(fields.size()):
		var idx := 1 + i
		var value = row[idx] if idx < row.size() else null
		fields[i].render(value)

func find_field_index(field_name: String) -> int:
	for i in range(fields.size()):
		if fields[i].field_name == field_name or fields[i].name == field_name:
			return i
	return -1

func field_as_comparable(index: int) -> Variant:
	if index < 0 or index >= fields.size():
		return null
	return fields[index].comparable_value()
