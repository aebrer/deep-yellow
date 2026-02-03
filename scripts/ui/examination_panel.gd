class_name ExaminationPanel
extends Control
## Examination text panel - lives in main viewport (always clean text)

# ============================================================================
# CONSTANTS
# ============================================================================

## Base font sizes (scaled by UIScaleManager)
const FONT_SIZE_HEADER := 14
const FONT_SIZE_ENTITY_NAME := 14
const FONT_SIZE_INFO := 12
const FONT_SIZE_DESCRIPTION := 11

## Font resource path for emoji support
const EMOJI_FONT_PATH := "res://assets/fonts/default_font.tres"

# ============================================================================
# NODE REFERENCES
# ============================================================================

var panel: PanelContainer
var header_label: Label
var entity_name_label: Label
var threat_level_label: Label
var description_label: RichTextLabel

## Font with emoji fallback (project default doesn't auto-apply to programmatic Labels)
var emoji_font: Font = null

## Portrait mode overlay panel (separate from embedded panel)
var portrait_overlay: PanelContainer = null

# ============================================================================
# STATE
# ============================================================================

var current_target: Examinable = null
var _is_portrait_mode: bool = false
var _is_repositioning: bool = false  ## Guard flag to prevent concurrent repositioning
var _is_expanded_upward: bool = false  ## Track if panel is in "overflow" mode (expanded upward)

func _ready() -> void:
	# Load emoji font (project setting doesn't auto-apply to programmatic Labels)
	emoji_font = load(EMOJI_FONT_PATH)

	# Fill remaining available space in RightSide VBoxContainer
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_panel()

	# Hide by default
	panel.visible = false

	# Connect to pause manager to update position when pausing (portrait mode only)
	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)

	# Connect to UIScaleManager for resolution-based font scaling
	if UIScaleManager:
		UIScaleManager.scale_changed.connect(_on_scale_changed)

func _build_panel() -> void:
	"""Build examination panel (embedded in RightSide VBoxContainer, below inventory)"""
	panel = PanelContainer.new()
	panel.name = "ExaminationPanelInner"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Use anchors to fill parent Control (size_flags don't work for non-container parents)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	# Style panel (Backrooms aesthetic - muted yellow border, slightly different background)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.05, 0.95)  # Slightly warm/sepia tinted dark background
	style.border_color = Color(0.76, 0.70, 0.50, 1.0)  # Muted yellow-brown (fluorescent/wallpaper theme)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	# Content container (no scroll - text will auto-fit)
	var vbox = VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	# Header
	header_label = Label.new()
	header_label.text = "OBJECT EXAMINATION REPORT"
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	header_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if emoji_font:
		header_label.add_theme_font_override("font", emoji_font)
	vbox.add_child(header_label)

	# Separator
	var separator1 = HSeparator.new()
	separator1.add_theme_constant_override("separation", 8)
	vbox.add_child(separator1)

	# Entity name
	entity_name_label = Label.new()
	entity_name_label.text = "Entity: Unknown"
	entity_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entity_name_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_ENTITY_NAME))
	entity_name_label.add_theme_color_override("font_color", Color.WHITE)
	if emoji_font:
		entity_name_label.add_theme_font_override("font", emoji_font)
	vbox.add_child(entity_name_label)

	# Threat level
	threat_level_label = Label.new()
	threat_level_label.text = "Threat: Unknown"
	threat_level_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	threat_level_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	if emoji_font:
		threat_level_label.add_theme_font_override("font", emoji_font)
	vbox.add_child(threat_level_label)

	# Separator
	var separator2 = HSeparator.new()
	separator2.add_theme_constant_override("separation", 8)
	vbox.add_child(separator2)

	# Description
	description_label = RichTextLabel.new()
	description_label.bbcode_enabled = true
	description_label.scroll_active = false
	description_label.fit_content = true
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_label.add_theme_font_size_override("normal_font_size", _get_font_size(FONT_SIZE_DESCRIPTION))
	description_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	if emoji_font:
		description_label.add_theme_font_override("normal_font", emoji_font)
	vbox.add_child(description_label)

func show_panel(target: Examinable) -> void:
	"""Display examination info for target"""
	if not target:
		hide_panel()
		return

	# Get entity info (via Examinable for corruption-aware data)
	var info = target.get_display_info()

	# Check if this is an item (has rarity info)
	var is_item = info.get("is_item", false)

	# Get common values
	var entity_name = ("Item: " if is_item else "Entity: ") + info.get("name", "Unknown")
	var description = info.get("description", "[DATA EXPUNGED]")

	# For items, show rarity instead of threat level
	var info_line_text: String
	var info_line_color: Color
	if is_item:
		var rarity_name = info.get("rarity_name", "Unknown")
		info_line_text = "Rarity: " + rarity_name
		info_line_color = info.get("rarity_color", Color.WHITE)
	else:
		var threat_name = info.get("threat_level_name", "")
		if threat_name.is_empty():
			threat_name = _format_threat_level(info.get("threat_level", 0))
		info_line_text = "Threat: " + threat_name
		info_line_color = _get_threat_color(info.get("threat_level", 0))

	if _is_portrait_mode:
		# Use overlay panel in portrait mode
		_show_portrait_overlay(entity_name, info_line_text, description, info_line_color)
	else:
		# Use embedded panel in landscape mode
		_show_embedded_panel(entity_name, info_line_text, description, info_line_color)

