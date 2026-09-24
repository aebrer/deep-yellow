extends SceneTree
## Headless checks for billboard sizing and orientation.
##
## Regression 1: a billboard sizes itself from the texture it is actually showing
## (world size = texture pixels * pixel_size). When Sprite Detail downscales a 512px
## sheet to 128px, pixel_size has to be recomputed against the 128px texture — deriving
## it from the 512px source rendered every non-animated billboard 4x too small. Related:
## AtlasTexture regions live in the atlas' own pixel space, so re-pointing frames at a
## downscaled sheet requires re-cutting them.
##
## Regression 2: the third-person avatar's pixel_size was a literal in game_3d.tscn
## calibrated for the 64px sprite, so re-rendering the art at 512px drew a 15 m player.
##
## Regression 3: ceiling fixtures were billboarded vertical quads centred on the ceiling
## plane, so half the housing sliced down through the tile into the room.
##
## Run: godot --headless --script scripts/tools/verify_sprite_snap.gd

# Static access to the same script the Utilities autoload exposes
const UtilitiesScript := preload("res://scripts/autoload/utilities.gd")
const EntityRendererScript := preload("res://scripts/world/entity_renderer.gd")
const ItemRendererScript := preload("res://scripts/world/item_renderer.gd")
const AnimatedBillboardScript := preload("res://scripts/world/animated_billboard.gd")

const ENTITY_TEX := "res://assets/textures/entities/tutorial_mannequin.png"  # 512x512
const SHEET_TEX := "res://assets/textures/entities/barrel_fire_spritesheet.png"  # 2048x512
const TALL_TEX := "res://assets/levels/level_00/textures/wallpaper_yellow.png"  # 512x1024
const AVATAR_TEX := "res://assets/sprites/player/hazmat_suit_back.png"
const SHEET_FRAMES := 4
const WORLD_SIZE := 2.0

## Height of the visible figure the avatar calibration must keep drawing, in metres.
## Measured off the original 64px sprite: a 58px figure at pixel_size 0.03.
const AVATAR_FIGURE_HEIGHT := 1.74

## Ceiling surface height, per the table in AGENTS.md.
const CEILING_Y := 4.4

## The alpha threshold sprites are cut at: hazmat_suit.tres sets alpha_scissor to 0.5,
## and Sprite3D.ALPHA_CUT_DISCARD is the equivalent for billboards. In 8-bit alpha.
const ALPHA_SCISSOR_8BIT := 128

var _failures := 0
var _check_count := 0


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

	_avatar_size()
	_ceiling_fixtures()
	_decal_uv()
	_sprite_sheets()

	if _failures == 0:
		print("ALL CHECKS PASSED")
		quit(0)
	print("%d CHECK(S) FAILED" % _failures)
	quit(1)


## The avatar must keep drawing a human-sized figure whatever resolution the art ships at.
func _avatar_size() -> void:
	var tex: Texture2D = load(AVATAR_TEX)
	var sprite := Sprite3D.new()
	sprite.texture = tex

	# Run the production calibration, not a copy of its arithmetic
	var player = load("res://scripts/player/player_3d.gd").new()
	player.model = sprite
	player._setup_avatar_scale()

	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var figure: Rect2i = _visible_rect(img)
	var figure_h := float(figure.size.y) * sprite.pixel_size
	var figure_w := float(figure.size.x) * sprite.pixel_size

	print("=== third-person avatar ===")
	print("  texture %dx%d, visible figure %dx%d px, pixel_size %.6f" % [
			tex.get_width(), tex.get_height(), figure.size.x, figure.size.y, sprite.pixel_size])
	_check("avatar figure height", absf(figure_h - AVATAR_FIGURE_HEIGHT) < AVATAR_FIGURE_HEIGHT * 0.05,
			"figure draws %.2f m tall (want %.2f m within 5%%)" % [figure_h, AVATAR_FIGURE_HEIGHT])
	# A cell is 2 m across; a figure wider than this swallows the corridor
	_check("avatar figure fits in a cell", figure_w < 1.0,
			"figure draws %.2f m wide" % figure_w)

	# What the stale literal in the scene would have drawn, for the record
	print("  (the scene's old literal 0.03 would draw %.1f m)" % (float(tex.get_height()) * 0.03))
	sprite.free()
	player.free()


