class_name Player
extends Node2D
## Player controller - manages player state, input, and visual representation
##
## Uses:
## - InputStateMachine for turn-based input handling
## - Grid for map queries and validation
## - Action system for turn execution

const TILE_SIZE := 32

## Current grid position
var grid_position: Vector2i = Vector2i(64, 64)

## Current movement target (for aiming indicator)
var movement_target: Vector2i = Vector2i.ZERO

## Pending action to execute (set by states)
var pending_action: Action = null

## Turn counter
var turn_count: int = 0

## Reference to grid
var grid: Grid = null

## References to child nodes
@onready var state_machine: InputStateMachine = $InputStateMachine
@onready var sprite: Label = $Sprite
@onready var move_indicator: Label = $MoveIndicator
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	print("[Player] Ready at position: ", grid_position)

	# Setup sprite
	sprite.text = "🚶"
	sprite.size = Vector2(TILE_SIZE, TILE_SIZE)
	sprite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sprite.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Setup move indicator
	move_indicator.size = Vector2(TILE_SIZE, TILE_SIZE)
	move_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	move_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	move_indicator.visible = false

	# Update visual position
	update_visual_position()

func _unhandled_input(event: InputEvent) -> void:
	# System actions (pause) handled here, not in states
	if event.is_action_pressed("pause"):
		print("[Player] Pause pressed - returning to menu")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	# Delegate gameplay input to state machine
	state_machine.handle_input(event)

func _process(delta: float) -> void:
	# Delegate frame processing to state machine
	state_machine.process_frame(delta)

func update_visual_position() -> void:
	"""Update sprite and camera to match grid position"""
	# Render tiles around new position
	if grid:
		grid.render_around_position(grid_position)

	# Update sprite position
	var world_pos = grid.grid_to_world(grid_position) if grid else Vector2(grid_position) * TILE_SIZE
	sprite.position = world_pos

	# Camera follows player
	camera.position = sprite.position + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)

func update_move_indicator() -> void:
	"""Update the movement preview indicator"""
	if movement_target == Vector2i.ZERO:
		hide_move_indicator()
		return

	var target_pos = grid_position + movement_target

	# Check if target is valid
	var is_valid = grid.is_walkable(target_pos) if grid else false

	if is_valid:
		move_indicator.modulate = Color.GREEN
		move_indicator.text = "→"
	else:
		move_indicator.modulate = Color.RED
		move_indicator.text = "✗"

	var world_pos = grid.grid_to_world(target_pos) if grid else Vector2(target_pos) * TILE_SIZE
	move_indicator.position = world_pos
	move_indicator.visible = true

func hide_move_indicator() -> void:
	"""Hide the movement preview indicator"""
	move_indicator.visible = false

func set_grid(new_grid: Grid) -> void:
	"""Set the grid reference"""
	grid = new_grid
	print("[Player] Grid reference set")
