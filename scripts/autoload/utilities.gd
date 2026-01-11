extends Node
## Global utility functions
##
## Shared math and helper functions used across the codebase.
## Autoloaded as "Utilities" for global access.

# ============================================================================
# MATH UTILITIES
# ============================================================================

static func bankers_round(value: float) -> float:
	"""Round using banker's rounding (round half to even).

	Unlike roundf() which rounds 0.5 away from zero (biased upward for positive),
	banker's rounding rounds 0.5 to the nearest even integer, giving an unbiased
	distribution over many values. This is Python's default round() behavior.

	Examples:
		0.5 → 0 (rounds to even)
		1.5 → 2 (rounds to even)
		2.5 → 2 (rounds to even)
		3.5 → 4 (rounds to even)
		2.4 → 2, 2.6 → 3 (normal rounding)
	"""
	var floored = floorf(value)
	var frac = value - floored

	if frac < 0.5:
		return floored
	elif frac > 0.5:
		return floored + 1.0
	else:
		# Exactly 0.5 - round to even
		if int(floored) % 2 == 0:
			return floored  # Already even, round down
		else:
			return floored + 1.0  # Odd, round up to even
