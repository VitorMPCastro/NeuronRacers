extends CanvasLayer

@onready var frame_scene := preload("res://scenes/ui/UIFrame.tscn")
@onready var leaderboard_container_scene := preload("res://scenes/ui/elements/leaderboard_container.tscn")

var frame: UIFrame
var _car_selector: OptionButton
var _neuron_graph: NeuronGraph
var _gen_file_dialog: FileDialog  # NEW

func _ready() -> void:
	frame = frame_scene.instantiate() as UIFrame
	add_child(frame)

	# Listen for population changes to refresh UI
	var am := _get_agent_manager()
	if am:
		am.population_spawned.connect(_on_population_spawned_hud)

	# Left bar: Leaderboard inside a collapsible panel
	var lb_container := leaderboard_container_scene.instantiate() as Control
	lb_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lb_panel := CollapsiblePanel.new()
	lb_panel.title = "Leaderboard"
	lb_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_to_left(lb_panel)
	lb_panel.set_content(lb_container)

	# Top bar: Generation panel
	var gen_panel := CollapsiblePanel.new()
	gen_panel.title = "Generation"
	gen_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_panel.size_flags_vertical = 0
	frame.add_to_top(gen_panel)

	var gen_content := VBoxContainer.new()
	gen_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_content.size_flags_vertical = 0

	var gen_time := am.generation_time if am else 20.0
	var pop_size := am.population_size if am else 20
	var elit := am.elitism_percent if am else 0.2
	var aps := am.ai_actions_per_second if am else 20.0
	var killswitch := am.killswitch if am else true
	var random_skins := am.randomize_car_skins if am else true
	var autosave := am.autosave_each_generation if am else false

	gen_content.add_child(_make_spin_row("Generation time (s)", gen_time, 1.0, 600.0, 0.1, func(v: float):
		var m := _get_agent_manager(); if m: m.generation_time = v
	))
	gen_content.add_child(_make_spin_row("Population size", float(pop_size), 1.0, 500.0, 1.0, func(v: float):
		var m := _get_agent_manager(); if m: m.population_size = int(v)
	))
	gen_content.add_child(_make_spin_row("Elitism %", elit, 0.0, 1.0, 0.01, func(v: float):
		var m := _get_agent_manager(); if m: m.elitism_percent = clamp(v, 0.0, 1.0)
	))
	gen_content.add_child(_make_spin_row("AI actions/sec", aps, 0.0, 120.0, 1.0, func(v: float):
		var m := _get_agent_manager(); if m: m.ai_actions_per_second = max(0.0, v)
	))
	gen_content.add_child(_make_check_row("Killswitch", killswitch, func(on: bool):
		var m := _get_agent_manager(); if m: m.killswitch = on
	))
	gen_content.add_child(_make_check_row("Randomize skins", random_skins, func(on: bool):
		var m := _get_agent_manager(); if m: m.randomize_car_skins = on
	))
	gen_content.add_child(_make_check_row("Autosave each generation", autosave, func(on: bool):
		var m := _get_agent_manager(); if m: m.autosave_each_generation = on
	))

	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_next := Button.new(); btn_next.text = "Next Gen"; btn_next.pressed.connect(func():
		var m := _get_agent_manager(); if m and m.has_method("next_generation"): m.next_generation()
	); actions.add_child(btn_next)
	var btn_respawn := Button.new(); btn_respawn.text = "Respawn Population"; btn_respawn.pressed.connect(func():
		var m := _get_agent_manager(); if m: m.clear_scene(); if m: m.spawn_population()
	); actions.add_child(btn_respawn)
	var btn_save := Button.new(); btn_save.text = "Save Generation"; btn_save.pressed.connect(func():
		var m := _get_agent_manager(); if m: m.save_generation_to_json("", [], "manual save from HUD")
	); actions.add_child(btn_save)

	# NEW: Load from JSON (queues brains for next generation)
	var btn_load := Button.new()
	btn_load.text = "Load From JSON..."
	btn_load.pressed.connect(func():
		var gen_dir := OS.get_user_data_dir().path_join("generations")
		# Try to open at user://generations if it exists, else default
		if DirAccess.dir_exists_absolute(gen_dir):
			_gen_file_dialog.current_dir = gen_dir
		_gen_file_dialog.popup_centered()
	)
	actions.add_child(btn_load)

	gen_content.add_child(actions)
	gen_panel.set_content(gen_content)

	# Right bar: Debug tabs (Cars / Managers / Track)
	_build_right_debug_tabs()

	# Bottom bar: Brain/Neuron graph for observed car
	_build_bottom_brain_panel()
	_refresh_neuron_graph()

	# File dialog for loading generations (hidden until used)
	_gen_file_dialog = FileDialog.new()
	_gen_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_gen_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_gen_file_dialog.filters = PackedStringArray(["*.json ; JSON files"])
	_gen_file_dialog.title = "Select generation JSON"
	add_child(_gen_file_dialog)
	_gen_file_dialog.file_selected.connect(_on_generation_json_selected)

