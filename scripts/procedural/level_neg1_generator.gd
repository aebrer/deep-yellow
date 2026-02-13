class_name LevelNeg1Generator extends LevelGenerator
## Level -1: Kingston, Ontario — Hand-crafted tutorial level
##
## Linear sequence of rooms teaching core mechanics:
##   [Room 1: Spawn] → [Hallway 1] → [Room 2: Item] → [Hallway 2] → [Room 3: Combat] → [Exit]
##
## Only generates content for chunk (0,0). All other chunks are solid walls.

# Tile types (SubChunk.TileType)
const FLOOR := 0
const WALL := 1
const CEILING := 2
const EXIT_STAIRS := 3

func _init() -> void:
	var config := ProceduralLevelConfig.new()
	config.level_id = -1
	config.level_name = "Level -1 - Kingston, Ontario"
	config.corruption_per_chunk = 0.0
	setup_level_config(config)

func generate_chunk(chunk: Chunk, _world_seed: int) -> void:
	"""Generate hand-crafted tutorial layout for chunk (0,0) only"""

	# Only chunk (0,0) has content — everything else is solid wall
	if chunk.position != Vector2i(0, 0):
		_fill_walls(chunk)
		return

	# Start with all walls
	_fill_walls(chunk)

	# Carve the tutorial layout
	_carve_room_1_spawn(chunk)
	_carve_hallway_1(chunk)
	_carve_room_2_item(chunk)
	_carve_hallway_2(chunk)
	_carve_room_3_combat(chunk)
	_carve_exit_hallway(chunk)
	_carve_exit_area(chunk)

	# Place entities and items
	_place_tutorial_content(chunk)

	chunk.state = Chunk.State.LOADED

func _fill_walls(chunk: Chunk) -> void:
	"""Fill entire chunk with walls (default state)"""
	for y in range(Chunk.SIZE):
		for x in range(Chunk.SIZE):
			var pos := Vector2i(x, y)
			chunk.set_tile(pos, WALL)

func _carve_floor(chunk: Chunk, x: int, y: int) -> void:
	"""Carve a single floor tile with ceiling above"""
	var pos := Vector2i(x, y)
	chunk.set_tile(pos, FLOOR)
	chunk.set_tile_at_layer(pos, 1, CEILING)

func _carve_rect(chunk: Chunk, x1: int, y1: int, x2: int, y2: int) -> void:
	"""Carve a rectangular area of floor tiles"""
	for y in range(y1, y2):
		for x in range(x1, x2):
			_carve_floor(chunk, x, y)

# ============================================================================
# ROOM LAYOUT — All coordinates are local to chunk (0-127)
# Layout runs south-to-north (decreasing Y): spawn at high Y, exit at low Y
# Player faces "forward" (increasing Y maps to default camera forward),
# so we spawn at low Y and exit at high Y.
# ============================================================================

# Room 1: Spawn (8×8, centered at x=64, y=16-24) — player starts here
func _carve_room_1_spawn(chunk: Chunk) -> void:
	_carve_rect(chunk, 60, 16, 68, 24)

# Hallway 1: 3 wide, connects Room 1 north to Room 2 (y=24 to y=36)
func _carve_hallway_1(chunk: Chunk) -> void:
	_carve_rect(chunk, 63, 24, 66, 36)

# Room 2: Item room (8×8, centered at x=64, y=36-44)
func _carve_room_2_item(chunk: Chunk) -> void:
	_carve_rect(chunk, 60, 36, 68, 44)

# Hallway 2: 3 wide, connects Room 2 north to Room 3 (y=44 to y=56)
func _carve_hallway_2(chunk: Chunk) -> void:
	_carve_rect(chunk, 63, 44, 66, 56)

# Room 3: Combat room (10×10, centered at x=64, y=56-66)
func _carve_room_3_combat(chunk: Chunk) -> void:
	_carve_rect(chunk, 59, 56, 69, 66)

# Exit hallway: 3 wide (y=66 to y=74)
func _carve_exit_hallway(chunk: Chunk) -> void:
	_carve_rect(chunk, 63, 66, 66, 74)

# Exit area: 6×6, centered at x=64, y=74-80
func _carve_exit_area(chunk: Chunk) -> void:
	_carve_rect(chunk, 61, 74, 67, 80)
	# Place exit stairs at center
	var exit_pos := Vector2i(64, 77)
	chunk.set_tile(exit_pos, EXIT_STAIRS)
	chunk.set_tile_at_layer(exit_pos, 1, CEILING)

# ============================================================================
# TUTORIAL CONTENT PLACEMENT
# ============================================================================

