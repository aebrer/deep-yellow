class_name EntityRenderer extends Node3D
## Renders entities as 3D billboards in the world
##
## Creates and manages Billboard3D nodes for entities that exist in loaded chunks.
## Billboards are created when chunks load and destroyed when chunks unload.
## Entity data persists in SubChunk.world_entities for chunk reload.
##
## Follows same pattern as ItemRenderer for consistency.
##
## Responsibilities:
## - Create Billboard3D for each entity in loaded chunks
## - Position billboards at entity world positions
## - Remove billboards when entities die
## - Cleanup billboards when chunks unload
## - Sync entity HP/state with WorldEntity data

# ============================================================================
# DEPENDENCIES
# ============================================================================

## Font with emoji fallback for floating VFX text
## Uses default_font.tres which has NotoColorEmoji as fallback
const _EMOJI_FONT = preload("res://assets/fonts/default_font.tres")

@onready var grid_3d: Grid3D = get_parent()

# ============================================================================
# STATE
# ============================================================================

## Maps world tile position to Sprite3D node
var entity_billboards: Dictionary = {}  # Vector2i -> Sprite3D

## Maps world tile position to WorldEntity data (for state sync)
var entity_data_cache: Dictionary = {}  # Vector2i -> Dictionary

## Maps world tile position to health bar Node3D
var entity_health_bars: Dictionary = {}  # Vector2i -> Node3D

## Currently highlighted entity positions (for attack preview)
var _highlighted_positions: Array[Vector2i] = []

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when an entity dies from damage
## entity_data: Dictionary with entity info (entity_type, exp_reward, etc.)
signal entity_died(entity_data: Dictionary)

# ============================================================================
# CONFIGURATION
# ============================================================================

## Billboard size (world units)
const BILLBOARD_SIZE = 0.5

## Billboard height above floor (world units)
## Matches player Y position (1.0) so entities float at same height
const BILLBOARD_HEIGHT = 1.0

## Entity type colors (until we have sprites)
const ENTITY_COLORS = {
	"debug_enemy": Color(1.0, 0.0, 1.0),       # Magenta
	"bacteria_spawn": Color(0.5, 1.0, 0.5),    # Light green
	"bacteria_brood_mother": Color(0.0, 0.8, 0.0),  # Dark green
}

## Default entity color
const DEFAULT_ENTITY_COLOR = Color(1.0, 0.0, 0.0)  # Red

## Highlight color for attack targets (red glow)
const ATTACK_TARGET_HIGHLIGHT = Color(1.0, 0.4, 0.4)  # Bright red tint

## Hit emoji VFX configuration
const HIT_EMOJI_RISE_HEIGHT = 1.2  # World units to rise (more visible travel)
const HIT_EMOJI_DURATION = 1.0  # Seconds for full animation (turn-based, no rush!)
const HIT_EMOJI_BASE_SIZE = 96  # Base font size (before scaling) - needs to be large for 3D visibility
const HIT_EMOJI_JITTER = 0.4  # Random position offset range (world units)

## Health bar configuration
const HEALTH_BAR_WIDTH = 0.5  # World units (larger for visibility)
const HEALTH_BAR_HEIGHT = 0.08  # World units (thicker)
const HEALTH_BAR_OFFSET_Y = 0.4  # Above entity sprite
const HEALTH_BAR_BG_COLOR = Color(0.0, 0.0, 0.0, 0.9)  # Black background (very visible)
const HEALTH_BAR_FG_COLOR = Color(0.9, 0.15, 0.15, 1.0)  # Bright red health

# ============================================================================
# CHUNK LOADING
# ============================================================================

