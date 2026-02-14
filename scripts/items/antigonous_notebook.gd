class_name AntigonousNotebook extends Item
"""Antigonous Family Notebook - Forbidden knowledge with protective wards.

Properties (scale with level N):
- On equip: Increases level corruption by 0.1 × N (PERMANENT!)
- Passive: +3×N NULL stat (via modifier, stronger than standard +N)
- Reactive shield: When damage is received, if cooldown ready and mana sufficient,
  spend mana to negate the damage completely
- Internal cooldown of 5 turns between shield activations
- Standard NULL stat bonus (+N NULL) from base class

Example Scaling:
- Level 1: +0.1 corruption, +4 NULL total, 5 mana to block damage
- Level 2: +0.2 corruption, +8 NULL total, 10 mana to block damage
- Level 3: +0.3 corruption, +12 NULL total, 15 mana to block damage

Design Intent:
- LEGENDARY high-risk, high-reward NULL item
- Corruption increase makes enemies stronger/more frequent
- Massive NULL boost enables powerful anomalous abilities
- Reactive damage prevention (only spends mana when actually hit)
- Synergizes with mana-focused builds (debug_item, roman_coin)
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "antigonous_notebook"
const ITEM_NAME = "Antigonous Notebook"
const POOL = Item.PoolType.NULL
const RARITY_TYPE = ItemRarity.Tier.LEGENDARY

# Corruption increase per level (permanent, on equip)
const CORRUPTION_PER_LEVEL = 0.1

# NULL stat bonus per level (in addition to base +N NULL)
const NULL_BONUS_PER_LEVEL = 3

# Shield mana cost per level
const SHIELD_MANA_COST_PER_LEVEL = 5.0

# Internal cooldown (turns between shield activations)
const SHIELD_COOLDOWN = 15

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/antigonous_notebook.png"

# ============================================================================
# RUNTIME STATE
# ============================================================================

var _current_cooldown: int = 0  # Shield cooldown tracker
var _corruption_applied: float = 0.0  # Track how much corruption we added
var _player_ref: Player3D = null  # Reference to player for interceptor callback

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Antigonous Notebook with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "A leather-bound journal, its cover marked with strange geometric patterns. The pages are filled with cramped handwriting in an unknown script. Touching it fills your mind with whispers."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Corruption and protection scale with level"

	# Load sprite texture (will fail gracefully if missing)
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# COOLDOWN INTERFACE (override base class)
# ============================================================================

func has_cooldown() -> bool:
	"""This item has an internal cooldown for shield activation."""
	return true

func get_cooldown_remaining() -> int:
	"""Return remaining turns on shield cooldown."""
	return _current_cooldown

func reset_cooldown() -> void:
	"""Reset shield cooldown to 0."""
	_current_cooldown = 0
	Log.player("ANTIGONOUS NOTEBOOK: Shield cooldown reset!")

# ============================================================================
# EQUIP/UNEQUIP
# ============================================================================

func on_equip(player: Player3D) -> void:
	"""Apply corruption increase, NULL bonus, and register damage interceptor."""
	super.on_equip(player)  # Apply base stat bonus (+N NULL)
	_player_ref = player

	# Add extra NULL modifier
	var null_bonus = NULL_BONUS_PER_LEVEL * level
	var modifier = StatModifier.new("anomaly", null_bonus, StatModifier.ModifierType.ADD, ITEM_NAME)
	player.stats.add_modifier(modifier)

	# Register damage interceptor (reactive damage prevention)
	player.stats.add_damage_interceptor(ITEM_NAME, _try_intercept_damage)

	# Increase corruption (permanent effect!)
	_corruption_applied = CORRUPTION_PER_LEVEL * level
	_increase_corruption(_corruption_applied)

	Log.player("ANTIGONOUS NOTEBOOK equipped: +%d NULL bonus, +%.1f corruption" % [null_bonus, _corruption_applied])

func on_unequip(player: Player3D) -> void:
	"""Remove NULL bonus and damage interceptor. Corruption stays!"""
	super.on_unequip(player)  # Remove base stat bonus

	# Remove NULL modifier
	player.stats.remove_modifiers_by_source(ITEM_NAME)

	# Remove damage interceptor
	player.stats.remove_damage_interceptor_by_source(ITEM_NAME)

	_player_ref = null

	Log.player("ANTIGONOUS NOTEBOOK unequipped (corruption remains!)")

# ============================================================================
# TURN EFFECT
# ============================================================================

func on_turn(_player: Player3D, _turn_number: int) -> void:
	"""Each turn: tick cooldown only. Shield is reactive, not proactive."""
	if _current_cooldown > 0:
		_current_cooldown -= 1

# ============================================================================
# DAMAGE INTERCEPTOR (reactive damage prevention)
# ============================================================================

func _try_intercept_damage(amount: float) -> bool:
	"""Called when player is about to take damage. Returns true to block.

	Checks:
	1. Cooldown must be ready (0)
	2. Player must have enough mana
	If both conditions met: spend mana, trigger cooldown, block damage.
	"""
	# Check cooldown
	if _current_cooldown > 0:
		return false  # On cooldown, can't block

	# Check player reference is still valid (could be freed during unequip edge cases)
	if not _player_ref or not is_instance_valid(_player_ref) or not _player_ref.stats:
		return false

	var mana_cost = SHIELD_MANA_COST_PER_LEVEL * level
	if _player_ref.stats.current_mana < mana_cost:
		return false  # Not enough mana

	# We can block! Spend mana and trigger cooldown
	_player_ref.stats.consume_mana(mana_cost)

	# Apply global cooldown multiplier
	var cooldown_mult = _player_ref.get_cooldown_multiply()
	_current_cooldown = maxi(1, roundi(SHIELD_COOLDOWN * cooldown_mult))

	Log.player("ANTIGONOUS NOTEBOOK: Damage blocked! (%.0f mana spent, %.0f damage negated)" % [mana_cost, amount])
	return true  # Damage intercepted

# ============================================================================
# CORRUPTION HELPER
# ============================================================================

func _increase_corruption(amount: float) -> void:
	"""Increase corruption on the current level."""
	# ChunkManager is an autoload, accessible directly
	if ChunkManager and ChunkManager.corruption_tracker:
		# Get current level - default to 0 if not set
		var current_level_id = 0
		if "level_configs" in ChunkManager and ChunkManager.level_configs.size() > 0:
			# Use first level config's level_id as current (simplified)
			current_level_id = 0
		ChunkManager.corruption_tracker.increase_corruption(current_level_id, amount, 0.0)
		Log.player("Corruption increased by %.2f on Level %d" % [amount, current_level_id])
	else:
		Log.warn(Log.Category.SYSTEM, "Could not access corruption tracker")

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
	desc += "\nDesignation: Forbidden Grimoire"
	desc += "\nProperties: Reality destabilization, protective wards"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		var total_null = (NULL_BONUS_PER_LEVEL * level) + level
		var corruption = CORRUPTION_PER_LEVEL * level
		var mana_cost = SHIELD_MANA_COST_PER_LEVEL * level
		desc += "\n\nMechanics:"
		desc += "\n- On equip: +%.1f corruption (PERMANENT)" % corruption
		desc += "\n- Passive: +%d NULL total" % total_null
		desc += "\n- When hit: If ready and mana >= %.0f, block damage" % mana_cost
		desc += "\n- Shield cooldown: %d turns after activation" % SHIELD_COOLDOWN
		desc += "\n- WARNING: Corruption persists after unequip!"

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: AntigonousNotebook extends Item"
		desc += "\npool: NULL, rarity: LEGENDARY"
		desc += "\n\non_equip():"
		desc += "\n  corruption += %.1f * level" % CORRUPTION_PER_LEVEL
		desc += "\n  stats.add_modifier(\"anomaly\", %d * level)" % NULL_BONUS_PER_LEVEL
		desc += "\n  register_damage_interceptor()"
		desc += "\n\n_try_intercept_damage(amount):"
		desc += "\n  if cooldown == 0 and mana >= %.0f * level:" % SHIELD_MANA_COST_PER_LEVEL
		desc += "\n    consume_mana(), start_cooldown()"
		desc += "\n    return true  # Damage blocked"

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	var total_null = (NULL_BONUS_PER_LEVEL * level) + level
	return "AntigonousNotebook(Level %d, +%d NULL, cd=%d, %s)" % [
		level,
		total_null,
		_current_cooldown,
		"Equipped" if equipped else "Ground"
	]
