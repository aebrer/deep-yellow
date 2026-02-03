class_name DebugItem extends Item
"""DEBUG_ITEM - Experimental NULL item for testing.

Properties (scale with level N):
- Every turn: Consume N mana, deal N damage to EITHER HP or Sanity (random 50/50)
- Even turns: Also heal N×2 to EITHER HP or Sanity (random 50/50, independent)
- Passive: +5×N max Mana (applied via modifier)

Example Scaling:
- Level 1: -1 Mana, -1 HP or -1 SAN, Even +2 HP or +2 SAN, +5 Mana
- Level 2: -2 Mana, -2 HP or -2 SAN, Even +4 HP or +4 SAN, +10 Mana
- Level 3: -3 Mana, -3 HP or -3 SAN, Even +6 HP or +6 SAN, +15 Mana

Design Intent:
- High-risk, high-reward NULL item
- Unlocks Mana pool for early testing
- Unpredictable damage/healing (RNG test)
- Tests mana cost, self-damage, and healing mechanics
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "debug_item"
const ITEM_NAME = "DEBUG_ITEM"
const POOL = Item.PoolType.NULL
const RARITY_TYPE = ItemRarity.Tier.UNCOMMON  # 2% spawn chance

# Mana bonus per level
const MANA_PER_LEVEL = 5

# Texture path
const TEXTURE_PATH = "res://assets/textures/debug_item.png"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize DEBUG_ITEM with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE
	starts_enabled = false  # Dangerous item — default to [OFF]

	# Visual description (CONSTANT - always shown)
	visual_description = "A malfunctioning device with flickering lights. Appears to be some kind of experimental anomaly containment apparatus."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Effects intensify with level"

	# Load sprite texture
	ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# CORE METHODS (override)
# ============================================================================

func on_equip(player: Player3D) -> void:
	"""Apply mana bonus when equipped."""
	super.on_equip(player)  # Apply base stat bonus (+N NULL)

	# Add mana modifier
	var mana_bonus = MANA_PER_LEVEL * level
	var modifier = StatModifier.new("mana", mana_bonus, StatModifier.ModifierType.ADD, ITEM_NAME)
	player.stats.add_modifier(modifier)

	Log.player("DEBUG_ITEM equipped: +%d max Mana" % mana_bonus)

func on_unequip(player: Player3D) -> void:
	"""Remove mana bonus when unequipped."""
	super.on_unequip(player)  # Remove base stat bonus

	# Remove mana modifier
	player.stats.remove_modifiers_by_source(ITEM_NAME)

	Log.player("DEBUG_ITEM unequipped")

func on_turn(player: Player3D, turn_number: int) -> void:
	"""Execute cyclic damage/healing pattern.

	Every turn: Consume N mana, damage HP or Sanity (random)
	Even turns: Also heal HP or Sanity (random)
	"""
	# Check if we have enough mana
	var mana_cost = float(level)
	if not player.stats.consume_mana(mana_cost):
		return  # Skip effects if no mana

	# EVERY turn - randomly damage HP or Sanity
	var damage = float(level)
	var damage_hp = randf() < 0.5

	if damage_hp:
		player.stats.take_damage(damage)
		Log.player("DEBUG_ITEM: Took %.0f HP damage" % damage)
	else:
		player.stats.drain_sanity(damage)
		Log.player("DEBUG_ITEM: Took %.0f Sanity damage" % damage)

	# Even turns ALSO heal HP or Sanity (independent random choice)
	if turn_number % 2 == 0:
		var heal = float(level * 2)
		var heal_hp = randf() < 0.5

		if heal_hp:
			player.stats.heal(heal)
			Log.player("DEBUG_ITEM: Healed %.0f HP" % heal)
		else:
			player.stats.restore_sanity(heal)
			Log.player("DEBUG_ITEM: Restored %.0f Sanity" % heal)

func level_up(amount: int = 1) -> void:
	"""Level up item and update mana bonus."""
	var old_level = level
	super.level_up(amount)  # Increment level

	Log.player("DEBUG_ITEM leveled up: %d → %d (+%d Mana)" % [
		old_level,
		level,
		MANA_PER_LEVEL
	])

func get_description(clearance_level: int) -> String:
	"""Get description that ADDITIVELY reveals info based on clearance level."""
	# Start with base description (visual + scaling hint)
	var desc = super.get_description(clearance_level)

	# Clearance 0-1: Just the basics (no additional info)
	if clearance_level < 2:
		return desc

	# Clearance 2+: Add designation and basic behavior
	desc += "\nDesignation: Experimental Containment Breach"
	desc += "\nProperties: Unstable energy fluctuations"
	desc += "\nEffects: Alternates between self-damage and regeneration"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		desc += "\n\nMechanics:"
		desc += "\n- Every turn: Consume %d Mana" % level
		desc += "\n- Every turn: -%d HP or -%d Sanity (random)" % [level, level]
		desc += "\n- Even turns: Also +%d HP or +%d Sanity (random)" % [level * 2, level * 2]
		desc += "\n- Passive: +%d max Mana" % [MANA_PER_LEVEL * level]

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: DebugItem extends Item"
		desc += "\npool: NULL"
		desc += "\n\non_turn(turn_number):"
		desc += "\n  # Every turn: random damage"
		desc += "\n  if randf() < 0.5:"
		desc += "\n    player.take_damage(level)"
		desc += "\n  else:"
		desc += "\n    player.drain_sanity(level)"
		desc += "\n  "
		desc += "\n  # Even turns: also random heal"
		desc += "\n  if turn_number %% 2 == 0:"
		desc += "\n    if randf() < 0.5:"
		desc += "\n      player.heal(level * 2)"
		desc += "\n    else:"
		desc += "\n      player.restore_sanity(level * 2)"
		desc += "\n\non_equip():"
		desc += "\n  player.stats.add_modifier("
		desc += "\n    StatModifier.new(\"mana\", 5 * level, ADD, \"DEBUG_ITEM\")"
		desc += "\n  )"

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func get_turn_effect_info() -> Dictionary:
	"""Return mana cost info for UI preview."""
	return {
		"effect_name": ITEM_NAME,
		"mana_cost": float(level),
		"description": "Chaos effect"
	}

func _to_string() -> String:
	"""Debug representation."""
	return "DebugItem(Level %d, +%d Mana, %s)" % [
		level,
		MANA_PER_LEVEL * level,
		"Equipped" if equipped else "Ground"
	]
