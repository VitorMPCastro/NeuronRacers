extends Node2D
class_name Sector

var start_index: int
var end_index: int
var sector_length: float = 0.0
var highlight_color: Color = Color(0, 0, 0, 0)

func _init(start_idx: int, end_idx: int, sec_length: float, hl_color: Color) -> void:
	self.start_index = start_idx
	self.end_index = end_idx
	self.sector_length = sec_length
	self.highlight_color = hl_color
