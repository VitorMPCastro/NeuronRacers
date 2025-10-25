extends Node2D
class_name CarHandleLineOverlay

@export var line_color: Color = Color(1, 1, 1, 0.6)
@export var line_width: float = 3.5

var camera: Camera2D
var car: Node2D
var panel_screen_top_left: Vector2 = Vector2.ZERO

func set_refs(cam: Camera2D, car_node: Node2D) -> void:
	camera = cam
	car = car_node

func set_panel_screen_top_left(p: Vector2) -> void:
	panel_screen_top_left = p

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if camera == null or !is_instance_valid(camera):
		return
	if car == null or !is_instance_valid(car):
		return

	# Convert panel screen point -> world (no Camera2D.screen_to_world in Godot 4)
	var panel_world := _screen_to_world(panel_screen_top_left)
	var car_world := car.global_position

	# Draw in overlay local
	var a := to_local(panel_world)
	var b := to_local(car_world)
	draw_line(a, b, line_color, line_width, true)

func _screen_to_world(s: Vector2) -> Vector2:
	# screen = S * C * world  =>  world = (S * C)^-1 * screen
	var vp := get_viewport()
	var to_screen: Transform2D = vp.get_screen_transform() * vp.get_canvas_transform()
	return to_screen.affine_inverse() * s
