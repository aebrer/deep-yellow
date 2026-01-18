extends Node
## EntityRegistry - Singleton for managing entity definitions
##
## This autoload handles:
## - Loading EntityInfo resources
## - Providing entity information with progressive revelation
## - Registry of all entities in the game
##
## Usage:
##   var info = EntityRegistry.get_info("skin_stealer", clearance)

# ============================================================================
# ENTITY REGISTRY
# ============================================================================

## Registry of all entity definitions: {entity_id: EntityInfo}
var _entities: Dictionary = {}

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	_load_entities()

func _load_entities() -> void:
	"""Load all EntityInfo resources"""
	# Generic placeholder for unregistered entities
	var unknown = EntityInfo.new()
	unknown.entity_id = "unknown_entity"
	unknown.entity_name = "Unknown Entity"
	unknown.visual_description = "Movement detected. Origin unknown."
	unknown.clearance_info[0] = ""  # No additional info at clearance 0
	unknown.clearance_info[1] = "Entity classification pending. Exhibits anomalous properties."
	unknown.clearance_info[2] = "Placeholder entity for examination system testing."
	unknown.object_class = "Unclassified"
	unknown.threat_level = 1
	_entities["unknown_entity"] = unknown

	# Create Level 0: Wall (yellow wallpaper)
	var wall = EntityInfo.new()
	wall.entity_id = "level_0_wall"
	wall.entity_name = "Yellow Wallpaper"
	wall.visual_description = "A vertical surface covered in greyish-yellow wallpaper with chevron patterns. Shows signs of age with water staining visible along edges and peeling in corners."
	wall.clearance_info[0] = ""  # No additional info at clearance 0
	wall.clearance_info[1] = "Standard office wallpaper typical of Level 0. Color approximately #D4C5A0."
	wall.clearance_info[2] = "The wallpaper appears to stretch infinitely in all directions, creating an unsettling monotony. No anomalous properties detected beyond the psychological effect of endless repetition."
	wall.object_class = "Safe"
	wall.threat_level = 0
	_entities["level_0_wall"] = wall

	# Create Level 0: Floor (brown carpet)
	var floor_tile = EntityInfo.new()
	floor_tile.entity_id = "level_0_floor"
	floor_tile.entity_name = "Brown Carpet"
	floor_tile.visual_description = "A horizontal surface covered in worn brown carpet with geometric patterns. Damp in places. Shows heavy wear patterns from countless footsteps."
	floor_tile.clearance_info[0] = ""  # No additional info at clearance 0
	floor_tile.clearance_info[1] = "Loop pile construction, heavily worn. Color approximately #8B6F4F. The pattern is difficult to discern due to age and traffic."
	floor_tile.clearance_info[2] = "Perpetually damp, possibly from moisture in the air. Shows darkened traffic patterns suggesting high foot traffic. Slight chemical smell detected - likely mold or mildew growth. The dampness makes the carpet squelch slightly underfoot."
	floor_tile.object_class = "Safe"
	floor_tile.threat_level = 0
	_entities["level_0_floor"] = floor_tile

	# Create Level 0: Ceiling (acoustic tiles)
	var ceiling = EntityInfo.new()
	ceiling.entity_id = "level_0_ceiling"
	ceiling.entity_name = "Acoustic Ceiling"
	ceiling.visual_description = "An overhead suspended ceiling with off-white acoustic tiles featuring a perforation pattern. Some tiles appear stained or discolored. Fluorescent light panels are intermittently placed."
	ceiling.clearance_info[0] = ""  # No additional info at clearance 0
	ceiling.clearance_info[1] = "Off-white to beige tiles (color approximately #D8D0C0) with small perforations for sound dampening. Grid system visible between tiles. Shows yellowing from age and water damage."
	ceiling.clearance_info[2] = "Fluorescent light panels provide inconsistent lighting - some flicker, others are completely dark. The ceiling height is approximately 8-9 feet, creating a claustrophobic office-like atmosphere typical of commercial spaces from the 1980s-1990s."
	ceiling.object_class = "Safe"
	ceiling.threat_level = 0
	_entities["level_0_ceiling"] = ceiling

	# Bacteria Spawn (Level 0 basic enemy)
	# threat_level 1 matches level_00_config.gd entity_spawn_table
	var bacteria_spawn = EntityInfo.new()
	bacteria_spawn.entity_id = "bacteria_spawn"
	bacteria_spawn.entity_name = "Bacteria Spawn"
	bacteria_spawn.visual_description = "A translucent green mass roughly the size of a basketball. Pseudopods extend and retract as it creeps across the damp carpet."
	bacteria_spawn.clearance_info[0] = ""  # No additional info at clearance 0
	bacteria_spawn.clearance_info[1] = "Swarms toward detected movement. Can sense disturbances from considerable distance."
	bacteria_spawn.clearance_info[2] = "Melee attacker. Weak individually but dangerous in groups. Often spawned by larger organisms."
	bacteria_spawn.clearance_info[3] = "--- FIELD DATA ---\nDamage: 1 HP per attack\nSpeed: 1 move per turn\nSense range: 80 tiles"
	bacteria_spawn.object_class = "Euclid"
	bacteria_spawn.threat_level = 1  # White (weakest) - common early, rarer later
	_entities["bacteria_spawn"] = bacteria_spawn

	# Bacteria Motherload (Level 0 dangerous enemy)
	# threat_level 3 matches level_00_config.gd entity_spawn_table
	var bacteria_motherload = EntityInfo.new()
	bacteria_motherload.entity_id = "bacteria_motherload"
	bacteria_motherload.entity_name = "Bacteria Motherload"
	bacteria_motherload.visual_description = "A massive greenish-black organism. Internal bioluminescent glow pulses rhythmically. Much larger than its spawn."
	bacteria_motherload.clearance_info[0] = ""  # No additional info at clearance 0
	bacteria_motherload.clearance_info[1] = "Moves faster when it senses prey. Highly aggressive."
	bacteria_motherload.clearance_info[2] = "Periodically spawns Bacteria Spawn from its mass. The glow intensifies before spawning."
	bacteria_motherload.clearance_info[3] = "--- FIELD DATA ---\nDamage: 4 HP per attack\nSpeed: 2 moves per turn (when aware)\nSpawn cooldown: 10 turns\nSense range: 32 tiles"
	bacteria_motherload.object_class = "Keter"
	bacteria_motherload.threat_level = 3  # Dangerous (Yellow) - rare early, common later
	_entities["bacteria_motherload"] = bacteria_motherload

	# Smiler (Level 0 psychological horror enemy)
	# threat_level 2 (Epsilon) but contributes EXTRA sanity damage
	var smiler = EntityInfo.new()
	smiler.entity_id = "smiler"
	smiler.entity_name = "Smiler"
	smiler.visual_description = "Two glowing eyes and a wide, toothy grin float in the darkness. The smile never wavers. It watches."
	smiler.clearance_info[0] = ""  # No additional info at clearance 0
	smiler.clearance_info[1] = "Appears in darker areas. Does not attack directly but its presence erodes sanity rapidly."
	smiler.clearance_info[2] = "VULNERABLE TO SOUND. Loud noises cause it to disperse instantly. The Whistle is particularly effective."
	smiler.clearance_info[3] = "Maintains distance from prey. Teleports short distances every few turns. Looking directly at it accelerates sanity loss."
	smiler.clearance_info[4] = "--- FIELD DATA ---\nDamage: None (psychological only)\nSpeed: 5 tiles every 4th turn\nWeakness: Sound-based attacks (instant kill)\nSense range: 20 tiles\nPreferred distance: ~5 tiles"
	smiler.object_class = "Euclid"
	smiler.threat_level = 2  # Epsilon (moderate) - but extra sanity contribution
	_entities["smiler"] = smiler

	# Bacteria Spreader (Level 0 support enemy)
	# threat_level 2 (Epsilon) matches level_00_config.gd entity_spawn_table
	var bacteria_spreader = EntityInfo.new()
	bacteria_spreader.entity_id = "bacteria_spreader"
	bacteria_spreader.entity_name = "Bacteria Spreader"
	bacteria_spreader.visual_description = "A dark green bulbous mass with tendrils extending outward. A cloud of golden-green spores drifts lazily around it, occasionally settling on nearby surfaces."
	bacteria_spreader.clearance_info[0] = ""  # No additional info at clearance 0
	bacteria_spreader.clearance_info[1] = "The spore cloud appears to have a restorative effect on nearby bacterial organisms."
	bacteria_spreader.clearance_info[2] = "SUPPORT ENTITY. Heals nearby bacteria each turn. Eliminating spreaders should be a priority to prevent swarm regeneration."
	bacteria_spreader.clearance_info[3] = "Attacks in a burst pattern, damaging anything within close proximity. The healing aura scales with the entity's overall power."
	bacteria_spreader.clearance_info[4] = "--- FIELD DATA ---\nDamage: 3 HP (AOE burst)\nSpeed: 1 move per turn\nHealing: [DAMAGE]% max HP to nearby bacteria (scales with corruption)\nHeal range: 3 tiles\nSense range: 40 tiles"
	bacteria_spreader.object_class = "Euclid"
	bacteria_spreader.threat_level = 2  # Epsilon (moderate) - support role
	_entities["bacteria_spreader"] = bacteria_spreader

	# Debug Enemy (testing entity)
	var debug_enemy = EntityInfo.new()
	debug_enemy.entity_id = "debug_enemy"
	debug_enemy.entity_name = "Debug Enemy"
	debug_enemy.visual_description = "A magenta cube floating at eye level. It doesn't move or react to your presence. Seems to exist purely for testing purposes."
	debug_enemy.clearance_info[0] = ""  # No additional info at clearance 0
	debug_enemy.clearance_info[1] = "Designation: TEST_ENTITY_001. Created for combat system validation."
	debug_enemy.clearance_info[2] = "HP: 1100 (extremely high for testing). Does not attack. Does not move. Classification: Punching Bag."
	debug_enemy.clearance_info[3] = "Entity spawns once per chunk. Position determined by walkable tile search from chunk center."
	debug_enemy.clearance_info[4] = "--- SYSTEM DATA ---\nclass_name: DebugEnemy\nstats.body = 100\nstats.bonus_hp = 1000.0\nprocess_turn(): pass  # Does nothing"
	debug_enemy.object_class = "Debug"
	debug_enemy.threat_level = 0
	_entities["debug_enemy"] = debug_enemy


