extends NodeBase
class_name ValueNode

@export var data_path: String = "total_checkpoints"

func _ready() -> void:
	title = "Value"
	_build_ui()
	add_output_port("Value", true)
	var lbl := Label.new()
	lbl.text = "Data: " + data_path
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_internal_field(lbl)

func evaluate_output(_port_index: int) -> float:
	if data_broker == null or data_provider == null:
		return 0.0
	var v = data_broker.get_value(data_provider, data_path)
	return _sanitize_number(v)

func compile_output_expression(_port_index: int) -> String:
	match data_path:
		"get_sector_time(1)": return "s1"
		"get_sector_time(2)": return "s2"
		"get_sector_time(3)": return "s3"
		"get_sector_time_prev(1)": return "ps1"
		"get_sector_time_prev(2)": return "ps2"
		"get_sector_time_prev(3)": return "ps3"
		"lap_time": return "lap_time"
		"last_lap_time": return "last_lap_time"
		"distance_to_next_checkpoint": return "distance_to_next_checkpoint"
		"total_checkpoints": return "total_checkpoints"
		"speed_kmh": return "speed_kmh"
		"lap": return "lap"
		_:
			var re := RegEx.new()
			re.compile("[^A-Za-z0-9_]")
			var t := re.sub(data_path, "_")
			return t if !t.is_empty() else "x"