class_name WorldItem extends RefCounted
## Represents an item spawned in the world
##
## WorldItems track ground items that can be picked up by the player.
## They persist through chunk load/unload cycles and track discovery state.
##
## Responsibilities:
## - Store item resource reference
## - Track world position
## - Track pickup/discovery state
## - Provide spawn metadata

# ============================================================================
# PROPERTIES
# ============================================================================

var item_resource: Item  ## Reference to Item definition
var world_position: Vector2i  ## Exact tile position in world coordinates
var picked_up: bool = false  ## Has player picked this up?
var discovered: bool = false  ## Has player seen this (within ~50 tiles)?
var spawn_turn: int = 0  ## When was this spawned?
var rarity: ItemRarity.Tier = ItemRarity.Tier.COMMON  ## Item rarity tier

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(
	p_item_resource: Item,
	p_world_position: Vector2i,
	p_rarity: ItemRarity.Tier = ItemRarity.Tier.COMMON,
	p_spawn_turn: int = 0
) -> void:
	"""Initialize world item

	Args:
		p_item_resource: Item definition (e.g., DebugItem)
		p_world_position: World tile coordinates
		p_rarity: Item rarity tier
		p_spawn_turn: Turn number when spawned
	"""
	item_resource = p_item_resource
	world_position = p_world_position
	rarity = p_rarity
	spawn_turn = p_spawn_turn
	picked_up = false
	discovered = false

# ============================================================================
# STATE QUERIES
# ============================================================================

func is_available() -> bool:
	"""Check if item can be picked up (not already picked up)"""
	return not picked_up

func should_render() -> bool:
	"""Check if item should be rendered (available or discovered)"""
	return not picked_up or discovered

func get_distance_to(pos: Vector2i) -> float:
	"""Get distance from this item to a position"""
	var dx = world_position.x - pos.x
	var dy = world_position.y - pos.y
	return sqrt(dx * dx + dy * dy)

# ============================================================================
# STATE CHANGES
# ============================================================================

func mark_discovered() -> void:
	"""Mark item as discovered (player has seen it)"""
	if not discovered:
		discovered = true

func mark_picked_up() -> void:
	"""Mark item as picked up (player has taken it)"""
	if not picked_up:
		picked_up = true
		Log.player("Picked up: %s" % [
			item_resource.item_name if item_resource else "Unknown"
		])

# ============================================================================
# SERIALIZATION
# ============================================================================

func to_dict() -> Dictionary:
	"""Serialize to dictionary for chunk persistence

	Returns:
		Dictionary with item state (for saving/loading chunks)
	"""
	return {
		"item_id": item_resource.item_id if item_resource else "",
		"world_position": {"x": world_position.x, "y": world_position.y},
		"picked_up": picked_up,
		"discovered": discovered,
		"spawn_turn": spawn_turn,
		"rarity": rarity,
		"level": item_resource.level if item_resource else 1
	}

static func from_dict(data: Dictionary, item_resource: Item) -> WorldItem:
	"""Deserialize from dictionary

	Args:
		data: Serialized item data
		item_resource: Item definition (looked up by item_id)

	Returns:
		Reconstructed WorldItem
	"""
	var pos_data = data.get("world_position", {"x": 0, "y": 0})
	var world_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

	var world_item = WorldItem.new(
		item_resource,
		world_pos,
		data.get("rarity", ItemRarity.Tier.COMMON),
		data.get("spawn_turn", 0)
	)

	world_item.picked_up = data.get("picked_up", false)
	world_item.discovered = data.get("discovered", false)

	# Restore item level (corruption-scaled items spawn above level 1)
	var saved_level = data.get("level", 1)
	if item_resource and saved_level > 1:
		item_resource.level = saved_level

	return world_item

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation"""
	var status = "PICKED_UP" if picked_up else ("DISCOVERED" if discovered else "UNDISCOVERED")
	return "WorldItem(%s @ %s, %s, %s)" % [
		item_resource.item_name if item_resource else "Unknown",
		world_position,
		ItemRarity.RARITY_NAMES.get(rarity, "Unknown"),
		status
	]
