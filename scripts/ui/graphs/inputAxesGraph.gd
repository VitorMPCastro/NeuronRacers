extends Control
class_name InputAxesGraph

@export_group("Data")
@export var throttle_path: String = "_ctrl_throttle"
@export var brake_path: String = "_ctrl_brake"
@export var steer_path: String = "_ctrl_steer"

@export_group("Appearance")
@export var padding: float = 8.0
@export var stroke_color: Color = Color(0.2, 0.2, 0.2, 1.0)
@export var bg_color: Color = Color(0.08, 0.08, 0.08, 1.0)
@export var fill_side: Color = Color(0.35, 0.7, 1.0, 0.9)     # shared color for both steer triangles
@export var fill_top: Color = Color(0.3, 1.0, 0.3, 0.9)       # throttle
@export var fill_bottom: Color = Color(1.0, 0.3, 0.3, 0.9)    # brake
@export var shape_line_width: float = 2.0
@export var auto_update: bool = true
@export var aspect_ratio: float = 2.0    # width:height for the whole widget drawing area

var _car: Node = null
var _broker: DataBroker = null

func _ready() -> void:
	custom_minimum_size = Vector2(240, 160)  # ensure it gets space
	_broker = get_tree().get_root().find_child("DataBroker", true, false) as DataBroker
	set_process(auto_update)

func set_car(car: Node) -> void:
	_car = car
	queue_redraw()

func _process(_delta: float) -> void:
	if auto_update:
		queue_redraw()

func _get_value(path: String, fallback_prop: String, default_val: float = 0.0) -> float:
	if _car == null:
		return default_val
	if is_instance_valid(_broker):
		var v = _broker.get_value(_car, path)
		match typeof(v):
			TYPE_INT, TYPE_FLOAT:
				return float(v)
	# Fallback to direct property by name (numeric only)
	var maybe = _car.get(fallback_prop)
	if typeof(maybe) == TYPE_INT or typeof(maybe) == TYPE_FLOAT:
		return float(maybe)
	return default_val

func _fetch_axes() -> Dictionary:
	# Preferred: standardized car API
	if _car and _car.has_method("get_control_axes"):
		var d = _car.get_control_axes()
		if typeof(d) == TYPE_DICTIONARY:
			return {
				"throttle": clamp(float(d.get("throttle", 0.0)), 0.0, 1.0),
				"brake": clamp(float(d.get("brake", 0.0)), 0.0, 1.0),
				"steer_left": max(0.0, -float(d.get("steer", 0.0))),
				"steer_right": max(0.0, float(d.get("steer", 0.0))),
			}

	# Fallback: DataBroker / property names
	var throttle := _get_value(throttle_path, "_ctrl_throttle", 0.0)
	var brake := _get_value(brake_path, "_ctrl_brake", 0.0)
	var steer := _get_value(steer_path, "_ctrl_steer", 0.0)

	if brake == 0.0 and throttle < 0.0:
		brake = -throttle
	if throttle < 0.0:
		throttle = 0.0

	return {
		"throttle": clamp(throttle, 0.0, 1.0),
		"brake": clamp(brake, 0.0, 1.0),
		"steer_left": max(0.0, -clamp(steer, -1.0, 1.0)),
		"steer_right": max(0.0, clamp(steer, -1.0, 1.0)),
	}

func _draw() -> void:
	# Compute padded area
	var bounds := Rect2(Vector2.ZERO, size)
	var padded := bounds.grow(-padding)

	# Lock aspect ratio for the drawing area
	var ar = max(0.1, aspect_ratio)
	var avail := padded.size
	var target_w := avail.x
	var target_h = target_w / ar
	if target_h > avail.y:
		target_h = avail.y
		target_w = target_h * ar
	var draw_pos := padded.position + (avail - Vector2(target_w, target_h)) * 0.5
	var inner := Rect2(draw_pos, Vector2(target_w, target_h))

	if inner.size.x < 50 or inner.size.y < 50:
		draw_string(get_theme_default_font(), Vector2(8, 18), "Inputs: area too small", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14.0, Color(1,1,1,0.6))
		return

	if _car == null:
		draw_string(get_theme_default_font(), inner.position + Vector2(8, 18), "No car selected", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14.0, Color(1,1,1,0.6))
		# Still draw background so user sees the widget
		draw_rect(inner, bg_color, true)

	# Layout: [left triangle] [stacked rects] [right triangle]
	var gap := 8.0
	var tri_w = max(24.0, inner.size.x * 0.3)
	var rect_w = max(24.0, inner.size.x - tri_w * 2.0 - gap * 2.0)
	var tri_h := inner.size.y

	var left_rect := Rect2(inner.position, Vector2(tri_w, tri_h))
	var mid_rect := Rect2(
		Vector2(inner.position.x + tri_w + gap, inner.position.y),
		Vector2(rect_w, tri_h)
	)
	var right_rect := Rect2(
		Vector2(inner.position.x + tri_w + gap + rect_w + gap, inner.position.y),
		Vector2(tri_w, tri_h)
	)

	# Backgrounds
	draw_rect(left_rect, bg_color, true)
	draw_rect(mid_rect, bg_color, true)
	draw_rect(right_rect, bg_color, true)

	var axes := _fetch_axes()

	# Middle stacked rects: top=throttle, bottom=brake (fill bottom-up)
	var mid_half_h := mid_rect.size.y * 0.5
	var rect_top := Rect2(mid_rect.position, Vector2(mid_rect.size.x, mid_half_h))
	var rect_bottom := Rect2(Vector2(mid_rect.position.x, mid_rect.position.y + mid_half_h), Vector2(mid_rect.size.x, mid_half_h))

	_draw_filled_rect(rect_top, axes["throttle"], fill_top)
	_draw_filled_rect(rect_bottom, axes["brake"], fill_bottom)

	# Triangles: fill from their base horizontally (left: right->left, right: left->right)
	_draw_left_triangle_horizontal(left_rect, axes["steer_left"], fill_side)
	_draw_right_triangle_horizontal(right_rect, axes["steer_right"], fill_side)

	# Borders
	draw_rect(left_rect, stroke_color, false, shape_line_width)
	draw_rect(mid_rect, stroke_color, false, shape_line_width)
	draw_rect(right_rect, stroke_color, false, shape_line_width)

