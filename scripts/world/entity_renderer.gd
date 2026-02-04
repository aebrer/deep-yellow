class_name EntityRenderer extends Node3D
## Renders entities as 3D billboards in the world
##
## Creates and manages Billboard3D nodes for entities that exist in loaded chunks.
## Billboards are created when chunks load and destroyed when chunks unload.
##
## ARCHITECTURE: EntityRenderer is RENDER-ONLY
## - WorldEntity is the authoritative source of entity state (HP, dead flag)
## - EntityRenderer connects to WorldEntity signals for updates
## - State modifications happen through WorldEntity.take_damage(), not here
## - VFX spawning happens here (hit emoji, death emoji)
##
## Follows same pattern as ItemRenderer for consistency.
##
## Responsibilities:
## - Create Billboard3D for each entity in loaded chunks
## - Position billboards at entity world positions
## - Connect to WorldEntity signals for state changes
## - Spawn VFX when entities take damage or die
## - Remove billboards when entities die (after VFX delay)
## - Cleanup billboards when chunks unload

# ============================================================================
# DEPENDENCIES
# ============================================================================

## Font with emoji fallback for floating VFX text
## Uses default_font.tres which has NotoColorEmoji as fallback
const _EMOJI_FONT = preload("res://assets/fonts/default_font.tres")

@onready var grid_3d: Grid3D = get_parent()

# ============================================================================
# STATE
# ============================================================================

## Maps world tile position to Sprite3D node
var entity_billboards: Dictionary = {}  # Vector2i -> Sprite3D

## Maps world tile position to WorldEntity reference
var entity_cache: Dictionary = {}  # Vector2i -> WorldEntity

## Maps world tile position to health bar Node3D
var entity_health_bars: Dictionary = {}  # Vector2i -> Node3D

## Reverse lookup: WorldEntity -> Vector2i (for O(1) entity position lookup)
var entity_to_pos: Dictionary = {}  # WorldEntity -> Vector2i

## Project-wide invalid position sentinel
const INVALID_POSITION := Vector2i(-999999, -999999)

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when an entity dies (for EXP rewards etc.)
## entity: WorldEntity that died
signal entity_died(entity: WorldEntity)

# ============================================================================
# CONFIGURATION
# ============================================================================

## Billboard size (world units)
const BILLBOARD_SIZE = 1.0

## Billboard height above floor (world units)
## Matches player Y position (1.0) so entities float at same height
const BILLBOARD_HEIGHT = 1.0

## Max render distance (world units). Entities beyond this are culled.
## Set beyond fog_end (35.0) with margin for tactical camera zoom offset (~25 units).
const VISIBILITY_RANGE_END = 60.0

## Entity type colors (fallback when no texture)
const ENTITY_COLORS = {
	"debug_enemy": Color(1.0, 0.0, 1.0),       # Magenta
	"bacteria_spawn": Color(0.5, 1.0, 0.5),    # Light green
	"bacteria_motherload": Color(0.0, 0.8, 0.0),  # Dark green
	"bacteria_spreader": Color(0.3, 0.6, 0.2),   # Darker green with yellow tint
	"smiler": Color(1.0, 1.0, 0.8),             # Pale yellow/white (eerie glow)
	"tutorial_mannequin": Color(0.85, 0.75, 0.65),  # Pale beige plastic
	"vending_machine": Color(0.6, 0.6, 0.7),        # Metallic gray-blue
	"exit_hole": Color(0.15, 0.1, 0.1),             # Dark pit
}

## Entity render modes: BILLBOARD (default, faces camera) or FLOOR_DECAL (flat on ground)
enum RenderMode { BILLBOARD, FLOOR_DECAL }
const ENTITY_RENDER_MODES = {
	"exit_hole": RenderMode.FLOOR_DECAL,
}

## Entity textures (loaded on demand)
const ENTITY_TEXTURES = {
	"bacteria_spawn": "res://assets/textures/entities/bacteria_spawn.png",
	"bacteria_motherload": "res://assets/textures/entities/bacteria_motherload.png",
	"bacteria_spreader": "res://assets/textures/entities/bacteria_spreader.png",
	"smiler": "res://assets/textures/entities/smiler.png",
	"tutorial_mannequin": "res://assets/textures/entities/tutorial_mannequin.png",
	"exit_hole": "res://assets/textures/entities/exit_hole.png",
	"vending_machine": "res://assets/textures/entities/vending_machine.png",
}

## Per-entity scale overrides (multiplier on BILLBOARD_SIZE)
const ENTITY_SCALE_OVERRIDES = {
	"bacteria_motherload": 2.0,  # Boss-sized
	"smiler": 2.0,  # Large, imposing presence
	"tutorial_mannequin": 2.0,  # Life-sized mannequin
	"vending_machine": 2.5,    # Tall vending machine
}

