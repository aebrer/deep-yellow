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
	Log.system("EntityRegistry initialized with %d entities" % _entities.size())

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

	Log.system("Loaded %d entities (including grid tiles)" % _entities.size())

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
	Log.system("Registered entity: %s" % entity.entity_id)

func _get_unknown_entity_info() -> Dictionary:
	"""Fallback info for unregistered entities"""
	return {
		"name": "Unknown",
		"description": "[ENTITY NOT REGISTERED IN DATABASE]",
		"object_class": "Unknown",
		"threat_level": 0
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
