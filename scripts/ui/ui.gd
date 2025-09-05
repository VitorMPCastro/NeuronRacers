extends Control

signal start_simulation(population_size: int, simulation_time: float)

@onready var population_spin: SpinBox = $VBoxContainer/SpinBox
@onready var time_spin: SpinBox = $VBoxContainer/SpinBox2
@onready var start_button: Button = $VBoxContainer/Button

func _ready():
	population_spin.value = 20
	time_spin.value = 30
	start_button.pressed.connect(_on_start_pressed)

func _on_start_pressed():
	var pop_size = int(population_spin.value)
	var sim_time = float(time_spin.value)
	emit_signal("start_simulation", pop_size, sim_time)
