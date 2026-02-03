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
##   var spawner = ItemSpawner.new(corruption_tracker)
##   var spawned_items = spawner.spawn_items_for_chunk(chunk, turn_number, items)

# ============================================================================
# DEPENDENCIES
# ============================================================================

var corruption_tracker: CorruptionTracker

# ============================================================================
# SPAWN CONFIGURATION
# ============================================================================

## Default spawn space requirement (3x3 clear area)
const DEFAULT_CLEAR_SIZE = 3

## Corruption per bonus item level (at 0.25 corruption → +1 level)
## At corruption 1.0 → level 5, corruption 2.0 → level 9
const CORRUPTION_PER_LEVEL_STEP = 0.25

## Discovery range (player must be within this distance to "see" item)
const DISCOVERY_RANGE = 50.0

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(p_corruption_tracker: CorruptionTracker) -> void:
	"""Initialize spawner with corruption tracker

	Args:
		p_corruption_tracker: Global corruption tracker
	"""
	corruption_tracker = p_corruption_tracker


# ============================================================================
# SPAWNING LOGIC
# ============================================================================

func spawn_items_for_chunk(
	chunk,  # Chunk instance
	turn_number: int,
	available_items: Array[Item],
	player = null  # Optional: Player3D reference for item spawn rate bonuses
) -> Array[WorldItem]:
	"""Spawn items in a chunk based on rarity and corruption

	Rolls from highest to lowest rarity. Each rarity tier gets one
	spawn attempt per chunk. Corruption modifies probabilities.

	Args:
		chunk: Chunk to spawn items in
		turn_number: Current turn number
		available_items: All items that could spawn (filtered by level allowlist)
		player: Optional player reference for spawn rate bonuses from equipped items

	Returns:
		Array of WorldItem instances that were spawned
	"""
	var spawned_items: Array[WorldItem] = []

	# Get current corruption level for this chunk's level
	var corruption = corruption_tracker.get_corruption(chunk.level_id)

	# Get item spawn rate bonus from player's equipped items
	var spawn_rate_bonus = _get_player_spawn_rate_bonus(player)

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

		# Apply item spawn rate bonus from equipped items (additive)
		final_prob = final_prob + spawn_rate_bonus

		# Roll for spawn
		if randf() < final_prob:
			# Choose random item of this rarity
			var item = items_of_rarity.pick_random()

			# Find valid spawn location
			var spawn_pos = _find_spawn_location(chunk, item)
			if spawn_pos != Vector2i(-1, -1):
				# Create WorldItem with corruption-scaled level
				var duped_item = item.duplicate_item()
				var item_level = _roll_item_level(corruption)
				if item_level > 1:
					duped_item.level = item_level
					Log.grid("Item %s spawned at level %d (corruption %.2f)" % [duped_item.item_name, item_level, corruption])

				var world_item = WorldItem.new(
					duped_item,
					spawn_pos,
					rarity,
					turn_number
				)
				spawned_items.append(world_item)

	# Bonus corrupted item spawns (extra on top of normal spawns)
	# Gated by corruption chance: 1.0 - exp(-corruption * 0.5)
	if corruption > 0.0:
		var corrupt_chance = 1.0 - exp(-corruption * 0.5)
		if randf() < corrupt_chance and not available_items.is_empty():
			var bonus_item = available_items.pick_random()
			var spawn_pos = _find_spawn_location(chunk, bonus_item)
			if spawn_pos != Vector2i(-1, -1):
				var duped = bonus_item.duplicate_item()
				duped.level = _roll_item_level(corruption)
				duped.corrupted = true
				duped.starts_enabled = false
				duped.corruption_debuffs.append(CorruptionDebuffs.roll_debuff())
				Log.grid("BONUS corrupted %s spawned (chance was %.1f%%)" % [duped.item_name, corrupt_chance * 100.0])
				spawned_items.append(WorldItem.new(duped, spawn_pos, bonus_item.rarity, turn_number))

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

		# Skip empty tile data
		if subchunk.tile_data.is_empty() or subchunk.tile_data[0].is_empty():
			continue

		# Pick random tile in subchunk
		var local_y = randi() % subchunk.tile_data.size()
		var local_x = randi() % subchunk.tile_data[0].size()

		# Check if 3x3 area is clear (centered on this tile)
		var center_world_pos = subchunk.world_position + Vector2i(local_x, local_y)
		if _is_area_clear(chunk, center_world_pos, DEFAULT_CLEAR_SIZE):
			return center_world_pos

	# Failed to find valid location
	return Vector2i(-1, -1)

