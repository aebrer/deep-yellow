class_name ChunkLoadingIndicator
extends Label
## Viewport overlay showing chunk loading status
##
## Fades in when chunks are generating, shows animated dots,
## then displays "done" and fades out.

# ============================================================================
# CONSTANTS
# ============================================================================

const FADE_IN_DURATION := 0.3
const FADE_OUT_DURATION := 0.8
const FADE_OUT_DELAY := 0.6  # How long "done" stays visible before fading
const DOT_INTERVAL := 0.3  # Time between dot animation updates
const MAX_DOTS := 7

# ============================================================================
# STATE
# ============================================================================

enum State { HIDDEN, LOADING, DONE }
var current_state: State = State.HIDDEN

var fade_alpha: float = 0.0
var dot_count: int = 0
var dot_timer: float = 0.0
var done_timer: float = 0.0

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Style: bottom-center of viewport, monospace, understated
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -40
	offset_bottom = -12

	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", Color(0.6, 0.6, 0.5))
	modulate.a = 0.0
	text = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Connect to ChunkManager signals
	if ChunkManager:
		ChunkManager.chunk_updates_completed.connect(_on_chunks_done)

func _process(delta: float) -> void:
	match current_state:
		State.HIDDEN:
			# Check if ChunkManager is generating chunks
			if ChunkManager and ChunkManager.was_generating:
				_start_loading()
			return

		State.LOADING:
			# Fade in
			fade_alpha = minf(fade_alpha + delta / FADE_IN_DURATION, 1.0)
			modulate.a = fade_alpha

			# Animate dots
			dot_timer += delta
			if dot_timer >= DOT_INTERVAL:
				dot_timer = 0.0
				dot_count = (dot_count + 1) % (MAX_DOTS + 1)
				text = "chunk loading" + ".".repeat(dot_count)

		State.DONE:
			# Count down before fading
			done_timer -= delta
			if done_timer <= 0.0:
				# Fade out
				fade_alpha = maxf(fade_alpha - delta / FADE_OUT_DURATION, 0.0)
				modulate.a = fade_alpha
				if fade_alpha <= 0.0:
					current_state = State.HIDDEN
					text = ""

# ============================================================================
# STATE TRANSITIONS
# ============================================================================

func _start_loading() -> void:
	current_state = State.LOADING
	dot_count = 0
	dot_timer = 0.0
	text = "chunk loading"

func _on_chunks_done() -> void:
	if current_state == State.LOADING:
		current_state = State.DONE
		text = "chunk loading.......done"
		done_timer = FADE_OUT_DELAY
