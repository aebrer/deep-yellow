extends SceneTree
## Run with: godot --headless --script _claude_scripts/generate_wall_mesh.gd
##
## Generates a wall box mesh with different materials per face and saves it.
## The mesh has 6 surfaces:
## - Surface 0: Bottom face (floor material) - visible from ABOVE (normal UP)
## - Surface 1: Top face (ceiling_wall material) - caps wall, NO proximity fade
## - Surfaces 2-5: Side faces (wall material) - visible from OUTSIDE
## NOTE: ceiling_wall.tres uses psx_lit_nocull (solid/opaque) unlike the main
## ceiling tiles which use proximity fade for tactical cam see-through.

func _init():
	print("=" .repeat(60))
	print("Generating multi-material wall mesh...")
	print("=" .repeat(60))

	# Load materials
	var floor_mat = load("res://assets/levels/level_00/floor_brown.tres")
	var wall_mat = load("res://assets/levels/level_00/wall_yellow.tres")
	var ceiling_wall_mat = load("res://assets/levels/level_00/ceiling_wall.tres")

	if not floor_mat or not wall_mat or not ceiling_wall_mat:
		push_error("Failed to load materials!")
		quit(1)
		return

	# Box dimensions: 2x4x2, centered at y=2 (bottom at y=0, top at y=4)
	var half_x := 1.0
	var half_z := 1.0
	var y_bottom := 0.0
	var y_top := 4.0

	var mesh := ArrayMesh.new()

	# Surface 0: Bottom face (floor) at y=0
	# Visible from above, so normal points UP
	# CCW winding when viewed from above (looking down at floor)
	_add_quad(mesh, floor_mat,
		Vector3(-half_x, y_bottom, -half_z),  # back-left
		Vector3(half_x, y_bottom, -half_z),   # back-right
		Vector3(half_x, y_bottom, half_z),    # front-right
		Vector3(-half_x, y_bottom, half_z),   # front-left
		Vector3.UP)

	# Surface 1: Top face (ceiling) at y=4
	# Uses ceiling_wall material (solid/opaque, no proximity fade)
	# This caps the wall so you can't see inside from above
	# Double-sided: visible from both above (tactical cam) and below (FPV looking up)
	_add_quad_double_sided(mesh, ceiling_wall_mat,
		Vector3(-half_x, y_top, half_z),    # front-left
		Vector3(half_x, y_top, half_z),     # front-right
		Vector3(half_x, y_top, -half_z),    # back-right
		Vector3(-half_x, y_top, -half_z))   # back-left

	# Surface 2: Front face (+Z) - visible from +Z direction
	# CCW winding when viewed from +Z
	_add_quad(mesh, wall_mat,
		Vector3(-half_x, y_bottom, half_z),  # bottom-left
		Vector3(-half_x, y_top, half_z),     # top-left
		Vector3(half_x, y_top, half_z),      # top-right
		Vector3(half_x, y_bottom, half_z),   # bottom-right
		Vector3(0, 0, 1))  # +Z normal

	# Surface 3: Back face (-Z) - visible from -Z direction
	# CCW winding when viewed from -Z
	_add_quad(mesh, wall_mat,
		Vector3(half_x, y_bottom, -half_z),  # bottom-left (from -Z view)
		Vector3(half_x, y_top, -half_z),     # top-left
		Vector3(-half_x, y_top, -half_z),    # top-right
		Vector3(-half_x, y_bottom, -half_z), # bottom-right
		Vector3(0, 0, -1))  # -Z normal

	# Surface 4: Right face (+X) - visible from +X direction
	# CCW winding when viewed from +X
	_add_quad(mesh, wall_mat,
		Vector3(half_x, y_bottom, half_z),   # bottom-left (from +X view)
		Vector3(half_x, y_top, half_z),      # top-left
		Vector3(half_x, y_top, -half_z),     # top-right
		Vector3(half_x, y_bottom, -half_z),  # bottom-right
		Vector3(1, 0, 0))  # +X normal

	# Surface 5: Left face (-X) - visible from -X direction
	# CCW winding when viewed from -X
	_add_quad(mesh, wall_mat,
		Vector3(-half_x, y_bottom, -half_z), # bottom-left (from -X view)
		Vector3(-half_x, y_top, -half_z),    # top-left
		Vector3(-half_x, y_top, half_z),     # top-right
		Vector3(-half_x, y_bottom, half_z),  # bottom-right
		Vector3(-1, 0, 0))  # -X normal

	# Save the mesh
	var save_path := "res://assets/levels/level_00/wall_multimat.tres"
	var err := ResourceSaver.save(mesh, save_path)
	if err == OK:
		print("SUCCESS: Saved mesh to: ", save_path)
	else:
		push_error("Failed to save mesh: error ", err)
		quit(1)
		return

	quit(0)


