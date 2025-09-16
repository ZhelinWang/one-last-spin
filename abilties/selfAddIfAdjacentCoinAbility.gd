extends TokenAbility
class_name SelfAddIfAdjacentCoinAbility

@export var amount: int = 2

# Passive-like: during the per-token phase, if any adjacent token in the current
# five-slot window is a coin type, add +amount to self.
func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	# Only target self during its own per-token phase
	if not matches_target(ctx, contrib, source_token):
		return []

	# Determine our offset and adjacent offsets within the five-slot context
	var off: int = int(contrib.get("offset", 99))
	if off == 99:
		return []
	var adj_offsets: Array = []
	match off:
		-2:
			adj_offsets = [-1]
		-1:
			adj_offsets = [-2, 0]
		0:
			adj_offsets = [-1, 1]
		1:
			adj_offsets = [0, 2]
		2:
			adj_offsets = [1]
		_:
			adj_offsets = []

	# Resolve tokens at those offsets from ctx (winner + neighbors array)
	var neighbors := []
	if ctx.has("neighbors"):
		neighbors = ctx.get("neighbors")
	var winner = ctx.get("winner") if ctx.has("winner") else null

	func token_at_offset(o: int):
		if o == 0:
			return winner
		var norder := [-2, -1, 1, 2]
		var idx := norder.find(o)
		if idx == -1:
			return null
		if neighbors is Array and idx < (neighbors as Array).size():
			return (neighbors as Array)[idx]
		return null

	var has_coin_adjacent := false
	for ao in adj_offsets:
		var tok = token_at_offset(ao)
		if tok != null and (_is_coin(tok) or _token_has_tag(tok, "coin")):
			has_coin_adjacent = true
			break

	if has_coin_adjacent and amount != 0:
		return [_mk_add(amount, "Adjacency coin buff", "ability:%s" % id)]
	return []
