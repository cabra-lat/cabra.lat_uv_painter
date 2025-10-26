@tool
extends Control

class_name ImageManager

static func create_mpaint_file(path :String):
  var dir = DirAccess.open("res://")
  if !dir:
    push_error("Cannot access res:// directory")
    return

  # Check if file already exists
  if dir.file_exists(path):
    return

  # Create proper default data based on file type
  var data_size = [512, 1] if "brush" in path else [512, 512]
  var data = []

  if "brush" in path:
    # For brush files, create empty data
    for y in range(data_size[1]):
      var row = []
      for x in range(data_size[0]):
        row.append([0.0, 0.0, 0.0, 0.0])  # Transparent black
      data.append(row)
  elif "color" in path:
    # For color files, create white data
    for y in range(data_size[1]):
      var row = []
      for x in range(data_size[0]):
        row.append([1.0, 1.0, 1.0, 1.0])  # Opaque white
      data.append(row)
  else:
    # For layer files, create appropriate default data
    for y in range(data_size[1]):
      var row = []
      for x in range(data_size[0]):
        if "roughness" in path:
          row.append([0.5, 0.5, 0.5, 1.0])  # Gray for roughness
        elif "metalness" in path:
          row.append([0.0, 0.0, 0.0, 1.0])  # Black for metalness
        elif "emission" in path:
          row.append([0.0, 0.0, 0.0, 1.0])  # Black for emission
        elif "vertex_weights" in path:
          row.append([0.0, 0.0, 0.0, 1.0])  # Black for vertex weights
        else:  # albedo
          row.append([1.0, 1.0, 1.0, 1.0])  # White for albedo
      data.append(row)

  # Write the file
  var file = FileAccess.open(path, FileAccess.WRITE)
  if file:
    file.store_var(data_size)
    file.store_var(data)
    file.close()
  else:
    push_error("Failed to create mpaint file: " + path)

static func mpaint_to_texture(path :String) -> ImageTexture:
  if not FileAccess.file_exists(path):
    push_error("MPaint file does not exist: " + path)
    return null

  var file = FileAccess.open(path, FileAccess.READ)
  if not file:
    push_error("Failed to open mpaint file: " + path)
    return null

  var data_size = file.get_var()
  var data = file.get_var()
  file.close()

  if data_size == null or data == null:
    push_error("Invalid mpaint file: " + path)
    return null

  var width = data_size[0]
  var height = data_size[1]

  var image = Image.create(width, height, false, Image.FORMAT_RGBA8)

  for y in range(height):
    var row = data[y]
    for x in range(width):
      var pixel_data = row[x]
      var color = Color(pixel_data[0], pixel_data[1], pixel_data[2], pixel_data[3])
      image.set_pixel(x, y, color)

  var texture = ImageTexture.create_from_image(image)
  return texture

static func texture_to_mpaint(image_tex :Texture2D, path :String):
  var image :Image = image_tex.get_image()
  if image.is_compressed():
    image.decompress()

  var data_size = [image.get_width(), image.get_height()]
  var data = []

  for y in data_size[1]:
    var row = []
    for x in data_size[0]:
      var color = image.get_pixel(x, y)
      row.append([color.r, color.g, color.b, color.a])
    data.append(row)

  var file = FileAccess.open(path, FileAccess.WRITE)
  if file:
    file.store_var(data_size)
    file.store_var(data)
    file.close()
  else:
    push_error("Failed to write mpaint file: " + path)
