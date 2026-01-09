class_name EntityRenderer extends Node3D
## Renders entities as 3D billboards in the world
##
## Creates and manages Billboard3D nodes for entities that exist in loaded chunks.
## Billboards are created when chunks load and destroyed when chunks unload.
## Entity data persists in SubChunk.world_entities for chunk reload.
##
## Follows same pattern as ItemRenderer for consistency.
##
## Responsibilities:
## - Create Billboard3D for each entity in loaded chunks
## - Position billboards at entity world positions
## - Remove billboards when entities die
## - Cleanup billboards when chunks unload
## - Sync entity HP/state with WorldEntity data

# ============================================================================
# DEPENDENCIES
# ============================================================================

@onready var grid_3d: Grid3D = get_parent()

# ============================================================================
# STATE
# ============================================================================

## Maps world tile position to Sprite3D node
var entity_billboards: Dictionary = {}  # Vector2i -> Sprite3D

## Maps world tile position to WorldEntity data (for state sync)
var entity_data_cache: Dictionary = {}  # Vector2i -> Dictionary

## Currently highlighted entity positions (for attack preview)
var _highlighted_positions: Array[Vector2i] = []

# ============================================================================
# CONFIGURATION
# ============================================================================

## Billboard size (world units)
const BILLBOARD_SIZE = 0.5

## Billboard height above floor (world units)
## Matches player Y position (1.0) so entities float at same height
const BILLBOARD_HEIGHT = 1.0

## Entity type colors (until we have sprites)
const ENTITY_COLORS = {
	"debug_enemy": Color(1.0, 0.0, 1.0),       # Magenta
	"bacteria_spawn": Color(0.5, 1.0, 0.5),    # Light green
	"bacteria_brood_mother": Color(0.0, 0.8, 0.0),  # Dark green
}

## Default entity color
const DEFAULT_ENTITY_COLOR = Color(1.0, 0.0, 0.0)  # Red

## Highlight color for attack targets (red glow)
const ATTACK_TARGET_HIGHLIGHT = Color(1.0, 0.4, 0.4)  # Bright red tint

# ============================================================================
# CHUNK LOADING
# ============================================================================

func render_chunk_entities(chunk: Chunk) -> void:
	"""Create billboards for all entities in chunk

	Args:
		chunk: Chunk that was just loaded
	"""
	for subchunk in chunk.sub_chunks:
		for entity_data in subchunk.world_entities:
			# Skip if dead
			if entity_data.get("is_dead", false):
				continue

			# Get world position
			var pos_data = entity_data.get("world_position", {"x": 0, "y": 0})
			var world_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

			# Skip if billboard already exists (shouldn't happen, but safety check)
			if entity_billboards.has(world_pos):
				continue

			# Create billboard
			var billboard = _create_billboard(entity_data, world_pos)
			if billboard:
				add_child(billboard)
				entity_billboards[world_pos] = billboard
				entity_data_cache[world_pos] = entity_data

	var entity_count = chunk.sub_chunks.map(func(s): return s.world_entities.size()).reduce(func(a, b): return a + b, 0)
	if entity_count > 0:
		Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "EntityRenderer: Created %d entity billboards for chunk at %s" % [
			entity_count,
			chunk.position
		])

func unload_chunk_entities(chunk: Chunk) -> void:
	"""Remove billboards for all entities in chunk

	Args:
		chunk: Chunk being unloaded
	"""
	var removed_count = 0

	for subchunk in chunk.sub_chunks:
		for entity_data in subchunk.world_entities:
			var pos_data = entity_data.get("world_position", {"x": 0, "y": 0})
			var world_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

			if entity_billboards.has(world_pos):
				var billboard = entity_billboards[world_pos]
				billboard.queue_free()
				entity_billboards.erase(world_pos)
				entity_data_cache.erase(world_pos)
				removed_count += 1

	if removed_count > 0:
		Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "EntityRenderer: Removed %d entity billboards for chunk at %s" % [
			removed_count,
			chunk.position
		])

# ============================================================================
# BILLBOARD CREATION
# ============================================================================

func _create_billboard(entity_data: Dictionary, world_pos: Vector2i) -> Sprite3D:
	"""Create a Sprite3D billboard for an entity

	Args:
		entity_data: Serialized WorldEntity data
		world_pos: World tile position

	Returns:
		Sprite3D node or null if creation failed
	"""
	var entity_type = entity_data.get("entity_type", "unknown")

	# Create sprite node
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # Pixel art friendly
	sprite.shaded = true  # Match debug_enemy.tscn setting
	sprite.alpha_cut = Sprite3D.ALPHA_CUT_OPAQUE_PREPASS

	# Position at world coordinates (centered in cell)
	var world_3d = grid_3d.grid_to_world_centered(world_pos, BILLBOARD_HEIGHT) if grid_3d else Vector3(
		world_pos.x * 2.0 + 1.0,  # Fallback if no grid
		BILLBOARD_HEIGHT,
		world_pos.y * 2.0 + 1.0
	)
	sprite.position = world_3d

	# Create placeholder white square and use modulate for color
	# This allows us to change modulate for highlighting effects
	var color = ENTITY_COLORS.get(entity_type, DEFAULT_ENTITY_COLOR)
	var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.pixel_size = BILLBOARD_SIZE / 16.0
	sprite.modulate = color  # Base color via modulate (can be changed for highlights)

	# Store original color for highlight restoration
	sprite.set_meta("base_color", color)

	# Store entity position for collision queries
	sprite.set_meta("grid_position", world_pos)
	sprite.set_meta("entity_type", entity_type)

	# Add examination support (same pattern as ItemRenderer)
	var exam_body = StaticBody3D.new()
	exam_body.name = "ExamBody"
	exam_body.collision_layer = 8  # Layer 4 for raycast detection
	exam_body.collision_mask = 0   # Doesn't collide with anything
	sprite.add_child(exam_body)

	# Add Examinable component as child of StaticBody3D
	var examinable = Examinable.new()
	examinable.entity_id = entity_type  # e.g., "debug_enemy"
	examinable.entity_type = Examinable.EntityType.ENTITY_HOSTILE  # Default to hostile for enemies
	exam_body.add_child(examinable)

	# Add collision shape to StaticBody3D
	var collision_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(BILLBOARD_SIZE, BILLBOARD_SIZE, 0.1)
	collision_shape.shape = box
	exam_body.add_child(collision_shape)

	return sprite

