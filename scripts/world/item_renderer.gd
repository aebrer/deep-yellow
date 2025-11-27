class_name ItemRenderer extends Node3D
## Renders items as 3D billboards in the world
##
## Creates and manages Billboard3D nodes for items that exist in loaded chunks.
## Items are always visible (discovery only affects minimap).
## Billboards are created when chunks load and destroyed when chunks unload.
##
## Responsibilities:
## - Create Billboard3D for each item in loaded chunks
## - Position billboards at item world positions
## - Remove billboards when items are picked up
## - Cleanup billboards when chunks unload
## - Provide query methods for pickup interaction
##
## Usage:
##   var renderer = ItemRenderer.new()
##   renderer.render_chunk_items(chunk)  # On chunk load
##   renderer.unload_chunk_items(chunk)  # On chunk unload
##   var item = renderer.get_item_at(player_pos)  # For pickup

# ============================================================================
# DEPENDENCIES
# ============================================================================

@onready var grid_3d: Grid3D = get_parent()

# ============================================================================
# STATE
# ============================================================================

## Maps world tile position to Sprite3D node
var item_billboards: Dictionary = {}  # Vector2i -> Sprite3D

## Maps world tile position to serialized item data
var item_data_cache: Dictionary = {}  # Vector2i -> Dictionary

# ============================================================================
# CONFIGURATION
# ============================================================================

## Billboard size (world units)
const BILLBOARD_SIZE = 0.5

## Billboard height above floor (world units)
## Matches player Y position (1.0) so items float at same height
const BILLBOARD_HEIGHT = 1.0

## Placeholder colors by rarity (until we have sprites)
const RARITY_COLORS = {
	ItemRarity.Tier.DEBUG: Color(1.0, 0.0, 1.0),       # Magenta
	ItemRarity.Tier.COMMON: Color(0.8, 0.8, 0.8),      # Light gray
	ItemRarity.Tier.UNCOMMON: Color(0.3, 1.0, 0.3),    # Green
	ItemRarity.Tier.RARE: Color(0.3, 0.5, 1.0),        # Blue
	ItemRarity.Tier.EPIC: Color(0.8, 0.3, 1.0),        # Purple
	ItemRarity.Tier.LEGENDARY: Color(1.0, 0.6, 0.0),   # Orange
	ItemRarity.Tier.ANOMALY: Color(1.0, 0.2, 0.2)      # Red
}

# ============================================================================
# CHUNK LOADING
# ============================================================================

func render_chunk_items(chunk: Chunk) -> void:
	"""Create billboards for all items in chunk

	Args:
		chunk: Chunk that was just loaded
	"""
	for subchunk in chunk.sub_chunks:
		for item_data in subchunk.world_items:
			# Skip if already picked up
			if item_data.get("picked_up", false):
				continue

			# Get world position
			var pos_data = item_data.get("world_position", {"x": 0, "y": 0})
			var world_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

			# Skip if billboard already exists (shouldn't happen, but safety check)
			if item_billboards.has(world_pos):
				continue

			# Create billboard
			var billboard = _create_billboard(item_data, world_pos)
			if billboard:
				add_child(billboard)
				item_billboards[world_pos] = billboard
				item_data_cache[world_pos] = item_data

	Log.grid("ItemRenderer: Created %d item billboards for chunk at %s" % [
		chunk.sub_chunks.map(func(s): return s.world_items.size()).reduce(func(a, b): return a + b, 0),
		chunk.position
	])

func unload_chunk_items(chunk: Chunk) -> void:
	"""Remove billboards for all items in chunk

	Args:
		chunk: Chunk being unloaded
	"""
	var removed_count = 0

	for subchunk in chunk.sub_chunks:
		for item_data in subchunk.world_items:
			var pos_data = item_data.get("world_position", {"x": 0, "y": 0})
			var world_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

			if item_billboards.has(world_pos):
				var billboard = item_billboards[world_pos]
				billboard.queue_free()
				item_billboards.erase(world_pos)
				item_data_cache.erase(world_pos)
				removed_count += 1

	Log.grid("ItemRenderer: Removed %d item billboards for chunk at %s" % [
		removed_count,
		chunk.position
	])

# ============================================================================
# BILLBOARD CREATION
# ============================================================================

