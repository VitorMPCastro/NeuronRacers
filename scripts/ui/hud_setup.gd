extends CanvasLayer

@onready var frame_scene := preload("res://scenes/ui/UIFrame.tscn")
@onready var leaderboard_container_scene := preload("res://scenes/ui/elements/leaderboard_container.tscn")

var frame: UIFrame
var _car_selector_top: OptionButton
var _car_selector_tab: OptionButton
var _neuron_graph: NeuronGraph
var _gen_file_dialog: FileDialog
var _camera: Camera2D
var _inputs_graph: InputAxesGraph

# HUD-authoritative selection
var _observed_car: Car = null
var _always_track_best: bool = true
var _always_best_poll_sec := 0.25
var _always_best_accum := 0.0

# NEW: show sensors for observed car
var _show_current_sensors: bool = false

# NEW: Best car selection via DataBroker
@export var best_car_score_path: String = "car_data.fitness"
@export var best_car_skip_crashed: bool = true

# NEW: performance knobs for "Always Track Best"
@export var best_recompute_on_ai_tick_only: bool = true
@export var best_switch_hysteresis: float = 0.02        # require >=2% improvement to switch
@export var best_switch_cooldown_sec: float = 0.75      # min time between switches
@export var best_gen_settle_sec: float = 0.50           # delay after generation spawn

var _best_cooldown_until: float = 0.0
var _best_settle_until: float = 0.0

# NEW: observed car label panel + overlay
var _car_handle: CarHandlePanel = null
var _car_handle_overlay: CarHandleLineOverlay = null
var _show_car_handle: bool = true

var _db_cached: DataBroker = null

func _ready() -> void:
	frame = frame_scene.instantiate() as UIFrame
	# Listen for population changes to refresh UI
	var am := _get_agent_manager()
	if am:
		am.population_spawned.connect(_on_population_spawned_hud)
		# NEW: react to fitness changes at AI tick rate
		if am.has_signal("ai_tick"):
			am.ai_tick.connect(_on_ai_tick)
	add_child(frame)
	_camera = _get_camera()

	# NEW: spawn one panel in HUD and an overlay line in world
	_ensure_car_handle_panel()

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
		if DirAccess.dir_exists_absolute(gen_dir):
			_gen_file_dialog.current_dir = gen_dir
		_gen_file_dialog.popup_centered()
	)
	actions.add_child(btn_load)

	gen_content.add_child(actions)
	gen_panel.set_content(gen_content)

	# REMOVED: Fitness quick-edit row from the top bar (moved to bottom tabs)
	# [deleted block that created row_fit_edit and frame.add_to_top(row_fit_edit)]

	# Right bar: Debug tabs (Cars / Managers / Track)
	_build_right_debug_tabs()

	# Bottom bar: tabs with Brain and Fitness
	_build_bottom_tabs()
	_refresh_neuron_graph()

	# File dialog for loading generations (hidden until used)
	_gen_file_dialog = FileDialog.new()
	_gen_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_gen_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_gen_file_dialog.filters = PackedStringArray(["*.json ; JSON files"])
	_gen_file_dialog.title = "Select generation JSON"
	add_child(_gen_file_dialog)
	_gen_file_dialog.file_selected.connect(_on_generation_json_selected)

	# Top bar: Spectate panel with car selector and highlight toggle
	var spectate_row := HBoxContainer.new()
	spectate_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var spectate_lbl := Label.new()
	spectate_lbl.text = "Spectate:"
	spectate_row.add_child(spectate_lbl)

	_car_selector_top = OptionButton.new()
	_car_selector_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_car_selector_top.item_selected.connect(_on_car_selected_top)
	spectate_row.add_child(_car_selector_top)

	var btn_best_top := Button.new()
	btn_best_top.text = "Best (B)"
	btn_best_top.pressed.connect(func():
		_always_track_best = false
		var best := _compute_best_car()
		if best: _set_observed_car(best, true)
	)
	spectate_row.add_child(btn_best_top)

	var chk_highlight := CheckBox.new()
	chk_highlight.text = "Highlight target"
	chk_highlight.button_pressed = _camera and _camera.has_method("highlight_enabled") and _camera.highlight_enabled
	chk_highlight.toggled.connect(func(on: bool):
		var cam = _get_camera()
		if cam and cam.has_method("highlight_enabled"):
			cam.highlight_enabled = on
		# Re-apply to current target to reflect change now
		if cam and cam.has_method("set_target") and cam.has("target"):
			cam.set_target(cam.get("target"))
	)
	spectate_row.add_child(chk_highlight)

	var collapsible := CollapsiblePanel.new()
	collapsible.title = "Spectate"
	collapsible.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collapsible.set_content(spectate_row)
	collapsible.size_flags_vertical = 0
	collapsible.set_content(spectate_row)

	frame.add_to_top(collapsible)

	# Ensure selectors are populated for the first population (signal may have fired before HUD connected)
	_rebuild_car_selectors()
	_pick_initial_observed()
	_refresh_neuron_graph()
	_refresh_input_graph()

