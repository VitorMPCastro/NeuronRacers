extends PanelContainer
class_name DraggablePanel

@export var title: String = "Panel"

var _dragging := false
var _drag_offset := Vector2.ZERO
var _title_label: Label
var _content_holder: VBoxContainer
var _built := false

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	if _built:
		return
	_build()
	_built = true

func _build() -> void:
	anchors_preset = PRESET_TOP_LEFT
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_END

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vb)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header.gui_input.connect(_on_header_gui_input)
	vb.add_child(header)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_content_holder = VBoxContainer.new()
	_content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_content_holder)

func set_title(t: String) -> void:
	title = t
	_ensure_built()
	if is_instance_valid(_title_label):
		_title_label.text = t

func set_content(ctrl: Control) -> void:
	_ensure_built()
	if _content_holder == null:
		return
	for c in _content_holder.get_children():
		_content_holder.remove_child(c)
		c.queue_free()
	if ctrl:
		_content_holder.add_child(ctrl)

func _on_header_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			accept_event()
		else:
			_dragging = false
	elif ev is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		accept_event()

# Small helper to clear children
func clear_children() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()

func destroy() -> void:
	clear_children()
	queue_free()
