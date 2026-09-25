extends Node
## Global utility functions
##
## Shared math and helper functions used across the codebase.
## Autoloaded as "Utilities" for global access.

func _ready() -> void:
	# Global shader uniforms must be registered once per session (Godot requirement).
	RenderingServer.global_shader_parameter_add(
			"pixel_snap_resolution", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 128.0
	)

# ============================================================================
# DEBUG FLAGS
# ============================================================================

## WARNING: Set to true to enable debug item spawning (one of each item in first chunk)
## This should be FALSE for release builds!
const DEBUG_SPAWN_ALL_ITEMS := false

## WARNING: Set to an entity_type string to spawn that entity next to the player for testing
## Set to "" (empty string) to disable. This should be "" for release builds!
const DEBUG_SPAWN_ENTITY := ""

# ============================================================================
# SETTINGS
# ============================================================================

## Movement smoothing (tween between grid positions)
## Can be toggled off for motion sickness or preference for instant snapping
static var movement_smoothing: bool = true

## Texture pixel snap: quantizes albedo UVs to an N-pixel grid per texture repeat,
## giving hi-res textures a chunky PSX look. 0 = off (crisp), 128 = PSX, 64 = chunky.
## Default: PSX.
static var texture_pixel_snap: float = 128.0

static func set_texture_pixel_snap(pixels: float) -> void:
	texture_pixel_snap = pixels
	RenderingServer.global_shader_parameter_set("pixel_snap_resolution", pixels)

## Sprite pixel snap: same idea for entities/items (Sprite3D paths that don't run
## the PSX shaders). Textures are downscaled to N px wide at assignment; 0 = off.
## Default: PSX.
static var sprite_pixel_snap: float = 128.0
static var _sprite_snap_cache: Dictionary = {}

## Which texture dimension a billboard's world size is measured against.
enum SnapRef { WIDTH, LONGEST_SIDE }

static func set_sprite_pixel_snap(pixels: float) -> void:
	sprite_pixel_snap = pixels
	_sprite_snap_cache.clear()
	_refresh_snap_nodes(Engine.get_main_loop().root)

## Returns a pixel-snapped variant of tex (downscaled to sprite_pixel_snap px wide).
## frames: number of horizontal frames in the sheet (sprite sheets snap per-frame).
## Textures without a resource_path (runtime-generated) are returned unchanged.
static func snap_texture(tex: Texture2D, frames: int = 1) -> Texture2D:
	if tex == null or sprite_pixel_snap <= 0.0:
		return tex
	var path: String = tex.resource_path
	if path == "":
		return tex
	var w: int = tex.get_width()
	var h: int = tex.get_height()
	var target_per_frame: int = int(sprite_pixel_snap)
	if int(float(w) / maxi(frames, 1)) <= target_per_frame:
		return tex
	var key := "%s@%d" % [path, target_per_frame]
	if _sprite_snap_cache.has(key):
		return _sprite_snap_cache[key]
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	if img.is_compressed():
		# Imported textures can hand back VRAM-compressed data, which cannot be
		# resized in place — decompress to RGBA first or the downscale silently no-ops.
		var err := img.decompress()
		if err != OK:
			push_warning("Utilities: cannot decompress %s for pixel snap (err %d)" % [path, err])
			return tex
	var nw: int = clampi(target_per_frame * maxi(frames, 1), 1, w)
	var nh: int = maxi(1, int(round(h * float(nw) / float(w))))
	img.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
	var snapped := ImageTexture.create_from_image(img)
	_sprite_snap_cache[key] = snapped
	return snapped

## Assign a pixel-snapped texture to a billboard and pin its world-space size.
##
## Sprite3D sizes itself from its texture (world size = texture size * pixel_size),
## so pixel_size MUST be derived from the SNAPPED texture. Deriving it from the
## source texture shrinks the sprite by the snap ratio (512px sheet at PSX = 1/4 size).
## AnimatedSprite3D is a sibling of Sprite3D (both extend SpriteBase3D) and has no
## texture property of its own — its frames are re-cut instead.
##
## world_size: desired world-space size of the sprite's reference side.
static func apply_snap_sprite(
		sprite: SpriteBase3D, texture: Texture2D, world_size: float,
		frames: int = 1, ref: SnapRef = SnapRef.WIDTH
) -> void:
	sprite.set_meta("snap_src_tex", texture)
	sprite.set_meta("snap_frames", frames)
	sprite.set_meta("snap_world_size", world_size)
	sprite.set_meta("snap_ref", ref)
	_apply_snap_to_sprite(sprite)

## Swap the texture on an already-snapped billboard (light on/off states) while
## keeping the world size apply_snap_sprite() pinned.
static func swap_snap_sprite(sprite: Sprite3D, texture: Texture2D) -> void:
	if not sprite.has_meta("snap_world_size"):
		sprite.set("texture", snap_texture(texture))
		return
	sprite.set_meta("snap_src_tex", texture)
	_apply_snap_to_sprite(sprite)