# NEW: keep camera following HUD’s observed car and poll fallback timer if needed
func _process(delta: float) -> void:
	var cam := _get_camera()
	var car := _get_observed_car()
	if cam and car:
		if cam.has_method("spectate_car"):
			cam.spectate_car(car)
		else:
			cam.set("target", car)

	# Keep handle panel and line in sync
	_update_car_handle_target()

	# Optional fallback polling (off by default)
	if _always_track_best and !best_recompute_on_ai_tick_only:
		_always_best_accum += delta
		if _always_best_accum >= max(0.25, _always_best_poll_sec):
			_always_best_accum = 0.0
			_maybe_switch_best()

# NEW: called each AI tick; switch to current best if needed
func _on_ai_tick() -> void:
	if !_always_track_best:
		return
	_maybe_switch_best()

func _on_population_spawned_hud() -> void:
	_best_settle_until = GameManager.global_time + best_gen_settle_sec
	_rebuild_car_selectors()
	_pick_initial_observed()
	_refresh_neuron_graph()
	_refresh_input_graph()
	# REMOVE per-car car_death lambdas; best is recomputed on ai_tick with hysteresis
	# (This avoids hundreds of lambda invocations in the same frame.)

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

# Cars tab: toggle to spawn/despawn the panel
func _make_cars_tab() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var _am := _get_agent_manager()

	# Select car (pilot names)
	var row_sel := HBoxContainer.new(); row_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new(); lbl.text = "Select car"; lbl.custom_minimum_size.x = 120; row_sel.add_child(lbl)
	_car_selector_tab = OptionButton.new(); _car_selector_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_car_selector_tab.item_selected.connect(func(_idx: int):
		_refresh_neuron_graph()
		_on_car_selected_tab(_idx)
	)
	row_sel.add_child(_car_selector_tab)
	var btn_spec := Button.new()
	btn_spec.text = "Spectate Selected"
	btn_spec.pressed.connect(func():
		_on_car_selected_tab(_car_selector_tab.get_selected_id())
	)
	row_sel.add_child(btn_spec)
	v.add_child(row_sel)

	# Camera debug options
	var cam_row := HBoxContainer.new(); cam_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cam_lbl := Label.new(); cam_lbl.text = "Camera"; cam_lbl.custom_minimum_size.x = 120
	cam_row.add_child(cam_lbl)

	var btn_prev := Button.new(); btn_prev.text = "< Prev"
	btn_prev.pressed.connect(func(): _select_relative(-1))
	cam_row.add_child(btn_prev)

	var btn_best := Button.new(); btn_best.text = "Best (B)"
	btn_best.pressed.connect(func():
		_always_track_best = false
		var best := _compute_best_car()
		if best: _set_observed_car(best, true)
	)
	cam_row.add_child(btn_best)

	var chk_always := CheckBox.new(); chk_always.text = "Always Track Best (Shift+B)"
	chk_always.button_pressed = _always_track_best
	chk_always.toggled.connect(func(on: bool):
		_always_track_best = on
		if on:
			var best := _compute_best_car()
			if best: _set_observed_car(best, true)
	)
	cam_row.add_child(chk_always)

	# Align rotation to car
	var chk_align := CheckBox.new(); chk_align.text = "Align rotation to car"
	var cam := _get_camera()
	chk_align.button_pressed = cam != null and cam.align_rotation_to_car
	chk_align.toggled.connect(func(on: bool):
		var c := _get_camera()
		if c:
			c.align_rotation_to_car = on
	)
	cam_row.add_child(chk_align)

	# NEW: rotation deadzone toggle
	var chk_dead := CheckBox.new(); chk_dead.text = "Rotation deadzone"
	chk_dead.button_pressed = cam != null and cam.align_use_deadzone
	chk_dead.toggled.connect(func(on: bool):
		var c := _get_camera()
		if c:
			c.align_use_deadzone = on
	)
	cam_row.add_child(chk_dead)

	# NEW: deadzone amount (degrees)
	var spn_dead := SpinBox.new()
	spn_dead.min_value = 0.0
	spn_dead.max_value = 180.0
	spn_dead.step = 0.5
	spn_dead.custom_minimum_size.x = 90
	spn_dead.value = (cam.align_deadzone_deg if cam else 10.0)
	spn_dead.value_changed.connect(func(value: float):
		var c := _get_camera()
		if c:
			c.align_deadzone_deg = value
	)
	cam_row.add_child(spn_dead)

	# Snap to North button (shortcut N)
	var btn_north := Button.new(); btn_north.text = "North (N)"
	btn_north.pressed.connect(func():
		var c := _get_camera()
		if c and c.has_method("snap_north"):
			c.snap_north()
		elif c:
			c.rotation = 0.0
	)
	cam_row.add_child(btn_north)

	var chk_hl := CheckBox.new(); chk_hl.text = "Highlight target"
	chk_hl.button_pressed = _camera and _camera.has_method("highlight_enabled") and _camera.highlight_enabled
	chk_hl.toggled.connect(func(on: bool):
		var c := _get_camera()
		if c and c.has_method("highlight_enabled"):
			c.highlight_enabled = on
		if c and c.has_method("set_target") and c.has("target"):
			c.set_target(c.get("target"))
	)
	cam_row.add_child(chk_hl)

	var btn_next := Button.new(); btn_next.text = "Next >"
	btn_next.pressed.connect(func(): _select_relative(1))
	cam_row.add_child(btn_next)

	# Zoom
	var btn_zoom_out := Button.new(); btn_zoom_out.text = "Zoom +"
	btn_zoom_out.pressed.connect(func():
		var c := _get_camera()
		if c and c.has_method("adjust_zoom"):
			c.adjust_zoom(c.zoom_speed)
	)
	cam_row.add_child(btn_zoom_out)

	var btn_zoom_in := Button.new(); btn_zoom_in.text = "Zoom -"
	btn_zoom_in.pressed.connect(func():
		var c := _get_camera()
		if c and c.has_method("adjust_zoom"):
			c.adjust_zoom(-c.zoom_speed)
	)
	cam_row.add_child(btn_zoom_in)

	v.add_child(cam_row)

	# Car label panel toggle
	var chk_handle := CheckBox.new(); chk_handle.text = "Show car label panel"
	chk_handle.button_pressed = _show_car_handle
	chk_handle.toggled.connect(func(on: bool):
		_show_car_handle = on
		if on:
			_ensure_car_handle_panel()
		else:
			_destroy_car_handle_panel()
	)
	v.add_child(chk_handle)

	# NEW: sensors toggle row
	var sensors_row := _make_check_row("Show sensors for observed car", _show_current_sensors, func(on: bool):
		_set_show_current_sensors(on)
	)
	v.add_child(sensors_row)

	return v

