extends Control
## Main Menu
## Temporary placeholder during initial development

func _ready() -> void:
	print("Backrooms Power Crawl - Main Menu loaded")
	print("Project initialized successfully!")

func _process(_delta: float) -> void:
	# Listen for START button to begin
	if Input.is_action_just_pressed("pause"):
		print("START pressed - No game scene yet!")
		# TODO: Load game scene when ready
		# get_tree().change_scene_to_file("res://scenes/game.tscn")
