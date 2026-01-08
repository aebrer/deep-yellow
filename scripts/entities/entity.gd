class_name Entity extends Node3D
"""Base class for all entities (enemies, NPCs, etc.)

Entities are turn-based actors in the world:
- Have stats (StatBlock - reuses player's stat system)
- Occupy grid positions (like player)
- Can move, attack, and use abilities
- Have visual representation (billboard sprite)
- Can be targeted and damaged

Architecture:
- Entity is a Node3D (exists in 3D world)
- Has StatBlock for HP, damage, stats
- AI controller (optional) handles behavior
- Integrates with Grid3D for positioning
"""

# ============================================================================
# SIGNALS
# ============================================================================

signal died(entity: Entity)  # Emitted when entity dies
signal damaged(amount: float, attacker: Node3D)  # Emitted when taking damage
signal moved(from_pos: Vector2i, to_pos: Vector2i)  # Emitted when moving

# ============================================================================
# EXPORTED PROPERTIES
# ============================================================================

@export var entity_id: String = ""  ## Unique identifier (e.g., "bacteria_spawn")
@export var entity_name: String = ""  ## Display name
@export var sprite_texture: Texture2D = null  ## Billboard sprite texture

# ============================================================================
# STATE
# ============================================================================

var grid_position: Vector2i = Vector2i(0, 0)  ## Current grid position
var stats: StatBlock = null  ## Entity stats (HP, damage, etc.)
var grid: Grid3D = null  ## Reference to grid (set by spawner)
var ai_controller = null  ## AI controller (optional, set by subclasses)
var is_dead: bool = false  ## Has this entity died?

# ============================================================================
# NODES
# ============================================================================

@onready var sprite: Sprite3D = $Sprite3D

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Add to entity group for targeting
	add_to_group("entities")

	# Initialize sprite if texture provided
	if sprite and sprite_texture:
		sprite.texture = sprite_texture

	# Connect stat signals
	if stats:
		stats.entity_died.connect(_on_entity_died)

	# Update 3D position to match grid position
	update_visual_position()

	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Entity ready: %s at %s" % [entity_name, grid_position])

# ============================================================================
# INITIALIZATION
# ============================================================================

func initialize(p_entity_id: String, p_entity_name: String, p_grid_position: Vector2i, p_stats: StatBlock) -> void:
	"""Initialize entity with ID, name, position, and stats

	Called by spawner after creating entity instance.
	"""
	entity_id = p_entity_id
	entity_name = p_entity_name
	grid_position = p_grid_position
	stats = p_stats

	# Connect stat signals
	if stats:
		stats.entity_died.connect(_on_entity_died)

	# Update visual position
	update_visual_position()

	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Initialized %s (%s) at %s" % [entity_name, entity_id, grid_position])

# ============================================================================
# VISUAL POSITION
# ============================================================================

func update_visual_position() -> void:
	"""Update 3D position to match grid position (SNAP instantly - turn-based!)"""
	if not grid:
		return

	var world_pos = grid.grid_to_world(grid_position)
	world_pos.y = 1.0  # Same height as player

	# TURN-BASED: Snap instantly to grid position
	global_position = world_pos

# ============================================================================
# MOVEMENT
# ============================================================================

func move_to(target_pos: Vector2i) -> bool:
	"""Move entity to target grid position

	Returns true if move succeeded, false if blocked.
	"""
	if not grid:
		Log.warn(Log.Category.ENTITY, "Cannot move %s - no grid reference" % entity_name)
		return false

	# Check if target is walkable
	if not grid.is_walkable(target_pos):
		return false

	# Check if another entity occupies target (TODO: entity collision system)
	# For now, allow overlap

	var old_pos = grid_position
	grid_position = target_pos
	update_visual_position()

	emit_signal("moved", old_pos, grid_position)
	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "%s moved: %s → %s" % [entity_name, old_pos, grid_position])

	return true

# ============================================================================
# COMBAT
# ============================================================================

func take_damage(amount: float, attacker: Node3D = null) -> void:
	"""Take damage from an attack

	Args:
		amount: Damage to take (before defense calculations)
		attacker: What dealt the damage (player, another entity, etc.)
	"""
	if is_dead:
		return  # Already dead, ignore further damage

	if not stats:
		Log.warn(Log.Category.ENTITY, "Cannot damage %s - no stats" % entity_name)
		return

	# Apply damage to HP
	stats.take_damage(amount)

	emit_signal("damaged", amount, attacker)
	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "%s took %.1f damage (%.1f/%.1f HP)" % [
		entity_name,
		amount,
		stats.current_hp,
		stats.max_hp
	])

# ============================================================================
# DEATH
# ============================================================================

func _on_entity_died(cause: String) -> void:
	"""Called when entity's HP reaches 0"""
	if is_dead:
		return  # Already processed death

	is_dead = true

	Log.msg(Log.Category.ENTITY, Log.Level.INFO, "%s died (%s)" % [entity_name, cause])

	emit_signal("died", self)

	# TODO: Drop loot
	# TODO: Award EXP to player
	# TODO: Death animation

	# Remove from scene
	queue_free()

# ============================================================================
# AI / TURN PROCESSING
# ============================================================================

func process_turn(player: Player3D, turn_number: int) -> void:
	"""Process entity's turn (called by AI system)

	Override in subclasses or delegate to AI controller.

	Args:
		player: Reference to player (for targeting)
		turn_number: Current turn number
	"""
	if ai_controller and ai_controller.has_method("process_turn"):
		ai_controller.process_turn(self, player, turn_number)

# ============================================================================
# UTILITY
# ============================================================================

func get_distance_to(target_pos: Vector2i) -> float:
	"""Get distance to target position (grid space)"""
	return grid_position.distance_to(target_pos)

func get_distance_to_player(player: Player3D) -> float:
	"""Get distance to player (grid space)"""
	if not player:
		return INF
	return get_distance_to(player.grid_position)

func _to_string() -> String:
	"""Debug representation"""
	if stats:
		return "Entity(%s, %s, pos=%s, HP=%.0f/%.0f)" % [
			entity_id,
			entity_name,
			grid_position,
			stats.current_hp,
			stats.max_hp
		]
	else:
		return "Entity(%s, %s, pos=%s, NO_STATS)" % [
			entity_id,
			entity_name,
			grid_position
		]
