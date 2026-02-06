class_name MapOverlayRenderer
extends Control
## Center map panel for the map overlay
##
## Renders a 512x512 north-up map from ChunkManager.tile_cache.
## Fog of war: tiles not in cache render as black.
## Supports zoom levels 0-5 and position highlighting.

# ============================================================================
# CONSTANTS
# ============================================================================

const MAP_SIZE := 512  # Internal image size in pixels

## Same color palette as minimap (colorblind-safe)
const COLOR_WALKABLE := Color("#8a8a8a")
const COLOR_WALL := Color("#1a3a52")
const COLOR_UNLOADED := Color("#000000")
const COLOR_PLAYER := Color("#00d9ff")
const COLOR_TRAIL_START := Color(0.9, 0.0, 1.0, 0.3)
const COLOR_TRAIL_END := Color(0.9, 0.0, 1.0, 1.0)
const COLOR_ITEM := Color("#ffff00")
const COLOR_ENTITY := Color("#ff00ff")
const COLOR_MARKER := Color("#00ff88")
const COLOR_HIGHLIGHT := Color("#ffdd00")
const COLOR_EXIT := Color("#d4c000")

## Aura colors for entity types
const COLOR_AURA_HOSTILE := Color(1.0, 0.0, 0.0, 0.45)
const COLOR_AURA_NEUTRAL := Color(0.0, 0.5, 1.0, 0.45)
const COLOR_AURA_EXIT := Color(0.85, 0.75, 0.0, 0.45)

## Zoom config: index → pixels per tile (0 = 2 tiles/pixel via special logic)
const ZOOM_LEVELS := [0, 1, 2, 3, 4, 5]
const DEFAULT_ZOOM := 1
const MIN_ZOOM := 0
const MAX_ZOOM := 5

## Sprite sizes per zoom level (pixels)
const SPRITE_SIZES := {0: 3, 1: 5, 2: 7, 3: 9, 4: 11, 5: 13}

# ============================================================================
# STATE
# ============================================================================

var map_image: Image
var map_texture: ImageTexture
var texture_rect: TextureRect

var zoom_level: int = DEFAULT_ZOOM
var view_center: Vector2i = Vector2i.ZERO  # World tile position at center of view

## References (set by show_map)
var player_ref: Node = null
var grid_ref: Node = null

## Highlight state
var highlight_pos: Vector2i = Vector2i(-999999, -999999)
var highlight_timer: float = 0.0
var _is_highlighting: bool = false

## Minimap trail data (borrowed from minimap on render)
var _trail_data: Array[Vector2i] = []
var _trail_valid_count: int = 0

## Sprite caches (populated on first render)
var _player_sprite_cache: Dictionary = {}
var _entity_sprite_cache: Dictionary = {}
var _item_sprite_cache: Dictionary = {}
var _sprites_cached: bool = false

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Create image and texture
	map_image = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	map_texture = ImageTexture.create_from_image(map_image)

	# Create TextureRect to display the map (no rotation — fixed north-up)
	texture_rect = TextureRect.new()
	texture_rect.texture = map_texture
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(texture_rect)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return

	# Animate highlight pulse
	if _is_highlighting:
		highlight_timer += delta
		render_map()

# ============================================================================
# PUBLIC API
# ============================================================================

func show_map(player: Node, grid: Node) -> void:
	"""Initialize and render the map."""
	player_ref = player
	grid_ref = grid

	if player:
		view_center = player.grid_position

	# Grab trail data from minimap
	_grab_trail_data()

	# Cache sprites on first use
	if not _sprites_cached:
		_cache_sprites()
		_sprites_cached = true

	render_map()

func change_zoom(direction: int) -> void:
	"""Change zoom level by direction (+1 or -1)."""
	var new_zoom := clampi(zoom_level + direction, MIN_ZOOM, MAX_ZOOM)
	if new_zoom != zoom_level:
		zoom_level = new_zoom
		render_map()

func highlight_position(world_pos: Vector2i) -> void:
	"""Pan view to position and draw highlight ring."""
	view_center = world_pos
	highlight_pos = world_pos
	highlight_timer = 0.0
	_is_highlighting = true
	render_map()

func clear_highlight() -> void:
	"""Remove highlight and re-center on player."""
	_is_highlighting = false
	highlight_pos = Vector2i(-999999, -999999)
	if player_ref:
		view_center = player_ref.grid_position
	render_map()

# ============================================================================
# RENDERING
# ============================================================================

func render_map() -> void:
	"""Full render of the map from tile_cache."""
	if not ChunkManager:
		return

	map_image.fill(COLOR_UNLOADED)
	var tile_cache: Dictionary = ChunkManager.tile_cache

	if zoom_level == 0:
		_render_zoom_0(tile_cache)
	else:
		_render_zoomed(tile_cache)

	# Draw trail
	_draw_trail()

	# Draw markers
	_draw_markers()

	# Draw items
	_draw_items()

	# Draw entities
	_draw_entities()

	# Draw player
	_draw_player()

	# Draw highlight
	if _is_highlighting:
		_draw_highlight_ring()

	# Update texture
	map_texture.update(map_image)

