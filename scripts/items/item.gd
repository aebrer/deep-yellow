class_name Item extends Resource
"""Base class for all items in the game.

Items can be equipped in one of three pools (BODY, MIND, NULL).
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
"""

# ============================================================================
# ENUMS
# ============================================================================

enum PoolType {
	BODY,   # Physical attacks, damage, defense
	MIND,   # Perception, knowledge, mental abilities
	NULL    # Anomalous effects (requires NULL stat > 0)
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
var starts_enabled: bool = true  ## Whether item defaults to [ON] when first equipped

# Corruption state
var corrupted: bool = false  ## Is this item corrupted?
var corruption_debuffs: Array[Dictionary] = []  ## Rolled debuffs (persisted)
var _last_stat_corruption: float = -1.0  ## Corruption level when STAT debuffs were last applied (-1 = not active)

# ============================================================================
# CORE METHODS (override in subclasses)
# ============================================================================

func get_display_name() -> String:
	"""Get display name, prefixed with [CORRUPT] if corrupted."""
	if corrupted:
		return "[CORRUPT] " + item_name
	return item_name

func on_equip(player: Player3D) -> void:
	"""Called when item is equipped to a slot.

	Common uses:
	- Add stat modifiers (e.g., +10 HP)
	- Apply passive effects
	- Initialize turn counters
	"""
	equipped = true

	# Default: Grant stat bonus based on pool type
	_apply_stat_bonus(player)

	# Apply corruption stat debuffs if enabled by default
	if corrupted and starts_enabled and not corruption_debuffs.is_empty():
		var corruption = CorruptionDebuffs._get_current_corruption()
		CorruptionDebuffs.apply_stat_debuffs(corruption_debuffs, player, corruption, level)
		_last_stat_corruption = corruption

func on_unequip(player: Player3D) -> void:
	"""Called when item is removed from a slot.

	Common uses:
	- Remove stat modifiers
	- Clean up effects
	"""
	# Remove corruption stat debuffs before unequip (only if currently applied)
	if corrupted and not corruption_debuffs.is_empty() and _last_stat_corruption >= 0:
		CorruptionDebuffs.remove_stat_debuffs(corruption_debuffs, player, _last_stat_corruption, level)
		_last_stat_corruption = -1.0

	equipped = false
	Log.player("Unequipped %s (Level %d)" % [get_display_name(), level])

	# Default: Remove stat bonus
	_remove_stat_bonus(player)

func on_turn(player: Player3D, _turn_number: int) -> void:
	"""Called every turn while equipped (in execution order).

	Common uses:
	- Trigger auto-attacks
	- Apply periodic effects
	- Consume resources

	Args:
		player: The player entity
		_turn_number: Global turn counter (for even/odd logic, etc.)
	"""
	if corrupted and not corruption_debuffs.is_empty():
		var corruption = CorruptionDebuffs._get_current_corruption()

		# Recalculate STAT debuffs if corruption has changed since last application
		if _last_stat_corruption >= 0 and corruption != _last_stat_corruption:
			CorruptionDebuffs.remove_stat_debuffs(corruption_debuffs, player, _last_stat_corruption, level)
			CorruptionDebuffs.apply_stat_debuffs(corruption_debuffs, player, corruption, level)
			_last_stat_corruption = corruption

		# Apply per-turn corruption debuffs (always uses current corruption)
		CorruptionDebuffs.apply_per_turn_debuffs(corruption_debuffs, player, corruption, level)

func on_enable(player: Player3D) -> void:
	"""Called when item is toggled ON. Restore all effects (stat bonus + corruption)."""
	_apply_stat_bonus(player)
	if corrupted and not corruption_debuffs.is_empty():
		var corruption = CorruptionDebuffs._get_current_corruption()
		CorruptionDebuffs.apply_stat_debuffs(corruption_debuffs, player, corruption, level)
		_last_stat_corruption = corruption

func on_disable(player: Player3D) -> void:
	"""Called when item is toggled OFF. Remove all effects (stat bonus + corruption)."""
	if corrupted and not corruption_debuffs.is_empty() and _last_stat_corruption >= 0:
		CorruptionDebuffs.remove_stat_debuffs(corruption_debuffs, player, _last_stat_corruption, level)
		_last_stat_corruption = -1.0
	_remove_stat_bonus(player)
	# Clamp current resources to new (lower) max values
	if player and player.stats:
		player.stats.clamp_resources()

func level_up(amount: int = 1) -> void:
	"""Called when a duplicate item is picked up.

	Increases item level by the given amount (default 1, unlimited scaling).
	When combining items, amount = incoming item's level (additive).
	Subclasses can override to apply additional effects.
	"""
	level += amount
	Log.player("%s leveled up by +%d! Now Level %d" % [item_name, amount, level])

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
	var desc = "%s (Level %d)\n\n" % [get_display_name(), level]

	# ALWAYS show visual description (constant)
	if visual_description:
		desc += visual_description + "\n\n"

	# ALWAYS show scaling hint (constant)
	if scaling_hint:
		desc += "Scaling: " + scaling_hint + "\n"

