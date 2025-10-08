extends Node2D

class_name GameManager

static var global_time: float = 0.0
@onready var trackObject: Node2D = self.find_child("Track") as Node2D
@onready var path_node: Path2D = trackObject.find_child("Path2D") as Path2D
@onready var track_manager: Node2D = self.find_child("TrackManager") as Node2D
@export var debug_show_track_lines: bool = false
@export var debug_show_polygons: bool = false
var track_tex: Texture2D = preload("res://assets/misc/asphalt_1.png")

func _ready() -> void:
	InputManager.set_active_context("Track Mode")

	var tm := track_manager as TrackManager
	if tm == null:
		push_error("TrackManager node not found or not using TrackManager.gd")
		return
	var width: float = 50.0
	var track := tm.generate_track_from_path(path_node, width)
	if track:
		print("Generated track length:", track.length)
		print("Track polygon:", track.polygon_node)
		track.polygon_node.color = Color(1, 1, 1, 1)
		var center_line = track.draw_centerline(self.path_node, 4.0, Color(1, 0, 0, 1), 6.0, true)
		var right_track = track.draw_offset_from_line(center_line, 20.0, 2.0, Color(0, 1, 0, 1))
		var left_track = track.draw_offset_from_line(center_line, -20.0, 2.0, Color(0, 0, 1, 1))
		var quads = track.draw_quads_between_lines(left_track, right_track, track_tex)
		print("Created", quads.size(), "quads between left/right lines")

		for quad in quads:
			quad.z_index = center_line.z_index - 1


func _process(delta: float) -> void:
	global_time += delta
