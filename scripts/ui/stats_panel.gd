extends VBoxContainer
"""Stats display panel with interactive elements.

Shows:
- Base stats (BODY, MIND, NULL) with resource pools
- Combat stats (STRENGTH, PERCEPTION, ANOMALY)
- Progression (EXP, Clearance Level)

Updates in real-time as stats change.
"""

var player: Player3D = null
var tooltip_labels: Array[Label] = []
var tooltip_texts: Dictionary = {}  # label -> tooltip_text (stored separately to disable native tooltips)

# Tooltip overlay (created programmatically, positioned absolutely)
var tooltip_panel: PanelContainer = null
var tooltip_label: Label = null

# Base Stats & Resources
@onready var body_label: Label = %BodyLabel
@onready var mind_label: Label = %MindLabel
@onready var null_label: Label = %NullLabel

@onready var hp_label: Label = %HPLabel
@onready var sanity_label: Label = %SanityLabel
@onready var mana_label: Label = %ManaLabel

# Combat Stats
@onready var strength_label: Label = %StrengthLabel
@onready var perception_label: Label = %PerceptionLabel
@onready var anomaly_label: Label = %AnomalyLabel

# Progression
@onready var level_label: Label = %LevelLabel
@onready var exp_label: Label = %EXPLabel
@onready var clearance_label: Label = %ClearanceLabel

func _ready():
	# Wait for player to be set by Game node
	await get_tree().process_frame

	# Build tooltip overlay
	_build_tooltip_overlay()

	# Setup hover/focus highlighting for all labels with tooltips
	_setup_label_highlights()

	# Connect to pause manager to clear focus when unpausing
	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)

	if player and player.stats:
		_connect_signals()
		_update_all_stats()
	else:
		Log.warn(Log.Category.SYSTEM, "StatsPanel: No player or stats found")