## Per-entity height overrides (world units above floor)
## Larger entities need higher placement so their bottom doesn't clip floor
const ENTITY_HEIGHT_OVERRIDES = {
	"bacteria_motherload": 2.0,  # Raised to match 2x size scale
	"smiler": 3.0,  # Floats ominously above the floor
	"tutorial_mannequin": 2.0,  # Raised to match 2x size scale
	"vending_machine": 2.5,    # Tall machine, raised to match scale
}

## Default entity color
const DEFAULT_ENTITY_COLOR = Color(1.0, 0.0, 0.0)  # Red


## Hit emoji VFX configuration
const HIT_EMOJI_RISE_HEIGHT = 1.2  # World units to rise (more visible travel)
const HIT_EMOJI_DURATION = 1.0  # Seconds for full animation (turn-based, no rush!)
const HIT_EMOJI_BASE_SIZE = 96  # Base font size (before scaling) - needs to be large for 3D visibility
const HIT_EMOJI_JITTER = 0.4  # Random position offset range (world units)

## Health bar configuration
const HEALTH_BAR_WIDTH = 0.5  # World units (larger for visibility)
const HEALTH_BAR_HEIGHT = 0.08  # World units (thicker)
const HEALTH_BAR_OFFSET_Y = 0.4  # Above entity sprite
const HEALTH_BAR_BG_COLOR = Color(0.0, 0.0, 0.0, 0.9)  # Black background (very visible)
const HEALTH_BAR_FG_COLOR = Color(0.9, 0.15, 0.15, 1.0)  # Bright red health

## Shared health bar shader (CRITICAL: reuse to avoid memory leak from shader recompilation)
## Creating a new Shader per entity causes massive memory bloat on web/WASM.
var _health_bar_shader: Shader = null

# ============================================================================
# CHUNK LOADING
# ============================================================================

func render_chunk_entities(chunk: Chunk) -> void:
	"""Create billboards for all entities in chunk

	Connects to WorldEntity signals for HP/death updates.

	Args:
		chunk: Chunk that was just loaded
	"""
	for subchunk in chunk.sub_chunks:
		for entity in subchunk.world_entities:
			# Skip if dead
			if entity.is_dead:
				continue

			var world_pos = entity.world_position

			# Skip if billboard already exists (shouldn't happen, but safety check)
			if entity_billboards.has(world_pos):
				continue

			# Create billboard
			var billboard = _create_billboard_for_entity(entity)
			if billboard:
				add_child(billboard)
				entity_billboards[world_pos] = billboard
				entity_cache[world_pos] = entity

				# Create health bar (as sibling, not child - avoids billboard nesting issues)
				var health_bar = _create_health_bar(billboard.position)
				add_child(health_bar)
				entity_health_bars[world_pos] = health_bar

				# Add reverse lookup for O(1) entity position finding
				entity_to_pos[entity] = world_pos

				# Connect to WorldEntity signals
				# Bind to entity (not position) so callbacks remain valid after entity moves
				if not entity.hp_changed.is_connected(_on_entity_hp_changed):
					entity.hp_changed.connect(_on_entity_hp_changed.bind(entity))
				if not entity.died.is_connected(_on_entity_died_signal):
					entity.died.connect(_on_entity_died_signal)
				if not entity.moved.is_connected(_on_entity_moved):
					entity.moved.connect(_on_entity_moved)

				# Check if entity is already damaged
				var hp_percent = entity.get_hp_percentage()
				if hp_percent < 1.0:
					_update_health_bar(world_pos, hp_percent)
				else:
					health_bar.visible = false

func unload_chunk_entities(chunk: Chunk) -> void:
	"""Remove billboards for all entities in chunk

	Note: We don't disconnect signals here - the EntityRenderer persists across
	chunk loads/unloads, so the signal handlers remain valid. Signals will be
	cleaned up when the scene reloads (start_new_run).

	Args:
		chunk: Chunk being unloaded
	"""
	var removed_count = 0

	for subchunk in chunk.sub_chunks:
		for entity in subchunk.world_entities:
			var world_pos = entity.world_position

			if entity_billboards.has(world_pos):
				var billboard = entity_billboards[world_pos]
				billboard.queue_free()
				entity_billboards.erase(world_pos)
				entity_cache.erase(world_pos)
				entity_to_pos.erase(entity)

				# Also remove health bar
				if entity_health_bars.has(world_pos):
					var health_bar = entity_health_bars[world_pos]
					health_bar.queue_free()
					entity_health_bars.erase(world_pos)

				removed_count += 1

# ============================================================================
# DYNAMIC ENTITY MANAGEMENT (for mid-game spawns and movement)
# ============================================================================

