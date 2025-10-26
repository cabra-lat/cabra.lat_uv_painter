# plugin_panel.gd
@tool
extends Control
class_name VertexWeightsPluginPanel

var plugin_cursor: PluginCursor
var editor_filesystem: EditorFileSystem
var dir_path: String = "res://meshpainter-vertex-weights"

var root: Node
var mesh_instance: MeshInstance3D

# Temporary nodes
var temp_plugin_node: Node3D
var temp_collision: CollisionShape3D
var temp_body: StaticBody3D

# Shader material for visualization
var vertex_weights_material: ShaderMaterial
var vertex_weights_shader: Shader = preload("res://addons/cabra.lat_uv_painter/materials/vertex_weights_shader.gdshader")

# Store original data to restore later
var original_material: Material
var original_mesh: Mesh # Store the original mesh resource

var is_setup_complete = false

func show_panel(p_root: Node, p_mesh_instance: MeshInstance3D) -> void:
  print("VertexWeightsPluginPanel: show_panel called")
  if not p_mesh_instance or not p_mesh_instance.mesh:
    push_error("No valid mesh instance selected")
    return

  show()
  root = p_root
  mesh_instance = p_mesh_instance

    # store original material and mesh
  original_material = mesh_instance.get_surface_override_material(0)
  if original_material == null:
    original_material = mesh_instance.mesh.surface_get_material(0)
  original_mesh = mesh_instance.mesh.duplicate() if mesh_instance.mesh else null

  if not _setup_skinning_environment():
    hide_panel() # abort
    return

  _generate_collision()
  _setup_ui_panel()

  vertex_weights_material = ShaderMaterial.new()
  vertex_weights_material.shader = vertex_weights_shader
  mesh_instance.set_surface_override_material(0, vertex_weights_material)
  print("Applied vertex weights material")

  if plugin_cursor:
    plugin_cursor.show_cursor(root, mesh_instance, temp_plugin_node)
    update_shader_for_current_bone()
    print("Cursor shown")

  is_setup_complete = true

func hide_panel() -> void:
  print("Hiding panel")
  if is_instance_valid(mesh_instance):
    if original_mesh:
      mesh_instance.mesh = original_mesh
    mesh_instance.set_surface_override_material(0, original_material)
    mesh_instance.skin = null
    mesh_instance.set_skeleton_path(NodePath())
    print("Restored original mesh and material")

    if temp_plugin_node and is_instance_valid(temp_plugin_node):
      if temp_plugin_node.get_parent() == mesh_instance:
        mesh_instance.remove_child(temp_plugin_node)
      temp_plugin_node.queue_free()
      temp_plugin_node = null
      print("Removed temp plugin node")

  if plugin_cursor:
    plugin_cursor.hide_cursor()
    print("Cursor hidden")

  mesh_instance = null
  is_setup_complete = false
  hide()
  print("Panel hidden")

