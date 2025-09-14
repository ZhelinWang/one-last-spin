# GenericNormalizeTagToExtremeAbility
# Effect:
# - During Active During Spin, finds all tokens on the board with `tag` and computes the group’s extreme value
#   (MAX or MIN). Then requests all tagged tokens to have their value set to that extreme, normalizing the group.
#
# Usage:
# - Attach to a token and set:
#   - tag: which tokens to normalize (e.g., "coin").
#   - extreme: MAX to raise all to the highest value among them, MIN to lower all to the smallest.
# - Requires your executor to process the command:
#   { op: "set_value", target_kind: "tag", target_tag: <tag>, value: <int> }.
# - ctx.board_tokens is preferred for scanning; falls back to tokens from contribs if not provided.
#
# Notes:
# - No command is emitted if no tagged tokens are found or the target value is invalid.
# - Runs only when trigger == ACTIVE_DURING_SPIN.
# - If multiple abilities try to modify the same tokens, define executor ordering to avoid conflicts.

extends TokenAbility
class_name GenericNormalizeTagToExtremeAbility

enum Extreme { MAX, MIN }

@export var tag: String = "coin"
@export var extreme: Extreme = Extreme.MAX

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN:
		return []

	var tokens: Array = []
	if ctx.has("board_tokens") and ctx["board_tokens"] is Array:
		tokens = ctx["board_tokens"]
	else:
		for c in contribs:
			if c.has("token"):
				tokens.append(c["token"])

	var target_val: int
	if extreme == Extreme.MAX:
		target_val = 0
	else:
		target_val = INF

	for t in tokens:
		if _token_has_tag(t, tag):
			var v = t.get("value")
			var iv: int
			if v != null:
				iv = v
			else:
				iv = 0

			if extreme == Extreme.MAX:
				target_val = max(target_val, iv)
			else:
				target_val = min(target_val, iv)

	if target_val < 0 or target_val == INF:
		return []

	return [{
		"op": "set_value",
		"target_kind": "tag",
		"target_tag": tag,
		"value": target_val
	}]
