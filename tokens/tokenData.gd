extends Resource
class_name TokenLootData

@export var name: String
@export var weight: float = 1.0
@export var rarity: String = "common"     # common | uncommon | rare | legendary
@export var icon: Texture2D = load("res://placehold.jpg")

@export var value: int = 1
@export var tags: PackedStringArray = PackedStringArray([])

#Ability
@export var abilities: Array[TokenAbility] = []
@export var activeDescription: String
@export var passiveDescription: String

const RARITY_COLORS := {
	"common": Color(1, 1, 1),            # white
	"uncommon": Color(0.45, 1.0, 0.45),  # green
	"rare": Color(0.4, 0.6, 1.0),        # blue
	"legendary": Color(1.0, 0.84, 0.0)   # gold
}

func get_color() -> Color:
	return RARITY_COLORS.get(rarity.to_lower(), Color.WHITE)
