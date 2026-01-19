class_name BacteriaSpreaderBehavior extends EntityBehavior
## Bacteria Spreader behavior
##
## Support enemy that buffs the swarm:
## - 1 move per turn
## - Passive healing aura: heals nearby bacteria each turn
## - AOE attack: damages player if within 3x3 area
## - Can attack AND move on the same turn
## - Medium HP, slower than spawns

const SENSE_RANGE: float = 40.0
const ATTACK_RANGE: float = 1.5  # 3x3 area = sqrt(2) diagonal ~ 1.41
const ATTACK_DAMAGE: float = 3.0
const HEAL_RANGE: float = 3.0  # Tiles - heals bacteria within this range
# Healing percent = attack_damage% (so 3 damage = 3% heal, scales with corruption)

func reset_turn_state(entity: WorldEntity) -> void:
	entity.moves_remaining = 1
	entity.attack_damage = ATTACK_DAMAGE
	entity.attack_range = ATTACK_RANGE

func process_turn(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	# PASSIVE: Heal nearby bacteria every turn (before anything else)
	_heal_nearby_bacteria(entity, grid)

	# SENSE: Can we see the player?
	var distance_to_player = entity.world_position.distance_to(player_pos)
	var can_sense_player = distance_to_player <= SENSE_RANGE

	if can_sense_player:
		entity.last_seen_player_pos = player_pos

	# Try AOE attack if player is in range
	var attacked = false
	if entity.attack_cooldown == 0 and distance_to_player <= entity.attack_range:
		if grid.has_line_of_sight(entity.world_position, player_pos):
			_execute_aoe_attack(entity, player_pos, grid)
			entity.attack_cooldown = 2
			attacked = true
			# Can still move after attacking!

	# If already in attack range, hold position or shuffle
	if distance_to_player <= entity.attack_range:
		if randf() < HOLD_POSITION_CHANCE:
			return
		else:
			if entity.moves_remaining > 0:
				shuffle_around_target(entity, player_pos, grid)
			return

	# Move toward player (slower - only move if we have moves)
	if entity.moves_remaining > 0 and entity.last_seen_player_pos != null:
		move_toward_target(entity, entity.last_seen_player_pos, grid)

func _heal_nearby_bacteria(entity: WorldEntity, grid) -> void:
	"""Heal all bacteria entities within HEAL_RANGE"""
	if not grid or not grid.entity_renderer:
		return

	var my_pos = entity.world_position
	var healed_any = false

	# Get all entities from the renderer's cache
	for pos in grid.entity_renderer.entity_cache:
		var other_entity: WorldEntity = grid.entity_renderer.entity_cache[pos]

		# Skip self and dead entities
		if other_entity == entity or other_entity.is_dead:
			continue

		# Only heal bacteria types, but NOT other spreaders (no self-sustaining spreader blob)
		if not other_entity.entity_type.begins_with("bacteria"):
			continue
		if other_entity.entity_type == "bacteria_spreader":
			continue

		# Check range
		var distance = my_pos.distance_to(other_entity.world_position)
		if distance > HEAL_RANGE:
			continue

		# Skip if already at full HP
		if other_entity.current_hp >= other_entity.max_hp:
			continue

		# Heal by percentage of max HP equal to attack_damage
		# So 3 damage = 3% heal, and both scale with corruption
		var heal_percent = entity.attack_damage / 100.0
		var heal_amount = other_entity.max_hp * heal_percent
		other_entity.current_hp = min(other_entity.max_hp, other_entity.current_hp + heal_amount)

		# Emit HP changed signal so health bars update
		other_entity.hp_changed.emit(other_entity.current_hp, other_entity.max_hp)

		healed_any = true

	if healed_any:
		Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Bacteria Spreader at %s healed nearby bacteria" % my_pos)

func _execute_aoe_attack(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	"""Execute AOE attack - damages player if in 3x3 area"""
	if not grid:
		return

	var player = grid.get_node_or_null("../Player3D")
	if not player:
		return

	if player.stats:
		player.stats.take_damage(entity.attack_damage)
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "Bacteria Spreader AOE attacks player for %.0f damage" % entity.attack_damage)

		# Show VFX at player position
		if grid.entity_renderer:
			grid.entity_renderer.spawn_hit_vfx(player_pos, get_attack_emoji(), entity.attack_damage)

func get_attack_emoji() -> String:
	return "🧪"  # Test tube / spreader vibe
