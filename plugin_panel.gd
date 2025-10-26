@tool
extends Control
class_name VertexWeightsPluginPanel

var plugin_cursor :PluginCursor
var editor_filesystem :EditorFileSystem
var dir_path :String = "res://meshpainter-vertex-weights"

var root :Node
var mesh_instance :MeshInstance3D

# Temporary nodes
var temp_plugin_node :Node
var temp_collision :CollisionShape3D
var temp_body :StaticBody3D

# Shader material for visualization
var vertex_weights_material :ShaderMaterial
var vertex_weights_shader :Shader = preload("res://addons/cabra.lat_uv_painter/materials/vertex_weights_shader.gdshader")

# Store original material to restore later
var original_material :Material

var mesh_id :String
var is_setup_complete = false

func ensure_mesh_has_skin():
    if not mesh_instance:
        return false
    if mesh_instance.skin:
        return true

    var skeleton = find_skeleton_parent(mesh_instance)
    if not skeleton:
        push_error("No skeleton found for mesh - cannot create skin")
        return false

    var skin = Skin.new()
    for bone_idx in skeleton.get_bone_count():
        var bone_pose = skeleton.get_bone_rest(bone_idx)
        skin.add_bind(bone_idx, bone_pose)

    mesh_instance.skin = skin

    # 🔥 CRITICAL: Assign the skeleton path
    var skeleton_path = mesh_instance.get_path_to(skeleton)
    mesh_instance.set_skeleton_path(skeleton_path)

    print("Created basic skin and assigned skeleton path")
    return true

func find_skeleton_parent(node: Node) -> Skeleton3D:
  var current = node
  while current:
    if current is Skeleton3D:
      return current
    current = current.get_parent()
  return null

func show_panel(root :Node, mesh_instance :MeshInstance3D):
  print("VertexWeightsPluginPanel: show_panel called")

  if not mesh_instance or not mesh_instance.mesh:
    push_error("No valid mesh instance selected")
    return

  show()
  self.root = root
  self.mesh_instance = mesh_instance

    # Ensure the mesh has a skin
  if not ensure_mesh_has_skin():
    push_error("Cannot proceed - mesh has no skin and cannot create one")
    return

    # Store the original material
  original_material = mesh_instance.get_surface_override_material(0)
  if not original_material:
    original_material = mesh_instance.mesh.surface_get_material(0)

  print("Original material: ", original_material)

  generate_id(mesh_instance.name)
  setup_part_1()

func generate_collision():
  print("Generating collision...")

  if not mesh_instance or not mesh_instance.mesh:
    push_error("Cannot generate collision: No mesh instance or mesh")
    return

  # Clean up any existing collision
  if temp_plugin_node and is_instance_valid(temp_plugin_node):
    mesh_instance.remove_child(temp_plugin_node)
    temp_plugin_node.queue_free()

  temp_collision = CollisionShape3D.new()
  var shape = mesh_instance.mesh.create_trimesh_shape()
  if not shape:
    push_error("Failed to create trimesh shape")
    return

  temp_collision.set_shape(shape)
  temp_collision.hide()

  # Add static body to use collisions
  temp_body = StaticBody3D.new()
  temp_body.add_child(temp_collision)
  temp_body.collision_layer = 32

  # Add main plugin node where body and collision shape will be
  temp_plugin_node = Node3D.new()
  temp_plugin_node.name = "VertexWeightsPainter"
  temp_plugin_node.add_child(temp_body)

  mesh_instance.add_child(temp_plugin_node)

  if root:
    temp_collision.owner = root
    temp_body.owner = root
    temp_plugin_node.owner = root

  print("Collision generation complete")

func generate_id(name :String):
  randomize()
  var scene_path = get_tree().edited_scene_root.scene_file_path if get_tree().edited_scene_root else "default"
  name = scene_path + name
  mesh_id = str(name.hash())
  print("Generated mesh ID: ", mesh_id)

func setup_part_1():
  print("Setup part 1")

  var dir = DirAccess.open("res://")
  if not dir:
    push_error("Cannot access res:// directory")
    return

  if not dir.dir_exists(dir_path):
    var error = dir.make_dir(dir_path)
    if error != OK:
      push_error("Failed to create directory: " + dir_path)
      return

  if mesh_instance and mesh_instance.mesh:
    generate_collision()

  # Create shader material for visualization
  vertex_weights_material = ShaderMaterial.new()
  vertex_weights_material.shader = vertex_weights_shader

  setup_part_2()

