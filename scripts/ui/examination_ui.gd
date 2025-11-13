class_name ExaminationUI
extends Control
## UI overlay for look mode examination
##
## Shows crosshair and SCP-style examination panel

# Node references (will be set manually since we're creating programmatically)
var crosshair: Control  # Container holding crosshair lines
var panel: PanelContainer
var scroll_container: ScrollContainer
var entity_name_label: Label
var object_class_label: Label
var threat_level_label: Label
var description_label: RichTextLabel

# State
var current_target: Examinable = null

# Scroll settings
const SCROLL_SPEED: float = 50.0  # Pixels per scroll event

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	Log.system("ExaminationUI _ready() called")
	# Build UI programmatically
	_build_ui()

	# Hide everything by default
	crosshair.visible = false
	panel.visible = false
	Log.system("ExaminationUI initialization complete")

func _build_ui() -> void:
	"""Build examination UI programmatically"""
	# Set control to fill viewport
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input

	# Create crosshair container (center of screen)
	var crosshair_container = Control.new()
	crosshair_container.name = "CrosshairContainer"
	crosshair_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Manually set to fill parent (anchors aren't working)
	crosshair_container.anchor_left = 0.0
	crosshair_container.anchor_top = 0.0
	crosshair_container.anchor_right = 1.0
	crosshair_container.anchor_bottom = 1.0
	crosshair_container.offset_left = 0.0
	crosshair_container.offset_top = 0.0
	crosshair_container.offset_right = 0.0
	crosshair_container.offset_bottom = 0.0
	add_child(crosshair_container)

	# Create crosshair as a simple cross (vertical and horizontal lines)
	# Vertical line
	var vertical_line = ColorRect.new()
	vertical_line.name = "VerticalLine"
	vertical_line.size = Vector2(2, 20)  # 2px wide, 20px tall
	vertical_line.color = Color.WHITE
	vertical_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical_line.set_anchors_preset(Control.PRESET_CENTER)
	vertical_line.position = Vector2(-1, -10)  # Offset from anchor center
	crosshair_container.add_child(vertical_line)

	# Horizontal line
	var horizontal_line = ColorRect.new()
	horizontal_line.name = "HorizontalLine"
	horizontal_line.size = Vector2(20, 2)  # 20px wide, 2px tall
	horizontal_line.color = Color.WHITE
	horizontal_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_line.set_anchors_preset(Control.PRESET_CENTER)
	horizontal_line.position = Vector2(-10, -1)  # Offset from anchor center
	crosshair_container.add_child(horizontal_line)

	# Store reference to container (so we can show/hide it)
	crosshair = crosshair_container

	# Debug: Log crosshair setup
	Log.system("Crosshair created - Container size: %s, V-line size: %s, H-line size: %s" % [
		crosshair_container.size,
		vertical_line.size,
		horizontal_line.size
	])

	# Create examination panel (left third of screen)
	panel = PanelContainer.new()
	panel.name = "ExaminationPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	# Position panel on left side, full height, 1/3 width
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.33  # Left third
	panel.anchor_bottom = 1.0
	panel.offset_left = 16  # Small margin from edge
	panel.offset_top = 16
	panel.offset_right = -16  # Small margin from 1/3 mark
	panel.offset_bottom = -16

	# Style panel (SCP aesthetic)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.9)  # Nearly opaque black
	style.border_color = Color(1, 1, 1, 1)  # White border
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	# Add ScrollContainer for overflow handling
	scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer"
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll_container)

	# Panel content container
	var vbox = VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "OBJECT EXAMINATION REPORT"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(header)

	# Separator
	var separator1 = HSeparator.new()
	separator1.add_theme_constant_override("separation", 8)
	vbox.add_child(separator1)

	# Entity name
	entity_name_label = Label.new()
	entity_name_label.text = "Entity: Unknown"
	entity_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entity_name_label.add_theme_font_size_override("font_size", 18)
	entity_name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(entity_name_label)

	# Object class
	object_class_label = Label.new()
	object_class_label.text = "Class: Unknown"
	object_class_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	object_class_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(object_class_label)

	# Threat level
	threat_level_label = Label.new()
	threat_level_label.text = "Threat: Unknown"
	threat_level_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	threat_level_label.add_theme_font_size_override("font_size", 14)
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
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # Wrap text to fit width
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_label.add_theme_font_size_override("normal_font_size", 14)
	description_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(description_label)

