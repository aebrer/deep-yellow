extends SceneTree
## Headless check for sprite pixel-snap sizing.
##
## Regression this guards: a billboard sizes itself from the texture it is actually
## showing (world size = texture pixels * pixel_size). When Sprite Detail downscales
## a 512px sheet to 128px, pixel_size has to be recomputed against the 128px
## texture — deriving it from the 512px source rendered every non-animated billboard
## 4x too small.
##
## Also guards the spritesheet toggle: AtlasTexture regions live in the atlas' own
## pixel space, so re-pointing frames at a downscaled sheet requires re-cutting them.
##
## Run: godot --headless --script scripts/tools/verify_sprite_snap.gd

# Static access to the same script the Utilities autoload exposes
const UtilitiesScript := preload("res://scripts/autoload/utilities.gd")

const ENTITY_TEX := "res://assets/textures/entities/tutorial_mannequin.png"  # 512x512
const SHEET_TEX := "res://assets/textures/entities/barrel_fire_spritesheet.png"  # 2048x512
const TALL_TEX := "res://assets/levels/level_00/textures/wallpaper_yellow.png"  # 512x1024
const SHEET_FRAMES := 4
const WORLD_SIZE := 2.0

var _failures := 0


func _initialize() -> void:
	var entity_tex: Texture2D = load(ENTITY_TEX)
	var sheet_tex: Texture2D = load(SHEET_TEX)
	var tall_tex: Texture2D = load(TALL_TEX)

	print("=== sprite pixel-snap sizing ===")
	print("source: entity=%dx%d sheet=%dx%d tall=%dx%d" % [
			entity_tex.get_width(), entity_tex.get_height(),
			sheet_tex.get_width(), sheet_tex.get_height(),
			tall_tex.get_width(), tall_tex.get_height()])

	for snap in [0.0, 128.0, 64.0]:
		UtilitiesScript.set_sprite_pixel_snap(snap)
		var label: String = "HD" if snap == 0.0 else ("%dpx" % int(snap))

		# Static billboard: world width must stay WORLD_SIZE at every snap level
		var sprite := Sprite3D.new()
		UtilitiesScript.apply_snap_sprite(sprite, entity_tex, WORLD_SIZE)
		_check_size("billboard %s" % label, sprite, WORLD_SIZE)

		# Item-style billboard measured on its longest side
		var tall := Sprite3D.new()
		UtilitiesScript.apply_snap_sprite(
				tall, tall_tex, WORLD_SIZE, 1, UtilitiesScript.SnapRef.LONGEST_SIDE)
		var tallest: int = maxi(tall.texture.get_width(), tall.texture.get_height())
		_check("item longest-side %s" % label,
				is_equal_approx(float(tallest) * tall.pixel_size, WORLD_SIZE),
				"texture=%dpx -> world %.4f (want %.4f)" % [
						tallest, float(tallest) * tall.pixel_size, WORLD_SIZE])

		# Spritesheet: world size stable AND frame regions inside the snapped atlas
		var anim := _make_animated(sheet_tex, SHEET_FRAMES)
		UtilitiesScript.apply_snap_sprite(anim, sheet_tex, WORLD_SIZE, SHEET_FRAMES)
		_check_size("spritesheet %s" % label, anim, WORLD_SIZE)
		_check_regions("spritesheet %s" % label, anim)

	# Live toggling (what the settings cycle drives) must not resize anything
	UtilitiesScript.set_sprite_pixel_snap(128.0)
	var live := Sprite3D.new()
	UtilitiesScript.apply_snap_sprite(live, entity_tex, WORLD_SIZE)
	var anim_live := _make_animated(sheet_tex, SHEET_FRAMES)
	UtilitiesScript.apply_snap_sprite(anim_live, sheet_tex, WORLD_SIZE, SHEET_FRAMES)
	root.add_child(live)
	root.add_child(anim_live)

	for snap in [64.0, 0.0, 128.0]:
		UtilitiesScript.set_sprite_pixel_snap(snap)
		var label: String = "HD" if snap == 0.0 else ("%dpx" % int(snap))
		_check_size("in-tree toggle billboard -> %s" % label, live, WORLD_SIZE)
		_check_size("in-tree toggle spritesheet -> %s" % label, anim_live, WORLD_SIZE)
		_check_regions("in-tree toggle spritesheet -> %s" % label, anim_live)

	# HD hands back the original texture object, not a resampled copy
	UtilitiesScript.set_sprite_pixel_snap(0.0)
	_check("HD returns source texture", live.texture == entity_tex,
			"got %s" % live.texture.resource_path)

	if _failures == 0:
		print("ALL CHECKS PASSED")
		quit(0)
	print("%d CHECK(S) FAILED" % _failures)
	quit(1)


func _make_animated(sheet_tex: Texture2D, frames: int) -> AnimatedSprite3D:
	var frames_res := SpriteFrames.new()
	var frame_w: int = sheet_tex.get_width() / frames
	for i in range(frames):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet_tex
		atlas.region = Rect2(i * frame_w, 0, frame_w, sheet_tex.get_height())
		atlas.filter_clip = true
		frames_res.add_frame("default", atlas)
	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = frames_res
	sprite.play("default")
	return sprite


## Pixels along the sprite's reference side, as the renderer sees them: Sprite3D
## uses its texture, AnimatedSprite3D uses the current frame's atlas region.
func _display_px(sprite: SpriteBase3D) -> int:
	if sprite is AnimatedSprite3D:
		var anim := sprite as AnimatedSprite3D
		var tex := anim.sprite_frames.get_frame_texture(anim.animation, anim.frame)
		return tex.get_width()
	return (sprite as Sprite3D).texture.get_width()


## Sprite3D world size = displayed texture size * pixel_size
func _check_size(what: String, sprite: SpriteBase3D, expected: float) -> void:
	var px := _display_px(sprite)
	var got := float(px) * sprite.pixel_size
	_check(what, is_equal_approx(got, expected),
			"displayed=%dpx pixel_size=%.6f -> world %.4f (want %.4f)" % [
					px, sprite.pixel_size, got, expected])


## Every frame region must sit inside its atlas and be one frame wide.
func _check_regions(what: String, sprite: AnimatedSprite3D) -> void:
	var frames_res: SpriteFrames = sprite.sprite_frames
	var frame_count := frames_res.get_frame_count("default")
	var first := frames_res.get_frame_texture("default", 0) as AtlasTexture
	var atlas: Texture2D = first.atlas
	var frame_w := first.get_width()
	for i in frame_count:
		var region: Rect2 = frames_res.get_frame_texture("default", i).region
		var inside := region.end.x <= float(atlas.get_width()) \
				and region.end.y <= float(atlas.get_height()) \
				and is_equal_approx(region.size.x, float(frame_w)) \
				and is_equal_approx(region.position.x, float(i * frame_w))
		_check("%s frame %d region" % [what, i], inside,
				"region=%s atlas=%dx%d frame_w=%d" % [
						str(region), atlas.get_width(), atlas.get_height(), frame_w])


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("  PASS  %s" % what)
	else:
		_failures += 1
		print("  FAIL  %s — %s" % [what, detail])