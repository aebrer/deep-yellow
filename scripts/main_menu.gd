extends Control
## Main Menu - Entry point for the game
##
## Simple menu with controller/keyboard support
## Uses clean input handling (no need for state machine here)

@onready var status_label: Label = $CenterContainer/VBoxContainer/Status

func _ready() -> void:
	print("[MainMenu] Loaded")
	print("[MainMenu] Waiting for input...")

	# InputManager will show connected controllers automatically
	if InputManager:
		print("[MainMenu] InputManager active")

func _input(event: InputEvent) -> void:
	# Start game with pause action (START button or ESCAPE)
	if event.is_action_pressed("pause"):
		_start_game()

	# Quit with inventory action (SELECT button or I key)
	if event.is_action_pressed("inventory"):
		_quit_game()

	# Keyboard fallback: SPACE also starts
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_start_game()

	# Keyboard fallback: ESC also quits
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_quit_game()

func _start_game() -> void:
	print("[MainMenu] Starting game...")
	status_label.text = "Loading game..."
	status_label.modulate = Color.GREEN
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _quit_game() -> void:
	print("[MainMenu] Quitting...")
	get_tree().quit()
