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

# Show how many rows. <= 0 means “all candidates”.
@export var max_rows: int = -1
# If false, hide crashed cars from the list.
@export var include_crashed: bool = true        # was false
# NEW: show crashed rows faded
@export var show_crashed_faded: bool = true
@export_range(0.05, 1.0, 0.05) var crashed_alpha: float = 0.35

var _entry_pool: Array[LeaderboardEntry] = []

var columns: Array[LeaderboardColumn] = []
var header_row: HBoxContainer
var _rebuild_deferred := false

func _ready() -> void:
	_ensure_refs()

	if agent_manager:
		agent_manager.population_spawned.connect(_on_population_spawned)

	add_child(timer)
	timer.wait_time = update_interval_s
	timer.timeout.connect(_on_timer_timeout)
	timer.start()

	_resolve_columns()
	_build_header()
	call_deferred("_do_rebuild_rows")

func _ensure_refs() -> void:
	# Late-bind AgentManager if car_telemetry wasn't ready yet
	if agent_manager == null:
		var am := get_tree().get_root().find_child("AgentManager", true, false)
		if am:
			agent_manager = am as AgentManager
	# Late-bind DataBroker by group or by name
	if data_broker == null:
		data_broker = get_tree().get_first_node_in_group("data_broker") as DataBroker
	if data_broker == null:
		var db := get_tree().get_root().find_child("DataBroker", true, false)
		if db:
			data_broker = db as DataBroker

func _on_population_spawned() -> void:
	_ensure_refs()
	if _rebuild_deferred:
		return
	_rebuild_deferred = true
	call_deferred("_do_rebuild_rows")

func _do_rebuild_rows() -> void:
	_rebuild_deferred = false
	_ensure_refs()
	_update_rows_structure(0) # shrink to 0, we’ll size properly on the first update
	update_leaderboard()

func _on_timer_timeout() -> void:
	update_leaderboard()

func update_leaderboard() -> void:
	if columns.is_empty():
		return
	_ensure_refs()
	if data_broker == null or agent_manager == null:
		return

	# Build candidate list (optionally exclude crashed)
	var candidates := _collect_candidates()
	if candidates.is_empty():
		_update_rows_structure(0)
		return

	# Target number of rows to render
	var target_count = candidates.size() if max_rows <= 0 else min(max_rows, candidates.size())
	_update_rows_structure(target_count)

	# Take top N by fitness (lightweight insert sort for small N)
	var top := _top_n_from(candidates, target_count)

	# Update rows
	for i in range(target_count):
		var car = top[i]
		var row := entries[i]
		row.set_car(car)
		row.update_entry(data_broker)
		row.set_rank(i + 1)
		# NEW: fade crashed rows
		row.set_crashed_style(show_crashed_faded and car.crashed, crashed_alpha)
		if row.get_parent() != self:
			add_child(row)
		move_child(row, i + 1) # header at 0

func _collect_candidates() -> Array:
	var out: Array = []
	if agent_manager == null:
		return out
	for c in agent_manager.cars:
		if c == null:
			continue
		if !include_crashed and c.crashed:
			continue
		out.append(c)
	return out

func _top_n_from(candidates: Array, n: int) -> Array:
	if n <= 0:
		return []
	var out: Array = []
	for c in candidates:
		var f := float(c.fitness)
		var inserted := false
		for i in range(out.size()):
			if f > float(out[i].fitness):
				out.insert(i, c)
				inserted = true
				break
		if !inserted:
			out.append(c)
		if out.size() > n:
			out.resize(n)
		# Early exit if filled
		if out.size() == n and f <= float(out.back().fitness):
			# Optional: skip obvious losers to save a few comparisons
			pass
	return out.slice(0, n) if out.size() > n else out

# Ensure we have exactly `target` rows, building fields only once per entry.
func _update_rows_structure(target: int) -> void:
	# Return extra entries to pool
	while entries.size() > target:
		var e = entries.pop_back()
		if e.is_inside_tree():
			remove_child(e)
		_entry_pool.append(e)

	# Add missing entries from pool/new
	while entries.size() < target:
		var entry = _entry_pool.pop_back() if _entry_pool.size() > 0 else LeaderboardEntry.new()
		# Build fields only once per entry
		if entry.get_child_count() == 0:
			for col in columns:
				entry.add_field(_make_field(col, false))
		entries.append(entry)
		add_child(entry)

	# Keep header on top
	if header_row and header_row.is_inside_tree():
		move_child(header_row, 0)

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
