extends LevelConfig
class_name Level1Config
## Level 1: The Poolrooms — first playable framework pass.

func _init() -> void:
	# ========================================================================
	# METADATA
	# ========================================================================
	level_id = 1
	display_name = "level 1 - the poolrooms"
	description = """endless tiled basins and corridors filled with still chlorinated water.

white ceramic walls reflect cold blue-green light. shallow pools hide sudden
black drops, and every footstep echoes too long.

survival difficulty: moderate
navigation difficulty: moderate
entity density: low but rising"""

	difficulty = 2
	required_clearance = 0

	# ========================================================================
	# VISUAL ASSETS
	# ========================================================================
	mesh_library_path = "res://assets/level_01_mesh_library.tres"

	tile_mapping = {
		0: 0,   # FLOOR → White tile walkway
		1: 1,   # WALL → White ceramic wall
		2: 2,   # CEILING → Damp white ceiling
		3: 0,   # EXIT_STAIRS → Floor (entity renders marker)
		15: 3,  # FLOOR_SHALLOW_WATER → Walkable shallow water
		26: 4,  # DEEP_WATER → Blocked deep water surface
		30: 2,  # CEILING_STAIN → Ceiling fallback for now
		31: 2,  # CEILING_HOLE → Ceiling fallback for now
	}

	ambient_light_color = Color(0.45, 0.85, 0.95, 1.0)
	ambient_light_intensity = 0.045
	fog_color = Color(0.22, 0.55, 0.62, 1.0)
	fog_start = 10.0
	fog_end = 28.0
	background_color = Color(0.03, 0.10, 0.12, 1.0)
	directional_light_color = Color(0.65, 0.95, 1.0, 1.0)
	directional_light_energy = 0.0
	directional_light_rotation = Vector3(-90, 0, 0)

	# ========================================================================
	# GENERATION PARAMETERS
	# ========================================================================
	grid_size = Vector2i(128, 128)
	room_density = 0.35
	min_room_size = Vector2i(8, 8)
	max_room_size = Vector2i(28, 28)
	corridor_width = 3
	wall_probability = 0.45
	use_chunk_system = false

	# ========================================================================
	# ENTITY SPAWNING
	# ========================================================================
	min_entity_distance = 18
	spawn_interval = 40
	escalation_rate = 0.08
	entity_spawn_table = [
		{
			"entity_type": "sodden",
			"weight": 6.0,
			"base_hp": 180.0,
			"hp_scale": 0.08,
			"base_damage": 3.0,
			"damage_scale": 0.04,
			"threat_level": 2,
			"corruption_threshold": 0.0,
		},
		{
			"entity_type": "drowner",
			"weight": 2.5,
			"base_hp": 120.0,
			"hp_scale": 0.12,
			"base_damage": 4.0,
			"damage_scale": 0.06,
			"threat_level": 3,
			"corruption_threshold": 0.05,
		},
		{
			"entity_type": "ambassador",
			"weight": 0.25,
			"base_hp": 80.0,
			"hp_scale": 0.0,
			"base_damage": 0.0,
			"damage_scale": 0.0,
			"threat_level": 0,
			"corruption_threshold": 0.0,
			"hostile": false,
			"blocks_movement": false,
		},
	]

	# ========================================================================
	# ENVIRONMENTAL HAZARDS
	# ========================================================================
	base_temperature = 18.0
	liquid_types = ["chlorinated_water"]
	corruption_rate = 0.008
	light_level = 0.45
	noise_echo = 1.4

	# ========================================================================
	# ITEM SPAWNING
	# ========================================================================
	item_density = 0.06
	add_permitted_item(AlmondWater.new())
	add_permitted_item(BaseballBat.new())
	add_permitted_item(BrassKnuckles.new())
	add_permitted_item(TrailMix.new())
	add_permitted_item(WheatieOs.new())
	add_permitted_item(Binoculars.new())
	add_permitted_item(DrinkingBird.new())
	add_permitted_item(LuckyRabbitsFoot.new())

	# ========================================================================
	# EXIT CONFIGURATION
	# ========================================================================
	exit_spawn_chance = 0.0  # Explicit generator-placed stairs only
	exit_destinations = [0]  # Implemented Poolrooms return route
	min_exit_distance = 0

	# ========================================================================
	# GAMEPLAY MODIFIERS
	# ========================================================================
	time_scale = 1.0
	sanity_drain_rate = 0.08
	visibility_range = 16
	enable_ceiling_vignette = true
	vignette_inner_radius = 0.25
	vignette_outer_radius = 0.85
	sprite_brightness = 1.8

func on_enter() -> void:
	super.on_enter()
	Log.player("the air turns wet and cold. tile echoes under your feet.")

func on_exit() -> void:
	super.on_exit()
	Log.player("you climb out of the poolrooms...")
