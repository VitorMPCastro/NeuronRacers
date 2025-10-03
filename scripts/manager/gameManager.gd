extends Node2D

class_name GameManager

static var global_time: float = 0.0
@onready var path_node: Path2D = $Path2D
@onready var manager: Node2D = $TrackManager
var track_tex: Texture2D = preload("res://assets/misc/asphalt_1.png")

func _ready() -> void:
	InputManager.set_active_context("Track Mode")

	var tm := manager as TrackManager
	if tm == null:
		push_error("TrackManager node not found or not using TrackManager.gd")
		return
	var width: float = 220.0
	var track := tm.generate_track_from_path(path_node, width, track_tex)
	if track:
		print("Generated track length:", track.length)

func _process(delta: float) -> void:
	global_time += delta
