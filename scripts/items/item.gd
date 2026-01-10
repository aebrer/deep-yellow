class_name Item extends Resource
"""Base class for all items in the game.

Items can be equipped in one of four pools (BODY, MIND, NULL, LIGHT).
Each item has a level that increases when duplicates are picked up.
Item properties scale with level (defined in subclasses).

Architecture:
- Item is a Resource (can be saved/loaded, used in editor)
- Subclasses override on_equip(), on_unequip(), on_turn() for behavior
- Descriptions change based on player Clearance level
- Code revelation at highest Clearance (shows actual implementation)

Design:
- Picking up an item grants +N to corresponding base stat (N = item level)
- BODY items → +N BODY
- MIND items → +N MIND
- NULL items → +N NULL
- LIGHT items → no stat bonus
"""

# ============================================================================
# ENUMS
# ============================================================================

enum PoolType {
	BODY,   # Physical attacks, damage, defense
	MIND,   # Perception, knowledge, mental abilities
	NULL,   # Anomalous effects (requires NULL stat > 0)
	LIGHT   # Light generation (single slot)
}

# ============================================================================
# EXPORTED PROPERTIES (set in editor/subclasses)
# ============================================================================

@export var item_id: String = ""  ## Unique identifier (e.g., "brass_knuckles")
@export var item_name: String = ""  ## Display name shown to player
@export var pool_type: PoolType = PoolType.BODY  ## Which pool this item belongs to
@export var rarity: ItemRarity.Tier = ItemRarity.Tier.COMMON  ## Spawn frequency tier

# Visual description (ALWAYS shown at all clearance levels - what it looks like)
@export_group("Descriptions")
@export_multiline var visual_description: String = ""  ## Physical appearance (constant across all clearance)
@export var scaling_hint: String = ""  ## Brief hint about what scales with level (e.g., "Damage increases", "Effects amplify")

# Sprite for ground visualization (billboard)
@export_group("Visuals")
@export var ground_sprite: Texture2D = null  ## Sprite shown when item is on ground

# ============================================================================
# RUNTIME PROPERTIES
# ============================================================================

var level: int = 1  ## Current level of this item (increases when duplicates picked up)
var equipped: bool = false  ## Is this item currently equipped?

# ============================================================================
# CORE METHODS (override in subclasses)
# ============================================================================

func on_equip(player: Player3D) -> void:
	"""Called when item is equipped to a slot.

	Common uses:
	- Add stat modifiers (e.g., +10 HP)
	- Apply passive effects
	- Initialize turn counters
	"""
	equipped = true
	Log.player("Equipped %s (Level %d)" % [item_name, level])

	# Default: Grant stat bonus based on pool type
	_apply_stat_bonus(player)

func on_unequip(player: Player3D) -> void:
	"""Called when item is removed from a slot.

	Common uses:
	- Remove stat modifiers
	- Clean up effects
	"""
	equipped = false
	Log.player("Unequipped %s (Level %d)" % [item_name, level])

	# Default: Remove stat bonus
	_remove_stat_bonus(player)

func on_turn(player: Player3D, turn_number: int) -> void:
	"""Called every turn while equipped (in execution order).

	Common uses:
	- Trigger auto-attacks
	- Apply periodic effects
	- Consume resources

	Args:
		player: The player entity
		turn_number: Global turn counter (for even/odd logic, etc.)
	"""
	pass  # Override in subclasses

func level_up() -> void:
	"""Called when a duplicate item is picked up.

	Increases item level by 1 (unlimited scaling).
	Subclasses can override to apply additional effects.
	"""
	level += 1
	Log.player("%s leveled up! Now Level %d" % [item_name, level])

func get_description(clearance_level: int) -> String:
	"""Get item description based on player's Clearance level.

	ALWAYS shows (constant at all clearance levels):
	- Item name + level
	- Visual description (what it looks like)
	- Scaling hint (what changes with level)

	Then ADDITIVELY reveals more information as clearance increases:
	- Clearance 0-1: Just the basics
	- Clearance 2-3: Mechanics partially revealed
	- Clearance 4+: Full mechanics + code revelation

	Override in subclasses to add clearance-scaled details.

	Args:
		clearance_level: Player's current Clearance (0-5+)

	Returns:
		Formatted description string
	"""
	var desc = "%s (Level %d)\n\n" % [item_name, level]

	# ALWAYS show visual description (constant)
	if visual_description:
		desc += visual_description + "\n\n"

	# ALWAYS show scaling hint (constant)
	if scaling_hint:
		desc += "Scaling: " + scaling_hint + "\n"

	# Subclasses can add additional clearance-based info by overriding
	return desc

