extends StickyPanel
class_name NodeCategoryMenu

const NodeSpawnMenuScript := preload("res://scripts/ui/nodegraph/context/node_spawn_menu.gd")

var graph: NodeGraph
var click_pos_local: Vector2     # in NodeGraph local space
var click_pos_screen: Vector2    # screen/viewport placement

func setup(g: NodeGraph, at_local: Vector2, parent: StickyPanel, at_screen: Vector2) -> void:
	graph = g
	click_pos_local = at_local
	click_pos_screen = at_screen
	parent_menu = parent
	_build()

func _build() -> void:
	var content := _ensure_content()
	content.add_theme_constant_override("separation", 2)

	var reg = graph.get_node_registry()
	for category in reg.keys():
		var btn := Button.new()
		btn.text = String(category)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func (cat = String(category)):
			var spawn := NodeSpawnMenuScript.new() as NodeSpawnMenu
			spawn.setup(graph, click_pos_local, self, cat)
			# Place child menu at original click screen position
			spawn_child_menu(spawn, click_pos_screen)
		)
		content.add_child(btn)

func _ensure_content() -> VBoxContainer:
	var pc := get_node_or_null("PanelContainer")
	if pc:
		var v := pc.get_node_or_null("Content") as VBoxContainer
		if v: return v
	var bg := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	bg.add_child(vbox)
	add_child(bg)
	return vbox
