extends DraggablePanel
class_name CarHandlePanel

@export_group("Data")
@export var name_path: String = "car_data.pilot.get_full_name()"
@export var score_path: String = "car_data.fitness"
@export var skip_crashed: bool = true
@export var update_hz: float = 4.0

# NEW: declarative list of fields for this panel
@export var fields: Array[DataFieldDef] = []

# NEW: style
@export var fade_crashed: bool = true
@export_range(0.05, 1.0, 0.05) var crashed_alpha: float = 0.45

var car: Car = null
var _db: DataBroker = null
var _am: AgentManager = null

var _label: Label
var _accum := 0.0

# NEW: UI container for fields + instances
var _box: VBoxContainer
var _field_nodes: Array[DataField] = []

# Rank provider (optional), reused by "#rank" virtual field
var _rank_provider: Callable = Callable()

func _ready() -> void:
	set_title("Car")
	_box = VBoxContainer.new()
	_label = Label.new()
	_label.text = "—"
	_box.add_child(_label)
	set_content(_box)

	_db = get_tree().get_root().find_child("DataBroker", true, false) as DataBroker
	_am = get_tree().get_root().find_child("AgentManager", true, false) as AgentManager
	set_process(true)

	# If no custom fields set in the inspector, use defaults
	if fields.is_empty():
		fields = DataFieldDef.make_default_car_fields()
	_build_fields()

func set_car(c: Car) -> void:
	car = c

func set_rank_provider(fn: Callable) -> void:
	_rank_provider = fn

func _process(dt: float) -> void:
	_accum += dt
	var step = 1.0 / max(1.0, update_hz)
	if _accum < step:
		return
	_accum = 0.0

	if car == null or !is_instance_valid(car):
		_label.text = "—"
		_render_faded(false)
		_render_fields_null()
		return

	# Title line stays as "rank. name"
	var pilot_name := str(car.name)
	if _db:
		var v = _db.get_value(car, name_path)
		if typeof(v) == TYPE_STRING:
			pilot_name = String(v)
	var rank := _compute_rank_linear(car) # O(n) scan
	_label.text = "%d. %s" % [rank, pilot_name]

	# Fade when crashed
	_render_faded(fade_crashed and car.crashed)

	# Data fields: batch resolve with DataBroker.get_many
	if _db == null or fields.is_empty():
		return

	# Collect query paths (skip special "#rank" and those with empty path)
	var paths := PackedStringArray()
	var field_to_path_idx := {}
	var p := 0
	for i in range(fields.size()):
		var qp := fields[i].query_path.strip_edges()
		if qp == "" or qp == "#rank":
			continue
		field_to_path_idx[i] = p
		paths.append(qp)
		p += 1

	var values: Array = []
	if paths.size() > 0:
		values = _db.get_many(car, paths)

	# Render each field
	for i in range(fields.size()):
		var def := fields[i]
		var node := _field_nodes[i]
		if def.query_path == "#rank":
			node.render(rank)
			continue
		if def.visible_if != "":
			var vis_val = _db.get_value(car, def.visible_if)
			if !vis_val:
				node.visible = false
				continue
			node.visible = true
		if field_to_path_idx.has(i):
			var idx: int = int(field_to_path_idx[i])
			var value = values[idx] if idx < values.size() else null
			node.render(value)
		else:
			node.render(null)

func _render_faded(faded: bool) -> void:
	if _label:
		var c := _label.modulate
		c.a = (crashed_alpha if faded else 1.0)
		_label.modulate = c
	for n in _field_nodes:
		n.set_faded(faded, crashed_alpha)

func _render_fields_null() -> void:
	for n in _field_nodes:
		n.render(null)

func _build_fields() -> void:
	# Clear old
	for n in _field_nodes:
		if n and n.is_inside_tree():
			_box.remove_child(n)
	_field_nodes.clear()

	# Create new
	for def in fields:
		var f := DataField.new()
		f.set_def(def)
		_field_nodes.append(f)
		_box.add_child(f)

func _compute_rank_linear(target: Car) -> int:
	if _am == null or _am.cars.is_empty():
		return 1
	var target_score := _score_for_car(target)
	var rank := 1
	for c in _am.cars:
		if c == null: continue
		if skip_crashed and c.crashed: continue
		if c == target: continue
		if _score_for_car(c) > target_score:
			rank += 1
	return rank

func _score_for_car(c: Car) -> float:
	if c == null: return -INF
	if score_path == "car_data.fitness":
		return float(c.fitness)
	if _db == null: return float(c.fitness)
	var v = _db.get_value(c, score_path)
	match typeof(v):
		TYPE_FLOAT, TYPE_INT: return float(v)
		TYPE_BOOL: return (1.0 if v else 0.0)
		TYPE_STRING:
			var s := String(v)
			return float(s) if s.is_valid_float() else 0.0
		_: return 0.0

func get_top_left_screen() -> Vector2:
	return get_global_rect().position