	# Append corruption debuff info (clearance-gated)
	if corrupted and not corruption_debuffs.is_empty():
		var corruption = CorruptionDebuffs._get_current_corruption()
		desc += CorruptionDebuffs.get_debuff_descriptions(corruption_debuffs, corruption, level, clearance_level)

	# Subclasses can add additional clearance-based info by overriding
	return desc

func get_info(clearance_level: int) -> Dictionary:
	"""Get item info in same format as EntityInfo for examination system

	Reuses existing get_description() for unified description system.

	Returns:
		Dictionary with name, description, object_class, threat_level, rarity info
	"""
	return {
		"name": "%s (Level %d)" % [get_display_name(), level],
		"description": get_description(clearance_level),
		"object_class": "Item",
		"threat_level": 0,
		"is_item": true,
		"corrupted": corrupted,
		"rarity": rarity,
		"rarity_name": ItemRarity.get_rarity_name(rarity),
		"rarity_color": ItemRarity.get_color(rarity)
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
		PoolType.MIND:
			player.stats.mind += level
		PoolType.NULL:
			player.stats.null_stat += level

func _remove_stat_bonus(player: Player3D) -> void:
	"""Remove base stat bonus when item is unequipped."""
	if not player or not player.stats:
		return

	match pool_type:
		PoolType.BODY:
			player.stats.body -= level
		PoolType.MIND:
			player.stats.mind -= level
		PoolType.NULL:
			player.stats.null_stat -= level

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
	- cooldown_multiply: float (cooldown multiplier, collected from ALL pools, e.g., 0.8 = 20% faster)
	- extra_attacks: int (additional attacks per turn, e.g., 1 = attack twice)
	- area: AttackTypes.Area (override attack pattern)
	- mana_cost_multiply: float (mana cost modifier for NULL, default 1.0)
	- special_effects: Array (effect objects with apply(player, targets) method)
	- add_tags: Array[String] (tags to add to attack, e.g., ["sound"])
	- remove_tags: Array[String] (tags to remove from attack)
	- tag_damage_multiply: Dictionary (tag -> multiplier, e.g., {"sound": 2.0})

	Tag system notes:
	- Base attacks have tags defined in AttackTypes.BASE_ATTACK_TAGS
	- Items can add/remove tags to transform attacks (e.g., make BODY attack sound-based)
	- tag_damage_multiply applies to ANY attack with matching tag, across all pools
	- Example: Coach's Whistle with {"sound": 1.5} boosts both MIND whistle AND
	  a BODY punch transformed to sound by "Siren's Lungs" item

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


func get_passive_modifiers() -> Dictionary:
	"""Return passive modifiers that affect gameplay systems beyond attacks.

	Override in subclasses that provide non-attack bonuses.
	These modifiers are queried by various game systems:

	Supported modifiers:
	- item_spawn_rate_add: float (additive bonus to item spawn probability, e.g., 0.1 = +10%)

	Returns:
		Dictionary of modifiers (empty dict = no modifications)
	"""
	return {}


# ============================================================================
# COOLDOWN INTERFACE (for items with internal cooldowns)
# ============================================================================

func has_cooldown() -> bool:
	"""Return true if this item has an internal cooldown that can be reset.

	Override in subclasses that have cooldowns (e.g., Lucky Rabbit's Foot).
	Used by cooldown manipulation effects.
	"""
	return false

func get_cooldown_remaining() -> int:
	"""Return remaining turns on internal cooldown (0 = ready).

	Override in subclasses with cooldowns.
	"""
	return 0

func reset_cooldown() -> void:
	"""Reset internal cooldown to 0 (ready to fire).

	Override in subclasses with cooldowns.
	Called by effects like Lucky Rabbit's Foot.
	"""
	pass

func get_status_display() -> Dictionary:
	"""Return info for action preview UI status display.

	Override in subclasses with reactive effects or important cooldowns.
	Used to show items in the action preview (e.g., shield ready, cooldown ticking).

	Returns:
		Dictionary with:
		- show: bool (true to display in action preview)
		- type: String ("ready" or "cooldown")
		- mana_cost: float (mana required when triggered, for ready type)
		- description: String (brief status description)

		Empty dict or show=false = don't display in action preview

	Example (Antigonous Notebook):
		Ready: {"show": true, "type": "ready", "mana_cost": 5, "description": "Blocks next hit"}
		Cooldown: {"show": true, "type": "cooldown", "description": "3 turns"}
	"""
	return {}

# ============================================================================
# UTILITY
# ============================================================================

func duplicate_item() -> Item:
	"""Create a duplicate of this item (for pickup/stacking logic).

	Note: Uses Godot's Resource.duplicate() which creates a deep copy.
	Corruption state is explicitly copied to ensure debuff arrays are independent.
	"""
	var copy = self.duplicate(true)
	copy.corrupted = corrupted
	copy.corruption_debuffs = corruption_debuffs.duplicate(true)
	return copy

func _to_string() -> String:
	"""Debug representation."""
	return "Item(%s, Level %d, %s, %s)" % [
		item_name,
		level,
		PoolType.keys()[pool_type],
		"Equipped" if equipped else "Ground"
	]