func add_entity_billboard(entity: WorldEntity) -> void:
	"""Add a billboard for a newly spawned entity (mid-game spawn)

	Used when entities spawn during gameplay (e.g., Motherload spawning minions).

	Args:
		entity: WorldEntity to create billboard for
	"""
	if entity.is_dead:
		return

	var world_pos = entity.world_position

	# Skip if billboard already exists
	if entity_billboards.has(world_pos):
		Log.warn(Log.Category.ENTITY, "Billboard already exists at %s" % world_pos)
		return

	# Create billboard
	var billboard = _create_billboard_for_entity(entity)
	if billboard:
		add_child(billboard)
		entity_billboards[world_pos] = billboard
		entity_cache[world_pos] = entity

		# Create health bar
		var health_bar = _create_health_bar(billboard.position)
		add_child(health_bar)
		entity_health_bars[world_pos] = health_bar
		health_bar.visible = false  # Hidden at full HP

		# Add reverse lookup
		entity_to_pos[entity] = world_pos

		# Connect to WorldEntity signals
		# Bind to entity (not position) so callbacks remain valid after entity moves
		if not entity.hp_changed.is_connected(_on_entity_hp_changed):
			entity.hp_changed.connect(_on_entity_hp_changed.bind(entity))
		if not entity.died.is_connected(_on_entity_died_signal):
			entity.died.connect(_on_entity_died_signal)
		if not entity.moved.is_connected(_on_entity_moved):
			entity.moved.connect(_on_entity_moved)


func _on_entity_moved(old_pos: Vector2i, new_pos: Vector2i) -> void:
	"""Handle WorldEntity moved signal - update billboard position

	Args:
		old_pos: Previous world tile position
		new_pos: New world tile position
	"""
	if not entity_billboards.has(old_pos):
		# This is normal for entities in unloaded chunks - they still process AI
		# but don't have billboards. Only warn at TRACE level.
		return

	# Get billboard and health bar
	var billboard = entity_billboards[old_pos]
	var entity = entity_cache[old_pos]
	var health_bar = entity_health_bars.get(old_pos, null)

	# No signal reconnection needed - hp_changed is bound to entity reference,
	# not position. The callback looks up current position via entity_to_pos.

	# Update cache keys
	entity_billboards.erase(old_pos)
	entity_billboards[new_pos] = billboard
	entity_cache.erase(old_pos)
	entity_cache[new_pos] = entity
	entity_to_pos[entity] = new_pos  # Update reverse lookup
	if health_bar:
		entity_health_bars.erase(old_pos)
		entity_health_bars[new_pos] = health_bar

	# Calculate new 3D position (use height override for this entity type)
	var entity_height = ENTITY_HEIGHT_OVERRIDES.get(entity.entity_type, BILLBOARD_HEIGHT)
	var new_world_3d = grid_3d.grid_to_world_centered(new_pos, entity_height) if grid_3d else Vector3(
		new_pos.x * 2.0 + 1.0,
		entity_height,
		new_pos.y * 2.0 + 1.0
	)

	# Update billboard position (tween if smoothing enabled)
	if Utilities.movement_smoothing:
		var tween = get_tree().create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(billboard, "position", new_world_3d, Player3D.MOVE_TWEEN_DURATION)
		if health_bar:
			tween.parallel().tween_property(health_bar, "position",
				new_world_3d + Vector3(0, HEALTH_BAR_OFFSET_Y, 0),
				Player3D.MOVE_TWEEN_DURATION)
	else:
		billboard.position = new_world_3d
		if health_bar:
			health_bar.position = new_world_3d + Vector3(0, HEALTH_BAR_OFFSET_Y, 0)


# ============================================================================
# BILLBOARD CREATION
# ============================================================================

func _create_billboard_for_entity(entity: WorldEntity) -> Node3D:
	"""Create a visual node for an entity (billboard sprite or floor decal)

	Args:
		entity: WorldEntity to create visual for

	Returns:
		Node3D (Sprite3D for billboards, MeshInstance3D for floor decals) or null
	"""
	var entity_type = entity.entity_type
	var world_pos = entity.world_position
	var render_mode = ENTITY_RENDER_MODES.get(entity_type, RenderMode.BILLBOARD)

	if render_mode == RenderMode.FLOOR_DECAL:
		return _create_floor_decal_for_entity(entity)

	# --- Standard billboard sprite ---
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = true
	sprite.alpha_cut = Sprite3D.ALPHA_CUT_DISCARD

	var entity_height = ENTITY_HEIGHT_OVERRIDES.get(entity_type, BILLBOARD_HEIGHT)
	var world_3d = grid_3d.grid_to_world_centered(world_pos, entity_height) if grid_3d else Vector3(
		world_pos.x * 2.0 + 1.0,
		entity_height,
		world_pos.y * 2.0 + 1.0
	)
	sprite.position = world_3d

	var scale_mult = ENTITY_SCALE_OVERRIDES.get(entity_type, 1.0)
	var final_size = BILLBOARD_SIZE * scale_mult

	var texture_path = ENTITY_TEXTURES.get(entity_type, "")
	if texture_path != "" and ResourceLoader.exists(texture_path):
		var texture = load(texture_path) as Texture2D
		if texture:
			sprite.texture = texture
			sprite.pixel_size = final_size / texture.get_width()
			sprite.modulate = Color.WHITE
			sprite.set_meta("base_color", Color.WHITE)
		else:
			_apply_fallback_texture(sprite, entity_type, scale_mult)
	else:
		_apply_fallback_texture(sprite, entity_type, scale_mult)

	sprite.visibility_range_end = VISIBILITY_RANGE_END

	sprite.set_meta("grid_position", world_pos)
	sprite.set_meta("entity_type", entity_type)

	_add_examination_support(sprite, entity, final_size)

	return sprite

