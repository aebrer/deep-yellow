extends Control
## Minimap - Top-down view of explored areas
##
## Features:
## - 256×256 pixel internal resolution, displayed at 2x (512×512)
## - Rotates to match camera direction (forward = north)
## - Shows walkable/walls, player position, 10k-step movement trail
## - Colorblind-safe palette
##
## Performance Optimizations:
## - Direct GridMap queries: Bypasses is_walkable() abstraction (major speedup)
## - Spatial culling: Trail rendering skips off-screen positions
## - Transform rotation: Rotates TextureRect node, not pixels
## - Full renders every turn: ~65k tile queries, but direct GridMap access is fast

## Emitted when minimap scale factor changes (for high-res UI scaling)
signal resolution_scale_changed(scale_factor: int)

# ============================================================================
# CONSTANTS
# ============================================================================

const MAP_SIZE := 256  # Pixels (image size)
const TRAIL_LENGTH := 10000  # Steps to remember

## Colorblind-safe colors (light floor, dark walls)
const COLOR_WALKABLE := Color("#8a8a8a")  # Light gray
const COLOR_WALL := Color("#1a3a52")  # Dark blue-gray
const COLOR_PLAYER := Color("#00d9ff")  # Bright cyan
const COLOR_TRAIL_START := Color(0.9, 0.0, 1.0, 0.3)  # Faint purple
const COLOR_TRAIL_END := Color(0.9, 0.0, 1.0, 1.0)  # Bright purple
const COLOR_CHUNK_BOUNDARY := Color("#404040")  # Subtle gray
const COLOR_UNLOADED := Color("#000000")  # Black
const COLOR_ITEM := Color("#ffff00")  # Bright yellow (discovered items)
const COLOR_ENTITY := Color("#ff00ff")  # Magenta (entities/enemies)

# ============================================================================
# NODES
# ============================================================================

@onready var map_texture_rect: TextureRect = $MapTextureRect

# ============================================================================
# STATE
# ============================================================================

## Dynamic image for minimap rendering
var map_image: Image

## Texture displayed on screen
var map_texture: ImageTexture

## Player position trail (ring buffer)
var player_trail: Array[Vector2i] = []
var trail_index: int = 0
var trail_valid_count: int = 0  # Track how many valid positions in buffer

## Reference to grid for tile data
var grid: Node = null

## Reference to player for position/camera
var player: Node = null

## Camera rotation (for north orientation)
var camera_rotation: float = 0.0
var last_camera_rotation: float = 0.0

## Dirty flag - needs content redraw
var content_dirty: bool = true

## Current scale factor (for resolution-based UI scaling)
var current_scale_factor: int = 0

## Last player position for incremental rendering
var last_player_pos: Vector2i = Vector2i(-99999, -99999)

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Create image and texture
	map_image = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	map_texture = ImageTexture.create_from_image(map_image)
	map_texture_rect.texture = map_texture

	# Initialize trail buffer
	player_trail.resize(TRAIL_LENGTH)
	for i in range(TRAIL_LENGTH):
		player_trail[i] = Vector2i(-99999, -99999)  # Invalid position

	# Clear cache when initial chunks finish loading
	if ChunkManager:
		ChunkManager.initial_load_completed.connect(_on_initial_load_completed)

	# Connect to container size changes for dynamic scaling
	var container = map_texture_rect.get_parent()
	if container:
		container.resized.connect(_on_container_resized)
		# Set initial scale (deferred to ensure container has size)
		call_deferred("_update_texture_scale")


func _process(_delta: float) -> void:
	# Update camera rotation every frame (for north orientation)
	if player:
		var camera_rig = player.get_node_or_null("CameraRig")
		if camera_rig:
			var h_pivot = camera_rig.get_node_or_null("HorizontalPivot")
			if h_pivot:
				camera_rotation = h_pivot.rotation.y

				# Rotate the texture rect itself instead of re-rendering pixels
				# Much faster - just a transform, not 65k pixel operations
				map_texture_rect.rotation = camera_rotation

	# Only redraw content when it actually changes (on turn, chunk load, etc)
	if content_dirty:
		_render_map()
		content_dirty = false

