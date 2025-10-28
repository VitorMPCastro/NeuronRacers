extends Control
class_name NodePort

signal request_connect(port: NodePort)
signal changed()

@export var is_input: bool = true
@export var label: String = ""
@export var max_connections: int = 1
@export var unlimited: bool = false

var connections: Array[NodePort] = []

const RADIUS := 6.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func _get_node_base() -> BaseNode:
	var n: Node = self
	while n and !(n is BaseNode):
		n = n.get_parent()
	return n as BaseNode

func can_accept_more() -> bool:
	if unlimited:
		return true
	if max_connections <= 0:
		return false
	return connections.size() < max_connections

func is_connected_to(p: NodePort) -> bool:
	for c in connections:
		if c == p:
			return true
	return false

func can_connect_to(other: NodePort) -> bool:
	if other == null or other == self:
		return false
	# block connecting a node to itself
	var a := _get_node_base()
	var b := other._get_node_base()
	if a != null and a == b:
		return false
	# inputs must connect to outputs
	if is_input == other.is_input:
		return false
	# capacity on both ends
	if !self.can_accept_more():
		return false
	if !other.can_accept_more():
		return false
	return true

func connect_to(other: NodePort) -> bool:
	if !can_connect_to(other):
		return false
	if is_connected_to(other):
		return true
	connections.append(other)
	other.connections.append(self)
	changed.emit()
	other.changed.emit()
	return true

func disconnect_from(other: NodePort) -> void:
	if !is_connected_to(other):
		return
	connections.erase(other)
	other.connections.erase(self)
	changed.emit()
	other.changed.emit()

func disconnect_all() -> void:
	for other in connections.duplicate():
		disconnect_from(other)

func get_anchor_global_pos() -> Vector2:
	var rect := get_global_rect()
	var center := rect.get_center()
	var dx := (rect.size.x * 0.5 - 2.0) * (1 if !is_input else -1)
	return center + Vector2(dx, 0)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		request_connect.emit(self)

func _draw() -> void:
	var c := Color(0.9, 0.9, 0.9) if can_accept_more() else Color(0.5, 0.5, 0.5)
	draw_circle(size * 0.5, RADIUS, c)
