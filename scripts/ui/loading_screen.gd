extends CanvasLayer
## Simple loading screen for initial chunk generation
##
## Shows "Generating [Level Name]..." with progress bar
## Automatically hides when ChunkManager emits initial_load_completed

@onready var loading_label: Label = %LoadingLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var progress_label: Label = %ProgressLabel

func _ready() -> void:
	# Connect to ChunkManager signals
	if ChunkManager:
		ChunkManager.initial_load_progress.connect(_on_load_progress)
		ChunkManager.initial_load_completed.connect(_on_load_completed)

	# Set initial level name (default to Level 0)
	var level_name := "Level 0"
	if LevelManager:
		var current_level = LevelManager.get_current_level()
		if current_level:
			level_name = current_level.display_name

	loading_label.text = "Generating %s..." % level_name

	# Start visible
	show()

func _on_load_progress(loaded_count: int, total_count: int) -> void:
	"""Update progress bar and label"""
	var progress := float(loaded_count) / float(total_count)
	progress_bar.value = progress
	progress_label.text = "%d / %d chunks" % [loaded_count, total_count]

func _on_load_completed() -> void:
	"""Hide loading screen when initial load completes"""
	hide()