## Bounding box of the pixels the shader actually draws.
##
## psx_sprite.gdshader declares ALPHA_SCISSOR at 0.5, so anything fainter is discarded.
## Image.get_used_rect() tests alpha != 0 instead, and 41% of this sprite's canvas is
## sub-scissor residue (a soft contact shadow), so it reports the whole canvas as figure.
func _visible_rect(img: Image) -> Rect2i:
	var src := img
	if src.get_format() != Image.FORMAT_RGBA8:
		src = src.duplicate()
		src.convert(Image.FORMAT_RGBA8)
	var w: int = src.get_width()
	var h: int = src.get_height()
	var data: PackedByteArray = src.get_data()
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	for y in h:
		var row: int = y * w * 4
		for x in w:
			if data[row + x * 4 + 3] >= ALPHA_SCISSOR_8BIT:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	return Rect2i(x0, y0, maxi(0, x1 - x0 + 1), maxi(0, y1 - y0 + 1))


## Ceiling fixtures lie flat under the ceiling plane, with a pick volume that stays level.
func _ceiling_fixtures() -> void:
	print("=== ceiling fixtures ===")
	var renderer = load("res://scripts/world/entity_renderer.gd").new()
	var entity_script = load("res://scripts/world/world_entity.gd")

	for type in ["poolroom_light", "fluorescent_light"]:
		var y: float = renderer._entity_billboard_height(type)
		_check("%s hung below the ceiling plane" % type, is_equal_approx(y, CEILING_Y - 0.02),
				"centre y=%.3f (want %.3f, ceiling is %.1f)" % [y, CEILING_Y - 0.02, CEILING_Y])

		var entity = entity_script.new(type, Vector2i(3, 4))
		var sprite: Sprite3D = renderer._create_light_fixture_sprite(type, Vector3(1, y, 1), entity)
		_check("%s laid flat, not billboarded" % type,
				sprite.billboard == BaseMaterial3D.BILLBOARD_DISABLED \
				and is_equal_approx(sprite.rotation_degrees.x, 90.0),
				"billboard=%d rotation=%s" % [sprite.billboard, str(sprite.rotation_degrees)])
		var body: Node3D = sprite.get_node("ExamBody")
		_check("%s pick volume stays level" % type, is_equal_approx(body.rotation_degrees.x, -90.0),
				"ExamBody rotation=%s (must cancel the fixture's)" % str(body.rotation_degrees))
		_check("%s visible from above" % type, sprite.double_sided, "double_sided=false")
		sprite.free()

	# Control: a floor-standing entity must be untouched by any of this
	var plain_y: float = renderer._entity_billboard_height("sodden")
	_check("floor entities keep their height", is_equal_approx(plain_y, 1.4),
			"sodden centre y=%.3f" % plain_y)


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


## Regression 4: a floor decal inherited the level floor's uv_scale. That value is a
## TILING factor (level 1 repeats its tile texture 2x2 across one cell) and the shader
## applies it as UV = UV * uv_scale, and the sampler is repeat_enable — so the decal drew
## its art four times. Drew: "it's literally four sets of stairs in a single tile".
func _decal_uv() -> void:
	print("=== floor decal UV ===")
	var grid = load("res://scripts/grid_3d.gd").new()
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://shaders/psx_lit.gdshader")
	floor_mat.set_shader_parameter("uv_scale", Vector2(2, 2))  # level 1 poolroom floor
	floor_mat.set_shader_parameter("uv_offset", Vector2(0.3, 0.7))
	floor_mat.set_shader_parameter("modulate_color", Color(1.35, 1.45, 1.44))
	var floor_mats: Array[ShaderMaterial] = [floor_mat]
	grid.floor_materials = floor_mats

	var tex: Texture2D = load("res://assets/textures/entities/lobby_to_poolrooms_stairs.png")
	var mat: ShaderMaterial = grid.get_lit_decal_material(tex)
	_check("decal material built", mat != null, "get_lit_decal_material returned null")
	if mat == null:
		return

	var uv_scale: Vector2 = mat.get_shader_parameter("uv_scale")
	_check("decal samples its art once", uv_scale == Vector2.ONE,
			"uv_scale=%s repeats the sprite %dx%d times per cell" % [
					str(uv_scale), int(uv_scale.x), int(uv_scale.y)])
	var uv_offset: Vector2 = mat.get_shader_parameter("uv_offset")
	_check("decal is not offset", uv_offset == Vector2.ZERO,
			"uv_offset=%s slides the sprite off its cell and wraps it" % str(uv_offset))
	var tone: Color = mat.get_shader_parameter("modulate_color")
	_check("decal still matches the floor's tone", tone == Color(1.35, 1.45, 1.44),
			"modulate_color=%s — the decal would not light like its floor" % str(tone))


