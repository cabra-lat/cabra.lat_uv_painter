@tool
class_name VertexWeightsPanel
extends PanelContainer

# Signal sent when parameters are changed
signal values_changed(brush_color, brush_opacity, brush_size)

enum Modes {BRUSH, SMOOTH, ERASER}

var mode = Modes.BRUSH
var brush_color :Color
var brush_size :float
var brush_opacity :float
var weight_value :float = 1.0

func setup():
  _on_BrushButton_pressed()
  $VBoxContainer/WeightContainer/WeightSlider.value = weight_value

# When brush button pressed, show brush panel
func _on_BrushButton_pressed() -> void:
  mode = Modes.BRUSH
  $VBoxContainer/Modes/BrushButton.set_pressed_no_signal(true)
  $VBoxContainer/Modes/SmoothButton.set_pressed_no_signal(false)
  $VBoxContainer/Modes/EraserButton.set_pressed_no_signal(false)

  $VBoxContainer/WeightContainer.show()
  $VBoxContainer/IntensityContainer.show()
  $VBoxContainer/SizeContainer.show()

  update_brush()

# When smooth button pressed, show smooth panel
func _on_SmoothButton_pressed() -> void:
  mode = Modes.SMOOTH

  $VBoxContainer/Modes/BrushButton.set_pressed_no_signal(false)
  $VBoxContainer/Modes/SmoothButton.set_pressed_no_signal(true)
  $VBoxContainer/Modes/EraserButton.set_pressed_no_signal(false)

  $VBoxContainer/WeightContainer.hide()
  $VBoxContainer/IntensityContainer.show()
  $VBoxContainer/SizeContainer.show()

  update_brush()

# When eraser button pressed, show eraser panel
func _on_EraserButton_pressed() -> void:
  mode = Modes.ERASER

  $VBoxContainer/Modes/BrushButton.set_pressed_no_signal(false)
  $VBoxContainer/Modes/SmoothButton.set_pressed_no_signal(false)
  $VBoxContainer/Modes/EraserButton.set_pressed_no_signal(true)

  $VBoxContainer/WeightContainer.hide()
  $VBoxContainer/IntensityContainer.hide()
  $VBoxContainer/SizeContainer.show()

  update_brush()

func _on_WeightSlider_value_changed(value: float) -> void:
  weight_value = value
  update_brush()

func _on_IntensitySlider_value_changed(value: float) -> void:
  update_brush()

func _on_SizeSlider_value_changed(value: float) -> void:
  update_brush()

func get_mode():
  return mode

func get_weight_value():
  return weight_value

func get_intensity():
  return $VBoxContainer/IntensityContainer/IntensitySlider.value

func get_size_value():
  return $VBoxContainer/SizeContainer/SizeSlider.value

func update_brush():
  var mode = get_mode()
  var weight_value = get_weight_value()
  var intensity = get_intensity()
  var size_value = get_size_value()

  match mode:
    Modes.BRUSH:
      brush_color = Color(weight_value, 0, 0, 1.0)  # Red channel for weight
      brush_opacity = intensity
      brush_size = size_value
    Modes.SMOOTH:
      brush_color = Color(0, weight_value, 0, 1.0)  # Green channel for smooth
      brush_opacity = intensity
      brush_size = size_value
    Modes.ERASER:
      brush_color = Color(0, 0, 0, 1.0)  # Black for erase
      brush_opacity = 1.0
      brush_size = size_value

  emit_signal("values_changed", brush_color, brush_opacity, brush_size)
