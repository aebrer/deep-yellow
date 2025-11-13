extends Node
## EntityRegistry - Singleton for managing entity definitions
##
## This autoload handles:
## - Loading EntityInfo resources
## - Providing entity information with progressive revelation
## - Registry of all entities in the game
##
## Usage:
##   var info = EntityRegistry.get_info("skin_stealer", discovery_level, clearance)

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
	"""Load all EntityInfo resources from data directory"""
	# TODO: When entity data files are created, load them here
	# For now, create some placeholder test entities

	# Create test entity: Test Cube
	var test_cube = EntityInfo.new()
	test_cube.entity_id = "test_cube"
	var test_cube_names: Array[String] = [
		"████████",
		"???",
		"Unknown Object",
		"Test Cube"
	]
	test_cube.name_levels = test_cube_names
	var test_cube_descs: Array[String] = [
		"[DATA EXPUNGED]",
		"An object has been detected. Approach with caution.",
		"Object identified as a geometric structure. Purpose unknown. [REQUIRES CLEARANCE 2]",
		"Test entity for examination system. A simple cube placed for testing raycast detection and UI display."
	]
	test_cube.description_levels = test_cube_descs
	var test_cube_clearance: Array[int] = [0, 0, 1, 2]
	test_cube.clearance_required = test_cube_clearance
	var test_cube_classes: Array[String] = ["[REDACTED]", "Unknown", "Safe", "Safe"]
	test_cube.object_class_levels = test_cube_classes
	test_cube.threat_level = 0
	_entities["test_cube"] = test_cube

	# Create test entity: Yellow Wallpaper
	var wallpaper = EntityInfo.new()
	wallpaper.entity_id = "yellow_wallpaper"
	var wallpaper_names: Array[String] = [
		"Wall Surface",
		"Wallpaper",
		"Yellow Wallpaper",
		"Level 0 Wallpaper"
	]
	wallpaper.name_levels = wallpaper_names
	var wallpaper_descs: Array[String] = [
		"A surface of unknown composition.",
		"Standard wallpaper. Shows signs of age and moisture damage.",
		"Yellow wallpaper with geometric patterns. Typical of Level 0. Slight water staining visible.",
		"Level 0's signature yellow wallpaper with chevron patterns. Greyish-yellow color (#D4C5A0). Shows aging and water damage consistent with the Backrooms environment. No anomalous properties detected."
	]
	wallpaper.description_levels = wallpaper_descs
	var wallpaper_clearance: Array[int] = [0, 0, 0, 1]
	wallpaper.clearance_required = wallpaper_clearance
	var wallpaper_classes: Array[String] = ["N/A", "N/A", "N/A", "Safe"]
	wallpaper.object_class_levels = wallpaper_classes
	wallpaper.threat_level = 0
	_entities["yellow_wallpaper"] = wallpaper

	# Create Level 0: Wall (same as wallpaper since walls ARE wallpaper)
	var wall = EntityInfo.new()
	wall.entity_id = "level_0_wall"
	var wall_names: Array[String] = [
		"Wall Surface",
		"Wallpaper",
		"Yellow Wallpaper",
		"Level 0 Wall"
	]
	wall.name_levels = wall_names
	var wall_descs: Array[String] = [
		"A vertical surface.",
		"Standard wallpaper covering the wall. Shows signs of age and moisture damage.",
		"Yellow wallpaper with chevron patterns typical of Level 0. Water staining visible along edges.",
		"Level 0's signature yellow wallpaper. Greyish-yellow with chevron patterns (#D4C5A0). Shows aging, water damage, and peeling in corners. The wallpaper appears to stretch infinitely in all directions. No anomalous properties beyond the unsettling monotony."
	]
	wall.description_levels = wall_descs
	var wall_clearance: Array[int] = [0, 0, 0, 0]  # Environment tiles never require clearance
	wall.clearance_required = wall_clearance
	var wall_classes: Array[String] = ["N/A", "N/A", "Safe", "Safe"]
	wall.object_class_levels = wall_classes
	wall.threat_level = 0
	_entities["level_0_wall"] = wall

	# Create Level 0: Floor (brown carpet)
	var floor_tile = EntityInfo.new()
	floor_tile.entity_id = "level_0_floor"
	var floor_names: Array[String] = [
		"Floor",
		"Carpet",
		"Brown Carpet",
		"Level 0 Carpet"
	]
	floor_tile.name_levels = floor_names
	var floor_descs: Array[String] = [
		"A horizontal surface.",
		"Worn carpet. Damp in places. The pattern is difficult to discern.",
		"Brown carpet with geometric patterns. Moist texture. Shows heavy wear patterns from countless footsteps.",
		"Level 0's brown carpet (approx. #8B6F4F). Loop pile construction, heavily worn. Perpetually damp, possibly from moisture in the air. Shows darkened traffic patterns. Slight chemical smell - likely mold or mildew. The dampness makes the carpet squelch slightly underfoot."
	]
	floor_tile.description_levels = floor_descs
	var floor_clearance: Array[int] = [0, 0, 0, 0]  # Environment tiles never require clearance
	floor_tile.clearance_required = floor_clearance
	var floor_classes: Array[String] = ["N/A", "N/A", "Safe", "Safe"]
	floor_tile.object_class_levels = floor_classes
	floor_tile.threat_level = 0
	_entities["level_0_floor"] = floor_tile

	# Create Level 0: Ceiling (acoustic tiles)
	var ceiling = EntityInfo.new()
	ceiling.entity_id = "level_0_ceiling"
	var ceiling_names: Array[String] = [
		"Ceiling",
		"Ceiling Tiles",
		"Acoustic Ceiling",
		"Level 0 Ceiling"
	]
	ceiling.name_levels = ceiling_names
	var ceiling_descs: Array[String] = [
		"An overhead surface.",
		"Suspended ceiling with acoustic tiles. Some tiles appear stained or discolored.",
		"Off-white acoustic ceiling tiles with perforation pattern. Water stains visible. Fluorescent light panels intermittently placed.",
		"Level 0's suspended acoustic ceiling. Off-white to beige tiles (#D8D0C0) with small perforations for sound dampening. Shows yellowing from age and water damage. Grid system visible between tiles. Fluorescent light panels provide inconsistent lighting - some flicker, others are dark. The ceiling height is approximately 8-9 feet, creating a claustrophobic office-like atmosphere."
	]
	ceiling.description_levels = ceiling_descs
	var ceiling_clearance: Array[int] = [0, 0, 0, 0]  # Environment tiles never require clearance
	ceiling.clearance_required = ceiling_clearance
	var ceiling_classes: Array[String] = ["N/A", "N/A", "Safe", "Safe"]
	ceiling.object_class_levels = ceiling_classes
	ceiling.threat_level = 0
	_entities["level_0_ceiling"] = ceiling

	Log.system("Loaded %d entities (including grid tiles)" % _entities.size())

# ============================================================================
# PUBLIC API
# ============================================================================

func get_info(entity_id: String, discovery_level: int, clearance: int) -> Dictionary:
	"""Get entity information with progressive revelation"""
	if not _entities.has(entity_id):
		push_warning("[EntityRegistry] Entity not found: %s" % entity_id)
		return _get_unknown_entity_info()

	var entity: EntityInfo = _entities[entity_id]
	return entity.get_info(discovery_level, clearance)

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