func _is_area_clear(chunk, center: Vector2i, size: int, occupied_positions: Array[Vector2i] = []) -> bool:
	"""Check if NxN area around center is clear (non-wall, no items)

	Args:
		chunk: Chunk to check
		center: Center tile position
		size: Area size (e.g., 3 for 3x3)
		occupied_positions: Additional positions to treat as occupied (for batch spawning)

	Returns:
		true if all tiles in area are non-wall and no items present
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

	# Check for existing items in chunk's subchunks
	for subchunk in chunk.sub_chunks:
		for item_data in subchunk.world_items:
			var pos_data = item_data.get("world_position", {})
			var item_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))
			# Check if item is within the spawn area
			if abs(item_pos.x - center.x) <= half and abs(item_pos.y - center.y) <= half:
				return false

	# Check additional occupied positions (used during batch spawning)
	for occupied_pos in occupied_positions:
		if abs(occupied_pos.x - center.x) <= half and abs(occupied_pos.y - center.y) <= half:
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

		# Skip empty tile data
		if subchunk.tile_data.is_empty():
			continue

		# Check if position is in this subchunk
		# CRITICAL: tile_data is stored as [y][x] (row-major), not [x][y]
		if local_y >= 0 and local_y < subchunk.tile_data.size():
			if subchunk.tile_data[local_y].is_empty():
				continue
			if local_x >= 0 and local_x < subchunk.tile_data[local_y].size():
				return subchunk.tile_data[local_y][local_x]

	return null

# ============================================================================
# PLAYER MODIFIERS
# ============================================================================

func _get_player_spawn_rate_bonus(player) -> float:
	"""Calculate total item spawn rate bonus from player's equipped items.

	Args:
		player: Player3D reference (or null)

	Returns:
		Total additive spawn rate bonus (e.g., 0.1 = +10% to spawn probability)
	"""
	if not player:
		return 0.0

	var total_bonus: float = 0.0
	var pools = [player.body_pool, player.mind_pool, player.null_pool]

	for pool in pools:
		if not pool:
			continue
		for i in range(pool.max_slots):
			var item = pool.items[i]
			var is_enabled = pool.enabled[i]
			if item and is_enabled:
				var mods = item.get_passive_modifiers()
				total_bonus += mods.get("item_spawn_rate_add", 0.0)

	return total_bonus


# ============================================================================
# UTILITY
# ============================================================================

func _maybe_corrupt_item(item: Item, corruption: float) -> void:
	"""Roll for corruption on a spawned item.

	Corruption chance: 1.0 - exp(-corruption * 0.5)
	~39% at corruption 1.0, ~63% at 2.0, ~0% at 0.0

	If corrupted, rolls a random debuff and sets starts_enabled to false.
	"""
	if corruption <= 0.0:
		return

	var corrupt_chance = 1.0 - exp(-corruption * 0.5)
	if randf() < corrupt_chance:
		item.corrupted = true
		item.starts_enabled = false
		item.corruption_debuffs.append(CorruptionDebuffs.roll_debuff())
		Log.grid("Item %s CORRUPTED (chance was %.1f%%)" % [item.item_name, corrupt_chance * 100.0])

func _roll_item_level(corruption: float) -> int:
	"""Roll item level based on corruption.

	Each CORRUPTION_PER_LEVEL_STEP (0.25) of corruption gives one guaranteed
	bonus level. The fractional remainder is a probability roll for +1 more.

	Examples (CORRUPTION_PER_LEVEL_STEP = 0.25):
	  corruption 0.0   → level 1 (always)
	  corruption 0.1   → level 1 (60%) or 2 (40%)
	  corruption 0.25  → level 2 (always)
	  corruption 0.5   → level 3 (always)
	  corruption 1.0   → level 5 (always)
	  corruption 2.0   → level 9 (always)

	Returns:
		Item level (1+)
	"""
	if corruption <= 0.0:
		return 1

	var steps = corruption / CORRUPTION_PER_LEVEL_STEP
	var guaranteed = int(steps)
	var remainder = steps - guaranteed

	# Roll for fractional step
	if randf() < remainder:
		guaranteed += 1

	return 1 + guaranteed

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


# ============================================================================
# DEBUG SPAWNING
# ============================================================================

func spawn_all_items_for_debug(
	chunk,
	turn_number: int,
	available_items: Array[Item]
) -> Array[WorldItem]:
	"""Spawn one of each item in the chunk (DEBUG MODE ONLY)

	Used when Utilities.DEBUG_SPAWN_ALL_ITEMS is true.
	Spawns all available items in a grid pattern near chunk center.

	Args:
		chunk: Chunk to spawn items in
		turn_number: Current turn number
		available_items: All items to spawn

	Returns:
		Array of WorldItem instances that were spawned
	"""
	var spawned_items: Array[WorldItem] = []

	if available_items.is_empty():
		return spawned_items

	Log.system("[DEBUG] Spawning ALL %d items in first chunk" % available_items.size())

	# Find a valid starting position (center-ish of first subchunk)
	var start_pos = Vector2i(-1, -1)
	if chunk.sub_chunks.size() > 0:
		var subchunk = chunk.sub_chunks[0]
		# Start near the middle of the subchunk
		var center_x = subchunk.tile_data[0].size() / 2
		var center_y = subchunk.tile_data.size() / 2
		start_pos = subchunk.world_position + Vector2i(center_x, center_y)

	if start_pos == Vector2i(-1, -1):
		Log.system("[DEBUG] Could not find starting position for debug items")
		return spawned_items

	# Track positions already used during this spawn pass
	var occupied_positions: Array[Vector2i] = []

	# Spawn items in a grid pattern (spacing of 4 tiles)
	var spacing = 4
	var items_per_row = ceili(sqrt(available_items.size()))
	var item_index = 0

	for item in available_items:
		var grid_x = item_index % items_per_row
		var grid_y = item_index / items_per_row
		var spawn_pos = start_pos + Vector2i(grid_x * spacing, grid_y * spacing)

		# Try to find a valid location near the target (passing already-occupied positions)
		var valid_pos = _find_nearby_valid_location(chunk, spawn_pos, 20, occupied_positions)
		if valid_pos != Vector2i(-1, -1):
			var world_item = WorldItem.new(
				item.duplicate_item(),
				valid_pos,
				item.rarity,
				turn_number
			)
			spawned_items.append(world_item)
			occupied_positions.append(valid_pos)  # Mark this position as occupied
			Log.system("[DEBUG] Spawned %s at %s" % [item.item_name, valid_pos])
		else:
			Log.system("[DEBUG] Failed to spawn %s - no valid location" % item.item_name)

		item_index += 1

	return spawned_items


func spawn_forced_item(
	chunk,
	turn_number: int,
	available_items: Array[Item],
	player = null
) -> WorldItem:
	"""Force spawn a single item (pity timer triggered).

	CRITICAL: This MUST use the EXACT SAME rarity probabilities as natural spawns!
	DO NOT filter to common-only or modify the rarity distribution in any way.
	The pity timer guarantees A spawn happens, but the rarity should still be
	rolled using the same corruption-modified probabilities as normal spawns.

	This avoids the memory overhead of calling spawn_items_for_chunk()
	repeatedly (which creates many temporary arrays and deep-copied Resources).

	Args:
		chunk: Chunk to spawn item in
		turn_number: Current turn number
		available_items: All items that could spawn
		player: Optional player reference for spawn rate bonuses

	Returns:
		WorldItem if spawned successfully, null otherwise
	"""
	if available_items.is_empty():
		return null

	# Get current corruption level for this chunk's level
	var corruption = corruption_tracker.get_corruption(chunk.level_id)

	# Roll for rarity using the SAME probabilities as natural spawns
	# (corruption-modified base probabilities, highest to lowest)
	var rarity_order = [
		ItemRarity.Tier.DEBUG,
		ItemRarity.Tier.ANOMALY,
		ItemRarity.Tier.LEGENDARY,
		ItemRarity.Tier.EPIC,
		ItemRarity.Tier.RARE,
		ItemRarity.Tier.UNCOMMON,
		ItemRarity.Tier.COMMON
	]

	var selected_rarity: ItemRarity.Tier = ItemRarity.Tier.COMMON  # Fallback
	var selected_items: Array[Item] = []

	# Get item spawn rate bonus from player's equipped items
	var spawn_rate_bonus = _get_player_spawn_rate_bonus(player)

	# Build weighted pool based on rarity probabilities (same as natural spawns)
	# Each rarity's weight = its corruption-modified spawn probability
	var weighted_pool: Array[Dictionary] = []  # [{item: Item, weight: float}, ...]
	var total_weight: float = 0.0

	for rarity in rarity_order:
		var items_of_rarity = _filter_by_rarity(available_items, rarity)
		if items_of_rarity.is_empty():
			continue

		# Calculate spawn probability for this rarity (SAME formula as natural spawns)
		var base_prob = ItemRarity.get_base_probability(rarity)
		var corruption_mult = ItemRarity.get_corruption_multiplier(rarity)
		var rarity_weight = corruption_tracker.calculate_spawn_probability(
			base_prob,
			corruption_mult,
			corruption
		)

		# Apply item spawn rate bonus from equipped items (additive)
		rarity_weight = rarity_weight + spawn_rate_bonus

		# Add all items of this rarity with equal share of the rarity's weight
		var per_item_weight = rarity_weight / items_of_rarity.size()
		for item in items_of_rarity:
			weighted_pool.append({"item": item, "weight": per_item_weight})
			total_weight += per_item_weight

	# Weighted random selection - pity timer guarantees something spawns
	if total_weight > 0:
		var roll = randf() * total_weight
		var cumulative: float = 0.0
		for entry in weighted_pool:
			cumulative += entry.weight
			if roll <= cumulative:
				selected_items = [entry.item]
				selected_rarity = entry.item.rarity
				break

	if selected_items.is_empty():
		return null

	# Pick a random item from the selected rarity pool
	var item = selected_items.pick_random()

	# Find spawn location (only try once - if chunk has no valid spots, fail gracefully)
	var spawn_pos = _find_spawn_location(chunk, item)
	if spawn_pos == Vector2i(-1, -1):
		return null

	# Create the WorldItem with corruption-scaled level
	var duped_item = item.duplicate_item()
	var item_level = _roll_item_level(corruption)
	if item_level > 1:
		duped_item.level = item_level
		Log.grid("Forced spawn %s at level %d (corruption %.2f)" % [duped_item.item_name, item_level, corruption])

	return WorldItem.new(
		duped_item,
		spawn_pos,
		selected_rarity,
		turn_number
	)


func _find_nearby_valid_location(chunk, target: Vector2i, max_attempts: int = 20, occupied_positions: Array[Vector2i] = []) -> Vector2i:
	"""Find a valid spawn location near the target position

	Args:
		chunk: Chunk to search
		target: Target position to spawn near
		max_attempts: Maximum search attempts
		occupied_positions: Additional positions to treat as occupied (for batch spawning)

	Returns:
		Valid world position or (-1, -1) if none found
	"""
	# First try the exact position
	if _is_area_clear(chunk, target, DEFAULT_CLEAR_SIZE, occupied_positions):
		return target

	# Spiral outward from target
	for attempt in range(1, max_attempts):
		for dx in range(-attempt, attempt + 1):
			for dy in range(-attempt, attempt + 1):
				if abs(dx) == attempt or abs(dy) == attempt:  # Only check perimeter
					var check_pos = target + Vector2i(dx, dy)
					if _is_area_clear(chunk, check_pos, DEFAULT_CLEAR_SIZE, occupied_positions):
						return check_pos

	return Vector2i(-1, -1)
