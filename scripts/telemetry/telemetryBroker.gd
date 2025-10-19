extends Node
class_name TelemetryBroker

# Simple key->callable registry; values can be callables or NodePaths
var _providers: Dictionary = {}  # key -> Callable

func _ready() -> void:
	add_to_group("telemetry_broker")

func register_value(key: String, provider: Callable) -> void:
	_providers[key] = provider

func get_value(context: Object, key: String) -> Variant:
	if not _providers.has(key):
		return null
	var c: Callable = _providers[key]
	if c.is_valid():
		return c.call(context)
	return null

# Common keys you can wire from your scene
static func default_keys(broker: TelemetryBroker) -> void:
	broker.register_value("car.speed", func(car: Node):
		return (car.velocity.length() if "velocity" in car else 0.0)
	)