# ============================================================================
# ENTITY QUERIES
# ============================================================================

func get_entity_at(world_pos: Vector2i) -> Dictionary:
	"""Get entity data at world position

	Args:
		world_pos: World tile coordinates

	Returns:
		Serialized entity data or empty dict if no entity at position
	"""
	return entity_data_cache.get(world_pos, {})

func has_entity_at(world_pos: Vector2i) -> bool:
	"""Check if there's a living entity at world position

	Args:
		world_pos: World tile coordinates

	Returns:
		true if entity exists and is alive
	"""
	return entity_billboards.has(world_pos)

func get_all_entity_positions() -> Array[Vector2i]:
	"""Get world positions of all rendered entities

	Returns:
		Array of world tile positions with entities
	"""
	var positions: Array[Vector2i] = []
	for pos in entity_billboards.keys():
		positions.append(pos)
	return positions

func get_entities_in_range(center: Vector2i, radius: float) -> Array[Vector2i]:
	"""Get entities within radius of center position

	Args:
		center: Center world tile position
		radius: Search radius in tiles

	Returns:
		Array of entity positions within range
	"""
	var in_range: Array[Vector2i] = []
	for pos in entity_billboards.keys():
		var distance = center.distance_to(pos)
		if distance <= radius:
			in_range.append(pos)
	return in_range

# ============================================================================
# ENTITY STATE UPDATES
# ============================================================================

func damage_entity_at(world_pos: Vector2i, amount: float) -> bool:
	"""Apply damage to entity at position

	Args:
		world_pos: World tile position
		amount: Damage amount

	Returns:
		true if entity was found and damaged
	"""
	if not entity_data_cache.has(world_pos):
		return false

	var entity_data = entity_data_cache[world_pos]
	var current_hp = entity_data.get("current_hp", 0.0)
	var new_hp = max(0.0, current_hp - amount)
	entity_data["current_hp"] = new_hp

	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Entity at %s took %.1f damage (%.1f/%.1f HP)" % [
		world_pos,
		amount,
		new_hp,
		entity_data.get("max_hp", 0.0)
	])

	# Check for death
	if new_hp <= 0:
		entity_data["is_dead"] = true
		remove_entity_at(world_pos)
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "Entity at %s died" % world_pos)

	return true

func remove_entity_at(world_pos: Vector2i) -> bool:
	"""Remove entity billboard (when killed or despawned)

	Args:
		world_pos: World tile coordinates

	Returns:
		true if entity was found and removed
	"""
	if not entity_billboards.has(world_pos):
		return false

	# Remove billboard
	var billboard = entity_billboards[world_pos]
	billboard.queue_free()
	entity_billboards.erase(world_pos)
	entity_data_cache.erase(world_pos)

	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Removed entity billboard at %s" % world_pos)
	return true

# ============================================================================
# ATTACK TARGET HIGHLIGHTING
# ============================================================================

func highlight_attack_targets(target_positions: Array) -> void:
	"""Highlight entities that will be attacked next turn.

	Clears previous highlights and applies new ones.
	Used by action preview to show what WILL happen.

	Args:
		target_positions: Array of Vector2i positions to highlight
	"""
	# Clear previous highlights first
	clear_attack_highlights()

	# Apply new highlights
	for pos in target_positions:
		if not pos is Vector2i:
			continue

		var world_pos = pos as Vector2i
		if entity_billboards.has(world_pos):
			var sprite = entity_billboards[world_pos] as Sprite3D
			if sprite:
				sprite.modulate = ATTACK_TARGET_HIGHLIGHT
				_highlighted_positions.append(world_pos)

func clear_attack_highlights() -> void:
	"""Clear all attack target highlights, restoring original colors."""
	for world_pos in _highlighted_positions:
		if entity_billboards.has(world_pos):
			var sprite = entity_billboards[world_pos] as Sprite3D
			if sprite:
				var base_color = sprite.get_meta("base_color", Color.WHITE)
				sprite.modulate = base_color  # Restore original color

	_highlighted_positions.clear()

# ============================================================================
# CLEANUP
# ============================================================================

func clear_all_entities() -> void:
	"""Remove all entity billboards (called on level unload)"""
	for billboard in entity_billboards.values():
		billboard.queue_free()

	entity_billboards.clear()
	entity_data_cache.clear()

	Log.msg(Log.Category.ENTITY, Log.Level.INFO, "EntityRenderer: Cleared all entity billboards")

# ============================================================================
# DEBUG
# ============================================================================

func _to_string() -> String:
	return "EntityRenderer(entities=%d)" % entity_billboards.size()