func render_chunk_entities(chunk: Chunk) -> void:
	"""Create billboards for all entities in chunk

	Args:
		chunk: Chunk that was just loaded
	"""
	for subchunk in chunk.sub_chunks:
		for entity_data in subchunk.world_entities:
			# Skip if dead
			if entity_data.get("is_dead", false):
				continue

			# Get world position
			var pos_data = entity_data.get("world_position", {"x": 0, "y": 0})
			var world_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

			# Skip if billboard already exists (shouldn't happen, but safety check)
			if entity_billboards.has(world_pos):
				continue

			# Create billboard
			var billboard = _create_billboard(entity_data, world_pos)
			if billboard:
				add_child(billboard)
				entity_billboards[world_pos] = billboard
				entity_data_cache[world_pos] = entity_data

				# Create health bar (as sibling, not child - avoids billboard nesting issues)
				var health_bar = _create_health_bar(billboard.position)
				add_child(health_bar)
				entity_health_bars[world_pos] = health_bar

				# Check if entity is already damaged
				var current_hp = entity_data.get("current_hp", 0.0)
				var max_hp = entity_data.get("max_hp", 1.0)
				var hp_percent = current_hp / max_hp if max_hp > 0 else 1.0
				if hp_percent < 1.0:
					_update_health_bar(world_pos, hp_percent)
				else:
					health_bar.visible = false

	var entity_count = chunk.sub_chunks.map(func(s): return s.world_entities.size()).reduce(func(a, b): return a + b, 0)
	if entity_count > 0:
		Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "EntityRenderer: Created %d entity billboards for chunk at %s" % [
			entity_count,
			chunk.position
		])

func unload_chunk_entities(chunk: Chunk) -> void:
	"""Remove billboards for all entities in chunk

	Args:
		chunk: Chunk being unloaded
	"""
	var removed_count = 0

	for subchunk in chunk.sub_chunks:
		for entity_data in subchunk.world_entities:
			var pos_data = entity_data.get("world_position", {"x": 0, "y": 0})
			var world_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

			if entity_billboards.has(world_pos):
				var billboard = entity_billboards[world_pos]
				billboard.queue_free()
				entity_billboards.erase(world_pos)
				entity_data_cache.erase(world_pos)

				# Also remove health bar
				if entity_health_bars.has(world_pos):
					var health_bar = entity_health_bars[world_pos]
					health_bar.queue_free()
					entity_health_bars.erase(world_pos)

				removed_count += 1

	if removed_count > 0:
		Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "EntityRenderer: Removed %d entity billboards for chunk at %s" % [
			removed_count,
			chunk.position
		])

# ============================================================================
# BILLBOARD CREATION
# ============================================================================

func _create_billboard(entity_data: Dictionary, world_pos: Vector2i) -> Sprite3D:
	"""Create a Sprite3D billboard for an entity

	Args:
		entity_data: Serialized WorldEntity data
		world_pos: World tile position

	Returns:
		Sprite3D node or null if creation failed
	"""
	var entity_type = entity_data.get("entity_type", "unknown")

	# Create sprite node
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # Pixel art friendly
	sprite.shaded = true  # Match debug_enemy.tscn setting
	sprite.alpha_cut = Sprite3D.ALPHA_CUT_OPAQUE_PREPASS

	# Position at world coordinates (centered in cell)
	var world_3d = grid_3d.grid_to_world_centered(world_pos, BILLBOARD_HEIGHT) if grid_3d else Vector3(
		world_pos.x * 2.0 + 1.0,  # Fallback if no grid
		BILLBOARD_HEIGHT,
		world_pos.y * 2.0 + 1.0
	)
	sprite.position = world_3d

	# Create placeholder white square and use modulate for color
	# This allows us to change modulate for highlighting effects
	var color = ENTITY_COLORS.get(entity_type, DEFAULT_ENTITY_COLOR)
	var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.pixel_size = BILLBOARD_SIZE / 16.0
	sprite.modulate = color  # Base color via modulate (can be changed for highlights)

	# Store original color for highlight restoration
	sprite.set_meta("base_color", color)

	# Store entity position for collision queries
	sprite.set_meta("grid_position", world_pos)
	sprite.set_meta("entity_type", entity_type)

	# Add examination support (same pattern as ItemRenderer)
	var exam_body = StaticBody3D.new()
	exam_body.name = "ExamBody"
	exam_body.collision_layer = 8  # Layer 4 for raycast detection
	exam_body.collision_mask = 0   # Doesn't collide with anything
	sprite.add_child(exam_body)

	# Add Examinable component as child of StaticBody3D
	var examinable = Examinable.new()
	examinable.entity_id = entity_type  # e.g., "debug_enemy"
	examinable.entity_type = Examinable.EntityType.ENTITY_HOSTILE  # Default to hostile for enemies
	exam_body.add_child(examinable)

	# Add collision shape to StaticBody3D
	var collision_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(BILLBOARD_SIZE, BILLBOARD_SIZE, 0.1)
	collision_shape.shape = box
	exam_body.add_child(collision_shape)

	return sprite

