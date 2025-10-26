extends HBoxContainer
class_name DataField

@export var def: DataFieldDef

var _title_lbl: Label
var _value_lbl: Label

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_title_lbl = Label.new()
	_value_lbl = Label.new()
	add_child(_title_lbl)
	add_child(_value_lbl)
	_title_lbl.visible = false
	_value_lbl.text = "—"
	_apply_def()

func set_def(d: DataFieldDef) -> void:
	def = d
	if _title_lbl != null and _value_lbl != null:
		_apply_def()

func _apply_def() -> void:
	if def == null or _title_lbl == null or _value_lbl == null:
		return
	_title_lbl.visible = def.show_title and def.title != ""
	_title_lbl.text = def.title
	_value_lbl.modulate = def.color
	# Layout and alignment
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_stretch_ratio = max(0.001, def.weight)
	_value_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if def.align_right else HORIZONTAL_ALIGNMENT_LEFT
	# Font size (fallback with theme override)
	_title_lbl.add_theme_font_size_override("font_size", def.font_size)
	_value_lbl.add_theme_font_size_override("font_size", def.font_size)

func render(value: Variant) -> void:
	if def == null or _value_lbl == null:
		return
	var txt := ""
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			var v := float(value)
			txt = def.prefix + (("%%.%df" % def.decimals) % v) + def.suffix
		TYPE_BOOL:
			txt = def.prefix + (("1" if value else "0")) + def.suffix
		_:
			txt = def.prefix + str(value) + def.suffix
	_value_lbl.text = txt

func set_faded(faded: bool, alpha: float = 0.35) -> void:
	if _title_lbl == null or _value_lbl == null:
		return
	var base := def.color if def else Color(1,1,1,1)
	var col := base
	col.a = (alpha if faded else base.a)
	_value_lbl.modulate = col
	_title_lbl.modulate = Color(1,1,1, alpha if faded else 1.0)
