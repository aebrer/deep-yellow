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

## Sprite pixel snap: same idea for entities/items/decals (Sprite3D + StandardMaterial3D
## paths that don't run the PSX shaders). Textures are downscaled to N px wide at
## assignment; 0 = off. Default: PSX.
static var sprite_pixel_snap: float = 128.0
static var _sprite_snap_cache: Dictionary = {}

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
	var nw: int = clampi(target_per_frame * maxi(frames, 1), 1, w)
	var nh: int = maxi(1, int(round(h * float(nw) / float(w))))
	img.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
	var snapped := ImageTexture.create_from_image(img)
	_sprite_snap_cache[key] = snapped
	return snapped

## Assigns a pixel-snapped texture to a Sprite3D or MeshInstance3D (decal),
## remembering the source so toggling the snap level can re-apply.
static func apply_snap_texture(node: Node, texture: Texture2D, frames: int = 1) -> void:
	node.set_meta("snap_src_tex", texture)
	if node is MeshInstance3D:
		_apply_snap_to_mesh(node as MeshInstance3D)
	else:
		node.set("texture", snap_texture(texture, frames))

static func _apply_snap_to_mesh(mesh_instance: MeshInstance3D) -> void:
	var src: Texture2D = mesh_instance.get_meta("snap_src_tex")
	var mat: StandardMaterial3D = null
	if mesh_instance.mesh is QuadMesh:
		mat = (mesh_instance.mesh as QuadMesh).material as StandardMaterial3D
	if mat and mat.albedo_texture:
		mat.albedo_texture = snap_texture(src)

static func _refresh_snap_nodes(node: Node) -> void:
	if node.has_meta("snap_src_tex"):
		if node is MeshInstance3D:
			_apply_snap_to_mesh(node as MeshInstance3D)
		elif node is AnimatedSprite3D:
			_resnap_animated_sheet(node as AnimatedSprite3D)
		elif node is Sprite3D:
			node.set("texture", snap_texture(node.get_meta("snap_src_tex")))
	for child in node.get_children():
		_refresh_snap_nodes(child)

## Re-point every AtlasTexture frame of an AnimatedSprite3D at the currently
## snapped variant of its source sheet (sprite_frames are mutated in place).
static func _resnap_animated_sheet(sprite: AnimatedSprite3D) -> void:
	var src: Texture2D = sprite.get_meta("snap_src_tex")
	var frames: int = int(sprite.get_meta("snap_frames"))
	var snapped_sheet := snap_texture(src, frames)
	var sheet: SpriteFrames = sprite.sprite_frames
	for anim_name in sheet.get_animation_names():
		for i in sheet.get_frame_count(anim_name):
			var frame_tex = sheet.get_frame_texture(anim_name, i)
			if frame_tex is AtlasTexture:
				frame_tex.atlas = snapped_sheet

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
