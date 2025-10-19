extends Node
class_name GenerationIO

static func save_to_json(path: String, generation: int, config: Dictionary, brains: Array[MLP]) -> bool:
	var payload := {
		"version": 2,
		"generation": generation,
		"nn": {
			"input": int(config.get("input", 0)),
			"hidden_layers": PackedInt32Array(config.get("hidden_layers", PackedInt32Array())),
			"output": int(config.get("output", 0))
		},
		"evolution": {
			"elitism_percent": float(config.get("elitism_percent", 0.2)),
			"mutate_chance": float(config.get("mutate_chance", 0.1)),
			"weight": float(config.get("weight", 0.3))
		},
		"ai_actions_per_second": float(config.get("ai_actions_per_second", 20.0)),
		"brains": brains.map(func(b: MLP) -> Dictionary: return b.to_dict())
	}
	var json := JSON.stringify(payload, "  ")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(json)
	file.close()
	return true

static func load_from_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data as Dictionary