extends Node2D

class_name GameManager

static var global_time: float = 0.0
@onready var trackObject: Node2D = self.find_child("Track") as Node2D
@onready var path_node: Path2D = trackObject.find_child("Path2D") as Path2D
@onready var track_manager: Node2D = self.find_child("TrackManager") as Node2D
@onready var race_progression_manager: Node = self.find_child("RaceProgressionManager")
@onready var agent_manager: Node = self.find_child("AgentManager")
var track_tex: Texture2D = preload("res://assets/misc/asphalt_1.png")

func _ready() -> void:
	InputManager.set_active_context("Track Mode")

	var tm := track_manager as TrackManager
	var _rpm := race_progression_manager as RaceProgressionManager
	var _am := agent_manager as AgentManager

	if tm == null:
		push_error("TrackManager node not found or not using TrackManager.gd")
		return

	var _track := tm.generate_track_from_path(path_node)

func _process(delta: float) -> void:
	global_time += delta