func _setup_skinning_environment() -> bool:
    # find skeleton parent
  var skeleton: Skeleton3D = find_skeleton_parent(mesh_instance)
  if not is_instance_valid(skeleton):
    push_error("No Skeleton3D found as a parent of the mesh.")
    return false

    # create new skin and bind default rest pose
  var new_skin := Skin.new()
  var original_skin : Skin = mesh_instance.skin

  if original_skin and original_skin.get_bind_count() > 0:
        # Copy binds from original skin
    for i in range(original_skin.get_bind_count()):
      var bone = original_skin.get_bind_bone(i)
      var pose = original_skin.get_bind_pose(i)
      new_skin.add_bind(bone, pose)
  else:
        # fallback: bind using rest poses (not ideal but better than nothing)
    for bone_idx in range(skeleton.get_bone_count()):
      new_skin.add_bind(bone_idx, skeleton.get_bone_rest(bone_idx))

  mesh_instance.skin = new_skin
  mesh_instance.set_skeleton_path(mesh_instance.get_path_to(skeleton))
  print("Created and assigned new Skin resource (copied bind poses if available).")

    # prepare a NEW ArrayMesh with sanitized arrays
  var p_original_mesh: ArrayMesh = original_mesh if original_mesh and original_mesh is ArrayMesh else mesh_instance.mesh
  if not p_original_mesh or p_original_mesh.get_surface_count() == 0:
    push_error("Original mesh is invalid or has no surfaces.")
    return false

  var original_arrays = p_original_mesh.surface_get_arrays(0)
  if original_arrays == null or original_arrays.size() <= Mesh.ARRAY_VERTEX or original_arrays[Mesh.ARRAY_VERTEX] == null:
    push_error("Mesh surface has no vertex data.")
    return false

    # Build a clean final arrays list with explicit expected slots
  var final_arrays = []
  final_arrays.resize(Mesh.ARRAY_MAX)

    # 0: vertices (must exist and be PackedVector3Array)
  var verts = original_arrays[Mesh.ARRAY_VERTEX]
  if not (verts is PackedVector3Array):
    push_error("Vertex array is not PackedVector3Array — aborting.")
    return false
  final_arrays[Mesh.ARRAY_VERTEX] = verts

    # 1: normals (copy if valid)
  var nors = original_arrays[Mesh.ARRAY_NORMAL]
  if nors is PackedVector3Array:
    final_arrays[Mesh.ARRAY_NORMAL] = nors
  else:
    final_arrays[Mesh.ARRAY_NORMAL] = null

    # 2: tangents -> skip/clear (most importers put weird formats)
  final_arrays[Mesh.ARRAY_TANGENT] = null

    # 3: colors -> copy only if PackedColorArray else null
  var cols = original_arrays[Mesh.ARRAY_COLOR]
  if cols is PackedColorArray:
    final_arrays[Mesh.ARRAY_COLOR] = cols
  else:
    final_arrays[Mesh.ARRAY_COLOR] = null

    # 4: uv
  var uv = original_arrays[Mesh.ARRAY_TEX_UV]
  if uv is PackedVector2Array:
    final_arrays[Mesh.ARRAY_TEX_UV] = uv
  else:
    final_arrays[Mesh.ARRAY_TEX_UV] = null

    # 5: uv2
  var uv2 = original_arrays[Mesh.ARRAY_TEX_UV2]
  if uv2 is PackedVector2Array:
    final_arrays[Mesh.ARRAY_TEX_UV2] = uv2
  else:
    final_arrays[Mesh.ARRAY_TEX_UV2] = null

    # 6..7: tangents/weights slot specifics; we'll handle bones/weights later
    # We'll search for a valid indices array anywhere in original_arrays
  var vertex_count = final_arrays[Mesh.ARRAY_VERTEX].size()

  var found_index = false
  for i in range(original_arrays.size()):
    var cand = original_arrays[i]
    if cand == null:
      continue
    if cand is PackedInt32Array:
            # treat as candidate for indices (or some importers put other int arrays here; validate)
      if cand.size() > 0 and cand.size() % 3 == 0:
        var maxv = -1
        for idx in cand:
          if int(idx) > maxv:
            maxv = int(idx)
        if maxv < vertex_count:
                    # accept this as the indices array (move it)
          final_arrays[Mesh.ARRAY_INDEX] = cand
          print("Detected indices array at original slot %d (size=%d), moved to ARRAY_INDEX" % [i, cand.size()])
          found_index = true
          break

    # If no indices found, attempt to auto-generate sequential indices if safe
  if not found_index:
    if vertex_count % 3 == 0:
      var seq = PackedInt32Array()
      seq.resize(vertex_count)
      for i in range(vertex_count):
        seq[i] = i
      final_arrays[Mesh.ARRAY_INDEX] = seq
      print("No indices found in source; generated sequential indices (vertex_count % 3 == 0).")
      found_index = true
    else:
      push_error("No suitable index array found and vertex_count (%d) is not divisible by 3; cannot auto-create indices." % vertex_count)
            # print helpful diagnostics and abort
      return false

    # Ensure bones & weights exist in correct typed arrays (4 per vertex)
  var req_size = vertex_count * 4
  var bones := PackedInt32Array()
  bones.resize(req_size)
  bones.fill(0)
  var weights := PackedFloat32Array()
  weights.resize(req_size)
  for v in range(vertex_count):
    var base = v * 4
    weights[base + 0] = 1.0
    weights[base + 1] = 0.0
    weights[base + 2] = 0.0
    weights[base + 3] = 0.0

  final_arrays[Mesh.ARRAY_BONES] = bones
  final_arrays[Mesh.ARRAY_WEIGHTS] = weights

    # Final pre-checks: ensure array types match expectations
  if not (final_arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array):
    push_error("Final vertex array missing or wrong type.")
    return false
  if not (final_arrays[Mesh.ARRAY_INDEX] is PackedInt32Array):
    push_error("Final index array missing or wrong type.")
    return false
  if not (final_arrays[Mesh.ARRAY_BONES] is PackedInt32Array):
    push_error("Final bones array wrong type.")
    return false
  if not (final_arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array):
    push_error("Final weights array wrong type.")
    return false

    # Create new mesh from sanitized arrays
  var new_skinned_mesh := ArrayMesh.new()
  new_skinned_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, final_arrays)
  if new_skinned_mesh.get_surface_count() == 0:
    push_error("FATAL: Failed to create new mesh surface. new_skinned_mesh.get_surface_count() == 0")
    return false

    # preserve material
  new_skinned_mesh.surface_set_material(0, p_original_mesh.surface_get_material(0))
  mesh_instance.mesh = new_skinned_mesh
  print("Replaced mesh with a new instance containing fresh skinning data.")
  return true