func _build_right_debug_tabs() -> void:
	var panel := CollapsiblePanel.new()
	panel.title = "Debug"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Cars tab
	var cars_tab := _make_cars_tab()
	cars_tab.name = "Cars"
	tabs.add_child(cars_tab)

	# AgentManager tab
	var am_tab := _make_agent_manager_tab()
	am_tab.name = "AgentManager"
	tabs.add_child(am_tab)

	# TrackManager tab
	var tm_tab := _make_track_manager_tab()
	tm_tab.name = "Track"
	tabs.add_child(tm_tab)

	# RaceProgressionManager tab
	var rpm_tab := _make_race_progression_tab()
	rpm_tab.name = "Race"
	tabs.add_child(rpm_tab)

	panel.set_content(tabs)
	frame.add_to_right(panel)

func _make_cars_tab() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var am := _get_agent_manager()

	# Select car
	var row_sel := HBoxContainer.new(); row_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new(); lbl.text = "Select car"; lbl.custom_minimum_size.x = 120; row_sel.add_child(lbl)
	_car_selector = OptionButton.new(); _car_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rebuild_car_selector_items()
	_car_selector.item_selected.connect(func(_idx: int):
		_refresh_neuron_graph()
	)
	row_sel.add_child(_car_selector)
	v.add_child(row_sel)

	# Toggle sensors debug for all cars
	v.add_child(_make_check_row("Show sensors (all cars)", false, func(on: bool):
		var m := _get_agent_manager(); if m:
			for c in m.cars:
				var rig := _get_car_sensors(c)
				if rig: rig.draw_debug = on
	))

	# Info + actions for selected car (safe ops)
	var row_btns := HBoxContainer.new(); row_btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_kill := Button.new(); btn_kill.text = "Crash Selected"
	btn_kill.pressed.connect(func():
		var m := _get_agent_manager(); if m and _car_selector.item_count > 0:
			var idx := _car_selector.get_selected_id()
			if idx >= 0 and idx < m.cars.size():
				var car = m.cars[idx]
				if car and car.has_variable("crashed"):
					car.crashed = true
	)
	row_btns.add_child(btn_kill)
	v.add_child(row_btns)

	return v

func _rebuild_car_selector_items() -> void:
	if _car_selector == null:
		return
	_car_selector.clear()
	var am := _get_agent_manager()
	var cars = am.cars if am else []
	for i in range(cars.size()):
		var car = cars[i]
		var car_name = car.name if car else "Car %d" % i
		_car_selector.add_item(car_name, i)
	if _car_selector.item_count > 0 and _car_selector.get_selected_id() == -1:
		_car_selector.select(0)

func _make_agent_manager_tab() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var am := _get_agent_manager()
	var gen_time := am.generation_time if am else 20.0
	var pop_size := am.population_size if am else 20
	var elit := am.elitism_percent if am else 0.2
	var aps := am.ai_actions_per_second if am else 20.0

	v.add_child(_make_spin_row("Generation time (s)", gen_time, 1.0, 600.0, 0.1, func(val: float):
		var m := _get_agent_manager(); if m: m.generation_time = val
	))
	v.add_child(_make_spin_row("Population size", float(pop_size), 1.0, 500.0, 1.0, func(val: float):
		var m := _get_agent_manager(); if m: m.population_size = int(val)
	))
	v.add_child(_make_spin_row("Elitism %", elit, 0.0, 1.0, 0.01, func(val: float):
		var m := _get_agent_manager(); if m: m.elitism_percent = clamp(val, 0.0, 1.0)
	))
	v.add_child(_make_spin_row("AI actions/sec", aps, 0.0, 120.0, 1.0, func(val: float):
		var m := _get_agent_manager(); if m: m.ai_actions_per_second = max(0.0, val)
	))

	var btns := HBoxContainer.new(); btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b1 := Button.new(); b1.text = "Next Gen"; b1.pressed.connect(func():
		var m := _get_agent_manager(); if m and m.has_method("next_generation"): m.next_generation()
	); btns.add_child(b1)
	var b2 := Button.new(); b2.text = "Respawn"; b2.pressed.connect(func():
		var m := _get_agent_manager(); if m:
			m.clear_scene(); m.spawn_population()
	); btns.add_child(b2)
	v.add_child(btns)

	return v

