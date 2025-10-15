extends Node
class_name DataBroker

func _ready() -> void:
	_connect_all()
	# Auto-connect any fields added later
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	# Attach to any node that exposes the 'request_value' signal
	if n.has_signal("request_value"):
		var sig: Signal = n.signal("request_value")
		if not sig.is_connected(_on_field_request):
			sig.connect(_on_field_request)

func _connect_all() -> void:
	for f in get_tree().get_nodes_in_group("telemetry_fetchers"):
		if (f as Object).has_signal("request_value"):
			var sig: Signal = f.signal("request_value")
			if not sig.is_connected(_on_field_request):
				sig.connect(_on_field_request)

func _on_field_request(provider: Object, path: String, reply: Callable) -> void:
	var value = get_value(provider, path)
	reply.call(value)

# Public API: resolve a value immediately (useful for MLP feature pulls)
func get_value(provider: Object, path: String) -> Variant:
	return _resolve(provider, path.strip_edges())

# Dot-path resolver with zero-arg method support and common helpers (Vector length, arrays)
func _resolve(obj: Variant, path: String) -> Variant:
	if obj == null or path == "":
		return null
	var parts := path.split(".")
	var current: Variant = obj
	for raw_key in parts:
		var key := raw_key.strip_edges()
		if typeof(current) == TYPE_NIL:
			return null

		# Zero-arg method call notation: "method()"
		var call_method := false
		if key.ends_with("()"):
			call_method = true
			key = key.trim_suffix("()")

		match typeof(current):
			TYPE_OBJECT:
				var o := current as Object
				# Method priority if "()" used
				if call_method and o.has_method(key):
					current = o.call(key)
					continue
				# Property
				if _has_property(o, key):
					current = o.get(key)
					continue
				# Zero-arg method fallback
				if o.has_method(key):
					current = o.call(key)
					continue
				# Optional: child node by exact name
				if o is Node:
					var child := (o as Node).find_child(key, false, false)
					if child != null:
						current = child
						continue
				return null

			TYPE_DICTIONARY:
				current = (current as Dictionary).get(key, null)

			TYPE_ARRAY:
				# Numeric index access: e.g. "items.0"
				if key.is_valid_int():
					var idx := int(key)
					var arr := current as Array
					current = arr[idx] if (idx >= 0 and idx < arr.size()) else null
				else:
					return null

			_:
				# Common helpers on plain Variants:
				# - Vector2/Vector3 length via ".length"
				# - PackedVector2Array size via ".size"
				if key == "length":
					if typeof(current) == TYPE_VECTOR2:
						return (current as Vector2).length()
					if typeof(current) == TYPE_VECTOR3:
						return (current as Vector3).length()
					return null
				if key == "size":
					if typeof(current) == TYPE_PACKED_VECTOR2_ARRAY:
						return (current as PackedVector2Array).size()
					if typeof(current) == TYPE_STRING:
						return (current as String).length()
					return null
				return null
	return current

func _has_property(obj: Object, prop_name: String) -> bool:
	for prop in obj.get_property_list():
		if prop.get("name", "") == prop_name:
			return true
	return false