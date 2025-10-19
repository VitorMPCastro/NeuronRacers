extends Control
class_name UIFrame

@export var top_bar_visible: bool = true
@export var bottom_bar_visible: bool = true
@export var left_bar_visible: bool = true
@export var right_bar_visible: bool = true

var _root: VBoxContainer
var _center_row: HBoxContainer
var _center_fill: Control

var top_bar: ContentBar
var bottom_bar: ContentBar
var left_bar: ContentBar
var right_bar: ContentBar

var _built := false

func _ready() -> void:
	_ensure_layout()
	_apply_visibility()

func _ensure_layout() -> void:
	if _built: return
	if _bind_scene_refs():
		_built = true
		return

	set_anchors_preset(Control.PRESET_FULL_RECT, false)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_root = VBoxContainer.new()
	_root.name = "Root"
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_root)

	top_bar = ContentBar.new()
	top_bar.name = "TopBar"
	top_bar.axis = HORIZONTAL
	_root.add_child(top_bar)

	_center_row = HBoxContainer.new()
	_center_row.name = "CenterRow"
	_center_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_center_row)

	left_bar = ContentBar.new()
	left_bar.name = "LeftBar"
	left_bar.axis = VERTICAL
	left_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_row.add_child(left_bar)

	_center_fill = Control.new()
	_center_fill.name = "CenterFill"
	_center_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_row.add_child(_center_fill)

	right_bar = ContentBar.new()
	right_bar.name = "RightBar"
	right_bar.axis = VERTICAL
	right_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_row.add_child(right_bar)

	bottom_bar = ContentBar.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.axis = HORIZONTAL
	_root.add_child(bottom_bar)

	_built = true

func _bind_scene_refs() -> bool:
	_root = get_node_or_null("Root") as VBoxContainer
	if _root == null:
		top_bar = get_node_or_null("TopBar") as ContentBar
		bottom_bar = get_node_or_null("BottomBar") as ContentBar
		left_bar = get_node_or_null("LeftBar") as ContentBar
		right_bar = get_node_or_null("RightBar") as ContentBar
		return is_instance_valid(top_bar) or is_instance_valid(bottom_bar) or is_instance_valid(left_bar) or is_instance_valid(right_bar)

	top_bar = get_node_or_null("Root/TopBar") as ContentBar
	bottom_bar = get_node_or_null("Root/BottomBar") as ContentBar
	_center_row = get_node_or_null("Root/CenterRow") as HBoxContainer
	if _center_row:
		left_bar = _center_row.get_node_or_null("LeftBar") as ContentBar
		_center_fill = _center_row.get_node_or_null("CenterFill") as Control
		right_bar = _center_row.get_node_or_null("RightBar") as ContentBar

	return is_instance_valid(top_bar) and is_instance_valid(bottom_bar) and is_instance_valid(left_bar) and is_instance_valid(right_bar)

func _apply_visibility() -> void:
	if is_instance_valid(top_bar): top_bar.visible = top_bar_visible
	if is_instance_valid(bottom_bar): bottom_bar.visible = bottom_bar_visible
	if is_instance_valid(left_bar): left_bar.visible = left_bar_visible
	if is_instance_valid(right_bar): right_bar.visible = right_bar_visible

# Public API
func add_to_top(ctrl: Control) -> void:
	_ensure_layout(); if top_bar: top_bar.add_control(ctrl)
func add_to_bottom(ctrl: Control) -> void:
	_ensure_layout(); if bottom_bar: bottom_bar.add_control(ctrl)
func add_to_left(ctrl: Control) -> void:
	_ensure_layout(); if left_bar: left_bar.add_control(ctrl)
func add_to_right(ctrl: Control) -> void:
	_ensure_layout(); if right_bar: right_bar.add_control(ctrl)
