extends StickyPanel
class_name NodeContextMenu

# Use NodeGraph as graph type so NodeGraph instances can be passed in
var graph: NodeGraph = null
var click_pos_screen: Vector2 = Vector2.ZERO
var click_pos_local: Vector2 = Vector2.ZERO

func setup(g: NodeGraph, at_screen: Vector2, at_local: Vector2) -> void:
	graph = g
	click_pos_screen = at_screen
	click_pos_local = at_local
	print_debug("[NodeContextMenu] setup: screen=", click_pos_screen, " graph_local=", click_pos_local, " graph=", graph)
	_build()

func _build() -> void:
	var pc := get_node_or_null("PanelContainer")
	if pc:
		pc.queue_free()
	var bg := PanelContainer.new()
	bg.name = "PanelContainer"
	var v := VBoxContainer.new()
	bg.add_child(v)
	add_child(bg)
	var b := Button.new()
	b.text = "Add Node…"
	v.add_child(b)
