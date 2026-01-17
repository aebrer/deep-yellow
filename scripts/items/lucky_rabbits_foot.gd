class_name LuckyRabbitsFoot extends Item
"""Lucky Rabbit's Foot - Chaotic cooldown manipulation.

Properties (scale with level N):
- On-turn effect costs 2 mana
- Internal cooldown of 3 turns between activations
- 10% + 5% per level chance to reset a random cooldown
- Can reset EITHER an item's internal cooldown OR an attack pool cooldown
- Standard NULL stat bonus (+N NULL)

Example Scaling:
- Level 1: 15% chance to reset cooldown (10% + 5%)
- Level 2: 20% chance (10% + 10%)
- Level 3: 25% chance (10% + 15%)

Design Intent:
- Chaotic luck-based item for NULL pool
- Can reset item cooldowns (debug_item, antigonous_notebook, itself)
- Can reset attack cooldowns (BODY/MIND/NULL)
- Low mana cost but unreliable - gambling on luck
- Synergizes with high-cooldown items and attacks
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "lucky_rabbits_foot"
const ITEM_NAME = "Lucky Rabbit's Foot"
const POOL = Item.PoolType.NULL
const RARITY_TYPE = ItemRarity.Tier.UNCOMMON

# Mana cost per activation attempt
const MANA_COST = 2.0

# Internal cooldown (turns between activations)
const INTERNAL_COOLDOWN = 3

# Base chance to reset cooldown (10%) + per level bonus (5%)
const BASE_RESET_CHANCE = 0.10
const RESET_CHANCE_PER_LEVEL = 0.05

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/lucky_rabbits_foot.png"

# Preload for cooldown manipulation
const _AttackTypes = preload("res://scripts/combat/attack_types.gd")

# ============================================================================
# RUNTIME STATE
# ============================================================================

var _current_cooldown: int = 0  # Internal cooldown tracker

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Lucky Rabbit's Foot with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "A severed rabbit's foot on a tarnished brass chain. The fur is matted and discolored. Still feels warm somehow."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Cooldown reset chance increases with level"

	# Load sprite texture (will fail gracefully if missing)
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# COOLDOWN INTERFACE (override base class)
# ============================================================================

func has_cooldown() -> bool:
	"""This item has an internal cooldown."""
	return true

func get_cooldown_remaining() -> int:
	"""Return remaining turns on internal cooldown."""
	return _current_cooldown

func reset_cooldown() -> void:
	"""Reset internal cooldown to 0."""
	_current_cooldown = 0
	Log.player("LUCKY RABBIT'S FOOT: Cooldown reset!")

# ============================================================================
# TURN EFFECT
# ============================================================================

func on_turn(player: Player3D, _turn_number: int) -> void:
	"""Each turn: tick cooldown, attempt lucky reset if ready and can afford.

	Only activates when there's actually something on cooldown to reset.
	Saves mana and avoids log spam when nothing needs resetting.
	"""
	# Tick internal cooldown
	if _current_cooldown > 0:
		_current_cooldown -= 1
		return

	# Check if we can afford mana
	if not player or not player.stats:
		return
	if player.stats.current_mana < MANA_COST:
		return

	# Check if there's anything on cooldown to reset (don't waste mana otherwise)
	var targets = _get_cooldown_targets(player)
	if targets.is_empty():
		return  # Nothing on cooldown - stay ready, don't spend mana

	# Pay mana cost
	player.stats.consume_mana(MANA_COST)

	# Reset internal cooldown
	_current_cooldown = INTERNAL_COOLDOWN

	# Roll for reset chance
	var reset_chance = BASE_RESET_CHANCE + (RESET_CHANCE_PER_LEVEL * level)
	if randf() < reset_chance:
		_reset_random_cooldown_from_targets(player, targets)
	else:
		Log.player("LUCKY RABBIT'S FOOT: No luck this time (%.0f%% chance)" % (reset_chance * 100))

func _get_cooldown_targets(player: Player3D) -> Array:
	"""Build list of all possible cooldown targets (items and attacks on cooldown)."""
	var targets: Array = []  # Array of {type: "item"/"attack", target: item/attack_type, name: String}

	if not player:
		return targets

	# Collect items with cooldowns from all pools
	for pool in [player.body_pool, player.mind_pool, player.null_pool]:
		if pool:
			for i in range(pool.max_slots):
				var item = pool.items[i]
				if item and item.has_cooldown() and item.get_cooldown_remaining() > 0:
					# Don't reset ourselves (that would be too powerful)
					if item != self:
						targets.append({
							"type": "item",
							"target": item,
							"name": item.item_name
						})

	# Collect attack cooldowns (only if on cooldown)
	if player.attack_executor:
		var attack_types = [
			_AttackTypes.Type.BODY,
			_AttackTypes.Type.MIND,
			_AttackTypes.Type.NULL
		]
		for attack_type in attack_types:
			if player.attack_executor._cooldowns[attack_type] > 0:
				targets.append({
					"type": "attack",
					"target": attack_type,
					"name": _AttackTypes.TYPE_NAMES[attack_type] + " attack"
				})

	return targets

func _reset_random_cooldown_from_targets(player: Player3D, targets: Array) -> void:
	"""Reset a random cooldown from the provided targets list."""
	if targets.is_empty():
		return

	# Pick a random target
	var chosen = targets[randi() % targets.size()]

	# Reset the chosen cooldown
	if chosen["type"] == "item":
		chosen["target"].reset_cooldown()
		Log.player("LUCKY RABBIT'S FOOT: Reset %s cooldown!" % chosen["name"])
	else:
		player.attack_executor._cooldowns[chosen["target"]] = 0
		Log.player("LUCKY RABBIT'S FOOT: Reset %s cooldown!" % chosen["name"])

# ============================================================================
# TURN EFFECT INFO (for UI preview)
# ============================================================================

func get_turn_effect_info() -> Dictionary:
	"""Return info about this item's on_turn() effect for UI preview."""
	var reset_chance = BASE_RESET_CHANCE + (RESET_CHANCE_PER_LEVEL * level)
	return {
		"effect_name": "Lucky Reset",
		"mana_cost": MANA_COST if _current_cooldown <= 0 else 0.0,
		"description": "%.0f%% chance to reset a random cooldown" % (reset_chance * 100)
	}

