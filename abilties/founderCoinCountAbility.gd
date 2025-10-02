extends TokenAbility
class_name FounderCoinCountAbility

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN:
		return []
	if contrib.get("token") != source_token:
		return []
	var coin_count := _count_in_inventory(ctx, "coin")
	if coin_count <= 0:
		return []
	return [_mk_add_step(int(coin_count), "+%d per Coin" % coin_count, "ability:%s" % String(id))]
