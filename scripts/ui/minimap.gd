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
## - Incremental rendering: Shifts cached tiles on movement, queries only new strip (~256 vs 65k)
## - Three-layer pipeline: tile_cache (shifted) → base_map (+ trail) → map_image (+ sprites)
## - Direct GridMap queries: Bypasses is_walkable() abstraction (major speedup)
## - Spatial culling: Trail rendering skips off-screen positions
## - Transform rotation: Rotates TextureRect node, not pixels


# ============================================================================
# CONSTANTS
# ============================================================================

const MAP_SIZE := 256  # Pixels (image size)
const TRAIL_LENGTH := 10000  # Steps to remember
const MIN_ZOOM := 0  # 2 tiles = 1 pixel (512×512 tile view, sampled)
const MAX_ZOOM := 4  # 1 tile = 4 pixels (64×64 tile view)

## Colorblind-safe colors (light floor, dark walls)
const COLOR_WALKABLE := Color("#8a8a8a")  # Light gray
const COLOR_WALL := Color("#1a3a52")  # Dark blue-gray
const COLOR_PLAYER := Color("#00d9ff")  # Bright cyan (fallback)
const COLOR_TRAIL_START := Color(0.9, 0.0, 1.0, 0.3)  # Faint purple
const COLOR_TRAIL_END := Color(0.9, 0.0, 1.0, 1.0)  # Bright purple
const COLOR_UNLOADED := Color("#000000")  # Black
const COLOR_ITEM := Color("#ffff00")  # Bright yellow (discovered items)
const COLOR_ENTITY := Color("#ff00ff")  # Magenta (entities/enemies)

## Aura colors (semi-transparent glow behind minimap sprites)
const COLOR_AURA_ENTITY := Color(1.0, 0.0, 0.0, 0.45)  # Red - hostile entities
const COLOR_AURA_ENTITY_NEUTRAL := Color(0.0, 0.5, 1.0, 0.45)  # Blue - non-hostile entities (vending machines)
const COLOR_AURA_ENTITY_EXIT := Color(0.85, 0.75, 0.0, 0.45)  # Deep yellow - exit stairs/holes
const COLOR_AURA_ITEM := Color(0.7, 0.2, 1.0, 0.45)  # Purple - items


## Sprite icon sizes per zoom level (pixels)
## Zoom 0: 5px, Zoom 1: 7px, Zoom 2: 11px, Zoom 3: 15px, Zoom 4: 21px
const SPRITE_SIZES := {0: 5, 1: 7, 2: 11, 3: 15, 4: 21}

## Texture paths for minimap sprites
const PLAYER_SPRITE_PATH := "res://assets/sprites/player/hazmat_suit.png"

# ============================================================================
# NODES
# ============================================================================

@onready var map_texture_rect: TextureRect = $MapTextureRect

# ============================================================================
# STATE
# ============================================================================

## Dynamic image for minimap rendering (final composited output)
var map_image: Image

## Base map image (tiles + trail, no sprites) — rendered once per turn
var base_map_image: Image

## Pure tile data cache (no trail, no sprites) — shifted incrementally
var tile_cache_image: Image

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

## Dirty flag - needs visual update (movement, full redraw, etc.)
var content_dirty: bool = true

## Force full tile redraw (zoom change, chunk load/unload, level change, grid change)
var _needs_full_redraw: bool = true

## Cached player position for sprite overlay (updated per turn)
var cached_player_pos: Vector2i = Vector2i(-99999, -99999)

## Current scale factor (for resolution-based UI scaling)
var current_scale_factor: int = 0

## Player position at last tile cache render (for incremental shift calculation)
var last_render_center: Vector2i = Vector2i(-99999, -99999)

## Zoom level: 0 = 2 tiles/pixel, 1 = 1 tile/pixel (default), 2-4 = N pixels/tile
var zoom_level: int = 1