func _place_tutorial_content(chunk: Chunk) -> void:
	"""Place spraypaint, items, and entities in the tutorial layout"""
	var chunk_world := chunk.position * Chunk.SIZE  # (0,0) for tutorial

	# --- Spraypaint text ---
	# rotation_y=180 so text reads correctly when player walks forward (increasing Y)

	# Room 1: Welcome messages
	_add_spraypaint(chunk, Vector2i(64, 18), "welcome to kingston, ontario", Color(0.9, 0.9, 0.85), 180.0)
	_add_spraypaint(chunk, Vector2i(64, 20), "the beginning and end of all things", Color(0.9, 0.9, 0.85), 180.0)
	_add_spraypaint(chunk, Vector2i(64, 22), "MOVE FORWARD", Color(0.8, 0.2, 0.2), 180.0)

	# Room 2: Item pickup
	_add_spraypaint(chunk, Vector2i(64, 37), "EXAMINE IT", Color(0.8, 0.2, 0.2), 180.0)
	_add_spraypaint(chunk, Vector2i(64, 39), "PICK IT UP", Color(0.8, 0.2, 0.2), 180.0)

	# Room 3: Combat
	_add_spraypaint(chunk, Vector2i(64, 57), "ATTACKS ARE AUTOMATIC", Color(0.8, 0.2, 0.2), 180.0)
	_add_spraypaint(chunk, Vector2i(64, 59), "WAIT NEARBY OR WALK AROUND IT", Color(0.8, 0.2, 0.2), 180.0)

	# Exit area
	_add_spraypaint(chunk, Vector2i(64, 73), "PAUSE AND READ THE CONTROLS", Color(0.8, 0.2, 0.2), 180.0)
	_add_spraypaint(chunk, Vector2i(64, 75), "DESCEND", Color(0.8, 0.2, 0.2), 180.0)

	# --- Item in Room 2 (weighted rarity pick from tutorial items) ---
	var item_pos := Vector2i(64, 40)
	var tutorial_item := _pick_tutorial_item()
	if tutorial_item:
		var item_data := {
			"item_id": tutorial_item.item_id,
			"world_position": {"x": item_pos.x + chunk_world.x, "y": item_pos.y + chunk_world.y},
			"picked_up": false,
			"discovered": false,
			"spawn_turn": 0,
			"rarity": tutorial_item.rarity,
			"level": tutorial_item.level,
		}
		var subchunk := chunk.get_sub_chunk(Vector2i(item_pos.x / SubChunk.SIZE, item_pos.y / SubChunk.SIZE))
		if subchunk:
			subchunk.add_world_item(item_data)

	# --- Mannequin in Room 3 ---
	var mannequin_pos := Vector2i(64, 61) + chunk_world
	var mannequin := WorldEntity.new("tutorial_mannequin", mannequin_pos, 50.0, 0)
	mannequin.attack_damage = 0.0
	var mannequin_local := Vector2i(64, 61)
	var mannequin_sc := chunk.get_sub_chunk(Vector2i(mannequin_local.x / SubChunk.SIZE, mannequin_local.y / SubChunk.SIZE))
	if mannequin_sc:
		mannequin_sc.add_world_entity(mannequin)

	# --- Barrel fires (warmth and light in the frozen forest) ---
	var barrel_positions: Array[Vector2i] = [
		Vector2i(61, 17),  # Room 1: near spawn
		Vector2i(65, 30),  # Hallway 1: midpoint
		Vector2i(61, 42),  # Room 2: corner
		Vector2i(67, 58),  # Room 3: corner (opposite side from mannequin)
		Vector2i(63, 76),  # Exit area
	]
	for local_pos in barrel_positions:
		var world_pos: Vector2i = local_pos + chunk_world
		var fire := WorldEntity.new("barrel_fire", world_pos, 99999.0, 0)
		EntityRegistry.apply_defaults(fire)
		var sc := chunk.get_sub_chunk(Vector2i(local_pos.x / SubChunk.SIZE, local_pos.y / SubChunk.SIZE))
		if sc:
			sc.add_world_entity(fire)


func _pick_tutorial_item() -> Item:
	"""Pick one tutorial item using weighted rarity selection.

	Uses base spawn probabilities as weights (no corruption in tutorial).
	Meat (COMMON) ~67%, Vegetables (UNCOMMON) ~27%, Mustard (RARE) ~7%.
	"""
	var items: Array[Item] = [Meat.new(), Vegetables.new(), Mustard.new()]

	# Build weighted pool from base rarity probabilities
	var total_weight := 0.0
	var weights: Array[float] = []
	for item in items:
		var weight: float = ItemRarity.get_base_probability(item.rarity)
		weights.append(weight)
		total_weight += weight

	# Weighted random selection
	var roll := randf() * total_weight
	var cumulative := 0.0
	for i in range(items.size()):
		cumulative += weights[i]
		if roll <= cumulative:
			return items[i]

	return items[0]  # Fallback


func _add_spraypaint(chunk: Chunk, local_pos: Vector2i, text: String, color: Color = Color(0.9, 0.9, 0.85), rotation_y: float = 0.0) -> void:
	"""Add spraypaint text at a local chunk position"""
	var chunk_world := chunk.position * Chunk.SIZE
	var world_pos := local_pos + chunk_world
	var spray_data := {
		"text": text,
		"world_position": {"x": world_pos.x, "y": world_pos.y},
		"color": color,
		"font_size": 48,
		"surface": "floor",
		"rotation_y": rotation_y,
	}
	var sc := chunk.get_sub_chunk(Vector2i(local_pos.x / SubChunk.SIZE, local_pos.y / SubChunk.SIZE))
	if sc:
		sc.spraypaint_data.append(spray_data)