func _create_billboard(item_data: Dictionary, world_pos: Vector2i) -> Sprite3D:
	"""Create a Sprite3D billboard for an item

	Args:
		item_data: Serialized WorldItem data
		world_pos: World tile position

	Returns:
		Sprite3D node or null if creation failed
	"""
	# Look up the Item resource by item_id
	var item_id = item_data.get("item_id", "")
	var item_resource = _get_item_by_id(item_id)

	if not item_resource:
		Log.warn(Log.Category.GRID, "Failed to find item resource for ID: %s" % item_id)
		return null

	# Create sprite node
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # Pixel art friendly

	# Position at world coordinates (centered in cell)
	var world_3d = grid_3d.grid_to_world_centered(world_pos, BILLBOARD_HEIGHT) if grid_3d else Vector3(
		world_pos.x * 2.0 + 1.0,  # Fallback if no grid
		BILLBOARD_HEIGHT,
		world_pos.y * 2.0 + 1.0
	)
	sprite.position = world_3d

	# Use the item's ground sprite
	if item_resource.ground_sprite:
		sprite.texture = item_resource.ground_sprite
		# Calculate pixel_size based on texture dimensions
		var texture_size = item_resource.ground_sprite.get_size()
		sprite.pixel_size = BILLBOARD_SIZE / max(texture_size.x, texture_size.y)
	else:
		# Fallback: colored square if no sprite defined
		var rarity = item_data.get("rarity", ItemRarity.Tier.COMMON)
		var color = RARITY_COLORS.get(rarity, Color.WHITE)
		var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(color)
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.pixel_size = BILLBOARD_SIZE / 16.0

	# Add examination support (same pattern as floor tiles)
	var exam_body = StaticBody3D.new()
	exam_body.name = "ExamBody"
	exam_body.collision_layer = 8  # Layer 4 for raycast detection
	exam_body.collision_mask = 0   # Doesn't collide with anything
	sprite.add_child(exam_body)

	# Add Examinable component as child of StaticBody3D
	var examinable = Examinable.new()
	examinable.entity_id = item_resource.item_id
	examinable.entity_type = Examinable.EntityType.ITEM
	exam_body.add_child(examinable)

	# Add collision shape to StaticBody3D (not to Examinable)
	var collision_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(BILLBOARD_SIZE, BILLBOARD_SIZE, 0.1)
	collision_shape.shape = box
	exam_body.add_child(collision_shape)

	return sprite

# ============================================================================
# ITEM PICKUP
# ============================================================================

func get_item_at(world_pos: Vector2i) -> Dictionary:
	"""Get item data at world position (for pickup interaction)

	Args:
		world_pos: World tile coordinates

	Returns:
		Serialized item data or empty dict if no item at position
	"""
	return item_data_cache.get(world_pos, {})

func remove_item_at(world_pos: Vector2i) -> bool:
	"""Remove item billboard when picked up

	This is called after the player confirms pickup.
	The SubChunk data should be updated separately by the pickup system.

	Args:
		world_pos: World tile coordinates

	Returns:
		true if item was found and removed
	"""
	if not item_billboards.has(world_pos):
		return false

	# Remove billboard
	var billboard = item_billboards[world_pos]
	billboard.queue_free()
	item_billboards.erase(world_pos)
	item_data_cache.erase(world_pos)

	Log.system("Removed item billboard at %s" % world_pos)
	return true

# ============================================================================
# QUERIES
# ============================================================================

func has_item_at(world_pos: Vector2i) -> bool:
	"""Check if there's an item at world position

	Args:
		world_pos: World tile coordinates

	Returns:
		true if item exists and is not picked up
	"""
	return item_billboards.has(world_pos)

func get_all_item_positions() -> Array[Vector2i]:
	"""Get world positions of all rendered items

	Returns:
		Array of world tile positions with items
	"""
	var positions: Array[Vector2i] = []
	for pos in item_billboards.keys():
		positions.append(pos)
	return positions

func get_discovered_item_positions() -> Array[Vector2i]:
	"""Get world positions of discovered items (for minimap)

	Returns:
		Array of world tile positions where items have been discovered
	"""
	var positions: Array[Vector2i] = []
	for pos in item_data_cache.keys():
		var item_data = item_data_cache[pos]
		if item_data.get("discovered", false):
			positions.append(pos)
	return positions

# ============================================================================
# ITEM LOOKUP
# ============================================================================

func _get_item_by_id(item_id: String) -> Item:
	"""Look up Item resource by item_id from level config

	Args:
		item_id: Unique item identifier (e.g., "debug_item")

	Returns:
		Item resource or null if not found
	"""
	if not grid_3d or not grid_3d.current_level:
		return null

	# Search through permitted items in level config
	for item in grid_3d.current_level.permitted_items:
		if item.item_id == item_id:
			return item

	return null

# ============================================================================
# CLEANUP
# ============================================================================

func clear_all_items() -> void:
	"""Remove all item billboards (called on level unload)"""
	for billboard in item_billboards.values():
		billboard.queue_free()

	item_billboards.clear()
	item_data_cache.clear()

	Log.system("ItemRenderer: Cleared all item billboards")

# ============================================================================
# DEBUG
# ============================================================================

func _to_string() -> String:
	return "ItemRenderer(items=%d)" % item_billboards.size()