# Populate both selectors
func _rebuild_car_selectors() -> void:
	var am := _get_agent_manager()
	var items: Array = []
	if am and !am.cars.is_empty():
		for i in range(am.cars.size()):
			var car = am.cars[i]
			var label := str(car.name)
			if car and "car_data" in car and car.car_data and car.car_data.pilot and car.car_data.pilot.has_method("get_full_name"):
				label = car.car_data.pilot.get_full_name()
			items.append({"label": label, "id": i})
	# Top selector
	if _car_selector_top:
		_car_selector_top.clear()
		for it in items:
			_car_selector_top.add_item(it.label, it.id)
		if _car_selector_top.item_count > 0:
			_car_selector_top.select(0)
	# Tab selector
	if _car_selector_tab:
		_car_selector_tab.clear()
		for it in items:
			_car_selector_tab.add_item(it.label, it.id)
		if _car_selector_tab.item_count > 0:
			_car_selector_tab.select(0)

func _on_car_selected_top(_idx: int) -> void:
	var am := _get_agent_manager()
	if am and _car_selector_top and _car_selector_top.item_count > 0:
		var i := _car_selector_top.get_selected_id()
		if i >= 0 and i < am.cars.size():
			_always_track_best = false
			_set_observed_car(am.cars[i], false)
	# Keep tab selector in sync
	if _car_selector_tab and _car_selector_top:
		_car_selector_tab.select(_car_selector_top.get_selected_index())
	_refresh_input_graph()

