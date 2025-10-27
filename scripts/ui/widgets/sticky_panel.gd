extends PopupPanel
class_name StickyPanel

var parent_menu: StickyPanel = null
static var _open: Array = []

func _ready() -> void:
	if not _open.has(self):
		_open.append(self)
	show()
	set_process_input(true)

func _exit_tree() -> void:
	_open.erase(self)

# Queries
static func is_any_open() -> bool:
	return _open.size() > 0

# Close helpers
static func close_all_except(except: StickyPanel = null) -> void:
	for p in _open.duplicate():
		if is_instance_valid(p) and p != except:
			p.queue_free()

static func close_all() -> void:
	for p in _open.duplicate():
		if is_instance_valid(p):
			p.queue_free()

func close_hierarchy_delayed() -> void:
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

	if parent and parent is Control:
		# use method checks and call() to avoid static cast errors
		if parent.has_method("get_global_transform"):
			var gt = parent.call("get_global_transform")
			if gt:
				# gt is a Transform2D-like; multiply inverse by screen_pos
				local_pos = gt.affine_inverse() * screen_pos
				print_debug("[StickyPanel] popup_at_screen: parent Control conversion; parent=", parent, " screen_pos=", screen_pos, " local_pos=", local_pos)
			else:
				print_debug("[StickyPanel] popup_at_screen: parent.get_global_transform() returned null; fallback")
		else:
			print_debug("[StickyPanel] popup_at_screen: parent Control has no get_global_transform(); fallback")
	elif parent and parent is Window:
		local_pos = Vector2(screen_pos) - Vector2(parent.get_position_with_decorations())
		print_debug("[StickyPanel] popup_at_screen: parent Window conversion; screen_pos=", screen_pos, " local_pos=", local_pos)
	else:
		print_debug("[StickyPanel] popup_at_screen: fallback; screen_pos=", screen_pos, " local_pos=", local_pos)

	position = Vector2i(int(round(local_pos.x)), int(round(local_pos.y)))
	show()
	# bring to front
	var p := get_parent()
	if p:
		p.move_child(self, max(0, p.get_child_count() - 1))

	# extra diagnostics: print ancestors of the parent and popup global transform
	var popup_global_origin := Vector2.ZERO
	if has_method("get_global_transform"):
		var self_gt = call("get_global_transform")
		if self_gt:
			popup_global_origin = self_gt.origin
	print_debug("[StickyPanel] final position (parent-local)=", position, " popup_global_origin=", popup_global_origin)

	var anc := get_parent()
	while anc:
		var anc_global := Vector2.ZERO
		if anc.has_method("get_global_transform"):
			var agt = anc.call("get_global_transform")
			if agt:
				anc_global = agt.origin
		print_debug("[StickyPanel] parent_ancestor:", anc, " global_origin=", anc_global, " class=", anc.get_class(), " rect_size=",
			(anc.rect_size if "rect_size" in anc else "N/A"), " position=",
			(anc.position if "position" in anc else "N/A"))
		anc = anc.get_parent()
	print_debug("[StickyPanel] viewport canvas_transform=", (get_viewport().get_canvas_transform() if get_viewport() else "N/A"))

# Spawn a submenu at the same screen coordinate (no extra conversion).
func spawn_child_menu(child: StickyPanel, screen_pos: Vector2) -> void:
	var container := get_parent()
	if child.get_parent() == null:
		if container:
			container.add_child(child)
		else:
			get_tree().root.add_child(child)
	child.parent_menu = self
	# analyzer-safe rounding
	child.position = Vector2i(int(round(screen_pos.x)), int(round(screen_pos.y)))
	child.show()
	var p := child.get_parent()
	if p:
		p.move_child(child, max(0, p.get_child_count() - 1))
	print_debug("[StickyPanel] spawn_child_menu at screen_pos=", screen_pos, " child_pos=", child.position, " parent=", child.get_parent())
