# plugin_cursor.gd
@tool
extends Node3D
class_name PluginCursor

var root: Node
var mesh_instance: MeshInstance3D
var temp_plugin_node: Node3D

var painting = false
var brush_color: Color = Color.WHITE
var brush_opacity: float = 1.0
var brush_size: float = 0.1
var weight_value: float = 1.0

var bone_weight_textures := {}  # bone_index -> ImageTexture
var bone_weight_images := {}    # bone_index -> Image
var current_bone_index: int = 0
var texture_size: int = 1024

func show_cursor(p_root: Node, p_mesh_instance: MeshInstance3D, p_temp_plugin_node: Node3D) -> void:
  print("PluginCursor: show_cursor called")

    # Store references
  root = p_root
  mesh_instance = p_mesh_instance
  temp_plugin_node = p_temp_plugin_node

    # Make sure we're in the scene tree
  if not is_inside_tree():
    if temp_plugin_node and is_instance_valid(temp_plugin_node):
      temp_plugin_node.add_child(self)
      print("PluginCursor: Added to temp_plugin_node")

    # Initialize textures if needed
  if bone_weight_textures.is_empty():
    bone_weight_textures.clear()
    bone_weight_images.clear()
    current_bone_index = 0
    create_bone_weight_texture(0)
    print("PluginCursor: Initialized bone weight textures")

    # Show the cursor and position it properly
  show()

    # Position cursor at mesh center initially
  if mesh_instance:
    global_transform = mesh_instance.global_transform
    print("PluginCursor: Cursor positioned at mesh transform")

  print("PluginCursor: Cursor shown")

func hide_cursor() -> void:
  print("PluginCursor: hide_cursor called")
  hide()

func create_bone_weight_texture(bone_index: int) -> void:
  var weight_image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
  weight_image.fill(Color(0, 0, 0, 1))
  bone_weight_images[bone_index] = weight_image

  var weight_texture := ImageTexture.create_from_image(weight_image)
  bone_weight_textures[bone_index] = weight_texture

func set_current_bone(bone_index: int) -> void:
  current_bone_index = bone_index
  if not bone_weight_textures.has(bone_index):
    create_bone_weight_texture(bone_index)

func get_current_bone_texture() -> ImageTexture:
  if bone_weight_textures.has(current_bone_index):
    return bone_weight_textures[current_bone_index]
  create_bone_weight_texture(current_bone_index)
  return bone_weight_textures[current_bone_index]

func get_all_bone_images() -> Dictionary:
  return bone_weight_images

func clear_all_bone_weights() -> void:
  for idx in bone_weight_images:
    var img: Image = bone_weight_images[idx]
    if idx == 0:
      img.fill(Color(0.1, 0.0, 0.0, 1.0))
    else:
      img.fill(Color(0,0,0,1))
    bone_weight_textures[idx].update(img)
  print("Cleared all bone weights")

func clear_current_bone_weights() -> void:
  if bone_weight_images.has(current_bone_index):
    var img: Image = bone_weight_images[current_bone_index]
        # Instead of clearing to all zeros, set a default weight pattern
        # This ensures there's always some influence
    if current_bone_index == 0:
      img.fill(Color(0.1, 0.0, 0.0, 1.0))
    else:
      img.fill(Color(0,0,0,1))

        # update texture from image
    if bone_weight_textures.has(current_bone_index):
      bone_weight_textures[current_bone_index].update(img)
    print("Reset weights for bone ", current_bone_index)

func set_brush_color(color: Color) -> void:
  brush_color = color

func set_brush_opacity(opacity: float) -> void:
  brush_opacity = opacity

func set_brush_size(size: float) -> void:
  brush_size = size
    # Update cursor visual scale based on brush size
  scale = Vector3.ONE * brush_size * 2.0

func input(camera: Camera3D, event: InputEvent) -> bool:
  var captured_event = false

  if event is InputEventMouseMotion:
    var ray_origin = camera.project_ray_origin(event.position)
    var ray_dir = camera.project_ray_normal(event.position)
    var ray_distance = camera.far

    var space_state = camera.get_world_3d().direct_space_state
    var ray_params = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * ray_distance)

        # Use collision mask that includes the static body we created
    ray_params.collision_mask = 1

    var hit = space_state.intersect_ray(ray_params)
    if hit:
      global_transform.origin = hit.position
      show()

      if painting:
        paint_vertex_weights(hit.position)
        captured_event = true
    else:
      hide()

  if event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_LEFT and visible:
      painting = event.pressed
      captured_event = true

  return captured_event

func paint_vertex_weights(position: Vector3) -> void:
  if not mesh_instance or not mesh_instance.mesh or mesh_instance.mesh.get_surface_count() == 0:
    return

  var arrays = mesh_instance.mesh.surface_get_arrays(0)
  if arrays == null:
    return

  var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
  var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
  if uvs == null or uvs.size() == 0 or vertices == null:
    return

  var local_pos = mesh_instance.to_local(position)
  if not bone_weight_images.has(current_bone_index):
    create_bone_weight_texture(current_bone_index)
  var weight_image: Image = bone_weight_images[current_bone_index]

    # find closest vertex in local space
  var closest_dist_sq = INF
  var closest_uv = Vector2.ZERO
  for i in range(vertices.size()):
    var dist_sq = vertices[i].distance_squared_to(local_pos)
    if dist_sq < closest_dist_sq:
      closest_dist_sq = dist_sq
      closest_uv = uvs[i]

  var center_x = int(clamp(closest_uv.x * texture_size, 0, texture_size - 1))
  var center_y = int(clamp(closest_uv.y * texture_size, 0, texture_size - 1))
  var brush_radius_uv = brush_size * 0.5
  var brush_radius_pixels = max(1, int(brush_radius_uv * texture_size))

  var image_changed = false
  for y in range(center_y - brush_radius_pixels, center_y + brush_radius_pixels + 1):
    for x in range(center_x - brush_radius_pixels, center_x + brush_radius_pixels + 1):
      if x < 0 or x >= texture_size or y < 0 or y >= texture_size:
        continue
      var dx = x - center_x
      var dy = y - center_y
      var uv_dist_sq = float(dx*dx + dy*dy)
      if uv_dist_sq <= float(brush_radius_pixels * brush_radius_pixels):
        var falloff = 1.0 - sqrt(uv_dist_sq) / float(brush_radius_pixels)
        var influence = brush_opacity * falloff * weight_value

        var current_color = weight_image.get_pixel(x, y)
        var current_weight = current_color.r
        var new_weight = current_weight

                # interpret brush_color: red = add, blue = erase
        if brush_color.r > 0.5:
          new_weight = clamp(current_weight + influence, 0.0, 1.0)
        elif brush_color.b > 0.5:
          new_weight = clamp(current_weight - influence, 0.0, 1.0)

        if abs(new_weight - current_weight) > 0.0005:
          weight_image.set_pixel(x, y, Color(new_weight, 0.0, 0.0, 1.0))
          image_changed = true

  if image_changed:
    if bone_weight_textures.has(current_bone_index):
      bone_weight_textures[current_bone_index].update(weight_image)
    else:
      var tex = ImageTexture.create_from_image(weight_image)
      bone_weight_textures[current_bone_index] = tex
