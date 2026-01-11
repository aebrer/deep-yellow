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

# ============================================================================
# STATE
# ============================================================================

var current_target: Examinable = null
var _is_portrait_mode: bool = false

func _ready() -> void:
	# Load emoji font (project setting doesn't auto-apply to programmatic Labels)
	emoji_font = load("res://assets/fonts/default_font.tres")

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

	# Style panel (SCP aesthetic - tight margins for embedded use)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.9)
	style.border_color = Color(1, 1, 1, 1)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
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

	# Get entity info
	var info = KnowledgeDB.get_entity_info(target.entity_id)

	# Reset header to default (stats_panel may have changed it to "STAT INFO")
	header_label.text = "OBJECT EXAMINATION REPORT"

	# Update labels
	entity_name_label.text = "Entity: " + info.get("name", "Unknown")
	# Use SCP-style threat level name from EntityInfo (e.g., "●●●○○ Keter")
	var threat_name = info.get("threat_level_name", "")
	if threat_name.is_empty():
		# Debug: Log when threat_level_name is missing
		print("[ExaminationPanel] WARNING: threat_level_name empty for entity_id: %s, info: %s" % [target.entity_id, info])
		threat_name = _format_threat_level(info.get("threat_level", 0))
	threat_level_label.text = "Threat: " + threat_name
	description_label.text = info.get("description", "[DATA EXPUNGED]")

	# Set colors based on threat
	var threat = info.get("threat_level", 0)
	_set_threat_colors(threat)

	# Ensure all labels are visible (defensive fix for intermittent visibility bug)
	header_label.visible = true
	entity_name_label.visible = true
	threat_level_label.visible = true
	description_label.visible = true

	# Show panel
	panel.visible = true

func hide_panel() -> void:
	"""Hide the panel"""
	panel.visible = false

func set_portrait_mode(is_portrait: bool) -> void:
	"""Track portrait mode state (layout now handled by parent container)"""
	_is_portrait_mode = is_portrait
	# Panel is now embedded in RightSide VBoxContainer, so no repositioning needed

func _on_pause_toggled(_is_paused: bool) -> void:
	"""Handle pause state changes (no repositioning needed when embedded)"""
	pass  # Panel position is managed by parent container

func set_target(target: Examinable) -> void:
	current_target = target

func clear_target() -> void:
	current_target = null

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

func _set_threat_colors(threat: int) -> void:
	"""Set label colors based on threat level"""
	var color: Color
	match threat:
		0, 1: color = Color.WHITE
		2: color = Color.YELLOW
		3, 4: color = Color.ORANGE
		5: color = Color.RED
		_: color = Color.GRAY

	threat_level_label.add_theme_color_override("font_color", color)

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
	if header_label:
		header_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	if entity_name_label:
		entity_name_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_ENTITY_NAME))
	if threat_level_label:
		threat_level_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	if description_label:
		description_label.add_theme_font_size_override("normal_font_size", _get_font_size(FONT_SIZE_DESCRIPTION))

func _on_scale_changed(_scale: float) -> void:
	"""Handle UI scale changes from UIScaleManager"""
	_update_all_font_sizes()
