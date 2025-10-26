@tool
extends Node3D

class_name PluginCursor

var root :Node
var mesh_instance :MeshInstance3D
var temp_plugin_node :Node3D

var painting = false
var brush_color :Color = Color.WHITE
var brush_size :float = 0.1
var weight_value :float = 1.0

# Multi-bone weight storage
var bone_weight_textures = {}  # Dictionary: bone_index -> ImageTexture
var bone_weight_images = {}    # Dictionary: bone_index -> Image
var current_bone_index :int = 0
var texture_size = 1024

func show_cursor(root :Node, mesh_instance :MeshInstance3D, temp_plugin_node :Node3D):
    show()
    self.root = root
    self.mesh_instance = mesh_instance
    self.temp_plugin_node = temp_plugin_node

    # Initialize weight textures from existing mesh weights
    initialize_weight_textures_from_mesh(mesh_instance)

    # Add cursor to tree
    var cursor_absent = true
    for child in temp_plugin_node.get_children():
        if child == self:
            cursor_absent = false
            break

    if cursor_absent:
        temp_plugin_node.add_child(self)
        self.owner = root

func initialize_weight_textures_from_mesh(mesh_instance: MeshInstance3D):
    # Clear existing textures
    bone_weight_textures.clear()
    bone_weight_images.clear()

    if not mesh_instance or not mesh_instance.mesh:
        # Create default texture for bone 0
        create_bone_weight_texture(0)
        return

    var mesh = mesh_instance.mesh
    var arrays = mesh.surface_get_arrays(0)
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var uvs = arrays[Mesh.ARRAY_TEX_UV]

    if uvs.size() == 0:
        push_error("Mesh has no UV coordinates! Cannot initialize weights.")
        create_bone_weight_texture(0)
        return

    # Check if mesh has vertex weights (bone weights)
    var bone_weights = []
    var bone_indices = []

    if arrays.size() > Mesh.ARRAY_WEIGHTS and arrays[Mesh.ARRAY_WEIGHTS] != null:
        bone_weights = arrays[Mesh.ARRAY_WEIGHTS]
    if arrays.size() > Mesh.ARRAY_BONES and arrays[Mesh.ARRAY_BONES] != null:
        bone_indices = arrays[Mesh.ARRAY_BONES]

    if bone_weights.size() > 0 and bone_indices.size() > 0:
        print("Loading existing multi-bone weights from mesh...")

        # Find all bones used in the mesh and their weights
        var bone_vertex_weights = {}  # bone_index -> Array of vertex weights

        for i in range(vertices.size()):
            if i < uvs.size() and i * 4 < bone_indices.size():
                var uv = uvs[i]

                # Check all 4 possible bone influences per vertex
                for j in range(4):
                    var bone_idx = bone_indices[i * 4 + j]
                    var weight = bone_weights[i * 4 + j]

                    if weight > 0:
                        if not bone_vertex_weights.has(bone_idx):
                            bone_vertex_weights[bone_idx] = []

                        bone_vertex_weights[bone_idx].append({
                            "vertex_index": i,
                            "uv": uv,
                            "weight": weight
                        })

        # Create textures for each bone with weights
        for bone_idx in bone_vertex_weights:
            create_bone_weight_texture(bone_idx)
            var weight_image = bone_weight_images[bone_idx]

            # Set weights for this bone
            for vertex_data in bone_vertex_weights[bone_idx]:
                var uv = vertex_data["uv"]
                var weight = vertex_data["weight"]

                var tex_x = int(uv.x * texture_size)
                var tex_y = int(uv.y * texture_size)

                tex_x = clamp(tex_x, 0, texture_size - 1)
                tex_y = clamp(tex_y, 0, texture_size - 1)

                weight_image.set_pixel(tex_x, tex_y, Color(weight, 0, 0, 1.0))

            # Update texture
            bone_weight_textures[bone_idx].update(weight_image)

        print("Loaded weights for bones: ", bone_vertex_weights.keys())

        # Set current bone to first one with weights, or 0 if none
        if bone_vertex_weights.size() > 0:
            current_bone_index = bone_vertex_weights.keys()[0]
        else:
            current_bone_index = 0
            create_bone_weight_texture(0)
    else:
        print("No existing vertex weights found - starting with default bone")
        create_bone_weight_texture(0)

