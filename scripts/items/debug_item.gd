class_name DebugItem extends Item
"""DEBUG_ITEM - Experimental NULL item for testing.

Properties (scale with level N):
- Odd turns: Deal N HP damage (to self) AND N Sanity damage (to self)
- Even turns: Heal N×2 HP (to self) AND restore N×2 Sanity (to self)
- Passive: +5×N max Mana (applied via modifier)

Example Scaling:
- Level 1: Odd -1 HP/-1 SAN, Even +2 HP/+2 SAN, +5 Mana
- Level 2: Odd -2 HP/-2 SAN, Even +4 HP/+4 SAN, +10 Mana
- Level 3: Odd -3 HP/-3 SAN, Even +6 HP/+6 SAN, +15 Mana

Design Intent:
- High-risk, high-reward NULL item
- Unlocks Mana pool for early testing
- Cyclic gameplay (odd/even turn pattern)
- Tests self-damage and healing mechanics
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "debug_item"
const ITEM_NAME = "DEBUG_ITEM"
const POOL = Item.PoolType.NULL
const RARITY_TYPE = Item.Rarity.COMMON

# Mana bonus per level
const MANA_PER_LEVEL = 5

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize DEBUG_ITEM with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "A malfunctioning device with flickering lights. Appears to be some kind of experimental anomaly containment apparatus."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Effects intensify with level"

	# Create simple red square placeholder sprite
	var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.0, 0.0, 1.0))  # Red
	ground_sprite = ImageTexture.create_from_image(img)

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

	Odd turns: Damage self
	Even turns: Heal self
	"""
	if turn_number % 2 == 1:
		# Odd turn - DAMAGE
		var damage = float(level)
		player.stats.take_damage(damage)
		player.stats.drain_sanity(damage)
		Log.player("DEBUG_ITEM: Took %.0f HP and %.0f Sanity damage" % [damage, damage])
	else:
		# Even turn - HEAL
		var heal = float(level * 2)
		player.stats.heal(heal)
		player.stats.restore_sanity(heal)
		Log.player("DEBUG_ITEM: Healed %.0f HP and %.0f Sanity" % [heal, heal])

func level_up() -> void:
	"""Level up item and update mana bonus."""
	var old_level = level
	super.level_up()  # Increment level

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
		desc += "\n- Odd turns: -%d HP, -%d Sanity" % [level, level]
		desc += "\n- Even turns: +%d HP, +%d Sanity" % [level * 2, level * 2]
		desc += "\n- Passive: +%d max Mana" % [MANA_PER_LEVEL * level]

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: DebugItem extends Item"
		desc += "\npool: NULL"
		desc += "\n\non_turn(turn_number):"
		desc += "\n  if turn_number %% 2 == 1:  # Odd turns"
		desc += "\n    player.take_damage(level)"
		desc += "\n    player.drain_sanity(level)"
		desc += "\n  else:  # Even turns"
		desc += "\n    player.heal(level * 2)"
		desc += "\n    player.restore_sanity(level * 2)"
		desc += "\n\non_equip():"
		desc += "\n  player.stats.add_modifier("
		desc += "\n    StatModifier.new(\"mana\", 5 * level, ADD, \"DEBUG_ITEM\")"
		desc += "\n  )"

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	return "DebugItem(Level %d, +%d Mana, %s)" % [
		level,
		MANA_PER_LEVEL * level,
		"Equipped" if equipped else "Ground"
	]
