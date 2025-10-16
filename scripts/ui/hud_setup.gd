extends CanvasLayer

@onready var frame_scene := preload("res://scenes/ui/UIFrame.tscn")
@onready var leaderboard_container_scene := preload("res://scenes/ui/elements/leaderboard_container.tscn")

var frame: UIFrame

func _ready() -> void:
	frame = frame_scene.instantiate() as UIFrame
	add_child(frame)

	# Left bar: Leaderboard inside a collapsible panel
	var lb_container := leaderboard_container_scene.instantiate() as Control
	lb_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lb_panel := CollapsiblePanel.new()
	lb_panel.title = "Leaderboard"
	lb_panel.start_collapsed = false
	lb_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_to_left(lb_panel)
	lb_panel.set_content(lb_container)

	# Top bar: Generation settings panel (collapsible)
	var gen_panel := CollapsiblePanel.new()
	gen_panel.title = "Generation"
	gen_panel.start_collapsed = false
	gen_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_panel.size_flags_vertical = 0
	frame.add_to_top(gen_panel)

	var gen_content := VBoxContainer.new()
	gen_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_content.size_flags_vertical = 0

	var am := _get_agent_manager()
	# Defaults if AgentManager not found
	var gen_time := 20.0
	var pop_size := 20
	var elit := 0.2
	var aps := 20.0
	var killswitch := true
	var random_skins := true
	var autosave := false

	if am:
		gen_time = am.generation_time
		pop_size = am.population_size
		elit = am.elitism_percent
		aps = am.ai_actions_per_second
		killswitch = am.killswitch
		random_skins = am.randomize_car_skins
		autosave = am.autosave_each_generation

	# Spin: Generation Time (seconds)
	gen_content.add_child(_make_spin_row(
		"Generation time (s)", gen_time, 1.0, 600.0, 0.1,
		func(v: float):
			var m := _get_agent_manager()
			if m: m.generation_time = v
	))

	# Spin: Population Size (applies next spawn)
	gen_content.add_child(_make_spin_row(
		"Population size", float(pop_size), 1.0, 500.0, 1.0,
		func(v: float):
			var m := _get_agent_manager()
			if m: m.population_size = int(v)
	))

	# Spin: Elitism (0..1)
	gen_content.add_child(_make_spin_row(
		"Elitism %", elit, 0.0, 1.0, 0.01,
		func(v: float):
			var m := _get_agent_manager()
			if m: m.elitism_percent = clamp(v, 0.0, 1.0)
	))

	# Spin: AI APS (0 = uncapped)
	gen_content.add_child(_make_spin_row(
		"AI actions/sec", aps, 0.0, 120.0, 1.0,
		func(v: float):
			var m := _get_agent_manager()
			if m: m.ai_actions_per_second = max(0.0, v)
	))

	# Toggle: Killswitch
	gen_content.add_child(_make_check_row(
		"Killswitch", killswitch,
		func(on: bool):
			var m := _get_agent_manager()
			if m: m.killswitch = on
	))

	# Toggle: Randomize car skins
	gen_content.add_child(_make_check_row(
		"Randomize skins", random_skins,
		func(on: bool):
			var m := _get_agent_manager()
			if m: m.randomize_car_skins = on
	))

	# Toggle: Autosave each generation
	gen_content.add_child(_make_check_row(
		"Autosave each generation", autosave,
		func(on: bool):
			var m := _get_agent_manager()
			if m: m.autosave_each_generation = on
	))

	# Actions row
	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var btn_next := Button.new()
	btn_next.text = "Next Gen"
	btn_next.pressed.connect(func():
		var m := _get_agent_manager()
		if m and m.has_method("next_generation"):
			m.next_generation()
	)
	actions.add_child(btn_next)

	var btn_respawn := Button.new()
	btn_respawn.text = "Respawn Population"
	btn_respawn.pressed.connect(func():
		var m := _get_agent_manager()
		if m:
			m.clear_scene()
			m.spawn_population()
	)
	actions.add_child(btn_respawn)

	var btn_save := Button.new()
	btn_save.text = "Save Generation"
	btn_save.pressed.connect(func():
		var m := _get_agent_manager()
		if m:
			m.save_generation_to_json("", [], "manual save from HUD")
	)
	actions.add_child(btn_save)

	gen_content.add_child(actions)

	# Attach content to the panel
	gen_panel.set_content(gen_content)

# Helpers to build labeled rows
func _make_spin_row(label_text: String, value: float, min: float, max: float, step: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	row.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min
	spin.max_value = max
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float):
		if on_change: on_change.call(v)
	)
	row.add_child(spin)

	return row

func _make_check_row(label_text: String, checked: bool, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var chk := CheckBox.new()
	chk.text = label_text
	chk.button_pressed = checked
	chk.toggled.connect(func(on: bool):
		if on_change: on_change.call(on)
	)
	row.add_child(chk)

	return row

func _get_agent_manager() -> AgentManager:
	var am := get_tree().get_first_node_in_group("agent_manager") as AgentManager
	if am == null:
		am = get_tree().get_root().find_child("AgentManager", true, false) as AgentManager
	return am

func _on_aps_selected(idx: int) -> void:
	pass

func _on_next_gen() -> void:
	pass
