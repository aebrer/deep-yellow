extends Node
class_name AnimatedBillboard

## Referenced as a preloaded script rather than through the Utilities autoload on purpose:
## autoload identifiers do not resolve when a script is loaded outside a running scene tree
## (godot --script, --check-only), which would stop the headless regression check in
## scripts/tools/verify_sprite_snap.gd from exercising this code at all. apply_snap_sprite()
## is a static function, so calling it on the script is the same call.
const UtilitiesScript := preload("res://scripts/autoload/utilities.gd")

## Shared factory for billboarded sprite animations built from a horizontal atlas strip.
##
## Both renderers need this: entities declare sheets in EntityRenderer.ENTITY_SPRITESHEETS
## and items in ItemRenderer.ITEM_SPRITESHEETS. Before this existed the construction lived
## inside EntityRenderer._create_animated_billboard() and items had no animated path at all,
## so animating an item meant copying ~30 lines of billboard setup.
##
## Frames are AtlasTexture regions of one strip, which is what barrel_fire already ships
## (assets/textures/entities/barrel_fire_spritesheet.png). Idle-motion strips are built by
## _claude_scripts/sprite_pipeline/assemble_frames.py, which bakes the playback order into
## the strip — a 4-frame idle loop is typically base, sway-left, sway-right, sway-left, so
## the cycle closes with no pop from only two generated frames.

## Build, snap, and start an animated billboard.
##
## Args:
##     sheet_path: res:// path to the horizontal strip
##     frame_count: frames in the strip (strip width / frame_count = frame width)
##     fps: playback speed. barrel_fire uses 6.0; idle motion wants the same neighbourhood
##     world_3d: where to place it
##     world_size: world width the strip's FRAME must occupy (see Utilities.SnapRef)
##     brightness: sprite modulate from the level's sprite brightness setting
##     ref: which frame side world_size applies to. Items use LONGEST_SIDE so a tall bottle
##          and a wide can read at the same size, matching static items.
##
## Returns:
##     configured AnimatedSprite3D, already playing, or null if the strip is missing
static func create(sheet_path: String, frame_count: int, fps: float, world_3d: Vector3,
		world_size: float, brightness: float,
		ref: int = UtilitiesScript.SnapRef.WIDTH) -> AnimatedSprite3D:
	var sheet_texture := load(sheet_path) as Texture2D
	if sheet_texture == null:
		push_warning("AnimatedBillboard: failed to load spritesheet %s" % sheet_path)
		return null

	var sprite_frames := build_frames(sheet_texture, frame_count, fps)
	if sprite_frames == null:
		return null

	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = sprite_frames
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.alpha_cut = Sprite3D.ALPHA_CUT_DISCARD
	sprite.position = world_3d
	# Snaps the sheet, re-cuts the atlas regions for the snapped sheet's pixel size, and
	# pins the world size (re-done live when the Sprite Detail setting changes)
	UtilitiesScript.apply_snap_sprite(sprite, sheet_texture, world_size, frame_count, ref)
	sprite.modulate = Color(brightness, brightness, brightness, 1.0)
	sprite.play("default")
	return sprite

## Cut a horizontal strip into a SpriteFrames animation.
##
## Split out from create() and deliberately free of any autoload reference: the pixel-snap
## path needs the Utilities singleton, which does not exist when a check runs as a bare
## SceneTree script (godot --script). Keeping the atlas arithmetic here means the headless
## regression check exercises the real code instead of a copy of it that can drift.
##
## Returns:
##     SpriteFrames with one looping "default" animation, or null (after warning) if the
##     strip cannot be cut into frame_count equal frames
static func build_frames(sheet: Texture2D, frame_count: int, fps: float) -> SpriteFrames:
	var what: String = str(sheet.resource_path)
	if frame_count < 2:
		push_warning("AnimatedBillboard: %s declares %d frames, need at least 2" % [what, frame_count])
		return null
	if sheet.get_width() % frame_count != 0:
		push_warning("AnimatedBillboard: %s is %d px wide, not divisible by %d frames — " % [
				what, sheet.get_width(), frame_count] +
				"frames would be cut unevenly")
		return null

	var frame_width: int = sheet.get_width() / frame_count
	var frame_height: int = sheet.get_height()

	var sprite_frames := SpriteFrames.new()
	# "default" exists on a fresh SpriteFrames; speed and loop are set before frames are
	# added, which is what barrel_fire has always done.
	sprite_frames.set_animation_speed("default", fps)
	sprite_frames.set_animation_loop("default", true)
	for i in range(frame_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
		atlas.filter_clip = true
		sprite_frames.add_frame("default", atlas)
	return sprite_frames