func _create_floor_decal_for_entity(entity: WorldEntity) -> MeshInstance3D:
	"""Create a floor decal (flat quad) for entities like exit holes

	Uses no_depth_test material so the decal renders on top of floor geometry.

	Args:
		entity: WorldEntity to create decal for

	Returns:
		MeshInstance3D positioned flat on the floor
	"""
	var entity_type = entity.entity_type
	var world_pos = entity.world_position

	# Load texture
	var texture_path = ENTITY_TEXTURES.get(entity_type, "")
	var texture: Texture2D = null
	if texture_path != "" and ResourceLoader.exists(texture_path):
		texture = load(texture_path) as Texture2D

	# Create material
	var mat = StandardMaterial3D.new()
	if texture:
		mat.albedo_texture = texture
	else:
		mat.albedo_color = ENTITY_COLORS.get(entity_type, DEFAULT_ENTITY_COLOR)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.1
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	# Create quad mesh sized to one tile
	var cell_size_x = 2.0  # Grid3D.CELL_SIZE.x
	var cell_size_z = 2.0  # Grid3D.CELL_SIZE.z
	var quad = QuadMesh.new()
	quad.size = Vector2(cell_size_x, cell_size_z)
	quad.material = mat

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = quad
	mesh_inst.rotation_degrees.x = -90.0  # Lie flat on floor

	# Position slightly above floor
	var world_3d = grid_3d.grid_to_world_centered(world_pos, 0.05) if grid_3d else Vector3(
		world_pos.x * 2.0 + 1.0,
		0.05,
		world_pos.y * 2.0 + 1.0
	)
	mesh_inst.position = world_3d
	mesh_inst.visibility_range_end = VISIBILITY_RANGE_END

	mesh_inst.set_meta("grid_position", world_pos)
	mesh_inst.set_meta("entity_type", entity_type)

	# Examination support with flat collision box
	_add_examination_support(mesh_inst, entity, cell_size_x, Vector3(cell_size_x, 0.2, cell_size_z))

	return mesh_inst

func _add_examination_support(node: Node3D, entity: WorldEntity, default_size: float, collision_size: Variant = null) -> void:
	"""Add Examinable + StaticBody3D for raycast examination

	Args:
		node: Parent node to attach examination body to
		entity: WorldEntity for type/hostile info
		default_size: Default collision box size (square)
		collision_size: Optional Vector3 override for collision box dimensions
	"""
	var exam_body = StaticBody3D.new()
	exam_body.name = "ExamBody"
	exam_body.collision_layer = 8
	exam_body.collision_mask = 0
	node.add_child(exam_body)

	var examinable = Examinable.new()
	examinable.entity_id = entity.entity_type
	examinable.entity_type = Examinable.EntityType.ENTITY_HOSTILE if entity.hostile else Examinable.EntityType.ENTITY_NEUTRAL
	exam_body.add_child(examinable)

	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	if collision_size is Vector3:
		box.size = collision_size
	else:
		box.size = Vector3(default_size, default_size, 0.1)
	col_shape.shape = box
	exam_body.add_child(col_shape)

func _apply_fallback_texture(sprite: Sprite3D, entity_type: String, scale_mult: float = 1.0) -> void:
	"""Apply colored square fallback texture when no sprite texture is available.

	Args:
		sprite: Sprite3D to apply texture to
		entity_type: Entity type for color lookup
		scale_mult: Scale multiplier (default 1.0)
	"""
	var color = ENTITY_COLORS.get(entity_type, DEFAULT_ENTITY_COLOR)
	var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.pixel_size = (BILLBOARD_SIZE * scale_mult) / 16.0
	sprite.modulate = color  # Base color via modulate
	sprite.set_meta("base_color", color)

func _get_health_bar_shader() -> Shader:
	"""Get or create the shared health bar shader.

	CRITICAL: Shaders should be shared, not recreated per entity.
	Creating new Shaders causes GPU compilation and memory bloat on web/WASM.
	"""
	if _health_bar_shader == null:
		_health_bar_shader = Shader.new()
		_health_bar_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 fg_color : source_color = vec4(0.9, 0.15, 0.15, 1.0);