func _make_track_manager_tab() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var tm = _get_track_manager()
	var show_lines = tm.debug_show_lines if tm else false
	var show_sectors = tm.debug_show_sectors if tm else false
	var sample_step = tm.sample_step if tm else 32.0
	var track_width = tm.track_width if tm else 128.0
	var curb_thickness = tm.curb_thickness if tm else 8.0

	v.add_child(_make_check_row("Show lines", show_lines, func(on: bool):
		var t = _get_track_manager(); if t: t.debug_show_lines = on
	))
	v.add_child(_make_check_row("Show sectors", show_sectors, func(on: bool):
		var t = _get_track_manager(); if t: t.debug_show_sectors = on
	))
	v.add_child(_make_spin_row("Sample step", sample_step, 1.0, 128.0, 1.0, func(val: float):
		var t = _get_track_manager(); if t: t.sample_step = val
	))
	v.add_child(_make_spin_row("Track width", track_width, 4.0, 256.0, 1.0, func(val: float):
		var t = _get_track_manager(); if t: t.track_width = val
	))
	v.add_child(_make_spin_row("Curb thickness", curb_thickness, 0.0, 32.0, 0.5, func(val: float):
		var t = _get_track_manager(); if t: t.curb_thickness = val
	))

	return v

func _make_race_progression_tab() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	var rpm = _get_race_progression_manager()
	var chk_count := (RaceProgressionManager.checkpoints.size() if rpm else 0)
	lbl.text = "Checkpoints: %d" % chk_count
	v.add_child(lbl)

	var btn_rebuild := Button.new()
	btn_rebuild.text = "Rebuild checkpoints"
	btn_rebuild.pressed.connect(func():
		var r = _get_race_progression_manager(); if r: r._cache_checkpoints()
		lbl.text = "Checkpoints: %d" % RaceProgressionManager.checkpoints.size()
	)
	v.add_child(btn_rebuild)

	var btn_clear := Button.new()
	btn_clear.text = "Clear progress"
	btn_clear.pressed.connect(func():
		RaceProgressionManager.car_progress.clear()
	)
	v.add_child(btn_clear)

	return v

# Helpers to build labeled rows
func _make_spin_row(label_text: String, value: float, min_value: float, max_value: float, step: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	row.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
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

# Lookups
func _get_agent_manager() -> AgentManager:
	var am := get_tree().get_first_node_in_group("agent_manager") as AgentManager
	if am == null:
		am = get_tree().get_root().find_child("AgentManager", true, false) as AgentManager
	return am

func _get_track_manager():
	var gm := get_tree().get_root().find_child("GameManager", true, false)
	if gm:
		return gm.find_child("TrackManager", true, false)
	return null

func _get_race_progression_manager():
	var gm := get_tree().get_root().find_child("GameManager", true, false)
	if gm:
		return gm.find_child("RaceProgressionManager", true, false)
	return null

func _get_car_sensors(car: Node) -> CarSensors:
	if car == null:
		return null
	var direct := car.get_node_or_null("RayParent")
	if direct and direct is CarSensors:
		return direct as CarSensors
	# Recursive search
	var stack := [car]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is CarSensors:
				return c as CarSensors
			stack.push_back(c)
	return null

func _build_bottom_brain_panel() -> void:
	var panel := CollapsiblePanel.new()
	panel.title = "Brain"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Keep a square drawing area
	var ar := AspectRatioContainer.new()
	ar.ratio = 1.0
	ar.stretch_mode = AspectRatioContainer.STRETCH_FIT
	ar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ar.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_neuron_graph = NeuronGraph.new()
	_neuron_graph.fit_square = true
	_neuron_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_neuron_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ar.add_child(_neuron_graph)

	container.add_child(ar)

	# Controls row
	var row := HBoxContainer.new(); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_refresh := Button.new(); btn_refresh.text = "Refresh"; btn_refresh.pressed.connect(_refresh_neuron_graph); row.add_child(btn_refresh)
	var chk_bias := CheckBox.new(); chk_bias.text = "Show bias"; chk_bias.toggled.connect(func(on: bool):
		if _neuron_graph: _neuron_graph.show_bias = on; _neuron_graph.queue_redraw()
	); row.add_child(chk_bias)
	container.add_child(row)

	panel.set_content(container)
	frame.add_to_bottom(panel)

func _get_observed_car() -> Car:
	# Prefer the selection from the Cars tab; fallback to best living car
	var am := _get_agent_manager()
	if am == null or am.cars.is_empty():
		return null
	if _car_selector and _car_selector.item_count > 0:
		var id := _car_selector.get_selected_id()
		if id >= 0 and id < am.cars.size():
			return am.cars[id]
	# Fallback: best living (if you have a helper, else first non-crashed)
	for c in am.cars:
		if c and !c.crashed:
			return c
	return am.cars[0]

func _refresh_neuron_graph() -> void:
	if _neuron_graph == null:
		return
	var car := _get_observed_car()
	_neuron_graph.set_brain_from_car(car)

func _on_population_spawned_hud() -> void:
	_rebuild_car_selector_items()
	_refresh_neuron_graph()

# NEW: callback after selecting a JSON file
func _on_generation_json_selected(path: String) -> void:
	var am := _get_agent_manager()
	if am == null:
		push_error("AgentManager not found; cannot queue JSON load.")
		return
	var ok = am.queue_generation_json(path, true)
	if ok:
		print("Queued generation JSON for next generation: ", path)
	else:
		push_error("Failed to queue generation JSON from: " + path)
