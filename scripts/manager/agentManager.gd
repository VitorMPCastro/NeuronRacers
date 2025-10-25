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

var _ai_timer: Timer
var _ai_aps: float = 20.0

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

	# Initialize and START the timer based on the exported APS
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
	update_car_fitness()         # do it at ai_actions_per_second
	ai_tick.emit()

func _update_ai_timer() -> void:
	if _ai_timer == null:
		return
	if _ai_aps <= 0.0:
		_ai_timer.stop()              # 0 -> ungated: cars decide every physics frame
		return
	_ai_timer.wait_time = 1.0 / _ai_aps
	# Always restart so new wait_time applies immediately
	if !_ai_timer.is_stopped():
		_ai_timer.stop()
	_ai_timer.start()

func _current_hidden_sizes() -> PackedInt32Array:
	return hidden_layers if hidden_layers.size() > 0 else PackedInt32Array([hidden_layer_neurons])

func _mlp_hidden_sizes(mlp: MLP) -> PackedInt32Array:
	return mlp.hidden_sizes if mlp.hidden_sizes.size() > 0 else PackedInt32Array([mlp.hidden_size])

func _required_input_size_from_cars() -> int:
	# Prefer live car scene probe if available; otherwise use input_layer_neurons
	if car_scene == null:
		return input_layer_neurons
	var probe := car_scene.instantiate()
	var size := 0
	if probe is Car:
		size = (probe as Car).ai_input_size()
	probe.queue_free()
	return max(1, size)

# Spawna uma população inteira
func spawn_population(brains: Array = []):
	cars.clear()

	var required_input := _required_input_size_from_cars()
	var h_sizes := _current_hidden_sizes()

	for i in range(population_size):
		var car = car_scene.instantiate()
		car.use_ai = true

		# Compute spawn position:
		var spawn_pos := Vector2.ZERO
		# Prefer exact center_line first point if available
		var track := gm.find_child("Track") as Track
		if track and is_instance_valid(track.center_line) and track.center_line.points.size() > 0:
			spawn_pos = track.to_global(track.center_line.points[0])
		elif is_instance_valid(trackOrigin):
			# Fallback: TrackOrigin node (in world space)
			spawn_pos = trackOrigin.global_position

		car.global_position = spawn_pos
		# ...existing code...
		var pilot := PilotFactory.create_random_pilot()
		if brains.size() > i:
			var base: MLP = brains[i]
			var base_hidden := _mlp_hidden_sizes(base)
			var sizes_match := (
				base.input_size == required_input and
				base_hidden == h_sizes and
				base.output_size == output_layer_neurons
			)
			if sizes_match:
				pilot.brain = base.clone()
			else:
				push_warning("Provided brain size mismatch; reinitializing. Got in/hid/out=%s/%s/%s, need %s/%s/%s"
					% [base.input_size, base_hidden, base.output_size, required_input, h_sizes, output_layer_neurons])
				pilot.brain = MLP.new(required_input, h_sizes, output_layer_neurons)
		else:
			pilot.brain = MLP.new(required_input, h_sizes, output_layer_neurons)

		car.car_data.pilot = pilot
		ai_tick.connect(pilot.notify_ai_tick)

		if randomize_car_skins and sprite_manager:
			var sprite := car.get_node_or_null("Sprite2D") as Sprite2D
			if sprite:
				var seed := int(i)
				var tex := sprite_manager.get_car_texture_for_pilot(pilot, seed)
				if tex:
					sprite.texture = tex

		add_child(car)
		cars.append(car)

	population_spawned.emit()
	print("População criada: ", cars.size())

func weighted_pick(cars: Array, total_fitness) -> Car:
	var r = randf() * total_fitness
	var cumulative = 0.0
	for car in cars:
		cumulative += car.fitness
		if r <= cumulative:
			return car
	return cars[-1]  # fallback in case of float precision issues

func next_generation():
	generation_completed.emit()
	generation += 1
	print("Geração: ", generation)
	var elites = int(population_size * elitism_percent)
	sort_by_fitness()
	best_cars = cars.slice(0, elites)

	var total_fitness := 0.0
	for car in best_cars:
		total_fitness += car.fitness

	sort_by_fitness()

	# NEW: if a JSON was queued, use those brains instead of evolving
	var new_brains: Array = []
	if !queued_brains_from_json.is_empty():
		new_brains = queued_brains_from_json.duplicate(true)
		queued_brains_from_json.clear()
	else:
		var required_input := _required_input_size_from_cars()
		for i in range(population_size):
			var parent = weighted_pick(best_cars, total_fitness)
			var brain = mutate(parent.car_data.pilot.brain, required_input)  # supports multi-layer
			new_brains.append(brain)

	print(generation_to_string()) if print_debug_generation else null

	clear_scene()
	spawn_population(new_brains)

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
		if car:
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
		if car.get_average_speed() < AgentManager.best_speed * 0.15 && grace_period < car.time_alive:
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
	for c in cars:
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
