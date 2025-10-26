extends HBoxContainer
class_name LeaderboardEntry

var car: Car = null
var fields: Array[LeaderboardField] = []
var _faded := false

func set_car(c: Car) -> void:
	car = c

func add_field(field: LeaderboardField) -> void:
	fields.append(field)
	add_child(field)

func remove_field(field: LeaderboardField) -> void:
	if fields.has(field):
		fields.erase(field)
		remove_child(field)

func update_entry(broker: DataBroker) -> void:
	if broker == null or fields.is_empty():
		return
	if car == null or !is_instance_valid(car):
		for f in fields:
			if f.query_path != "":
				f.render(null)
		return

	var paths := PackedStringArray()
	var field_to_path_idx := {}
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
			var idx: int = int(field_to_path_idx[i])
			var value = values[idx] if idx < values.size() else null
			fields[i].render(value)

func set_rank(rank: int) -> void:
	var idx := find_field_index("#")
	if idx != -1:
		fields[idx].render(rank)

func find_field_index(field_name: String) -> int:
	for i in range(fields.size()):
		if fields[i].field_name == field_name or fields[i].name == field_name:
			return i
	return -1

func set_crashed_style(crashed: bool, alpha: float = 0.35) -> void:
	# Fade the whole row by modulating only the alpha
	var c := modulate
	var target_a := (alpha if crashed else 1.0)
	if _faded and !crashed and is_equal_approx(c.a, 1.0):
		return
	if (!_faded and crashed and is_equal_approx(c.a, alpha)):
		return
	c.a = target_a
	modulate = c
	_faded = crashed
