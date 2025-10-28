extends StickyPanel
class_name NodeSpawnMenu

var graph: NodeGraph
var click_pos_local: Vector2   # in NodeGraph local space
var category: String

func setup(g: NodeGraph, at_local: Vector2, parent: StickyPanel, cat: String) -> void:
	graph = g
	click_pos_local = at_local
	parent_menu = parent
	category = cat
	_build()

func _build() -> void:
	var content := _ensure_content()
	content.add_theme_constant_override("separation", 2)
	var entries: Array = graph.get_node_registry().get(category, [])
	print_debug("[NodeSpawnMenu] building category", category, " entries=", entries.size())
	for entry in entries:
		var btn := Button.new()
		btn.text = entry.get("name", "Node")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func():
			# Spawn at graph-local position
			graph.spawn_node_from_entry(entry, click_pos_local)
			# Close full chain with small delay so the press handler finishes
			var root_menu: StickyPanel = self
			while root_menu.parent_menu:
				root_menu = root_menu.parent_menu
			root_menu.close_hierarchy_delayed()
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
