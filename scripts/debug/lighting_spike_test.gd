extends Node
## Lighting Spike Test — Temporary debug script
##
## Autoload that spawns OmniLight3D nodes around the player to test GL Compatibility limits.
## Works on both tutorial (Level -1) and Level 0.
##
## Controls:
##   F6  = Print light count + FPS to console
##   F7  = Toggle void-fill floor plane (fixes bright void under walls)
##   F9  = Add 4 lights near player (increment test)
##   F10 = Remove all test lights + restore lighting
##   F11 = Cycle lighting: NORMAL → DIM → OFF → DARK → NORMAL
##
## Y COORDINATE REFERENCE (empirically confirmed):
##   Y=4.4  — Ceiling surface (just below ceiling tiles)
##   Y=2.5  — Midpoint (eye level)
##   Y=1.0  — Player / Entity billboards (player_3d.gd)
##   Y=0.51 — Spraypaint text (spraypaint_renderer.gd)
##   Y=0.48 — Void-fill floor plane
##   Y=0.0  — Bottom of floor cell (the void under walls)
##
## LIGHT HEIGHTS (per-level, defined in level config):
##   Ceiling fixtures (Level 0 fluorescent): Y=4.4
##   Barrel fires (Level -1):                Y=TBD (ground level, much lower)

var test_lights: Array[OmniLight3D] = []
var debug_meshes: Array[MeshInstance3D] = []
var light_container: Node3D = null
var void_plane: MeshInstance3D = null

# On-screen HUD
var hud_label: Label = null
var hud_layer: CanvasLayer = null

# Lighting presets to cycle through
enum LightPreset { NORMAL, DIM, OFF, DARK }
var current_preset := LightPreset.NORMAL
var preset_names := ["NORMAL", "DIM (dir 0.15)", "DIR OFF", "DARK (dir off + amb low)"]

# Saved originals for restore
var _original_directional_energy := -1.0
var _original_ambient_energy := -1.0
var _original_ambient_color := Color.WHITE

# Light configuration (Level 0 fluorescent aesthetic)
const LIGHT_COLOR := Color(0.95, 0.9, 0.7)
const LIGHT_ENERGY := 1.2
const LIGHT_RANGE := 8.0   # World units (4 tiles at cell_size 2.0)
const LIGHT_Y := 4.4       # Ceiling fixtures — empirically confirmed
const VOID_PLANE_Y := 0.48 # Just below floor surface — empirically confirmed

# Debug sphere for visualizing light positions
var _sphere_mesh: SphereMesh = null
var _sphere_material: StandardMaterial3D = null

func _ready() -> void:
	light_container = Node3D.new()
	light_container.name = "LightingSpikeTest"

	# Pre-create shared mesh + material for debug spheres
	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = 0.15
	_sphere_mesh.height = 0.3
	_sphere_mesh.radial_segments = 8
	_sphere_mesh.rings = 4

	_sphere_material = StandardMaterial3D.new()
	_sphere_material.albedo_color = Color(1.0, 1.0, 0.5)
	_sphere_material.emission_enabled = true
	_sphere_material.emission = Color(1.0, 0.95, 0.6)
	_sphere_material.emission_energy_multiplier = 3.0
	_sphere_material.render_priority = 127

	# Create HUD overlay
	_create_hud()

	# Wait for game scene to load before attaching
	get_tree().node_added.connect(_on_node_added)
	# Wait for chunks to finish loading before creating void plane
	if ChunkManager.initial_load_completed.is_connected(_on_initial_load_completed):
		return
	ChunkManager.initial_load_completed.connect(_on_initial_load_completed)

func _create_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 100
	add_child(hud_layer)

	hud_label = Label.new()
	hud_label.position = Vector2(10, 10)
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.7))
	hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hud_label.add_theme_constant_override("shadow_offset_x", 1)
	hud_label.add_theme_constant_override("shadow_offset_y", 1)
	hud_layer.add_child(hud_label)
	_update_hud()