func _render_zoom_0(tile_cache: Dictionary) -> void:
	"""Render at zoom 0: 2 tiles per pixel (covers 1024x1024 tile area)."""
	var view_radius := MAP_SIZE  # 512 pixels * 2 tiles/pixel = 1024 tiles
	var min_tile := view_center - Vector2i(view_radius, view_radius)

	for py in range(MAP_SIZE):
		for px in range(MAP_SIZE):
			var world_x := min_tile.x + px * 2
			var world_y := min_tile.y + py * 2

			# Sample 2x2 area — prefer wall if any wall found
			var has_wall := false
			var has_floor := false
			for ty in range(2):
				for tx in range(2):
					var pos := Vector2i(world_x + tx, world_y + ty)
					if tile_cache.has(pos):
						var tile_type: int = tile_cache[pos]
						if SubChunk.is_wall_type(tile_type):
							has_wall = true
						elif SubChunk.is_floor_type(tile_type):
							has_floor = true

			if has_wall:
				map_image.set_pixelv(Vector2i(px, py), COLOR_WALL)
			elif has_floor:
				map_image.set_pixelv(Vector2i(px, py), COLOR_WALKABLE)
			# else: remains COLOR_UNLOADED (black = fog of war)

func _render_zoomed(tile_cache: Dictionary) -> void:
	"""Render at zoom 1-5: N pixels per tile."""
	var half_size := MAP_SIZE / 2
	var view_radius := MAP_SIZE / (2 * zoom_level)
	var min_tile := view_center - Vector2i(view_radius, view_radius)
	var max_tile := view_center + Vector2i(view_radius, view_radius)

	for y in range(min_tile.y, max_tile.y):
		for x in range(min_tile.x, max_tile.x):
			var pos := Vector2i(x, y)
			if not tile_cache.has(pos):
				continue  # Fog of war (already black)

			var tile_type: int = tile_cache[pos]
			var color: Color
			if SubChunk.is_wall_type(tile_type):
				color = COLOR_WALL
			elif SubChunk.is_floor_type(tile_type):
				color = COLOR_WALKABLE
			else:
				continue  # Unknown tile, leave as black

			var screen := _world_to_screen(pos)
			for ppy in range(zoom_level):
				for ppx in range(zoom_level):
					var pixel := screen + Vector2i(ppx, ppy)
					if _is_valid(pixel):
						map_image.set_pixelv(pixel, color)

# ============================================================================
# OVERLAY LAYERS
# ============================================================================

func _draw_trail() -> void:
	"""Draw player movement trail from minimap data."""
	if _trail_valid_count == 0:
		return

	for i in range(_trail_data.size()):
		var trail_pos: Vector2i = _trail_data[i]
		if trail_pos.x == -99999:
			continue

		var screen := _world_to_screen(trail_pos)
		if not _is_valid(screen):
			continue

		var age := clampf(float(i) / float(_trail_valid_count), 0.0, 1.0)
		var color := COLOR_TRAIL_START.lerp(COLOR_TRAIL_END, age)

		# At higher zoom, draw larger trail dots
		if zoom_level <= 1:
			map_image.set_pixelv(screen, color)
		else:
			for dy in range(zoom_level):
				for dx in range(zoom_level):
					var pixel := screen + Vector2i(dx, dy)
					if _is_valid(pixel):
						map_image.set_pixelv(pixel, color)

func _draw_markers() -> void:
	"""Draw map markers from MapMarkerManager."""
	var marker_mgr = Engine.get_singleton("MapMarkerManager") if Engine.has_singleton("MapMarkerManager") else null
	if not marker_mgr:
		# Try autoload path
		marker_mgr = _get_autoload("MapMarkerManager")
	if not marker_mgr:
		return

	var level_id := 0
	var current_level = LevelManager.get_current_level()
	if current_level:
		level_id = current_level.level_id

	var markers = marker_mgr.get_markers(level_id)
	for marker in markers:
		var pos: Vector2i = marker["position"]
		var screen := _world_to_screen(pos)
		if not _is_valid(screen):
			continue

		# Draw marker as a diamond shape
		var size := maxi(3, zoom_level * 2 + 1)
		var half := size / 2
		for dy in range(-half, half + 1):
			for dx in range(-half, half + 1):
				if absi(dx) + absi(dy) <= half:
					var pixel := screen + Vector2i(dx, dy)
					if _is_valid(pixel):
						map_image.set_pixelv(pixel, COLOR_MARKER)

