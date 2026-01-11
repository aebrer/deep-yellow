class_name Examinable
extends Area3D
## Component for objects that can be examined in Look Mode
##
## Attach to entities, items, hazards, or environment objects.
## Must be on collision layer 4 (mask = 8) for raycast detection.

@export_group("Entity Information")
@export var entity_id: String = ""  ## Unique ID, e.g., "skin_stealer", "almond_water", "yellow_wallpaper"
@export var entity_type: EntityType = EntityType.UNKNOWN

@export_group("Requirements")
@export var requires_clearance: int = 0  ## Min clearance to examine (0 = no requirement)

enum EntityType {
	UNKNOWN,
	ENTITY_HOSTILE,
	ENTITY_NEUTRAL,
	ENTITY_FRIENDLY,
	HAZARD,
	ITEM,
	ENVIRONMENT
}

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Ensure Area3D is configured correctly
	collision_layer = 8  # Layer 4 (bit 3) - for raycast detection
	collision_mask = 0   # Doesn't collide with anything, just detects raycasts

	# Add collision shape if not present (for raycast detection)
	if get_child_count() == 0:
		_add_default_collision_shape()

	if entity_id.is_empty():
		push_warning("[Examinable] No entity_id set for: %s" % get_parent().name)

func _add_default_collision_shape() -> void:
	"""Add a default box collision shape if none exists"""
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(1, 2, 1)  # Human-sized default
	shape.shape = box
	add_child(shape)

# ============================================================================
# EXAMINATION API
# ============================================================================

func can_examine() -> bool:
	"""Check if player meets requirements to examine this object"""
	return KnowledgeDB.clearance_level >= requires_clearance

func get_display_info() -> Dictionary:
	"""Get information to display in examination UI"""
	if not can_examine():
		return {
			"name": "[INSUFFICIENT CLEARANCE]",
			"object_class": "[REDACTED]",
			"threat_level": 0,
			"description": "CLEARANCE LEVEL %d REQUIRED" % requires_clearance
		}

	# Get entity info from KnowledgeDB
	return KnowledgeDB.get_entity_info(entity_id)
