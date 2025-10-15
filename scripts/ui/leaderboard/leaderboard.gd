extends VBoxContainer
class_name Leaderboard

var entries: Array[LeaderboardEntry] = []
var timer: Timer = Timer.new()

@onready var car_telemetry: CarTelemetry = get_tree().get_first_node_in_group("car_telemetry") as CarTelemetry
@onready var agent_manager: AgentManager = car_telemetry.agent_manager if car_telemetry else null

@export var sort_field: String = "Fitness"
@export var update_interval_s: float = 0.2
# Control whether default columns can be used when no custom columns are provided
@export var load_default_columns: bool = true
# Custom columns you can set in the Inspector (leave empty to use defaults when allowed)
@export var custom_columns: Array[LeaderboardColumn] = []

# Runtime-active columns (resolved from custom_columns or defaults)
var columns: Array[LeaderboardColumn] = []

# Header HBox (first child)
var header_row: HBoxContainer

func _ready() -> void:
	# Connect to generation spawn signal to refresh rows for the new cars
	if agent_manager:
		agent_manager.population_spawned.connect(_on_population_spawned)

	add_child(timer)
	timer.wait_time = update_interval_s
	timer.timeout.connect(_on_timer_timeout)
	timer.start()

	_resolve_columns()
	_build_header()
	_build_rows()

func _resolve_columns() -> void:
	columns.clear()

	if load_default_columns:
		# Requires your LeaderboardColumn to implement make_default_columns()
		columns += LeaderboardColumn.make_default_columns()

	if !custom_columns.is_empty():
		columns += custom_columns.duplicate()
	
	if columns.is_empty():
		push_error("Leaderboard: No columns defined and load_default_columns is false. Please define custom columns or enable default columns.")

func _on_population_spawned() -> void:
	# Re-evaluate schema (in case inspector changed), then rebuild
	_resolve_columns()
	_build_header()
	_build_rows()
	update_leaderboard()

func _on_timer_timeout() -> void:
	update_leaderboard()

# Create a field (cell) from a column definition
func _make_field(col: LeaderboardColumn, is_header: bool) -> LeaderboardField:
	var f := LeaderboardField.new()
	f.field_name = col.title
	f.query_path = "" if is_header else col.query_path
	f.align = col.align
	f.column_weight = col.weight
	f.min_width = col.min_width
	f.decimals = col.decimals
	f.format = col.format
	if is_header:
		f.text = col.title
	return f

func _build_header() -> void:
	if header_row and header_row.is_inside_tree():
		remove_child(header_row)
		header_row.queue_free()
	header_row = HBoxContainer.new()
	header_row.name = "Header"
	add_child(header_row)
	move_child(header_row, 0)

	if columns.is_empty():
		return

	for col in columns:
		header_row.add_child(_make_field(col, true))

func _build_rows() -> void:
	if agent_manager == null or columns.is_empty():
		return
	# Clear any existing entries (preserve header at index 0)
	for e in entries:
		if e.is_inside_tree():
			remove_child(e)
		e.queue_free()
	entries.clear()

	# Create entries for all cars using the same schema
	for car in agent_manager.cars:
		if car == null or car.crashed:
			continue
		var entry := LeaderboardEntry.new()
		entry.set_car(car)

		for col in columns:
			entry.add_field(_make_field(col, false))

		entries.append(entry)
		add_child(entry)     # after header

func update_leaderboard() -> void:
	if columns.is_empty():
		return
	# Update visible values (excluding "#" which is set after sorting)
	for entry in entries:
		entry.update_entry(car_telemetry)

	# Sort entries by selected field
	entries.sort_custom(_compare_entries)

	# Reflect sorted order in UI (skip header at index 0)
	var header_offset := 1
	for i in range(entries.size()):
		if entries[i].get_parent() != self:
			add_child(entries[i])
		move_child(entries[i], i + header_offset)
		# Set placement after sorting
		entries[i].set_rank(i + 1)

func _compare_entries(a: LeaderboardEntry, b: LeaderboardEntry) -> bool:
	var ia = a.find_field_index(sort_field)
	var ib = b.find_field_index(sort_field)
	var va = a.field_as_comparable(ia)
	var vb = b.field_as_comparable(ib)

	# Nulls last
	if va == null and vb == null:
		return false
	if va == null:
		return false
	if vb == null:
		return true

	# Numbers: descending (higher first)
	var na := typeof(va) in [TYPE_FLOAT, TYPE_INT]
	var nb := typeof(vb) in [TYPE_FLOAT, TYPE_INT]
	if na and nb:
		return float(va) > float(vb)

	# Strings: ascending
	return str(va) < str(vb)

func add_entry(entry: LeaderboardEntry) -> void:
	entries.append(entry)
	add_child(entry)

func remove_entry(entry: LeaderboardEntry) -> void:
	if entries.has(entry):
		entries.erase(entry)
		remove_child(entry)
	entry.queue_free()