uniform vec4 bg_color : source_color = vec4(0.0, 0.0, 0.0, 0.9);
uniform float health : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Billboard: make quad always face camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	// UV.x goes 0.0 (left) to 1.0 (right)
	// Show foreground color where UV.x < health (left side = remaining health)
	if (UV.x < health) {
		ALBEDO = fg_color.rgb;
		ALPHA = fg_color.a;
	} else {
		ALBEDO = bg_color.rgb;
		ALPHA = bg_color.a;
	}
}
"""
	return _health_bar_shader

func _create_health_bar(entity_pos: Vector3) -> MeshInstance3D:
	"""Create a health bar using a shader for proper fill behavior.

	Uses a single quad mesh with a shader that handles the fill direction.
	This avoids scaling/positioning issues with sprite-based approaches.

	Args:
		entity_pos: World position of the entity

	Returns:
		MeshInstance3D with health bar shader
	"""
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "HealthBar"
	mesh_instance.position = entity_pos + Vector3(0, HEALTH_BAR_OFFSET_Y, 0)

	# Create quad mesh
	var quad = QuadMesh.new()
	quad.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	mesh_instance.mesh = quad

	# Use shared shader (CRITICAL: don't create new Shader per entity!)
	var material = ShaderMaterial.new()
	material.shader = _get_health_bar_shader()
	material.set_shader_parameter("fg_color", HEALTH_BAR_FG_COLOR)
	material.set_shader_parameter("bg_color", HEALTH_BAR_BG_COLOR)
	material.set_shader_parameter("health", 1.0)

	mesh_instance.material_override = material
	mesh_instance.visibility_range_end = VISIBILITY_RANGE_END

	return mesh_instance

func _update_health_bar(world_pos: Vector2i, hp_percent: float) -> void:
	"""Update health bar display for entity at position.

	Shows the health bar if entity is damaged, updates fill amount.
	Bar depletes from RIGHT to LEFT (health remaining on left side).

	Args:
		world_pos: Entity world position
		hp_percent: Health as 0.0-1.0 (1.0 = full health)
	"""
	if not entity_health_bars.has(world_pos):
		return

	var health_bar = entity_health_bars[world_pos] as MeshInstance3D
	if not health_bar:
		return

	# Show health bar only when damaged (not at full HP)
	health_bar.visible = hp_percent < 1.0

	# Update shader health parameter
	var material = health_bar.material_override as ShaderMaterial
	if material:
		material.set_shader_parameter("health", hp_percent)

# ============================================================================
# ENTITY QUERIES
# ============================================================================

func get_entity_at(world_pos: Vector2i) -> WorldEntity:
	"""Get WorldEntity at world position

	Args:
		world_pos: World tile coordinates

	Returns:
		WorldEntity or null if no entity at position
	"""
	return entity_cache.get(world_pos, null)

func has_entity_at(world_pos: Vector2i) -> bool:
	"""Check if there's a living entity at world position

	Args:
		world_pos: World tile coordinates

	Returns:
		true if entity exists and is alive (not dead)
	"""
	var entity = entity_cache.get(world_pos, null)
	return entity != null and not entity.is_dead

func get_all_entity_positions() -> Array[Vector2i]:
	"""Get world positions of all living entities

	Returns:
		Array of world tile positions with living entities (excludes dead)
	"""
	var positions: Array[Vector2i] = []
	for pos in entity_cache.keys():
		var entity = entity_cache[pos] as WorldEntity
		if entity and not entity.is_dead:
			positions.append(pos)
	return positions

func get_entities_in_range(center: Vector2i, radius: float, hostile_only: bool = true) -> Array[Vector2i]:
	"""Get living entities within radius of center position

	Args:
		center: Center world tile position
		radius: Search radius in tiles
		hostile_only: If true (default), only return hostile entities (skips vending machines, etc.)

	Returns:
		Array of entity positions within range (excludes dead entities)
	"""
	var in_range: Array[Vector2i] = []
	for pos in entity_cache.keys():
		var entity = entity_cache[pos] as WorldEntity
		if not entity or entity.is_dead:
			continue
		if hostile_only and not entity.hostile:
			continue
		var distance = center.distance_to(pos)
		if distance <= radius:
			in_range.append(pos)
	return in_range

# ============================================================================
# SIGNAL HANDLERS (WorldEntity signals)
# ============================================================================

func _on_entity_hp_changed(current_hp: float, max_hp: float, entity: WorldEntity) -> void:
	"""Handle WorldEntity hp_changed signal - update health bar

	Args:
		current_hp: New current HP
		max_hp: Maximum HP
		entity: WorldEntity reference (bound parameter, remains valid after entity moves)
	"""
	# Look up current position from reverse lookup (always current, even after move)
	var world_pos = entity_to_pos.get(entity, INVALID_POSITION)
	if world_pos == INVALID_POSITION:
		# Entity not rendered (chunk unloaded) - skip health bar update
		return

	var hp_percent = current_hp / max_hp if max_hp > 0 else 0.0
	_update_health_bar(world_pos, hp_percent)

func _on_entity_died_signal(entity: WorldEntity) -> void:
	"""Handle WorldEntity died signal - spawn death VFX and cleanup

	Args:
		entity: WorldEntity that died
	"""
	# Find entity in cache using O(1) reverse lookup
	var cache_pos = _find_entity_in_cache(entity)
	if cache_pos == INVALID_POSITION:
		# Entity not in cache - either already removed or in unloaded chunk
		return

	# Spawn death skull emoji at current position
	_spawn_death_emoji(cache_pos)

	# Emit our death signal for EXP rewards etc.
	entity_died.emit(entity)

	# Remove billboard immediately (not delayed) to prevent ghost billboards
	# The death VFX (skull emoji) floats independently, so billboard can go now
	_remove_entity_immediately(cache_pos, entity)

	# Remove dead entity from SubChunk to prevent memory leaks
	_remove_dead_entity_from_subchunk(entity)


func _remove_entity_immediately(world_pos: Vector2i, entity: WorldEntity = null) -> void:
	"""Remove entity billboard immediately (no delay)

	Args:
		world_pos: Position to remove
		entity: Optional entity reference for cleanup (avoids second lookup)
	"""
	if not entity_billboards.has(world_pos):
		return

	# Get entity if not provided
	if entity == null:
		entity = entity_cache.get(world_pos, null)

	# Remove billboard
	var billboard = entity_billboards[world_pos]
	if is_instance_valid(billboard):
		billboard.queue_free()
	entity_billboards.erase(world_pos)
	entity_cache.erase(world_pos)

	# Remove from reverse lookup
	if entity:
		entity_to_pos.erase(entity)

	# Remove health bar
	if entity_health_bars.has(world_pos):
		var health_bar = entity_health_bars[world_pos]
		if is_instance_valid(health_bar):
			health_bar.queue_free()
		entity_health_bars.erase(world_pos)

func _find_entity_in_cache(entity: WorldEntity) -> Vector2i:
	"""Find entity's position in cache using O(1) reverse lookup

	Args:
		entity: WorldEntity to find

	Returns:
		Cache position, or INVALID_POSITION if not found
	"""
	# Use O(1) reverse lookup instead of linear search
	return entity_to_pos.get(entity, INVALID_POSITION)

func _remove_dead_entity_from_subchunk(entity: WorldEntity) -> void:
	"""Remove dead entity from SubChunk storage to prevent memory leaks

	Args:
		entity: Dead entity to remove from storage
	"""
	if not grid_3d:
		return

	var chunk_manager = grid_3d.get_node_or_null("ChunkManager")
	if not chunk_manager:
		return

	var chunk = chunk_manager.get_chunk_at_tile(entity.world_position, 0)
	if not chunk:
		return

	var subchunk = chunk.get_sub_chunk_at_tile(entity.world_position)
	if subchunk:
		subchunk.remove_world_entity(entity.world_position)

# ============================================================================
# VFX SPAWNING (called by AttackExecutor and EntityAI)
# ============================================================================

func spawn_hit_vfx(world_pos: Vector2i, emoji: String, damage: float) -> void:
	"""Spawn floating hit VFX at world position

	Called by AttackExecutor when player attacks an entity, or by EntityAI
	when entities attack the player. Does NOT modify entity state.

	Args:
		world_pos: World tile position
		emoji: Emoji to display
		damage: Damage amount to show
	"""
	# Check if target is an entity billboard
	if entity_billboards.has(world_pos):
		_spawn_hit_emoji(world_pos, emoji, damage)
	else:
		# Target isn't an entity (likely the player) - spawn VFX at world position
		_spawn_hit_emoji_at_world_pos(world_pos, emoji, damage)

# ============================================================================
# BILLBOARD REMOVAL
# ============================================================================

func remove_entity_at(world_pos: Vector2i) -> bool:
	"""Remove entity billboard (when killed or despawned)

	Args:
		world_pos: World tile coordinates

	Returns:
		true if entity was found and removed
	"""
	if not entity_billboards.has(world_pos):
		return false

	# Get entity for reverse lookup cleanup
	var entity = entity_cache.get(world_pos, null)

	# Remove billboard
	var billboard = entity_billboards[world_pos]
	if is_instance_valid(billboard):
		billboard.queue_free()
	entity_billboards.erase(world_pos)
	entity_cache.erase(world_pos)

	# Remove from reverse lookup
	if entity:
		entity_to_pos.erase(entity)

	# Remove health bar
	if entity_health_bars.has(world_pos):
		var health_bar = entity_health_bars[world_pos]
		if is_instance_valid(health_bar):
			health_bar.queue_free()
		entity_health_bars.erase(world_pos)

	return true

# ============================================================================
# HIT VFX
# ============================================================================

func _spawn_hit_emoji(world_pos: Vector2i, emoji: String, damage: float = 0.0) -> void:
	"""Spawn a floating emoji with damage number that rises and fades.

	Creates a Label3D billboard with the attack emoji and damage that:
	- Starts at the entity position (with random jitter)
	- Rises upward while fading out
	- Auto-removes when animation completes
	- Font size scales with UI and camera zoom

	Args:
		world_pos: Position of entity that was hit
		emoji: Emoji character to display
		damage: Damage amount to show (0 = don't show number)
	"""
	if not entity_billboards.has(world_pos):
		return

	var sprite = entity_billboards[world_pos] as Sprite3D
	if not sprite:
		return

	# Calculate scaled font size
	var base_size = HIT_EMOJI_BASE_SIZE
	if UIScaleManager:
		base_size = UIScaleManager.get_scaled_font_size(base_size)

	# Scale with camera zoom (further out = larger emoji for visibility)
	# Navigate via grid_3d parent to find Player3D sibling
	var tactical_camera: Node = null
	var first_person_camera: Node = null
	if grid_3d:
		var game_3d = grid_3d.get_parent()
		if game_3d:
			var player = game_3d.get_node_or_null("Player3D")
			if player:
				tactical_camera = player.get_node_or_null("CameraRig")
				first_person_camera = player.get_node_or_null("FirstPersonCamera")

	# Determine scaling based on active camera
	if first_person_camera and first_person_camera.get("camera") and first_person_camera.camera.current:
		# Look mode (FPV) - scale based on FOV (60-90, lower = zoomed in)
		# Smaller than tactical since we're closer, but still readable
		# At FOV 60: 0.5x, at FOV 90: 0.75x
		var fov = first_person_camera.camera.fov
		var fov_ratio = clampf((fov - 60.0) / 30.0, 0.0, 1.0)
		var zoom_scale = lerp(0.5, 0.75, fov_ratio)
		base_size = int(base_size * zoom_scale)
	elif tactical_camera and "current_zoom" in tactical_camera:
		# Tactical view - scale based on zoom distance (8-25)
		# 10% smaller: at zoom 8 (close): 0.9x, at zoom 25 (far): 2.7x
		var zoom = tactical_camera.current_zoom
		var zoom_ratio = clampf((zoom - 8.0) / 17.0, 0.0, 1.0)
		var zoom_scale = lerp(0.9, 2.7, zoom_ratio)
		base_size = int(base_size * zoom_scale)

	# Create floating emoji label with damage number
	var label = Label3D.new()
	if damage > 0:
		label.text = "%s %.0f" % [emoji, damage]
	else:
		label.text = emoji
	label.font = _EMOJI_FONT  # Use font with emoji fallback for exports
	label.font_size = base_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true  # Always render on top
	label.modulate = Color.WHITE

	# Position slightly above the entity with random jitter
	var jitter = Vector3(
		randf_range(-HIT_EMOJI_JITTER, HIT_EMOJI_JITTER),
		0,
		randf_range(-HIT_EMOJI_JITTER, HIT_EMOJI_JITTER)
	)
	var start_pos = sprite.position + Vector3(0, 0.3, 0) + jitter
	label.position = start_pos

	add_child(label)

	# Animate rise and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	# Rise upward
	var end_pos = start_pos + Vector3(0, HIT_EMOJI_RISE_HEIGHT, 0)
	tween.tween_property(label, "position", end_pos, HIT_EMOJI_DURATION)

	# Fade out
	tween.tween_property(label, "modulate:a", 0.0, HIT_EMOJI_DURATION)

	# Remove when done
	tween.chain().tween_callback(label.queue_free)

func _spawn_hit_emoji_at_world_pos(world_pos: Vector2i, emoji: String, damage: float = 0.0) -> void:
	"""Spawn a floating emoji with damage number at a world position (not an entity).

	Used for damage VFX on the player (who doesn't have an entity billboard).

	Args:
		world_pos: Grid position to spawn VFX at
		emoji: Emoji character to display
		damage: Damage amount to show (0 = don't show number)
	"""
	# Convert grid position to 3D world position
	var world_3d: Vector3
	if grid_3d:
		world_3d = grid_3d.grid_to_world_centered(world_pos, 1.0)  # Player height
	else:
		world_3d = Vector3(world_pos.x * 2.0 + 1.0, 1.0, world_pos.y * 2.0 + 1.0)

	# Calculate scaled font size
	var base_size = HIT_EMOJI_BASE_SIZE
	if UIScaleManager:
		base_size = UIScaleManager.get_scaled_font_size(base_size)

	# Scale with camera zoom
	var tactical_camera: Node = null
	var first_person_camera: Node = null
	if grid_3d:
		var game_3d = grid_3d.get_parent()
		if game_3d:
			var player = game_3d.get_node_or_null("Player3D")
			if player:
				tactical_camera = player.get_node_or_null("CameraRig")
				first_person_camera = player.get_node_or_null("FirstPersonCamera")

	# Determine scaling based on active camera
	if first_person_camera and first_person_camera.get("camera") and first_person_camera.camera.current:
		# Look mode (FPV) - scale based on FOV (60-90, lower = zoomed in)
		# Smaller than tactical since we're closer, but still readable
		# At FOV 60: 0.5x, at FOV 90: 0.75x
		var fov = first_person_camera.camera.fov
		var fov_ratio = clampf((fov - 60.0) / 30.0, 0.0, 1.0)
		var zoom_scale = lerp(0.5, 0.75, fov_ratio)
		base_size = int(base_size * zoom_scale)
	elif tactical_camera and "current_zoom" in tactical_camera:
		var zoom = tactical_camera.current_zoom
		var zoom_ratio = clampf((zoom - 8.0) / 17.0, 0.0, 1.0)
		var zoom_scale = lerp(0.9, 2.7, zoom_ratio)
		base_size = int(base_size * zoom_scale)

	# Create floating emoji label with damage number
	var label = Label3D.new()
	if damage > 0:
		label.text = "%s %.0f" % [emoji, damage]
	else:
		label.text = emoji
	label.font = _EMOJI_FONT
	label.font_size = base_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color.WHITE

	# Position slightly above target with random jitter
	var jitter = Vector3(
		randf_range(-HIT_EMOJI_JITTER, HIT_EMOJI_JITTER),
		0,
		randf_range(-HIT_EMOJI_JITTER, HIT_EMOJI_JITTER)
	)
	var start_pos = world_3d + Vector3(0, 0.3, 0) + jitter
	label.position = start_pos

	add_child(label)

	# Animate rise and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	# Rise upward
	var end_pos = start_pos + Vector3(0, HIT_EMOJI_RISE_HEIGHT, 0)
	tween.tween_property(label, "position", end_pos, HIT_EMOJI_DURATION)

	# Fade out
	tween.tween_property(label, "modulate:a", 0.0, HIT_EMOJI_DURATION)

	# Remove when done
	tween.chain().tween_callback(label.queue_free)

func _spawn_death_emoji(world_pos: Vector2i) -> void:
	"""Spawn a skull emoji when entity dies (2x size of hit emoji).

	Args:
		world_pos: Position of entity that died
	"""
	if not entity_billboards.has(world_pos):
		return

	var sprite = entity_billboards[world_pos] as Sprite3D
	if not sprite:
		return

	# Calculate scaled font size (2x the hit emoji size)
	var base_size = HIT_EMOJI_BASE_SIZE * 2
	if UIScaleManager:
		base_size = UIScaleManager.get_scaled_font_size(base_size)

	# Scale with camera zoom (same logic as hit emoji)
	var tactical_camera: Node = null
	var first_person_camera: Node = null
	if grid_3d:
		var game_3d = grid_3d.get_parent()
		if game_3d:
			var player = game_3d.get_node_or_null("Player3D")
			if player:
				tactical_camera = player.get_node_or_null("CameraRig")
				first_person_camera = player.get_node_or_null("FirstPersonCamera")

	if first_person_camera and first_person_camera.get("camera") and first_person_camera.camera.current:
		var fov = first_person_camera.camera.fov
		var fov_ratio = clampf((fov - 60.0) / 30.0, 0.0, 1.0)
		var zoom_scale = lerp(0.5, 0.75, fov_ratio)
		base_size = int(base_size * zoom_scale)
	elif tactical_camera and "current_zoom" in tactical_camera:
		var zoom = tactical_camera.current_zoom
		var zoom_ratio = clampf((zoom - 8.0) / 17.0, 0.0, 1.0)
		var zoom_scale = lerp(1.0, 3.0, zoom_ratio)
		base_size = int(base_size * zoom_scale)

	# Create death emoji label
	var label = Label3D.new()
	label.text = "💀"
	label.font = _EMOJI_FONT  # Use font with emoji fallback for exports
	label.font_size = base_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color.WHITE

	# Position at entity (no jitter - death is centered)
	var start_pos = sprite.position + Vector3(0, 0.5, 0)
	label.position = start_pos

	add_child(label)

	# Animate rise and fade (same timing as hit emoji)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	var end_pos = start_pos + Vector3(0, HIT_EMOJI_RISE_HEIGHT * 1.5, 0)
	tween.tween_property(label, "position", end_pos, HIT_EMOJI_DURATION)
	tween.tween_property(label, "modulate:a", 0.0, HIT_EMOJI_DURATION)

	tween.chain().tween_callback(label.queue_free)


# ============================================================================
# CLEANUP
# ============================================================================

func clear_all_entities() -> void:
	"""Remove all entity billboards (called on level unload)"""
	for billboard in entity_billboards.values():
		billboard.queue_free()

	for health_bar in entity_health_bars.values():
		health_bar.queue_free()

	entity_billboards.clear()
	entity_cache.clear()
	entity_health_bars.clear()
	entity_to_pos.clear()

	Log.msg(Log.Category.ENTITY, Log.Level.INFO, "EntityRenderer: Cleared all entity billboards")

# ============================================================================
# DEBUG
# ============================================================================

func _to_string() -> String:
	return "EntityRenderer(entities=%d)" % entity_billboards.size()