func _show_embedded_panel(entity_name: String, info_line_text: String, description: String, info_color: Color) -> void:
	"""Show the embedded panel (landscape mode)"""
	# Reset header to default (stats_panel may have changed it to "STAT INFO")
	header_label.text = "OBJECT EXAMINATION REPORT"

	# Update labels
	entity_name_label.text = entity_name
	threat_level_label.text = info_line_text
	description_label.text = description

	# Set info line color (threat or rarity)
	threat_level_label.add_theme_color_override("font_color", info_color)

	# Ensure all labels are visible (defensive fix for intermittent visibility bug)
	header_label.visible = true
	entity_name_label.visible = true
	threat_level_label.visible = true
	description_label.visible = true

	# Show panel
	panel.visible = true

	# Check for overflow and expand upward if needed (after a frame for layout)
	_check_overflow_and_expand.call_deferred()

func _show_portrait_overlay(entity_name: String, info_line_text: String, description: String, info_color: Color) -> void:
	"""Show the overlay panel (portrait mode)"""
	if not portrait_overlay:
		_build_portrait_overlay()

	if not portrait_overlay:
		return  # Failed to create overlay

	# Get overlay labels with null checks
	var vbox = portrait_overlay.get_node_or_null("ContentVBox")
	if not vbox:
		return
	var header = vbox.get_node_or_null("OverlayHeader")
	var entity_label = vbox.get_node_or_null("OverlayEntityName")
	var threat_label = vbox.get_node_or_null("OverlayThreatLevel")
	var desc_label = vbox.get_node_or_null("OverlayDescription")

	# Update content (with null guards)
	if header:
		header.text = "OBJECT EXAMINATION REPORT"
	if entity_label:
		entity_label.text = entity_name
	if threat_label:
		threat_label.text = info_line_text
		threat_label.add_theme_color_override("font_color", info_color)
	if desc_label:
		desc_label.text = description

	# Position overlay over the info panel (minimap + log row at bottom)
	_position_portrait_overlay()

	# Show overlay
	portrait_overlay.visible = true

func _position_portrait_overlay() -> void:
	"""Position the portrait overlay at the bottom of the screen (over info row)"""
	if not portrait_overlay:
		return

	# Guard against concurrent repositioning (async method with awaits)
	if _is_repositioning:
		return
	_is_repositioning = true

	var game_root = get_tree().root.get_node_or_null("Game")
	if not game_root:
		_is_repositioning = false
		return

	# Get the window size
	var window_size = get_window().size

	# Let panel auto-size first
	portrait_overlay.reset_size()

	# Wait a frame for size to be calculated
	await get_tree().process_frame

	# Check overlay still valid after await
	if not portrait_overlay or not is_instance_valid(portrait_overlay):
		_is_repositioning = false
		return

	# Position at bottom of screen with some margin
	var margin = 10
	var panel_size = portrait_overlay.size

	# Full width minus margins
	portrait_overlay.custom_minimum_size.x = window_size.x - (margin * 2)
	portrait_overlay.reset_size()

	# Wait for size update
	await get_tree().process_frame

	# Check overlay still valid after second await
	if not portrait_overlay or not is_instance_valid(portrait_overlay):
		_is_repositioning = false
		return

	panel_size = portrait_overlay.size
	portrait_overlay.position = Vector2(
		margin,  # Left margin
		window_size.y - panel_size.y - margin  # Bottom with margin
	)

	_is_repositioning = false

func hide_panel() -> void:
	"""Hide the panel (both embedded and overlay)"""
	panel.visible = false
	if portrait_overlay:
		portrait_overlay.visible = false

	# Restore normal layout if expanded
	if _is_expanded_upward:
		_restore_panel_normal()

func set_portrait_mode(is_portrait: bool) -> void:
	"""Switch between embedded panel (landscape) and overlay panel (portrait)"""
	if _is_portrait_mode == is_portrait:
		return  # No change

	_is_portrait_mode = is_portrait

	if is_portrait:
		# Hide embedded panel in portrait mode
		panel.visible = false
		# Create overlay if needed
		if not portrait_overlay:
			_build_portrait_overlay()
	else:
		# Hide overlay and show embedded panel in landscape mode
		if portrait_overlay:
			portrait_overlay.visible = false
		# Embedded panel visibility controlled by show_panel/hide_panel

