class_name ItemSpawner extends RefCounted
## Handles item spawning with corruption-based probabilities
##
## The spawner rolls for item spawns from highest to lowest rarity,
## using corruption to modify spawn chances. Items spawn in valid
## locations (3x3 clear space by default).
##
## Responsibilities:
## - Calculate spawn probabilities with corruption modifiers
## - Roll for item spawns per chunk
## - Validate spawn locations (clear space requirements)
## - Create WorldItem instances for spawned items
##
## Usage:
##   var spawner = ItemSpawner.new(corruption_tracker, level_config)
##   var spawned_items = spawner.spawn_items_for_chunk(chunk, turn_number)

# ============================================================================
# DEPENDENCIES
# ============================================================================

var corruption_tracker: CorruptionTracker
var level_config  # LevelConfig resource (defines item allowlist)

# ============================================================================
# SPAWN CONFIGURATION
# ============================================================================

## Default spawn space requirement (3x3 clear area)
const DEFAULT_CLEAR_SIZE = 3

## Discovery range (player must be within this distance to "see" item)
const DISCOVERY_RANGE = 50.0

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(p_corruption_tracker: CorruptionTracker, p_level_config) -> void:
	"""Initialize spawner with corruption tracker and level config

	Args:
		p_corruption_tracker: Global corruption tracker
		p_level_config: Level configuration (defines item allowlist)
	"""
	corruption_tracker = p_corruption_tracker
	level_config = p_level_config

	Log.system("ItemSpawner initialized for level")

# ============================================================================
# SPAWNING LOGIC
# ============================================================================

func spawn_items_for_chunk(
	chunk,  # Chunk instance
	turn_number: int,
	available_items: Array[Item]
) -> Array[WorldItem]:
	"""Spawn items in a chunk based on rarity and corruption

	Rolls from highest to lowest rarity. Each rarity tier gets one
	spawn attempt per chunk. Corruption modifies probabilities.

	Args:
		chunk: Chunk to spawn items in
		turn_number: Current turn number
		available_items: All items that could spawn (filtered by level allowlist)

	Returns:
		Array of WorldItem instances that were spawned
	"""
	var spawned_items: Array[WorldItem] = []

	# Get current corruption level for this chunk's level
	var corruption = corruption_tracker.get_corruption(chunk.level_id)

	# Roll for each rarity tier (highest to lowest)
	var rarity_order = [
		ItemRarity.Tier.DEBUG,
		ItemRarity.Tier.ANOMALY,
		ItemRarity.Tier.LEGENDARY,
		ItemRarity.Tier.EPIC,
		ItemRarity.Tier.RARE,
		ItemRarity.Tier.UNCOMMON,
		ItemRarity.Tier.COMMON
	]

	for rarity in rarity_order:
		# Get items of this rarity
		var items_of_rarity = _filter_by_rarity(available_items, rarity)
		if items_of_rarity.is_empty():
			continue

		# Calculate spawn probability for this rarity
		var base_prob = ItemRarity.get_base_probability(rarity)
		var corruption_mult = ItemRarity.get_corruption_multiplier(rarity)
		var final_prob = corruption_tracker.calculate_spawn_probability(
			base_prob,
			corruption_mult,
			corruption
		)

		# Roll for spawn
		if randf() < final_prob:
			# Choose random item of this rarity
			var item = items_of_rarity.pick_random()

			# Find valid spawn location
			var spawn_pos = _find_spawn_location(chunk, item)
			if spawn_pos != Vector2i(-1, -1):
				# Create WorldItem
				var world_item = WorldItem.new(
					item.duplicate_item(),  # Create independent copy
					spawn_pos,
					rarity,
					turn_number
				)
				spawned_items.append(world_item)

				Log.system("Spawned %s (%s) at %s (corruption: %.3f, prob: %.1f%%)" % [
					item.item_name,
					ItemRarity.RARITY_NAMES.get(rarity, "Unknown"),
					spawn_pos,
					corruption,
					final_prob * 100.0
				])
			else:
				Log.system("Failed to find spawn location for %s (%s)" % [
					item.item_name,
					ItemRarity.RARITY_NAMES.get(rarity, "Unknown")
				])

	return spawned_items

# ============================================================================
# SPAWN VALIDATION
# ============================================================================

func _find_spawn_location(chunk, item: Item) -> Vector2i:
	"""Find valid spawn location in chunk for item

	Default requirement: 3x3 clear space (non-wall tiles)
	Items can override with custom spawn requirements.

	Args:
		chunk: Chunk to search
		item: Item needing a spawn location

	Returns:
		World position (center of spawn area) or (-1, -1) if none found
	"""
	# Try up to 10 random locations
	for attempt in range(10):
		# Pick random subchunk
		var subchunk = chunk.sub_chunks.pick_random()
		if not subchunk:
			continue

		# Pick random tile in subchunk
		var local_x = randi() % subchunk.tile_data.size()
		var local_y = randi() % subchunk.tile_data[0].size()

		# Check if 3x3 area is clear (centered on this tile)
		var center_world_pos = subchunk.world_position + Vector2i(local_x, local_y)
		if _is_area_clear(chunk, center_world_pos, DEFAULT_CLEAR_SIZE):
			return center_world_pos

	# Failed to find valid location
	return Vector2i(-1, -1)

func _is_area_clear(chunk, center: Vector2i, size: int) -> bool:
	"""Check if NxN area around center is clear (non-wall)

	Args:
		chunk: Chunk to check
		center: Center tile position
		size: Area size (e.g., 3 for 3x3)

	Returns:
		true if all tiles in area are non-wall
	"""
	var half = size / 2

	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var check_pos = center + Vector2i(dx, dy)

			# Get tile at position
			var tile = _get_tile_at_world_pos(chunk, check_pos)

			# Wall tiles have IDs >= 1 (0 = floor)
			if tile == null or tile >= 1:
				return false

	return true

func _get_tile_at_world_pos(chunk, world_pos: Vector2i):
	"""Get tile ID at world position within chunk

	Args:
		chunk: Chunk to search
		world_pos: World tile coordinates

	Returns:
		Tile ID or null if out of bounds
	"""
	# Find subchunk containing this position
	for subchunk in chunk.sub_chunks:
		var local_x = world_pos.x - subchunk.world_position.x
		var local_y = world_pos.y - subchunk.world_position.y

		# Check if position is in this subchunk
		if local_x >= 0 and local_x < subchunk.tile_data.size():
			if local_y >= 0 and local_y < subchunk.tile_data[0].size():
				return subchunk.tile_data[local_x][local_y]

	return null

# ============================================================================
# UTILITY
# ============================================================================

func _filter_by_rarity(items: Array[Item], rarity: ItemRarity.Tier) -> Array[Item]:
	"""Filter items by rarity tier

	Args:
		items: All available items
		rarity: Rarity tier to filter for

	Returns:
		Items matching the rarity tier
	"""
	var filtered: Array[Item] = []
	for item in items:
		if item.rarity == rarity:
			filtered.append(item)
	return filtered
