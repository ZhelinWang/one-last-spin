#GenericDestroyNeighborAbility
#Effect:
#- During the command phase, targets the immediate neighbor at neighbor_offset relative to the source token
#(use -1 for left, +1 for right, ±2 for edges) and requests its destruction.
#- If respect_guard is true, your executor should allow guard/aura mechanics to intercept and prevent removal.
#Usage:
#- Attach to a token you want to remove an adjacent token.
#- Configure:
#- neighbor_offset: which neighbor to hit (-1/1/±2).
#- respect_guard: whether destroy can be vetoed by guard effects.
#- Ensure your CoinManager/executor collects ability build_commands and supports:
#{ op: "destroy", target_kind: "offset", target_offset: int, respect_guard: bool }.
#Notes:
#- If the neighbor doesn’t exist this emits no command.
#- This uses the spin contribs’ offsets, so it runs only in contexts where contribs are provided (e.g., during a spin).

extends TokenAbility
class_name GenericDestroyNeighborAbility

@export var neighbor_offset: int = 1
@export var respect_guard: bool = true

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty(): return []
	var target := _neighbor_at_offset(contribs, self_c, neighbor_offset)
	if target.is_empty(): return []
	return [{"op":"destroy","target_kind":"offset","target_offset":int(target.get("offset",0)),"respect_guard":respect_guard}]
