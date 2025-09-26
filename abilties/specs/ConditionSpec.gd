extends Resource
class_name AbilityCondition

# Simple, reusable condition for abilities/effects.
# Supported kinds:
# - "always"                              -> always true
# - "has_tag"                             -> source token has tag == tag
# - "name_is"                             -> source token name == name
# - "count_tag_at_least"                  -> count of tokens in inventory with tag >= min_count
# - "value_at_least" | "value_at_most"   -> current contrib value threshold checks
# - "random_chance"                       -> passes with probability `chance` (0..1)
# - "adjacent_any_tag"                    -> any adjacent neighbor has tag
# - "adjacent_all_tag"                    -> all adjacent neighbors have tag (and there is at least one neighbor)
# - "adjacent_count_tag_at_least"         -> at least min_count adjacent neighbors have tag
# - "is_winner"                            -> passes only if this token is in the winner (center) slot
# - "not_winner"                           -> passes only if this token is NOT in the winner slot

## Condition kind to check (see header comment for supported kinds).
@export var kind: String = "always"

## For tag-based checks: tag to look for (case-insensitive).
@export var tag: String = ""

## For name-based checks: exact token name.
@export var name: String = ""

## For count-based checks: minimum count required to pass.
@export var min_count: int = 1

## For random_chance: probability between 0.0 and 1.0 inclusive.
@export var chance: float = 1.0

## For value threshold checks: value to compare against.
@export var threshold: int = 0

func _str_eqi(a: String, b: String) -> bool:
	return a.strip_edges().to_lower() == b.strip_edges().to_lower()

# Helper interface expected from caller (EffectSpec):
# - _token_has_tag(token, tag) -> bool
# - _token_name(token) -> String
# - _count_in_inventory(ctx, tag) -> int
# - _contrib_value(contrib: Dictionary) -> int
# - mk_rng() from ctx: ctx.get("rng") or local RNG

func passes(ctx: Dictionary, contrib: Dictionary, contribs: Array, source_token: Resource, helper) -> bool:
	var k := kind.strip_edges().to_lower()
	match k:
		"always":
			return true
		"has_tag":
			return helper._token_has_tag(source_token, tag)
		"name_is":
			return helper._str_eqi(helper._token_name(source_token), name)
		"count_tag_at_least":
			return helper._count_in_inventory(ctx, tag) >= int(min_count)
		"value_at_least":
			return helper._contrib_value(contrib) >= int(threshold)
		"value_at_most":
			return helper._contrib_value(contrib) <= int(threshold)
		"random_chance":
			var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
			if not ctx.has("rng"): rng.randomize()
			return rng.randf() <= max(0.0, min(1.0, float(chance)))
		"adjacent_any_tag":
			return _adjacent_tag_check(contribs, source_token, helper, tag, 1, false)
		"adjacent_all_tag":
			return _adjacent_tag_check(contribs, source_token, helper, tag, 9999, true)
		"adjacent_count_tag_at_least":
			return _adjacent_tag_check(contribs, source_token, helper, tag, int(min_count), false)
		"is_winner":
			return _is_self_winner(contribs, source_token, helper)
		"not_winner":
			return not _is_self_winner(contribs, source_token, helper)
		_:
			# Unknown kinds default to true to avoid silent lockouts
			return true

func _adjacent_tag_check(contribs: Array, source_token: Resource, helper, tag_name: String, need: int, require_all: bool) -> bool:
	if contribs == null or not (contribs is Array):
		return false
	var self_c: Variant = helper._find_self_contrib(contribs, source_token)

	if self_c.is_empty():
		return false
	var adj: Variant = helper._adjacent_contribs(contribs, self_c)
	if adj.is_empty():
		return false
	var hits := 0
	for nc in adj:
		if helper._token_has_tag(nc.get("token"), tag_name):
			hits += 1
	if require_all:
		return hits == adj.size()
	return hits >= max(1, need)

func _is_self_winner(contribs: Array, source_token: Resource, helper) -> bool:
	if contribs == null or not (contribs is Array):
		return false
	var self_c: Variant = helper._find_self_contrib(contribs, source_token)

	if self_c.is_empty():
		return false
	return int(self_c.get("offset", 99)) == 0
