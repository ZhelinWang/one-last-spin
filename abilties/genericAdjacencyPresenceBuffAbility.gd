extends TokenAbility
class_name GenericAdjacencyPresenceBuffAbility

@export var require_any: bool = true           # used when per_adjacent == false
@export var per_adjacent: bool = false         # true -> one add per matching neighbor
@export var amount: int = 1
@export var match_tag: String = ""             # e.g., "coin", "worker"
@export var match_name: String = ""            # alternative to tag

# IMPORTANT: Make the manager ignore this as an "Active During Spin" auto-step.
func is_active_during_spin() -> bool:
	return false

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

	var adj := _adjacent_contribs(contribs, self_c)
	var adj_count := adj.size()
	if adj_count == 0:
		return out

	var hits := 0
	if per_adjacent:
		for nc in adj:
			if _match_token(nc.get("token")):
				hits += 1
				var step := _mk_add(amount, "Adjacency buff", "ability:%s" % id).duplicate()
				step.merge({"target_kind": "self"}, true)
				out.append(step)
		return out

	# grouped mode: one step if any/all matches
	for nc in adj:
		if _match_token(nc.get("token")):
			hits += 1

	var pass_any := require_any and hits > 0
	var pass_all := (not require_any) and hits == adj_count and adj_count > 0
	if pass_any or pass_all:
		var merged := _mk_add(amount, "Adjacency buff", "ability:%s" % id).duplicate()
		merged.merge({"target_kind": "self"}, true)
		out.append(merged)

	return out
