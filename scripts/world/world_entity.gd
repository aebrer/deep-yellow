class_name WorldEntity extends RefCounted
## Represents an entity spawned in the world
##
## WorldEntities track enemies/NPCs in the world.
## They persist through chunk load/unload cycles and track state.
## This is the AUTHORITATIVE source of entity state - EntityRenderer only renders.
##
## Responsibilities:
## - Store entity type and spawn parameters
## - Track world position
## - Track current HP and status (authoritative)
## - Emit signals on state changes
## - Provide spawn metadata
## - Track AI state (move budget, cooldowns, wait flags)

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when entity HP changes (for health bar updates)
signal hp_changed(current_hp: float, max_hp: float)

## Emitted when entity dies (for VFX, EXP rewards, cleanup)
signal died(entity: WorldEntity)

## Emitted when entity moves (for billboard position updates)
## old_pos: Previous world tile position
## new_pos: New world tile position
signal moved(old_pos: Vector2i, new_pos: Vector2i)

# ============================================================================
# PROPERTIES - Core
# ============================================================================

var entity_type: String  ## Entity type ID (e.g., "debug_enemy", "bacteria_spawn")
var world_position: Vector2i  ## Exact tile position in world coordinates
var max_hp: float = 0.0  ## Max HP at spawn time
var spawn_turn: int = 0  ## When was this spawned?

## Current HP - emits hp_changed signal on change
var current_hp: float = 0.0:
	set(value):
		var old_hp = current_hp
		current_hp = clampf(value, 0.0, max_hp)
		if current_hp != old_hp:
			hp_changed.emit(current_hp, max_hp)

## Dead flag - once true, entity is permanently dead
var is_dead: bool = false

# ============================================================================
# PROPERTIES - AI State
# ============================================================================

## Moves remaining this turn (reset at turn start based on entity type)
var moves_remaining: int = 0

## Attack cooldown (turns until can attack again, 0 = ready)
var attack_cooldown: int = 0

## Must wait this turn (post-attack wait, post-spawn wait, etc.)
var must_wait: bool = false

## Turns until can spawn minions again (Motherload only)
var spawn_cooldown: int = 0

## Last known player position (for pathfinding, null if never seen)
var last_seen_player_pos: Variant = null  # Vector2i or null

## Current path to target (array of Vector2i positions)
var current_path: Array[Vector2i] = []

## Attack damage for this entity
var attack_damage: float = 5.0

## Attack range in tiles
var attack_range: float = 1.5

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
	"""Apply damage to entity

	Emits hp_changed signal. If HP reaches 0, sets is_dead and emits died signal.

	Args:
		amount: Damage to apply (positive value)
	"""
	if is_dead:
		return  # Already dead, ignore further damage

	current_hp = max(0.0, current_hp - amount)  # Setter emits hp_changed

	if current_hp <= 0 and not is_dead:
		is_dead = true
		died.emit(self)
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "WorldEntity '%s' at %s died" % [entity_type, world_position])

func heal(amount: float) -> void:
	"""Heal entity"""
	current_hp = min(max_hp, current_hp + amount)

func mark_dead() -> void:
	"""Mark entity as dead"""
	is_dead = true
	current_hp = 0.0

func move_to(new_pos: Vector2i) -> void:
	"""Move entity to new position

	Emits moved signal for EntityRenderer to update billboard position.

	Args:
		new_pos: New world tile coordinates
	"""
	if new_pos == world_position:
		return  # No movement

	var old_pos = world_position
	world_position = new_pos
	moved.emit(old_pos, new_pos)
	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "%s moved from %s to %s" % [entity_type, old_pos, new_pos])

# ============================================================================
# SERIALIZATION
# ============================================================================

func to_dict() -> Dictionary:
	"""Serialize to dictionary for chunk persistence

	Returns:
		Dictionary with entity state (for saving/loading chunks)
	"""
	var data = {
		"entity_type": entity_type,
		"world_position": {"x": world_position.x, "y": world_position.y},
		"current_hp": current_hp,
		"max_hp": max_hp,
		"is_dead": is_dead,
		"spawn_turn": spawn_turn,
		# AI state
		"moves_remaining": moves_remaining,
		"attack_cooldown": attack_cooldown,
		"must_wait": must_wait,
		"spawn_cooldown": spawn_cooldown,
		"attack_damage": attack_damage,
		"attack_range": attack_range,
	}
	# Serialize last_seen_player_pos if set
	if last_seen_player_pos != null:
		data["last_seen_player_pos"] = {"x": last_seen_player_pos.x, "y": last_seen_player_pos.y}
	return data

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

	# Restore AI state
	world_entity.moves_remaining = data.get("moves_remaining", 0)
	world_entity.attack_cooldown = data.get("attack_cooldown", 0)
	world_entity.must_wait = data.get("must_wait", false)
	world_entity.spawn_cooldown = data.get("spawn_cooldown", 0)
	world_entity.attack_damage = data.get("attack_damage", 5.0)
	world_entity.attack_range = data.get("attack_range", 1.5)

	# Restore last_seen_player_pos if present
	if data.has("last_seen_player_pos"):
		var lsp = data["last_seen_player_pos"]
		world_entity.last_seen_player_pos = Vector2i(lsp.get("x", 0), lsp.get("y", 0))

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
