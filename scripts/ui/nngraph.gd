extends Control
class_name NeuralNetworkGraph

@export var refresh_interval_frames: int = 10
@export var padding: Vector2 = Vector2(24, 24)
@export var node_radius: float = 10.0
@export var layer_spacing: float = 140.0
@export var min_weight_color: Color = Color(0.1, 0.1, 0.8)
@export var zero_weight_color: Color = Color(0.3, 0.3, 0.3)
@export var max_weight_color: Color = Color(0.8, 0.1, 0.1)
@export var line_base_width: float = 2.0
@export var line_max_extra: float = 4.0

var observed_car: Car
var brain                       # MLP resource
var layer_sizes: Array[int] = []
var weights: Array = []         # Expect: Array[PackedFloat32Array] or Array[Array]
var node_positions: Array = []  # [ [Vector2, ...], ... ]
var frame_counter := 0

func _ready():
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _find_observed_car()
    _rebuild_graph()

func _process(_dt):
    frame_counter += 1
    if frame_counter % refresh_interval_frames == 0:
        var prev = observed_car
        _find_observed_car()
        if observed_car != prev:
            _rebuild_graph()
        queue_redraw()

func _find_observed_car():
    var cars = get_tree().get_nodes_in_group("cars")
    var candidate: Car = null
    for c in cars:
        if c.camera_follow:
            candidate = c
            break
    if candidate == null and cars.size() > 0:
        for c in cars:
            if c.is_player:
                candidate = c
                break
    if candidate == null and cars.size() > 0:
        candidate = cars[0]
    observed_car = candidate
    brain = observed_car.brain if observed_car else null

func _rebuild_graph():
    layer_sizes.clear()
    weights.clear()
    node_positions.clear()
    if not brain:
        return
    # Try common property names; adjust if your MLP differs.
    if brain.has_method("get_layer_sizes"):
        layer_sizes = brain.get_layer_sizes()
    elif "layer_sizes" in brain:
        layer_sizes = brain.layer_sizes
    elif "layers" in brain:
        # Fallback guess
        layer_sizes = brain.layers
    if brain.has_method("get_weights"):
        weights = brain.get_weights()
    elif "weights" in brain:
        weights = brain.weights
    if layer_sizes.is_empty():
        return
    # Compute node positions
    var total_layers = layer_sizes.size()
    var rect = get_size()
    if rect == Vector2.ZERO:
        rect = Vector2(600, 400)
    var usable_height = rect.y - padding.y * 2.0
    node_positions.resize(total_layers)
    for li in range(total_layers):
        var count = layer_sizes[li]
        var layer_y_start = padding.y
        var gap = 0.0
        if count > 1:
            gap = usable_height / float(count - 1)
        node_positions[li] = []
        var x = padding.x + li * layer_spacing
        for ni in range(count):
            var y = layer_y_start + gap * ni
            node_positions[li].append(Vector2(x, y))

func _draw():
    if not brain or layer_sizes.is_empty():
        draw_string(get_theme_default_font(), Vector2(10, 20), "No brain", HORIZONTAL_ALIGNMENT_LEFT, -1, 1, Color(1,0.4,0.4))
        return
    _draw_connections()
    _draw_nodes()
    _draw_header()

func _draw_header():
    var label = "Observed: %s" % (str(observed_car.name) if observed_car else "None")
    draw_string(get_theme_default_font(), Vector2(8, get_size().y - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 1, Color(0.8,0.8,0.8))

func _draw_nodes():
    for li in range(node_positions.size()):
        for p in node_positions[li]:
            draw_circle(p, node_radius, Color(0.9,0.9,0.9))
            draw_circle(p, node_radius * 0.7, Color(0.15,0.15,0.15))

func _draw_connections():
    # weights[i] should map layer i (source) to i+1 (target)
    for li in range(min(weights.size(), node_positions.size() - 1)):
        var w_matrix = weights[li]
        # Normalize access patterns (convert to 2D array if needed)
        for si in range(node_positions[li].size()):
            for ti in range(node_positions[li + 1].size()):
                var w = _get_weight(w_matrix, si, ti)
                var col = _weight_color(w)
                var width = line_base_width + line_max_extra * clamp(abs(w), 0.0, 1.0)
                draw_line(node_positions[li][si], node_positions[li + 1][ti], col, width)

func _get_weight(w_matrix, si: int, ti: int) -> float:
    # Try common conventions w[source][target]
    if typeof(w_matrix) == TYPE_ARRAY:
        if si < w_matrix.size():
            var row = w_matrix[si]
            if typeof(row) == TYPE_ARRAY and ti < row.size():
                return float(row[ti])
            elif typeof(row) == TYPE_PACKED_FLOAT32_ARRAY and ti < row.size():
                return row[ti]
    elif typeof(w_matrix) == TYPE_PACKED_FLOAT32_ARRAY:
        # If flattened, attempt index (si * next + ti)
        var next_count = node_positions[si + 1].size()
        var idx = si * next_count + ti
        if idx < w_matrix.size():
            return w_matrix[idx]
    return 0.0

func _weight_color(w: float) -> Color:
    # Map -1..0..1
    var clamped = clamp(w, -1.0, 1.0)
    if clamped > 0.0:
        return zero_weight_color.lerp(max_weight_color, clamped)
    elif clamped < 0.0:
        return zero_weight_color.lerp(min_weight_color, -clamped)
    return zero_weight_color

func force_refresh():
    _rebuild_graph()
    queue_redraw()