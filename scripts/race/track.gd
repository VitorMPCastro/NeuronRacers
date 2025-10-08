extends Node2D
class_name Track

# Public editable properties
@export var track_width := 128.0
@export var asphalt_texture: Texture2D = null
var border_texture_a: Texture2D = null
var border_texture_b: Texture2D = null
var polygon_node: Polygon2D = null
var length: float = 0.0
var debug_show_lines: bool = false
var debug_show_polygons: bool = false

# Convenience helper to free the generated polygon
func free_polygon() -> void:
	if polygon_node and polygon_node.is_inside_tree():
		polygon_node.queue_free()
		polygon_node = null

# Draws a Line2D along the given Path2D's curve for quick visualization.
# Returns the created Line2D (or null on failure).
func draw_centerline(path: Path2D, step: float = 4.0, color: Color = Color(0, 0, 0, 0), line_width: float = 0.0, cubic: bool = false) -> Line2D:
	if path == null or path.curve == null:
		return null
	var curve := path.curve
	if step <= 0.0:
		step = 16.0

	# Ensure baked cache density is reasonable for the requested step.
	curve.bake_interval = max(1.0, step * 0.5)

	var total := curve.get_baked_length()
	if total <= 0.0:
		return null

	var pts := PackedVector2Array()
	var d := 0.0
	while d < total:
		pts.append(curve.sample_baked(d, cubic))
		d += step
	pts.append(curve.sample_baked(total, cubic))

	var line := Line2D.new()
	line.points = pts
	line.width = line_width
	line.default_color = color
	line.antialiased = true
	# Close the line if the curve endpoints meet.
	if pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < step * 0.75:
		line.closed = true

	# Place it under the Path2D so local space matches.
	var parent: Node = path
	if polygon_node and is_instance_valid(polygon_node) and polygon_node.get_parent():
		parent = polygon_node.get_parent()
	parent.add_child(line)
	line.owner = parent.owner
	line.z_as_relative = false
	line.z_index = parent.z_index + 1
	line.name = "TrackCenterline"
	return line

func draw_offset_from_line(line: Line2D, offset: float, width: float = 0, color: Color = Color(0, 0, 0, 0)) -> Line2D:
	if !is_instance_valid(line) or line.points.size() < 2:
		push_error("Track.draw_offset_from_line: invalid line")
		return null

	var pts: PackedVector2Array = line.points
	var n := pts.size()
	var closed := line.closed
	if not closed and n > 2 and pts[0].distance_to(pts[n - 1]) < 1.0:
		closed = true

	var out_pts := PackedVector2Array()
	out_pts.resize(n)

	for i in range(n):
		var p: Vector2 = pts[i]
		var i_prev = (i - 1 + n) % n if closed else max(0, i - 1)
		var i_next = (i + 1) % n if closed else min(n - 1, i + 1)

		var tangent := pts[i_next] - pts[i_prev]
		if tangent.length_squared() == 0.0:
			tangent = Vector2.RIGHT
		else:
			tangent = tangent.normalized()

		var normal := Vector2(-tangent.y, tangent.x)
		out_pts[i] = p + normal * offset

	var offset_line := Line2D.new()
	var parent := self.find_child("LineParent")
	offset_line.points = out_pts
	offset_line.width = width
	offset_line.antialiased = true
	offset_line.default_color = color
	offset_line.z_as_relative = false
	offset_line.z_index = parent.z_index
	offset_line.name = "TrackOffsetLine"
	offset_line.closed = closed

	parent.add_child(offset_line)
	offset_line.owner = parent.owner

	return offset_line

func draw_quads_between_lines(line1: Line2D, line2: Line2D, texture: Texture2D = null) -> Array[Polygon2D]:
	var quads: Array[Polygon2D] = []
	
	if !is_instance_valid(line1) || !is_instance_valid(line2):
		push_error("Track.draw_quad: invalid line(s)")
		return quads
	if line1.points.size() != line2.points.size():
		push_error("Track.draw_quad: line point counts do not match")
		return quads
	if line1.points.size() < 2:
		push_error("Track.draw_quad: not enough points in lines")
		return quads

	for i in range(line1.points.size() - 1):
		var p1a = line1.points[i]
		var p1b = line1.points[i + 1]
		var p2a = line2.points[i]
		var p2b = line2.points[i + 1]

		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([p1a, p1b, p2b, p2a])
		if texture:
			poly.texture = texture

		self.find_child("PolygonParent").add_child(poly)
		quads.append(poly)

	return quads

# Static builder that generates a track polygon around a Path2D.
# Returns a Track or null on failure.
func build_from_path(path: Path2D, width: float = 128.0, tex: Texture2D = null, sample_step: float = 32.0, use_cubic_sampling: bool = false, treat_as_loop: bool = true, z_index: int = 1000) -> Track:
	if path == null:
		push_error("Track.build_from_path: path is null")
		return null

	var half := width/2
	var poly_points := PackedVector2Array([
		Vector2(-half, -half),
		Vector2( half, -half),
		Vector2( half,  half),
		Vector2(-half,  half),
	])

	var poly_node := Polygon2D.new()
	poly_node.polygon = poly_points
	if tex:
		poly_node.texture = tex
	poly_node.z_as_relative = false
	poly_node.z_index = z_index
	poly_node.modulate = Color(1, 0, 0, 1)
	poly_node.name = "DebugSquare1000"

	# Place at the Path2D's origin by parenting under it (local coords).
	path.add_child(poly_node)
	poly_node.owner = path.owner

	# Length is arbitrary for this debug square; set to perimeter or 0.
	self.polygon_node = poly_node
	self.track_width = width
	return self