## Regression 5: every declared spritesheet must cut into equal frames, snap, and keep its
## world size. Entities and items now share AnimatedBillboard, so a bad strip — wrong
## declared frame count, a width that doesn't divide, a file that moved — shows up here
## instead of as a billboard rendering at the wrong scale in a level this check never loads.
func _sprite_sheets() -> void:
	print("=== spritesheet animations ===")
	var entity_sheets = EntityRendererScript.ENTITY_SPRITESHEETS
	var item_sheets = ItemRendererScript.ITEM_SPRITESHEETS
	_check("entity sheets registered", entity_sheets.size() > 0, "none")
	for id in entity_sheets:
		var world_size: float = float(EntityRendererScript.BILLBOARD_SIZE) * float(
				EntityRendererScript.ENTITY_SCALE_OVERRIDES.get(id, 1.0))
		_check_sheet("entity %s" % id, entity_sheets[id], world_size,
				UtilitiesScript.SnapRef.WIDTH)
	for id in item_sheets:
		_check_sheet("item %s" % id, item_sheets[id],
				float(ItemRendererScript.BILLBOARD_SIZE),
				UtilitiesScript.SnapRef.LONGEST_SIDE)


const SHEET_INSPECTIONS := 6

func _check_sheet(what: String, cfg: Dictionary, world_size: float, ref: int) -> void:
	var checks_before := _check_count
	var path: String = cfg["path"]
	var frames: int = int(cfg["frames"])
	var fps: float = float(cfg["fps"])
	if not ResourceLoader.exists(path):
		_check("%s strip exists" % what, false, "missing %s" % path)
		return

	var sheet: Texture2D = load(path)
	var sprite_frames = AnimatedBillboardScript.build_frames(sheet, frames, fps)
	if sprite_frames == null:
		_check("%s cuts into frames" % what, false,
				"%s is %dpx wide, declares %d frames" % [path, sheet.get_width(), frames])
		return

	_check("%s frame count" % what, sprite_frames.get_frame_count("default") == frames,
			"%d frames, declares %d" % [sprite_frames.get_frame_count("default"), frames])
	_check("%s loops" % what, sprite_frames.get_animation_loop("default"), "loop off")
	_check("%s fps" % what,
			is_equal_approx(sprite_frames.get_animation_speed("default"), fps),
			"%s want %s" % [sprite_frames.get_animation_speed("default"), fps])

	var frame_w: int = sheet.get_width() / frames
	var bad := ""
	for i in frames:
		var region: Rect2 = sprite_frames.get_frame_texture("default", i).region
		if not is_equal_approx(region.size.x, float(frame_w)) \
				or not is_equal_approx(region.position.x, float(i * frame_w)) \
				or region.end.x > float(sheet.get_width()):
			bad = "frame %d region %s, want x=%d w=%d inside %dpx" % [
					i, str(region), i * frame_w, frame_w, sheet.get_width()]
			break
	_check("%s regions tile the strip" % what, bad == "", bad)

	# Snapping must re-cut the regions for the snapped sheet (frame regions live in the
	# atlas' own pixel space) and pin the world size off the snapped frame.
	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = sprite_frames
	UtilitiesScript.apply_snap_sprite(sprite, sheet, world_size, frames, ref)
	var frame0: Texture2D = sprite_frames.get_frame_texture("default", 0)
	var atlas: Texture2D = frame0.atlas
	var snapped_w: int = int(frame0.region.size.x)
	_check("%s regions re-cut after snap" % what,
			atlas.get_width() == snapped_w * frames
					and frame0.region.end.x <= float(atlas.get_width()),
			"atlas %dpx, frame %dpx, frames %d" % [atlas.get_width(), snapped_w, frames])
	var ref_px: int = maxi(1, snapped_w)
	if ref == UtilitiesScript.SnapRef.LONGEST_SIDE:
		ref_px = maxi(ref_px, atlas.get_height())
	_check("%s world size" % what,
			is_equal_approx(float(ref_px) * sprite.pixel_size, world_size),
			"frame %dpx * pixel_size %.6f = %.3f m, want %.3f m" % [
					ref_px, sprite.pixel_size, float(ref_px) * sprite.pixel_size, world_size])
	var ran := _check_count - checks_before
	_check("%s ran every inspection" % what, ran == SHEET_INSPECTIONS,
			"only %d of %d inspections ran — something errored inside the check" % [
					ran, SHEET_INSPECTIONS])


## Every inspection is counted so an aborted check run cannot report success. A script
## error inside a check (a renamed function, a missing const) aborts only that call, so the
## summary used to still print ALL CHECKS PASSED with half the checks never run.
func _check(what: String, ok: bool, detail: String) -> void:
	_check_count += 1
	if ok:
		print("  PASS  %s" % what)
	else:
		_failures += 1
		print("  FAIL  %s — %s" % [what, detail])