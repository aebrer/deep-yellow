extends LevelConfig
class_name LevelNeg1Config
## Level -1: "Kingston, Ontario" - Tutorial level
##
## A snowy dark forest clearing. Hand-crafted rooms teach core mechanics:
## movement, item pickup, and combat. No random generation.

func _init() -> void:
	# ========================================================================
	# METADATA
	# ========================================================================
	level_id = -1
	display_name = "level -1 - kingston, ontario"
	description = """a clearing in a dark forest. snow falls silently.

this place feels familiar, like a memory you can't quite place.
wooden mannequins stand motionless among the trees.

survival difficulty: none
navigation difficulty: none
entity density: none (hand-placed)"""

	difficulty = 0
	required_clearance = 0

	# ========================================================================
	# VISUAL ASSETS
	# ========================================================================
	mesh_library_path = "res://assets/level_neg1_mesh_library.tres"

	# Only 3 items in MeshLibrary — no variants for tutorial
	tile_mapping = {
		0: 0,   # FLOOR → Floor (snowy dirt)
		1: 1,   # WALL → Wall (dark pine forest)
		2: 2,   # CEILING → Ceiling (dark overcast sky)
		3: 0,   # EXIT_STAIRS → Floor (renders as floor)
	}

	# Cool blue-white winter night atmosphere
	# Ambient must be high enough to illuminate wall sides (vertical faces)
	ambient_light_color = Color(0.6, 0.65, 0.8, 1.0)
	ambient_light_intensity = 0.6

	# Gray fog — dark forest
	fog_color = Color(0.15, 0.15, 0.2, 1.0)
	fog_start = 12.0
	fog_end = 30.0

	# ========================================================================
	# ENVIRONMENT & LIGHTING
	# ========================================================================
	# Dark void beyond geometry
	background_color = Color(0.05, 0.05, 0.08, 1.0)

	# Moonlight — cold blue tint, angled to hit wall sides
	directional_light_color = Color(0.7, 0.75, 0.9, 1.0)
	directional_light_energy = 0.7
	directional_light_rotation = Vector3(-45, 30, 0)

	# ========================================================================
	# GENERATION PARAMETERS
	# ========================================================================
	grid_size = Vector2i(128, 128)
	# These are ignored — level -1 uses a hand-crafted generator
	room_density = 0.0
	wall_probability = 1.0
	use_chunk_system = false

	# ========================================================================
	# ENTITY SPAWNING
	# ========================================================================
	# No random spawning — entities placed manually by generator
	entity_spawn_table = []
	min_entity_distance = 100
	spawn_interval = 100
	escalation_rate = 0.0

	# ========================================================================
	# ENVIRONMENTAL HAZARDS
	# ========================================================================
	base_temperature = -5.0  # Below freezing
	liquid_types = []
	corruption_rate = 0.0  # No corruption in tutorial
	light_level = 0.3  # Dark forest
	noise_echo = 0.5  # Snow dampens sound

	# ========================================================================
	# ITEM SPAWNING
	# ========================================================================
	item_density = 0.0  # No random items — placed manually
	add_permitted_item(Meat.new())
	add_permitted_item(Vegetables.new())
	add_permitted_item(Mustard.new())

	# ========================================================================
	# EXIT CONFIGURATION
	# ========================================================================
	exit_spawn_chance = 0.0  # No random exits — placed manually
	exit_destinations = [0]  # Tutorial exits to Level 0
	min_exit_distance = 0

	# ========================================================================
	# AUDIO
	# ========================================================================
	ambient_volume = 0.3
	music_volume = 0.0

	# ========================================================================
	# GAMEPLAY MODIFIERS
	# ========================================================================
	time_scale = 1.0
	sanity_drain_rate = 0.0  # No sanity drain in tutorial
	visibility_range = 20

	enable_ceiling_vignette = true
	vignette_inner_radius = 0.2
	vignette_outer_radius = 0.8

	# Snowfall effect
	enable_snowfall = true

	# Fixed spawn at back wall of Room 1, facing forward (toward hallway)
	player_spawn_position = Vector2i(64, 17)
	player_spawn_camera_yaw = 180.0  # Face toward increasing Y (forward into hallway)

# ========================================================================
# LIFECYCLE HOOKS
# ========================================================================

func on_load() -> void:
	super.on_load()
	_show_welcome_messages.call_deferred()

func _show_welcome_messages() -> void:
	Log.player("you wake up in a clearing. snow falls silently around you.")
	Log.player("the dark outlines of pine trees surround you on all sides.")

func on_enter() -> void:
	super.on_enter()

func on_exit() -> void:
	super.on_exit()
	Log.player("you descend into the backrooms...")