func _on_car_selected_tab(_idx: int) -> void:
	var am := _get_agent_manager()
	if am and _car_selector_tab and _car_selector_tab.item_count > 0:
		var i := _car_selector_tab.get_selected_id()
		if i >= 0 and i < am.cars.size():
			_always_track_best = false
			_set_observed_car(am.cars[i], false)
	# Keep top selector in sync
	if _car_selector_top and _car_selector_tab:
		_car_selector_top.select(_car_selector_tab.get_selected_index())
	_refresh_input_graph()

# Build bottom tabs (Brain + Fitness)
func _build_bottom_tabs() -> void:
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var brain := _make_bottom_brain_panel()
	brain.name = "Brain"
	tabs.add_child(brain)

	var fitness := _make_bottom_fitness_panel()
	fitness.name = "Fitness"
	tabs.add_child(fitness)

	# NEW: Inputs tab
	var inputs := _make_bottom_inputs_panel()
	inputs.name = "Inputs"
	tabs.add_child(inputs)

	frame.add_to_bottom(tabs)

func _make_bottom_inputs_panel() -> Control:
	var panel := CollapsiblePanel.new()
	panel.title = "Inputs"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_inputs_graph = InputAxesGraph.new()
	_inputs_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inputs_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.set_content(_inputs_graph)

	_refresh_input_graph()
	return panel

func _refresh_input_graph() -> void:
	if _inputs_graph == null:
		return
	_inputs_graph.set_car(_get_observed_car())

# Brain panel (refactored to return a Control)
func _make_bottom_brain_panel() -> Control:
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
	return panel

# NEW: Fitness panel (moved from top bar)
func _make_bottom_fitness_panel() -> Control:
	var panel := CollapsiblePanel.new()
	panel.title = "Custom Fitness"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var row1 := HBoxContainer.new(); row1.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var chk := CheckBox.new()
	chk.text = "Enable custom fitness"
	chk.tooltip_text = "Toggle custom fitness expression (AgentManager.use_custom_fitness)"
	var am := _get_agent_manager()
	chk.button_pressed = (am and am.use_custom_fitness)
	chk.toggled.connect(func(on: bool):
		var m := _get_agent_manager(); if m: m.use_custom_fitness = on
	)
	row1.add_child(chk)

	v.add_child(row1)

	var row2 := HBoxContainer.new(); row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = "Expression:"
	lbl.tooltip_text = "Variables: total_checkpoints, distance_to_next_checkpoint, time_alive, speed, top_speed + any names set in AgentManager.fitness_variable_paths"
	row2.add_child(lbl)

	var le := LineEdit.new()
	am = _get_agent_manager()
	le.placeholder_text = "e.g. total_checkpoints*1000 + 1000/max(1, distance_to_next_checkpoint)"
	le.text = (am.fitness_expression if am else "")
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_submitted.connect(func(txt: String):
		var m := _get_agent_manager(); if m: m.fitness_expression = txt
	)
	le.focus_exited.connect(func():
		var m := _get_agent_manager(); if m: m.fitness_expression = le.text
	)
	row2.add_child(le)

	var btn := Button.new()
	btn.text = "Apply"
	btn.pressed.connect(func():
		var m := _get_agent_manager(); if m: m.fitness_expression = le.text
	)
	row2.add_child(btn)

	v.add_child(row2)

	var help := Label.new()
	help.text = "Built-ins: total_checkpoints, distance_to_next_checkpoint, time_alive, speed, top_speed"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)

	panel.set_content(v)
	return panel

# Selection helpers -----------------------------------------------------------

