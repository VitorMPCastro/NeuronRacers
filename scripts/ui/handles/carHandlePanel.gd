extends DraggablePanel
class_name CarHandlePanel

@export_group("Data")
@export var name_path: String = "car_data.pilot.get_full_name()"
@export var score_path: String = "car_data.fitness"
@export var skip_crashed: bool = true

var car: Car = null
var _db: DataBroker = null
var _am: AgentManager = null

var _label: Label

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

func _process(_dt: float) -> void:
	if car == null or !is_instance_valid(car):
		_label.text = "—"
		return

	# Name via DataBroker
	var pilot_name := str(car.name)
	if _db:
		var v = _db.get_value(car, name_path)
		if typeof(v) == TYPE_STRING:
			pilot_name = String(v)

	# Rank from score_path via DataBroker
	var rank := _compute_rank(car)
	_label.text = "%d. %s" % [rank, pilot_name]

func _compute_rank(target: Car) -> int:
	if _am == null or _am.cars.is_empty():
		return 1
	var best_list: Array = []
	for c in _am.cars:
		if c == null:
			continue
		if skip_crashed and c.crashed:
			continue
		var score := 0.0
		if _db:
			var v = _db.get_value(c, score_path)
			match typeof(v):
				TYPE_FLOAT, TYPE_INT: score = float(v)
				TYPE_BOOL: score = (1.0 if v else 0.0)
				TYPE_STRING:
					var s := String(v)
					score = float(s) if s.is_valid_float() else 0.0
				_: score = 0.0
		best_list.append({ "c": c, "s": score })
	best_list.sort_custom(func(a, b): return a.s > b.s)
	for i in range(best_list.size()):
		if best_list[i].c == target:
			return i + 1
	return 1

func get_top_left_screen() -> Vector2:
	return get_global_rect().position