func _draw_filled_rect(r: Rect2, frac: float, col: Color) -> void:
	frac = clamp(frac, 0.0, 1.0)
	if frac <= 0.0:
		return
	var h := r.size.y * frac
	var fill_rect := Rect2(Vector2(r.position.x, r.position.y + r.size.y - h), Vector2(r.size.x, h))
	draw_rect(fill_rect, col, true)

# Left triangle points left. Base is the vertical right edge. Fill grows right->left.
func _draw_left_triangle_horizontal(b: Rect2, frac: float, col: Color) -> void:
	frac = clamp(frac, 0.0, 1.0)
	# Outline triangle points
	var top_right := Vector2(b.position.x + b.size.x, b.position.y)
	var bottom_right := Vector2(b.position.x + b.size.x, b.position.y + b.size.y)
	var apex_left := Vector2(b.position.x, b.position.y + b.size.y * 0.5)
	var tri := PackedVector2Array([top_right, bottom_right, apex_left])

	# Fill polygon (horizontal clip from base)
	if frac > 0.0:
		if frac >= 1.0:
			draw_colored_polygon(tri, col)
		else:
			var x_base := top_right.x
			var x_apex := apex_left.x
			var x_clip = lerp(x_base, x_apex, frac)  # move from base to apex with frac

			# Intersection with edges apex->top_right and apex->bottom_right at x_clip
			var br := bottom_right
			var tr := top_right
			var ax := apex_left

			var t_bottom = (x_clip - ax.x) / (br.x - ax.x)
			var p_bottom := ax.lerp(br, t_bottom)

			var t_top = (x_clip - ax.x) / (tr.x - ax.x)
			var p_top := ax.lerp(tr, t_top)

			var poly := PackedVector2Array([bottom_right, p_bottom, p_top, top_right])
			draw_colored_polygon(poly, col)

	# Outline
	var outline := PackedVector2Array(tri)
	outline.push_back(tri[0])
	draw_polyline(outline, stroke_color, shape_line_width)

# Right triangle points right. Base is the vertical left edge. Fill grows left->right.
func _draw_right_triangle_horizontal(b: Rect2, frac: float, col: Color) -> void:
	frac = clamp(frac, 0.0, 1.0)
	# Outline triangle points
	var top_left := Vector2(b.position.x, b.position.y)
	var bottom_left := Vector2(b.position.x, b.position.y + b.size.y)
	var apex_right := Vector2(b.position.x + b.size.x, b.position.y + b.size.y * 0.5)
	var tri := PackedVector2Array([top_left, apex_right, bottom_left])

	# Fill polygon (horizontal clip from base)
	if frac > 0.0:
		if frac >= 1.0:
			draw_colored_polygon(tri, col)
		else:
			var x_base := top_left.x
			var x_apex := apex_right.x
			var x_clip = lerp(x_base, x_apex, frac)  # move from base to apex with frac

			# Intersection with edges apex->top_left and apex->bottom_left at x_clip
			var tl := top_left
			var bl := bottom_left
			var ax := apex_right

			var t_top = (x_clip - tl.x) / (ax.x - tl.x)
			var p_top := tl.lerp(ax, t_top)

			var t_bottom = (x_clip - bl.x) / (ax.x - bl.x)
			var p_bottom := bl.lerp(ax, t_bottom)

			var poly := PackedVector2Array([bottom_left, p_bottom, p_top, top_left])
			draw_colored_polygon(poly, col)

	# Outline
	var outline := PackedVector2Array(tri)
	outline.push_back(tri[0])
	draw_polyline(outline, stroke_color, shape_line_width)
