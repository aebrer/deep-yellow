extends LevelConfig
class_name Level0Config
## Level 0: "The Lobby" - Classic yellow office maze
##
## The quintessential Backrooms experience. Endless yellow-wallpapered rooms,
## buzzing fluorescent lights, damp carpet. Low danger, high disorientation.
## Perfect for learning game mechanics and soaking in liminal dread.

func _init() -> void:
	# ========================================================================
	# METADATA
	# ========================================================================
	level_id = 0
	display_name = "level 0 - the lobby"
	description = """the first and most iconic level.

an endless maze of yellow-wallpapered office rooms lit by flickering
fluorescent lights. the air smells of mold and damp carpet. the constant
buzzing hum fills your ears.

entities are rare here, but the labyrinth itself is the true threat -
many wanderers have starved to death trying to find an exit.

survival difficulty: low
navigation difficulty: extreme
entity density: very low"""

	difficulty = 1
	required_clearance = 0

	# ========================================================================
	# VISUAL ASSETS
	# ========================================================================
	# Level 0 specific mesh library (yellow wallpaper, brown carpet, grey ceiling)
	mesh_library_path = "res://assets/level_00_mesh_library.tres"

	# Tile type → MeshLibrary item ID mapping
	# SubChunk.TileType values → MeshLibrary item indices
	tile_mapping = {
		0: 0,   # FLOOR → Floor
		1: 1,   # WALL → Wall
		2: 2,   # CEILING → Ceiling
		3: 0,   # EXIT_STAIRS → Floor (renders as floor)
		10: 3,  # FLOOR_PUDDLE → FloorPuddle
		11: 4,  # FLOOR_CARDBOARD → FloorCardboard
		20: 5,  # WALL_CRACKED → WallCracked
		21: 6,  # WALL_HOLE → WallHole
		22: 7,  # WALL_MOULDY → WallMouldy
		30: 8,  # CEILING_STAIN → CeilingStain
		31: 9,  # CEILING_HOLE → CeilingHole
	}

	# Yellow office aesthetic
	ambient_light_color = Color(1.0, 0.95, 0.7, 1.0)  # Warm yellow
	ambient_light_intensity = 0.5

	# Yellowish fog for distance culling
	fog_color = Color(0.8, 0.75, 0.5, 1.0)
	fog_start = 15.0
	fog_end = 35.0

	# ========================================================================
	# ENVIRONMENT & LIGHTING - The "Backrooms Level 0" aesthetic
	# ========================================================================
	# Indoor ceiling background (no outdoor sky - this is an endless building)
	# When player zooms out in tactical cam, they see this color at the horizon.
	# Greyish-beige represents stained office ceiling tiles stretching to infinity.
	background_color = Color(0.82, 0.8, 0.75, 1.0)

	# Overhead fluorescent lighting - The iconic buzzing lights of Level 0
	# Slight blue tint gives that harsh, artificial fluorescent office feel
	# Bright energy (0.9) ensures good visibility while maintaining atmosphere
	# Rotation (-90, 0, 0) = straight down from above, like ceiling-mounted fluorescent panels
	# This creates even illumination on all walls without harsh shadows
	directional_light_color = Color(0.95, 0.97, 1.0, 1.0)
	directional_light_energy = 0.9
	directional_light_rotation = Vector3(-90, 0, 0)

	# ========================================================================
	# GENERATION PARAMETERS
	# ========================================================================
	grid_size = Vector2i(128, 128)
	room_density = 0.7  # Mostly rooms, some corridors
	min_room_size = Vector2i(4, 4)
	max_room_size = Vector2i(12, 12)
	corridor_width = 2
	wall_probability = 0.6  # Medium maze density

	# No chunk system for Level 0 (simple uniform generation)
	use_chunk_system = false

	# ========================================================================
	# ENTITY SPAWNING
	# ========================================================================
	# Entity count is per-chunk (see ChunkManager.BASE_ENTITIES_PER_CHUNK)
	# Isolation is the horror - low density, slow escalation
	min_entity_distance = 30
	spawn_interval = 50  # Very slow spawning
	escalation_rate = 0.05  # Minimal escalation

	# Entity spawn table - uses entity_type strings (WorldEntity pattern)
	# weight: spawn probability (higher = more common)
	# base_hp: HP at 0 corruption
	# hp_scale: HP multiplier per 0.05 corruption (e.g., 0.1 = +10% HP per 0.05 corruption)
	# base_damage: damage dealt per attack at 0 corruption
	# damage_scale: damage multiplier per 0.05 corruption (e.g., 0.05 = +5% damage per 0.05 corruption)
	# threat_level: entity difficulty tier (1=weak, 2=moderate, 3=dangerous, 4=elite, 5=boss)
	#   Higher threat entities become MORE common as corruption rises
	#   Lower threat entities become LESS common as corruption rises
	# corruption_threshold: minimum corruption to spawn (0.0 = always)
	#
	# SCALING FORMULA (per 0.05 corruption):
	#   final_hp = base_hp * (1 + (corruption / 0.05) * hp_scale)
	#   final_damage = base_damage * (1 + (corruption / 0.05) * damage_scale)
	# Example at corruption 0.25 (5 steps of 0.05):
	#   bacteria_spawn: HP = 100 * (1 + 5 * 0.1) = 150 HP, Damage = 3 * (1 + 5 * 0.05) = 3.75
	entity_spawn_table = [
		{
			"entity_type": "bacteria_spawn",
			"weight": 10.0,
			"base_hp": 100.0,
			"hp_scale": 0.1,  # +10% HP per 0.05 corruption
			"base_damage": 3.0,
			"damage_scale": 0.05,  # +5% damage per 0.05 corruption
			"threat_level": 1,  # Weak - common early, less common later
			"corruption_threshold": 0.0,
		},
		{
			"entity_type": "bacteria_motherload",
			"weight": 0.5,  # Rare but possible from the start
			"base_hp": 1000.0,
			"hp_scale": 0.15,  # +15% HP per 0.05 corruption
			"base_damage": 10.0,
			"damage_scale": 0.1,  # +10% damage per 0.05 corruption
			"threat_level": 3,  # Dangerous - rare early, more common later
			"corruption_threshold": 0.0,  # Can spawn at any corruption
		},
		{
			"entity_type": "smiler",
			"weight": 1.0,  # Uncommon - psychological horror
			"base_hp": 1.0,  # Dies instantly to sound, HP doesn't matter
			"hp_scale": 0.0,  # No HP scaling (sound = instant kill)
			"base_damage": 0.0,  # No direct damage (sanity drain only)
			"damage_scale": 0.0,  # No damage scaling
			"threat_level": 2,  # Epsilon - moderate threat (but extra sanity drain)
			"corruption_threshold": 0.0,  # Can spawn at any corruption
		},
		{
			"entity_type": "bacteria_spreader",
			"weight": 2.0,  # Uncommon support enemy
			"base_hp": 200.0,  # Support role, less tanky than before
			"hp_scale": 0.1,  # +10% HP per 0.05 corruption
			"base_damage": 3.0,  # AOE attack damage
			"damage_scale": 0.05,  # +5% damage per 0.05 corruption (also scales healing!)
			"threat_level": 2,  # Epsilon - moderate threat
			"corruption_threshold": 0.0,  # Can spawn at any corruption
		},
	]

	# ========================================================================
	# ENVIRONMENTAL HAZARDS
	# ========================================================================
	base_temperature = 22.0  # Uncomfortably warm
	liquid_types = []  # No liquids in Level 0
	corruption_rate = 0.005  # Very slow reality degradation
	light_level = 0.8  # Well-lit but flickering
	noise_echo = 1.2  # Sound travels far in empty rooms

	# ========================================================================
	# ITEM SPAWNING
	# ========================================================================
	item_density = 0.05  # Sparse items

	# Permitted items for Level 0 (rarity-based spawning)
	add_permitted_item(DebugItem.new())  # UNCOMMON rarity (2% spawn chance)
	add_permitted_item(BrassKnuckles.new())  # COMMON rarity
	add_permitted_item(BaseballBat.new())  # COMMON rarity
	add_permitted_item(WheatieOs.new())  # COMMON rarity
	add_permitted_item(TrailMix.new())  # RARE rarity
	add_permitted_item(Binoculars.new())  # UNCOMMON rarity
	add_permitted_item(CoachsWhistle.new())  # UNCOMMON rarity
	add_permitted_item(LuckyRabbitsFoot.new())  # UNCOMMON rarity
	add_permitted_item(RomanCoin.new())  # COMMON rarity
	add_permitted_item(AntigonousNotebook.new())  # LEGENDARY rarity
	add_permitted_item(SirensCords.new())  # EPIC rarity
	add_permitted_item(Shovel.new())  # UNCOMMON rarity
	add_permitted_item(DrinkingBird.new())  # COMMON rarity
	add_permitted_item(AlmondWater.new())  # RARE rarity

	# ========================================================================
	# EXIT CONFIGURATION
	# ========================================================================
	exit_spawn_chance = 0.03  # Rare exits (hard to escape)
	exit_destinations = []  # TODO: Add Level 1, 2 when implemented
	min_exit_distance = 60  # Must explore significantly to find exit

	# ========================================================================
	# AUDIO
	# ========================================================================
	# Future: fluorescent hum ambient sound
	# ambient_sound = load("res://assets/audio/ambient/fluorescent_hum.ogg")
	ambient_volume = 0.4

	# No music - only the hum
	music_volume = 0.0

	# ========================================================================
	# GAMEPLAY MODIFIERS
	# ========================================================================
	time_scale = 1.0  # Normal speed
	sanity_drain_rate = 0.05  # Slow sanity drain (isolation horror)
	visibility_range = 20  # Good visibility

	# Ceiling vignette enabled for top-down view
	enable_ceiling_vignette = true
	vignette_inner_radius = 0.2
	vignette_outer_radius = 0.8

# ========================================================================
# LIFECYCLE HOOKS
# ========================================================================

func on_load() -> void:
	super.on_load()

func on_enter() -> void:
	super.on_enter()
	# Defer welcome messages so they appear after UI log panel is ready
	_show_welcome_messages.call_deferred()

func _show_welcome_messages() -> void:
	Log.player("welcome to the backrooms. you are in the lobby.")
	Log.player("the fluorescent lights buzz overhead. the air smells of mold.")

func on_exit() -> void:
	super.on_exit()
	Log.player("you noclip out of level 0...")
