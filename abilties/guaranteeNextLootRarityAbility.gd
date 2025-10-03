extends TokenAbility
class_name GuaranteeNextLootRarityAbility

@export var rarity: String = "uncommon"
@export var count: int = 1

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	if winner_only:
		var self_c: Dictionary = _find_self_contrib(contribs, source_token)
		if self_c.is_empty() or int(self_c.get("offset", 99)) != 0:
			return []
	var rarity_l: String = String(rarity).strip_edges().to_lower()
	if rarity_l == "":
		return []
	var amount: int = max(1, int(count))
	return [{
		"op": "guarantee_next_loot_rarity",
		"rarity": rarity_l,
		"count": amount,
		"source": "ability:%s" % String(id)
	}]