func setup_part_2():
    print("Setup part 2")

    # Setup vertex weights panel
    if has_node("VBoxContainer/VertexWeightsPanel"):
        var vertex_weights_panel = $VBoxContainer/VertexWeightsPanel

        # Get bone names from skeleton
        var bone_names = get_bone_names_from_skeleton()
        vertex_weights_panel.setup_bones(bone_names, plugin_cursor.current_bone_index)

        # Connect bone selection signal
        vertex_weights_panel.bone_selected.connect(_on_bone_selected)

        if vertex_weights_panel.has_method("setup"):
            vertex_weights_panel.setup()
            is_setup_complete = true
        else:
            push_error("VertexWeightsPanel doesn't have setup method")
    else:
        push_error("VertexWeightsPanel node not found")

    # Apply the shader material
    if mesh_instance:
        mesh_instance.set_surface_override_material(0, vertex_weights_material)
        print("Applied vertex weights material")

    # Show cursor
    if mesh_instance and temp_plugin_node and plugin_cursor:
        plugin_cursor.show_cursor(root, mesh_instance, temp_plugin_node)

        # Connect weight texture to shader
        update_shader_for_current_bone()

        print("Cursor shown")
    else:
        push_error("Cannot show cursor: missing required components")

func get_bone_names_from_skeleton() -> Array:
    var bone_names = []
    var skeleton = find_skeleton_parent(mesh_instance)

    if skeleton and skeleton is Skeleton3D:
        for i in range(skeleton.get_bone_count()):
            bone_names.append(skeleton.get_bone_name(i))
        print("Found ", bone_names.size(), " bones in skeleton")
    else:
        bone_names = ["Bone_0"]  # Default if no skeleton found
        print("No skeleton found, using default bone")

    return bone_names

func _on_bone_selected(bone_index: int):
    if plugin_cursor:
        plugin_cursor.set_current_bone(bone_index)
        update_shader_for_current_bone()
        print("Switched to bone: ", bone_index)

func update_shader_for_current_bone():
    if plugin_cursor and vertex_weights_material:
        var weight_texture = plugin_cursor.get_current_bone_texture()
        vertex_weights_material.set_shader_parameter("weight_texture", weight_texture)
        vertex_weights_material.set_shader_parameter("current_bone_index", plugin_cursor.current_bone_index)
        print("Updated shader for bone: ", plugin_cursor.current_bone_index)

# When changing Vertex Weights panel uniforms, pass new brush info to cursor
func _on_vertex_weights_panel_values_changed(brush_color, brush_opacity, brush_size, weight_value) -> void:
  if plugin_cursor:
    plugin_cursor.set_brush_color(brush_color)
    plugin_cursor.set_brush_opacity(brush_opacity)
    plugin_cursor.set_brush_size(brush_size)
    plugin_cursor.weight_value = weight_value

    # Update shader parameters
    vertex_weights_material.set_shader_parameter("brush_color", brush_color)

    print("Brush values updated")

func _on_vertex_weights_panel_apply_weights():
  apply_weights_to_mesh()

func hide_panel():
  print("Hiding panel")

  if mesh_instance:
    # Restore original material
    mesh_instance.set_surface_override_material(0, original_material)
    print("Restored original material")

    if temp_plugin_node and is_instance_valid(temp_plugin_node):
      mesh_instance.remove_child(temp_plugin_node)
      temp_plugin_node.queue_free()
      print("Removed temp plugin node")
    mesh_instance = null

  if plugin_cursor:
    plugin_cursor.hide_cursor()
    print("Cursor hidden")

  is_setup_complete = false
  hide()
  print("Panel hidden")


