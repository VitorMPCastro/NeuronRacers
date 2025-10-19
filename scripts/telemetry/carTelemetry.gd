extends Node
class_name CarTelemetry

@export var auto_sample: bool = true
@export var update_interval: float = 0.5

@onready var _broker: TelemetryBroker = get_tree().get_first_node_in_group("telemetry_broker") as TelemetryBroker

func _ready() -> void:
	add_to_group("car_telemetry")
	if _broker:
		TelemetryBroker.default_keys(_broker)

func get_value(context: Object, key: String) -> Variant:
	return _broker.get_value(context, key) if _broker else null