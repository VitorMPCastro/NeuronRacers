extends Node
class_name SpriteManager

const CARS_DIR := "res://assets/cars"

var _all_textures: Array[Texture2D] = []
var _by_number: Dictionary = {}  # number:int -> Texture2D

func _ready() -> void:
	_preload_car_textures()

func _preload_car_textures() -> void:
	if !_all_textures.is_empty():
		return
	var files := DirAccess.get_files_at(CARS_DIR)
	for f in files:
		if !f.ends_with(".png"):
			continue
		# Skip directional variants and driver icon
		if f.contains("_left") or f.contains("_right") or f.begins_with("driver"):
			continue
		var tex := ResourceLoader.load(CARS_DIR + "/" + f) as Texture2D
		if tex:
			_all_textures.append(tex)
			var n := _extract_number(f)
			if n > 0:
				_by_number[n] = tex

func _extract_number(file_name: String) -> int:
	var digits := ""
	for c in file_name:
		if c.is_valid_int():
			digits += c
		elif digits != "":
			break
	return int(digits) if digits != "" else -1

func get_random_car_texture(skin_seed: int = -1) -> Texture2D:
	if _all_textures.is_empty():
		_preload_car_textures()
	if _all_textures.is_empty():
		return null
	if skin_seed >= 0:
		return _all_textures[abs(skin_seed) % _all_textures.size()]
	return _all_textures[randi() % _all_textures.size()]

func get_car_texture_by_number(number: int) -> Texture2D:
	if _all_textures.is_empty():
		_preload_car_textures()
	return _by_number.get(number, null)

func get_car_texture_for_pilot(pilot: Pilot, fallback_seed: int = -1) -> Texture2D:
	if pilot and pilot.pilot_number > 0:
		var t := get_car_texture_by_number(pilot.pilot_number)
		if t:
			return t
	return get_random_car_texture(fallback_seed)
