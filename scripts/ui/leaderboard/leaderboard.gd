extends VBoxContainer
class_name Leaderboard

var entries: Array[LeaderboardEntry] = []
var timer: Timer = Timer.new()

@onready var car_telemetry: CarTelemetry = get_tree().get_first_node_in_group("car_telemetry") as CarTelemetry
@onready var agent_manager: AgentManager = car_telemetry.agent_manager if car_telemetry else null

@export var sort_field: String = "Fitness"
@export var update_interval_s: float = 0.2

# Header HBox (first child)
var header_row: HBoxContainer

func _ready() -> void:
	# Connect to generation spawn signal to refresh rows for the new cars
	if agent_manager:
		# Godot 4 style connection
		agent_manager.population_spawned.connect(_on_population_spawned)

	add_child(timer)
	timer.wait_time = update_interval_s
	timer.timeout.connect(_on_timer_timeout)
	timer.start()

	_build_header()
	_build_rows()

func _on_population_spawned() -> void:
	# Rebuild entries for the new generation and update once
	_build_rows()
	update_leaderboard()

func _on_timer_timeout() -> void:
	update_leaderboard()

func _build_header() -> void:
	if header_row and header_row.is_inside_tree():
		remove_child(header_row)
		header_row.queue_free()
	header_row = HBoxContainer.new()
	header_row.name = "Header"
	add_child(header_row)
	move_child(header_row, 0)

	# Rank column
	var rank_col := LeaderboardField.new()
	rank_col.field_name = "#"
	rank_col.align = HORIZONTAL_ALIGNMENT_RIGHT
	rank_col.column_weight = 0.5
	rank_col.min_width = 48
	rank_col.text = rank_col.field_name

	# Pilot column
	var name_col := LeaderboardField.new()
	name_col.field_name = "Pilot"
	name_col.align = HORIZONTAL_ALIGNMENT_LEFT
	name_col.column_weight = 2.0
	name_col.min_width = 200
	name_col.text = name_col.field_name

	# Fitness column
	var fit_col := LeaderboardField.new()
	fit_col.field_name = "Fitness"
	fit_col.align = HORIZONTAL_ALIGNMENT_RIGHT
	fit_col.column_weight = 1.0
	fit_col.min_width = 120
	fit_col.text = fit_col.field_name

	header_row.add_child(rank_col)
	header_row.add_child(name_col)
	header_row.add_child(fit_col)

func _build_rows() -> void:
	if agent_manager == null:
		return
	# Clear any existing entries (preserve header at index 0)
	for e in entries:
		if e.is_inside_tree():
			remove_child(e)
		e.queue_free()
	entries.clear()

	# Create entries for all cars
	for car in agent_manager.cars:
		if car == null:
			continue
		var entry := LeaderboardEntry.new()
		entry.set_car(car)

		# Rank field (no query_path, set later by set_rank)
		var rank_field := LeaderboardField.new()
		rank_field.field_name = "#"
		rank_field.query_path = ""  # empty means: computed column
		rank_field.align = HORIZONTAL_ALIGNMENT_RIGHT
		rank_field.column_weight = 0.5
		rank_field.min_width = 16
		rank_field.format = "{value}"

		var pilot_field := LeaderboardField.new()
		pilot_field.field_name = "Pilot"
		pilot_field.query_path = "car_data.pilot.get_full_name()"
		pilot_field.align = HORIZONTAL_ALIGNMENT_LEFT
		pilot_field.column_weight = 2.0
		pilot_field.min_width = 200
		pilot_field.format = "{value}"

		var fitness_field := LeaderboardField.new()
		fitness_field.field_name = "Fitness"
		fitness_field.query_path = "car_data.fitness"
		fitness_field.align = HORIZONTAL_ALIGNMENT_RIGHT
		fitness_field.column_weight = 1.0
		fitness_field.min_width = 120
		fitness_field.decimals = 3
		fitness_field.format = "{value}"

		entry.add_field(rank_field)
		entry.add_field(pilot_field)
		entry.add_field(fitness_field)

		entries.append(entry)
		add_child(entry)     # after header

func update_leaderboard() -> void:
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