# ============================================================================
# PUBLIC API
# ============================================================================

func get_info(entity_id: String, clearance: int) -> Dictionary:
	"""Get entity information with progressive revelation based on clearance"""
	if not _entities.has(entity_id):
		push_warning("[EntityRegistry] Entity not found: %s" % entity_id)
		return _get_unknown_entity_info()

	var entity: EntityInfo = _entities[entity_id]
	return entity.get_info(clearance)

func has_entity(entity_id: String) -> bool:
	"""Check if entity is registered"""
	return _entities.has(entity_id)

func get_all_entity_ids() -> Array[String]:
	"""Get list of all registered entity IDs"""
	var ids: Array[String] = []
	for id in _entities.keys():
		ids.append(id)
	return ids

func register_entity(entity: EntityInfo) -> void:
	"""Register a new entity (for runtime additions)"""
	if entity.entity_id.is_empty():
		push_error("[EntityRegistry] Cannot register entity with empty ID")
		return

	_entities[entity.entity_id] = entity

func _get_unknown_entity_info() -> Dictionary:
	"""Fallback info for unregistered entities"""
	return {
		"name": "Unknown",
		"description": "[ENTITY NOT REGISTERED IN DATABASE]",
		"object_class": "Unknown",
		"threat_level": 0,
		"threat_level_name": EntityInfo.threat_level_to_name(0)
	}

# ============================================================================
# DEBUG / DEVELOPMENT
# ============================================================================

func print_registry() -> void:
	"""Print all registered entities to console"""
	print("\n=== EntityRegistry ===")
	print("Total entities: %d" % _entities.size())
	for entity_id in _entities.keys():
		print("  - %s" % entity_id)
	print("======================\n")
