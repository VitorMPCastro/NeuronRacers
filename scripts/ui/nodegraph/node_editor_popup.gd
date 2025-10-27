extends PopupPanel
class_name NodeEditorPopup

@onready var _top_bar := HBoxContainer.new()
@onready var _save_btn := Button.new()
@onready var _open_btn := Button.new()
@onready var _apply_btn := Button.new()
@onready var _close_btn := Button.new()
@onready var _graph_container := PanelContainer.new()
@onready var _status_label := Label.new()
@onready var _header_label := Label.new()
# Resize handle
var _resize_handle: Control = null
var graph: NodeGraph = null

# File dialogs
var _save_dialog: FileDialog = null
var _open_dialog: FileDialog = null

# Drag / resize state
var _dragging: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_pos: Vector2 = Vector2.ZERO
var _resizing: bool = false
var _resize_start_mouse: Vector2 = Vector2.ZERO
var _resize_start_size: Vector2 = Vector2.ZERO
const MIN_SIZE := Vector2(480, 320)

func _ready() -> void:
	# Set a sensible initial size and allow manual positioning
	size = Vector2(900, 600)
	# DO NOT set mouse_filter on the PopupPanel itself (caused linter/runtime confusion).
	# Instead configure children below so events reach the graph and buttons as intended.

	var root_v := VBoxContainer.new()
	add_child(root_v)

	# Header label (above the top bar)
	_header_label.text = "Node Editor"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_label.custom_minimum_size = Vector2(0, 22)
	# don't block by default; only capture while hovering or dragging
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_label.connect("mouse_entered", Callable(self, "_on_header_mouse_entered"))
	_header_label.connect("mouse_exited", Callable(self, "_on_header_mouse_exited"))
	_header_label.connect("gui_input", Callable(self, "_on_header_gui_input"))
	root_v.add_child(_header_label)

	# Top bar
	_top_bar.name = "TopBar"
	_top_bar.custom_minimum_size = Vector2(0, 36)
	root_v.add_child(_top_bar)

	_save_btn.text = "Save..."
	_save_btn.connect("pressed", Callable(self, "_on_save_pressed"))
	_top_bar.add_child(_save_btn)

	_open_btn.text = "Open..."
	_open_btn.connect("pressed", Callable(self, "_on_open_pressed"))
	_top_bar.add_child(_open_btn)

	_apply_btn.text = "Apply"
	_apply_btn.connect("pressed", Callable(self, "_on_apply_pressed"))
	_top_bar.add_child(_apply_btn)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar.add_child(sp)

	# status label (inline parse errors / info)
	_status_label.text = ""
	_status_label.add_theme_color_override("font_color", Color(1,0.4,0.4))
	_status_label.size_flags_horizontal = Control.SIZE_FILL
	_top_bar.add_child(_status_label)

	_close_btn.text = "Close"
	_close_btn.connect("pressed", Callable(self, "_on_close_pressed"))
	_top_bar.add_child(_close_btn)

	# Graph area
	_graph_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# allow graph container to pass events to its child graph
	_graph_container.mouse_filter = Control.MOUSE_FILTER_PASS
	root_v.add_child(_graph_container)

	# instantiate NodeGraph
	var ng_res = preload("res://scripts/ui/nodegraph/node_graph.gd")
	graph = ng_res.new() as NodeGraph
	_graph_container.add_child(graph)
	# let graph expand inside container
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# ensure the graph receives mouse input (so it can show context menu / accept right-clicks)
	graph.mouse_filter = Control.MOUSE_FILTER_PASS
	# allow the graph to receive focus, then grab it
	graph.focus_mode = Control.FOCUS_ALL
	# grab focus after node is in tree to avoid timing warning / odd focus stealing
	graph.call_deferred("grab_focus")

	# Resize handle (bottom-right)
	_resize_handle = Control.new()
	_resize_handle.name = "ResizeHandle"
	# ignore events by default so the graph/buttons remain interactive;
	# switch to STOP only while hovered or while resizing.
	_resize_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize_handle.focus_mode = Control.FOCUS_NONE
	_resize_handle.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_resize_handle.anchor_left = 0.0
	_resize_handle.anchor_top = 0.0
	_resize_handle.anchor_right = 0.0
	_resize_handle.anchor_bottom = 0.0
	_resize_handle.size_flags_horizontal = 0
	_resize_handle.size_flags_vertical = 0
	_resize_handle.custom_minimum_size = Vector2(14, 14)
	_resize_handle.size = Vector2(14, 14)
	_resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize_handle.position = Vector2(size.x - 18, size.y - 18)
	_resize_handle.connect("gui_input", Callable(self, "_on_resize_gui_input"))
	_resize_handle.connect("mouse_entered", Callable(self, "_on_resize_mouse_entered"))
	_resize_handle.connect("mouse_exited", Callable(self, "_on_resize_mouse_exited"))
	add_child(_resize_handle)

	# File dialogs
	_save_dialog = FileDialog.new()
	# Godot 4 uses file_mode constants on FileDialog
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.set_current_path("user://nodegraph.json")
	_save_dialog.add_filter("*.json ; JSON files")
	_save_dialog.connect("file_selected", Callable(self, "_on_save_file_selected"))
	add_child(_save_dialog)

	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.add_filter("*.json ; JSON files")
	_open_dialog.connect("file_selected", Callable(self, "_on_open_file_selected"))
	add_child(_open_dialog)

	# Try auto-load existing user file if present (non-blocking)
	var user_path := "user://nodegraph.json"
	if FileAccess.file_exists(user_path):
		graph.load_from_file(user_path)

