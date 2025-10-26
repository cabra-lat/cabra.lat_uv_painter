@tool
extends EditorPlugin

var plugin_panel :VertexWeightsPluginPanel
var plugin_button :PluginButton
var plugin_cursor :PluginCursor
var editable = false

func selection_changed() -> void:
  var selection = get_editor_interface().get_selection().get_selected_nodes()
  if selection.size() == 1 and selection[0] is MeshInstance3D:
    var root = get_tree().get_edited_scene_root()
    var mesh_instance = selection[0]
    editable = true
    plugin_button.show_button(root, mesh_instance)
    plugin_panel.hide_panel()
    plugin_cursor.hide_cursor()
  else:
    editable = false
    plugin_button.hide_button()

func _handles(obj) -> bool:
  return editable

func _forward_3d_gui_input(viewport_camera, event):
  return plugin_cursor.input(viewport_camera, event)

func _enter_tree():
  # Add cursor instance
  plugin_cursor = preload("res://addons/cabra.lat_uv_painter/plugin_cursor.tscn").instantiate()
  plugin_cursor.hide()

  # Add panel instance
  plugin_panel = preload("res://addons/cabra.lat_uv_painter/plugin_panel.tscn").instantiate()
  add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, plugin_panel)
  plugin_panel.hide()
  plugin_panel.plugin_cursor = plugin_cursor
  plugin_panel.editor_filesystem = get_editor_interface().get_resource_filesystem()

  # Add button to 3D scene UI
  plugin_button = preload("res://addons/cabra.lat_uv_painter/plugin_button.tscn").instantiate()
  add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, plugin_button)
  plugin_button.hide()
  plugin_button.plugin_panel = plugin_panel

  get_editor_interface().get_selection().selection_changed.connect(self.selection_changed)

func _exit_tree():
  remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, plugin_button)
  if plugin_button:
    plugin_button.free()

  remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, plugin_panel)
  if plugin_panel:
    plugin_panel.free()
