class_name EntityInfo
extends Resource
## Entity information resource with progressive revelation
##
## Defines how entity information is revealed as player gains knowledge.
## Used by KnowledgeDB and EntityRegistry for examination system.

@export_group("Identity")
@export var entity_id: String = ""  ## Unique identifier (e.g., "skin_stealer")

@export_group("Progressive Name Revelation")
## Name revelation based on discovery level (0-3)
@export var name_levels: Array[String] = [
	"████████",                    # Discovery 0: Unknown
	"???",                         # Discovery 1: Detected
	"Unknown Entity",              # Discovery 2: Identified
	"Entity Name"                  # Discovery 3: Fully Known
]

@export_group("Progressive Description Revelation")
## Description revelation based on discovery level (0-3)
@export var description_levels: Array[String] = [
	"[DATA EXPUNGED]",
	"Entity detected. Approach with caution. [REDACTED]",
	"Entity identified. [FURTHER DATA REQUIRES HIGHER CLEARANCE]",
	"Full entity information available."
]

@export_group("Clearance Requirements")
## Minimum clearance required for each discovery level (0-3)
@export var clearance_required: Array[int] = [0, 0, 1, 2]

@export_group("Classification")
## SCP-style object class based on discovery level
@export var object_class_levels: Array[String] = [
	"[REDACTED]",
	"Unknown",
	"Euclid",
	"Euclid"
]

## Threat level (0-5 scale)
@export var threat_level: int = 0

# ============================================================================
# API
# ============================================================================

func get_entity_name(discovery_level: int, clearance: int) -> String:
	"""Get entity name for discovery level and clearance"""
	var level = clampi(discovery_level, 0, 3)

	# Check clearance requirement
	if clearance < clearance_required[level]:
		return "[INSUFFICIENT CLEARANCE]"

	if level < name_levels.size():
		return name_levels[level]
	else:
		return "Unknown"

func get_entity_description(discovery_level: int, clearance: int) -> String:
	"""Get entity description for discovery level and clearance"""
	var level = clampi(discovery_level, 0, 3)

	# Check clearance requirement
	if clearance < clearance_required[level]:
		return "CLEARANCE LEVEL %d REQUIRED" % clearance_required[level]

	if level < description_levels.size():
		return description_levels[level]
	else:
		return "[NO DATA]"

func get_entity_object_class(discovery_level: int, clearance: int) -> String:
	"""Get SCP object class for discovery level and clearance"""
	var level = clampi(discovery_level, 0, 3)

	# Check clearance requirement
	if clearance < clearance_required[level]:
		return "[REDACTED]"

	if level < object_class_levels.size():
		return object_class_levels[level]
	else:
		return "Unknown"

func get_info(discovery_level: int, clearance: int) -> Dictionary:
	"""Get complete entity info dictionary"""
	return {
		"name": get_entity_name(discovery_level, clearance),
		"description": get_entity_description(discovery_level, clearance),
		"object_class": get_entity_object_class(discovery_level, clearance),
		"threat_level": threat_level
	}
