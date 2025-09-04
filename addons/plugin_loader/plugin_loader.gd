@tool
extends EditorPlugin

var inspector_plugin = null

func _enter_tree():
	inspector_plugin = preload("res://addons/dynamic_load_tool/dynamic_load_tool.gd").new()
	add_inspector_plugin(inspector_plugin)

func _exit_tree():
	remove_inspector_plugin(inspector_plugin)