func _add_quad(mesh: ArrayMesh, material: Material, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3) -> void:
	# Double-sided quad: vertices for both front and back faces
	# Front face uses normal, back face uses -normal
	var back_normal := -normal

	var vertices := PackedVector3Array([
		# Front face (indices 0-3)
		v0, v1, v2, v3,
		# Back face (indices 4-7) - same positions, different normals
		v0, v1, v2, v3
	])

	var normals := PackedVector3Array([
		# Front face normals
		normal, normal, normal, normal,
		# Back face normals (inverted)
		back_normal, back_normal, back_normal, back_normal
	])

	# UVs: v0=bottom-left, v1=top-left, v2=top-right, v3=bottom-right
	var uvs := PackedVector2Array([
		# Front face UVs
		Vector2(0, 1),  # v0: bottom-left
		Vector2(0, 0),  # v1: top-left
		Vector2(1, 0),  # v2: top-right
		Vector2(1, 1),  # v3: bottom-right
		# Back face UVs (mirrored horizontally for correct appearance)
		Vector2(1, 1),  # v0: bottom-right (mirrored)
		Vector2(1, 0),  # v1: top-right (mirrored)
		Vector2(0, 0),  # v2: top-left (mirrored)
		Vector2(0, 1),  # v3: bottom-left (mirrored)
	])

	# Front face: 0-1-2 and 0-2-3 (CCW)
	# Back face: 4-6-5 and 4-7-6 (reversed winding = CW from front, CCW from back)
	var indices := PackedInt32Array([
		0, 1, 2, 0, 2, 3,  # Front face
		4, 6, 5, 4, 7, 6   # Back face (reversed winding)
	])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


func _add_quad_double_sided(mesh: ArrayMesh, material: Material, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	# Horizontal quad visible from both above and below
	# Creates two surfaces with opposite normals for proper lighting on each side
	# Small Y offset between surfaces to prevent Z-fighting

	var y_offset := 0.001  # Tiny offset to prevent Z-fighting

	# Surface for viewing from above (normal UP) - slightly higher
	var vertices_up := PackedVector3Array([
		v0 + Vector3(0, y_offset, 0),
		v1 + Vector3(0, y_offset, 0),
		v2 + Vector3(0, y_offset, 0),
		v3 + Vector3(0, y_offset, 0)
	])
	var normals_up := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	])
	# CCW winding when viewed from above
	var indices_up := PackedInt32Array([0, 3, 2, 0, 2, 1])

	var arrays_up := []
	arrays_up.resize(Mesh.ARRAY_MAX)
	arrays_up[Mesh.ARRAY_VERTEX] = vertices_up
	arrays_up[Mesh.ARRAY_NORMAL] = normals_up
	arrays_up[Mesh.ARRAY_TEX_UV] = uvs
	arrays_up[Mesh.ARRAY_INDEX] = indices_up

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_up)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)

	# Surface for viewing from below (normal DOWN) - slightly lower
	var vertices_down := PackedVector3Array([
		v0 - Vector3(0, y_offset, 0),
		v1 - Vector3(0, y_offset, 0),
		v2 - Vector3(0, y_offset, 0),
		v3 - Vector3(0, y_offset, 0)
	])
	var normals_down := PackedVector3Array([Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN])
	# CCW winding when viewed from below (reversed)
	var indices_down := PackedInt32Array([0, 1, 2, 0, 2, 3])

	var arrays_down := []
	arrays_down.resize(Mesh.ARRAY_MAX)
	arrays_down[Mesh.ARRAY_VERTEX] = vertices_down
	arrays_down[Mesh.ARRAY_NORMAL] = normals_down
	arrays_down[Mesh.ARRAY_TEX_UV] = uvs
	arrays_down[Mesh.ARRAY_INDEX] = indices_down

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_down)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
