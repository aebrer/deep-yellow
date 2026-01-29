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
const MIN_ZOOM := 0  # 2 tiles = 1 pixel (512×512 tile view, sampled)
const MAX_ZOOM := 4  # 1 tile = 4 pixels (64×64 tile view)

## Colorblind-safe colors (light floor, dark walls)
const COLOR_WALKABLE := Color("#8a8a8a")  # Light gray
const COLOR_WALL := Color("#1a3a52")  # Dark blue-gray
const COLOR_PLAYER := Color("#00d9ff")  # Bright cyan (fallback)
const COLOR_TRAIL_START := Color(0.9, 0.0, 1.0, 0.3)  # Faint purple
const COLOR_TRAIL_END := Color(0.9, 0.0, 1.0, 1.0)  # Bright purple
const COLOR_CHUNK_BOUNDARY := Color("#404040")  # Subtle gray
const COLOR_UNLOADED := Color("#000000")  # Black
const COLOR_ITEM := Color("#ffff00")  # Bright yellow (discovered items)
const COLOR_ENTITY := Color("#ff00ff")  # Magenta (entities/enemies)

## Aura colors (semi-transparent glow behind minimap sprites)
const COLOR_AURA_ENTITY := Color(1.0, 0.0, 0.0, 0.45)  # Red, semi-transparent
const COLOR_AURA_ITEM := Color(1.0, 1.0, 0.0, 0.45)  # Yellow, semi-transparent

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

## Dirty flag - needs full content redraw (tiles + trail + sprites)
var content_dirty: bool = true

## Cached player position for sprite overlay (updated per turn)
var cached_player_pos: Vector2i = Vector2i(-99999, -99999)

## Current scale factor (for resolution-based UI scaling)
var current_scale_factor: int = 0

## Last player position for incremental rendering
var last_player_pos: Vector2i = Vector2i(-99999, -99999)

## Zoom level: 0 = 2 tiles/pixel, 1 = 1 tile/pixel (default), 2-4 = N pixels/tile
var zoom_level: int = 1

## Pre-cached sprite icons at each zoom size {zoom_level: Image}
var player_sprite_cache: Dictionary = {}
var entity_sprite_cache: Dictionary = {}  # {entity_type: {zoom_level: Image}}
var item_sprite_cache: Dictionary = {}  # {item_id: {zoom_level: Image}}
var exit_hole_sprite_cache: Dictionary = {}  # {zoom_level: Image}

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Create images and texture
	map_image = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	base_map_image = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	map_texture = ImageTexture.create_from_image(map_image)
	map_texture_rect.texture = map_texture

	# Initialize trail buffer
	player_trail.resize(TRAIL_LENGTH)
	for i in range(TRAIL_LENGTH):
		player_trail[i] = Vector2i(-99999, -99999)  # Invalid position

	# Pre-cache minimap sprite icons
	_cache_player_sprite()
	_cache_entity_sprites()

	# Clear cache when initial chunks finish loading
	if ChunkManager:
		ChunkManager.initial_load_completed.connect(_on_initial_load_completed)

	# Connect to container size changes for dynamic scaling
	var container = map_texture_rect.get_parent()
	if container:
		container.resized.connect(_on_container_resized)
		# Set initial scale (deferred to ensure container has size)
		call_deferred("_update_texture_scale")