func _generate_collision() -> void:
  print("Generating collision...")

    # Clean previous helper node if present and valid
  if temp_plugin_node and is_instance_valid(temp_plugin_node):
    if temp_plugin_node.get_parent() == mesh_instance:
      mesh_instance.remove_child(temp_plugin_node)
    temp_plugin_node.queue_free()
    temp_plugin_node = null

    # Create a Node3D to hold helper nodes (collision, cursor, etc.)
  temp_plugin_node = Node3D.new()
  temp_plugin_node.name = "VertexWeightsPainter"
    # Mark it as non-exported helper by setting a custom metadata (useful for debugging)
  temp_plugin_node.set_meta("vertex_weights_helper", true)

    # Create collision shape from current mesh
  if mesh_instance and mesh_instance.mesh:
    var shape = mesh_instance.mesh.create_trimesh_shape()
    if shape:
      temp_collision = CollisionShape3D.new()
      temp_collision.shape = shape

      temp_body = StaticBody3D.new()
      temp_body.collision_layer = 1  # Make sure it's on a layer that can be hit
      temp_body.add_child(temp_collision)
      temp_plugin_node.add_child(temp_body)

      print("Collision shape created and added to static body")
    else:
      push_warning("Failed to create trimesh shape for mesh. Collision not created.")
  else:
    push_warning("No mesh to generate collision from.")

    # Add node under the mesh_instance
  if mesh_instance:
    mesh_instance.add_child(temp_plugin_node)
        # Set owner to the edited root so it's visible in the scene while editing
    temp_plugin_node.owner = root
    print("Temp plugin node added to mesh instance")

  print("Collision generation complete")

func _setup_ui_panel() -> void:
  var vertex_weights_panel = $VBoxContainer/VertexWeightsPanel
  var bone_names = get_bone_names_from_skeleton()
  vertex_weights_panel.setup_bones(bone_names, 0)
  if not vertex_weights_panel.is_connected("values_changed", Callable(self, "_on_vertex_weights_panel_values_changed")):
    vertex_weights_panel.connect("values_changed", Callable(self, "_on_vertex_weights_panel_values_changed"))
  if not vertex_weights_panel.is_connected("apply_weights", Callable(self, "_on_vertex_weights_panel_apply_weights")):
    vertex_weights_panel.connect("apply_weights", Callable(self, "_on_vertex_weights_panel_apply_weights"))
  if not vertex_weights_panel.is_connected("clear_preview", Callable(self, "_on_vertex_weights_panel_clear_preview")):
    vertex_weights_panel.connect("clear_preview", Callable(self, "_on_vertex_weights_panel_clear_preview"))
  if not vertex_weights_panel.is_connected("bone_selected", Callable(self, "_on_bone_selected")):
    vertex_weights_panel.connect("bone_selected", Callable(self, "_on_bone_selected"))
  if vertex_weights_panel.has_method("setup"):
    vertex_weights_panel.setup()