func create_bone_weight_texture(bone_index: int):
    var weight_image = Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
    weight_image.fill(Color(0, 0, 0, 1))  # Initialize with black (0 weight)
    bone_weight_images[bone_index] = weight_image

    var weight_texture = ImageTexture.create_from_image(weight_image)
    bone_weight_textures[bone_index] = weight_texture

    print("Created weight texture for bone ", bone_index)

func set_current_bone(bone_index: int):
    current_bone_index = bone_index
    print("PluginCursor: Set current bone to ", bone_index)

    # Ensure this bone has a weight texture
    if not bone_weight_textures.has(bone_index):
        create_bone_weight_texture(bone_index)

func get_current_bone_texture() -> ImageTexture:
    if bone_weight_textures.has(current_bone_index):
        return bone_weight_textures[current_bone_index]
    else:
        # Create texture if it doesn't exist
        create_bone_weight_texture(current_bone_index)
        return bone_weight_textures[current_bone_index]

func get_all_bone_textures() -> Dictionary:
    return bone_weight_textures.duplicate()

func paint_vertex_weights(position: Vector3):
    if not mesh_instance or not mesh_instance.mesh:
        return

    var mesh :Mesh = mesh_instance.mesh
    if mesh.get_surface_count() == 0:
        return

    # Get mesh data
    var arrays = mesh.surface_get_arrays(0)
    var vertices :PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var uvs :PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]

    if uvs.size() == 0:
        push_error("Mesh has no UV coordinates! Cannot paint weights.")
        return

    var local_pos = mesh_instance.to_local(position)
    var max_distance = brush_size * 2.0

    # Make sure we have a texture for the current bone
    if not bone_weight_images.has(current_bone_index):
        create_bone_weight_texture(current_bone_index)

    var weight_image = bone_weight_images[current_bone_index]
    var vertices_painted = 0

    # Find the closest point on the mesh surface for more accurate UV sampling
    var closest_distance = INF
    var closest_uv = Vector2.ZERO
    var closest_vertex = -1

    # First pass: find the closest vertex and its UV
    for i in range(vertices.size()):
        var vertex = vertices[i]
        var distance = vertex.distance_to(local_pos)

        if distance < closest_distance:
            closest_distance = distance
            closest_vertex = i
            if i < uvs.size():
                closest_uv = uvs[i]

    if closest_vertex == -1:
        return

    # Second pass: paint in a radius around the closest UV point
    var brush_radius_uv = brush_size * 0.1  # Adjust this multiplier based on your UV scale
    var brush_center_uv = closest_uv

    # Convert brush radius to texture pixels
    var brush_radius_pixels = int(brush_radius_uv * texture_size)
    var center_x = int(brush_center_uv.x * texture_size)
    var center_y = int(brush_center_uv.y * texture_size)

    # Paint in a circular area in UV space
    for x in range(center_x - brush_radius_pixels, center_x + brush_radius_pixels + 1):
        for y in range(center_y - brush_radius_pixels, center_y + brush_radius_pixels + 1):
            if x < 0 or x >= texture_size or y < 0 or y >= texture_size:
                continue

            # Calculate distance from brush center in UV space
            var uv_dist_x = float(x - center_x) / texture_size
            var uv_dist_y = float(y - center_y) / texture_size
            var uv_distance = sqrt(uv_dist_x * uv_dist_x + uv_dist_y * uv_dist_y)

            if uv_distance <= brush_radius_uv:
                # Calculate falloff based on UV distance
                var falloff = 1.0 - (uv_distance / brush_radius_uv)
                var influence = brush_color.a * falloff * weight_value

                # Get current weight from texture
                var current_color = weight_image.get_pixel(x, y)
                var current_weight = current_color.r

                # Apply painting based on brush mode
                var new_weight = current_weight
                if brush_color.r > 0.5:  # Brush mode - add weight
                    new_weight = clamp(current_weight + influence, 0.0, 1.0)
                elif brush_color.b > 0.5:  # Eraser mode - remove weight
                    new_weight = clamp(current_weight - influence, 0.0, 1.0)

                # Update texture
                weight_image.set_pixel(x, y, Color(new_weight, 0, 0, 1.0))
                vertices_painted += 1

    # Update texture
    var weight_texture = bone_weight_textures[current_bone_index]
    weight_texture.update(weight_image)

    print("Painted ", vertices_painted, " pixels for bone ", current_bone_index)

