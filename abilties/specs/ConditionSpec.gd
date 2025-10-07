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
# - "adjacent_any_higher"                 -> any adjacent neighbor has higher value than self
# - "adjacent_all_tag"                    -> all adjacent neighbors have tag (and there is at least one neighbor)
# - "adjacent_count_tag_at_least"         -> at least min_count adjacent neighbors have tag
# - "is_winner"                            -> passes only if this token is in the winner (center) slot
# - "not_winner"                           -> passes only if this token is NOT in the winner slot
# - "triggered_any_name_is"                -> any triggered slot has exact name (case-insensitive)

## Condition kind to check (see header comment for supported kinds).
@export_enum(
	"Always: always",
	"Source Has Tag: has_tag",
	"Source Name Is: name_is",
	"Inventory Count Of Tag At Least: count_tag_at_least",
	"Value At Least: value_at_least",
	"Value At Most: value_at_most",
	"Random Chance: random_chance",
	"Adjacent Any Has Tag: adjacent_any_tag",
	"Adjacent Any Higher Value: adjacent_any_higher",
	"Adjacent Any Name Is: adjacent_any_name_is",
	"Adjacent Any Of Tags: adjacent_any_of_tags",
	"Adjacent All Have Tag: adjacent_all_tag",
	"Adjacent Count Tag At Least: adjacent_count_tag_at_least",
	"Inventory Count Of Name At Least: count_name_at_least",
	"Inventory Count Of Name At Most: count_name_at_most",
	"Destroyed Is Adjacent: destroyed_is_adjacent",
	"Destroyed Offset Equals: destroyed_offset_is",
	"Is Winner (Center): is_winner",
	"Not Winner: not_winner",
	"Destroyed Has Tag: destroyed_has_tag",
    "Destroyed Name Is: destroyed_name_is"
) var kind: String = "always"

## For tag-based checks: tag to look for (case-insensitive).
@export var tag: String = ""

## For name-based checks: exact token name.
@export var name: String = ""

## For multi-tag adjacency checks: list of tags (lowercase-insensitive compare).
@export var tags_list: PackedStringArray = PackedStringArray()

## For count-based checks: minimum count required to pass.
@export var min_count: int = 1

## For random_chance: probability between 0.0 and 1.0 inclusive.
@export var chance: float = 1.0

## Optional editor-friendly percent field (0..100). If >= 0, overrides `chance`.
@export_range(0, 100, 1) var chance_percent: int = -1

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
			var prob := float(chance)
			if int(chance_percent) >= 0:
				prob = clamp(float(chance_percent) / 100.0, 0.0, 1.0)
			return rng.randf() <= max(0.0, min(1.0, prob))
		"adjacent_any_tag":
			return _adjacent_tag_check(contribs, source_token, helper, tag, 1, false)
		"adjacent_any_name_is":
			if contribs == null or not (contribs is Array):
				return false
			var self_c: Variant = helper._find_self_contrib(contribs, source_token)
			if self_c.is_empty():
				return false
			var adj: Variant = helper._adjacent_contribs(contribs, self_c)
			if adj.is_empty():
				return false
			for nc in adj:
				var nm = helper._token_name(nc.get("token"))
				if helper._str_eqi(nm, name):
					return true
			return false
		"adjacent_any_of_tags":
			if contribs == null or not (contribs is Array):
				return false
			var self_c2: Variant = helper._find_self_contrib(contribs, source_token)
			if self_c2.is_empty():
				return false
			var adj2: Variant = helper._adjacent_contribs(contribs, self_c2)
			if adj2.is_empty():
				return false
			var want: Array = []
			for t in tags_list:
				want.append(String(t).to_lower())
			for nc2 in adj2:
				var tok = nc2.get("token")
				for t2 in want:
					if helper._token_has_tag(tok, t2):
						return true
			return false
		"adjacent_any_higher":
			if contribs == null or not (contribs is Array):
				return false
			var self_c: Variant = helper._find_self_contrib(contribs, source_token)
			if self_c.is_empty():
				return false
			var self_val = helper._contrib_value(self_c)
			var adj: Variant = helper._adjacent_contribs(contribs, self_c)
			if adj.is_empty():
				return false
			for nc in adj:
				if helper._contrib_value(nc) > self_val:
					return true
			return false
		"adjacent_all_tag":
			return _adjacent_tag_check(contribs, source_token, helper, tag, 9999, true)
		"adjacent_count_tag_at_least":
			return _adjacent_tag_check(contribs, source_token, helper, tag, int(min_count), false)
		"destroyed_is_adjacent":
			if ctx == null or not (ctx is Dictionary):
				return false
			var off_d := int(ctx.get("last_destroyed_offset", 999))
			if off_d == 999:
				return false
			if contribs == null or not (contribs is Array):
				return false
			var self_c3: Variant = helper._find_self_contrib(contribs, source_token)
			if self_c3.is_empty():
				return false
			var self_off := int(self_c3.get("offset", 999))
			return abs(off_d - self_off) == 1
		"destroyed_offset_is":
			if ctx == null or not (ctx is Dictionary):
				return false
			var off_d2 := int(ctx.get("last_destroyed_offset", 999))
			return off_d2 == int(threshold)
		"count_name_at_least":
			if ctx == null or not (ctx is Dictionary):
				return false
			var arr = ctx.get("board_tokens")
			if not (arr is Array):
				return false
			var c := 0
			for t in arr:
				if t != null and (t as Object).has_method("get"):
					var nmv = String(t.get("name"))
					if helper._str_eqi(nmv, name):
						c += 1
			return c >= int(min_count)
		"count_name_at_most":
			if ctx == null or not (ctx is Dictionary):
				return false
			var arr2 = ctx.get("board_tokens")
			if not (arr2 is Array):
				return false
			var c2 := 0
			for t2 in arr2:
				if t2 != null and (t2 as Object).has_method("get"):
					var nmv2 = String(t2.get("name"))
					if helper._str_eqi(nmv2, name):
						c2 += 1
			return c2 <= int(min_count)
		"is_winner":
			return _is_self_winner(contribs, source_token, helper)
		"not_winner":
			return not _is_self_winner(contribs, source_token, helper)
		"triggered_any_name_is":
			if contribs == null or not (contribs is Array):
				return false
			for c in contribs:
				if c is Dictionary:
					var nm = helper._token_name((c as Dictionary).get("token"))
					if helper._str_eqi(nm, name):
						return true
			return false
		"destroyed_has_tag":
			var d = null
			if ctx is Dictionary and ctx.has("last_destroyed_token"):
				d = ctx["last_destroyed_token"]
			return d != null and (d as Object).has_method("get") and helper._token_has_tag(d, tag)
		"destroyed_name_is":
			var dx = null
			if ctx is Dictionary and ctx.has("last_destroyed_token"):
				dx = ctx["last_destroyed_token"]
			if dx == null or not (dx as Object).has_method("get"):
				return false
			return helper._str_eqi(helper._token_name(dx), name)
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
