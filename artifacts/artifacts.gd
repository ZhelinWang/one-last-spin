extends Resource
class_name ArtifactData

# Base class for step-wise spin effects (token descriptions or artifacts).
# Each effect returns a list of step dicts:
# { kind: "add"|"mult", amount?: int, factor?: float, desc: String }

@export var effect_name: String = "Unnamed Effect"
@export var priority: int = 100

func applies(ctx: Dictionary, contrib: Dictionary) -> bool:
	return true

func build_steps(ctx: Dictionary, contrib: Dictionary) -> Array:
	return []
