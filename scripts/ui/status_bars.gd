class_name StatusBars
extends Control
## Horizontal HP and Sanity bars at top of game viewport
##
## Layout: HP bar on left 1/3, Sanity bar on right 1/3
##
## Features:
## - Smooth fill animation on damage/healing
## - Color changes based on current value (green -> yellow -> red)
## - Shows numeric values (current/max)

# ============================================================================
# CONSTANTS
# ============================================================================

const BAR_HEIGHT := 12  # Pixels tall
const BAR_MARGIN := 16  # Margin from viewport edge (increased)
const BAR_GAP := 4  # Gap between bar and text
const FILL_SPEED := 3.0  # Fill animation speed (per second)
const TEXT_MARGIN := 8  # Margin for text from bar edge

## Bar width as fraction of viewport (each bar takes 2/5 = 40%)
const BAR_WIDTH_FRACTION := 0.40  # 40% of viewport width per bar

## Colors - matching the 3D bars above player's head in tactical cam
const COLOR_BACKGROUND := Color(0.0, 0.0, 0.0, 0.9)  # Black background (matches BAR_BG_COLOR)
const COLOR_BORDER := Color(0.5, 0.5, 0.5, 1.0)

## HP color - solid red (matches HP_BAR_FG_COLOR from player_3d.gd)
const COLOR_HP := Color(0.9, 0.15, 0.15, 1.0)

## Sanity color - solid purple (matches SANITY_BAR_FG_COLOR from player_3d.gd)
const COLOR_SANITY := Color(0.6, 0.2, 0.8, 1.0)

# ============================================================================
# STATE
# ============================================================================

var player: Node = null

## HP state
var hp_current: float = 0.0
var hp_max: float = 100.0
var hp_target_fill: float = 1.0
var hp_current_fill: float = 1.0

## Sanity state
var sanity_current: float = 0.0
var sanity_max: float = 100.0
var sanity_target_fill: float = 1.0
var sanity_current_fill: float = 1.0

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	var needs_redraw := false

	# Animate HP fill toward target
	if hp_current_fill != hp_target_fill:
		if hp_current_fill < hp_target_fill:
			hp_current_fill = min(hp_current_fill + FILL_SPEED * delta, hp_target_fill)
		else:
			hp_current_fill = max(hp_current_fill - FILL_SPEED * delta, hp_target_fill)
		needs_redraw = true

	# Animate Sanity fill toward target
	if sanity_current_fill != sanity_target_fill:
		if sanity_current_fill < sanity_target_fill:
			sanity_current_fill = min(sanity_current_fill + FILL_SPEED * delta, sanity_target_fill)
		else:
			sanity_current_fill = max(sanity_current_fill - FILL_SPEED * delta, sanity_target_fill)
		needs_redraw = true

	if needs_redraw:
		queue_redraw()

func _draw() -> void:
	var viewport_size = get_viewport_rect().size
	var bar_width = viewport_size.x * BAR_WIDTH_FRACTION

	# HP bar (left side)
	var hp_rect = Rect2(
		BAR_MARGIN,
		BAR_MARGIN,
		bar_width,
		BAR_HEIGHT
	)
	_draw_bar(hp_rect, hp_current_fill, hp_current, hp_max, "HP", true)

	# Sanity bar (right side)
	var sanity_rect = Rect2(
		viewport_size.x - BAR_MARGIN - bar_width,
		BAR_MARGIN,
		bar_width,
		BAR_HEIGHT
	)
	_draw_bar(sanity_rect, sanity_current_fill, sanity_current, sanity_max, "SAN", false)

func _draw_bar(rect: Rect2, fill: float, current: float, max_val: float, label: String, is_hp: bool) -> void:
	# Background
	draw_rect(rect, COLOR_BACKGROUND)

	# Fill (left to right)
	if fill > 0:
		var fill_width = rect.size.x * fill
		var fill_rect = Rect2(
			rect.position.x,
			rect.position.y,
			fill_width,
			rect.size.y
		)
		var fill_color = _get_fill_color(is_hp)
		draw_rect(fill_rect, fill_color)

	# Border
	draw_rect(rect, COLOR_BORDER, false, 1.0)

	# Text (current/max)
	var font = ThemeDB.fallback_font
	var font_size = 10
	var text = "%s: %d/%d" % [label, int(current), int(max_val)]
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)

	# Center text vertically in bar, position based on which bar
	var text_y = rect.position.y + (rect.size.y + text_size.y) / 2 - 2
	var text_x: float

	if is_hp:
		# HP: text inside bar, left-aligned with small margin
		text_x = rect.position.x + TEXT_MARGIN
	else:
		# Sanity: text inside bar, right-aligned with small margin
		text_x = rect.position.x + rect.size.x - text_size.x - TEXT_MARGIN

	# Draw text with shadow for readability
	draw_string(font, Vector2(text_x + 1, text_y + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(text_x, text_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _get_fill_color(is_hp: bool) -> Color:
	# Solid colors matching the 3D bars above player's head
	return COLOR_HP if is_hp else COLOR_SANITY

# ============================================================================
# PUBLIC API
# ============================================================================

func set_player(player_ref: Node) -> void:
	"""Set player reference and connect to stat signals"""
	# Disconnect from old player if reconnecting
	if player and player.stats:
		if player.stats.resource_changed.is_connected(_on_resource_changed):
			player.stats.resource_changed.disconnect(_on_resource_changed)
		if player.stats.stat_changed.is_connected(_on_stat_changed):
			player.stats.stat_changed.disconnect(_on_stat_changed)

	player = player_ref

	if player and player.stats:
		# Connect to resource and stat change signals
		player.stats.resource_changed.connect(_on_resource_changed)
		player.stats.stat_changed.connect(_on_stat_changed)

		# Initial update
		_update_values()
		queue_redraw()

func _on_resource_changed(resource_name: String, current: float, maximum: float) -> void:
	"""Called when player HP, Sanity, or Mana changes"""
	match resource_name:
		"hp":
			hp_current = current
			hp_max = maximum
			hp_target_fill = current / maximum if maximum > 0 else 0.0
		"sanity":
			sanity_current = current
			sanity_max = maximum
			sanity_target_fill = current / maximum if maximum > 0 else 0.0
	# Mana is ignored (shown in stats panel instead)
	queue_redraw()

func _on_stat_changed(_stat_name: String, _old_value: float, _new_value: float) -> void:
	"""Called when base stats change (body/mind/null) — recalculate derived HP/Sanity"""
	_update_values()
	queue_redraw()

func _update_values() -> void:
	"""Update all values from player stats"""
	if not player or not player.stats:
		return

	hp_current = player.stats.current_hp
	hp_max = player.stats.max_hp
	hp_target_fill = hp_current / hp_max if hp_max > 0 else 0.0
	hp_current_fill = hp_target_fill  # Instant on initial load

	sanity_current = player.stats.current_sanity
	sanity_max = player.stats.max_sanity
	sanity_target_fill = sanity_current / sanity_max if sanity_max > 0 else 0.0
	sanity_current_fill = sanity_target_fill  # Instant on initial load
