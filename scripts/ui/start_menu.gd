extends Control
## Simple start menu for web exports
##
## Provides user interaction needed for mouse capture in browsers.
## Click "Start Game" button → loads game scene → mouse ready to capture.

@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel

func _ready() -> void:
	# Connect button
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
		start_button.grab_focus()

	# Show platform info for debugging
	if OS.has_feature("web"):
		print("[StartMenu] Web export detected - click will enable mouse capture")

func _on_start_pressed() -> void:
	print("[StartMenu] Starting game...")
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _input(event: InputEvent) -> void:
	# Also allow Space/Enter or any gamepad button to start
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("move_confirm"):
		_on_start_pressed()
