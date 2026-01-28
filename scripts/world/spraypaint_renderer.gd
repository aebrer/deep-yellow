class_name SpraypaintRenderer extends Node3D
## Renders spraypaint text as Label3D nodes in the 3D world
##
## Manages Label3D nodes for spraypaint text stored in chunk data.
## Floor text is rotated to lie flat on the ground.
## Wall text faces outward from the wall surface.
##
## Spraypaint data format (Dictionary):
##   text: String - The text to display
##   world_position: Vector2i - World tile position
##   color: Color - Text color (default: white)
##   font_size: int - Font size (default: 48)
##   surface: String - "floor" or "wall" (default: "floor")
##   rotation_y: float - Y rotation in degrees (default: 0)
##
## Usage:
##   renderer.render_chunk_spraypaint(chunk)  # On chunk load
##   renderer.unload_chunk_spraypaint(chunk)  # On chunk unload

# ============================================================================
# DEPENDENCIES
# ============================================================================

## Font for spraypaint text (uses default font with emoji fallback)
const _SPRAYPAINT_FONT = preload("res://assets/fonts/default_font.tres")

@onready var grid_3d: Grid3D = get_parent()

# ============================================================================
# STATE
# ============================================================================

## Maps chunk position to array of Label3D nodes
var chunk_labels: Dictionary = {}  # Vector2i -> Array[Label3D]

# ============================================================================
# CONFIGURATION
# ============================================================================

## Default spraypaint text color (graffiti-style off-white)
const DEFAULT_COLOR := Color(0.9, 0.9, 0.85)

## Default font size
const DEFAULT_FONT_SIZE := 48

## Height above floor for floor spraypaint
## GridMap floor meshes sit at Y=0, so we need to be clearly above the surface.
## Y=0.51 places text at the top of the cell_size.y (1.0) / 2 = 0.5 midpoint,
## just above where the floor surface actually renders.
const FLOOR_HEIGHT := 0.51

## Outline size for readability against any surface
const OUTLINE_SIZE := 8

## Outline color (dark for contrast)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.6)

# ============================================================================
# CHUNK LOADING
# ============================================================================

func render_chunk_spraypaint(chunk: Chunk) -> void:
	"""Create Label3D nodes for all spraypaint text in chunk

	Args:
		chunk: Chunk that was just loaded
	"""
	var labels: Array[Label3D] = []

	for subchunk in chunk.sub_chunks:
		for spray_data in subchunk.spraypaint_data:
			var label := _create_spraypaint_label(spray_data)
			if label:
				add_child(label)
				labels.append(label)

	if not labels.is_empty():
		chunk_labels[chunk.position] = labels

func unload_chunk_spraypaint(chunk: Chunk) -> void:
	"""Remove Label3D nodes for all spraypaint text in chunk

	Args:
		chunk: Chunk being unloaded
	"""
	if not chunk_labels.has(chunk.position):
		return

	var labels: Array = chunk_labels[chunk.position]
	for label in labels:
		if is_instance_valid(label):
			label.queue_free()

	chunk_labels.erase(chunk.position)

# ============================================================================
# LABEL CREATION
# ============================================================================

func _create_spraypaint_label(spray_data: Dictionary) -> Label3D:
	"""Create a Label3D node for a spraypaint entry

	Args:
		spray_data: Dictionary with spraypaint data

	Returns:
		Label3D node or null if invalid data
	"""
	var text: String = spray_data.get("text", "")
	if text.is_empty():
		return null

	var world_pos_data = spray_data.get("world_position", {})
	var world_pos := Vector2i(
		world_pos_data.get("x", 0),
		world_pos_data.get("y", 0)
	)

	var color: Color = spray_data.get("color", DEFAULT_COLOR)
	var font_size: int = spray_data.get("font_size", DEFAULT_FONT_SIZE)
	var surface: String = spray_data.get("surface", "floor")
	var rotation_y: float = spray_data.get("rotation_y", 0.0)

	# Create Label3D
	var label := Label3D.new()
	label.text = text
	label.font = _SPRAYPAINT_FONT
	label.font_size = font_size
	label.modulate = color
	label.outline_size = OUTLINE_SIZE
	label.outline_modulate = OUTLINE_COLOR

	# Render on top of floor geometry (prevents depth-clipping by floor mesh)
	label.no_depth_test = true
	label.render_priority = 1

	# Double-sided so visible from both sides
	label.double_sided = true

	# Alpha cut for clean rendering
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED

	# Position and rotation based on surface type
	if surface == "floor":
		_setup_floor_label(label, world_pos, rotation_y)
	elif surface == "wall":
		_setup_wall_label(label, world_pos, rotation_y)

	return label

