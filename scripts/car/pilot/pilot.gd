extends Node
class_name Pilot

var pilot_first_name: String
var pilot_last_name: String
var pilot_number: int
var brain: MLP

# AI tick gating
var _decision_ready: bool = true

func _init(first_name: String = "Unknown", last_name: String = "Racer", number: int = 0) -> void:
	pilot_first_name = first_name
	pilot_last_name = last_name
	pilot_number = number

func get_full_name() -> String:
	return "%s %s" % [pilot_first_name, pilot_last_name]

# Called by AgentManager.ai_tick
func notify_ai_tick() -> void:
	_decision_ready = true

func can_decide(actions_per_second: float) -> bool:
	return actions_per_second <= 0.0 or _decision_ready

func decide(sensors: Array) -> Dictionary:
	# Returns {"steer": -1..1, "throttle": -1..1}
	if brain == null or sensors.is_empty():
		return {"steer": 0.0, "throttle": 0.0}
	var outputs := brain.forward(sensors)
	var steer = clamp(float(outputs[0]), -1.0, 1.0)
	var throttle = clamp(float(outputs[1]), -1.0, 1.0)
	return {"steer": steer, "throttle": throttle}

func consume_decision(actions_per_second: float) -> void:
	if actions_per_second > 0.0:
		_decision_ready = false
