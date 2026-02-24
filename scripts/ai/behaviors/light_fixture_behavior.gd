class_name LightFixtureBehavior extends EntityBehavior
## Behavior for fluorescent light fixtures — entropy-locked flicker system
##
## Each light gets a unique personality (reseed_threshold + on_weight) rolled
## at spawn from its world position hash. The entropy lock produces deterministic
## sequences between reseeds — most lights settle into a permanent state, while
## lights with low reseed_threshold keep flickering indefinitely.
##
## Personality spectrum (emergent from uniform random rolls):
##   reseed_threshold high + on_weight high → steady on, locked almost immediately
##   reseed_threshold high + on_weight low  → steady off, locked almost immediately
##   reseed_threshold low  + on_weight high → mostly on, frequent brief flickers off
##   reseed_threshold low  + on_weight ~0.5 → chaotic, unpredictable
##   reseed_threshold low  + on_weight low  → mostly off, occasional brief sparks

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

static func tick(entity: WorldEntity) -> bool:
	"""Run one entropy-lock tick on a single light entity.

	Probabilistically reseeds, then resets to the locked seed and evaluates
	state. Between reseeds the output is deterministic (same seed → same
	randf() → same state). Most lights settle permanently; lights with low
	reseed_threshold keep cycling.

	Args:
		entity: Light entity with flicker_rng set up

	Returns:
		true if the light changed state this tick
	"""
	var was_on := entity.flicker_on

	# Entropy lock: probabilistic reseed breaks the current pattern
	if entity.flicker_rng.randf() > entity.reseed_threshold:
		entity.flicker_seed = entity.flicker_rng.randi()

	# Reset to locked seed — deterministic from here
	entity.flicker_rng.seed = entity.flicker_seed

	# Choose state from weighted pool
	entity.flicker_on = entity.flicker_rng.randf() < entity.on_weight

	return entity.flicker_on != was_on
