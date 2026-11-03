class_name AdvisorPolicy
extends RefCounted
## How an advisor picks which option to recommend from a ranked list that a
## game system produced (best first). Policies are named in advisor data, so a
## later advisor can be steered toward self-interested or misleading picks
## without touching the systems that rank the options.
##
## Policies: "best" (the top option). Unknown names fall back to "best".

const BEST := "best"


## The chosen option, or {} when there are none. `rng` is the advisor's own
## random stream (never the gameplay RNG), for policies that need chance.
static func select(policy: String, options: Array[Dictionary], _rng: RandomNumberGenerator) -> Dictionary:
	if options.is_empty():
		return {}
	match policy:
		BEST:
			return options[0]
		_:
			push_warning("Unknown advisor policy '%s'; using '%s'" % [policy, BEST])
			return options[0]
