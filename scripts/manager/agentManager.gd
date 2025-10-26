extends Node2D
class_name AgentManager

@export_category("Simulation Config")
@export var car_scene: PackedScene
@export var population_size: int = 20
@export var generation_time: float = 20.0
@export var is_training: bool = false
@export_range(0.0, 1.0, 0.01, "How many cars spread their genes") var elitism_percent: float = 0.2
@export_subgroup("Mutation")
@export var weight: float = 0.1
@export var mutate_chance: float = 0.1
@export_subgroup("NN Layers")
@export var input_layer_neurons: int = 5
@export var hidden_layer_neurons: int = 8              # kept for backward compatibility
@export var hidden_layers: PackedInt32Array = PackedInt32Array()   # NEW: use this if non-empty
@export var output_layer_neurons: int = 2
@export_category("Debug")
@export var print_debug_generation: bool = false
@export var print_new_brains_to_console: bool = false
@export var killswitch: bool = true
@export var ai_actions_per_second: float = 20.0:
	get: return _ai_aps
	set(value):
		_ai_aps = max(0.0, value)
		_update_ai_timer()
@export var randomize_car_skins: bool = true

# NEW: control how we decide NN input size and alignment
@export var detect_input_size_from_scene: bool = false  # if true, probe car_scene; otherwise use configured input_layer_neurons
@export var align_nn_to_provided_brains: bool = true    # when spawn_population receives brains, align NN config to those sizes

# NEW: pooling to avoid spike on generation spawn
@export var use_car_pooling: bool = true
var _car_pool: Array[Car] = []

@export_enum("Dump", "Archive") var pilot_retention: String = "Dump"
@export var pilots_archive_path: String = "user://pilot_archive.json"
var _pilot_archive: Array = []

@export_category("Persistence")
@export var save_dir: String = "user://generations"
@export var autosave_each_generation: bool = false
@export var autosave_prefix: String = "gen"   # file name prefix

@export_category("Fitness")
@export var use_custom_fitness: bool = true
@export var fitness_expression: String = "total_checkpoints*1000 + 1000/max(1, distance_to_next_checkpoint)":
	set(value):
		fitness_expression = value
		_rebuild_fitness_expression()
@export var fitness_variable_paths: Dictionary = {}: # name -> DataBroker path on Car
	set(value):
		fitness_variable_paths = value
		_rebuild_fitness_expression()

@export var fitness_evals_per_tick: int = 32
@export var kills_per_tick: int = 8
var _fitness_cursor: int = 0
var _kills_left: int = 0

signal population_spawned
signal generation_completed
signal ai_tick

var cars = []
var best_cars = []
static var best_speed: int = -1
var generation = 0
var timer = 0.0
@onready var gm = self.find_parent("GameManager") as GameManager
@onready var trackOrigin = gm.find_child("TrackOrigin") as Node2D
@onready var data_broker = gm.find_child("DataBroker") as DataBroker
@onready var telemetry: CarTelemetry = self.find_child("CarTelemetry") as CarTelemetry
@onready var sprite_manager: SpriteManager = gm.find_child("SpriteManager") as SpriteManager

@export var ai_phases: int = 4            # split AI decisions over P phases
var _ai_phase_idx: int = 0

# Optional: keep decisions/sec bounded as population grows
@export var auto_scale_ai_aps: bool = true
@export var target_decisions_per_sec: int = 600   # total decisions/sec across all cars
var _ai_aps: float = 20.0
var _ai_timer: Timer

# NEW: queued brains to use on next_generation
var queued_brains_from_json: Array[MLP] = []

var _fitness_expr: Expression = Expression.new()
var _fitness_inputs: PackedStringArray = PackedStringArray()
var _fitness_expr_ok: bool = false
const _FITNESS_FALLBACK := "total_checkpoints*1000 + 1000/max(1, distance_to_next_checkpoint)"