func _compute_best_car() -> Car:
	var am := _get_agent_manager()
	if am == null or am.cars.is_empty():
		return null

	var best: Car = null

	var db := _get_data_broker()
	# Fallback to previous behavior if broker/expr is missing
	if db == null or best_car_score_path.strip_edges() == "":
		if am.has_method("get_best_car"):
			best = am.get_best_car()
			if best: return best
		for c in am.cars:
			if c and (!best_car_skip_crashed or !c.crashed):
				return c
		return am.cars[0]

	var best_score := -1.0e100
	for c in am.cars:
		if c == null:
			continue
		if best_car_skip_crashed and c.crashed:
			continue
		var v = db.get_value(c, best_car_score_path)
		var s := 0.0
		match typeof(v):
			TYPE_FLOAT, TYPE_INT:
				s = float(v)
			TYPE_BOOL:
				s = (1.0 if v else 0.0)
			TYPE_STRING:
				# try parse numeric strings
				var p := str(v)
				s = float(p) if p.is_valid_float() else 0.0
			_:
				s = 0.0
		if s > best_score:
			best_score = s
			best = c

	if best:
		return best

	# Last resort
	if am.has_method("get_best_car"):
		return am.get_best_car()
	return am.cars[0]

func _pick_initial_observed() -> void:
	var am := _get_agent_manager()
	if am == null or am.cars.is_empty():
		_observed_car = null
		return
	var target := _compute_best_car() if _always_track_best else null
	if target == null:
		for c in am.cars:
			if c and !c.crashed:
				target = c
				break
	if target == null:
		target = am.cars[0]
	_set_observed_car(target, true)

func _set_observed_car(car: Car, update_selectors: bool = true) -> void:
	if car == _observed_car:
		return
	# Turn off sensors on previous car
	if _show_current_sensors and is_instance_valid(_observed_car):
		_apply_sensors_debug_to_car(_observed_car, false)

	_observed_car = car

	# Turn on sensors on new observed car
	if _show_current_sensors and is_instance_valid(_observed_car):
		_apply_sensors_debug_to_car(_observed_car, true)

	# NEW: update the handle's target
	_update_car_handle_target()

	if update_selectors:
		var am := _get_agent_manager()
		if am:
			var idx := am.cars.find(car)
			if idx >= 0:
				if _car_selector_top and _car_selector_top.item_count > 0:
					_car_selector_top.select(idx)
				if _car_selector_tab and _car_selector_tab.item_count > 0:
					_car_selector_tab.select(idx)
	_refresh_neuron_graph()
	_refresh_input_graph()

# NEW: toggle handler
func _set_show_current_sensors(on: bool) -> void:
	if _show_current_sensors == on:
		return
	_show_current_sensors = on

	# First, disable on all cars to avoid leftovers
	var am := _get_agent_manager()
	if am:
		for c in am.cars:
			_apply_sensors_debug_to_car(c, false)

	# Then apply to current observed (if enabled)
	if on:
		_apply_sensors_debug_to_car(_get_observed_car(), true)

# NEW: apply draw_debug on a car's sensors (if present)
func _apply_sensors_debug_to_car(car: Car, on: bool) -> void:
	if car == null or !is_instance_valid(car):
		return
	var sensors := _get_car_sensors(car)
	if sensors:
		sensors.draw_debug = on
		sensors.queue_redraw()

func _select_relative(step: int) -> void:
	var am := _get_agent_manager()
	if am == null or am.cars.is_empty():
		return
	var n := am.cars.size()
	var cur := am.cars.find(_observed_car)
	if cur < 0: cur = 0
	var next := (cur + step) % n
	if next < 0: next += n
	var car = am.cars[next]
	if car:
		_always_track_best = false
		_set_observed_car(car, true)

# Use observed car everywhere -------------------------------------------------

func _get_observed_car() -> Car:
	if _observed_car and is_instance_valid(_observed_car):
		return _observed_car
	# Fallback to previous logic
	var am := _get_agent_manager()
	if am == null or am.cars.is_empty():
		return null
	if _car_selector_top and _car_selector_top.item_count > 0:
		var id := _car_selector_top.get_selected_id()
		if id >= 0 and id < am.cars.size():
			return am.cars[id]
	for c in am.cars:
		if c and !c.crashed:
			return c
	return am.cars[0]

