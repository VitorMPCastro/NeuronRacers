extends Node2D
class_name Track

# Public editable properties
@export var track_width := 128.0
@export var track_checkpoints := 30
@export var track_sectors := 3
@export var asphalt_texture: Texture2D = null
@export var curb_texture: Texture2D = null
var border_texture_a: Texture2D = null
var border_texture_b: Texture2D = null
var polygon_node: Polygon2D = null
var length: float = 0.0
var center_line: Line2D = null
var left_line: Line2D = null
var right_line: Line2D = null
var curb_right: Line2D = null
var curb_left: Line2D = null
var asphalt: Array[Polygon2D] = []
var track_limits_left: Array[Polygon2D] = []
var track_limits_right: Array[Polygon2D] = []
var track_data: TrackData = null

# signal
signal track_built

func _ready() -> void:
	# Connect the track_built signal to the TrackManager
	track_built.connect(get_parent().get_node("TrackManager")._on_track_built)
	track_built.connect(_on_track_built)

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
func build_from_path(path: Path2D, width: float = 128.0, curb_thickness: float = 8.0, tex: Texture2D = null, sample_step: float = 32.0, use_cubic_sampling: bool = false, treat_as_loop: bool = true, z_index: int = 1000) -> Track:
	if path == null:
		push_error("Track.build_from_path: path is null")
		return null

	center_line = self.draw_centerline(path, sample_step, Color(1, 0, 0, 0), 0.0, use_cubic_sampling)
	left_line = self.draw_offset_from_line(center_line, -width / 2, 0.0)
	right_line = self.draw_offset_from_line(center_line, width / 2, 0.0)
	curb_left = self.draw_offset_from_line(left_line, -curb_thickness, 0.0, Color(1, 1, 1, 1))
	curb_right = self.draw_offset_from_line(right_line, curb_thickness, 0.0, Color(1, 1, 1, 1))

	if !is_instance_valid(center_line) or !is_instance_valid(left_line) or !is_instance_valid(right_line):
		push_error("Track.build_from_path: failed to create center or offset lines")
		return null


	track_limits_left = self.draw_quads_between_lines(curb_left, left_line)
	track_limits_right = self.draw_quads_between_lines(right_line, curb_right)

	add_collision_to_polygons(track_limits_left)
	add_collision_to_polygons(track_limits_right)

	track_built.emit()


	return self

func toggle_show_lines(debug_show_lines: bool) -> void:
	print("Track.toggle_show_lines: ", debug_show_lines)
	print(" center_line: ", is_instance_valid(center_line))
	print(" left_line: ", is_instance_valid(left_line))
	print(" right_line: ", is_instance_valid(right_line))
	print(" curb_left: ", is_instance_valid(curb_left))
	print(" curb_right: ", is_instance_valid(curb_right))
	if is_instance_valid(center_line):
		center_line.visible = debug_show_lines
		center_line.width = 4.0 if debug_show_lines else 0.0
		center_line.default_color = Color(1, 0, 0, 1) if debug_show_lines else Color(0, 0, 0, 0)
	if is_instance_valid(left_line):
		left_line.visible = debug_show_lines
		left_line.width = 2.0 if debug_show_lines else 0.0
		left_line.default_color = Color(0, 0, 1, 1) if debug_show_lines else Color(0, 0, 0, 0)
	if is_instance_valid(right_line):
		right_line.visible = debug_show_lines
		right_line.width = 2.0 if debug_show_lines else 0.0
		right_line.default_color = Color(0, 1, 0, 1) if debug_show_lines else Color(0, 0, 0, 0)
	if is_instance_valid(curb_left):
		curb_left.visible = debug_show_lines
		curb_left.width = 2.0 if debug_show_lines else 0.0
		curb_left.default_color = Color(1, 1, 1, 1) if debug_show_lines else Color(0, 0, 0, 0)
	if is_instance_valid(curb_right):
		curb_right.visible = debug_show_lines
		curb_right.width = 2.0 if debug_show_lines else 0.0
		curb_right.default_color = Color(1, 1, 1, 1) if debug_show_lines else Color(0, 0, 0, 0)

func add_collision_to_polygons(polygons: Array[Polygon2D]) -> void:
	for poly in polygons:
		if !is_instance_valid(poly):
			continue

		# Create a StaticBody2D as the collision owner
		var body := StaticBody2D.new()
		body.name = "%s_StaticBody2D" % poly.name
		# Place it alongside the visual polygon so transforms match
		var parent := poly.get_parent()
		parent.add_child(body)
		body.owner = parent.owner
		# Copy transform (if your polygons have local transforms)
		body.position = poly.position
		body.rotation = poly.rotation
		body.scale = poly.scale

		# Configure collision layers/masks:
		# Walls on layer 1, collide with layer 2 (cars)
		body.collision_layer = 0
		body.collision_mask = 0
		body.set_collision_layer_value(1, true) # this object is on layer 1
		body.set_collision_mask_value(2, true)  # it collides with layer 2

		# Add shape
		var coll := CollisionPolygon2D.new()
		coll.polygon = poly.polygon
		body.add_child(coll)
		coll.owner = body.owner
		coll.disabled = false

func _on_track_built() -> void:
	if track_data == null:
		track_data = self.find_child("TrackData") as TrackData
		track_data.track = self
		track_data.center_line = center_line
		track_data.calculate_track_length()
		track_data.divide_sectors()
		track_data.generate_checkpoints()
		for sector in track_data.sectors.values():
			print("Sector from index %d to %d, length: %.2f" % [sector.start_index, sector.end_index, sector.sector_length])
