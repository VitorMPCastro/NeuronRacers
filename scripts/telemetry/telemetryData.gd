extends Node
class_name TelemetryData

# Snapshot container
var header: PackedStringArray = PackedStringArray()   # queried fields only, e.g.: ["car_data.pilot.get_full_name()", "car_data.fitness"]
var lines: PackedStringArray = PackedStringArray()    # one CSV-style line per row, matching 'header' order

# Optional raw data for further processing/UI
var columns: PackedStringArray = PackedStringArray()  # full columns, e.g.: ["car_name", ...header...]
var rows: Array = []                                  # Array[Array]: [car_name, value1, value2, ...]

func _to_string() -> String:
	var out := ", ".join(header) + "\n"
	for line in lines:
		out += line + "\n"
	return out
