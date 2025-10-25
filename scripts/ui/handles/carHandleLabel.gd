extends Node2D
class_name CarHandleLabel

@export_group("Appearance")
@export var offset: Vector2 = Vector2(72, -48)   # label position relative to car center (in world space)
@export var padding: Vector2 = Vector2(8, 4)
@export var bg_color: Color = Color(0, 0, 0, 0.65)
@export var border_color: Color = Color(1, 1, 1, 0.25)
@export var text_color: Color = Color(1, 1, 1, 1)
@export var line_color: Color = Color(1, 1, 1, 0.5)
@export var border_width: float = 1.5
@export var corner_radius: float = 6.0
@export var font_size: int = 16
@export var font_resource: Font   # assign a Font in the editor (fallback for drawing)

@export_group("Data")
@export var name_path: String = "car_data.pilot.get_full_name()"

var car: Car = null
var _db: DataBroker = null
var _rank_provider: Callable = Callable()   # Callable(car: Car) -> int

func _ready() -> void:
	set_process(true)
	_db = get_tree().get_root().find_child("DataBroker", true, false) as DataBroker

func set_car(c: Car) -> void:
	car = c
	queue_redraw()

# Optional: HUD provides a rank function
func set_rank_provider(fn: Callable) -> void:
	_rank_provider = fn
	queue_redraw()

func _process(_delta: float) -> void:
	if car and is_instance_valid(car):
		global_position = car.global_position
		queue_redraw()
	else:
		# Hide offscreen when no car
		global_position = Vector2.ZERO

func _draw() -> void:
	if car == null or !is_instance_valid(car):
		return

	# Resolve data using DataBroker (pilot name)
	var pilot_name := "Unknown"
	if _db:
		var v = _db.get_value(car, name_path)
		if typeof(v) == TYPE_STRING:
			pilot_name = String(v)

	# Resolve rank via provider if available
	var rank_text := ""
	if _rank_provider.is_valid():
		var r := int(_rank_provider.call(car))
		if r > 0:
			rank_text = "%d. " % r

	var text := "%s%s" % [rank_text, pilot_name]
	# Compute rect for text at offset
	var font = font_resource
	if font == null:
		return
	var size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var rect_pos := offset
	var rect_size = size + padding * 2.0
	var rect := Rect2(rect_pos, rect_size)

	# Line from rect top-left to car center (0,0)
	draw_line(rect_pos, Vector2.ZERO, line_color, 1.2)

	# Background (rounded) and border
	_draw_rounded_rect(rect, bg_color)
	_draw_rounded_rect_outline(rect, border_color, border_width)

	# Text
	var baseline := rect_pos + padding + Vector2(0, size.y) - Vector2(0, 3) # slight upshift for nicer baseline
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)

func _draw_rounded_rect(r: Rect2, col: Color) -> void:
	# Cheap rounded rect: fill as rect, then draw four quarter-circles (good enough for debug)
	draw_rect(r, col, true)
	if corner_radius <= 0.0:
		return
	var rad := corner_radius
	var corners := [
		[r.position + Vector2(rad, rad), 180.0, 270.0],                        # TL
		[Vector2(r.position.x + r.size.x - rad, r.position.y + rad), 270.0, 360.0], # TR
		[Vector2(r.position.x + r.size.x - rad, r.position.y + r.size.y - rad), 0.0, 90.0], # BR
		[Vector2(r.position.x + rad, r.position.y + r.size.y - rad), 90.0, 180.0],   # BL
	]
	# You can skip filling arcs for performance; background rect is usually enough.

func _draw_rounded_rect_outline(r: Rect2, col: Color, width: float) -> void:
	# Simple outline box (rounded rendering can be complex; keep it minimal)
	draw_rect(r, col, false, width)
