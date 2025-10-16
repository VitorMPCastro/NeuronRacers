extends PanelContainer
class_name CollapsiblePanel

@export var title: String = "Panel":
	set(v):
		title = v
		if is_instance_valid(_title_lbl): _title_lbl.text = v

@export var start_collapsed: bool = false

var _header: HBoxContainer
var _toggle_btn: Button
var _title_lbl: Label
var _content_wrap: VBoxContainer
var _built := false

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	if _built:
		return
	_build()
	_built = true

func _build() -> void:
	add_theme_constant_override("margin_left", 6)
	add_theme_constant_override("margin_right", 6)
	add_theme_constant_override("margin_top", 4)
	add_theme_constant_override("margin_bottom", 4)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	_header = HBoxContainer.new()
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_header)

	_toggle_btn = Button.new()
	_toggle_btn.toggle_mode = true
	_toggle_btn.text = "▼"
	_toggle_btn.tooltip_text = "Show/Hide"
	_toggle_btn.button_pressed = !start_collapsed
	_toggle_btn.toggled.connect(_on_toggled)
	_header.add_child(_toggle_btn)

	_title_lbl = Label.new()
	_title_lbl.text = title
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_title_lbl)

	_content_wrap = VBoxContainer.new()
	_content_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content_wrap)

	_content_wrap.visible = !start_collapsed

func _on_toggled(pressed: bool) -> void:
	if is_instance_valid(_toggle_btn):
		_toggle_btn.text = "▼" if pressed else "▲"
	if is_instance_valid(_content_wrap):
		_content_wrap.visible = pressed

func set_content(node: Control) -> void:
	_ensure_built()
	for c in _content_wrap.get_children():
		_content_wrap.remove_child(c)
		c.queue_free()
	_content_wrap.add_child(node)
