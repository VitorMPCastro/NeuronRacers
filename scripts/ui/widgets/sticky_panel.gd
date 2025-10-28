extends PopupPanel
class_name StickyPanel

var parent_menu: StickyPanel = null
static var _open := []

static func is_any_open() -> bool:
	return _open.size() > 0

func _ready() -> void:
	if not _open.has(self):
		_open.append(self)
	show()
	set_process_input(true)

func _exit_tree() -> void:
	_open.erase(self)

func close_hierarchy_delayed() -> void:
	# Godot 4: use await instead of yield
	await get_tree().create_timer(0.06).timeout
	for p in _open.duplicate():
		if is_instance_valid(p) and p.parent_menu == self:
			p.queue_free()
	queue_free()

# Restore convenience API expected by context menus --------------------------------
func popup_at(screen_pos: Vector2) -> void:
	# legacy: treat incoming as already-parent-local (existing behavior)
	if get_parent() == null:
		get_tree().root.add_child(self)
	if size.length() < 1.0:
		size = Vector2(220, 120)
	# use analyzer-safe rounding
	position = Vector2i(int(round(screen_pos.x)), int(round(screen_pos.y)))
	show()
	# bring to front
	var p := get_parent()
	if p:
		p.move_child(self, max(0, p.get_child_count() - 1))
	print_debug("[StickyPanel] popup_at (Window coords): screen_pos=", screen_pos, " final_pos=", position, " parent=", get_parent())

# New: place a popup using viewport/screen coordinates (single, correct conversion)
func popup_at_screen(screen_pos: Vector2) -> void:
	# ensure parent exists so we can convert against it
	if get_parent() == null:
		get_tree().root.add_child(self)

	if size.length() < 1.0:
		size = Vector2(220, 120)

	var parent := get_parent()
	var local_pos := Vector2(screen_pos)

	# Convert screen -> parent-local once
	if parent and parent is Control:
		if parent.has_method("get_global_transform"):
			var gt = parent.call("get_global_transform")
			if gt:
				local_pos = gt.affine_inverse() * screen_pos
				print_debug("[StickyPanel] popup_at_screen: parent Control conversion; parent=", parent, " screen_pos=", screen_pos, " local_pos=", local_pos)
	elif parent and parent is Window:
		local_pos = Vector2(screen_pos) - Vector2(parent.get_position_with_decorations())
		print_debug("[StickyPanel] popup_at_screen: parent Window conversion; screen_pos=", screen_pos, " local_pos=", local_pos)
	else:
		print_debug("[StickyPanel] popup_at_screen: fallback; screen_pos=", screen_pos, " local_pos=", local_pos)

	# Place popup (parent-local)
	position = Vector2i(int(round(local_pos.x)), int(round(local_pos.y)))
	show()

	# bring to front
	var p := get_parent()
	if p:
		p.move_child(self, max(0, p.get_child_count() - 1))

	# --- adjust for internal content inset so content top-left = click ----------
	var content_control = get_node_or_null("PanelContainer")
	if content_control == null:
		for c in get_children():
			if c is Control:
				content_control = c
				break

	if content_control and content_control.has_method("get_global_transform") and has_method("get_global_transform"):
		var content_gt = content_control.call("get_global_transform")
		var popup_gt = call("get_global_transform")
		if content_gt and popup_gt:
			var content_global_origin = content_gt.origin
			var popup_global_origin = popup_gt.origin
			var delta = content_global_origin - popup_global_origin
			if delta.length() > 0.001:
				var new_local := Vector2(local_pos.x - delta.x, local_pos.y - delta.y)
				position = Vector2i(int(round(new_local.x)), int(round(new_local.y)))
				print_debug("[StickyPanel] popup_at_screen: adjusted for content offset delta=", delta, " new_local=", new_local, " final_pos=", position)
	# -------------------------------------------------------------------------

	print_debug("[StickyPanel] popup_at_screen: parent=", parent, " screen_pos=", screen_pos, " local_pos=", local_pos)

# Spawn a child StickyPanel; parent next to this menu and position in parent-local using screen coords
func spawn_child_menu(child: StickyPanel, screen_pos: Vector2) -> void:
	var container := get_parent()
	if child.get_parent() == null:
		if container:
			container.add_child(child)
		else:
			get_tree().root.add_child(child)

	child.parent_menu = self
	# compute child local via same conversion: parent is child's parent
	var parent_node := child.get_parent()
	var child_local := Vector2(screen_pos)
	if parent_node and parent_node is Control:
		if parent_node.has_method("get_global_transform"):
			var gt = parent_node.call("get_global_transform")
			if gt:
				child_local = gt.affine_inverse() * screen_pos
	elif parent_node and parent_node is Window:
		child_local = Vector2(screen_pos) - Vector2(parent_node.get_position_with_decorations())

	child.position = Vector2i(int(round(child_local.x)), int(round(child_local.y)))
	child.show()
	var p := child.get_parent()
	if p:
		p.move_child(child, max(0, p.get_child_count() - 1))