func apply_weights_to_mesh() -> void:
  if not is_setup_complete:
    push_error("Setup is not complete. Cannot apply weights.")
    return

  var mesh := mesh_instance.mesh
  if not (mesh and mesh is ArrayMesh):
    push_error("Mesh is not an ArrayMesh or is invalid.")
    return

  var arrays = mesh.surface_get_arrays(0)
  if arrays == null:
    push_error("No arrays found on mesh.")
    return

  var vertex_count = arrays[Mesh.ARRAY_VERTEX].size()
  var uvs : PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
  if uvs == null or uvs.size() == 0:
    push_error("Mesh has no UV coordinates. Cannot apply weights.")
    return

  var new_bones := PackedInt32Array()
  new_bones.resize(vertex_count * 4)
  var new_weights := PackedFloat32Array()
  new_weights.resize(vertex_count * 4)

  var bone_images = plugin_cursor.get_all_bone_images()
  var bone_indices = bone_images.keys()

  for i in range(vertex_count):
    var uv = uvs[i]
    var tex_x = int(clamp(uv.x * plugin_cursor.texture_size, 0, plugin_cursor.texture_size - 1))
    var tex_y = int(clamp(uv.y * plugin_cursor.texture_size, 0, plugin_cursor.texture_size - 1))

    var vertex_influences := []
    for bone_idx in bone_indices:
      var img : Image = bone_images[bone_idx]
      if img == null:
        continue
      var c = img.get_pixel(tex_x, tex_y)
      var weight = c.r
      if weight > 0.001:
        vertex_influences.append({"bone": bone_idx, "weight": weight})

    vertex_influences.sort_custom(func(a, b):
      return int(sign(b["weight"] - a["weight"]))
    )

        # CRITICAL FIX: Ensure at least one bone has weight
    if vertex_influences.size() == 0:
            # If no bones influence this vertex, assign it to bone 0 with full weight
      vertex_influences.append({"bone": 0, "weight": 1.0})

    if vertex_influences.size() > 4:
      vertex_influences = vertex_influences.slice(0, 4)

    var total_weight = 0.0
    for inf in vertex_influences:
      total_weight += inf["weight"]

        # Normalize weights so they sum to 1.0
    if total_weight > 0.0:
      for inf in vertex_influences:
        inf["weight"] = inf["weight"] / total_weight
    else:
            # Fallback: if somehow total is still 0, use bone 0
      vertex_influences = [{"bone": 0, "weight": 1.0}]

    var base_idx = i * 4
    for j in range(4):
      if j < vertex_influences.size():
        new_bones[base_idx + j] = vertex_influences[j]["bone"]
        new_weights[base_idx + j] = vertex_influences[j]["weight"]
      else:
        new_bones[base_idx + j] = 0
        new_weights[base_idx + j] = 0.0

  arrays[Mesh.ARRAY_BONES] = new_bones
  arrays[Mesh.ARRAY_WEIGHTS] = new_weights

  var mat = mesh.surface_get_material(0)
  var new_mesh := ArrayMesh.new()
  new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
  if mat:
    new_mesh.surface_set_material(0, mat)
  mesh_instance.mesh = new_mesh

  print("Successfully applied weights to mesh for %d vertices." % vertex_count)

# utility
func find_skeleton_parent(node: Node) -> Skeleton3D:
  var current = node.get_parent()
  while current:
    if current is Skeleton3D:
      return current
    current = current.get_parent()
  return null

func get_bone_names_from_skeleton() -> Array:
  var bone_names := []
  var skeleton = find_skeleton_parent(mesh_instance)
  if is_instance_valid(skeleton):
    for i in range(skeleton.get_bone_count()):
      bone_names.append(skeleton.get_bone_name(i))
  else:
    bone_names.append("Bone_0")
  return bone_names

func update_shader_for_current_bone() -> void:
  if plugin_cursor and vertex_weights_material:
    var weight_texture = plugin_cursor.get_current_bone_texture()
    vertex_weights_material.set_shader_parameter("weight_texture", weight_texture)
    vertex_weights_material.set_shader_parameter("current_bone_index", plugin_cursor.current_bone_index)

func _on_bone_selected(bone_index: int) -> void:
  if plugin_cursor:
    plugin_cursor.set_current_bone(bone_index)
    update_shader_for_current_bone()

func _on_vertex_weights_panel_values_changed(brush_color, brush_opacity, brush_size, weight_value) -> void:
  if plugin_cursor:
    plugin_cursor.set_brush_color(brush_color)
    plugin_cursor.set_brush_opacity(brush_opacity)
    plugin_cursor.set_brush_size(brush_size)
    plugin_cursor.weight_value = weight_value

func _on_vertex_weights_panel_apply_weights() -> void:
  apply_weights_to_mesh()

func _on_vertex_weights_panel_clear_bone() -> void:
  if plugin_cursor:
    plugin_cursor.clear_current_bone_weights()
    update_shader_for_current_bone()

func _on_vertex_weights_panel_clear_all() -> void:
  if plugin_cursor:
    plugin_cursor.clear_all_bone_weights()
    update_shader_for_current_bone()
