extends StickyPanel
class_name NodeContextMenu

var graph: NodeGraph
var click_pos_screen: Vector2   # viewport/screen coords for popup placement
var click_pos_local: Vector2    # NodeGraph local coords for spawning

func setup(g: NodeGraph, at_screen: Vector2, at_local: Vector2 = Vector2.ZERO) -> void:
	graph = g
	click_pos_screen = at_screen
	# If caller didn’t provide local, compute once from the same screen click
	click_pos_local = at_local if at_local != Vector2.ZERO else graph.screen_to_graph_local(at_screen)
	print_debug("[NodeContextMenu] setup: screen=", click_pos_screen, " graph_local=", click_pos_local, " graph=", graph)

func _build() -> void:
	var content := _ensure_content()
	content.add_theme_constant_override("separation", 2)

	var btn_add := Button.new()
	btn_add.text = "Add Node…"
	btn_add.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_add.pressed.connect(func():
		var cat := NodeCategoryMenu.new()
		cat.setup(graph, click_pos_local, self, click_pos_screen)
		# Place child at the exact same click position in screen coords
		spawn_child_menu(cat, click_pos_screen)
	)
	content.add_child(btn_add)

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
