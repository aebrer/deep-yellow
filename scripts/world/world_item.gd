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
# SERIALIZATION
# ============================================================================

func to_dict() -> Dictionary:
	"""Serialize to dictionary for chunk persistence

	Returns:
		Dictionary with item state (for saving/loading chunks)
	"""
	var data = {
		"item_id": item_resource.item_id if item_resource else "",
		"world_position": {"x": world_position.x, "y": world_position.y},
		"picked_up": picked_up,
		"discovered": discovered,
		"spawn_turn": spawn_turn,
		"rarity": rarity,
		"level": item_resource.level if item_resource else 1
	}

	# Serialize corruption state
	if item_resource and item_resource.corrupted:
		data["corrupted"] = true
		data["corruption_debuffs"] = item_resource.corruption_debuffs.duplicate(true)

	return data

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
