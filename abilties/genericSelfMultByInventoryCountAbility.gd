extends TokenAbility
class_name GenericSelfMultByInventoryCountAbility

## Count tokens in inventory with this tag; use the count as a multiplier.
@export var tag: String = "coin"

## If the count is >= threshold, do not apply the multiplier (acts as a cap gate).
@export var threshold: int = 5

## Minimum multiplier to apply (clamps the count if too low).
@export var min_factor: float = 0.0 # clamp to at least this value

func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	# Only self-target in this ability
	if target_kind != TokenAbility.TargetKind.SELF:
		return []
	if not matches_target(ctx, contrib, source_token):
		return []
	var cnt := 0
	if ctx.has("board_tokens") and (ctx["board_tokens"] is Array):
		for t in ctx["board_tokens"]:
			if _token_has_tag(t, tag):
				cnt += 1
	if cnt >= threshold:
		return []
	var fac: float = float(cnt)
	if fac < min_factor:
		fac = min_factor
	var src_name := _token_name(source_token)
	return [_mk_mult_step(fac, "Inventory coin count multiplier", "ability:%s" % id)]

func should_refresh_after_board_change() -> bool:
	return true