## Pre-cached sprite icons at each zoom size {zoom_level: Image}
var player_sprite_cache: Dictionary = {}
var entity_sprite_cache: Dictionary = {}  # {entity_type: {zoom_level: Image}}
var item_sprite_cache: Dictionary = {}  # {item_id: {zoom_level: Image}}

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Create images and texture
	map_image = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	base_map_image = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	tile_cache_image = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	map_texture = ImageTexture.create_from_image(map_image)
	map_texture_rect.texture = map_texture

	# Initialize trail buffer
	player_trail.resize(TRAIL_LENGTH)
	for i in range(TRAIL_LENGTH):
		player_trail[i] = Vector2i(-99999, -99999)  # Invalid position

	# Pre-cache minimap sprite icons
	_cache_player_sprite()
	_cache_entity_sprites()

	# Connect to ChunkManager signals for chunk lifecycle events
	if ChunkManager:
		ChunkManager.initial_load_completed.connect(_on_initial_load_completed)
		ChunkManager.chunk_grid_loaded.connect(on_chunk_loaded)
		ChunkManager.chunk_grid_unloaded.connect(on_chunk_unloaded)
		if ChunkManager.has_signal("level_changed"):
			ChunkManager.level_changed.connect(_on_level_changed)

	# Connect to container size changes for dynamic scaling
	var container = map_texture_rect.get_parent()
	if container:
		container.resized.connect(_on_container_resized)
		# Set initial scale (deferred to ensure container has size)
		call_deferred("_update_texture_scale")


func _exit_tree() -> void:
	# Disconnect autoload signals to prevent memory leaks on scene reload
	if ChunkManager:
		if ChunkManager.initial_load_completed.is_connected(_on_initial_load_completed):
			ChunkManager.initial_load_completed.disconnect(_on_initial_load_completed)
		if ChunkManager.chunk_grid_loaded.is_connected(on_chunk_loaded):
			ChunkManager.chunk_grid_loaded.disconnect(on_chunk_loaded)
		if ChunkManager.chunk_grid_unloaded.is_connected(on_chunk_unloaded):
			ChunkManager.chunk_grid_unloaded.disconnect(on_chunk_unloaded)
		if ChunkManager.has_signal("level_changed") and ChunkManager.level_changed.is_connected(_on_level_changed):
			ChunkManager.level_changed.disconnect(_on_level_changed)


