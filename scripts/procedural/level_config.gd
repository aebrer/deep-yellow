class_name ProceduralLevelConfig extends RefCounted
## Configuration for procedural level generation

var level_id: int = 0  # Level number (0, 1, 2...)
var level_name: String = ""  # Display name (e.g., "Level 0 - The Lobby")
var permitted_entities: Array[EntityConfig] = []  # Spawnable entities
var corruption_per_chunk: float = 0.01  # How fast corruption increases

func initialize(p_level_id: int, p_level_name: String, p_corruption_per_chunk: float = 0.01) -> void:
	"""Initialize level configuration"""
	level_id = p_level_id
	level_name = p_level_name
	corruption_per_chunk = p_corruption_per_chunk

func add_entity(config: EntityConfig) -> void:
	"""Add an entity configuration to this level"""
	permitted_entities.append(config)

func get_entity_config(entity_id: String) -> EntityConfig:
	"""Get configuration for a specific entity

	Returns null if entity is not permitted on this level.
	"""
	for config in permitted_entities:
		if config.entity_id == entity_id:
			return config
	return null

func _to_string() -> String:
	return "LevelConfig(%d: %s, entities=%d)" % [
		level_id,
		level_name,
		permitted_entities.size()
	]