func _draw_items() -> void:
	"""Draw discovered items within perception range."""
	if not grid_ref or not grid_ref.item_renderer:
		return

	var perception_range: float = 15.0
	if player_ref and player_ref.stats:
		perception_range = 15.0 + (player_ref.stats.perception * 5.0)

	var player_pos: Vector2i = view_center if not player_ref else player_ref.grid_position
	var discovered_items = grid_ref.item_renderer.get_discovered_item_positions()

	for item_pos in discovered_items:
		var distance: float = Vector2(item_pos).distance_to(Vector2(player_pos))
		if distance > perception_range:
			continue

		var screen := _world_to_screen(item_pos)
		if not _is_valid(screen):
			continue

		# Try sprite icon first (lazily cache on first encounter)
		var drew_sprite := false
		var item_data = grid_ref.item_renderer.get_item_at(item_pos)
		if item_data:
			var item_id: String = item_data.get("item_id", "")
			if item_id != "":
				if not _item_sprite_cache.has(item_id):
					_cache_item_sprite(item_id)
				if _item_sprite_cache.has(item_id) and _item_sprite_cache[item_id].has(zoom_level):
					_blit_sprite(_item_sprite_cache[item_id][zoom_level], screen)
					drew_sprite = true

		if not drew_sprite:
			var marker_size := maxi(2, zoom_level + 1)
			for dy in range(marker_size):
				for dx in range(marker_size):
					var pixel := screen + Vector2i(dx, dy)
					if _is_valid(pixel):
						map_image.set_pixelv(pixel, COLOR_ITEM)

func _draw_entities() -> void:
	"""Draw entities within perception range."""
	if not grid_ref or not grid_ref.entity_renderer:
		return

	var perception_range: float = 15.0
	if player_ref and player_ref.stats:
		perception_range = 15.0 + (player_ref.stats.perception * 5.0)

	var player_pos: Vector2i = view_center if not player_ref else player_ref.grid_position
	var entity_positions = grid_ref.entity_renderer.get_all_entity_positions()

	for entity_pos in entity_positions:
		var distance: float = Vector2(entity_pos).distance_to(Vector2(player_pos))
		if distance > perception_range:
			continue

		var screen := _world_to_screen(entity_pos)
		if not _is_valid(screen):
			continue

		var entity = grid_ref.entity_renderer.get_entity_at(entity_pos)
		var drew_sprite := false
		if entity:
			var etype: String = entity.entity_type
			if _entity_sprite_cache.has(etype) and _entity_sprite_cache[etype].has(zoom_level):
				_blit_sprite(_entity_sprite_cache[etype][zoom_level], screen)
				drew_sprite = true

		if not drew_sprite:
			# Color-coded fallback
			var color := COLOR_ENTITY
			if entity and entity.is_exit:
				color = COLOR_EXIT
			elif entity and not entity.hostile:
				color = Color("#0088ff")
			var marker_size := maxi(2, zoom_level + 1)
			for dy in range(marker_size):
				for dx in range(marker_size):
					var pixel := screen + Vector2i(dx, dy)
					if _is_valid(pixel):
						map_image.set_pixelv(pixel, color)

func _draw_player() -> void:
	"""Draw player position marker."""
	if not player_ref:
		return

	var screen := _world_to_screen(player_ref.grid_position)
	if not _is_valid(screen):
		return

	# Try sprite icon
	if _player_sprite_cache.has(zoom_level):
		_blit_sprite(_player_sprite_cache[zoom_level], screen)
	else:
		# Fallback: bright cyan diamond
		var size := maxi(3, zoom_level * 2 + 1)
		var half := size / 2
		for dy in range(-half, half + 1):
			for dx in range(-half, half + 1):
				if absi(dx) + absi(dy) <= half:
					var pixel := screen + Vector2i(dx, dy)
					if _is_valid(pixel):
						map_image.set_pixelv(pixel, COLOR_PLAYER)

func _draw_highlight_ring() -> void:
	"""Draw pulsing highlight ring at highlight_pos."""
	var screen := _world_to_screen(highlight_pos)
	if not _is_valid(screen):
		return

	# Pulsing alpha (0.5 to 1.0 over 0.8s)
	var pulse := 0.5 + 0.5 * sin(highlight_timer * TAU / 0.8)
	var color := Color(COLOR_HIGHLIGHT, pulse)

	# Draw ring (hollow circle)
	var radius := maxi(4, zoom_level * 3 + 2)
	var inner_sq := (radius - 1) * (radius - 1)
	var outer_sq := (radius + 1) * (radius + 1)
	for dy in range(-radius - 1, radius + 2):
		for dx in range(-radius - 1, radius + 2):
			var dist_sq := dx * dx + dy * dy
			if dist_sq >= inner_sq and dist_sq <= outer_sq:
				var pixel := screen + Vector2i(dx, dy)
				if _is_valid(pixel):
					var existing := map_image.get_pixelv(pixel)
					var blended := existing.lerp(Color(color, 1.0), color.a)
					map_image.set_pixelv(pixel, blended)

