extends Node2D
class_name HighlightAura

@export var radius: float = 80.0
@export var width: float = 12.0
@export var color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var pulse: bool = true
@export var pulse_speed: float = 2.0
@export var pulse_amplitude: float = 6.0
@export var antialiased: bool = true

var color_outer_soft
var color_inner_bright
var color_center_dot

var _t := 0.0

func _ready() -> void:
	color_outer_soft = color
	color_inner_bright = color
	color_center_dot = color

	color_outer_soft.a = color.a * 0.25
	color_inner_bright.a = color.a * 0.9
	color_center_dot.a = color.a * 0.6

func _process(delta: float) -> void:
	if pulse:
		_t += delta
		queue_redraw()

func _draw() -> void:
	var r := radius + (sin(_t * TAU * 0.16 * pulse_speed) * pulse_amplitude if pulse else 0.0)
	# Outer soft ring
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, color_outer_soft, width * 2.0, antialiased)
	# Inner bright ring
	draw_arc(Vector2.ZERO, r * 0.86, 0.0, TAU, 64, color_inner_bright, width, antialiased)
	# Center dot (subtle)
	draw_circle(Vector2.ZERO, max(2.0, width * 0.25), color_center_dot)
