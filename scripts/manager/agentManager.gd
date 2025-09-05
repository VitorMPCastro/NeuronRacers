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
@export var hidden_layer_neurons: int = 8
@export var output_layer_neurons: int = 2
@export_category("Debug")
@export var print_debug_generation: bool = false
@export var print_new_brains_to_console: bool = false
var cars = []
var best_cars = []
static var best_speed: int = -1
var generation = 0
var timer = 0.0
@onready var trackOrigin = $"../../track/TrackOrigin"

func _ready():
	if !is_training:
		return
	spawn_population()

func _physics_process(delta: float) -> void:
	update_car_fitness()

func _process(delta):
	if !is_training:
		return
	timer += delta
	get_best_speed()
	if timer >= generation_time || is_all_cars_dead():
		next_generation()

# Spawna uma população inteira
func spawn_population(brains: Array = []):
	cars.clear()
	
	for i in range(population_size):
		var car = car_scene.instantiate()
		car.use_ai = true
		car.position = trackOrigin.position

		if brains.size() > i:
			car.brain = brains[i]
		else:
			car.brain = MLP.new(input_layer_neurons, hidden_layer_neurons, output_layer_neurons)
		
		add_child(car)
		cars.append(car)
	
	print("População criada: ", cars.size())

func next_generation():
	generation += 1
	print("Geração: ", generation)
	var elites = int(population_size * elitism_percent)
	best_cars = cars.slice(0, elites)
	
	sort_by_fitness()
	var new_brains: Array = []
	for i in range(population_size):
		var parent = best_cars[randi() % best_cars.size()]
		var brain = mutate(parent.brain)
		new_brains.append(brain)
	
	# Cria nova população com os cérebros
	print(generation_to_string()) if print_debug_generation else null
	
	clear_scene()
	spawn_population(new_brains)

# Faz mutação nos pesos do MLP
func mutate(brain: MLP):
	var new_brain: MLP = brain.clone()
	
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

func update_car_fitness():
	for car in cars:
		if car:
			kill_stagnant_car(car)
			car.fitness = (car.get_average_speed() / 1000)/(RaceProgressionManager.get_distance_to_next_checkpoint(car) - (car.time_alive / 1000))

func get_best_speed():
	for car in cars:
		if car:
			var avg_speed = car.get_average_speed()
			if avg_speed > AgentManager.best_speed:
				AgentManager.best_speed = avg_speed
	return AgentManager.best_speed

func kill_stagnant_car(car):
	var grace_period = 3.0
	if car.get_average_speed() < AgentManager.best_speed * 0.25 && grace_period < car.time_alive:
		car.die()

func sort_by_fitness():
	cars.sort_custom(func(a, b): if a && b: return a.fitness > b.fitness)

func get_best_car() -> Node:
	sort_by_fitness()
	for car in cars:
		if not car.crashed:
			return car
	return cars[0]

func clear_scene():
	for c in cars:
		c.queue_free()
	cars.clear()
	timer = 0.0

func is_all_cars_dead():
	for car in cars:
		if !car.crashed:
			return false
	return true

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
