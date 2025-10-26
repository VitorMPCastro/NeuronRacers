extends Resource
class_name DataFieldDef

@export var title: String = ""            # Optional label to show on the left
@export var query_path: String = ""       # DataBroker path; use "#rank" for rank virtual field
@export var prefix: String = ""
@export var suffix: String = ""
@export var decimals: int = 2
@export var show_title: bool = true
@export var align_right: bool = true
@export var color: Color = Color(1, 1, 1, 1)
@export var font_size: int = 16
@export var weight: float = 1.0           # layout weight in the row
@export var visible_if: String = ""       # optional DataBroker path; hide if falsy

static func make_default_car_fields() -> Array[DataFieldDef]:
	var arr: Array[DataFieldDef] = []

	var f_rank := DataFieldDef.new()
	f_rank.title = "#"
	f_rank.query_path = "#rank"            # special
	f_rank.show_title = false
	f_rank.align_right = true
	f_rank.font_size = 18
	arr.append(f_rank)

	var f_name := DataFieldDef.new()
	f_name.title = "Pilot"
	f_name.query_path = "car_data.pilot.get_full_name()"
	f_name.show_title = false
	f_name.font_size = 18
	f_name.weight = 2.0
	arr.append(f_name)

	var f_speed := DataFieldDef.new()
	f_speed.title = "Speed"
	f_speed.query_path = "speed"           # DataBroker fast path
	f_speed.suffix = " px/s"
	f_speed.decimals = 0
	arr.append(f_speed)

	var f_fit := DataFieldDef.new()
	f_fit.title = "Fitness"
	f_fit.query_path = "car_data.fitness"
	f_fit.decimals = 2
	arr.append(f_fit)

	var f_time := DataFieldDef.new()
	f_time.title = "Alive"
	f_time.query_path = "car_data.time_alive"
	f_time.suffix = " s"
	f_time.decimals = 2
	arr.append(f_time)

	var f_checks := DataFieldDef.new()
	f_checks.title = "Checkpoints"
	f_checks.query_path = "total_checkpoints"
	f_checks.decimals = 0
	arr.append(f_checks)

	var f_sec1 := DataFieldDef.new()
	f_sec1.title = "Sector 1"
	f_sec1.query_path = "get_sector_time(1)"
	f_sec1.suffix = " s"
	f_sec1.decimals = 2
	arr.append(f_sec1)

	var f_sec2 := DataFieldDef.new()
	f_sec2.title = "Sector 2"
	f_sec2.query_path = "get_sector_time(2)"
	f_sec2.suffix = " s"
	f_sec2.decimals = 2
	arr.append(f_sec2)

	var f_sec3 := DataFieldDef.new()
	f_sec3.title = "Sector 3"
	f_sec3.query_path = "get_sector_time(3)"
	f_sec3.suffix = " s"
	f_sec3.decimals = 2
	arr.append(f_sec3)

	return arr
