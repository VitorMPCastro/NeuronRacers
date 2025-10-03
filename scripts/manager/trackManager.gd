extends Node2D
class_name TrackManager

@export var sample_step: float = 32.0        # Distance in pixels between samples along the curve
@export var use_baked: bool = true
@export var use_cubic_sampling: bool = false # Pass true to sample_baked() for cubic interpolation
@export var treat_as_loop: bool = true       # If true and endpoints are near, smooth tangents across seam

# Main generator. Returns a Track instance or null on failure.
func generate_track_from_path(path: Path2D, width: float = 128.0, tex: Texture2D = null) -> Track:
	if path == null:
		push_error("generate_track_from_path: path is null")
		return null
	var curve: Curve2D = path.curve
	if curve == null:
		push_error("generate_track_from_path: Path2D has no curve")
		return null

	# Force (re)build of baked cache by touching bake_interval before querying baked length
	if use_baked:
		curve.bake_interval = max(1.0, sample_step * 0.25)
	var total_length := curve.get_baked_length()
	if total_length <= 0.0:
		push_error("generate_track_from_path: curve has zero length")
		return null

	# Sample offsets along curve
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var d := 0.0
	while d < total_length:
		offsets.append(d)
		d += sample_step
	offsets.append(total_length)

	# Gather centerline points
	var samples := PackedVector2Array()
	for off in offsets:
		samples.append(curve.sample_baked(off, use_cubic_sampling))

	# Detect loop (optional)
	var is_loop := false
	if treat_as_loop and samples.size() > 2:
		if samples[0].distance_to(samples[samples.size() - 1]) < width * 0.5:
			is_loop = true

	var half_w := width * 0.5
	var left_points: Array = []
	var right_points: Array = []

	for i in range(samples.size()):
		var p: Vector2 = samples[i]

		var prev_i := i - 1
		var next_i := i + 1
		if prev_i < 0:
			prev_i = samples.size() - 2 if is_loop else 0
		if next_i >= samples.size():
			next_i = 1 if is_loop else samples.size() - 1

		var prev_p: Vector2 = samples[prev_i]
		var next_p: Vector2 = samples[next_i]

		var tangent := (next_p - prev_p)
		if tangent.length_squared() == 0.0:
			tangent = Vector2.RIGHT
		else:
			tangent = tangent.normalized()

		var normal := Vector2(-tangent.y, tangent.x)
		left_points.append(p + normal * half_w)
		right_points.append(p - normal * half_w)

	# Build polygon (strip)
	var poly_points := PackedVector2Array()
	for lp in left_points:
		poly_points.append(lp)
	for j in range(right_points.size() - 1, -1, -1):
		poly_points.append(right_points[j])

	var poly_node := Polygon2D.new()
	poly_node.polygon = poly_points
	if tex:
		poly_node.texture = tex

	path.add_child(poly_node)
	poly_node.owner = path.owner
	poly_node.name = "GeneratedTrackPolygon"

	var track := Track.new(poly_node, width, tex, total_length)
	return track