## Swap the whole animation on an already-snapped animated billboard.
##
## The light fixtures need this: a fixture's on and off states are separate atlas strips,
## so a flicker is a SpriteFrames swap, not a texture swap. Sprite3D and AnimatedSprite3D
## are siblings, so a caller holding a SpriteBase3D cannot use swap_snap_sprite() at all,
## and assigning sprite_frames alone would leave the world size pinned from the old sheet
## and the frame regions cut for the old atlas' pixel size.
static func swap_snap_frames(sprite: AnimatedSprite3D, frames: SpriteFrames,
		sheet: Texture2D, frame_count: int) -> void:
	if not sprite.has_meta("snap_world_size"):
		push_warning("swap_snap_frames: sprite has no snap state — call apply_snap_sprite() first")
		return
	sprite.sprite_frames = frames
	sprite.set_meta("snap_src_tex", sheet)
	sprite.set_meta("snap_frames", frame_count)
	_apply_snap_to_sprite(sprite)

static func _apply_snap_to_sprite(sprite: SpriteBase3D) -> void:
	var frames: int = maxi(1, int(sprite.get_meta("snap_frames")))
	var snapped := snap_texture(sprite.get_meta("snap_src_tex"), frames)
	if sprite is AnimatedSprite3D:
		_resnap_animated_sheet(sprite as AnimatedSprite3D, snapped, frames)
	else:
		sprite.set("texture", snapped)
	# Reference side in the snapped texture's own pixels (per frame for sheets)
	var ref_px: int = maxi(1, snapped.get_width() / frames)
	if int(sprite.get_meta("snap_ref")) == SnapRef.LONGEST_SIDE:
		ref_px = maxi(ref_px, snapped.get_height())
	sprite.pixel_size = float(sprite.get_meta("snap_world_size")) / float(ref_px)

static func _refresh_snap_nodes(node: Node) -> void:
	if node.has_meta("snap_world_size"):
		_apply_snap_to_sprite(node as SpriteBase3D)
	for child in node.get_children():
		_refresh_snap_nodes(child)

## Re-point every AtlasTexture frame of an AnimatedSprite3D at a snapped variant of
## its source sheet AND re-cut the regions for that sheet's pixel size: frame
## regions live in the atlas' own pixel space, so they have to move with the atlas
## (re-pointing without re-cutting puts frames 1..N outside a downscaled sheet).
static func _resnap_animated_sheet(sprite: AnimatedSprite3D, snapped_sheet: Texture2D, frames: int) -> void:
	var sheet: SpriteFrames = sprite.sprite_frames
	if sheet == null:
		return
	var frame_width: int = maxi(1, snapped_sheet.get_width() / frames)
	var frame_height: int = snapped_sheet.get_height()
	for anim_name in sheet.get_animation_names():
		for i in sheet.get_frame_count(anim_name):
			var frame_tex = sheet.get_frame_texture(anim_name, i)
			if frame_tex is AtlasTexture:
				frame_tex.atlas = snapped_sheet
				frame_tex.region = Rect2(i * frame_width, 0, frame_width, frame_height)

## Auto-explore settings
static var auto_explore_speed: float = 10.0  # turns per second
static var auto_explore_hp_threshold: float = 0.5  # stop below this % of max HP
static var auto_explore_sanity_threshold: float = 0.5  # stop below this % of max sanity
## Enemy threat threshold: stop for enemies with threat_level >= this value
## 0 = all hostiles, 1 = weak+, 2 = moderate+, 3 = dangerous+, 4 = elite+, 5 = boss only, 6 = never
static var auto_explore_enemy_threat_threshold: int = 2  # default: stop for moderate+ threats
static var auto_explore_stop_for_items: bool = true
static var auto_explore_stop_on_damage: bool = false
static var auto_explore_stop_at_stairs: bool = true

# ============================================================================
# MATH UTILITIES
# ============================================================================

static func bankers_round(value: float) -> float:
	"""Round using banker's rounding (round half to even).

	Unlike roundf() which rounds 0.5 away from zero (biased upward for positive),
	banker's rounding rounds 0.5 to the nearest even integer, giving an unbiased
	distribution over many values. This is Python's default round() behavior.

	Examples:
		0.5 → 0 (rounds to even)
		1.5 → 2 (rounds to even)
		2.5 → 2 (rounds to even)
		3.5 → 4 (rounds to even)
		2.4 → 2, 2.6 → 3 (normal rounding)
	"""
	var floored = floorf(value)
	var frac = value - floored

	if frac < 0.5:
		return floored
	elif frac > 0.5:
		return floored + 1.0
	else:
		# Exactly 0.5 - round to even
		if int(floored) % 2 == 0:
			return floored  # Already even, round down
		else:
			return floored + 1.0  # Odd, round up to even
