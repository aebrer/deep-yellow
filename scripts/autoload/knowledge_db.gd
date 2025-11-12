extends Node
## KnowledgeDB - Singleton for tracking player knowledge and discoveries
##
## This autoload handles:
## - Discovery level tracking for entities (0-3 scale)
## - Clearance level tracking (0-5 scale)
## - Researcher classification (total research score)
## - Entity information retrieval with progressive revelation
##
## Usage:
##   KnowledgeDB.examine_entity("skin_stealer")
##   var info = KnowledgeDB.get_entity_info("skin_stealer")

# ============================================================================
# PLAYER KNOWLEDGE STATE
# ============================================================================

## Entity discovery levels: {entity_id: discovery_level}
## Discovery 0 = Unknown (never seen)
## Discovery 1 = Detected (first examination)
## Discovery 2 = Identified (multiple examinations or combat)
## Discovery 3 = Fully Known (complete understanding)
var discovered_entities: Dictionary = {}

## Player clearance level (0-5)
## 0 = No clearance
## 1-4 = Progressive access
## 5 = Maximum clearance (Omega)
var clearance_level: int = 0

## Total research score (meta-progression tracking)
## Increases with each discovery, examination, and objective completion
var researcher_classification: int = 0

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	Log.system("KnowledgeDB initialized - Clearance: %d" % clearance_level)

# ============================================================================
# EXAMINATION API
# ============================================================================

func examine_entity(entity_id: String) -> void:
	"""Called when player examines an entity - increases discovery level"""
	if entity_id.is_empty():
		push_warning("[KnowledgeDB] Cannot examine entity with empty ID")
		return

	var current_level = discovered_entities.get(entity_id, 0)

	# Max discovery level is 3
	if current_level < 3:
		discovered_entities[entity_id] = current_level + 1
		researcher_classification += 1
		Log.system("Entity examined: %s (discovery level: %d -> %d)" % [
			entity_id,
			current_level,
			current_level + 1
		])
	else:
		Log.trace(Log.Category.SYSTEM, "Entity already fully known: %s (level 3)" % entity_id)

func get_discovery_level(entity_id: String) -> int:
	"""Get current discovery level for entity (0-3)"""
	return discovered_entities.get(entity_id, 0)

func get_entity_info(entity_id: String) -> Dictionary:
	"""Get display information for entity based on discovery and clearance"""
	var discovery = get_discovery_level(entity_id)

	# Query EntityRegistry for entity info
	return EntityRegistry.get_info(entity_id, discovery, clearance_level)

# ============================================================================
# CLEARANCE MANAGEMENT
# ============================================================================

func set_clearance_level(level: int) -> void:
	"""Set player clearance level (0-5)"""
	clearance_level = clampi(level, 0, 5)
	Log.system("Clearance level set to: %d" % clearance_level)

func increase_clearance() -> void:
	"""Increase clearance level by 1 (max 5)"""
	if clearance_level < 5:
		clearance_level += 1
		Log.system("Clearance increased to: %d" % clearance_level)

# ============================================================================
# DEBUG / DEVELOPMENT
# ============================================================================

func reset_knowledge() -> void:
	"""Reset all knowledge (for debugging)"""
	discovered_entities.clear()
	clearance_level = 0
	researcher_classification = 0
	Log.system("Knowledge database reset")

func get_stats() -> Dictionary:
	"""Get knowledge statistics for debugging"""
	return {
		"discovered_entities": discovered_entities.size(),
		"clearance_level": clearance_level,
		"researcher_classification": researcher_classification,
		"entities": discovered_entities.keys()
	}

func print_stats() -> void:
	"""Print knowledge stats to console"""
	var stats = get_stats()
	print("\n=== KnowledgeDB Stats ===")
	print("Discovered entities: %d" % stats.discovered_entities)
	print("Clearance level: %d" % stats.clearance_level)
	print("Research score: %d" % stats.researcher_classification)
	print("Entities: %s" % str(stats.entities))
	print("========================\n")
