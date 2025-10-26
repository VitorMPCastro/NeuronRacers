extends Node
class_name DataBroker

# Cache: "a.b.c()" -> [ {name:"a", call:false}, {name:"b", call:false}, {name:"c", call:true} ]
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
			# NEW: common velocity/speed aliases
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
		var token_name: String = t.token_name
		if t.call:
			if typeof(cur) == TYPE_OBJECT and (cur as Object).has_method(token_name):
				cur = (cur as Object).call(token_name)
			elif typeof(cur) == TYPE_VECTOR2:
				# NEW: support Vector2 method calls
				match token_name:
					"length": cur = (cur as Vector2).length()
					"length_squared": cur = (cur as Vector2).length_squared()
					"normalized":
						cur = (cur as Vector2).normalized()
					_:
						return null
			else:
				return null
		else:
			# Property/field
			if typeof(cur) == TYPE_OBJECT:
				var obj := cur as Object
				if obj.has_method(name):      # allow zero-arg getter by method name
					cur = obj.call(name)
				else:
					cur = obj.get(name) if name in obj else null
			elif typeof(cur) == TYPE_DICTIONARY:
				cur = (cur as Dictionary).get(name, null)
			elif typeof(cur) == TYPE_VECTOR2:
				# NEW: support Vector2 fields
				match name:
					"x": cur = (cur as Vector2).x
					"y": cur = (cur as Vector2).y
					_:
						return null
			else:
				return null
	return cur

func _compile_path(path: String) -> Array:
	var tokens = _path_cache.get(path)
	if tokens != null:
		return tokens
	tokens = []
	var parts := path.split(".")
	for p in parts:
		var is_call := false
		var token_name := p
		if p.ends_with("()"):
			is_call = true
			token_name = p.substr(0, p.length() - 2)
		tokens.append({ "name": token_name, "call": is_call })
	# Small struct-like access
	for i in tokens.size():
		tokens[i] = Token.new(tokens[i].token_name, tokens[i].is_call)
	_path_cache[path] = tokens
	return tokens

class Token:
	var token_name: String
	var is_call: bool
	func _init(n: String, c: bool) -> void:
		token_name = n
		is_call = c