func _exit_tree() -> void:
	# Disconnect autoload signals to prevent memory leaks on scene reload
	if ChunkManager and ChunkManager.initial_load_completed.is_connected(_on_initial_load_completed):
		ChunkManager.initial_load_completed.disconnect(_on_initial_load_completed)


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
		content_dirty = true

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
	"""Full render of minimap. At zoom >= 1, each tile = N×N pixels.
	At zoom 0, 2×2 tiles map to 1 pixel (zoomed out overview)."""
	# Clear to unloaded color
	map_image.fill(COLOR_UNLOADED)

	# Get GridMap reference for direct tile queries
	var grid_map: GridMap = grid.grid_map
	if not grid_map:
		Log.warn(Log.Category.SYSTEM, "Minimap: No GridMap found on grid node")
		return

	if zoom_level == 0:
		# ZOOMED OUT: 2 tiles per pixel, check 2×2 area per pixel
		# Shows 512×512 tiles in 256×256 pixels
		var view_radius := MAP_SIZE  # 256 tiles each direction = 512 total
		var min_tile := player_pos - Vector2i(view_radius, view_radius)

		for py in range(MAP_SIZE):
			for px in range(MAP_SIZE):
				# Map pixel to 2×2 tile area
				var world_x := min_tile.x + px * 2
				var world_y := min_tile.y + py * 2

				# Check all 4 tiles in the 2×2 area — use best info available
				# Priority: wall > floor > unloaded (prevents blank chunk artifacts)
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

				map_image.set_pixelv(Vector2i(px, py), color)
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

				# Fill N×N pixel block for this tile
				var tile_pos := Vector2i(x, y)
				var screen_origin := _world_to_screen(tile_pos, player_pos)
				for ppy in range(zoom_level):
					for ppx in range(zoom_level):
						var pixel := screen_origin + Vector2i(ppx, ppy)
						if _is_valid_screen_pos(pixel):
							map_image.set_pixelv(pixel, color)

	# Draw trail onto base map
	_draw_trail(player_pos)

	# Save base map (tiles + trail) for per-frame sprite compositing
	base_map_image.copy_from(map_image)
	cached_player_pos = player_pos

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

	# Draw exit holes
	_draw_exit_holes(player_pos)

	# Draw entities
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
		map_image.set_pixelv(screen_pos, color)

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

	for entity_pos in entity_positions:
		var distance: float = Vector2(entity_pos).distance_to(Vector2(player_pos))
		if distance > perception_range:
			continue

		var screen_pos := _world_to_screen(entity_pos, player_pos)
		if not _is_valid_screen_pos(screen_pos):
			continue

		# Try to blit sprite icon
		var entity = grid.entity_renderer.get_entity_at(entity_pos)
		var drew_sprite := false
		if entity:
			var etype: String = entity.entity_type
			if entity_sprite_cache.has(etype) and entity_sprite_cache[etype].has(zoom_level):
				_blit_sprite(entity_sprite_cache[etype][zoom_level], screen_pos, COLOR_AURA_ENTITY)
				drew_sprite = true

		if not drew_sprite:
			# Fallback: colored pixel marker
			var marker_size := maxi(2, zoom_level + 1)
			for dy in range(marker_size):
				for dx in range(marker_size):
					var pixel := screen_pos + Vector2i(dx, dy)
					if _is_valid_screen_pos(pixel):
						map_image.set_pixelv(pixel, COLOR_ENTITY)

func _draw_exit_holes(player_pos: Vector2i) -> void:
	"""Draw exit hole sprites on minimap at EXIT_STAIRS tile positions."""
	if not grid:
		return

	# Lazy-cache exit hole sprite
	if exit_hole_sprite_cache.is_empty():
		_cache_exit_hole_sprite()

	for exit_pos in grid.exit_tile_positions:
		var screen_pos := _world_to_screen(exit_pos, player_pos)
		if not _is_valid_screen_pos(screen_pos):
			continue

		if exit_hole_sprite_cache.has(zoom_level):
			_blit_sprite(exit_hole_sprite_cache[zoom_level], screen_pos)
		else:
			# Fallback: dark pixel
			var marker_size := maxi(2, zoom_level + 1)
			for dy in range(marker_size):
				for dx in range(marker_size):
					var pixel := screen_pos + Vector2i(dx, dy)
					if _is_valid_screen_pos(pixel):
						map_image.set_pixelv(pixel, Color(0.1, 0.1, 0.1))

func _cache_exit_hole_sprite() -> void:
	"""Cache exit hole sprite at all zoom sizes."""
	var texture := load("res://assets/textures/entities/exit_hole.png")
	if not texture:
		return
	var base_image: Image = texture.get_image()
	if not base_image:
		return

	for zoom in range(MIN_ZOOM, MAX_ZOOM + 1):
		var target_size: int = SPRITE_SIZES.get(zoom, 7)
		var resized := base_image.duplicate()
		resized.resize(target_size, target_size, Image.INTERPOLATE_NEAREST)
		exit_hole_sprite_cache[zoom] = resized

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
	"""Load entity textures and pre-cache resized versions for each zoom level."""
	var entity_textures := {
		"bacteria_spawn": "res://assets/textures/entities/bacteria_spawn.png",
		"bacteria_motherload": "res://assets/textures/entities/bacteria_motherload.png",
		"bacteria_spreader": "res://assets/textures/entities/bacteria_spreader.png",
		"smiler": "res://assets/textures/entities/smiler.png",
	}

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
