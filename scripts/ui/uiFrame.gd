extends Control
class_name UIFrame

@export var top_bar_visible: bool = true:
	set(v):
		top_bar_visible = v
		if is_instance_valid(_top_bar): _top_bar.visible = v

@export var bottom_bar_visible: bool = true:
	set(v):
		bottom_bar_visible = v
		if is_instance_valid(_bottom_bar): _bottom_bar.visible = v

@export var left_bar_visible: bool = true:
	set(v):
		left_bar_visible = v
		if is_instance_valid(_left_bar): _left_bar.visible = v

@export var right_bar_visible: bool = true:
	set(v):
		right_bar_visible = v
		if is_instance_valid(_right_bar): _right_bar.visible = v

@export var top_bar_min_h: int = 40
@export var bottom_bar_min_h: int = 40
@export var side_bar_min_w: int = 220

var _root: VBoxContainer
var _center_row: HBoxContainer
var _top_bar: PanelContainer
var _bottom_bar: PanelContainer
var _left_bar: PanelContainer
var _right_bar: PanelContainer
var _top_bar_content: HBoxContainer
var _bottom_bar_content: HBoxContainer
var _left_bar_content: VBoxContainer
var _right_bar_content: VBoxContainer
var _center_content: Control

func _ready() -> void:
	_ensure_layout()

	_top_bar.custom_minimum_size.y = top_bar_min_h
	_bottom_bar.custom_minimum_size.y = bottom_bar_min_h
	_left_bar.custom_minimum_size.x = side_bar_min_w
	_right_bar.custom_minimum_size.x = side_bar_min_w

	_top_bar.visible = top_bar_visible
	_bottom_bar.visible = bottom_bar_visible
	_left_bar.visible = left_bar_visible
	_right_bar.visible = right_bar_visible

# Public API
func add_to_top(node: Control) -> void:
	_ensure_layout()
	_top_bar_content.add_child(node)

func add_to_bottom(node: Control) -> void:
	_ensure_layout()
	_bottom_bar_content.add_child(node)

func add_to_left(node: Control) -> void:
	_ensure_layout()
	_left_bar_content.add_child(node)

func add_to_right(node: Control) -> void:
	_ensure_layout()
	_right_bar_content.add_child(node)

func get_center_container() -> Control:
	_ensure_layout()
	return _center_content

# Try to bind refs from the scene if UIFrame.tscn already provides them
func _bind_scene_refs() -> bool:
	_root = get_node_or_null("Root") as VBoxContainer
	if _root == null:
		return false

	_top_bar = get_node_or_null("Root/TopBar") as PanelContainer
	_top_bar_content = get_node_or_null("Root/TopBar/TopBarContent") as HBoxContainer

	_center_row = get_node_or_null("Root/CenterRow") as HBoxContainer
	_left_bar = get_node_or_null("Root/CenterRow/LeftBar") as PanelContainer
	_left_bar_content = get_node_or_null("Root/CenterRow/LeftBar/LeftBarContent") as VBoxContainer
	_center_content = get_node_or_null("Root/CenterRow/CenterContent") as Control
	_right_bar = get_node_or_null("Root/CenterRow/RightBar") as PanelContainer
	_right_bar_content = get_node_or_null("Root/CenterRow/RightBar/RightBarContent") as VBoxContainer

	_bottom_bar = get_node_or_null("Root/BottomBar") as PanelContainer
	_bottom_bar_content = get_node_or_null("Root/BottomBar/BottomBarContent") as HBoxContainer

	# All critical parts must exist
	return (
		is_instance_valid(_top_bar) and
		is_instance_valid(_top_bar_content) and
		is_instance_valid(_center_row) and
		is_instance_valid(_left_bar) and
		is_instance_valid(_left_bar_content) and
		is_instance_valid(_center_content) and
		is_instance_valid(_right_bar) and
		is_instance_valid(_right_bar_content) and
		is_instance_valid(_bottom_bar) and
		is_instance_valid(_bottom_bar_content)
	)

# Build UI if scene lacks the containers (works with empty UIFrame.tscn)
func _ensure_layout() -> void:
	if is_instance_valid(_root):
		return

	# First, try to bind to nodes provided by UIFrame.tscn
	if _bind_scene_refs():
		return

	# Otherwise, build the layout programmatically
	set_anchors_preset(Control.PRESET_FULL_RECT, false)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_root = VBoxContainer.new()
	_root.name = "Root"
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_root)

	# Top bar (full width)
	_top_bar = PanelContainer.new()
	_top_bar.name = "TopBar"
	_top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar.size_flags_vertical = 0
	_root.add_child(_top_bar)

	_top_bar_content = HBoxContainer.new()
	_top_bar_content.name = "TopBarContent"
	_top_bar_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar.add_child(_top_bar_content)

	# Center row with left (fixed), center (expand), right (fixed)
	_center_row = HBoxContainer.new()
	_center_row.name = "CenterRow"
	_center_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_center_row)

	_left_bar = PanelContainer.new()
	_left_bar.name = "LeftBar"
	_left_bar.size_flags_horizontal = 0
	_left_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_row.add_child(_left_bar)

	_left_bar_content = VBoxContainer.new()
	_left_bar_content.name = "LeftBarContent"
	_left_bar_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_bar_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_bar.add_child(_left_bar_content)

	_center_content = Control.new()
	_center_content.name = "CenterContent"
	_center_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_row.add_child(_center_content)

	_right_bar = PanelContainer.new()
	_right_bar.name = "RightBar"
	_right_bar.size_flags_horizontal = 0
	_right_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_row.add_child(_right_bar)

	_right_bar_content = VBoxContainer.new()
	_right_bar_content.name = "RightBarContent"
	_right_bar_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_bar_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_bar.add_child(_right_bar_content)

	# Bottom bar (full width)
	_bottom_bar = PanelContainer.new()
	_bottom_bar.name = "BottomBar"
	_bottom_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_bar.size_flags_vertical = 0
	_root.add_child(_bottom_bar)

	_bottom_bar_content = HBoxContainer.new()
	_bottom_bar_content.name = "BottomBarContent"
	_bottom_bar_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_bar.add_child(_bottom_bar_content)