func apply_weights_to_mesh():
  if not mesh_instance or not mesh_instance.mesh:
    push_error("No mesh instance to apply weights to")
    return

  var mesh = mesh_instance.mesh
  if mesh.get_surface_count() <= 0:
    push_error("Mesh has no surfaces!")
    return

  var arrays = mesh.surface_get_arrays(0)

  # --- SAFETY: Ensure required arrays exist ---
  var vertex_count = 0
  if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX]:
    vertex_count = arrays[Mesh.ARRAY_VERTEX].size()
  else:
    push_error("Mesh has no vertices!")
    return

  # Ensure ARRAY_BONES and ARRAY_WEIGHTS exist and are correct type
  if arrays.size() <= Mesh.ARRAY_BONES or arrays[Mesh.ARRAY_BONES] == null:
    arrays.resize(max(arrays.size(), Mesh.ARRAY_BONES + 1))
    arrays[Mesh.ARRAY_BONES] = PackedInt32Array()
  if arrays.size() <= Mesh.ARRAY_WEIGHTS or arrays[Mesh.ARRAY_WEIGHTS] == null:
    arrays.resize(max(arrays.size(), Mesh.ARRAY_WEIGHTS + 1))
    arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array()

  # Initialize with zeros if empty or wrong size
  if typeof(arrays[Mesh.ARRAY_BONES]) != TYPE_PACKED_INT32_ARRAY:
    arrays[Mesh.ARRAY_BONES] = PackedInt32Array()
  if typeof(arrays[Mesh.ARRAY_WEIGHTS]) != TYPE_PACKED_FLOAT32_ARRAY:
    arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array()

  # Ensure they have 4 * vertex_count elements
  var required_size = vertex_count * 4
  if arrays[Mesh.ARRAY_BONES].size() != required_size:
    arrays[Mesh.ARRAY_BONES].resize(required_size)
    for i in range(required_size):
      arrays[Mesh.ARRAY_BONES][i] = 0
  if arrays[Mesh.ARRAY_WEIGHTS].size() != required_size:
    arrays[Mesh.ARRAY_WEIGHTS].resize(required_size)
    for i in range(required_size):
      arrays[Mesh.ARRAY_WEIGHTS][i] = 0.0

  # --- Now safe to proceed ---
  var uvs = arrays[Mesh.ARRAY_TEX_UV]
  if uvs.size() == 0:
    push_error("Mesh has no UV coordinates")
    return

  var new_weights = PackedFloat32Array()
  var new_bones = PackedInt32Array()

  var bone_textures = plugin_cursor.get_all_bone_textures()
  var bone_indices = bone_textures.keys()

  for i in range(vertex_count):
    if i < uvs.size():
      var uv = uvs[i]
      var tex_x = int(clamp(uv.x * plugin_cursor.texture_size, 0, plugin_cursor.texture_size - 1))
      var tex_y = int(clamp(uv.y * plugin_cursor.texture_size, 0, plugin_cursor.texture_size - 1))

      var vertex_weights = []
      for bone_idx in bone_indices:
        var weight_image = plugin_cursor.bone_weight_images[bone_idx]
        var weight = weight_image.get_pixel(tex_x, tex_y).r
        if weight > 0:
          vertex_weights.append({"bone": bone_idx, "weight": weight})

      vertex_weights.sort_custom(func(a, b): return a.weight > b.weight)
      vertex_weights = vertex_weights.slice(0, min(4, vertex_weights.size()))

      var total_weight = 0.0
      for vw in vertex_weights:
        total_weight += vw.weight
      if total_weight > 0:
        for vw in vertex_weights:
          vw.weight /= total_weight

      for j in range(4):
        if j < vertex_weights.size():
          new_weights.append(vertex_weights[j].weight)
          new_bones.append(vertex_weights[j].bone)
        else:
          new_weights.append(0.0)
          new_bones.append(0)
    else:
      for j in range(4):
        new_weights.append(0.0)
        new_bones.append(0)

  # Assign
  arrays[Mesh.ARRAY_WEIGHTS] = new_weights
  arrays[Mesh.ARRAY_BONES] = new_bones

  # Validate types before creating mesh
  if typeof(arrays[Mesh.ARRAY_BONES]) != TYPE_PACKED_INT32_ARRAY:
    push_error("ARRAY_BONES is not PackedInt32Array")
    return
  if typeof(arrays[Mesh.ARRAY_WEIGHTS]) != TYPE_PACKED_FLOAT32_ARRAY:
    push_error("ARRAY_WEIGHTS is not PackedFloat32Array")
    return

  var new_mesh = ArrayMesh.new()
  new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

  if new_mesh.get_surface_count() == 0:
    push_error("Failed to create new mesh surface — invalid arrays")
    return

  # Copy materials
  var surface_count = min(mesh.get_surface_count(), new_mesh.get_surface_count())
  for i in range(surface_count):
    var mat = mesh.surface_get_material(i)
    if mat:
      new_mesh.surface_set_material(i, mat)

  mesh_instance.mesh = new_mesh
  print("Applied multi-bone weights to mesh for ", vertex_count, " vertices")
  print("Used bones: ", bone_indices)

func _on_vertex_weights_panel_clear_preview() -> void:
  if plugin_cursor:
    plugin_cursor.clear_current_bone_weights()
    update_shader_for_current_bone()