# Texture-based weight storage
var weight_texture :ImageTexture
var weight_image :Image

func initialize_weight_texture_from_mesh(mesh_instance: MeshInstance3D):
    # Create a blank weight texture
    weight_image = Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)

    if not mesh_instance or not mesh_instance.mesh:
        weight_image.fill(Color(0, 0, 0, 1))
        weight_texture = ImageTexture.create_from_image(weight_image)
        return

    var mesh = mesh_instance.mesh
    var arrays = mesh.surface_get_arrays(0)
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var uvs = arrays[Mesh.ARRAY_TEX_UV]

    if uvs.size() == 0:
        push_error("Mesh has no UV coordinates! Cannot initialize weights.")
        weight_image.fill(Color(0, 0, 0, 1))
        weight_texture = ImageTexture.create_from_image(weight_image)
        return

    # Check if mesh has vertex weights
    var bone_weights = []
    if arrays.size() > Mesh.ARRAY_WEIGHTS and arrays[Mesh.ARRAY_WEIGHTS] != null:
        bone_weights = arrays[Mesh.ARRAY_WEIGHTS]

    # Fill texture with existing weights
    weight_image.fill(Color(0, 0, 0, 1))

    if bone_weights.size() > 0:
        print("Loading existing vertex weights from mesh for ", vertices.size(), " vertices")

        for i in range(vertices.size()):
            if i < uvs.size():
                var uv = uvs[i]
                var tex_x = int(uv.x * texture_size)
                var tex_y = int(uv.y * texture_size)

                tex_x = clamp(tex_x, 0, texture_size - 1)
                tex_y = clamp(tex_y, 0, texture_size - 1)

                # Get the weight for this vertex (using first bone weight)
                var weight = 0.0
                if i * 4 < bone_weights.size():
                    weight = bone_weights[i * 4]  # First bone weight

                # Store weight in red channel
                weight_image.set_pixel(tex_x, tex_y, Color(weight, 0, 0, 1.0))

        print("Successfully loaded existing weights")
    else:
        print("No existing vertex weights found - starting with default weights")
        weight_image.fill(Color(0, 0, 0, 1))

    weight_texture = ImageTexture.create_from_image(weight_image)

func input(camera :Camera3D, event: InputEvent) -> bool:
  var captured_event = false

  if event is InputEventMouseMotion:
    var ray_origin = camera.project_ray_origin(event.position)
    var ray_dir = camera.project_ray_normal(event.position)
    var ray_distance = camera.far

    var space_state = camera.get_world_3d().direct_space_state
    var ray_params :PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
    ray_params.from = ray_origin
    ray_params.to = ray_origin + ray_dir * ray_distance
    var hit = space_state.intersect_ray(ray_params)
    if hit:
      display_brush_at(hit.position, hit.normal)
      if painting:
        paint_vertex_weights(hit.position)
        captured_event = true
    else:
      display_brush_at()

  if event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_LEFT and visible:
      painting = event.pressed
      captured_event = true

  return captured_event

func get_weight_texture() -> ImageTexture:
  return weight_texture

func set_brush_color(color :Color):
  brush_color = color

func set_brush_opacity(alpha: float):
  brush_color.a = alpha

func set_brush_size(size :float):
  brush_size = size
  if size == 1.0:
    size *= 100
  $Cursor.scale = Vector3(1.0, 1.0, 1.0) * size

func display_brush_at(pos = null, normal = null) -> void:
  if pos and self.owner:
    $Cursor.visible = true
    $Cursor.global_transform.origin = pos
    $CursorMiddle.visible = true
    $CursorMiddle.global_transform.origin = pos
  else:
    $Cursor.visible = false
    $CursorMiddle.visible = false

func hide_cursor():
  painting = false
  if temp_plugin_node:
    var cursor_present = false
    for child in temp_plugin_node.get_children():
      if child == self:
        cursor_present = true
        break
    if cursor_present:
      temp_plugin_node.remove_child(self)
  hide()

func clear_current_bone_weights():
  if not bone_weight_images.has(current_bone_index):
    return
  var weight_image = bone_weight_images[current_bone_index]
  weight_image.fill(Color(0, 0, 0, 1))  # Clear all weights (red channel = 0)
  var weight_texture = bone_weight_textures[current_bone_index]
  weight_texture.update(weight_image)
  print("Cleared weights for bone ", current_bone_index)
