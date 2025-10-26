extends Node
class_name DataBroker

# Cache: path -> tokens
var _path_cache: Dictionary = {}

func _ready() -> void:
	add_to_group("data_broker")

func get_many(provider: Object, paths: PackedStringArray) -> Array:
	var out: Array = []
	out.resize(paths.size())
	for i in range(paths.size()):
		out[i] = get_value(provider, paths[i])
	return out

func get_value(provider: Object, path: String) -> Variant:
	if provider == null or path.is_empty():
		return null

	# Fast paths
	if provider is Car:
		match path:
			"lap": return RaceProgressionManager.get_lap_static(provider)
			"lap_time": return RaceProgressionManager.get_lap_time_static(provider)
			"speed_kmh": return (provider as Car).velocity.length() / 10.0
			"get_sector_time(1)": return RaceProgressionManager.get_sector_time_static(provider, 1)
			"get_sector_time(2)": return RaceProgressionManager.get_sector_time_static(provider, 2)
			"get_sector_time(3)": return RaceProgressionManager.get_sector_time_static(provider, 3)
			"get_sector_time_prev(1)": return RaceProgressionManager.get_sector_time_prev_static(provider, 1)
			"get_sector_time_prev(2)": return RaceProgressionManager.get_sector_time_prev_static(provider, 2)
			"get_sector_time_prev(3)": return RaceProgressionManager.get_sector_time_prev_static(provider, 3)
			"car_data.fitness": return (provider as Car).fitness
			"car_data.time_alive": return (provider as Car).time_alive
			"total_checkpoints": return RaceProgressionManager.get_checkpoint_count_static(provider)
			"distance_to_next_checkpoint": return RaceProgressionManager.get_distance_to_next_checkpoint_static(provider)
			"speed", "velocity.length", "velocity.length()": return (provider as Car).velocity.length()
			"velocity.x": return (provider as Car).velocity.x
			"velocity.y": return (provider as Car).velocity.y
			"car_data.pilot.get_full_name()":
				var p = (provider as Car).car_data.pilot
				return p.get_full_name() if p and p.has_method("get_full_name") else ""
			_: pass

	# Dynamic path: obj.prop or obj.method(args) chaining
	var tokens: Array = _compile_path(path)
	var cur: Variant = provider
	for t in tokens:
		if cur == null:
			return null
		var tok := t as Token
		if tok.is_call:
			if typeof(cur) == TYPE_OBJECT and (cur as Object).has_method(tok.token_name):
				cur = (cur as Object).callv(tok.token_name, tok.args) if tok.args.size() > 0 else (cur as Object).call(tok.token_name)
			elif typeof(cur) == TYPE_VECTOR2:
				match tok.token_name:
					"length": cur = (cur as Vector2).length()
					"length_squared": cur = (cur as Vector2).length_squared()
					"normalized": cur = (cur as Vector2).normalized()
					_: return null
			else:
				return null
		else:
			if typeof(cur) == TYPE_OBJECT:
				var obj := cur as Object
				if obj.has_method(tok.token_name):
					cur = obj.call(tok.token_name)  # zero-arg getter
				else:
					cur = obj.get(tok.token_name)
			elif typeof(cur) == TYPE_DICTIONARY:
				cur = (cur as Dictionary).get(tok.token_name, null)
			elif typeof(cur) == TYPE_VECTOR2:
				match tok.token_name:
					"x": cur = (cur as Vector2).x
					"y": cur = (cur as Vector2).y
					_: return null
			else:
				return null
	return cur

class Token:
	var token_name: String = ""
	var is_call: bool = false
	var args: Array = []

func _compile_path(path: String) -> Array:
	var cached = _path_cache.get(path)
	if cached != null:
		return cached
	var tokens: Array = []
	for part in path.split("."):
		var open_idx := part.find("(")
		var is_call := open_idx != -1 and part.ends_with(")")
		var tkn_name := part
		var args: Array = []
		if is_call:
			tkn_name = part.substr(0, open_idx)
			var inner := part.substr(open_idx + 1, part.length() - open_idx - 2)
			args = _parse_args(inner)
		var tok := Token.new()
		tok.token_name = tkn_name
		tok.is_call = is_call
		tok.args = args
		tokens.append(tok)
	_path_cache[path] = tokens
	return tokens

func _parse_args(s: String) -> Array:
	var args: Array = []
	if s.strip_edges() == "":
		return args
	for raw in s.split(","):
		var a := raw.strip_edges()
		if a == "true" or a == "false":
			args.append(a == "true")
		elif a.is_valid_int():
			args.append(int(a))
		elif a.is_valid_float():
			args.append(float(a))
		else:
			if (a.begins_with("'") and a.ends_with("'")) or (a.begins_with("\"") and a.ends_with("\"")):
				a = a.substr(1, a.length() - 2)
			args.append(a)
	return args
