@tool
extends EditorPlugin

var plugin_panel : VertexWeightsPluginPanel
var plugin_button : PluginButton
var plugin_cursor : PluginCursor
var editable = false
var mesh_instance: MeshInstance3D  # Track the current mesh instance

func _is_descendant(selected: Node, possible_ancestor: Node) -> bool:
  if not is_instance_valid(selected) or not is_instance_valid(possible_ancestor):
    return false
  var cur := selected
  while cur:
    if cur == possible_ancestor:
      return true
    cur = cur.get_parent()
  return false

func selection_changed() -> void:
  var selection := get_editor_interface().get_selection().get_selected_nodes()
  var root := get_tree().get_edited_scene_root()

  # require exactly one selected node
  if selection.size() != 1:
    editable = false
    if plugin_button:
      plugin_button.hide_button()
    return

  var candidate := selection[0]

  # If the selected node is one of the plugin's UI/tree children, ignore it
  if plugin_panel and _is_descendant(candidate, plugin_panel):
    editable = false
    if plugin_button:
      plugin_button.hide_button()
    return
  if plugin_button and _is_descendant(candidate, plugin_button):
    editable = false
    if plugin_button:
      plugin_button.hide_button()
    return
  if plugin_cursor and _is_descendant(candidate, plugin_cursor):
    editable = false
    if plugin_button:
      plugin_button.hide_button()
    return

  # Also ignore our temporary plugin node if present
  if plugin_cursor and plugin_cursor.temp_plugin_node \
  and is_instance_valid(plugin_cursor.temp_plugin_node) \
  and _is_descendant(candidate, plugin_cursor.temp_plugin_node):
    editable = false
    if plugin_button:
      plugin_button.hide_button()
    return

  # FIXED: Better check for editable children in inherited scenes
  # For inherited scenes, we need to check if the candidate is editable and part of the scene
  var is_editable_in_scene = false

  if root:
    # Check direct ownership
    if candidate.get_owner() == root:
      is_editable_in_scene = true
    # Check for editable children in inherited scenes
    elif candidate.is_editable_instance(root):
      # In inherited scenes, editable children might have different owners
      # but they're still selectable if they're in the current edited scene
      var current = candidate
      while current and current != root:
        if current.get_owner() == root:
          is_editable_in_scene = true
          break
        current = current.get_parent()

  if not root or not is_editable_in_scene:
    editable = false
    if plugin_button:
      plugin_button.hide_button()
    return

  if candidate is MeshInstance3D:
    editable = true
    mesh_instance = candidate  # Store the current mesh instance

    if plugin_button:
      plugin_button.show_button(root, candidate)

    # FIXED: Don't automatically hide panel when selecting mesh
    # Only hide if we're selecting a DIFFERENT mesh and panel is open for current mesh
    if plugin_panel and plugin_panel.is_setup_complete:
      if plugin_panel.mesh_instance != candidate:
        # We're selecting a different mesh, hide the panel
        plugin_panel.hide_panel()
        if plugin_cursor:
          plugin_cursor.hide_cursor()
    else:
      # Panel is not setup, ensure it's hidden
      if plugin_panel:
        plugin_panel.hide_panel()
      if plugin_cursor:
        plugin_cursor.hide_cursor()
  else:
    editable = false
    if plugin_button:
      plugin_button.hide_button()

func _handles(obj) -> bool:
  return editable

func _forward_3d_gui_input(viewport_camera, event):
  if plugin_cursor:
    return plugin_cursor.input(viewport_camera, event)
  return false

func _enter_tree():
  print("Vertex Weights Plugin: Entering tree")

  # Add cursor instance
  plugin_cursor = preload("res://addons/cabra.lat_uv_painter/plugin_cursor.tscn").instantiate()
  if plugin_cursor:
    plugin_cursor.hide()
    add_child(plugin_cursor)
    print("Plugin cursor added")

  # Add panel instance
  plugin_panel = preload("res://addons/cabra.lat_uv_painter/plugin_panel.tscn").instantiate()
  if plugin_panel:
    add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, plugin_panel)
    plugin_panel.hide()
    plugin_panel.plugin_cursor = plugin_cursor
    plugin_panel.editor_filesystem = get_editor_interface().get_resource_filesystem()
    print("Plugin panel added")

  # Add button to 3D scene UI
  plugin_button = preload("res://addons/cabra.lat_uv_painter/plugin_button.tscn").instantiate()
  if plugin_button:
    add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, plugin_button)
    plugin_button.hide()
    plugin_button.plugin_panel = plugin_panel
    print("Plugin button added")

  # Connect selection changed signal
  if get_editor_interface().get_selection():
    get_editor_interface().get_selection().selection_changed.connect(self.selection_changed)
    print("Selection changed signal connected")

  print("Vertex Weights Plugin: Setup complete")

func _exit_tree():
  print("Vertex Weights Plugin: Exiting tree")

  if plugin_button:
    remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, plugin_button)
    plugin_button.queue_free()

  if plugin_panel:
    remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, plugin_panel)
    plugin_panel.queue_free()

  if plugin_cursor:
    plugin_cursor.queue_free()

  print("Vertex Weights Plugin: Cleanup complete")