func _build_tooltip_overlay() -> void:
	"""Build tooltip overlay (positioned absolutely, no layout reflow)"""
	# Get the root game Control to add overlay
	var game_root = get_tree().root.get_node_or_null("Game")
	if not game_root:
		return

	# Create tooltip panel positioned at bottom-center
	tooltip_panel = PanelContainer.new()
	tooltip_panel.name = "StatsTooltipOverlay"
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.visible = false

	# Position at bottom-center
	tooltip_panel.anchor_left = 0.5
	tooltip_panel.anchor_right = 0.5
	tooltip_panel.anchor_top = 1.0
	tooltip_panel.anchor_bottom = 1.0
	tooltip_panel.offset_left = -200  # 400px wide centered
	tooltip_panel.offset_right = 200
	tooltip_panel.offset_bottom = -80  # 80px from bottom
	tooltip_panel.offset_top = -130    # 50px tall
	tooltip_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# Style (matching ActionPreviewUI)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.9)
	style.border_color = Color(1, 1, 1, 1)
	style.set_border_width_all(2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	tooltip_panel.add_theme_stylebox_override("panel", style)

	# Tooltip text label
	tooltip_label = Label.new()
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tooltip_label.add_theme_font_size_override("font_size", 14)
	tooltip_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	tooltip_panel.add_child(tooltip_label)

	# Add to game root (not to StatsPanel to avoid layout issues)
	game_root.add_child(tooltip_panel)

func set_player(p: Player3D) -> void:
	"""Called by Game node to set player reference"""
	player = p
	if player and player.stats:
		_connect_signals()
		_update_all_stats()

func _connect_signals() -> void:
	"""Connect to StatBlock signals for real-time updates"""
	if not player or not player.stats:
		return

	# Check if already connected to avoid duplicate connections
	if player.stats.stat_changed.is_connected(_on_stat_changed):
		return  # Already connected

	# Stat changes
	player.stats.stat_changed.connect(_on_stat_changed)

	# Resource changes
	player.stats.resource_changed.connect(_on_resource_changed)

	# Progression
	player.stats.exp_gained.connect(_on_exp_gained)
	player.stats.level_increased.connect(_on_level_increased)
	player.stats.clearance_increased.connect(_on_clearance_increased)

func _update_all_stats() -> void:
	"""Update all stat displays"""
	if not player or not player.stats:
		return

	var s = player.stats

	# Base stats
	if body_label:
		body_label.text = "BODY: %d" % s.body
	if mind_label:
		mind_label.text = "MIND: %d" % s.mind
	if null_label:
		null_label.text = "NULL: %d" % s.null_stat

	# Resources
	if hp_label:
		hp_label.text = "HP: %.0f / %.0f" % [s.current_hp, s.max_hp]
	if sanity_label:
		sanity_label.text = "Sanity: %.0f / %.0f" % [s.current_sanity, s.max_sanity]
	if mana_label:
		if s.null_stat > 0:
			mana_label.text = "Mana: %.0f / %.0f" % [s.current_mana, s.max_mana]
		else:
			mana_label.text = "Mana: [LOCKED]"

	# Combat stats
	if strength_label:
		strength_label.text = "STRENGTH: %.0f" % s.strength
	if perception_label:
		perception_label.text = "PERCEPTION: %.0f" % s.perception
	if anomaly_label:
		anomaly_label.text = "ANOMALY: %.0f" % s.anomaly

	# Progression
	if level_label:
		level_label.text = "Level: %d" % s.level
	if exp_label:
		var next_exp = s.exp_to_next_level()
		exp_label.text = "EXP: %d / %d" % [s.exp, s.exp + next_exp]
	if clearance_label:
		clearance_label.text = "Clearance: %d" % s.clearance_level

# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

func _on_stat_changed(stat_name: String, _old_value: float, _new_value: float) -> void:
	"""Update display when a stat changes"""
	# Just refresh everything for simplicity
	_update_all_stats()

func _on_resource_changed(resource_name: String, current: float, maximum: float) -> void:
	"""Update resource display"""
	match resource_name:
		"hp":
			if hp_label:
				hp_label.text = "HP: %.0f / %.0f" % [current, maximum]
		"sanity":
			if sanity_label:
				sanity_label.text = "Sanity: %.0f / %.0f" % [current, maximum]
		"mana":
			if mana_label:
				mana_label.text = "Mana: %.0f / %.0f" % [current, maximum]

func _on_exp_gained(_amount: int, new_total: int) -> void:
	"""Update EXP display"""
	if exp_label and player and player.stats:
		var next_exp = player.stats.exp_to_next_level()
		exp_label.text = "EXP: %d / %d" % [new_total, new_total + next_exp]

func _on_level_increased(_old_level: int, new_level: int) -> void:
	"""Update Level display"""
	if level_label:
		level_label.text = "Level: %d" % new_level

	# Refresh EXP display (threshold changed)
	if player and player.stats:
		_on_exp_gained(0, player.stats.exp)

func _on_clearance_increased(_old_level: int, new_level: int) -> void:
	"""Update Clearance display"""
	if clearance_label:
		clearance_label.text = "Clearance: %d" % new_level

# ============================================================================
# HOVER/FOCUS HIGHLIGHTING
# ============================================================================

func _setup_label_highlights() -> void:
	"""Setup unified hover/focus system for all labels with tooltips"""
	tooltip_labels = [
		body_label, mind_label, null_label,
		hp_label, sanity_label, mana_label,
		strength_label, perception_label, anomaly_label,
		level_label, exp_label, clearance_label
	]

	for label in tooltip_labels:
		if label and not label.tooltip_text.is_empty():
			# Store tooltip text and clear from label (disables native tooltips)
			tooltip_texts[label] = label.tooltip_text
			label.tooltip_text = ""

			# Add to hud_focusable group (so PauseManager can find it)
			label.add_to_group("hud_focusable")

			# Connect hover signals (always active)
			label.mouse_entered.connect(_on_label_hovered.bind(label))
			label.mouse_exited.connect(_on_label_unhovered.bind(label))

			# Connect focus signals (controller - only when paused)
			label.focus_entered.connect(_on_label_focused.bind(label))
			label.focus_exited.connect(_on_label_unfocused.bind(label))

			# Make focusable immediately (controller navigation only works when paused)
			label.focus_mode = Control.FOCUS_ALL

func _on_label_hovered(label: Label) -> void:
	"""Highlight label on mouse hover"""
	_highlight_label(label)

func _on_label_unhovered(label: Label) -> void:
	"""Remove highlight when mouse leaves"""
	_unhighlight_label(label)

func _on_label_focused(label: Label) -> void:
	"""Highlight label when focused (controller)"""
	_highlight_label(label)

func _on_label_unfocused(label: Label) -> void:
	"""Remove highlight when focus lost"""
	_unhighlight_label(label)

func _highlight_label(label: Label) -> void:
	"""Apply visual highlight and show tooltip (unified for mouse and controller)"""
	# Create a StyleBoxFlat for the background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 0.5, 0.3)  # Yellow transparent
	style.border_color = Color(1.0, 1.0, 0.5, 0.8)  # Yellow border
	style.set_border_width_all(2)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2

	# Override BOTH normal and focus to disable Godot's built-in focus indicator
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_stylebox_override("focus", style)  # Same style for focus = no dual highlights

	# Show tooltip in overlay
	if tooltip_panel and tooltip_label and label in tooltip_texts:
		tooltip_label.text = tooltip_texts[label]
		tooltip_panel.visible = true

func _unhighlight_label(label: Label) -> void:
	"""Remove visual highlight and hide tooltip"""
	label.remove_theme_stylebox_override("normal")
	label.remove_theme_stylebox_override("focus")  # Remove both overrides

	# Hide tooltip overlay
	if tooltip_panel:
		tooltip_panel.visible = false

func _on_pause_toggled(is_paused: bool) -> void:
	"""Clear highlights when unpausing"""
	if not is_paused:
		# Clear any highlights and focus when returning to gameplay
		for label in tooltip_labels:
			if label:
				if label.has_focus():
					label.release_focus()
				_unhighlight_label(label)