func _ready():
	if !is_training:
		return
	# Build fitness Expression once (editor can override both expression and variables)
	_rebuild_fitness_expression()
	_ai_timer = Timer.new()
	_ai_timer.one_shot = false
	_ai_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(_ai_timer)
	_ai_timer.timeout.connect(_on_ai_timer_timeout)
	_update_ai_timer()
	DirAccess.make_dir_recursive_absolute(save_dir)
	spawn_population()

func _process(delta):
	if !is_training:
		return
	timer += delta
	get_best_speed()
	if timer >= generation_time || is_all_cars_dead():
		next_generation()

func _on_ai_timer_timeout() -> void:
	# Advance phase first so cars see the current phase this tick
	if ai_phases > 1:
		_ai_phase_idx = (_ai_phase_idx + 1) % ai_phases
	_update_car_fitness_budgeted()
	ai_tick.emit()

func get_current_ai_phase() -> int:
	return _ai_phase_idx

# Replace update_car_fitness() with a budgeted version
func _update_car_fitness_budgeted() -> void:
	var n := cars.size()
	if n == 0:
		return
	var rpm := _get_rpm()
	_kills_left = max(0, kills_per_tick)

	var evals := clampi(fitness_evals_per_tick, 1, n)
	var i := 0
	while i < evals:
		var idx := (_fitness_cursor + i) % n
		var car: Car = cars[idx]
		if car and !car.crashed:
			if killswitch:
				_try_kill_stagnant(car)
			# Only compute fitness for alive cars
			car.fitness = _eval_fitness(car, rpm)
		i += 1

	_fitness_cursor = (_fitness_cursor + evals) % n

# Kill logic with rate limit and sane condition (no mass-kill because someone crashed)
func _try_kill_stagnant(car: Car) -> void:
	if _kills_left <= 0:
		return
	if car == null or car.crashed:
		return

	var grace_period := 3.0
	if car.time_alive < grace_period:
		return

	var best = get_best_speed() # cached static best_speed inside this function
	var threshold := 0.15 * float(best) if best > 0 else 0.0
	if car.get_average_speed() < threshold:
		car.die()
		_kills_left -= 1

func _update_ai_timer() -> void:
	if _ai_timer == null:
		return
	var aps := _ai_aps
	if auto_scale_ai_aps and population_size > 0:
		var target := float(target_decisions_per_sec)
		aps = clampf(target / float(max(1, population_size)), 2.0, 30.0)  # clamp to sane bounds
		_ai_aps = aps
	if _ai_aps <= 0.0:
		_ai_timer.stop()              # 0 -> ungated: cars decide every physics frame
		return
	_ai_timer.wait_time = 1.0 / _ai_aps
	# Always restart so new wait_time applies immediately
	if !_ai_timer.is_stopped():
		_ai_timer.stop()
	_ai_timer.start()

# Call this after changing population_size or when spawning a new generation
func _refresh_ai_scaling() -> void:
	_update_ai_timer()

func _current_hidden_sizes() -> PackedInt32Array:
	return hidden_layers if hidden_layers.size() > 0 else PackedInt32Array([hidden_layer_neurons])

func _mlp_hidden_sizes(mlp: MLP) -> PackedInt32Array:
	return mlp.hidden_sizes if mlp.hidden_sizes.size() > 0 else PackedInt32Array([mlp.hidden_size])

func _required_input_size_from_cars() -> int:
	# Prefer configured value to avoid accidental size drift (prevents random reinit)
	if !detect_input_size_from_scene or car_scene == null:
		return max(1, input_layer_neurons)
	var probe := car_scene.instantiate()
	var size := 0
	if probe is Car:
		size = (probe as Car).ai_input_size()
	probe.queue_free()
	return max(1, size)