# ============================================================================
# CROSSHAIR
# ============================================================================

func show_crosshair() -> void:
	crosshair.visible = true
	crosshair.modulate = Color.WHITE  # Reset to default color
	Log.system("Crosshair shown - Visible: %s, Size: %s, Position: %s, Modulate: %s" % [
		crosshair.visible,
		crosshair.size,
		crosshair.position,
		crosshair.modulate
	])

func hide_crosshair() -> void:
	crosshair.visible = false

func set_crosshair_color(color: Color) -> void:
	"""Change crosshair color based on target type"""
	crosshair.modulate = color

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	"""Handle scroll inputs when panel is visible"""
	if not panel.visible:
		return

	# Scroll wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_scroll_panel(-SCROLL_SPEED)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_scroll_panel(SCROLL_SPEED)
			get_viewport().set_input_as_handled()

	# RB/LB for scrolling (shoulder buttons)
	if event.is_action_pressed("camera_zoom_in"):  # LB
		_scroll_panel(-SCROLL_SPEED)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_out"):  # RB
		_scroll_panel(SCROLL_SPEED)
		get_viewport().set_input_as_handled()

func _scroll_panel(amount: float) -> void:
	"""Scroll the examination panel by amount (positive = down, negative = up)"""
	if scroll_container:
		var new_scroll = scroll_container.scroll_vertical + amount
		scroll_container.scroll_vertical = max(0, new_scroll)

# ============================================================================
# EXAMINATION PANEL
# ============================================================================

func show_panel(target: Examinable) -> void:
	"""Display examination info for target"""
	if not target:
		hide_panel()
		return

	# Reset scroll position when showing new target
	if scroll_container:
		scroll_container.scroll_vertical = 0

	# Get entity info from knowledge database
	var info = KnowledgeDB.get_entity_info(target.entity_id)

	# Update labels
	entity_name_label.text = "Entity: " + info.get("name", "Unknown")
	object_class_label.text = "Class: " + info.get("object_class", "[REDACTED]")
	threat_level_label.text = "Threat: " + _format_threat_level(info.get("threat_level", 0))
	description_label.text = info.get("description", "[DATA EXPUNGED]")

	# Set colors based on threat
	var threat = info.get("threat_level", 0)
	_set_threat_colors(threat)

	# Set crosshair color
	var entity_type = target.entity_type
	set_crosshair_color(_get_entity_type_color(entity_type))

	# Show panel
	panel.visible = true

func hide_panel() -> void:
	panel.visible = false

func set_target(target: Examinable) -> void:
	current_target = target

func clear_target() -> void:
	current_target = null

# ============================================================================
# FORMATTING HELPERS
# ============================================================================

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

func _get_entity_type_color(entity_type: Examinable.EntityType) -> Color:
	"""Get crosshair color for entity type"""
	match entity_type:
		Examinable.EntityType.ENTITY_HOSTILE:
			return Color.RED
		Examinable.EntityType.ENTITY_NEUTRAL:
			return Color.ORANGE
		Examinable.EntityType.ENTITY_FRIENDLY:
			return Color.GREEN
		Examinable.EntityType.HAZARD:
			return Color.YELLOW
		Examinable.EntityType.ITEM:
			return Color.CYAN
		Examinable.EntityType.ENVIRONMENT:
			return Color.WHITE
		_:
			return Color.GRAY
