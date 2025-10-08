extends Node2D
class_name TrackManager

@export var sample_step: float = 32.0
@export var track_width: float = 128.0
@export var curb_thickness: float = 8.0
@export var use_cubic_sampling: bool = false
@export var treat_as_loop: bool = true
@onready var track: Track = self.get_parent().find_child("Track") as Track

signal debug_show_lines_changed(new_value: bool)

@export var debug_show_lines: bool:
	get: return debug_show_lines
	set(value):
		if debug_show_lines == value:
			return
		debug_show_lines = value
		emit_signal("debug_show_lines_changed", value)
		if is_instance_valid(track):
			track.toggle_show_lines(value)

func _on_track_built() -> void:
	if is_instance_valid(track):
		track.toggle_show_lines(debug_show_lines)

func _ready() -> void:
	debug_show_lines_changed.connect(_on_debug_show_lines_changed)

func _on_debug_show_lines_changed(value: bool) -> void:
	if is_instance_valid(track):
		track.toggle_show_lines(value)

# Thin wrapper that delegates track generation to Track.
func generate_track_from_path(path: Path2D, tex: Texture2D = null) -> Track:
	return track.build_from_path(path, track_width, curb_thickness, tex, sample_step, use_cubic_sampling, treat_as_loop, 1000)