# Spawna uma população inteira
func spawn_population(brains: Array = []):
	cars.clear()

	# If we were given brains (from evolution or JSON), align config so we don't resize/mutate randomly
	if align_nn_to_provided_brains and brains.size() > 0 and brains[0] is MLP:
		_align_nn_config_to_brain(brains[0] as MLP)

	var required_input := _required_input_size_from_cars()
	var desired_hidden := _current_hidden_sizes()

	# Cache commonly used refs once
	var gm_node = gm
	var track := gm_node.find_child("Track") as Track
	var use_center := track and is_instance_valid(track.center_line) and track.center_line.points.size() > 0
	var base_spawn = (track.to_global(track.center_line.points[0]) if use_center else (trackOrigin.global_position if is_instance_valid(trackOrigin) else Vector2.ZERO))

	for i in range(population_size):
		var car: Car = null
		if use_car_pooling and _car_pool.size() > 0:
			car = _car_pool.pop_back()
		else:
			car = car_scene.instantiate()

		car.reset_for_spawn(base_spawn, 0.0)

		# New pilot and brain
		var pilot := PilotFactory.create_random_pilot()

		# ALWAYS give the pilot a brain; avoid random reinit by cloning provided brain 1:1
		var brain: MLP = null
		if brains.size() > i and brains[i] != null:
			var base: MLP = brains[i]
			var mismatch := (
				base.input_size != required_input or
				_mlp_hidden_sizes(base) != desired_hidden or
				base.output_size != output_layer_neurons
			)
			if mismatch:
				# Align once more just in case the first brain differed (mixed sizes array)
				if align_nn_to_provided_brains:
					_align_nn_config_to_brain(base)
					required_input = _required_input_size_from_cars()
					desired_hidden = _current_hidden_sizes()
				# Final check; if still mismatched, just clone (do NOT randomize with mutate)
				brain = base.clone()
			else:
				brain = base.clone()
		else:
			# Initial population (no brains passed): create fresh random MLP
			brain = MLP.new(required_input, desired_hidden, output_layer_neurons)

		pilot.brain = brain
		car.car_data.pilot = pilot
		# Tie pilot lifecycle to car to avoid leaks and ensure clean reuse
		car.add_child(pilot)
		var cb: Callable = Callable(pilot, "notify_ai_tick")
		if !is_connected("ai_tick", cb):
			ai_tick.connect(cb)

		# Optional skin randomization
		if randomize_car_skins:
			var sprite := car.get_node_or_null("Sprite2D") as Sprite2D
			if sprite and sprite_manager:
				var seed_local := int(i)
				var tex := sprite_manager.get_car_texture_for_pilot(pilot, seed_local)
				if tex: sprite.texture = tex

		# Add or re-add car under manager
		if car.get_parent() != self:
			add_child(car)
		cars.append(car)

	population_spawned.emit()
	print("População criada: ", cars.size())

# Ensure our NN config matches a provided brain (prevents unintended resizes)
func _align_nn_config_to_brain(b: MLP) -> void:
	if b == null:
		return
	input_layer_neurons = int(b.input_size)
	if b.hidden_sizes.size() > 0:
		hidden_layers = b.hidden_sizes
	else:
		hidden_layer_neurons = int(b.hidden_size)
		hidden_layers = PackedInt32Array()  # keep legacy single-layer if needed
	output_layer_neurons = int(b.output_size)

func weighted_pick(cars_local: Array, total_fitness) -> Car:
	var r = randf() * total_fitness
	var cumulative = 0.0
	for car in cars_local:
		cumulative += car.fitness
		if r <= cumulative:
			return car
	return cars_local[-1]  # fallback in case of float precision issues

func next_generation():
	generation_completed.emit()
	generation += 1
	print("Geração: ", generation)
	var elites = max(1, int(population_size * elitism_percent))   # ensure at least one elite
	sort_by_fitness()
	best_cars = cars.slice(0, elites)

	var total_fitness := 0.0
	for car in best_cars:
		total_fitness += max(0.0, car.fitness)

	sort_by_fitness()

	# Use queued brains from JSON if present
	var new_brains: Array = []
	if !queued_brains_from_json.is_empty():
		new_brains = queued_brains_from_json.duplicate(true)
		queued_brains_from_json.clear()
	else:
		var required_input := _required_input_size_from_cars()
		for i in range(population_size):
			var parent: Car = null
			if total_fitness > 0.0:
				parent = weighted_pick(best_cars, total_fitness)
			else:
				# All fitness == 0: pick round-robin or random from elites to avoid degenerate selection
				parent = best_cars[i % best_cars.size()]
			var brain = mutate(parent.car_data.pilot.brain, required_input)  # supports multi-layer
			new_brains.append(brain)

	print(generation_to_string() if print_debug_generation else "") 

	clear_scene()
	spawn_population(new_brains)
	print(self.get_signal_connection_list("ai_tick").size())