# ============================================================================
# PUBLIC API
# ============================================================================

func set_grid(grid_ref: Node) -> void:
	"""Set grid reference for tile queries"""
	grid = grid_ref
	content_dirty = true

func set_player(player_ref: Node) -> void:
	"""Set player reference for position/camera"""
	player = player_ref

func on_player_moved(new_position: Vector2i) -> void:
	"""Called when player moves - update trail and mark dirty"""
	# Add to trail (ring buffer)
	if player_trail[trail_index].x == -99999:
		trail_valid_count += 1  # Adding new position to previously empty slot

	player_trail[trail_index] = new_position
	trail_index = (trail_index + 1) % TRAIL_LENGTH

	content_dirty = true

func on_chunk_loaded(_chunk_pos: Vector2i) -> void:
	"""Called when chunk loads - mark dirty for full redraw"""
	content_dirty = true

func on_chunk_unloaded(_chunk_pos: Vector2i) -> void:
	"""Called when chunk unloads - mark dirty for full redraw"""
	content_dirty = true

func _on_initial_load_completed() -> void:
	"""Called when ChunkManager finishes initial chunk loading"""
	content_dirty = true

func _update_texture_scale() -> void:
	"""Dynamically scale texture by largest integer that fits container (pixel-perfect scaling)"""
	var container = map_texture_rect.get_parent()
	if not container:
		Log.warn(Log.Category.SYSTEM, "Minimap: No container found for MapTextureRect")
		return

	var container_size: Vector2 = container.size

	# Avoid division by zero on initial frame
	if container_size.x <= 0 or container_size.y <= 0:
		Log.warn(Log.Category.SYSTEM, "Minimap: Container size is zero or negative: %v" % container_size)
		return

	# Find largest integer scale that fits, then add 2
	# Image is 256×256, we want pixel-perfect integer multiples
	# +2 ensures minimap is always 2 scale levels larger than what fits
	var max_scale_x := int(floor(container_size.x / MAP_SIZE))
	var max_scale_y := int(floor(container_size.y / MAP_SIZE))
	var scale_factor: int = min(max_scale_x, max_scale_y) + 2

	# Update TextureRect size to match
	var new_size: int = MAP_SIZE * scale_factor
	var half_size: float = new_size / 2.0
	map_texture_rect.offset_left = -half_size
	map_texture_rect.offset_top = -half_size
	map_texture_rect.offset_right = half_size
	map_texture_rect.offset_bottom = half_size

	# Update pivot for rotation (should stay centered)
	map_texture_rect.pivot_offset = Vector2(half_size, half_size)

	# Update UIScaleManager if scale changed (for high-res UI scaling)
	if scale_factor != current_scale_factor:
		current_scale_factor = scale_factor
		if UIScaleManager:
			UIScaleManager.set_resolution_scale(scale_factor)
		resolution_scale_changed.emit(scale_factor)  # Keep signal for any direct listeners

func _on_container_resized() -> void:
	"""Called when parent container changes size"""
	_update_texture_scale()

# ============================================================================
# RENDERING
# ============================================================================

func _render_map() -> void:
	"""Render minimap (always full render for correctness)"""
	if not grid or not player:
		return

	var player_pos: Vector2i = player.grid_position

	# Always do full render - direct GridMap queries are fast enough
	# Incremental rendering would require image scrolling (complex)
	_render_full_map(player_pos)

