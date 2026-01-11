class_name EntityInfo
extends Resource
## Entity/Environment information resource with progressive revelation via clearance
##
## Base level (clearance 0) ALWAYS shows:
## - Name (never obfuscated)
## - Visual description (what it looks like - from wiki)
## - Scaling hint (if applicable)
##
## Higher clearance levels ADDITIVELY reveal:
## - Mechanics, behavior, technical details
## - Code revelation at highest clearance
##
## Used by KnowledgeDB and EntityRegistry for examination system.

@export_group("Identity")
@export var entity_id: String = ""  ## Unique identifier (e.g., "skin_stealer", "level_0_wall")
@export var entity_name: String = ""  ## Display name (ALWAYS shown, never obfuscated)

@export_group("Descriptions")
## Visual description (CONSTANT - always shown at clearance 0+)
## This is what it LOOKS like - from Backrooms/SCP wiki
@export_multiline var visual_description: String = ""

## Scaling hint (CONSTANT - always shown at clearance 0+ if applicable)
## Brief description of what changes with level (for entities with levels)
@export var scaling_hint: String = ""

## Additional information revealed at each clearance level (ADDITIVE)
## Indexed by clearance level: [0, 1, 2, 3, 4, 5]
## Clearance 0: Just visual + scaling (no additional info)
## Clearance 1-3: Progressive mechanics/behavior details
## Clearance 4-5: Technical details + code revelation
@export var clearance_info: Array[String] = ["", "", "", "", "", ""]

@export_group("Classification")
## SCP-style object class (shown at all clearance levels)
@export var object_class: String = "Safe"

## Threat level (1-5 scale, matches entity_spawn_table threat_level)
## See get_threat_level_name() for SCP-style names
@export var threat_level: int = 1

## SCP-style threat level designations (biblical/Hebrew alphabet aesthetic)
## Matches ChunkManager's threat_level system for entity spawning
const THREAT_LEVEL_NAMES = {
	0: "○○○○○ Gimel",        # Environment/props - negligible threat
	1: "●○○○○ Daleth",       # Weak - common early (bacteria_spawn)
	2: "●●○○○ Epsilon",      # Moderate - stable distribution
	3: "●●●○○ Keter",        # Dangerous - rare early, common later (brood_mother)
	4: "●●●●○ Aleph",        # Elite - very rare, severe threat
	5: "●●●●● YOU WILL DIE", # Boss/Apex - certain death without preparation
}

# ============================================================================
# API
# ============================================================================

func get_description(clearance: int) -> String:
	"""Get entity description with ADDITIVE revelation based on clearance.

	Base level (clearance 0) ALWAYS shows:
	- Name
	- Visual description
	- Scaling hint (if applicable)

	Higher clearance ADDITIVELY reveals more info.
	"""
	var desc = ""

	# ALWAYS show name (never obfuscated)
	if entity_name:
		desc += entity_name + "\n\n"

	# ALWAYS show visual description
	if visual_description:
		desc += visual_description + "\n"

	# ALWAYS show scaling hint (if applicable)
	if scaling_hint:
		desc += "\nScaling: " + scaling_hint + "\n"

	# Add clearance-specific additional info (ADDITIVE)
	var cl = clampi(clearance, 0, 5)
	for i in range(cl + 1):
		if i < clearance_info.size() and not clearance_info[i].is_empty():
			desc += "\n" + clearance_info[i]

	return desc

func get_threat_level_name() -> String:
	"""Get SCP-style threat level designation"""
	return THREAT_LEVEL_NAMES.get(threat_level, "●●●○○ Unknown")

static func threat_level_to_name(level: int) -> String:
	"""Static helper to convert threat_level int to SCP-style name"""
	return THREAT_LEVEL_NAMES.get(level, "●●●○○ Unknown")

func get_info(clearance: int) -> Dictionary:
	"""Get complete entity info dictionary for examination UI"""
	return {
		"name": entity_name,
		"description": get_description(clearance),
		"object_class": object_class,
		"threat_level": threat_level,
		"threat_level_name": get_threat_level_name()
	}
