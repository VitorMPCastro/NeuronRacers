extends Node2D

class_name GameManager

# signals
signal debug_show_lines_changed
signal debug_show_polygons_changed

static var global_time: float = 0.0
@onready var trackObject: Node2D = self.find_child("Track") as Node2D
@onready var path_node: Path2D = trackObject.find_child("Path2D") as Path2D
@onready var track_manager: Node2D = self.find_child("TrackManager") as Node2D
var track_tex: Texture2D = preload("res://assets/misc/asphalt_1.png")

func _ready() -> void:
	InputManager.set_active_context("Track Mode")

	var tm := track_manager as TrackManager
	if tm == null:
		push_error("TrackManager node not found or not using TrackManager.gd")
		return
	var track := tm.generate_track_from_path(path_node)
	if track:
		print("Generated track length:", track.length)


func _process(delta: float) -> void:
	global_time += delta
