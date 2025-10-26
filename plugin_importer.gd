@tool
extends EditorImportPlugin
class_name PluginImporter

const size = 512

func _get_importer_name():
  return "mesh.painter.plugin"

func _get_visible_name():
  return "Mesh Painter"

func _get_recognized_extensions():
  return ["mpaint"]

func _get_save_extension():
  return "res"

func _get_resource_type():
  return "Image"

func _get_preset_count():
  return 1

func _get_preset_name(i):
  return "Default"

func _get_priority():
  return 1.0

func _get_import_order():
  return 100

func _get_import_options(path: String, preset_index: int):
  return []

func _get_option_visibility(path: String, option_name: StringName, options: Dictionary):
  return true

func _import(source_file, save_path, options, platform_variants, gen_files):
  # Add a small delay to prevent recursive imports
  OS.delay_msec(100)

  var file = FileAccess.open(source_file, FileAccess.READ)
  if file == null:
    push_error("Failed to open mpaint file: " + source_file)
    return ERR_FILE_CANT_READ

  # Verify file format
  if file.get_length() < 8:
    push_error("Invalid mpaint file format: " + source_file)
    return ERR_FILE_CORRUPT

  var data_size = file.get_var()
  if data_size == null or not data_size is Array or data_size.size() != 2:
    push_error("Invalid data_size in mpaint file: " + source_file)
    return ERR_FILE_CORRUPT

  var data = file.get_var()
  if data == null or not data is Array:
    push_error("Invalid data in mpaint file: " + source_file)
    return ERR_FILE_CORRUPT

  var width = data_size[0]
  var height = data_size[1]

  # Create image with proper format
  var image = Image.create(width, height, false, Image.FORMAT_RGBA8)

  # Fill image with data
  for y in range(height):
    var row = data[y]
    for x in range(width):
      var pixel_data = row[x]
      if pixel_data is Array and pixel_data.size() >= 4:
        var color = Color(pixel_data[0], pixel_data[1], pixel_data[2], pixel_data[3])
        image.set_pixel(x, y, color)
      else:
        # Default to white if data is invalid
        image.set_pixel(x, y, Color(1, 1, 1, 1))

  var filename = save_path + "." + _get_save_extension()
  var result = ResourceSaver.save(image, filename)

  if result != OK:
    push_error("Failed to save imported image: " + filename)

  return result