# Faz mutação nos pesos do MLP (supports multi-layer)
func mutate(brain: MLP, required_input_size: int):
	var desired_hidden := _current_hidden_sizes()

	var needs_resize := (
		brain.input_size != required_input_size or
		_mlp_hidden_sizes(brain) != desired_hidden or
		brain.output_size != output_layer_neurons
	)

	var new_brain: MLP = null
	if needs_resize:
		new_brain = MLP.new(required_input_size, desired_hidden, output_layer_neurons)
	else:
		new_brain = brain.clone()

	# Mutate across all layers if available; otherwise legacy fields
	if new_brain.weights.size() > 0 and new_brain.biases.size() == new_brain.weights.size():
		for l in range(new_brain.weights.size()):
			var w: PackedFloat32Array = new_brain.weights[l]
			for i in range(w.size()):
				if randf() < mutate_chance:
					w[i] += randf_range(-weight, weight)
			new_brain.weights[l] = w

			var b: PackedFloat32Array = new_brain.biases[l]
			for i in range(b.size()):
				if randf() < mutate_chance:
					b[i] += randf_range(-weight, weight)
			new_brain.biases[l] = b
	else:
		for i in range(new_brain.w1.size()):
			if randf() < mutate_chance:
				new_brain.w1[i] += randf_range(-weight, weight)
		for i in range(new_brain.w2.size()):
			if randf() < mutate_chance:
				new_brain.w2[i] += randf_range(-weight, weight)
		for i in range(new_brain.b1.size()):
			if randf() < mutate_chance:
				new_brain.b1[i] += randf_range(-weight, weight)
		for i in range(new_brain.b2.size()):
			if randf() < mutate_chance:
				new_brain.b2[i] += randf_range(-weight, weight)

	return new_brain

# JSON persistence: include hidden_layers array in addition to legacy "hidden"
func save_generation_to_json(file_path: String = "", brains: Array = [], note: String = "") -> String:
	var brains_to_save: Array = brains
	if brains_to_save.is_empty():
		for c in cars:
			if c and c.car_data and c.car_data.pilot and c.car_data.pilot.brain:
				brains_to_save.append(c.car_data.pilot.brain)

	if brains_to_save.is_empty():
		push_error("AgentManager.save_generation_to_json: No brains to save.")
		return ""

	var required_input := _required_input_size_from_cars()
	var payload := {
		"version": 2,
		"timestamp": Time.get_unix_time_from_system(),
		"generation": generation,
		"population_size": brains_to_save.size(),
		"nn": {
			"input": required_input,
			"hidden": hidden_layer_neurons,
			"hidden_layers": _current_hidden_sizes(),
			"output": output_layer_neurons
		},
		"evolution": {
			"elitism_percent": elitism_percent,
			"mutate_chance": mutate_chance,
			"weight": weight
		},
		"ai_actions_per_second": _ai_aps,
		"note": note,
		"brains": brains_to_save.map(func(b: MLP) -> Dictionary: return b.to_dict())
	}

	var json := JSON.stringify(payload, "  ")
	var path := file_path
	if path.is_empty():
		var fname := "%s_g%03d_%d.json" % [autosave_prefix, generation, int(Time.get_unix_time_from_system())]
		path = save_dir.rstrip("/") + "/" + fname

	var ok := _write_text_file(path, json)
	if ok:
		print("Saved generation to: ", path)
		return path
	push_error("AgentManager.save_generation_to_json: Failed to write file at " + path)
	return ""

