extends CharacterBody2D
class_name CarData


# STATISTICS AND TELEMETRY
var top_speed: float = 0.0:
	set(value):
		if value > top_speed:
			top_speed = value

var total_distance: float = 0.0
var time_alive: float:
	get: 
		return (GameManager.global_time if timestamp_death == -1.0 else timestamp_death) - timestamp_spawn
var timestamp_spawn: float = 0.0
var timestamp_death: float = -1.0
var fitness: float = 0.0
var collected_checkpoints: Array = []
# GRAPHS
