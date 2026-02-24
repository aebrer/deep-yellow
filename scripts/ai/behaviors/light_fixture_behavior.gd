class_name LightFixtureBehavior extends EntityBehavior
## Behavior for fluorescent light fixtures — entropy-locked flicker system
##
## Each light gets a unique personality (reseed_threshold + on_weight) rolled
## at spawn from its world position hash. The entropy lock produces stable
## patterns that occasionally break and reform — recognizable but unpredictable.
##
## Personality spectrum:
##   reseed_threshold high + on_weight high → steady, rarely flickers off
##   reseed_threshold low + on_weight ~0.5 → chaotic, unpredictable
##   reseed_threshold high + on_weight low → stably off, rare brief spark

func _init() -> void:
	skip_turn_processing = true

static func setup_flicker(entity: WorldEntity) -> void:
	"""Stamp entropy lock personality onto a light entity at spawn.

	Uses the entity's world position as a deterministic seed so the same
	light always gets the same personality in the same world.

	Args:
		entity: The fluorescent light entity
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(entity.world_position)

	entity.on_weight = rng.randf()
	entity.reseed_threshold = rng.randf()

	# Each light gets its own RNG instance for the entropy lock
	entity.flicker_rng = RandomNumberGenerator.new()
	entity.flicker_seed = rng.randi()
	entity.flicker_rng.seed = entity.flicker_seed

	# Evaluate initial state
	entity.flicker_on = entity.flicker_rng.randf() < entity.on_weight