func load_generation_from_json(path: String, allow_resize: bool = false) -> void:
	var txt := _read_text_file(path)
	if txt.is_empty():
		push_error("AgentManager.load_generation_from_json: File empty or not found: " + path)
		return
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("AgentManager.load_generation_from_json: Invalid JSON.")
		return

	var saved_gen := int(data.get("generation", 0))
	var nn = data.get("nn", {})
	var saved_in := int(nn.get("input", 0))
	var saved_out := int(nn.get("output", output_layer_neurons))
	var saved_hidden_layers := PackedInt32Array(nn.get("hidden_layers", PackedInt32Array()))
	if saved_hidden_layers.size() == 0:
		# Legacy
		saved_hidden_layers = PackedInt32Array([int(nn.get("hidden", hidden_layer_neurons))])

	var brains_arr = data.get("brains", [])
	if brains_arr.is_empty():
		push_error("AgentManager.load_generation_from_json: No brains in file.")
		return

	var brains: Array[MLP] = []
	for d in brains_arr:
		var mlp := MLP.from_dict(d)
		brains.append(mlp)

	var required_input := _required_input_size_from_cars()
	var same_sizes := (saved_in == required_input and saved_hidden_layers == _current_hidden_sizes() and saved_out == output_layer_neurons)
	if not same_sizes and not allow_resize:
		push_error("Saved NN sizes (%s,%s,%s) do not match current config (%s,%s,%s). Set allow_resize=true or align config."
			% [saved_in, saved_hidden_layers, saved_out, required_input, _current_hidden_sizes(), output_layer_neurons])
		return

	if data.has("evolution"):
		var evo = data["evolution"]
		if evo.has("elitism_percent"): elitism_percent = float(evo["elitism_percent"])
		if evo.has("mutate_chance"): mutate_chance = float(evo["mutate_chance"])
		if evo.has("weight"): weight = float(evo["weight"])
	if data.has("ai_actions_per_second"):
		ai_actions_per_second = float(data["ai_actions_per_second"])

	clear_scene()
	spawn_population(brains)
	generation = saved_gen
	timer = 0.0
	print("Loaded generation ", generation, " from ", path)

