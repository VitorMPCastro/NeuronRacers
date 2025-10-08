extends Node2D
class_name TrackManager

@export var sample_step: float = 32.0
@export var use_cubic_sampling: bool = false
@export var treat_as_loop: bool = true
@onready var track: Track = self.get_parent().find_child("Track") as Track

# Thin wrapper that delegates track generation to Track.
func generate_track_from_path(path: Path2D, width: float = 128.0, tex: Texture2D = null) -> Track:
	return track.build_from_path(path, width, tex, sample_step, use_cubic_sampling, treat_as_loop, 1000)
