extends Label
class_name LeaderboardField

@export var field_name: String = ""                 # Display name (also used for sorting)
@export var query_path: String = ""                 # Path resolved via CarTelemetry/DataBroker
@export var format: String = "{value}"
@export var decimals: int = 2

# Column layout
@export var column_weight: float = 1.0              # Relative width
@export var min_width: int = 100                    # Minimum column width (px)
@export var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT

var last_value: Variant = null

func _ready() -> void:
	# Make this label behave like a table cell
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_stretch_ratio = max(0.001, column_weight)
	custom_minimum_size.x = min_width
	horizontal_alignment = align
	clip_text = true

func render(value: Variant) -> void:
	last_value = value
	var text_out := ""
	match typeof(value):
		TYPE_FLOAT:
			text_out = ("%." + str(max(0, decimals)) + "f") % float(value)
		TYPE_INT:
			text_out = str(int(value))
		_:
			text_out = str(value)
	self.text = format.replacen("{value}", text_out)

func comparable_value() -> Variant:
	# Prefer numeric compare when possible
	if typeof(last_value) == TYPE_STRING:
		var s := str(last_value)
		if s.is_valid_float():
			return s.to_float()
		if s.is_valid_int():
			return s.to_int()
	return last_value