func _write_text_file(path: String, content: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(content)
	f.flush()
	f.close()
	return true

func _read_text_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt

func _get_rpm() -> RaceProgressionManager:
	return get_tree().get_first_node_in_group("race_progression") as RaceProgressionManager

func _rebuild_fitness_expression() -> void:
	# Built-in variable names we always provide
	var builtin := PackedStringArray([
		"total_checkpoints",
		"distance_to_next_checkpoint",
		"time_alive",
		"speed",
		"top_speed"
	])
	# Add user variables (keys of dictionary)
	var user_vars := PackedStringArray()
	for k in fitness_variable_paths.keys():
		user_vars.push_back(String(k))
	# Merge, preserve order: builtin then user
	_fitness_inputs = PackedStringArray()
	_fitness_inputs.append_array(builtin)
	_fitness_inputs.append_array(user_vars)

	var expr_str := fitness_expression if fitness_expression.strip_edges() != "" else _FITNESS_FALLBACK
	_fitness_expr = Expression.new()
	var err := _fitness_expr.parse(expr_str, _fitness_inputs)
	_fitness_expr_ok = (err == OK)
	if !_fitness_expr_ok:
		push_warning("Fitness expression parse error. Using fallback. expr=" + expr_str)

# Build the values array (same order as _fitness_inputs) for a given car
func _build_fitness_inputs_for_car(car: Car, rpm: RaceProgressionManager) -> Array:
	var values: Array = []
	# Builtins (must match order in _rebuild_fitness_expression)
	var total_cp := 0
	if rpm and rpm.car_state.has(car):
		total_cp = int(rpm.car_state[car]["checkpoints"])
	var dist_next := 1e6
	if rpm:
		dist_next = rpm.get_distance_to_next_checkpoint(car)
	dist_next = max(1.0, float(dist_next)) # avoid division by zero in user expr

	var time_alive := float(car.time_alive)
	var speed := float(car.velocity.length())
	var top_speed := float(car.car_data.top_speed)

	values.append(float(total_cp))
	values.append(float(dist_next))
	values.append(float(time_alive))
	values.append(float(speed))
	values.append(float(top_speed))

	# User variables via DataBroker on the Car provider
	if is_instance_valid(data_broker):
		for k in fitness_variable_paths.keys():
			var path := String(fitness_variable_paths[k])
			var v = data_broker.get_value(car, path)
			match typeof(v):
				TYPE_INT, TYPE_FLOAT:
					values.append(float(v))
				_:
					values.append(0.0)
	else:
		# No broker: append zeros for user vars
		for _k in fitness_variable_paths.keys():
			values.append(0.0)
	return values

func _eval_fitness(car: Car, rpm: RaceProgressionManager) -> float:
	# Fast path using Expression if enabled and valid
	if use_custom_fitness and _fitness_expr_ok and _fitness_inputs.size() > 0:
		var inputs := _build_fitness_inputs_for_car(car, rpm)
		var result = _fitness_expr.execute(inputs, null, false)
		if typeof(result) == TYPE_FLOAT or typeof(result) == TYPE_INT:
			return float(result)
	# Fallback to default formula
	var total_cp := 0
	if rpm and rpm.car_state.has(car):
		total_cp = int(rpm.car_state[car]["checkpoints"])
	var dist := 1.0
	if rpm:
		dist = max(1.0, rpm.get_distance_to_next_checkpoint(car))
	return float(total_cp) * 1000.0 + 1000.0 / dist

func update_car_fitness():
	var rpm := _get_rpm()
	for car in cars:
		if car:
			if killswitch:
				kill_stagnant_car(car)
			car.fitness = _eval_fitness(car, rpm)

func get_best_speed():
	for car in cars:
		if car and !car.crashed:
			var avg_speed = car.get_average_speed()
			if avg_speed > AgentManager.best_speed:
				AgentManager.best_speed = avg_speed
	return AgentManager.best_speed

func kill_stagnant_car(car):
	var grace_period = 3.0
	var active_cars = []
	for c in cars:
		if !c.crashed:
			active_cars.append(c)
	if cars.size() > active_cars.size():
		if car.get_average_speed() < AgentManager.best_speed * 0.15 and grace_period < car.time_alive:
			car.die()

func sort_by_fitness():
	cars.sort_custom(func(a, b): if a && b: return a.fitness > b.fitness)
	var cars_by_fitness = cars.duplicate(true)
	return cars_by_fitness

func get_best_car() -> Node:
	var sorted = sort_by_fitness()
	for car in sorted:
		if not car.crashed:
			return car
	return sorted[0]

func clear_scene():
	# Pool cars instead of freeing to avoid large allocation spikes next spawn.
	if use_car_pooling:
		for c in cars:
			if c == null: continue
			# Handle pilot gracefully
			if c.car_data and c.car_data.pilot:
				var p = c.car_data.pilot
				# Disconnect ai_tick
				var cb: Callable = Callable(p, "notify_ai_tick")
				if is_connected("ai_tick", cb):
					disconnect("ai_tick", cb)
				# Archive or dump
				if pilot_retention == "Archive":
					_archive_pilot(p)
				# Remove node
				if p.get_parent():
					p.queue_free()
				c.car_data.pilot = null
			# Deactivate and pool the car
			c.prepare_for_pool()
			_car_pool.append(c)
		cars.clear()
		timer = 0.0
		return

	# Fallback: free cars
	for c in cars:
		if c:
			# Also disconnect/dump pilot when not pooling
			if c.car_data and c.car_data.pilot:
				var p = c.car_data.pilot
				var cb2: Callable = Callable(p, "notify_ai_tick")
				if is_connected("ai_tick", cb2):
					disconnect("ai_tick", cb2)
				if pilot_retention == "Archive":
					_archive_pilot(p)
				if p.get_parent():
					p.queue_free()
				c.car_data.pilot = null
			c.queue_free()
	cars.clear()
	timer = 0.0


func generation_to_string(options: Dictionary = {
	"car_obj": {"print": false, "once": false},
	"car_fitness": {"print": false, "once": false},
	"car_brain": {"print": false, "once": false},
	"new_brains": {"print": true, "once": true}
}) -> String:
	
	var generation_string = str("\n GENERATION ", generation)
	var function_extractor = {
		"car_obj": func(car = null) -> String: return car._to_string(), 
		"car_fitness": func(car = null) -> String: return car.fitness, 
		"car_brain": func(car = null) -> String: return car.brain,
		"new_brains": func(new_brains: Array[MLP] = []) -> String: return str(new_brains.map(func(brain): brain._to_string()))
	}
	
	for key in options as Dictionary:
		if options[key]["print"]:
			for car in cars:
				generation_string += str("\n", key, ": ", function_extractor[key].call(car))
				if options[key]["once"]:
					break
	
	
	return generation_string

func is_all_cars_dead():
	for car in cars:
		if !car.crashed:
			return false
	return true

# NEW: queue brains from a JSON file for the next generation (does not replace current gen immediately)
func queue_generation_json(path: String, allow_resize: bool = true) -> bool:
	var txt := _read_text_file(path)
	if txt.is_empty():
		push_error("queue_generation_json: File empty or not found: " + path)
		return false
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("queue_generation_json: Invalid JSON.")
		return false

	var nn = data.get("nn", {})
	var saved_in := int(nn.get("input", 0))
	var saved_out := int(nn.get("output", output_layer_neurons))
	var saved_hidden_layers := PackedInt32Array(nn.get("hidden_layers", PackedInt32Array()))
	if saved_hidden_layers.size() == 0:
		# legacy format support
		saved_hidden_layers = PackedInt32Array([int(nn.get("hidden", hidden_layer_neurons))])

	var brains_arr = data.get("brains", [])
	if brains_arr.is_empty():
		push_error("queue_generation_json: No brains in file.")
		return false

	# Optionally validate sizes; if !allow_resize, require exact match
	if !allow_resize:
		var required_input := _required_input_size_from_cars()
		if saved_in != required_input or saved_hidden_layers != _current_hidden_sizes() or saved_out != output_layer_neurons:
			push_error("queue_generation_json: NN sizes from file (%s,%s,%s) do not match current config (%s,%s,%s)."
				% [saved_in, saved_hidden_layers, saved_out, required_input, _current_hidden_sizes(), output_layer_neurons])
			return false

	# Parse brains now; spawn_population will handle size mismatches gracefully per-car
	queued_brains_from_json.clear()
	for d in brains_arr:
		var mlp := MLP.from_dict(d)
		queued_brains_from_json.append(mlp)

	# Optionally adopt evolution/APS settings from file (commented out; enable if desired)
	# if data.has("evolution"):
	# 	var evo = data["evolution"]
	# 	if evo.has("elitism_percent"): elitism_percent = float(evo["elitism_percent"])
	# 	if evo.has("mutate_chance"): mutate_chance = float(evo["mutate_chance"])
	# 	if evo.has("weight"): weight = float(evo["weight"])
	# if data.has("ai_actions_per_second"):
	# 	ai_actions_per_second = float(data["ai_actions_per_second"])

	return true

func _debug_dump_brain_sizes(_tag: String, arr: Array) -> void:
	if arr.is_empty(): return
	var b := arr[0] as MLP
	print("[%s] NN sizes: in=", b.input_size, " hidden=", (b.hidden_sizes if b.hidden_sizes.size()>0 else PackedInt32Array([b.hidden_size])), " out=", b.output_size)

func _archive_pilot(p: Pilot) -> void:
	if p == null:
		return
	var rec := {
		"first_name": p.pilot_first_name,
		"last_name": p.pilot_last_name,
		"number": p.pilot_number,
	}
	# Brain archival is optional; avoid heavy payload unless you add MLP.to_dict()
	if p.brain and p.brain.has_method("to_dict"):
		rec["brain"] = p.brain.to_dict()
	_pilot_archive.append(rec)

func save_pilot_archive(path: String = "") -> bool:
	var out_path := path if path != "" else pilots_archive_path
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	if fa == null:
		push_error("save_pilot_archive: could not open file: " + out_path)
		return false
	var txt := JSON.stringify(_pilot_archive, "  ")
	fa.store_string(txt)
	fa.flush()
	fa.close()
	return true
