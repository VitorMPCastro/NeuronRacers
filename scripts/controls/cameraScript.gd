extends Camera2D

@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.1
@export var max_zoom: float = 1.0
@export var camera_change_cd = 0.5

# NEW: optionally bind HUD explicitly in the editor
@export var hud_path: NodePath
# NEW: allow HUD to toggle highlight visuals (HUD already reads this)
@export var highlight_enabled: bool = true

signal target_changed(new_target: Node2D)

var target: Node2D = null
var _hud: Node = null
var _last_highlighted: Node2D = null

func _ready() -> void:
	_resolve_hud()

func _physics_process(_delta: float) -> void:
	# Follow HUD-selected car if available
	var desired: Node2D = _get_hud_observed_car()
	if desired != null and desired != target:
		set_target(desired)

	if target:
		global_position = target.global_position

func _input(event: InputEvent) -> void:
	# Only handle zoom here; HUD owns selection keys
	if event is InputEventKey and event.pressed and !event.echo:
		match event.keycode:
			KEY_UP:
				adjust_zoom(-zoom_speed)
				return
			KEY_DOWN:
				adjust_zoom(zoom_speed)
				return

func adjust_zoom(amount: float) -> void:
	var new_zoom := zoom + Vector2(amount, amount)
	new_zoom.x = clamp(new_zoom.x, min_zoom, max_zoom)
	new_zoom.y = clamp(new_zoom.y, min_zoom, max_zoom)
	zoom = new_zoom

# Public API for HUD
func spectate_car(car: Node2D) -> void:
	set_target(car)

func set_target(obj: Node2D) -> void:
	if obj == target:
		return
	# Clear previous highlight
	if is_instance_valid(_last_highlighted) and _last_highlighted.has_method("set_highlighted"):
		_last_highlighted.set_highlighted(false)

	target = obj

	# Apply highlight on new target
	if highlight_enabled and is_instance_valid(target) and target.has_method("set_highlighted"):
		target.set_highlighted(true)
		_last_highlighted = target

	target_changed.emit(target)

# Internal helpers ------------------------------------------------------------

func _resolve_hud() -> void:
	if hud_path != NodePath():
		_hud = get_node_or_null(hud_path)
		if _hud:
			return
	# Try by group
	_hud = get_tree().get_first_node_in_group("hud")
	if _hud:
		return
	# Fallback: search for a CanvasLayer that exposes get_observed_car/_get_observed_car
	var root := get_tree().get_root()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is CanvasLayer and (n.has_method("get_observed_car") or n.has_method("_get_observed_car")):
			_hud = n
			return
		for c in n.get_children():
			stack.push_back(c)

func _get_hud_observed_car() -> Node2D:
	if _hud == null or !is_instance_valid(_hud):
		_resolve_hud()
	if _hud:
		if _hud.has_method("get_observed_car"):
			var car = _hud.get_observed_car()
			return car as Node2D
		if _hud.has_method("_get_observed_car"):
			var car2 = _hud._get_observed_car()
			return car2 as Node2D
	return null
