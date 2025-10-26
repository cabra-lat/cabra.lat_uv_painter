@tool
extends TextureButton

class_name PluginButton

var plugin_panel : VertexWeightsPluginPanel

var root : Node
var mesh_instance : MeshInstance3D
var handle = false

func show_button(p_root: Node, p_mesh_instance: MeshInstance3D):
  print("PluginButton: show_button called")
  set_pressed_no_signal(false)
  show()
  self.root = p_root
  self.mesh_instance = p_mesh_instance

func hide_button():
  print("PluginButton: hide_button called")
  if plugin_panel:
    plugin_panel.hide_panel()
  set_pressed_no_signal(false)
  hide()

func _on_PluginButton_toggled(button_pressed: bool) -> void:
  print("PluginButton: toggled, pressed = ", button_pressed)
  if button_pressed:
    if plugin_panel and root and mesh_instance:
      plugin_panel.show_panel(root, mesh_instance)
    else:
      print("PluginButton: Missing required references for showing panel")
      set_pressed_no_signal(false)
  else:
    if plugin_panel:
      plugin_panel.hide_panel()