func get_info(clearance_level: int) -> Dictionary:
	"""Get item info in same format as EntityInfo for examination system

	Reuses existing get_description() for unified description system.

	Returns:
		Dictionary with name, description, object_class, threat_level
	"""
	return {
		"name": "%s (Level %d)" % [item_name, level],
		"description": get_description(clearance_level),
		"object_class": "Item",
		"threat_level": 0
	}

# ============================================================================
# STAT BONUS SYSTEM
# ============================================================================

func _apply_stat_bonus(player: Player3D) -> void:
	"""Apply base stat bonus when item is equipped (+N to corresponding stat)."""
	if not player or not player.stats:
		return

	match pool_type:
		PoolType.BODY:
			player.stats.body += level
			Log.system("Applied +%d BODY from %s" % [level, item_name])
		PoolType.MIND:
			player.stats.mind += level
			Log.system("Applied +%d MIND from %s" % [level, item_name])
		PoolType.NULL:
			player.stats.null_stat += level
			Log.system("Applied +%d NULL from %s" % [level, item_name])
		PoolType.LIGHT:
			pass  # No stat bonus for LIGHT items

func _remove_stat_bonus(player: Player3D) -> void:
	"""Remove base stat bonus when item is unequipped."""
	if not player or not player.stats:
		return

	match pool_type:
		PoolType.BODY:
			player.stats.body -= level
			Log.system("Removed +%d BODY from %s" % [level, item_name])
		PoolType.MIND:
			player.stats.mind -= level
			Log.system("Removed +%d MIND from %s" % [level, item_name])
		PoolType.NULL:
			player.stats.null_stat -= level
			Log.system("Removed +%d NULL from %s" % [level, item_name])
		PoolType.LIGHT:
			pass  # No stat bonus for LIGHT items

# ============================================================================
# ATTACK MODIFIERS
# ============================================================================

func get_attack_modifiers() -> Dictionary:
	"""Return this item's contribution to the pool's attack.

	Override in subclasses to modify the pool's attack properties.
	Items do NOT have their own attacks - they MODIFY the pool's single attack.

	Possible keys:
	- attack_name: String (override attack display name, e.g., "Brass Knuckles")
	- attack_emoji: String (override attack emoji for UI and VFX, e.g., "🔥")
	- damage_add: float (flat damage bonus)
	- damage_multiply: float (damage multiplier, default 1.0)
	- range_add: float (extra range in tiles)
	- cooldown_add: int (cooldown modifier, negative = faster attacks)
	- area: AttackTypes.Area (override attack pattern)
	- mana_cost_multiply: float (mana cost modifier for NULL, default 1.0)
	- special_effects: Array (effect objects with apply(player, targets) method)

	Returns:
		Dictionary of modifiers (empty dict = no modifications)
	"""
	return {}

func get_turn_effect_info() -> Dictionary:
	"""Return info about this item's on_turn() effect for UI preview.

	Override in subclasses that have mana-consuming turn effects.
	Used by action preview to show 🚫 when item can't afford its effect.

	Returns:
		Dictionary with:
		- effect_name: String (display name for the effect)
		- mana_cost: float (mana required per turn, 0 if none)
		- description: String (brief effect description, optional)

		Empty dict = no turn effect to preview
	"""
	return {}

# ============================================================================
# UTILITY
# ============================================================================

func duplicate_item() -> Item:
	"""Create a duplicate of this item (for pickup/stacking logic).

	Note: Uses Godot's Resource.duplicate() which creates a deep copy.
	"""
	return self.duplicate(true)

func _to_string() -> String:
	"""Debug representation."""
	return "Item(%s, Level %d, %s, %s)" % [
		item_name,
		level,
		PoolType.keys()[pool_type],
		"Equipped" if equipped else "Ground"
	]
