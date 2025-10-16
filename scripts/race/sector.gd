extends Node2D
class_name Sector

var start_index: int
var end_index: int
var sector_length: float = 0.0
var highlight_color: Color = Color(0, 0, 0, 0)

func _init(start_index: int, end_index: int, sector_length: float, highlight_color: Color) -> void:
	self.start_index = start_index
	self.end_index = end_index
	self.sector_length = sector_length
	self.highlight_color = highlight_color
