extends Node
class_name HumanControl

@export var accelerate := ["w", "ui_up"]
@export var brake := ["s", "ui_down", "spacebar"]
@export var steer_left := ["a", "left_arrow"]
@export var steer_right := ["d", "right_arrow"]

func getTurn():
	return Input.get_axis(steer_left[1], steer_right[1])
