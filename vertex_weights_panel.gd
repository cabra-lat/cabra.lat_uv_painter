@tool
extends PanelContainer

signal values_changed(brush_color, brush_opacity, brush_size, weight_value)
signal apply_weights()
signal clear_bone()
signal clear_all()
signal bone_selected(bone_index)  # New signal for bone selection

enum Modes {BRUSH, SMOOTH, ERASER}

var mode = Modes.BRUSH
var brush_color :Color = Color.WHITE
var brush_size :float = 0.1
var brush_opacity :float = 1.0
var weight_value :float = 1.0
var available_bones = []  # Array of bone names
var current_bone_index = 0

func setup():
    print("VertexWeightsPanel: setup called")

    # Set initial values
    if has_node("VBoxContainer/WeightContainer/WeightSlider"):
        $VBoxContainer/WeightContainer/WeightSlider.value = weight_value

    if has_node("VBoxContainer/IntensityContainer/IntensitySlider"):
        $VBoxContainer/IntensityContainer/IntensitySlider.value = brush_opacity

    if has_node("VBoxContainer/SizeContainer/SizeSlider"):
        $VBoxContainer/SizeContainer/SizeSlider.value = brush_size

    _on_BrushButton_pressed()

# New function to populate bone dropdown
func setup_bones(bone_names: Array, current_bone: int = 0):
    available_bones = bone_names
    current_bone_index = current_bone

    if has_node("VBoxContainer/BoneContainer/BoneDropdown"):
        var dropdown = $VBoxContainer/BoneContainer/BoneDropdown
        dropdown.clear()

        for i in range(bone_names.size()):
            dropdown.add_item(bone_names[i], i)

        if bone_names.size() > 0:
            dropdown.selected = current_bone
            _on_BoneDropdown_item_selected(current_bone)

func _on_BoneDropdown_item_selected(index: int):
    current_bone_index = index
    emit_signal("bone_selected", index)
    print("Selected bone: ", available_bones[index], " (index: ", index, ")")

func _on_BrushButton_pressed() -> void:
  mode = Modes.BRUSH

  if has_node("VBoxContainer/Modes/BrushButton"):
    $VBoxContainer/Modes/BrushButton.set_pressed_no_signal(true)
  if has_node("VBoxContainer/Modes/SmoothButton"):
    $VBoxContainer/Modes/SmoothButton.set_pressed_no_signal(false)
  if has_node("VBoxContainer/Modes/EraserButton"):
    $VBoxContainer/Modes/EraserButton.set_pressed_no_signal(false)

  if has_node("VBoxContainer/WeightContainer"):
    $VBoxContainer/WeightContainer.show()
  if has_node("VBoxContainer/IntensityContainer"):
    $VBoxContainer/IntensityContainer.show()
  if has_node("VBoxContainer/SizeContainer"):
    $VBoxContainer/SizeContainer.show()

  update_brush()

func _on_SmoothButton_pressed() -> void:
  mode = Modes.SMOOTH

  if has_node("VBoxContainer/Modes/BrushButton"):
    $VBoxContainer/Modes/BrushButton.set_pressed_no_signal(false)
  if has_node("VBoxContainer/Modes/SmoothButton"):
    $VBoxContainer/Modes/SmoothButton.set_pressed_no_signal(true)
  if has_node("VBoxContainer/Modes/EraserButton"):
    $VBoxContainer/Modes/EraserButton.set_pressed_no_signal(false)

  if has_node("VBoxContainer/WeightContainer"):
    $VBoxContainer/WeightContainer.hide()
  if has_node("VBoxContainer/IntensityContainer"):
    $VBoxContainer/IntensityContainer.show()
  if has_node("VBoxContainer/SizeContainer"):
    $VBoxContainer/SizeContainer.show()

  update_brush()

func _on_EraserButton_pressed() -> void:
  mode = Modes.ERASER

  if has_node("VBoxContainer/Modes/BrushButton"):
    $VBoxContainer/Modes/BrushButton.set_pressed_no_signal(false)
  if has_node("VBoxContainer/Modes/SmoothButton"):
    $VBoxContainer/Modes/SmoothButton.set_pressed_no_signal(false)
  if has_node("VBoxContainer/Modes/EraserButton"):
    $VBoxContainer/Modes/EraserButton.set_pressed_no_signal(true)

  if has_node("VBoxContainer/WeightContainer"):
    $VBoxContainer/WeightContainer.hide()
  if has_node("VBoxContainer/IntensityContainer"):
    $VBoxContainer/IntensityContainer.hide()
  if has_node("VBoxContainer/SizeContainer"):
    $VBoxContainer/SizeContainer.show()

  update_brush()

func _on_WeightSlider_value_changed(value: float) -> void:
  weight_value = value
  update_brush()

func _on_IntensitySlider_value_changed(value: float) -> void:
  brush_opacity = value
  update_brush()

func _on_SizeSlider_value_changed(value: float) -> void:
  brush_size = value
  update_brush()

func update_brush():
  var current_brush_color = Color()

  match mode:
    Modes.BRUSH:
      current_brush_color = Color(weight_value, 0, 0, brush_opacity)  # Red for brush
    Modes.SMOOTH:
      current_brush_color = Color(0, weight_value, 0, brush_opacity)  # Green for smooth
    Modes.ERASER:
      current_brush_color = Color(0, 0, 1.0, brush_opacity)  # Blue for eraser

  print("VertexWeightsPanel: Emitting values_changed - Color: ", current_brush_color, " Opacity: ", brush_opacity, " Size: ", brush_size, " Weight: ", weight_value)
  emit_signal("values_changed", current_brush_color, brush_opacity, brush_size, weight_value)

func _on_apply_button_pressed():
  emit_signal("apply_weights")

func _on_clear_all_button_pressed():
  emit_signal("clear_all")

func _on_clear_bone_button_pressed():
  emit_signal("clear_bone")