func _render_full_map(player_pos: Vector2i) -> void:
	"""Full render of 256×256 tile area (used for first render or teleports)"""
	# Clear to unloaded color
	map_image.fill(COLOR_UNLOADED)

	# Get GridMap reference for direct tile queries
	var grid_map: GridMap = grid.grid_map
	if not grid_map:
		Log.warn(Log.Category.SYSTEM, "Minimap: No GridMap found on grid node")
		return

	var half_size := MAP_SIZE / 2
	var min_tile := player_pos - Vector2i(half_size, half_size)
	var max_tile := player_pos + Vector2i(half_size, half_size)

	# Render all tiles in visible area
	for y in range(min_tile.y, max_tile.y):
		for x in range(min_tile.x, max_tile.x):
			var tile_pos := Vector2i(x, y)
			var screen_pos := _world_to_screen(tile_pos, player_pos)

			if not _is_valid_screen_pos(screen_pos):
				continue

			# Query GridMap directly (WALL = 1, FLOOR = 0, INVALID = -1)
			var cell_item := grid_map.get_cell_item(Vector3i(x, 0, y))

			var color: Color
			if cell_item == -1:
				color = COLOR_UNLOADED  # Unloaded/empty cell
			elif cell_item == 1:
				color = COLOR_WALL  # Wall
			else:
				color = COLOR_WALKABLE  # Floor or other walkable

			map_image.set_pixelv(screen_pos, color)

	# Draw dynamic elements (trail + player)
	_update_dynamic_elements(player_pos)

	# Update texture
	map_texture.update(map_image)

func _update_dynamic_elements(player_pos: Vector2i) -> void:
	"""Redraw only trail and player marker (tiles unchanged)"""
	# Draw player trail
	_draw_trail(player_pos)

	# Draw discovered items
	_draw_discovered_items(player_pos)

	# Draw entities
	_draw_entities(player_pos)

	# Draw player position (centered)
	var player_screen := _world_to_screen(player_pos, player_pos)
	if _is_valid_screen_pos(player_screen):
		# Draw 3x3 player marker
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var pixel := player_screen + Vector2i(dx, dy)
				if _is_valid_screen_pos(pixel):
					map_image.set_pixelv(pixel, COLOR_PLAYER)

func _draw_chunk_boundaries(player_pos: Vector2i) -> void:
	"""Draw chunk boundary lines (every 128 tiles)"""
	const CHUNK_SIZE := 128
	var half_size := MAP_SIZE / 2
	var min_tile := player_pos - Vector2i(half_size, half_size)
	var max_tile := player_pos + Vector2i(half_size, half_size)

	# Find chunk boundaries in visible area
	var min_chunk := Vector2i(floor(float(min_tile.x) / CHUNK_SIZE), floor(float(min_tile.y) / CHUNK_SIZE))
	var max_chunk := Vector2i(ceil(float(max_tile.x) / CHUNK_SIZE), ceil(float(max_tile.y) / CHUNK_SIZE))

	# Draw vertical lines (no rotation - TextureRect handles it)
	for chunk_x in range(min_chunk.x, max_chunk.x + 1):
		var world_x := chunk_x * CHUNK_SIZE
		for y in range(min_tile.y, max_tile.y):
			var tile_pos := Vector2i(world_x, y)
			var screen_pos := _world_to_screen(tile_pos, player_pos)

			if _is_valid_screen_pos(screen_pos):
				map_image.set_pixelv(screen_pos, COLOR_CHUNK_BOUNDARY)

	# Draw horizontal lines (no rotation - TextureRect handles it)
	for chunk_y in range(min_chunk.y, max_chunk.y + 1):
		var world_y := chunk_y * CHUNK_SIZE
		for x in range(min_tile.x, max_tile.x):
			var tile_pos := Vector2i(x, world_y)
			var screen_pos := _world_to_screen(tile_pos, player_pos)

			if _is_valid_screen_pos(screen_pos):
				map_image.set_pixelv(screen_pos, COLOR_CHUNK_BOUNDARY)

func _draw_trail(player_pos: Vector2i) -> void:
	"""Draw player movement trail with fading (optimized with spatial culling)"""
	# Pre-calculate visible bounds for spatial culling
	var half_size := MAP_SIZE / 2
	var min_visible := player_pos - Vector2i(half_size, half_size)
	var max_visible := player_pos + Vector2i(half_size, half_size)

	# Early exit if no trail positions yet
	if trail_valid_count == 0:
		return

	# Draw trail with gradient and spatial culling (single pass!)
	for i in range(TRAIL_LENGTH):
		var trail_pos: Vector2i = player_trail[i]

		# Skip invalid positions
		if trail_pos.x == -99999:
			continue

		# SPATIAL CULLING - skip positions outside visible area (major optimization!)
		if trail_pos.x < min_visible.x or trail_pos.x >= max_visible.x:
			continue
		if trail_pos.y < min_visible.y or trail_pos.y >= max_visible.y:
			continue

		# Calculate age for gradient (0.0 = oldest, 1.0 = newest)
		var age := float(i) / float(trail_valid_count)
		var color := COLOR_TRAIL_START.lerp(COLOR_TRAIL_END, age)

		# Convert to screen position (already know it's in bounds)
		var screen_pos := _world_to_screen(trail_pos, player_pos)

		# Draw trail pixel
		map_image.set_pixelv(screen_pos, color)

