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

	var f_speed := DataFieldDef.new()
	f_speed.title = "Speed"
	f_speed.query_path = "speed_kmh"           # DataBroker fast path
	f_speed.suffix = " km/h"
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

	var f_lap := DataFieldDef.new()
	f_lap.title = "Lap"
	f_lap.query_path = "lap"
	f_lap.decimals = 0
	arr.append(f_lap)

	var f_lap_time := DataFieldDef.new()
	f_lap_time.title = "Lap Time"
	f_lap_time.query_path = "lap_time"
	f_lap_time.decimals = 2
	arr.append(f_lap_time)

	# Current lap sector times
	for i in range(1, 4):
		var f := DataFieldDef.new()
		f.title = "Sector %d" % i
		f.query_path = "get_sector_time(%d)" % i
		f.suffix = " s"
		f.decimals = 2
		arr.append(f)

	# Previous lap sector times
	for i in range(1, 4):
		var fp := DataFieldDef.new()
		fp.title = "Prev S%d" % i
		fp.query_path = "get_sector_time_prev(%d)" % i
		fp.suffix = " s"
		fp.decimals = 2
		arr.append(fp)

	return arr
