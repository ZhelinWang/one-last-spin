extends TokenAbility
class_name GenericAdjacencyPresenceBuffAbility

## When per_adjacent is false: if true, at least one adjacent must match; otherwise all must match.
@export var require_any: bool = true			# used when per_adjacent == false

## If true, emit one add step per matching neighbor; otherwise a single add when condition passes.
@export var per_adjacent: bool = false		  # true -> one add per matching neighbor

## Amount to add to self when condition passes.
@export var amount: int = 1

## Tag to match on adjacent tokens (case-insensitive), e.g., "coin", "worker".
@export var match_tag: String = ""

## Name to match on adjacent tokens; use instead of tag if set.
@export var match_name: String = ""

## If true, run during per-token phase (self only) instead of winner final phase.
@export var emit_as_spin_steps: bool = false	# when true, emit during per-token phase instead of final

# Toggle whether the manager treats this as Active During Spin for per-token collection
func is_active_during_spin() -> bool:
	return emit_as_spin_steps

func _has_matcher() -> bool:
	return match_tag.strip_edges() != "" or match_name.strip_edges() != ""

func _match_token(tok) -> bool:
	if not _has_matcher():
		return false
	if tok == null:
		return false
	if match_tag.strip_edges() != "" and _token_has_tag(tok, match_tag):
		return true
	if match_name.strip_edges() != "" and _token_name(tok).to_lower() == match_name.to_lower():
		return true
	return false

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var out: Array = []
	if not _has_matcher():
		return out

	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return out

	var adj_f := _adjacent_contribs(contribs, self_c)
	var adj_count := adj_f.size()
	if adj_count == 0:
		return out

	if per_adjacent:
		for nc in adj_f:
			if _match_token(nc.get("token")):
				var step := _mk_add(amount, "Adjacency buff", "ability:%s" % id).duplicate()
				step.merge({"target_kind": "self"}, true)
				out.append(step)
		return out

	var hits_final := 0
	for nc in adj_f:
		if _match_token(nc.get("token")):
			hits_final += 1
	var pass_any_final := require_any and hits_final > 0
	var pass_all_final := (not require_any) and hits_final == adj_count and adj_count > 0
	if pass_any_final or pass_all_final:
		var merged := _mk_add(amount, "Adjacency buff", "ability:%s" % id).duplicate()
		merged.merge({"target_kind": "self"}, true)
		out.append(merged)

	return out

# Optional per-token emission (when emit_as_spin_steps == true)
func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	if not emit_as_spin_steps:
		return []
	if not _has_matcher():
		return []
	# Only self phase
	if contrib == null or contrib.is_empty() or contrib.get("token") != source_token:
		return []
	# Reuse the same adjacency logic against the current five-slot window
	var fake_contribs: Array = []
	# Reconstruct contribs array from ctx: winner + neighbors in offsets [-2,-1,0,1,2]
	var offsets := [-2, -1, 0, 1, 2]
	for off in offsets:
		var t = null
		if off == 0:
			t = ctx.get("winner") if ctx.has("winner") else null
		else:
			var order := [-2, -1, 1, 2]
			var idx := order.find(off)
			if idx != -1 and ctx.has("neighbors") and (ctx["neighbors"] is Array) and idx < (ctx["neighbors"] as Array).size():
				t = (ctx["neighbors"] as Array)[idx]
		var c := {
			"token": t,
			"offset": off,
			"kind": ("active" if off == 0 else "passive"),
			"base": 0, "delta": 0, "mult": 1.0,
			"meta": {}
		}
		fake_contribs.append(c)

	var self_c := _find_self_contrib(fake_contribs, source_token)
	if self_c.is_empty():
		return []
	var adj := _adjacent_contribs(fake_contribs, self_c)
	if adj.is_empty():
		return []

	if per_adjacent:
		var out_steps: Array = []
		for nc in adj:
			if _match_token(nc.get("token")):
				var step := _mk_add(amount, "Adjacency buff", "ability:%s" % id).duplicate()
				step.merge({"target_kind": "self"}, true)
				out_steps.append(step)
		return out_steps

	var hits := 0
	for nc in adj:
		if _match_token(nc.get("token")):
			hits += 1
	var pass_any := require_any and hits > 0
	var pass_all := (not require_any) and hits == adj.size() and adj.size() > 0
	if pass_any or pass_all:
		var merged := _mk_add(amount, "Adjacency buff", "ability:%s" % id).duplicate()
		merged.merge({"target_kind": "self"}, true)
		return [merged]
	return []

func should_refresh_after_board_change() -> bool:
	# This adjacency depends on neighbors; re-evaluate when the board changes mid-spin.
	return true