func _update_hud() -> void:
	if not hud_label:
		return
	var valid_count = test_lights.filter(func(l): return is_instance_valid(l)).size()
	var fps = Engine.get_frames_per_second()
	var plane_status = "ON" if (void_plane and is_instance_valid(void_plane) and void_plane.visible) else "OFF"
	hud_label.text = "[LIGHT SPIKE] Lights: %d | FPS: %d | Mode: %s | Floor plane: %s\nF6=stats | F7=floor plane | F9=+4 lights | F10=clear | F11=cycle mode" % [
		valid_count, fps, preset_names[current_preset], plane_status
	]

func _process(_delta: float) -> void:
	_update_hud()

func _on_initial_load_completed() -> void:
	print("[LightSpike] Initial load completed — creating void plane")
	# Defer to ensure Game node is fully parented
	call_deferred("_ensure_void_plane")

func _on_node_added(node: Node) -> void:
	if node.name == "Game" and node is Node3D:
		if light_container.get_parent() != null:
			light_container.get_parent().remove_child(light_container)
		node.add_child.call_deferred(light_container)
		_original_directional_energy = -1.0
		# Create void plane deferred
		call_deferred("_ensure_void_plane")
		print("[LightSpike] Attached to game scene")

func _ensure_void_plane() -> void:
	"""Create or re-parent the void-fill floor plane."""
	# Find the Game node
	var game = _find_node_by_name("Game")
	if not game:
		print("[LightSpike] Game node not found for void plane")
		return

	if void_plane and is_instance_valid(void_plane):
		# Re-parent if needed (scene reload)
		if void_plane.get_parent() != game:
			if void_plane.get_parent():
				void_plane.get_parent().remove_child(void_plane)
			game.add_child(void_plane)
		return

	# Create new plane
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(4000.0, 4000.0)

	var plane_mat := StandardMaterial3D.new()
	plane_mat.albedo_color = Color.BLACK
	plane_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	void_plane = MeshInstance3D.new()
	void_plane.mesh = plane_mesh
	void_plane.material_override = plane_mat
	void_plane.name = "VoidFillPlane"
	void_plane.visible = true

	game.add_child(void_plane)
	void_plane.global_position = Vector3(0, VOID_PLANE_Y, 0)
	print("[LightSpike] Void-fill plane created at Y=%.2f" % VOID_PLANE_Y)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F6:
				_print_stats()
			KEY_F7:
				_toggle_void_plane()
			KEY_F9:
				_add_lights_near_player(4)
			KEY_F10:
				_clear_all_lights()
			KEY_F11:
				_cycle_lighting_preset()

func _toggle_void_plane() -> void:
	if void_plane and is_instance_valid(void_plane):
		void_plane.visible = not void_plane.visible
		print("[LightSpike] Floor plane: %s" % ("ON" if void_plane.visible else "OFF"))
	else:
		print("[LightSpike] Floor plane not created — trying to create now")
		_ensure_void_plane()

func _add_lights_near_player(count: int) -> void:
	var player = _find_node_by_name("Player3D")
	if not player:
		print("[LightSpike] Player not found")
		return

	if light_container.get_parent() == null:
		var game = _find_node_by_name("Game")
		if game:
			game.add_child(light_container)

	var player_pos: Vector3 = player.global_position
	var grid_3d = _find_by_type_grid3d()
	var added := 0

	for i in range(count):
		var angle = randf() * TAU
		var distance = randf_range(4.0, 16.0)
		var offset = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		var light_pos = player_pos + offset
		light_pos.y = LIGHT_Y

		if grid_3d:
			var grid_pos = grid_3d.world_to_grid(light_pos)
			if not grid_3d.is_walkable(grid_pos):
				continue
			light_pos = grid_3d.grid_to_world_centered(grid_pos, LIGHT_Y)

		# Create OmniLight3D
		var light := OmniLight3D.new()
		light.light_color = LIGHT_COLOR
		light.light_energy = LIGHT_ENERGY
		light.omni_range = LIGHT_RANGE
		light.shadow_enabled = false
		light.light_specular = 0.0
		light.omni_attenuation = 1.0
		light_container.add_child(light)
		light.global_position = light_pos
		test_lights.append(light)

		# Create debug sphere at light position
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _sphere_mesh
		mesh_instance.material_override = _sphere_material
		light_container.add_child(mesh_instance)
		mesh_instance.global_position = light_pos
		debug_meshes.append(mesh_instance)
		added += 1

	print("[LightSpike] Added %d lights at Y=%.2f (total: %d)" % [added, LIGHT_Y, test_lights.size()])

