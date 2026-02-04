extends Node
## UIScaleManager - Centralized UI scaling for high-resolution displays
##
## Provides consistent font and UI element scaling across all UI components.
## Modifies the game theme at runtime to scale all text automatically.
## Triggered by minimap resolution detection, will eventually be user-configurable.

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when UI scale changes (for components needing custom handling)
signal scale_changed(scale_factor: float)

# ============================================================================
# CONSTANTS
# ============================================================================

## Resolution scale threshold for high-res mode (minimap scale >= 3 means 4K+)
const HIGH_RES_SCALE_THRESHOLD := 3

## Scale multiplier for high-res mode
const HIGH_RES_SCALE_MULTIPLIER := 1.5

## Default scale (1.0 = 100%)
const DEFAULT_SCALE := 1.0

## Base font sizes from minimal_mono_theme.tres
const BASE_FONT_SIZE_DEFAULT := 14
const BASE_FONT_SIZE_LABEL := 14
const BASE_FONT_SIZE_RICH_TEXT := 13

# ============================================================================
# STATE
# ============================================================================

## Current UI scale factor (1.0 = normal, 1.5 = high-res)
var current_scale: float = DEFAULT_SCALE

## Current minimap resolution scale (for threshold detection)
var _minimap_scale: int = 0

## Reference to the game theme (set by game.gd)
var _game_theme: Theme = null

# ============================================================================
# PUBLIC API
# ============================================================================

func set_theme(theme: Theme) -> void:
	"""Set the theme to modify for scaling (called by game.gd on startup)"""
	_game_theme = theme

func set_resolution_scale(minimap_scale: int) -> void:
	"""Called by minimap when its scale factor changes"""
	_minimap_scale = minimap_scale

	var new_scale = HIGH_RES_SCALE_MULTIPLIER if minimap_scale >= HIGH_RES_SCALE_THRESHOLD else DEFAULT_SCALE

	if new_scale != current_scale:
		current_scale = new_scale
		_apply_theme_scaling()
		scale_changed.emit(current_scale)

func _apply_theme_scaling() -> void:
	"""Apply current scale to theme font sizes"""
	if not _game_theme:
		Log.warn(Log.Category.SYSTEM, "UIScaleManager: No theme set, cannot apply scaling")
		return

	# Scale the theme's font sizes
	var scaled_default = int(BASE_FONT_SIZE_DEFAULT * current_scale)
	var scaled_label = int(BASE_FONT_SIZE_LABEL * current_scale)
	var scaled_rich_text = int(BASE_FONT_SIZE_RICH_TEXT * current_scale)

	_game_theme.default_font_size = scaled_default
	_game_theme.set_font_size("font_size", "Label", scaled_label)
	_game_theme.set_font_size("normal_font_size", "RichTextLabel", scaled_rich_text)

func get_scaled_font_size(base_size: int) -> int:
	"""Get a font size scaled for current resolution"""
	return int(base_size * current_scale)

