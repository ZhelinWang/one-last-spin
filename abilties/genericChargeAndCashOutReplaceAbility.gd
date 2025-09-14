#GenericChargeAndCashOutReplaceAbility
#Effect:
#- “Charge” and “Cash Out” behavior using a stored counter on the source token.
#- Cash Out (during Active During Spin): replaces the source token at its offset with the resource at replace_path and sets its value to the stored counter (store_key), then you typically reset the counter externally.
#- Charge (when not winner): intended to increment the counter each spin where the token doesn’t win.
#Usage:
#- Attach to a token that should accumulate a charge and transform into another token to redeem that charge.
#- Configure:
#- store_key: the int property on the token used as the counter (e.g., "charge").
#- replace_path: resource path to the token used when cashing out.
#- increment_on_non_winner_trigger: if true, increment the counter on non-winner spins (requires executor hook; see Notes).
#- Set trigger:
#- Active During Spin → ability will “cash out” by emitting a replace_at_offset command:
#{ op: "replace_at_offset", offset, token_path: replace_path, set_value: stored_count, preserve_tags: false }
#- Any other trigger → no cash out; see Notes for charging.
#Requirements:
#- Your CoinManager/executor must support the command:
#op: "replace_at_offset", fields: offset:int, token_path:String, set_value:int, preserve_tags:bool.
#Notes:
#- build_final_steps is only collected for the winner, so increment_on_non_winner_trigger inside build_final_steps won’t fire as written.
#To actually “charge” on non-winner spins, implement one of:
#1) Call on_not_triggered for non-winner tokens and increment there, or
#2) Emit a custom command (e.g., {op:"inc_store", key:store_key, by:1}) for non-winners and handle it in your executor, or
#3) Increment in build_steps for non-winner contribs and return [] (side-effect only).
#- If you need to preserve tags on the replacement token, set preserve_tags = true and merge those in your executor.

extends TokenAbility
class_name GenericChargeAndCashOutReplaceAbility

@export var store_key: String = "charge"
@export var increment_on_non_winner_trigger: bool = true
@export var replace_path: String = "res://tokens/coin.tres"

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var out: Array = []
	# Final steps are collected only for the winner; this guard is fine.
	if trigger == TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return out
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return out
	# WARNING: self_c.offset is 0 for the winner; this block won't run here.
	if increment_on_non_winner_trigger and int(self_c.get("offset", 99)) != 0:
		var x_v = source_token.get(store_key)
		var x: int = int(x_v) if x_v != null else 0
		source_token.set(store_key, x + 1)
	return out

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	# Cash out: only when this ability is set to Active During Spin.
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var x_v = source_token.get(store_key)
	var x: int = int(x_v) if x_v != null else 0
	return [{
		"op": "replace_at_offset",
		"offset": int(self_c.get("offset", 0)),
		"token_path": replace_path,
		"set_value": x,
		"preserve_tags": false
	}]
