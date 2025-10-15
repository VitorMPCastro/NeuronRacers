extends Resource
class_name LeaderboardColumn

@export var title: String = ""                       # Header text (e.g., "Pilot", "Fitness", "#")
@export var query_path: String = ""                  # Data path (empty = computed column like "#")
@export var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
@export var weight: float = 1.0                      # HBox stretch ratio
@export var min_width: int = 100
@export var decimals: int = 2
@export var format: String = "{value}"

static func make_default_columns() -> Array[LeaderboardColumn]:
	var out: Array[LeaderboardColumn] = []

	var c_rank := LeaderboardColumn.new()
	c_rank.title = "#"
	c_rank.query_path = ""  # computed column (set via set_rank)
	c_rank.align = HORIZONTAL_ALIGNMENT_RIGHT
	c_rank.weight = 0.5
	c_rank.min_width = 48
	out.append(c_rank)

	var c_pilot := LeaderboardColumn.new()
	c_pilot.title = "Pilot"
	c_pilot.query_path = "car_data.pilot.get_full_name()"
	c_pilot.align = HORIZONTAL_ALIGNMENT_LEFT
	c_pilot.weight = 2.0
	c_pilot.min_width = 200
	out.append(c_pilot)

	var c_fit := LeaderboardColumn.new()
	c_fit.title = "Fitness"
	c_fit.query_path = "car_data.fitness"
	c_fit.align = HORIZONTAL_ALIGNMENT_RIGHT
	c_fit.weight = 1.0
	c_fit.min_width = 120
	c_fit.decimals = 3
	out.append(c_fit)

	return out
