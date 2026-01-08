class_name DebugEnemy extends Entity
"""Debug enemy for combat testing

A simple punching bag enemy that:
- Has tons of HP (1000+) so it doesn't die during testing
- Does NOT attack back
- Does NOT move
- Just stands there being targetable

Spawns once per chunk (guaranteed) for testing combat systems.
"""

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	entity_id = "debug_enemy"
	entity_name = "Debug Enemy"

	# Create placeholder sprite (magenta square - different from debug_item's red)
	var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.0, 1.0, 1.0))  # Magenta
	sprite_texture = ImageTexture.create_from_image(img)

	# Initialize with high HP stats
	stats = StatBlock.new()
	stats.body = 100  # High body for huge HP
	stats.bonus_hp = 1000.0  # Extra flat HP bonus

	# Refresh stats to apply HP
	stats._invalidate_cache()
	stats.current_hp = stats.max_hp

	# Call parent ready
	super._ready()

	Log.msg(Log.Category.ENTITY, Log.Level.INFO, "DebugEnemy spawned at %s (HP: %.0f)" % [grid_position, stats.max_hp])

# ============================================================================
# AI (NONE - STATIONARY PUNCHING BAG)
# ============================================================================

func process_turn(_player: Player3D, _turn_number: int) -> void:
	"""Debug enemy does nothing - just stands there"""
	pass  # Intentionally empty - punching bag behavior