func _setup_floor_label(label: Label3D, world_pos: Vector2i, rotation_y: float) -> void:
	"""Position label flat on the floor

	Floor labels are rotated -90 degrees on X axis so they face upward,
	then rotated on Y axis for orientation.
	"""
	var world_3d: Vector3
	if grid_3d:
		world_3d = grid_3d.grid_to_world_centered(world_pos, FLOOR_HEIGHT)
	else:
		world_3d = Vector3(
			world_pos.x * 2.0 + 1.0,
			FLOOR_HEIGHT,
			world_pos.y * 2.0 + 1.0
		)

	label.position = world_3d

	# Rotate to lie flat on floor: -90° on X makes text face up
	# Then rotate on Y for text orientation
	label.rotation_degrees = Vector3(-90.0, rotation_y, 0.0)

func _setup_wall_label(label: Label3D, world_pos: Vector2i, rotation_y: float) -> void:
	"""Position label on a wall face

	Wall labels are placed at wall height, facing outward.
	rotation_y determines which wall face (0=north, 90=east, 180=south, 270=west).
	"""
	var wall_height := 0.5  # Mid-wall height

	var world_3d: Vector3
	if grid_3d:
		world_3d = grid_3d.grid_to_world_centered(world_pos, wall_height)
	else:
		world_3d = Vector3(
			world_pos.x * 2.0 + 1.0,
			wall_height,
			world_pos.y * 2.0 + 1.0
		)

	label.position = world_3d
	label.rotation_degrees = Vector3(0.0, rotation_y, 0.0)

# ============================================================================
# DYNAMIC SPRAYPAINT (for adding text at runtime)
# ============================================================================

func add_spraypaint(world_pos: Vector2i, text: String, color: Color = DEFAULT_COLOR,
		font_size: int = DEFAULT_FONT_SIZE, surface: String = "floor",
		rotation_y: float = 0.0) -> void:
	"""Add spraypaint text to the world and store in chunk data

	Creates the Label3D immediately and stores data in the SubChunk
	for persistence across chunk load/unload cycles.

	Args:
		world_pos: World tile position
		text: Text to display
		color: Text color
		font_size: Font size
		surface: "floor" or "wall"
		rotation_y: Y rotation in degrees
	"""
	# Build spray data dictionary
	var spray_data := {
		"text": text,
		"world_position": {"x": world_pos.x, "y": world_pos.y},
		"color": color,
		"font_size": font_size,
		"surface": surface,
		"rotation_y": rotation_y,
	}

	# Determine chunk position for storage and tracking
	var chunk_pos := Vector2i.ZERO
	if ChunkManager:
		chunk_pos = ChunkManager.tile_to_chunk(world_pos)

	# Store in SubChunk for persistence
	if ChunkManager:
		var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, 0)
		var chunk: Chunk = ChunkManager.loaded_chunks.get(chunk_key, null)
		if chunk:
			var subchunk := chunk.get_sub_chunk_at_tile(world_pos)
			if subchunk:
				subchunk.spraypaint_data.append(spray_data)

	# Create label immediately if chunk is loaded
	var label := _create_spraypaint_label(spray_data)
	if label:
		add_child(label)
		print("[SpraypaintRenderer] Added spraypaint '%s' at %s (3D pos: %s)" % [text, world_pos, label.position])

		# Track with chunk for cleanup
		if not chunk_labels.has(chunk_pos):
			chunk_labels[chunk_pos] = []
		chunk_labels[chunk_pos].append(label)
	else:
		print("[SpraypaintRenderer] WARNING: Failed to create label for '%s'" % text)

# ============================================================================
# CLEANUP
# ============================================================================

func clear_all_spraypaint() -> void:
	"""Remove all spraypaint labels (called on level unload)"""
	for labels in chunk_labels.values():
		for label in labels:
			if is_instance_valid(label):
				label.queue_free()
	chunk_labels.clear()
