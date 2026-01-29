class_name BehaviorRegistry extends RefCounted
## Registry for entity behaviors
##
## Maps entity_type strings to behavior instances.
## Behaviors are stateless, so we use singleton instances.

# Preload behavior classes
const _EntityBehavior = preload("res://scripts/ai/behaviors/entity_behavior.gd")
const _DebugEnemyBehavior = preload("res://scripts/ai/behaviors/debug_enemy_behavior.gd")
const _BacteriaSpawnBehavior = preload("res://scripts/ai/behaviors/bacteria_spawn_behavior.gd")
const _BacteriaMotherloadBehavior = preload("res://scripts/ai/behaviors/bacteria_motherload_behavior.gd")
const _SmilerBehavior = preload("res://scripts/ai/behaviors/smiler_behavior.gd")
const _BacteriaSpreaderBehavior = preload("res://scripts/ai/behaviors/bacteria_spreader_behavior.gd")
const _TutorialMannequinBehavior = preload("res://scripts/ai/behaviors/tutorial_mannequin_behavior.gd")

# Singleton instance
static var _instance: BehaviorRegistry = null

# Cached behavior instances (stateless, so one per type is fine)
var _behaviors: Dictionary = {}

static func get_instance() -> BehaviorRegistry:
	"""Get or create singleton instance"""
	if _instance == null:
		_instance = BehaviorRegistry.new()
		_instance._init_behaviors()
	return _instance

func _init_behaviors() -> void:
	"""Initialize behavior instances"""
	_behaviors = {
		"debug_enemy": _DebugEnemyBehavior.new(),
		"bacteria_spawn": _BacteriaSpawnBehavior.new(),
		"bacteria_motherload": _BacteriaMotherloadBehavior.new(),
		"bacteria_spreader": _BacteriaSpreaderBehavior.new(),
		"smiler": _SmilerBehavior.new(),
		"tutorial_mannequin": _TutorialMannequinBehavior.new(),
	}

static func get_behavior(entity_type: String) -> EntityBehavior:
	"""Get behavior for entity type

	Args:
		entity_type: Entity type ID (e.g., "bacteria_spawn", "smiler")

	Returns:
		EntityBehavior instance, or base EntityBehavior for unknown types
	"""
	var instance = get_instance()
	return instance._get_behavior_internal(entity_type)

func _get_behavior_internal(entity_type: String) -> EntityBehavior:
	"""Internal implementation of get_behavior"""
	if _behaviors.has(entity_type):
		return _behaviors[entity_type]

	# Unknown type - return base behavior (does nothing)
	Log.warn(Log.Category.ENTITY, "No behavior registered for entity type: %s" % entity_type)
	if not _behaviors.has("_default"):
		_behaviors["_default"] = _EntityBehavior.new()
	return _behaviors["_default"]

static func register_behavior(entity_type: String, behavior: EntityBehavior) -> void:
	"""Register a custom behavior at runtime

	Args:
		entity_type: Entity type ID
		behavior: Behavior instance to use
	"""
	var instance = get_instance()
	instance._behaviors[entity_type] = behavior
