extends PanelContainer
class_name ContentBar

@export var axis: int = HORIZONTAL  # BoxContainer.HORIZONTAL or VERTICAL
@export var padding_px: int = 6

var _container: BoxContainer
var _built := false

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	if _built: return
	_build()
	_built = true

func _build() -> void:
	add_theme_constant_override("margin_left", padding_px)
	add_theme_constant_override("margin_right", padding_px)
	add_theme_constant_override("margin_top", padding_px)
	add_theme_constant_override("margin_bottom", padding_px)

	_container = (HBoxContainer.new() if axis == HORIZONTAL else VBoxContainer.new())
	_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_container)

func add_control(ctrl: Control) -> void:
	_ensure_built()
	if ctrl:
		_container.add_child(ctrl)

func add_spacer(expand := true) -> Control:
	_ensure_built()
	var s := Control.new()
	if axis == HORIZONTAL:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else 0
	else:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL if expand else 0
	_container.add_child(s)
	return s

func clear() -> void:
	_ensure_built()
	for c in _container.get_children():
		c.queue_free()

func get_container() -> BoxContainer:
	_ensure_built()
	return _container