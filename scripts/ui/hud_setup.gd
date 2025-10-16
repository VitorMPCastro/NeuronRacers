extends CanvasLayer

@onready var frame_scene := preload("res://scenes/ui/UIFrame.tscn")
@onready var leaderboard_container_scene := preload("res://scenes/ui/elements/leaderboard_container.tscn")

var frame: UIFrame

func _ready() -> void:
	frame = frame_scene.instantiate() as UIFrame
	add_child(frame)

	# Leaderboard inside a collapsible element on the left bar
	var lb_container := leaderboard_container_scene.instantiate() as Control  # ScrollContainer root
	lb_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lb_panel := CollapsiblePanel.new()
	lb_panel.title = "Leaderboard"
	lb_panel.start_collapsed = false
	lb_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Add panel first so it builds, then set content
	frame.add_to_left(lb_panel)
	lb_panel.set_content(lb_container)

	# Top bar example controls
	var aps_dropdown := OptionButton.new()
	aps_dropdown.item_selected.connect(_on_aps_selected)
	aps_dropdown.add_item("APS: ∞ (uncapped)")
	aps_dropdown.add_item("APS: 2")
	aps_dropdown.add_item("APS: 5")
	aps_dropdown.add_item("APS: 10")
	aps_dropdown.add_item("APS: 20")
	frame.add_to_top(aps_dropdown)

	var next_gen_btn := Button.new()
	next_gen_btn.text = "Next Gen"
	next_gen_btn.pressed.connect(_on_next_gen)
	frame.add_to_top(next_gen_btn)

func _on_aps_selected(idx: int) -> void:
	var am := get_tree().get_first_node_in_group("agent_manager") as AgentManager
	if am == null:
		am = get_tree().get_root().find_child("AgentManager", true, false) as AgentManager
	if am == null:
		return
	var aps := 5.0
	match idx:
		0:
			aps = 0.0
		1:
			aps = 2.0
		2:
			aps = 5.0
		3:
			aps = 10.0
		4:
			aps = 20.0
		_:
			pass
	am.set("ai_actions_per_second", aps)

func _on_next_gen() -> void:
	var am := get_tree().get_first_node_in_group("agent_manager") as AgentManager
	if am == null:
		am = get_tree().get_root().find_child("AgentManager", true, false) as AgentManager
	if am and am.has_method("next_generation"):
		am.next_generation()
