extends ScrollContainer
class_name LeaderboardScroll

@export_range(0.1, 1.0, 0.05) var height_percent: float = 0.6
@export var min_height_px: int = 120
@export var max_height_px: int = 1600

func _ready() -> void:
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	get_viewport().size_changed.connect(_update_height)
	_update_height()

func _update_height() -> void:
	var vp_h := get_viewport_rect().size.y
	custom_minimum_size.y = clamp(int(vp_h * height_percent), min_height_px, max_height_px)
