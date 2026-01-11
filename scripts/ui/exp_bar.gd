class_name EXPBar
extends Control
## Vertical EXP progress bar along left edge of game viewport
##
## Features:
## - Fills from bottom to top as EXP accumulates
## - Shows current level in center
## - Smooth fill animation on EXP gain
## - Subtle glow effect when close to level up

# ============================================================================
# CONSTANTS
# ============================================================================

const BAR_WIDTH := 8  # Pixels wide
const BAR_MARGIN := 4  # Margin from viewport edge
const FILL_SPEED := 2.0  # Fill animation speed (per second)
const GLOW_THRESHOLD := 0.8  # Start glowing at 80% to next level

## Colors
const COLOR_BACKGROUND := Color(0.1, 0.1, 0.1, 0.8)  # Dark background
const COLOR_FILL := Color(0.2, 0.8, 0.3, 1.0)  # Green fill
const COLOR_FILL_GLOW := Color(0.4, 1.0, 0.5, 1.0)  # Bright green when close to levelup
const COLOR_BORDER := Color(0.4, 0.4, 0.4, 1.0)  # Gray border

# ============================================================================
# STATE
# ============================================================================

var player: Node = null
var target_fill: float = 0.0  # Target fill percentage (0-1)
var current_fill: float = 0.0  # Current animated fill
var is_glowing: bool = false

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Fill the full control area
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	# Animate fill toward target
	if current_fill != target_fill:
		if current_fill < target_fill:
			current_fill = min(current_fill + FILL_SPEED * delta, target_fill)
		else:
			# Instant reset on level up (fill drops)
			current_fill = target_fill
		queue_redraw()

	# Update glow state
	var new_glow = target_fill >= GLOW_THRESHOLD
	if new_glow != is_glowing:
		is_glowing = new_glow
		queue_redraw()

func _draw() -> void:
	var viewport_size = get_viewport_rect().size

	# Bar dimensions - full height, positioned on left edge
	var bar_rect = Rect2(
		BAR_MARGIN,
		BAR_MARGIN,
		BAR_WIDTH,
		viewport_size.y - BAR_MARGIN * 2
	)

	# Background
	draw_rect(bar_rect, COLOR_BACKGROUND)

	# Fill (from bottom up)
	if current_fill > 0:
		var fill_height = bar_rect.size.y * current_fill
		var fill_rect = Rect2(
			bar_rect.position.x,
			bar_rect.position.y + bar_rect.size.y - fill_height,
			bar_rect.size.x,
			fill_height
		)
		var fill_color = COLOR_FILL_GLOW if is_glowing else COLOR_FILL
		draw_rect(fill_rect, fill_color)

	# Border
	draw_rect(bar_rect, COLOR_BORDER, false, 1.0)

	# Level indicator (centered on bar)
	if player and player.stats:
		var level_text = str(player.stats.level)
		var font = ThemeDB.fallback_font
		var font_size = 10
		var text_size = font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos = Vector2(
			bar_rect.position.x + (bar_rect.size.x - text_size.x) / 2,
			bar_rect.position.y + bar_rect.size.y / 2 + text_size.y / 4
		)
		# Draw text background for readability
		var bg_rect = Rect2(
			text_pos.x - 2,
			text_pos.y - text_size.y,
			text_size.x + 4,
			text_size.y + 4
		)
		draw_rect(bg_rect, Color(0, 0, 0, 0.8))
		draw_string(font, text_pos, level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

# ============================================================================
# PUBLIC API
# ============================================================================

func set_player(player_ref: Node) -> void:
	"""Set player reference and connect to stat signals"""
	player = player_ref

	if player and player.stats:
		# Connect to EXP signals
		if not player.stats.exp_gained.is_connected(_on_exp_gained):
			player.stats.exp_gained.connect(_on_exp_gained)
		if not player.stats.level_increased.is_connected(_on_level_increased):
			player.stats.level_increased.connect(_on_level_increased)

		# Initial update
		_update_fill()
		queue_redraw()  # Force initial draw with correct level

func _on_exp_gained(_amount: int, _new_total: int) -> void:
	"""Called when player gains EXP"""
	_update_fill()
	queue_redraw()  # Redraw to update any visual changes

func _on_level_increased(_old_level: int, _new_level: int) -> void:
	"""Called when player levels up"""
	_update_fill()
	queue_redraw()

func _update_fill() -> void:
	"""Update target fill based on current EXP progress"""
	if not player or not player.stats:
		target_fill = 0.0
		return

	var stats = player.stats
	var exp_needed = stats.exp_to_next_level()
	var exp_total_for_level = stats._exp_for_next_level()
	var exp_current_toward_level = exp_total_for_level - exp_needed

	if exp_total_for_level > 0:
		target_fill = float(exp_current_toward_level) / float(exp_total_for_level)
	else:
		target_fill = 0.0

	target_fill = clamp(target_fill, 0.0, 1.0)