# ============================================================================
# DESCRIPTIONS
# ============================================================================

func get_description(clearance_level: int) -> String:
	"""Get description that ADDITIVELY reveals info based on clearance level."""
	# Start with base description (visual + scaling hint)
	var desc = super.get_description(clearance_level)

	# Clearance 0-1: Just the basics (no additional info)
	if clearance_level < 2:
		return desc

	# Clearance 2+: Add designation and basic behavior
	desc += "\nDesignation: Probability Manipulator"
	desc += "\nProperties: Random cooldown interference"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		var reset_chance = BASE_RESET_CHANCE + (RESET_CHANCE_PER_LEVEL * level)
		desc += "\n\nMechanics:"
		desc += "\n- Mana cost: %.0f per attempt" % MANA_COST
		desc += "\n- Internal cooldown: %d turns" % INTERNAL_COOLDOWN
		desc += "\n- Reset chance: %.0f%%" % (reset_chance * 100)
		desc += "\n- Targets: Items with cooldowns OR attack pools"
		desc += "\n- Also grants +%d NULL" % level

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: LuckyRabbitsFoot extends Item"
		desc += "\npool: NULL"
		desc += "\n\non_turn():"
		desc += "\n  if randf() < %.2f + %.2f * level:" % [BASE_RESET_CHANCE, RESET_CHANCE_PER_LEVEL]
		desc += "\n    # Pick random from items + attacks on cooldown"
		desc += "\n    target.reset_cooldown()"

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	var reset_chance = BASE_RESET_CHANCE + (RESET_CHANCE_PER_LEVEL * level)
	return "LuckyRabbitsFoot(Level %d, %.0f%% reset, cd=%d, %s)" % [
		level,
		reset_chance * 100,
		_current_cooldown,
		"Equipped" if equipped else "Ground"
	]
