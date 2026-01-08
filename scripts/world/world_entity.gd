class_name WorldEntity extends RefCounted
## Represents an entity spawned in the world
##
## WorldEntities track enemies/NPCs in the world.
## They persist through chunk load/unload cycles and track state.
##
## Responsibilities:
## - Store entity type and spawn parameters
## - Track world position
## - Track current HP and status
## - Provide spawn metadata

# ============================================================================
# PROPERTIES
# ============================================================================

var entity_type: String  ## Entity type ID (e.g., "debug_enemy", "bacteria_spawn")
var world_position: Vector2i  ## Exact tile position in world coordinates
var current_hp: float = 0.0  ## Current HP (persists across chunk unload)
var max_hp: float = 0.0  ## Max HP at spawn time
var is_dead: bool = false  ## Has this entity died?
var spawn_turn: int = 0  ## When was this spawned?

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(
	p_entity_type: String,
	p_world_position: Vector2i,
	p_max_hp: float = 100.0,
	p_spawn_turn: int = 0
) -> void:
	"""Initialize world entity

	Args:
		p_entity_type: Entity type ID (e.g., "debug_enemy")
		p_world_position: World tile coordinates
		p_max_hp: Maximum HP
		p_spawn_turn: Turn number when spawned
	"""
	entity_type = p_entity_type
	world_position = p_world_position
	max_hp = p_max_hp
	current_hp = p_max_hp
	spawn_turn = p_spawn_turn
	is_dead = false

	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "WorldEntity created: %s at %s (HP: %.0f)" % [
		entity_type,
		world_position,
		max_hp
	])

# ============================================================================
# STATE QUERIES
# ============================================================================

func is_alive() -> bool:
	"""Check if entity is alive"""
	return not is_dead and current_hp > 0

func get_hp_percentage() -> float:
	"""Get HP as percentage (0.0 to 1.0)"""
	if max_hp <= 0:
		return 0.0
	return current_hp / max_hp

# ============================================================================
# STATE CHANGES
# ============================================================================

func take_damage(amount: float) -> void:
	"""Apply damage to entity"""
	current_hp = max(0.0, current_hp - amount)
	if current_hp <= 0:
		is_dead = true

func heal(amount: float) -> void:
	"""Heal entity"""
	current_hp = min(max_hp, current_hp + amount)

func mark_dead() -> void:
	"""Mark entity as dead"""
	is_dead = true
	current_hp = 0.0

# ============================================================================
# SERIALIZATION
# ============================================================================

func to_dict() -> Dictionary:
	"""Serialize to dictionary for chunk persistence

	Returns:
		Dictionary with entity state (for saving/loading chunks)
	"""
	return {
		"entity_type": entity_type,
		"world_position": {"x": world_position.x, "y": world_position.y},
		"current_hp": current_hp,
		"max_hp": max_hp,
		"is_dead": is_dead,
		"spawn_turn": spawn_turn
	}

static func from_dict(data: Dictionary) -> WorldEntity:
	"""Deserialize from dictionary

	Args:
		data: Serialized entity data

	Returns:
		Reconstructed WorldEntity
	"""
	var pos_data = data.get("world_position", {"x": 0, "y": 0})
	var world_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

	var world_entity = WorldEntity.new(
		data.get("entity_type", "unknown"),
		world_pos,
		data.get("max_hp", 100.0),
		data.get("spawn_turn", 0)
	)

	world_entity.current_hp = data.get("current_hp", world_entity.max_hp)
	world_entity.is_dead = data.get("is_dead", false)

	return world_entity

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation"""
	var status = "DEAD" if is_dead else "ALIVE"
	return "WorldEntity(%s @ %s, HP=%.0f/%.0f, %s)" % [
		entity_type,
		world_position,
		current_hp,
		max_hp,
		status
	]
