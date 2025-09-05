extends Node2D

class_name GameManager

static var global_time: float = 0.0

func _ready() -> void:
	InputManager.set_active_context("Track Mode")

func _process(delta: float) -> void:
	global_time += delta
