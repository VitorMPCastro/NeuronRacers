@tool
extends Node2D
class_name CheckpointsDebug

@export var enabled: bool = true
@export var draw_indices: bool = true
@export var draw_order_lines: bool = true
@export var draw_progress_values: bool = false
@export var radius: float = 10.0
@export var color_checkpoint: Color = Color(0.05, 0.85, 1.0, 0.85)
@export var color_start: Color = Color(0.2, 1.0, 0.2, 1.0)
@export var color_lines: Color = Color(1.0, 0.8, 0.2, 0.7)
@export var auto_update: bool = true

var _rpm: RaceProgressionManager
var _font: Font

func _ready() -> void:
	add_to_group("checkpoint_debug")
	_bind_rpm()
	if Engine.is_editor_hint():
		set_process(false)
	else:
		set_process(auto_update)

func _bind_rpm() -> void:
	_rpm = get_tree().get_first_node_in_group("race_progression") as RaceProgressionManager
	if _rpm and _rpm.checkpoints_changed.is_connected(_on_checkpoints_changed) == false:
		_rpm.checkpoints_changed.connect(_on_checkpoints_changed)
	if _rpm and _rpm.track and _rpm.track.has_signal("track_built"):
		if _rpm.track.track_built.is_connected(_on_checkpoints_changed) == false:
			_rpm.track.track_built.connect(_on_checkpoints_changed)

func _on_checkpoints_changed() -> void:
	queue_redraw()

func _process(_delta: float) -> void:
	if auto_update:
		queue_redraw()

func _draw() -> void:
	if !enabled:
		return
	if _rpm == null:
		_bind_rpm()
		if _rpm == null:
			return

	var cps := _rpm.checkpoints
	if cps.is_empty():
		return

	var prog := _rpm.get_checkpoints_progress()
	var n := cps.size()

	# Lines in visiting order
	if draw_order_lines and n > 1:
		for i in range(n):
			var a := cps[i]
			var b := cps[(i + 1) % n]
			draw_line(to_local(a), to_local(b), color_lines, 1.5)

	# Points + labels
	for i in range(n):
		var p := cps[i]
		var col := color_start if i == 0 else color_checkpoint
		draw_circle(to_local(p), radius, col)

		if draw_indices and _font:
			var idx_text := str(i)
			var pos := to_local(p) + Vector2(8, -6)
			draw_string(_font, pos, idx_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1,1,1,0.95))

		if draw_progress_values and _font and i < prog.size():
			var pr := "%.1f" % prog[i]
			var pos2 := to_local(p) + Vector2(8, 10)
			draw_string(_font, pos2, pr, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.9,0.9,0.9,0.9))