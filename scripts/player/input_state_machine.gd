class_name InputStateMachine
extends Node
## State machine for managing player input states
##
## This node should be a child of the Player node.
## All states should be children of this node.
##
## States are automatically registered on _ready()
## and can transition between each other via signals.
##
## Usage:
##   Player/
##     ├─ InputStateMachine/
##     │   ├─ IdleState
##     │   └─ ExecutingTurnState
##     └─ ... (other player components)

## Currently active state
var current_state: PlayerInputState = null

## Dictionary of all registered states (name -> state node)
var states: Dictionary = {}

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Wait one frame so all children are ready
	await get_tree().process_frame

	# Register all child states
	for child in get_children():
		if child is PlayerInputState:
			_register_state(child)

	# Start with first state if no explicit initial state is set
	if states.size() > 0 and current_state == null:
		var first_state_name = states.keys()[0]
		change_state(first_state_name)

	# Connect to PauseManager to exit LookModeState when paused
	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)

	Log.system("InputStateMachine ready with %d states" % states.size())

func _register_state(state: PlayerInputState) -> void:
	"""Register a state and connect its signals"""
	states[state.name] = state
	state.player = get_parent()  # Assumes parent is Player
	state.state_machine = self
	state.state_transition_requested.connect(_on_state_transition_requested)
	Log.state("Registered state: %s" % state.name)

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

func change_state(new_state_name: String) -> void:
	"""Change to a new state"""
	if not new_state_name in states:
		push_warning("[InputStateMachine] State not found: " + new_state_name)
		return

	# Exit current state
	if current_state:
		current_state.exit()

	# Enter new state
	current_state = states[new_state_name]
	current_state.enter()

	if InputManager and InputManager.debug_input:
		Log.state_info("State changed: %s" % new_state_name)

func get_current_state_name() -> String:
	"""Get name of current state for debugging"""
	if current_state:
		return current_state.name
	else:
		return ""

# ============================================================================
# INPUT DELEGATION
# ============================================================================

## Delegate input to current state
func handle_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

## Delegate frame processing to current state
func process_frame(delta: float) -> void:
	if current_state:
		current_state.process_frame(delta)

# ============================================================================
# SIGNALS
# ============================================================================

func _on_state_transition_requested(new_state_name: String) -> void:
	"""Handle state transition requests from states"""
	change_state(new_state_name)

func _on_pause_toggled(is_paused: bool) -> void:
	"""Handle pause state changes - exit LookModeState when paused

	LookModeState activates the first-person camera which requires get_tree().root
	access. If the player dies while in LookModeState and game over triggers pause,
	the scene may be in a transitional state. Exit to IdleState to prevent errors.
	"""
	if is_paused and current_state and current_state.name == "LookModeState":
		Log.state("Pause activated while in LookModeState - exiting to IdleState")
		change_state("IdleState")