func _draw_discovered_items(player_pos: Vector2i) -> void:
	"""Draw discovered items as yellow pixels on minimap (within PERCEPTION range)"""
	if not grid or not grid.item_renderer:
		return

	# Get perception range: base 10 tiles + 3 per PERCEPTION stat
	var perception_range: float = 10.0
	if player and player.stats:
		perception_range = 10.0 + (player.stats.perception * 3.0)

	# Get all discovered item positions from ItemRenderer
	var discovered_items = grid.item_renderer.get_discovered_item_positions()

	# Draw each discovered item as a yellow pixel (if within perception range)
	for item_pos in discovered_items:
		# Check if within perception range
		var distance: float = Vector2(item_pos).distance_to(Vector2(player_pos))
		if distance > perception_range:
			continue

		var screen_pos := _world_to_screen(item_pos, player_pos)

		if _is_valid_screen_pos(screen_pos):
			map_image.set_pixelv(screen_pos, COLOR_ITEM)

func _draw_entities(player_pos: Vector2i) -> void:
	"""Draw entities as magenta pixels on minimap (within PERCEPTION range)

	Uses EntityRenderer to get entity positions (data-driven, like items).
	"""
	# Get EntityRenderer from Grid3D
	if not grid or not grid.entity_renderer:
		return

	# Get perception range: base 10 tiles + 3 per PERCEPTION stat
	var perception_range: float = 10.0
	if player and player.stats:
		perception_range = 10.0 + (player.stats.perception * 3.0)

	# Get all entity positions from renderer
	var entity_positions = grid.entity_renderer.get_all_entity_positions()

	# Draw each entity as a magenta pixel (if within perception range)
	for entity_pos in entity_positions:
		# Check if within perception range
		var distance: float = Vector2(entity_pos).distance_to(Vector2(player_pos))
		if distance > perception_range:
			continue

		var screen_pos := _world_to_screen(entity_pos, player_pos)

		if _is_valid_screen_pos(screen_pos):
			# Draw 2x2 entity marker (slightly larger than items)
			for dy in range(0, 2):
				for dx in range(0, 2):
					var pixel := screen_pos + Vector2i(dx, dy)
					if _is_valid_screen_pos(pixel):
						map_image.set_pixelv(pixel, COLOR_ENTITY)

# ============================================================================
# HELPERS
# ============================================================================

func _world_to_screen(world_pos: Vector2i, player_pos: Vector2i) -> Vector2i:
	"""Convert world tile position to screen pixel (before rotation)"""
	var half_size := MAP_SIZE / 2
	var relative := world_pos - player_pos
	return Vector2i(half_size + relative.x, half_size + relative.y)

func _rotate_screen_pos(screen_pos: Vector2i, angle: float) -> Vector2i:
	"""Rotate screen position around center by angle (radians)"""
	var center := Vector2(MAP_SIZE / 2, MAP_SIZE / 2)
	var offset := Vector2(screen_pos) - center

	# Rotate by camera angle
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	var rotated := Vector2(
		offset.x * cos_a - offset.y * sin_a,
		offset.x * sin_a + offset.y * cos_a
	)

	var final_pos := center + rotated
	return Vector2i(int(final_pos.x), int(final_pos.y))

func _is_valid_screen_pos(pos: Vector2i) -> bool:
	"""Check if screen position is within bounds"""
	return pos.x >= 0 and pos.x < MAP_SIZE and pos.y >= 0 and pos.y < MAP_SIZE
