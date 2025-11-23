class_name ExaminationPanel
extends Control
## Examination text panel - lives in main viewport (always clean text)

# Node references
var panel: PanelContainer
var scroll_container: ScrollContainer
var entity_name_label: Label
var object_class_label: Label
var threat_level_label: Label
var description_label: RichTextLabel

# State
var current_target: Examinable = null
var _is_portrait_mode: bool = false

# Scroll settings
const SCROLL_SPEED: float = 50.0

func _ready() -> void:
	# Fill screen for positioning
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_panel()

	# Hide by default
	panel.visible = false

func _build_panel() -> void:
	"""Build examination panel (left third of screen)"""
	panel = PanelContainer.new()
	panel.name = "ExaminationPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	# Position on left side, full height, 1/3 width
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.33
	panel.anchor_bottom = 1.0
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_right = -16
	panel.offset_bottom = -16

	# Style panel (SCP aesthetic)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.9)
	style.border_color = Color(1, 1, 1, 1)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	# ScrollContainer for overflow
	scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer"
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll_container)

	# Content container
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
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_label.add_theme_font_size_override("normal_font_size", 14)
	description_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(description_label)

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

	# RB/LB for scrolling
	if event.is_action_pressed("camera_zoom_in"):
		_scroll_panel(-SCROLL_SPEED)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_out"):
		_scroll_panel(SCROLL_SPEED)
		get_viewport().set_input_as_handled()

func _scroll_panel(amount: float) -> void:
	"""Scroll the panel"""
	if scroll_container:
		var new_scroll = scroll_container.scroll_vertical + amount
		scroll_container.scroll_vertical = max(0, new_scroll)

func show_panel(target: Examinable) -> void:
	"""Display examination info for target"""
	if not target:
		hide_panel()
		return

	# Reset scroll
	if scroll_container:
		scroll_container.scroll_vertical = 0

	# Get entity info
	var info = KnowledgeDB.get_entity_info(target.entity_id)

	# Update labels
	entity_name_label.text = "Entity: " + info.get("name", "Unknown")
	object_class_label.text = "Class: " + info.get("object_class", "[REDACTED]")
	threat_level_label.text = "Threat: " + _format_threat_level(info.get("threat_level", 0))
	description_label.text = info.get("description", "[DATA EXPUNGED]")

	# Set colors based on threat
	var threat = info.get("threat_level", 0)
	_set_threat_colors(threat)

	# Show panel
	panel.visible = true

func hide_panel() -> void:
	"""Hide the panel"""
	panel.visible = false

func set_portrait_mode(is_portrait: bool) -> void:
	"""Switch between portrait (bottom overlay) and landscape (left side) positioning"""
	_is_portrait_mode = is_portrait

	if is_portrait:
		# Portrait mode: Bottom ~1/3 overlay, landscape orientation
		panel.anchor_left = 0.0
		panel.anchor_top = 0.67  # Start at 2/3 down the screen
		panel.anchor_right = 1.0
		panel.anchor_bottom = 1.0
		panel.offset_left = 8
		panel.offset_top = 8
		panel.offset_right = -8
		panel.offset_bottom = -8
	else:
		# Landscape mode: Left 1/3, full height
		panel.anchor_left = 0.0
		panel.anchor_top = 0.0
		panel.anchor_right = 0.33
		panel.anchor_bottom = 1.0
		panel.offset_left = 16
		panel.offset_top = 16
		panel.offset_right = -16
		panel.offset_bottom = -16

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
