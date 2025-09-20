extends Node
class_name RaceProgressionManager

# Lista de checkpoints (Nodes com dois filhos: "A" e "B")
@export var checkpoint_nodes: Array[NodePath] = []

# Lista de pares de pontos que formam os segmentos dos checkpoints
static var checkpoints: Array = []
static var sectors: Array[Sector]

# Progresso de cada carro: {car: {index: int, checkpoints: int}}
static var car_progress: Dictionary = {}

var sector: Dictionary = {}

func _ready():
	_cache_checkpoints()
	print(checkpoints.size())


func _cache_checkpoints():
	"""
	Preenche a lista de checkpoints como segmentos [(A, B), ...].
	"""
	checkpoints.clear()
	for cp_path in checkpoint_nodes:
		var cp_node = get_node(cp_path)
		var a = cp_node.get_node("A").global_position
		var b = cp_node.get_node("B").global_position
		checkpoints.append([a, b])


static func register_car(car: Node):
	"""
	Registra um novo carro no sistema de progressão.
	"""
	car_progress[car] = {
		"index": 0,
		"checkpoints": 0,
		"time_collected": 0.0
	}


static func update_car_progress(car: Node, old_pos: Vector2, new_pos: Vector2):
	"""
	Checa se o carro cruzou o próximo checkpoint.
	"""
	if not car_progress.has(car):
		return

	var current_index = car_progress[car]["index"]
	if current_index >= checkpoints.size()-1:
		car_progress[car]["index"] = 0

	var cp = checkpoints[current_index]
	var crossed = Utils.segments_intersect(old_pos, new_pos, cp[0], cp[1])

	if crossed:
		car_progress[car]["index"] += 1
		car_progress[car]["checkpoints"] += 1
		car_progress[car]["time_collected"] = GameManager.global_time
		car.car_data.collected_checkpoints.append(car_progress[car].duplicate())
	


static func get_next_checkpoint_position(car: Node) -> Vector2:
	"""
	Retorna a posição central do próximo checkpoint para esse carro.
	"""
	if not car_progress.has(car):
		return Vector2.ZERO

	var idx = car_progress[car]["index"]
	if idx >= checkpoints.size():
		return Vector2.ZERO

	var cp = checkpoints[idx]
	return (cp[0] + cp[1]) * 0.5


static func get_distance_to_next_checkpoint(car: Node) -> float:
	"""
	Distância até o próximo checkpoint (para usar como entrada da IA).
	"""
	if not car_progress.has(car):
		return 0.0

	var car_pos = car.global_position
	var next_cp = get_next_checkpoint_position(car)
	return car_pos.distance_to(next_cp)
