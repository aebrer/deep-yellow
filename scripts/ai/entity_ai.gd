class_name EntityAI extends RefCounted
## Entity AI system - processes entity turns using behavior classes
##
## ARCHITECTURE:
## - WorldEntity holds all state (HP, position, AI state like cooldowns)
## - EntityBehavior subclasses provide behavior logic (polymorphic)
## - BehaviorRegistry maps entity_type → behavior instance
## - Called once per turn by ChunkManager after player acts
##
## Each entity type has its own behavior class in scripts/ai/behaviors/
## that handles turn processing, damage, and special abilities.

# Preload behavior classes (needed for static method access)
const _BehaviorRegistry = preload("res://scripts/ai/behaviors/behavior_registry.gd")

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

static func process_entity_turn(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	"""Process one entity's turn using its behavior class

	Args:
		entity: WorldEntity to process
		player_pos: Current player grid position
		grid: Grid3D reference for spatial queries
	"""
	if entity.is_dead:
		return

	# Check must_wait BEFORE resetting turn state
	# This flag is set at end of previous turn, checked at start of this turn
	if entity.must_wait:
		entity.must_wait = false
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "%s at %s is waiting (post-attack/spawn cooldown)" % [entity.entity_type, entity.world_position])
		return

	# Get behavior for this entity type
	var behavior = _BehaviorRegistry.get_behavior(entity.entity_type)

	# Skip static entities (lights, vending machines, exit holes, etc.)
	if behavior.skip_turn_processing:
		return

	# Reset turn state via behavior
	behavior.reset_turn_state(entity)

	# Tick cooldowns
	_tick_cooldowns(entity)

	# Process turn via behavior
	behavior.process_turn(entity, player_pos, grid)

static func _tick_cooldowns(entity: WorldEntity) -> void:
	"""Decrement cooldowns at turn start"""
	if entity.attack_cooldown > 0:
		entity.attack_cooldown -= 1
	if entity.spawn_cooldown > 0:
		entity.spawn_cooldown -= 1

# ============================================================================
# DAMAGE DELEGATION
# ============================================================================

static func apply_damage(entity: WorldEntity, amount: float, tags: Array = []) -> void:
	"""Apply damage to entity via its behavior class

	This allows entity-specific damage handling (immunities, vulnerabilities).

	Args:
		entity: Entity to damage
		amount: Damage amount
		tags: Attack tags (e.g., ["physical", "melee"], ["sound"])
	"""
	var behavior = _BehaviorRegistry.get_behavior(entity.entity_type)
	behavior.take_damage(entity, amount, tags)