func _create_health_bar(entity_pos: Vector3) -> MeshInstance3D:
	"""Create a health bar using a shader for proper fill behavior.

	Uses a single quad mesh with a shader that handles the fill direction.
	This avoids scaling/positioning issues with sprite-based approaches.

	Args:
		entity_pos: World position of the entity

	Returns:
		MeshInstance3D with health bar shader
	"""
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "HealthBar"
	mesh_instance.position = entity_pos + Vector3(0, HEALTH_BAR_OFFSET_Y, 0)

	# Create quad mesh
	var quad = QuadMesh.new()
	quad.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	mesh_instance.mesh = quad

	# Create shader material
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 fg_color : source_color = vec4(0.9, 0.15, 0.15, 1.0);
uniform vec4 bg_color : source_color = vec4(0.0, 0.0, 0.0, 0.9);
uniform float health : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Billboard: make quad always face camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	// UV.x goes 0.0 (left) to 1.0 (right)
	// Show foreground color where UV.x < health (left side = remaining health)
	if (UV.x < health) {
		ALBEDO = fg_color.rgb;
		ALPHA = fg_color.a;
	} else {
		ALBEDO = bg_color.rgb;
		ALPHA = bg_color.a;
	}
}
"""

	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("fg_color", HEALTH_BAR_FG_COLOR)
	material.set_shader_parameter("bg_color", HEALTH_BAR_BG_COLOR)
	material.set_shader_parameter("health", 1.0)

	mesh_instance.material_override = material

	return mesh_instance

func _update_health_bar(world_pos: Vector2i, hp_percent: float) -> void:
	"""Update health bar display for entity at position.

	Shows the health bar if entity is damaged, updates fill amount.
	Bar depletes from RIGHT to LEFT (health remaining on left side).

	Args:
		world_pos: Entity world position
		hp_percent: Health as 0.0-1.0 (1.0 = full health)
	"""
	if not entity_health_bars.has(world_pos):
		return

	var health_bar = entity_health_bars[world_pos] as MeshInstance3D
	if not health_bar:
		return

	# Show health bar only when damaged (not at full HP)
	health_bar.visible = hp_percent < 1.0

	# Update shader health parameter
	var material = health_bar.material_override as ShaderMaterial
	if material:
		material.set_shader_parameter("health", hp_percent)

# ============================================================================
# ENTITY QUERIES
# ============================================================================

func get_entity_at(world_pos: Vector2i) -> Dictionary:
	"""Get entity data at world position

	Args:
		world_pos: World tile coordinates

	Returns:
		Serialized entity data or empty dict if no entity at position
	"""
	return entity_data_cache.get(world_pos, {})

func has_entity_at(world_pos: Vector2i) -> bool:
	"""Check if there's a living entity at world position

	Args:
		world_pos: World tile coordinates

	Returns:
		true if entity exists and is alive
	"""
	return entity_billboards.has(world_pos)

func get_all_entity_positions() -> Array[Vector2i]:
	"""Get world positions of all rendered entities

	Returns:
		Array of world tile positions with entities
	"""
	var positions: Array[Vector2i] = []
	for pos in entity_billboards.keys():
		positions.append(pos)
	return positions

func get_entities_in_range(center: Vector2i, radius: float) -> Array[Vector2i]:
	"""Get entities within radius of center position

	Args:
		center: Center world tile position
		radius: Search radius in tiles

	Returns:
		Array of entity positions within range
	"""
	var in_range: Array[Vector2i] = []
	for pos in entity_billboards.keys():
		var distance = center.distance_to(pos)
		if distance <= radius:
			in_range.append(pos)
	return in_range

# ============================================================================
# ENTITY STATE UPDATES
# ============================================================================

func damage_entity_at(world_pos: Vector2i, amount: float, attack_emoji: String = "👊") -> bool:
	"""Apply damage to entity at position

	Args:
		world_pos: World tile position
		amount: Damage amount
		attack_emoji: Emoji to display as hit VFX (default: punch)

	Returns:
		true if entity was found and damaged
	"""
	if not entity_data_cache.has(world_pos):
		return false

	var entity_data = entity_data_cache[world_pos]
	var current_hp = entity_data.get("current_hp", 0.0)
	var new_hp = max(0.0, current_hp - amount)
	entity_data["current_hp"] = new_hp

	var max_hp = entity_data.get("max_hp", 1.0)
	var hp_percent = new_hp / max_hp if max_hp > 0 else 0.0

	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Entity at %s took %.1f damage (%.1f/%.1f HP)" % [
		world_pos,
		amount,
		new_hp,
		max_hp
	])

	# Update health bar display
	_update_health_bar(world_pos, hp_percent)

	# Spawn floating emoji VFX with damage number
	_spawn_hit_emoji(world_pos, attack_emoji, amount)

	# Check for death
	if new_hp <= 0:
		entity_data["is_dead"] = true

		# Spawn death skull emoji (2x size of hit emoji)
		_spawn_death_emoji(world_pos)

		# Emit death signal for EXP rewards etc.
		entity_died.emit(entity_data)

		# Delay removal slightly so VFX is visible
		_remove_entity_delayed(world_pos, HIT_EMOJI_DURATION)

		var entity_type = entity_data.get("entity_type", "unknown")
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "Entity '%s' at %s died!" % [entity_type, world_pos])

	return true

func remove_entity_at(world_pos: Vector2i) -> bool:
	"""Remove entity billboard (when killed or despawned)

	Args:
		world_pos: World tile coordinates

	Returns:
		true if entity was found and removed
	"""
	if not entity_billboards.has(world_pos):
		return false

	# Remove billboard
	var billboard = entity_billboards[world_pos]
	billboard.queue_free()
	entity_billboards.erase(world_pos)
	entity_data_cache.erase(world_pos)

	# Remove health bar
	if entity_health_bars.has(world_pos):
		var health_bar = entity_health_bars[world_pos]
		health_bar.queue_free()
		entity_health_bars.erase(world_pos)

	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Removed entity billboard at %s" % world_pos)
	return true

# ============================================================================
# ATTACK TARGET HIGHLIGHTING
# ============================================================================

func highlight_attack_targets(target_positions: Array) -> void:
	"""Highlight entities that will be attacked next turn.

	Clears previous highlights and applies new ones.
	Used by action preview to show what WILL happen.

	Args:
		target_positions: Array of Vector2i positions to highlight
	"""
	# Clear previous highlights first
	clear_attack_highlights()

	# Apply new highlights
	for pos in target_positions:
		if not pos is Vector2i:
			continue

		var world_pos = pos as Vector2i
		if entity_billboards.has(world_pos):
			var sprite = entity_billboards[world_pos] as Sprite3D
			if sprite:
				sprite.modulate = ATTACK_TARGET_HIGHLIGHT
				_highlighted_positions.append(world_pos)

func clear_attack_highlights() -> void:
	"""Clear all attack target highlights, restoring original colors."""
	for world_pos in _highlighted_positions:
		if entity_billboards.has(world_pos):
			var sprite = entity_billboards[world_pos] as Sprite3D
			if sprite:
				var base_color = sprite.get_meta("base_color", Color.WHITE)
				sprite.modulate = base_color  # Restore original color

	_highlighted_positions.clear()

# ============================================================================
# HIT VFX
# ============================================================================

func _spawn_hit_emoji(world_pos: Vector2i, emoji: String, damage: float = 0.0) -> void:
	"""Spawn a floating emoji with damage number that rises and fades.

	Creates a Label3D billboard with the attack emoji and damage that:
	- Starts at the entity position (with random jitter)
	- Rises upward while fading out
	- Auto-removes when animation completes
	- Font size scales with UI and camera zoom

	Args:
		world_pos: Position of entity that was hit
		emoji: Emoji character to display
		damage: Damage amount to show (0 = don't show number)
	"""
	if not entity_billboards.has(world_pos):
		return

	var sprite = entity_billboards[world_pos] as Sprite3D
	if not sprite:
		return

	# Calculate scaled font size
	var base_size = HIT_EMOJI_BASE_SIZE
	if UIScaleManager:
		base_size = UIScaleManager.get_scaled_font_size(base_size)

	# Scale with camera zoom (further out = larger emoji for visibility)
	# Navigate via grid_3d parent to find Player3D sibling
	var tactical_camera: Node = null
	var first_person_camera: Node = null
	if grid_3d:
		var game_3d = grid_3d.get_parent()
		if game_3d:
			var player = game_3d.get_node_or_null("Player3D")
			if player:
				tactical_camera = player.get_node_or_null("CameraRig")
				first_person_camera = player.get_node_or_null("FirstPersonCamera")

	# Determine scaling based on active camera
	if first_person_camera and first_person_camera.get("camera") and first_person_camera.camera.current:
		# Look mode - scale based on FOV (60-90, lower = zoomed in)
		# 75% smaller than tactical: at FOV 60: 0.125x, at FOV 90: 0.1875x
		var fov = first_person_camera.camera.fov
		var fov_ratio = clampf((fov - 60.0) / 30.0, 0.0, 1.0)
		var zoom_scale = lerp(0.125, 0.1875, fov_ratio)
		base_size = int(base_size * zoom_scale)
	elif tactical_camera and "current_zoom" in tactical_camera:
		# Tactical view - scale based on zoom distance (8-25)
		# 10% smaller: at zoom 8 (close): 0.9x, at zoom 25 (far): 2.7x
		var zoom = tactical_camera.current_zoom
		var zoom_ratio = clampf((zoom - 8.0) / 17.0, 0.0, 1.0)
		var zoom_scale = lerp(0.9, 2.7, zoom_ratio)
		base_size = int(base_size * zoom_scale)

	# Create floating emoji label with damage number
	var label = Label3D.new()
	if damage > 0:
		label.text = "%s %.0f" % [emoji, damage]
	else:
		label.text = emoji
	label.font = _EMOJI_FONT  # Use font with emoji fallback for exports
	label.font_size = base_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true  # Always render on top
	label.modulate = Color.WHITE

	# Position slightly above the entity with random jitter
	var jitter = Vector3(
		randf_range(-HIT_EMOJI_JITTER, HIT_EMOJI_JITTER),
		0,
		randf_range(-HIT_EMOJI_JITTER, HIT_EMOJI_JITTER)
	)
	var start_pos = sprite.position + Vector3(0, 0.3, 0) + jitter
	label.position = start_pos

	add_child(label)

	# Animate rise and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	# Rise upward
	var end_pos = start_pos + Vector3(0, HIT_EMOJI_RISE_HEIGHT, 0)
	tween.tween_property(label, "position", end_pos, HIT_EMOJI_DURATION)

	# Fade out
	tween.tween_property(label, "modulate:a", 0.0, HIT_EMOJI_DURATION)

	# Remove when done
	tween.chain().tween_callback(label.queue_free)

func _spawn_death_emoji(world_pos: Vector2i) -> void:
	"""Spawn a skull emoji when entity dies (2x size of hit emoji).

	Args:
		world_pos: Position of entity that died
	"""
	if not entity_billboards.has(world_pos):
		return

	var sprite = entity_billboards[world_pos] as Sprite3D
	if not sprite:
		return

	# Calculate scaled font size (2x the hit emoji size)
	var base_size = HIT_EMOJI_BASE_SIZE * 2
	if UIScaleManager:
		base_size = UIScaleManager.get_scaled_font_size(base_size)

	# Scale with camera zoom (same logic as hit emoji)
	var tactical_camera: Node = null
	var first_person_camera: Node = null
	if grid_3d:
		var game_3d = grid_3d.get_parent()
		if game_3d:
			var player = game_3d.get_node_or_null("Player3D")
			if player:
				tactical_camera = player.get_node_or_null("CameraRig")
				first_person_camera = player.get_node_or_null("FirstPersonCamera")

	if first_person_camera and first_person_camera.get("camera") and first_person_camera.camera.current:
		var fov = first_person_camera.camera.fov
		var fov_ratio = clampf((fov - 60.0) / 30.0, 0.0, 1.0)
		var zoom_scale = lerp(0.5, 0.75, fov_ratio)
		base_size = int(base_size * zoom_scale)
	elif tactical_camera and "current_zoom" in tactical_camera:
		var zoom = tactical_camera.current_zoom
		var zoom_ratio = clampf((zoom - 8.0) / 17.0, 0.0, 1.0)
		var zoom_scale = lerp(1.0, 3.0, zoom_ratio)
		base_size = int(base_size * zoom_scale)

	# Create death emoji label
	var label = Label3D.new()
	label.text = "💀"
	label.font = _EMOJI_FONT  # Use font with emoji fallback for exports
	label.font_size = base_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color.WHITE

	# Position at entity (no jitter - death is centered)
	var start_pos = sprite.position + Vector3(0, 0.5, 0)
	label.position = start_pos

	add_child(label)

	# Animate rise and fade (same timing as hit emoji)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	var end_pos = start_pos + Vector3(0, HIT_EMOJI_RISE_HEIGHT * 1.5, 0)
	tween.tween_property(label, "position", end_pos, HIT_EMOJI_DURATION)
	tween.tween_property(label, "modulate:a", 0.0, HIT_EMOJI_DURATION)

	tween.chain().tween_callback(label.queue_free)

func _remove_entity_delayed(world_pos: Vector2i, delay: float) -> void:
	"""Remove entity after a delay (allows VFX to play on death).

	Args:
		world_pos: Position of entity to remove
		delay: Delay in seconds before removal
	"""
	# Create a timer to delay removal
	var timer = get_tree().create_timer(delay)
	timer.timeout.connect(func(): remove_entity_at(world_pos))

# ============================================================================
# CLEANUP
# ============================================================================

func clear_all_entities() -> void:
	"""Remove all entity billboards (called on level unload)"""
	for billboard in entity_billboards.values():
		billboard.queue_free()

	for health_bar in entity_health_bars.values():
		health_bar.queue_free()

	entity_billboards.clear()
	entity_data_cache.clear()
	entity_health_bars.clear()

	Log.msg(Log.Category.ENTITY, Log.Level.INFO, "EntityRenderer: Cleared all entity billboards")

# ============================================================================
# DEBUG
# ============================================================================

func _to_string() -> String:
	return "EntityRenderer(entities=%d)" % entity_billboards.size()