func _clear_all_lights() -> void:
	for light in test_lights:
		if is_instance_valid(light):
			light.queue_free()
	for mesh in debug_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	test_lights.clear()
	debug_meshes.clear()
	if current_preset != LightPreset.NORMAL:
		current_preset = LightPreset.NORMAL
		_apply_preset()
	print("[LightSpike] Cleared all test lights, restored lighting")

func _cycle_lighting_preset() -> void:
	current_preset = ((current_preset as int + 1) % LightPreset.size()) as LightPreset
	_apply_preset()

func _apply_preset() -> void:
	var dir_light := _find_by_type(get_tree().root, DirectionalLight3D) as DirectionalLight3D
	var world_env := _find_by_type(get_tree().root, WorldEnvironment) as WorldEnvironment

	if not dir_light:
		print("[LightSpike] DirectionalLight3D not found")
		return
	if not world_env or not world_env.environment:
		print("[LightSpike] WorldEnvironment not found")
		return

	var env := world_env.environment

	if _original_directional_energy < 0:
		_original_directional_energy = dir_light.light_energy
		_original_ambient_energy = env.ambient_light_energy
		_original_ambient_color = env.ambient_light_color

	match current_preset:
		LightPreset.NORMAL:
			dir_light.light_energy = _original_directional_energy
			env.ambient_light_energy = _original_ambient_energy
			env.ambient_light_color = _original_ambient_color
		LightPreset.DIM:
			dir_light.light_energy = 0.15
			env.ambient_light_energy = _original_ambient_energy
			env.ambient_light_color = _original_ambient_color
		LightPreset.OFF:
			dir_light.light_energy = 0.0
			env.ambient_light_energy = _original_ambient_energy
			env.ambient_light_color = _original_ambient_color
		LightPreset.DARK:
			dir_light.light_energy = 0.0
			env.ambient_light_energy = 0.08
			env.ambient_light_color = Color(0.3, 0.3, 0.4)

	print("[LightSpike] Mode: %s | Dir: %.2f | Amb: %.2f" % [
		preset_names[current_preset], dir_light.light_energy, env.ambient_light_energy
	])

func _print_stats() -> void:
	var fps = Engine.get_frames_per_second()
	var valid_lights = test_lights.filter(func(l): return is_instance_valid(l))

	var dir_light := _find_by_type(get_tree().root, DirectionalLight3D) as DirectionalLight3D
	var world_env := _find_by_type(get_tree().root, WorldEnvironment) as WorldEnvironment

	var dir_energy := dir_light.light_energy if dir_light else -1.0
	var amb_energy := world_env.environment.ambient_light_energy if world_env and world_env.environment else -1.0

	var sphere_y := "N/A"
	if not debug_meshes.is_empty() and is_instance_valid(debug_meshes[0]):
		sphere_y = "%.2f" % debug_meshes[0].global_position.y

	var plane_y := "N/A"
	if void_plane and is_instance_valid(void_plane):
		plane_y = "%.2f (visible=%s)" % [void_plane.global_position.y, void_plane.visible]

	print("[LightSpike] === STATS ===")
	print("[LightSpike] Active lights: %d | FPS: %d" % [valid_lights.size(), fps])
	print("[LightSpike] Directional: %.2f | Ambient: %.2f" % [dir_energy, amb_energy])
	print("[LightSpike] Sphere Y: %s | Void plane: %s" % [sphere_y, plane_y])

# ============================================================================
# NODE FINDING
# ============================================================================

func _find_node_by_name(target_name: String, node: Node = null) -> Node:
	if node == null:
		node = get_tree().root
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result = _find_node_by_name(target_name, child)
		if result:
			return result
	return null

func _find_by_type(node: Node, type: Variant) -> Node:
	if is_instance_of(node, type):
		return node
	for child in node.get_children():
		var result = _find_by_type(child, type)
		if result:
			return result
	return null

func _find_by_type_grid3d(node: Node = null) -> Grid3D:
	if node == null:
		node = get_tree().root
	if node is Grid3D:
		return node
	for child in node.get_children():
		var result = _find_by_type_grid3d(child)
		if result:
			return result
	return null
