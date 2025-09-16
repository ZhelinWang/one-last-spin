extends TokenAbility
class_name InvestorActiveRandomAdjacentHalveAbility

# Active: Add self's current contrib value to a random adjacent token,
# then halve self (x0.5). Winner-only recommended.

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var out: Array = []
	# Winner-only behavior expected; still guard by locating self contrib
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return out

	# Determine adjacent offsets relative to self
	var adj: Array = []
	for nc in _adjacent_contribs(contribs, self_c):
		adj.append(int(nc.get("offset", 0)))
	if adj.is_empty():
		return out

	# RNG from context if available
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()

	# Choose a random adjacent offset
	var idx := rng.randi_range(0, adj.size() - 1)
	var target_off: int = int(adj[idx])

	# Compute self's current value (after prior steps)
	var self_val: int = _contrib_value(self_c)
	if self_val <= 0:
		# Still apply halving to self even if zero
		out.append({
			"kind": "mult",
			"amount": 0,
			"factor": 0.5,
			"desc": "Halve self",
			"source": "ability:%s" % id,
			"target_kind": "self"
		})
		return out

	# Step 1: add self value to the chosen adjacent offset
	out.append({
		"kind": "add",
		"amount": self_val,
		"factor": 1.0,
		"desc": "+%d to adjacent" % self_val,
		"source": "ability:%s" % id,
		"target_kind": "offset",
		"target_offset": target_off
	})

	# Step 2: halve self
	out.append({
		"kind": "mult",
		"amount": 0,
		"factor": 0.5,
		"desc": "Halve self",
		"source": "ability:%s" % id,
		"target_kind": "self"
	})

	return out