func _build_portrait_overlay() -> void:
	"""Build the portrait mode overlay panel (appears on top of info row)"""
	# Find the Game node to add overlay at top level
	var game_root = get_tree().root.get_node_or_null("Game")
	if not game_root:
		return

	portrait_overlay = PanelContainer.new()
	portrait_overlay.name = "ExaminationOverlay"
	portrait_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_overlay.visible = false  # Hidden until needed
	portrait_overlay.z_index = 50  # Above game content but below game over

	# Style panel (SCP aesthetic - matching embedded style)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.05, 0.95)  # Slightly warm/sepia tinted dark background
	style.border_color = Color(0.76, 0.70, 0.50, 1.0)  # Muted yellow-brown border
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	portrait_overlay.add_theme_stylebox_override("panel", style)

	# Add to Game node so it can be positioned absolutely
	game_root.add_child(portrait_overlay)

	# Content container
	var vbox = VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_overlay.add_child(vbox)

	# Header
	var header = Label.new()
	header.name = "OverlayHeader"
	header.text = "OBJECT EXAMINATION REPORT"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if emoji_font:
		header.add_theme_font_override("font", emoji_font)
	vbox.add_child(header)

	# Separator
	var separator1 = HSeparator.new()
	separator1.add_theme_constant_override("separation", 6)
	vbox.add_child(separator1)

	# Entity name
	var entity_name = Label.new()
	entity_name.name = "OverlayEntityName"
	entity_name.text = "Entity: Unknown"
	entity_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entity_name.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_ENTITY_NAME))
	entity_name.add_theme_color_override("font_color", Color.WHITE)
	if emoji_font:
		entity_name.add_theme_font_override("font", emoji_font)
	vbox.add_child(entity_name)

	# Threat level
	var threat_level = Label.new()
	threat_level.name = "OverlayThreatLevel"
	threat_level.text = "Threat: Unknown"
	threat_level.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	threat_level.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	if emoji_font:
		threat_level.add_theme_font_override("font", emoji_font)
	vbox.add_child(threat_level)

	# Separator
	var separator2 = HSeparator.new()
	separator2.add_theme_constant_override("separation", 6)
	vbox.add_child(separator2)

	# Description
	var description = RichTextLabel.new()
	description.name = "OverlayDescription"
	description.bbcode_enabled = true
	description.scroll_active = false
	description.fit_content = true
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("normal_font_size", _get_font_size(FONT_SIZE_DESCRIPTION))
	description.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	if emoji_font:
		description.add_theme_font_override("normal_font", emoji_font)
	vbox.add_child(description)

func _on_pause_toggled(_is_paused: bool) -> void:
	"""Handle pause state changes (no repositioning needed when embedded)"""
	pass  # Panel position is managed by parent container or overlay positioning

func set_target(target: Examinable) -> void:
	current_target = target

func clear_target() -> void:
	current_target = null

func show_stat_info(stat_name: String, description: String) -> void:
	"""Show stat information (used by stats_panel for hover tooltips)"""
	if _is_portrait_mode:
		_show_stat_info_overlay(stat_name, description)
	else:
		_show_stat_info_embedded(stat_name, description)

func _show_stat_info_embedded(stat_name: String, description: String) -> void:
	"""Show stat info in embedded panel (landscape mode)"""
	header_label.text = "STAT INFO"
	header_label.visible = true
	entity_name_label.text = stat_name
	entity_name_label.visible = true
	threat_level_label.visible = false  # Hide threat for stats
	description_label.text = description
	description_label.visible = true
	panel.visible = true

	# Check for overflow and expand upward if needed (after a frame for layout)
	_check_overflow_and_expand.call_deferred()

func _show_stat_info_overlay(stat_name: String, description: String) -> void:
	"""Show stat info in overlay panel (portrait mode)"""
	if not portrait_overlay:
		_build_portrait_overlay()

	if not portrait_overlay:
		return

	# Get overlay labels with null checks
	var vbox = portrait_overlay.get_node_or_null("ContentVBox")
	if not vbox:
		return
	var header = vbox.get_node_or_null("OverlayHeader")
	var entity_label = vbox.get_node_or_null("OverlayEntityName")
	var threat_label = vbox.get_node_or_null("OverlayThreatLevel")
	var desc_label = vbox.get_node_or_null("OverlayDescription")

	# Update content (with null guards)
	if header:
		header.text = "STAT INFO"
	if entity_label:
		entity_label.text = stat_name
	if threat_label:
		threat_label.visible = false  # Hide threat for stats
	if desc_label:
		desc_label.text = description

	# Position and show overlay
	_position_portrait_overlay()
	portrait_overlay.visible = true

