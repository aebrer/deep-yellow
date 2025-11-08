class_name PlayerInputState
extends Node
## Base class for all player input states
##
## States represent different input handling modes:
## - IdleState: No input, waiting for player action
## - AimingMoveState: Player is aiming movement with stick
## - ExecutingTurnState: Processing turn, blocked from input
## - (Future: ExamineModeState, AbilityTargetingState, etc.)
##
## States communicate with InputStateMachine via signals to request transitions

## Emitted when this state wants to transition to another state
signal state_transition_requested(new_state_name: String)

## Reference to player (set by state machine)
var player = null

## Reference to state machine (set by state machine)
var state_machine = null

## State name for debugging
var state_name: String = "BaseState"

# ============================================================================
# STATE LIFECYCLE
# ============================================================================

## Called when entering this state
func enter() -> void:
	if InputManager.debug_input:
		print("[State] Entered: ", state_name)

## Called when exiting this state
func exit() -> void:
	if InputManager.debug_input:
		print("[State] Exited: ", state_name)

# ============================================================================
# INPUT HANDLING
# ============================================================================

## Handle input events (called from player's _unhandled_input)
func handle_input(event: InputEvent) -> void:
	pass  # Override in subclasses

## Called every frame (from player's _process)
func process_frame(delta: float) -> void:
	pass  # Override in subclasses

# ============================================================================
# STATE TRANSITIONS
# ============================================================================

## Request a transition to another state
func transition_to(new_state_name: String) -> void:
	state_transition_requested.emit(new_state_name)
