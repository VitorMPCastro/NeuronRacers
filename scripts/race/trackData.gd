extends Node
class_name TrackData

var track_length: float = 0.0
var center_line: Line2D = null

func _ready() -> void:
	self.get_parent()

func get_telemetry_dictionary() -> Dictionary:
	var data := {
		"track_length": track_length,
	}
	return data