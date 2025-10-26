extends DraggablePanel
class_name CarHandlePanel

@export_group("Data")
@export var name_path: String = "car_data.pilot.get_full_name()"
@export var score_path: String = "car_data.fitness"
@export var skip_crashed: bool = true
@export var update_hz: float = 4.0

var car: Car = null
var _db: DataBroker = null
var _am: AgentManager = null

var _label: Label
var _accum := 0.0

func _ready() -> void:
	set_title("Car")
	var box := VBoxContainer.new()
	_label = Label.new()
	_label.text = "—"
	box.add_child(_label)
	set_content(box)

	_db = get_tree().get_root().find_child("DataBroker", true, false) as DataBroker
	_am = get_tree().get_root().find_child("AgentManager", true, false) as AgentManager
	set_process(true)

func set_car(c: Car) -> void:
	car = c

func _process(dt: float) -> void:
	_accum += dt
	var step = 1.0 / max(1.0, update_hz)
	if _accum < step:
		return
	_accum = 0.0
	if car == null or !is_instance_valid(car):
		_label.text = "—"
		return
	var pilot_name := str(car.name)
	if _db:
		var v = _db.get_value(car, name_path)
		if typeof(v) == TYPE_STRING:
			pilot_name = String(v)
	var rank := _compute_rank_linear(car) # no sort
	_label.text = "%d. %s" % [rank, pilot_name]

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