# GenericGuardAuraAbility
# Effect:
# - During the command phase, registers a “guard aura” at the source token’s offset for the current spin.
# - Your executor should treat guarded offsets as protected: intercept and cancel destructive/removal ops
#   (e.g., {op:"destroy"}, {op:"replace_at_offset"}) that target the guarded slot.
#
# Usage:
# - Attach to any token that should protect itself from being destroyed/replaced this spin.
# - Ensure your CoinManager/executor:
#   - Collects ability build_commands and processes: { op: "register_guard_aura", offset: int }.
#   - Maintains a per-spin guard registry, checking it before applying destructive ops.
#   - Clears the registry at the end of the spin/phase to avoid leaking state.
#
# Notes:
# - This script guards the source token’s own offset; for broader auras, extend the command to cover ranges/tags.
# - Define precedence if multiple effects conflict (e.g., a forced-destroy that ignores guard).

extends TokenAbility
class_name GenericGuardAuraAbility

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty(): return []
	return [{"op":"register_guard_aura","offset":int(self_c.get("offset",0))}]
