extends Node
class_name Pilot

var pilot_first_name: String
var pilot_last_name: String
var pilot_number: int
var brain: MLP

func _init(first_name: String = "Unknown", last_name: String = "Racer", number: int = 0) -> void:
	pilot_first_name = first_name
	pilot_last_name = last_name
	pilot_number = number

func get_full_name() -> String:
	return "%s %s" % [pilot_first_name, pilot_last_name]