func _refresh_neuron_graph() -> void:
	if _neuron_graph == null:
		return
	_neuron_graph.set_brain_from_car(_get_observed_car())

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
	var chk_count = (rpm.checkpoints.size() if rpm else 0)
	lbl.text = "Checkpoints: %d" % chk_count
	v.add_child(lbl)

	var btn_rebuild := Button.new()
	btn_rebuild.text = "Rebuild checkpoints"
	btn_rebuild.pressed.connect(func():
		var r = _get_race_progression_manager(); if r: r._cache_checkpoints()
		lbl.text = "Checkpoints: %d" % rpm.checkpoints.size()
	)
	v.add_child(btn_rebuild)

	var btn_clear := Button.new()
	btn_clear.text = "Clear progress"
	btn_clear.pressed.connect(func():
		rpm.car_progress.clear()
	)
	v.add_child(btn_clear)

	# NEW: Checkpoint debug options panel (affects all CheckpointsDebug nodes)
	var dbg_nodes := _get_checkpoint_debug_nodes()
	var dbg0 = (dbg_nodes[0] if dbg_nodes.size() > 0 else null)

	var dbg_panel := CollapsiblePanel.new()
	dbg_panel.title = "Checkpoint Debug"
	dbg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var dbg_v := VBoxContainer.new()
	dbg_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Enabled
	dbg_v.add_child(_make_check_row("Enabled", (dbg0.enabled if dbg0 else false), func(on: bool):
		for n in _get_checkpoint_debug_nodes():
			n.enabled = on
	))

	# Show indices
	dbg_v.add_child(_make_check_row("Show indices", (dbg0.draw_indices if dbg0 else true), func(on: bool):
		for n in _get_checkpoint_debug_nodes():
			n.draw_indices = on
	))

	# Show order lines
	dbg_v.add_child(_make_check_row("Show order lines", (dbg0.draw_order_lines if dbg0 else true), func(on: bool):
		for n in _get_checkpoint_debug_nodes():
			n.draw_order_lines = on
	))

	# Show progress values
	dbg_v.add_child(_make_check_row("Show progress values", (dbg0.draw_progress_values if dbg0 else false), func(on: bool):
		for n in _get_checkpoint_debug_nodes():
			n.draw_progress_values = on
	))

	# Auto-update (redraw every frame)
	dbg_v.add_child(_make_check_row("Auto update", (dbg0.auto_update if dbg0 else true), func(on: bool):
		for n in _get_checkpoint_debug_nodes():
			n.auto_update = on
			n.set_process(on)
	))

	dbg_panel.set_content(dbg_v)
	v.add_child(dbg_panel)

	return v

# Helpers
func _get_checkpoint_debug_nodes() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("checkpoint_debug"):
		if n is CheckpointsDebug:
			out.append(n)
	return out

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

# NEW: DataBroker lookup
func _get_data_broker() -> DataBroker:
	if _db_cached and is_instance_valid(_db_cached):
		return _db_cached
	_db_cached = get_tree().get_first_node_in_group("data_broker") as DataBroker
	if _db_cached == null:
		_db_cached = get_tree().get_root().find_child("DataBroker", true, false) as DataBroker
	return _db_cached

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

# Camera lookup (restored)
func _get_camera() -> Camera2D:
	if is_instance_valid(_camera):
		return _camera
	var root := get_tree().get_root()

	# By group (preferred if you tag it)
	var cam := get_tree().get_first_node_in_group("game_camera") as Camera2D
	if cam:
		return cam

	# By name anywhere in tree
	cam = root.find_child("Camera2D", true, false) as Camera2D
	if cam:
		return cam

	# Fallback: first Camera2D found by traversal
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is Camera2D:
			return n as Camera2D
		for c in n.get_children():
			stack.push_back(c)

	return null

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

# Handle: world-space label next to observed car --------------------------------

func _ensure_car_handle_panel() -> void:
	# Panel (HUD space)
	if _car_handle == null or !is_instance_valid(_car_handle):
		_car_handle = CarHandlePanel.new()
		_car_handle.visible = _show_car_handle
		add_child(_car_handle)
		_position_handle_panel_default()

	# Overlay (world space)
	if _car_handle_overlay == null or !is_instance_valid(_car_handle_overlay):
		var parent_node: Node = _get_camera().get_parent() if _get_camera() else get_tree().get_root()
		_car_handle_overlay = CarHandleLineOverlay.new()
		parent_node.add_child(_car_handle_overlay)

	# Initial sync
	_update_car_handle_target()

