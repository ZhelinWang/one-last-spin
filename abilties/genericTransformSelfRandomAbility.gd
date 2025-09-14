# GenericTransformSelfRandomAbility
# Effect:
# - During Active During Spin, randomly transforms the source token into one of the `candidates` (resource paths).
# - Emits a command:
#   { op: "transform_self", to_path: <candidate>, preserve_value: true, preserve_state: true }.
#
# Usage:
# - Attach to a token and set `candidates` to a list of token resource paths (e.g., ["res://tokens/coin.tres", ...]).
# - RNG: uses ctx.rng if provided; otherwise creates and randomizes a local RNG.
#
# Executor requirements:
# - Implement command "transform_self":
#   - Load the resource at `to_path` and replace the source token with it.
#   - If preserve_value is true, copy current value; if preserve_state is true, copy relevant properties/tags/metadata.
#
# Notes:
# - No command is emitted if `candidates` is empty.
# - Define how state/perm fields merge on transform to avoid loss of key properties.

extends TokenAbility
class_name GenericTransformSelfRandomAbility

@export var candidates: PackedStringArray

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN or candidates.is_empty(): return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"): rng.randomize()
	var pick := candidates[rng.randi_range(0, candidates.size()-1)]
	return [{"op":"transform_self","to_path":String(pick),"preserve_value":true,"preserve_state":true}]
