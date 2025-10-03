extends RefCounted
class_name Track

# Backing field for read-only length
var _length := 0.0

# Public editable properties
@export var track_width := 128.0
@export var texture : Texture = null
var polygon_node : Polygon2D = null
var length : float = 0.0

func _init(polygon: Polygon2D = null, width: float = 128.0, tex: Texture = null, length_val: float = 0.0) -> void:
	polygon_node = polygon
	track_width = width
	texture = tex
	_length = length_val

# Convenience helper to free the generated polygon
func free_polygon() -> void:
	if polygon_node and polygon_node.is_inside_tree():
		polygon_node.queue_free()
		polygon_node = null