func _destroy_car_handle_panel() -> void:
	if _car_handle and is_instance_valid(_car_handle):
		_car_handle.queue_free()
	_car_handle = null
	if _car_handle_overlay and is_instance_valid(_car_handle_overlay):
		_car_handle_overlay.queue_free()
	_car_handle_overlay = null

func _update_car_handle_target() -> void:
	if _car_handle and is_instance_valid(_car_handle):
		_car_handle.visible = _show_car_handle
		_car_handle.set_car(_get_observed_car())
	if _car_handle_overlay and is_instance_valid(_car_handle_overlay):
		var cam := _get_camera()
		_car_handle_overlay.set_refs(cam, _get_observed_car())
		if _car_handle:
			_car_handle_overlay.set_panel_screen_top_left(_car_handle.get_top_left_screen())

# Compute rank using DataBroker score (same path as best-car), higher is better
func _compute_rank_index(target_car: Car) -> int:
	var am := _get_agent_manager()
	if am == null or am.cars.is_empty() or target_car == null:
		return 1
	var db := _get_data_broker()
	var entries: Array = []
	for c in am.cars:
		if c == null:
			continue
		if best_car_skip_crashed and c.crashed:
			continue
		var v = db.get_value(c, best_car_score_path) if db else 0.0
		var s := 0.0
		match typeof(v):
			TYPE_FLOAT, TYPE_INT: s = float(v)
			TYPE_BOOL: s = (1.0 if v else 0.0)
			TYPE_STRING:
				var p := str(v)
				s = float(p) if p.is_valid_float() else 0.0
			_: s = 0.0
		entries.append({"car": c, "score": s})
	# Sort desc by score
	entries.sort_custom(func(a, b):
		return a["score"] > b["score"]
	)
	for i in range(entries.size()):
		if entries[i]["car"] == target_car:
			return i + 1
	return 1

func _position_handle_panel_default() -> void:
	# Place at the center of the bottom-right quadrant of the viewport
	var vp_size := get_viewport().get_visible_rect().size
	var center := Vector2(vp_size.x * 0.75, vp_size.y * 0.75)
	# Defer to ensure the panel has a valid size before centering
	call_deferred("_center_handle_panel_at", center)

func _center_handle_panel_at(center: Vector2) -> void:
	if _car_handle == null or !is_instance_valid(_car_handle):
		return
	var sz := _car_handle.size
	_car_handle.global_position = center - sz * 0.5

func _maybe_switch_best() -> void:
	var now_t := GameManager.global_time if Engine.has_singleton("GameManager") else Time.get_ticks_msec() * 0.001
	if now_t < _best_settle_until or now_t < _best_cooldown_until:
		return

	var am := _get_agent_manager()
	if am == null or am.cars.is_empty():
		return

	var cur := _get_observed_car()
	var cur_score := -INF
	if cur and is_instance_valid(cur) and (!best_car_skip_crashed or !cur.crashed):
		cur_score = _score_for_car(cur)

	var top: Car = cur
	var top_score := cur_score
	for c in am.cars:
		if c == null:
			continue
		if best_car_skip_crashed and c.crashed:
			continue
		if c == cur:
			continue
		var s := _score_for_car(c)
		if top == null or s > top_score:
			top = c
			top_score = s

	if top == null or top == cur:
		return

	var improve_ok := false
	if cur_score <= 0.0:
		improve_ok = top_score > 0.0
	else:
		improve_ok = ((top_score - cur_score) / abs(cur_score)) >= best_switch_hysteresis

	if improve_ok:
		_set_observed_car(top, true)
		_best_cooldown_until = now_t + best_switch_cooldown_sec

func _score_for_car(c: Car) -> float:
	if c == null:
		return -INF
	# Fast path: direct fitness (no broker or parsing)
	if best_car_score_path == "car_data.fitness":
		return float(c.fitness)
	var db := _get_data_broker()
	if db == null:
		return float(c.fitness)
	var v = db.get_value(c, best_car_score_path)
	match typeof(v):
		TYPE_FLOAT, TYPE_INT: return float(v)
		TYPE_BOOL: return (1.0 if v else 0.0)
		TYPE_STRING:
			var p := String(v)
			return float(p) if p.is_valid_float() else 0.0
		_: return 0.0
