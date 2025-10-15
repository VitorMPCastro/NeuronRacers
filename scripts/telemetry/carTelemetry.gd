extends Node
class_name CarTelemetry

@export var auto_sample: bool = true
@export var update_interval: float = 0.5
# Set any car properties you want to print. Example starts with driver name.
@export var feature_paths: PackedStringArray = ["car_data.pilot.get_full_name()", "car_data.fitness"]

@onready var agent_manager: AgentManager = get_parent() as AgentManager
@onready var data_broker: DataBroker = (agent_manager.get_parent() as Node).find_child("DataBroker", true, false) as DataBroker

var _acc := 0.0

func _ready() -> void:
	add_to_group("car_telemetry")

func _process(delta: float) -> void:
	if !auto_sample or data_broker == null or agent_manager == null:
		return
	_acc += delta
	if _acc >= update_interval:
		_acc = 0.0


# Build a snapshot and return it as TelemetryData.
# header = exactly 'paths' (queried fields);
# lines = values-only CSV per car (order matches header).
# rows/columns also include car_name for UI convenience.
func sample_once(paths: PackedStringArray = feature_paths) -> TelemetryData:
	var td := TelemetryData.new()

	if agent_manager == null or data_broker == null:
		push_warning("CarTelemetry: missing AgentManager or DataBroker.")
		return td
	if paths.is_empty():
		push_warning("CarTelemetry: feature_paths is empty.")
		return td

	# Header is exactly what was queried
	td.header = paths.duplicate()

	# Full columns = car_name + queried fields (useful for UI tables)
	td.columns = PackedStringArray(["car_name"])
	td.columns.append_array(paths)

	# Aggregate per-car snapshots into a single TelemetryData
	for car in agent_manager.cars:
		if car == null:
			continue
		var per_car := get_values_for_car(car, paths)
		if per_car.rows.size() > 0:
			td.rows.append(per_car.rows[0])
		if per_car.lines.size() > 0:
			td.lines.append(per_car.lines[0])

	return td

func get_values_for_car(provider: Object, paths: PackedStringArray) -> TelemetryData:
	var td := TelemetryData.new()
	if !provider or !paths or !data_broker:
		return td
	
	td.header = paths.duplicate()
	td.columns = PackedStringArray(["car_name"])
	td.columns.append_array(paths)

	var values: Array = []
	for path in paths:
		values.append(data_broker.get_value(provider, path))

	var car_name = (provider as Node).name if provider is Node else str(provider)
	var row: Array = [car_name]
	row.append_array(values)
	td.rows.append(row)

	var parts: Array[String] = []
	for v in values:
		parts.append(str(v))
	td.lines.append(", ".join(parts))
	
	return td