# ============================================================================
# COORDINATE CONVERSION
# ============================================================================

func _world_to_screen(world_pos: Vector2i) -> Vector2i:
	"""Convert world tile position to screen pixel (north-up, no rotation)."""
	var half_size := MAP_SIZE / 2
	var relative := world_pos - view_center
	if zoom_level == 0:
		return Vector2i(half_size + relative.x / 2, half_size + relative.y / 2)
	return Vector2i(half_size + relative.x * zoom_level, half_size + relative.y * zoom_level)

func _screen_to_world(screen_pos: Vector2i) -> Vector2i:
	"""Convert screen pixel to world tile position."""
	var half_size := MAP_SIZE / 2
	var relative := screen_pos - Vector2i(half_size, half_size)
	if zoom_level == 0:
		return view_center + relative * 2
	return view_center + relative / zoom_level

func _is_valid(pos: Vector2i) -> bool:
	"""Check if screen position is within image bounds."""
	return pos.x >= 0 and pos.x < MAP_SIZE and pos.y >= 0 and pos.y < MAP_SIZE

# ============================================================================
# SPRITE CACHING
# ============================================================================

func _cache_sprites() -> void:
	"""Cache player and entity sprites for all zoom levels."""
	# Player sprite
	var player_path := "res://assets/sprites/player/hazmat_suit.png"
	if ResourceLoader.exists(player_path):
		var tex = load(player_path) as Texture2D
		if tex:
			var src := tex.get_image()
			if src:
				if src.is_compressed():
					src.decompress()
				for zoom in SPRITE_SIZES:
					var icon_size: int = SPRITE_SIZES[zoom]
					var resized := src.duplicate()
					resized.resize(icon_size, icon_size, Image.INTERPOLATE_NEAREST)
					_player_sprite_cache[zoom] = resized

	# Entity sprites (from EntityRenderer)
	var entity_textures: Dictionary = EntityRenderer.ENTITY_TEXTURES
	for entity_type in entity_textures:
		var path: String = entity_textures[entity_type]
		if not ResourceLoader.exists(path):
			continue
		var tex = load(path) as Texture2D
		if not tex:
			continue
		var src := tex.get_image()
		if not src:
			continue
		if src.is_compressed():
			src.decompress()
		_entity_sprite_cache[entity_type] = {}
		for zoom in SPRITE_SIZES:
			var icon_size: int = SPRITE_SIZES[zoom]
			var resized := src.duplicate()
			resized.resize(icon_size, icon_size, Image.INTERPOLATE_NEAREST)
			_entity_sprite_cache[entity_type][zoom] = resized

func _cache_item_sprite(item_id: String) -> void:
	"""Lazily cache an item sprite."""
	if _item_sprite_cache.has(item_id):
		return
	if not grid_ref or not grid_ref.item_renderer:
		return
	var item_resource = grid_ref.item_renderer._get_item_by_id(item_id)
	if not item_resource or not item_resource.ground_sprite:
		return
	var src: Image = item_resource.ground_sprite.get_image()
	if not src:
		return
	if src.is_compressed():
		src.decompress()
	_item_sprite_cache[item_id] = {}
	for zoom in SPRITE_SIZES:
		var icon_size: int = SPRITE_SIZES[zoom]
		var resized: Image = src.duplicate() as Image
		resized.resize(icon_size, icon_size, Image.INTERPOLATE_NEAREST)
		_item_sprite_cache[item_id][zoom] = resized

func _blit_sprite(sprite_image: Image, center: Vector2i) -> void:
	"""Blit a sprite image centered on a screen position (no rotation needed)."""
	var size := sprite_image.get_width()
	var half := size / 2

	for dy in range(size):
		for dx in range(size):
			var pixel_color := sprite_image.get_pixel(dx, dy)
			if pixel_color.a > 0.1:
				var dest := center + Vector2i(dx - half, dy - half)
				if _is_valid(dest):
					map_image.set_pixelv(dest, pixel_color)

# ============================================================================
# HELPERS
# ============================================================================

func _grab_trail_data() -> void:
	"""Copy trail data from minimap for rendering."""
	_trail_data.clear()
	_trail_valid_count = 0

	# Find minimap via game node
	var game_node = get_node_or_null("/root/Game")
	if not game_node:
		return
	var minimap = game_node.get("minimap")
	if not minimap:
		return

	_trail_data = minimap.player_trail.duplicate()
	_trail_valid_count = minimap.trail_valid_count

func _get_autoload(autoload_name: String) -> Node:
	"""Get an autoload by name."""
	return get_node_or_null("/root/" + autoload_name)
