extends Node2D

class_name GameManager

static var global_time: float = 0.0

func _process(delta: float) -> void:
	global_time += delta
