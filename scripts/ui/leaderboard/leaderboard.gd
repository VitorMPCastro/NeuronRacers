extends VBoxContainer
class_name Leaderboard

var entries: Array[LeaderboardEntry] = []
var timer: Timer = Timer.new()

@onready var car_telemetry: CarTelemetry = get_tree().get_first_node_in_group("car_telemetry") as CarTelemetry
@onready var agent_manager: AgentManager = car_telemetry.agent_manager if car_telemetry else null
@onready var data_broker: DataBroker = get_tree().get_first_node_in_group("data_broker") as DataBroker

@export var sort_field: String = "Fitness"
@export var update_interval_s: float = 0.3
@export var load_default_columns: bool = true
@export var custom_columns: Array[LeaderboardColumn] = []

# NEW: show only top N rows; pool row controls
@export var max_rows: int = 20
var _entry_pool: Array[LeaderboardEntry] = []

var columns: Array[LeaderboardColumn] = []
var header_row: HBoxContainer
var _rebuild_deferred := false

func _ready() -> void:
	if agent_manager:
		agent_manager.population_spawned.connect(_on_population_spawned)

	add_child(timer)
	timer.wait_time = update_interval_s
	timer.timeout.connect(_on_timer_timeout)
	timer.start()

	if data_broker == null and agent_manager:
		var root := agent_manager.get_parent() as Node
		if root:
			data_broker = root.find_child("DataBroker", true, false) as DataBroker

	_resolve_columns()
	_build_header()
	_build_rows()

func _on_population_spawned() -> void:
	# Defer heavy UI rebuild to avoid sharing the same frame as spawn_population()
	if _rebuild_deferred:
		return
	_rebuild_deferred = true
	call_deferred("_do_rebuild_rows")

func _do_rebuild_rows() -> void:
	_rebuild_deferred = false
	_resolve_columns()
	_build_header()
	_build_rows()
	update_leaderboard()

func _on_timer_timeout() -> void:
	update_leaderboard()

func _build_rows() -> void:
	if columns.is_empty():
		return
	if agent_manager == null:
		return

	# Keep only up to max_rows, pool the rest
	var target := clampi(min(agent_manager.cars.size(), max_rows), 0, max_rows)
	# Return extra entries to pool
	while entries.size() > target:
		var e = entries.pop_back()
		if e.is_inside_tree():
			remove_child(e)
		_entry_pool.append(e)

	# Add missing entries from pool/new
	while entries.size() < target:
		var entry = _entry_pool.pop_back() if _entry_pool.size() > 0 else LeaderboardEntry.new()
		# Build fields only when newly created (no children)
		if entry.get_child_count() == 0:
			for col in columns:
				entry.add_field(_make_field(col, false))
		entries.append(entry)
		add_child(entry)

	# Header stays at index 0
	if header_row and header_row.is_inside_tree():
		move_child(header_row, 0)

func update_leaderboard() -> void:
	if columns.is_empty() or data_broker == null or agent_manager == null:
		return

	# Get top N cars by fitness with a single linear pass (no global sort)
	var top := _top_n_cars(min(max_rows, agent_manager.cars.size()))

	# Ensure we have matching number of rows
	if entries.size() != top.size():
		_build_rows()
		if entries.size() != top.size():
			return

	# Update rows
	for i in range(top.size()):
		var car = top[i]
		var row := entries[i]
		row.set_car(car)
		row.update_entry(data_broker)
		row.set_rank(i + 1)
		# Keep rows right after header
		if row.get_parent() != self:
			add_child(row)
		move_child(row, i + 1) # header at 0

func _top_n_cars(n: int) -> Array:
	var out: Array = []
	out.resize(0)
	if n <= 0:
		return out
	# Keep a small sorted list by fitness (descending)
	for c in agent_manager.cars:
		if c == null or c.crashed:
			continue
		var f := float(c.fitness)
		# insert into out
		var inserted := false
		for i in range(out.size()):
			if f > float(out[i].fitness):
				out.insert(i, c)
				inserted = true
				break
		if not inserted:
			out.append(c)
		if out.size() > n:
			out.resize(n)
	return out

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

func _resolve_columns() -> void:
	columns.clear()
	if load_default_columns:
		columns += LeaderboardColumn.make_default_columns()
	if !custom_columns.is_empty():
		columns += custom_columns.duplicate()
	if columns.is_empty():
		push_error("Leaderboard: No columns defined and load_default_columns is false. Please define custom columns or enable default columns.")
