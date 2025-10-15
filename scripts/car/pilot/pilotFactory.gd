extends Node
class_name PilotFactory

const PILOTS_FILE_PATH := "res://scripts/car/pilot/pilots.json"
static var first_names: Array[String] = []
static var last_names: Array[String] = []
static var numbers: Array[int] = []

func _ready() -> void:
	if !first_names or !last_names or !numbers:
		read_pilots_from_file()

static func read_pilots_from_file() -> void:
	var file = FileAccess.open(PILOTS_FILE_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open pilots file at path: %s" % PILOTS_FILE_PATH)
		return
	
	var data = JSON.parse_string(file.get_as_text())
	if !data:
		push_error("Error parsing JSON from pilots file: %s" % data.error_string)
		return

	var json = data as Dictionary
	if json.has("firstNames"):
		var names_array = json["firstNames"]
		for first_name in names_array:
			first_names.append(first_name)
	if json.has("lastNames"):
		var last_names_array = json["lastNames"]
		for last_name in last_names_array:
			last_names.append(last_name)
	if json.has("numbers"):
		var numbers_array = json["numbers"]
		for n in numbers_array:
			numbers.append(n as int)

	file.close()

static func create_random_pilot() -> Pilot:
	if !first_names or !last_names or !numbers:
		read_pilots_from_file()
	var first_name = first_names[randi() % first_names.size()]
	var last_name = last_names[randi() % last_names.size()]
	var number = numbers[randi() % numbers.size()]
	return Pilot.new(first_name, last_name, number)
