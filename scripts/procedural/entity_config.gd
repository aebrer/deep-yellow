class_name EntityConfig extends RefCounted
## Configuration for a spawnable entity type

var entity_id: String = ""  # Unique identifier (e.g., "bacteria", "hound")
var base_probability: float = 0.0  # Base spawn chance per sub-chunk (0.0-1.0)
var corruption_multiplier: float = 0.0  # How corruption affects spawn rate
# Positive: becomes MORE common (enemies, hazards)
# Negative: becomes LESS common (items, exits)
# Zero: unaffected by corruption

func initialize(p_entity_id: String, p_base_probability: float, p_corruption_multiplier: float) -> EntityConfig:
	"""Initialize entity configuration (returns self for chaining)"""
	entity_id = p_entity_id
	base_probability = p_base_probability
	corruption_multiplier = p_corruption_multiplier
	return self

func _to_string() -> String:
	return "EntityConfig(%s, base=%.3f, mult=%.2f)" % [
		entity_id,
		base_probability,
		corruption_multiplier
	]
