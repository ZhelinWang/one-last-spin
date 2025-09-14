# GenericConditionalSelfMultiplierAbility
# Effect:
# - Multiplies contributions by `factor` when configured conditions pass.
# - Self-phase (per-token): if `target_kind == SELF` and conditions pass, emits a single "mult" step on self.
# - Final-phase (broadcast): if `target_kind != SELF` and conditions pass (evaluated against the winner/self),
#   emits a single global "mult" step; CoinManager targets recipients using the ability’s target_* fields.
#
# Conditions (leave empty/zero to ignore any of them):
# - require_self_tag: source must have this tag (checked on the token resource).
# - require_self_name: source’s name must match exactly (case-sensitive in this script; adjust if needed).
# - min_self_value: winner/self’s computed contrib value must be at least this amount during the spin.
# - require_board_tag + require_board_count_at_least: board must contain at least N tokens with the given tag
#   (looked up via ctx.board_tokens).
#
# Usage:
# - Attach to a token and set Trigger = ACTIVE_DURING_SPIN.
# - For a pure self-multiplier (e.g., “x2 if my value ≥ 10”), keep target_kind = SELF and set min_self_value = 10.
# - For a conditional aura/broadcast (e.g., “neighbors x1.5 if I have tag ‘coin’”), set target_kind to NEIGHBORS (or TAG/NAME/OFFSET)
#   and set require_self_tag = "coin".
# - Customize description via desc_template, which supports:
#   - %f → factor (float), %s → source token name. If no placeholders, the text is used verbatim.
#
# Notes:
# - min_self_value checks the current spin’s computed contrib (base + delta) * mult for the winner/self.
# - Board-tag counting requires ctx.board_tokens to be present (TokenAbility._count_in_inventory).
# - The emitted steps integrate with CoinManager’s normal UI (shake/popup) and broadcast

extends TokenAbility
class_name GenericConditionalSelfMultiplierAbility

@export var factor: float = 2.0
# Conditions (leave empty/zero to ignore)
@export var require_self_tag: String = ""
@export var require_self_name: String = ""
@export var min_self_value: int = 0
@export var require_board_tag: String = ""
@export var require_board_count_at_least: int = 0

func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	if target_kind != TokenAbility.TargetKind.SELF:
		return []
	if not matches_target(ctx, contrib, source_token):
		return []
	if not _conditions_pass(ctx, contrib, source_token):
		return []
	var src_name := _token_name(source_token)
	var desc := _format_desc(desc_template, factor, src_name)
	return [_mk_mult_step(factor, desc, "ability:%s" % id)]

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	# Only broadcast when not targeting self; CoinManager will target by target_kind fields.
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN or target_kind == TokenAbility.TargetKind.SELF:
		return []
	# Evaluate conditions against the winner/self contrib where needed (e.g., min_self_value)
	var self_c := _find_self_contrib(contribs, source_token)
	if not _conditions_pass(ctx, self_c, source_token):
		return []
	var src_name := _token_name(source_token)
	var desc := _format_desc(desc_template, factor, src_name)
	return [make_global_step("mult", 0, factor, desc, "ability:%s" % id)]

# ---------- internal ----------
func _conditions_pass(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> bool:
	if require_self_tag.strip_edges() != "":
		if not _token_has_tag(source_token, require_self_tag):
			return false
	if require_self_name.strip_edges() != "":
		if _token_name(source_token) != require_self_name:
			return false
	if min_self_value > 0:
		if contrib == null or contrib.is_empty():
			return false
		if _contrib_value(contrib) < min_self_value:
			return false
	if require_board_tag.strip_edges() != "" and require_board_count_at_least > 0:
		var cnt := _count_in_inventory(ctx, require_board_tag)
		if cnt < require_board_count_at_least:
			return false
	return true

func _format_desc(tpl: String, f: float, name: String) -> String:
	var s := tpl.strip_edges()
	if s == "":
		return "x%.2f" % f
	if s.find("%") == -1:
		return s
	var args := []
	if s.find("%f") != -1 and s.find("%s") != -1:
		args = [f, name]
	elif s.find("%f") != -1:
		args = [f]
	elif s.find("%s") != -1:
		args = [name]
	return s % args if args.size() > 0 else s
