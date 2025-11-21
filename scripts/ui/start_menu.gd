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

	# Immediate visual feedback - disable button and change text
	if start_button:
		start_button.disabled = true
		start_button.text = "Loading..."

	# Wait a couple frames for UI to update visually before scene change
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/game.tscn")

var _starting := false  # Prevent double-triggering from multiple input methods

func _input(event: InputEvent) -> void:
	# Handle raw controller/keyboard input (START button, LMB)
	# Use _input() to intercept BEFORE PauseManager's _unhandled_input()
	if _starting:
		return  # Already starting, ignore additional inputs

	# Check for pause action (START button) - must intercept before PauseManager
	if event.is_action_pressed("pause"):
		_starting = true
		_on_start_pressed()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	# Handle synthesized actions from InputManager (RT via trigger axis)
	# RT synthesizes "move_confirm" action which isn't in raw events
	if _starting:
		return  # Already starting, ignore additional inputs

	if InputManager:
		var move_pressed = InputManager.is_action_just_pressed("move_confirm")
		if move_pressed:
			_starting = true
			_on_start_pressed()
