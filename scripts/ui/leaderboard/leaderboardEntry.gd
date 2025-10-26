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

# Update using DataBroker.get_many (no TelemetryData)
func update_entry(broker: DataBroker) -> void:
	if car == null or broker == null or fields.is_empty():
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

	var values: Array = broker.get_many(car, paths)

	for i in range(fields.size()):
		if field_to_path_idx.has(i):
			var path_idx: int = int(field_to_path_idx[i])
			var value = values[path_idx] if path_idx < values.size() else null
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