func _format_threat_level(level: int) -> String:
	"""Convert threat level to display string"""
	match level:
		0: return "Minimal"
		1: return "Low"
		2: return "Moderate"
		3: return "High"
		4: return "Severe"
		5: return "Critical"
		_: return "Unknown"

func _get_threat_color(threat: int) -> Color:
	"""Get color for a threat level (shared by embedded and overlay panels)"""
	match threat:
		0, 1: return Color.WHITE
		2: return Color.YELLOW
		3, 4: return Color.ORANGE
		5: return Color.RED
		_: return Color.GRAY

func _set_threat_colors(threat: int) -> void:
	"""Set label colors based on threat level"""
	threat_level_label.add_theme_color_override("font_color", _get_threat_color(threat))

# ============================================================================
# UI SCALING
# ============================================================================

func _get_font_size(base_size: int) -> int:
	"""Get font size scaled by UIScaleManager"""
	var scaled: int = base_size
	if UIScaleManager:
		scaled = UIScaleManager.get_scaled_font_size(base_size)
	# Defensive: ensure font size is never 0 or negative
	return max(1, scaled)

func _update_all_font_sizes() -> void:
	"""Update all font sizes after scale change"""
	# Update embedded panel labels
	if header_label:
		header_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	if entity_name_label:
		entity_name_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_ENTITY_NAME))
	if threat_level_label:
		threat_level_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	if description_label:
		description_label.add_theme_font_size_override("normal_font_size", _get_font_size(FONT_SIZE_DESCRIPTION))

	# Update portrait overlay labels if they exist
	if portrait_overlay:
		var vbox = portrait_overlay.get_node_or_null("ContentVBox")
		if vbox:
			var header = vbox.get_node_or_null("OverlayHeader")
			var entity = vbox.get_node_or_null("OverlayEntityName")
			var threat = vbox.get_node_or_null("OverlayThreatLevel")
			var desc = vbox.get_node_or_null("OverlayDescription")
			if header:
				header.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
			if entity:
				entity.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_ENTITY_NAME))
			if threat:
				threat.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
			if desc:
				desc.add_theme_font_size_override("normal_font_size", _get_font_size(FONT_SIZE_DESCRIPTION))

func _on_scale_changed(_scale: float) -> void:
	"""Handle UI scale changes from UIScaleManager"""
	_update_all_font_sizes()

# ============================================================================
# OVERFLOW EXPANSION (Expand Upward)
# ============================================================================

func _check_overflow_and_expand() -> void:
	"""Check if panel content overflows available space and expand upward if needed.

	When content is taller than the allocated container space, the panel
	switches to absolute positioning and grows upward from its bottom edge,
	overlapping content above it. This ensures all examination text is visible
	regardless of screen size.
	"""
	if _is_portrait_mode:
		return  # Portrait mode uses overlay, not embedded panel

	if not panel or not panel.visible:
		return

	# Wait a frame for layout to settle
	await get_tree().process_frame

	if not panel or not is_instance_valid(panel):
		return

	# Get the content's minimum required size
	var vbox = panel.get_node_or_null("ContentVBox")
	if not vbox:
		return

	# Get the actual minimum size the content needs
	var content_min_size = vbox.get_combined_minimum_size()
	# Add panel padding/margins
	var style = panel.get_theme_stylebox("panel")
	if style:
		content_min_size.y += style.content_margin_top + style.content_margin_bottom
		content_min_size.x += style.content_margin_left + style.content_margin_right

	# Get the space we actually have (the Control node's allocated size)
	var available_size = self.size

	# Check if content overflows vertically
	var overflow = content_min_size.y > available_size.y

	if overflow and not _is_expanded_upward:
		# Need to expand upward - switch to absolute positioning
		_expand_panel_upward(content_min_size)
	elif not overflow and _is_expanded_upward:
		# Content fits now - restore normal layout
		_restore_panel_normal()


func _expand_panel_upward(content_size: Vector2) -> void:
	"""Switch panel to absolute positioning, growing upward from bottom edge."""
	_is_expanded_upward = true

	# Remove anchor preset (switch to manual positioning)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT, false)

	# Position panel at bottom of our container, extending upward
	var bottom_y = self.size.y
	var panel_height = content_size.y
	var panel_top = bottom_y - panel_height

	panel.position = Vector2(0, panel_top)
	panel.size = Vector2(self.size.x, panel_height)

	# Raise z_index so panel overlaps content above
	panel.z_index = 10


func _restore_panel_normal() -> void:
	"""Restore panel to normal container-based layout."""
	_is_expanded_upward = false

	# Restore anchor preset to fill parent
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.position = Vector2.ZERO

	# Reset z_index
	panel.z_index = 0