func _on_header_mouse_entered() -> void:
	if not _dragging:
		_header_label.mouse_filter = Control.MOUSE_FILTER_STOP

func _on_header_mouse_exited() -> void:
	if not _dragging:
		_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_resize_mouse_entered() -> void:
	if not _resizing:
		_resize_handle.mouse_filter = Control.MOUSE_FILTER_STOP

func _on_resize_mouse_exited() -> void:
	if not _resizing:
		_resize_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_header_gui_input(ev: InputEvent) -> void:
	# Keep local check as extra guard.
	var local := _header_label.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, _header_label.size).has_point(local):
		return

	# remove noisy print spam
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_dragging = true
			_drag_start_mouse = ev.global_position
			_drag_start_pos = position
		else:
			_dragging = false
	elif ev is InputEventMouseMotion and _dragging:
		var delta = ev.global_position - _drag_start_mouse
		var new_pos = _drag_start_pos + delta
		var vp_size := get_viewport().get_visible_rect().size
		new_pos.x = clamp(new_pos.x, 0.0, max(0.0, vp_size.x - size.x))
		new_pos.y = clamp(new_pos.y, 0.0, max(0.0, vp_size.y - size.y))
		position = new_pos

func _on_resize_gui_input(ev: InputEvent) -> void:
	var local := _resize_handle.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, _resize_handle.size).has_point(local) and not _resizing:
		return

	# remove noisy print spam
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_resizing = true
			_resize_start_mouse = ev.global_position
			_resize_start_size = size
			# ensure we keep capturing while resizing
			_resize_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			_resizing = false
			# release capture when done (only ignore if not hovering)
			if not Rect2(Vector2.ZERO, _resize_handle.size).has_point(_resize_handle.get_local_mouse_position()):
				_resize_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif ev is InputEventMouseMotion and _resizing:
		var vp_size := get_viewport().get_visible_rect().size
		var delta = ev.global_position - _resize_start_mouse
		var new_size = _resize_start_size + delta
		new_size.x = max(MIN_SIZE.x, min(new_size.x, vp_size.x - position.x))
		new_size.y = max(MIN_SIZE.y, min(new_size.y, vp_size.y - position.y))
		size = new_size

func set_data_context(broker: DataBroker, provider: Object) -> void:
	if graph:
		graph.set_data_context(broker, provider)

func popup_centered_full() -> void:
	popup_centered(Vector2(0.8, 0.8))

func _on_save_pressed() -> void:
	_save_dialog.popup_centered()

func _on_open_pressed() -> void:
	_open_dialog.popup_centered()

func _on_save_file_selected(path: String) -> void:
	if not graph:
		return
	var ok := graph.save_to_file(path)
	if ok:
		_status_label.add_color_override("font_color", Color(0.4,1,0.4))
		_status_label.text = "Saved: " + path
	else:
		_status_label.add_color_override("font_color", Color(1,0.4,0.4))
		_status_label.text = "Failed to save: " + path
	call_deferred("_clear_status_later")

func _on_open_file_selected(path: String) -> void:
	if not graph:
		return
	var ok := graph.load_from_file(path)
	if ok:
		_status_label.add_color_override("font_color", Color(0.4,1,0.4))
		_status_label.text = "Loaded: " + path
	else:
		_status_label.add_color_override("font_color", Color(1,0.4,0.4))
		_status_label.text = "Failed to load: " + path
	call_deferred("_clear_status_later")

func _clear_status_later() -> void:
	await get_tree().create_timer(3.0).timeout
	_status_label.text = ""

# Public API: allow external callers (e.g. FitnessNode) to set the inline status
func set_status(text: String, color: Color = Color(1,1,1)) -> void:
	_status_label.add_color_override("font_color", color)
	_status_label.text = text
	# reset after a short delay
	call_deferred("_clear_status_later")

func _on_apply_pressed() -> void:
	_status_label.text = ""
	if graph:
		graph.evaluate_fitness()  # Fitness node(s) will push equation into AgentManager

	# Check AgentManager parse status (AgentManager sets use_custom_fitness = parse_ok)
	var am := get_tree().get_first_node_in_group("AgentManager")
	if am == null:
		_status_label.add_color_override("font_color", Color(1,0.6,0.2))
		_status_label.text = "Applied (AgentManager not found — saved on graph only)"
		call_deferred("_clear_status_later")
		return

	# If AgentManager exposes use_custom_fitness (we set this true only when parse OK)
	if "use_custom_fitness" in am:
		if am.use_custom_fitness:
			_status_label.add_color_override("font_color", Color(0.4,1,0.4))
			_status_label.text = "Applied: equation parsed successfully"
		else:
			_status_label.add_color_override("font_color", Color(1,0.4,0.4))
			var eq = am.custom_fitness_equation if "custom_fitness_equation" in am else "<unknown>"
			_status_label.text = "Parse error — equation rejected: " + eq
	else:
		_status_label.add_color_override("font_color", Color(0.8,0.8,0.2))
		_status_label.text = "Applied (no parse status available)"
	call_deferred("_clear_status_later")

func _on_close_pressed() -> void:
	hide()

# Keep this notification handler near other helpers in the script
func _notification(what: int) -> void:
	if what == Control.NOTIFICATION_RESIZED:
		if _resize_handle:
			_resize_handle.position = Vector2(size.x - 18, size.y - 18)

func _input(ev: InputEvent) -> void:
	# If a context StickyPanel is open, ignore RIGHT clicks so they go to menus instead of closing the editor
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		if StickyPanel.is_any_open():
			return
