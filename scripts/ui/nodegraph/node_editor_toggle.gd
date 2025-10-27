extends Button
class_name NodeEditorToggle

@export var popup_scene_path: String = "res://scenes/ui/node_editor_popup.tscn"
var _popup: Node = null

func _ready() -> void:
	toggle_mode = true
	connect("pressed", Callable(self, "_on_toggled"))

func _on_toggled() -> void:
	if pressed:
		if _popup == null:
			var popup_res = load(popup_scene_path)
			if popup_res == null:
				push_error("NodeEditorPopup resource not found: " + popup_scene_path)
				return
			_popup = popup_res.instantiate()
			get_tree().root.add_child(_popup)
			# forward data context if possible — compute provider safely
			var db := get_tree().get_first_node_in_group("data_broker")
			var provider = null
			var am := get_tree().get_first_node_in_group("AgentManager")
			if am != null:
				# only access `cars` when it's present and non-empty
				if "cars" in am:
					if am.cars != null and am.cars.size() > 0:
						provider = am.cars[0]
			if _popup.has_method("set_data_context"):
				_popup.set_data_context(db, provider)
		_popup.popup_centered(Vector2(0.9, 0.9))
	else:
		if _popup:
			_popup.hide()
