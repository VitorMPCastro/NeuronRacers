extends Node
class_name DataBroker

# Cache: path -> Array[Token]
var _path_cache: Dictionary = {}

func _ready() -> void:
	add_to_group("data_broker")

func get_many(provider: Object, paths: PackedStringArray) -> Array:
	var out: Array = []
	out.resize(paths.size())
	for i in paths.size():
		out[i] = get_value(provider, paths[i])
	return out

func get_value(provider: Object, path: String) -> Variant:
	if provider == null or path.is_empty():
		return null

	# Fast paths for hot fields
	if provider is Car:
		match path:
			"car_data.fitness": return (provider as Car).fitness
			"car_data.time_alive": return (provider as Car).time_alive
			"speed", "velocity.length", "velocity.length()":
				return (provider as Car).velocity.length()
			"velocity.x": return (provider as Car).velocity.x
			"velocity.y": return (provider as Car).velocity.y
			"car_data.pilot.get_full_name()":
				var p = (provider as Car).car_data.pilot
				return p.get_full_name() if p and p.has_method("get_full_name") else ""
			_: pass

	var tokens: Array = _compile_path(path)
	var cur: Variant = provider
	for t in tokens:
		if cur == null:
			return null
		var token_name: String = (t as Token).token_name
		var is_call: bool = (t as Token).is_call
		if is_call:
			if typeof(cur) == TYPE_OBJECT and (cur as Object).has_method(token_name):
				cur = (cur as Object).call(token_name)
			elif typeof(cur) == TYPE_VECTOR2:
				match token_name:
					"length": cur = (cur as Vector2).length()
					"length_squared": cur = (cur as Vector2).length_squared()
					"normalized": cur = (cur as Vector2).normalized()
					_: return null
			else:
				return null
		else:
			if typeof(cur) == TYPE_OBJECT:
				var obj := cur as Object
				if obj.has_method(token_name):      # allow zero-arg getter by method name
					cur = obj.call(token_name)
				else:
					cur = obj.get(token_name) if token_name in obj else null
			elif typeof(cur) == TYPE_DICTIONARY:
				cur = (cur as Dictionary).get(token_name, null)
			elif typeof(cur) == TYPE_VECTOR2:
				match token_name:
					"x": cur = (cur as Vector2).x
					"y": cur = (cur as Vector2).y
					_: return null
			else:
				return null
	return cur

func _compile_path(path: String) -> Array:
	var cached = _path_cache.get(path)
	if cached != null:
		return cached
	var tokens: Array = []
	for part in path.split("."):
		var is_call := part.ends_with("()")
		var nm := part.substr(0, part.length() - 2) if is_call else part
		var tok := Token.new()
		tok.token_name = nm
		tok.is_call = is_call
		tokens.append(tok)
	_path_cache[path] = tokens
	return tokens

class Token:
	var token_name: String = ""
	var is_call: bool = false