func _process(_delta: float) -> void:
	# Update camera rotation every frame (for north orientation)
	if player:
		# Check if FPV camera is active (takes priority)
		var fpv_camera = player.get_node_or_null("FirstPersonCamera")
		if fpv_camera and fpv_camera.active:
			var h_pivot = fpv_camera.get_node_or_null("HorizontalPivot")
			if h_pivot:
				camera_rotation = h_pivot.rotation.y
		else:
			# Fall back to tactical camera
			var camera_rig = player.get_node_or_null("CameraRig")
			if camera_rig:
				var h_pivot = camera_rig.get_node_or_null("HorizontalPivot")
				if h_pivot:
					camera_rotation = h_pivot.rotation.y

		# Rotate the texture rect itself instead of re-rendering pixels
		# Much faster - just a transform, not 65k pixel operations
		map_texture_rect.rotation = camera_rotation

	# Full redraw when content changes (on turn, chunk load, etc)
	if content_dirty:
		_render_map()
		content_dirty = false

	# Composite sprites every frame (cheap — just a few small sprite blits)
	# This keeps sprites upright as the minimap TextureRect rotates
	_composite_sprites()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("minimap_zoom_in"):
		_change_zoom(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("minimap_zoom_out"):
		_change_zoom(-1)
		get_viewport().set_input_as_handled()

func _change_zoom(direction: int) -> void:
	"""Change zoom level by direction (+1 or -1), clamped to MIN/MAX"""
	var new_zoom := clampi(zoom_level + direction, MIN_ZOOM, MAX_ZOOM)
	if new_zoom != zoom_level:
		zoom_level = new_zoom
		_needs_full_redraw = true
		content_dirty = true

# ============================================================================
# PUBLIC API
# ============================================================================

func set_grid(grid_ref: Node) -> void:
	"""Set grid reference for tile queries"""
	grid = grid_ref
	_needs_full_redraw = true
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

func clear_trail() -> void:
	"""Clear movement trail (used during level transitions)"""
	for i in range(TRAIL_LENGTH):
		player_trail[i] = Vector2i(-99999, -99999)
	trail_index = 0
	trail_valid_count = 0
	_needs_full_redraw = true
	content_dirty = true

func on_chunk_loaded(_chunk_pos: Vector2i) -> void:
	"""Called when chunk loads - mark dirty for full redraw"""
	_needs_full_redraw = true
	content_dirty = true

func on_chunk_unloaded(_chunk_pos: Vector2i) -> void:
	"""Called when chunk unloads - mark dirty for full redraw"""
	_needs_full_redraw = true
	content_dirty = true

func _on_initial_load_completed() -> void:
	"""Called when ChunkManager finishes initial chunk loading"""
	_needs_full_redraw = true
	content_dirty = true

func _on_level_changed(_new_level_id: int) -> void:
	"""Clear trail and redraw when level changes mid-run"""
	clear_trail()
	# _needs_full_redraw already set by clear_trail()

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

func _on_container_resized() -> void:
	"""Called when parent container changes size"""
	_update_texture_scale()

# ============================================================================
# RENDERING
# ============================================================================

func _render_map() -> void:
	"""Render minimap tiles, using incremental shift when possible.

	Three-layer pipeline:
	  Layer 1: tile_cache_image  (tiles only, shifted incrementally)
	  Layer 2: base_map_image    (tiles + trail, rebuilt each turn)
	  Layer 3: map_image         (tiles + trail + sprites, rebuilt every frame)
	"""
	if not grid or not player:
		return

	var player_pos: Vector2i = player.grid_position

	# Get GridMap reference for direct tile queries
	var grid_map: GridMap = grid.grid_map
	if not grid_map:
		Log.warn(Log.Category.SYSTEM, "Minimap: No GridMap found on grid node")
		return

	if _needs_full_redraw:
		# Full redraw: zoom change, chunk load/unload, level change, etc.
		_render_full_tiles(player_pos, grid_map)
		_needs_full_redraw = false
	elif zoom_level >= 1:
		# Incremental shift for normal movement at zoom >= 1
		var delta := player_pos - last_render_center
		if delta == Vector2i.ZERO:
			# No movement (wait action) — tile cache is still valid, just re-composite trail
			pass
		else:
			var pixel_shift := delta * zoom_level
			var max_shift := MAP_SIZE / 2
			if absi(pixel_shift.x) >= max_shift or absi(pixel_shift.y) >= max_shift:
				# Teleport or huge move — fall back to full redraw
				_render_full_tiles(player_pos, grid_map)
			else:
				_render_incremental_tiles(player_pos, grid_map, delta, pixel_shift)
	else:
		# Zoom 0 always does full redraw (different sampling logic)
		_render_full_tiles(player_pos, grid_map)

	# Layer 2: copy tile cache → base_map, then draw trail on top
	base_map_image.copy_from(tile_cache_image)
	_draw_trail_onto(base_map_image, player_pos)
	cached_player_pos = player_pos

func _render_full_tiles(player_pos: Vector2i, grid_map: GridMap) -> void:
	"""Full render of all tiles into tile_cache_image."""
	tile_cache_image.fill(COLOR_UNLOADED)

	if zoom_level == 0:
		# ZOOMED OUT: 2 tiles per pixel, check 2×2 area per pixel
		var view_radius := MAP_SIZE  # 256 tiles each direction = 512 total
		var min_tile := player_pos - Vector2i(view_radius, view_radius)

		for py in range(MAP_SIZE):
			for px in range(MAP_SIZE):
				var world_x := min_tile.x + px * 2
				var world_y := min_tile.y + py * 2

				var has_wall := false
				var has_floor := false
				for ty in range(2):
					for tx in range(2):
						var cell := grid_map.get_cell_item(Vector3i(world_x + tx, 0, world_y + ty))
						if cell != -1:
							if Grid3D.is_wall_tile(cell):
								has_wall = true
							else:
								has_floor = true

				var color: Color
				if has_wall:
					color = COLOR_WALL
				elif has_floor:
					color = COLOR_WALKABLE
				else:
					color = COLOR_UNLOADED

				tile_cache_image.set_pixelv(Vector2i(px, py), color)
	else:
		# NORMAL/ZOOMED IN: At zoom N, show MAP_SIZE/N tiles per axis
		var view_radius := MAP_SIZE / (2 * zoom_level)
		var min_tile := player_pos - Vector2i(view_radius, view_radius)
		var max_tile := player_pos + Vector2i(view_radius, view_radius)

		for y in range(min_tile.y, max_tile.y):
			for x in range(min_tile.x, max_tile.x):
				var cell_item := grid_map.get_cell_item(Vector3i(x, 0, y))

				var color: Color
				if cell_item == -1:
					color = COLOR_UNLOADED
				elif Grid3D.is_wall_tile(cell_item):
					color = COLOR_WALL
				else:
					color = COLOR_WALKABLE

				var tile_pos := Vector2i(x, y)
				var screen_origin := _world_to_screen(tile_pos, player_pos)
				for ppy in range(zoom_level):
					for ppx in range(zoom_level):
						var pixel := screen_origin + Vector2i(ppx, ppy)
						if _is_valid_screen_pos(pixel):
							tile_cache_image.set_pixelv(pixel, color)

	last_render_center = player_pos

func _render_incremental_tiles(player_pos: Vector2i, grid_map: GridMap, delta: Vector2i, pixel_shift: Vector2i) -> void:
	"""Shift tile_cache_image by pixel_shift and render only the newly exposed strips.

	Uses base_map_image as temporary workspace for the shift operation.
	"""
	# Shift existing tiles: blit the still-valid region to its new position
	var src_x := maxi(pixel_shift.x, 0)
	var src_y := maxi(pixel_shift.y, 0)
	var dst_x := maxi(-pixel_shift.x, 0)
	var dst_y := maxi(-pixel_shift.y, 0)
	var blit_w := MAP_SIZE - absi(pixel_shift.x)
	var blit_h := MAP_SIZE - absi(pixel_shift.y)

	# Use base_map_image as workspace for the shift
	base_map_image.fill(COLOR_UNLOADED)
	base_map_image.blit_rect(tile_cache_image, Rect2i(src_x, src_y, blit_w, blit_h), Vector2i(dst_x, dst_y))

	# Copy shifted result back to tile cache
	tile_cache_image.copy_from(base_map_image)

	# Now render the newly exposed strips
	var view_radius := MAP_SIZE / (2 * zoom_level)
	var min_tile := player_pos - Vector2i(view_radius, view_radius)
	var max_tile := player_pos + Vector2i(view_radius, view_radius)

	# Vertical strip (new columns from horizontal movement)
	if delta.x != 0:
		var strip_tiles := absi(delta.x)
		if delta.x > 0:
			# Moved right — new tiles on the right edge
			var strip_start_x := max_tile.x - strip_tiles
			_render_tile_rect(grid_map, player_pos, strip_start_x, min_tile.y, max_tile.x, max_tile.y)
		else:
			# Moved left — new tiles on the left edge
			var strip_end_x := min_tile.x + strip_tiles
			_render_tile_rect(grid_map, player_pos, min_tile.x, min_tile.y, strip_end_x, max_tile.y)

	# Horizontal strip (new rows from vertical movement)
	if delta.y != 0:
		var strip_tiles := absi(delta.y)
		if delta.y > 0:
			# Moved down — new tiles on the bottom edge
			var strip_start_y := max_tile.y - strip_tiles
			_render_tile_rect(grid_map, player_pos, min_tile.x, strip_start_y, max_tile.x, max_tile.y)
		else:
			# Moved up — new tiles on the top edge
			var strip_end_y := min_tile.y + strip_tiles
			_render_tile_rect(grid_map, player_pos, min_tile.x, min_tile.y, max_tile.x, strip_end_y)

	last_render_center = player_pos

func _render_tile_rect(grid_map: GridMap, player_pos: Vector2i, x_start: int, y_start: int, x_end: int, y_end: int) -> void:
	"""Render a rectangular region of tiles into tile_cache_image."""
	for y in range(y_start, y_end):
		for x in range(x_start, x_end):
			var cell_item := grid_map.get_cell_item(Vector3i(x, 0, y))

			var color: Color
			if cell_item == -1:
				color = COLOR_UNLOADED
			elif Grid3D.is_wall_tile(cell_item):
				color = COLOR_WALL
			else:
				color = COLOR_WALKABLE

			var screen_origin := _world_to_screen(Vector2i(x, y), player_pos)
			for ppy in range(zoom_level):
				for ppx in range(zoom_level):
					var pixel := screen_origin + Vector2i(ppx, ppy)
					if _is_valid_screen_pos(pixel):
						tile_cache_image.set_pixelv(pixel, color)

func _composite_sprites() -> void:
	"""Composite rotated sprites onto base map every frame.

	Copies base_map_image → map_image, then blits counter-rotated sprites on top.
	This is cheap: just a memcpy + a few small sprite blits per frame.
	"""
	if not grid or not player:
		return

	# Start from clean base map (tiles + trail)
	map_image.copy_from(base_map_image)

	var player_pos := cached_player_pos

	# Draw discovered items
	_draw_discovered_items(player_pos)

	# Draw entities (includes exit holes, vending machines, and hostile entities)
	_draw_entities(player_pos)

	# Draw player position (sprite icon, centered, scales with zoom)
	var player_screen := _world_to_screen(player_pos, player_pos)
	if _is_valid_screen_pos(player_screen):
		if player_sprite_cache.has(zoom_level):
			_blit_sprite(player_sprite_cache[zoom_level], player_screen)
		else:
			# Fallback: cyan pixel if sprite not loaded
			var marker_radius := maxi(1, zoom_level)
			for dy in range(-marker_radius, marker_radius + 1):
				for dx in range(-marker_radius, marker_radius + 1):
					var pixel := player_screen + Vector2i(dx, dy)
					if _is_valid_screen_pos(pixel):
						map_image.set_pixelv(pixel, COLOR_PLAYER)

	# Update texture
	map_texture.update(map_image)


func _draw_trail_onto(target_image: Image, player_pos: Vector2i) -> void:
	"""Draw player movement trail with fading onto target image (optimized with spatial culling)"""
	# Pre-calculate visible bounds for spatial culling (zoom-aware)
	var view_radius: int
	if zoom_level == 0:
		view_radius = MAP_SIZE  # 512 tiles visible at zoom 0
	else:
		view_radius = MAP_SIZE / (2 * zoom_level)
	var min_visible := player_pos - Vector2i(view_radius, view_radius)
	var max_visible := player_pos + Vector2i(view_radius, view_radius)

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
		target_image.set_pixelv(screen_pos, color)

func _draw_discovered_items(player_pos: Vector2i) -> void:
	"""Draw discovered items on minimap using sprite icons (within PERCEPTION range).

	Lazily caches item sprites on first encounter. Falls back to colored
	pixels for items without textures.
	"""
	if not grid or not grid.item_renderer:
		return

	# Get perception range: base 15 tiles + 5 per PERCEPTION stat
	var perception_range: float = 15.0
	if player and player.stats:
		perception_range = 15.0 + (player.stats.perception * 5.0)

	# Get all discovered item positions from ItemRenderer
	var discovered_items = grid.item_renderer.get_discovered_item_positions()

	for item_pos in discovered_items:
		var distance: float = Vector2(item_pos).distance_to(Vector2(player_pos))
		if distance > perception_range:
			continue

		var screen_pos := _world_to_screen(item_pos, player_pos)
		if not _is_valid_screen_pos(screen_pos):
			continue

		# Try to get item_id and blit sprite
		var drew_sprite := false
		var item_data = grid.item_renderer.get_item_at(item_pos)
		if item_data:
			var item_id: String = item_data.get("item_id", "")
			if item_id != "":
				# Lazy-cache this item's sprite if not already done
				_cache_item_sprite(item_id)
				if item_sprite_cache.has(item_id) and item_sprite_cache[item_id].has(zoom_level):
					_blit_sprite(item_sprite_cache[item_id][zoom_level], screen_pos, COLOR_AURA_ITEM)
					drew_sprite = true

		if not drew_sprite:
			# Fallback: yellow pixel marker
			var marker_size := maxi(1, zoom_level)
			for dy in range(marker_size):
				for dx in range(marker_size):
					var pixel := screen_pos + Vector2i(dx, dy)
					if _is_valid_screen_pos(pixel):
						map_image.set_pixelv(pixel, COLOR_ITEM)

func _draw_entities(player_pos: Vector2i) -> void:
	"""Draw entities on minimap using sprite icons (within PERCEPTION range).

	Uses EntityRenderer to get entity positions and types. Falls back to
	colored pixels for entities without cached sprites.
	"""
	if not grid or not grid.entity_renderer:
		return

	# Get perception range: base 15 tiles + 5 per PERCEPTION stat
	var perception_range: float = 15.0
	if player and player.stats:
		perception_range = 15.0 + (player.stats.perception * 5.0)

	# Get all entity positions from renderer
	var entity_positions = grid.entity_renderer.get_all_entity_positions()

	# Entity types to skip on minimap (environmental fixtures, too numerous to render)
	const MINIMAP_HIDDEN_ENTITIES := [
		"fluorescent_light", "barrel_fire",
	]

	for entity_pos in entity_positions:
		var distance: float = Vector2(entity_pos).distance_to(Vector2(player_pos))
		if distance > perception_range:
			continue

		var entity = grid.entity_renderer.get_entity_at(entity_pos)
		if not entity:
			continue

		# Skip light fixtures — too many, kills perf, not useful on minimap
		if entity.entity_type in MINIMAP_HIDDEN_ENTITIES:
			continue

		var screen_pos := _world_to_screen(entity_pos, player_pos)
		if not _is_valid_screen_pos(screen_pos):
			continue

		# Try to blit sprite icon
		var drew_sprite := false
		if entity:
			var etype: String = entity.entity_type
			if entity_sprite_cache.has(etype) and entity_sprite_cache[etype].has(zoom_level):
				var aura := _get_entity_aura_color(entity)
				_blit_sprite(entity_sprite_cache[etype][zoom_level], screen_pos, aura)
				drew_sprite = true

		if not drew_sprite:
			# Fallback: colored pixel marker
			var marker_size := maxi(2, zoom_level + 1)
			for dy in range(marker_size):
				for dx in range(marker_size):
					var pixel := screen_pos + Vector2i(dx, dy)
					if _is_valid_screen_pos(pixel):
						map_image.set_pixelv(pixel, COLOR_ENTITY)

func _get_entity_aura_color(entity: WorldEntity) -> Color:
	"""Return the appropriate minimap aura color for an entity."""
	# Exit entities get deep yellow
	if entity.is_exit:
		return COLOR_AURA_ENTITY_EXIT
	# Non-hostile entities (vending machines, etc.) get blue
	if not entity.hostile:
		return COLOR_AURA_ENTITY_NEUTRAL
	# Hostile entities get red
	return COLOR_AURA_ENTITY

# ============================================================================
# HELPERS
# ============================================================================

func _world_to_screen(world_pos: Vector2i, player_pos: Vector2i) -> Vector2i:
	"""Convert world tile position to screen pixel (zoom-aware, before rotation)"""
	var half_size := MAP_SIZE / 2
	var relative := world_pos - player_pos
	if zoom_level == 0:
		# Zoomed out: 2 tiles per pixel, so divide offset by 2
		return Vector2i(half_size + relative.x / 2, half_size + relative.y / 2)
	return Vector2i(half_size + relative.x * zoom_level, half_size + relative.y * zoom_level)


func _is_valid_screen_pos(pos: Vector2i) -> bool:
	"""Check if screen position is within bounds"""
	return pos.x >= 0 and pos.x < MAP_SIZE and pos.y >= 0 and pos.y < MAP_SIZE

# ============================================================================
# SPRITE CACHING
# ============================================================================

func _cache_player_sprite() -> void:
	"""Load player sprite and pre-cache resized versions for each zoom level."""
	if not ResourceLoader.exists(PLAYER_SPRITE_PATH):
		Log.warn(Log.Category.SYSTEM, "Minimap: Player sprite not found: %s" % PLAYER_SPRITE_PATH)
		return

	var texture = load(PLAYER_SPRITE_PATH) as Texture2D
	if not texture:
		return

	var source_image := texture.get_image()
	if not source_image:
		return
	# Decompress VRAM-compressed images so resize() works
	if source_image.is_compressed():
		source_image.decompress()

	# Cache resized version for each zoom level
	for zoom in SPRITE_SIZES:
		var icon_size: int = SPRITE_SIZES[zoom]
		var resized := source_image.duplicate()
		resized.resize(icon_size, icon_size, Image.INTERPOLATE_NEAREST)
		player_sprite_cache[zoom] = resized

func _cache_entity_sprites() -> void:
	"""Load entity textures and pre-cache resized versions for each zoom level.
	Uses EntityRenderer.ENTITY_TEXTURES as single source of truth."""
	var entity_textures: Dictionary = EntityRenderer.ENTITY_TEXTURES

	for entity_type in entity_textures:
		var path: String = entity_textures[entity_type]
		if not ResourceLoader.exists(path):
			continue

		var texture = load(path) as Texture2D
		if not texture:
			continue

		var source_image := texture.get_image()
		if not source_image:
			continue
		if source_image.is_compressed():
			source_image.decompress()

		entity_sprite_cache[entity_type] = {}
		for zoom in SPRITE_SIZES:
			var icon_size: int = SPRITE_SIZES[zoom]
			var resized := source_image.duplicate()
			resized.resize(icon_size, icon_size, Image.INTERPOLATE_NEAREST)
			entity_sprite_cache[entity_type][zoom] = resized

func _cache_item_sprite(item_id: String) -> void:
	"""Lazily cache an item sprite when first encountered on minimap."""
	if item_sprite_cache.has(item_id):
		return  # Already cached

	if not grid or not grid.item_renderer:
		return

	# Get item texture from ItemRenderer's item_data_cache → item resource
	var item_resource = grid.item_renderer._get_item_by_id(item_id)
	if not item_resource or not item_resource.ground_sprite:
		return

	var source_image: Image = item_resource.ground_sprite.get_image()
	if not source_image:
		return
	if source_image.is_compressed():
		source_image.decompress()

	item_sprite_cache[item_id] = {}
	for zoom in SPRITE_SIZES:
		var icon_size: int = SPRITE_SIZES[zoom]
		var resized: Image = source_image.duplicate() as Image
		resized.resize(icon_size, icon_size, Image.INTERPOLATE_NEAREST)
		item_sprite_cache[item_id][zoom] = resized

func _blit_sprite(sprite_image: Image, center: Vector2i, aura_color: Color = Color.TRANSPARENT) -> void:
	"""Blit a sprite image onto the minimap, counter-rotated to stay upright.

	The minimap TextureRect rotates by camera_rotation, so we rotate each
	sprite by -camera_rotation to cancel it out. Uses inverse sampling to
	avoid gaps. Only copies non-transparent pixels (alpha > 0.1).

	If aura_color is non-transparent, draws a circular glow behind the sprite
	(2px larger radius) to help it stand out against the map.
	"""
	var size := sprite_image.get_width()
	var half := size / 2.0
	var angle := -camera_rotation  # Counter-rotate against minimap rotation

	var cos_a := cos(angle)
	var sin_a := sin(angle)

	# Draw aura behind sprite (slightly larger circle)
	if aura_color.a > 0.0:
		var aura_radius := half + 2.0
		var aura_radius_sq := aura_radius * aura_radius
		for dy in range(int(-aura_radius), int(aura_radius) + 1):
			for dx in range(int(-aura_radius), int(aura_radius) + 1):
				if dx * dx + dy * dy <= aura_radius_sq:
					var dest := center + Vector2i(dx, dy)
					if _is_valid_screen_pos(dest):
						# Blend aura with existing pixel
						var existing := map_image.get_pixelv(dest)
						var blended := existing.lerp(Color(aura_color, 1.0), aura_color.a)
						map_image.set_pixelv(dest, blended)

	# Iterate over destination pixels in the bounding square
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			# Inverse rotate: find which source pixel maps to this destination
			var src_x := int(round(dx * cos_a + dy * sin_a + half))
			var src_y := int(round(-dx * sin_a + dy * cos_a + half))

			if src_x >= 0 and src_x < size and src_y >= 0 and src_y < size:
				var pixel_color := sprite_image.get_pixel(src_x, src_y)
				if pixel_color.a > 0.1:
					var dest := center + Vector2i(dx, dy)
					if _is_valid_screen_pos(dest):
						map_image.set_pixelv(dest, pixel_color)
