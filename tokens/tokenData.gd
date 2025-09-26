extends Resource
class_name TokenLootData

## In-game display name for this token.
@export var name: String

## Rarity weight used by loot/selection systems (higher = more common).
@export var weight: float = 1.0

## Rarity label used for visuals and balancing: common | uncommon | rare | legendary
@export var rarity: String = "common"

## Icon shown in UI for this token.
@export var icon: Texture2D = load("res://placehold.jpg")

## Base value before spin-time modifications.
@export var value: int = 1

## Tags used by abilities/selectors/conditions (e.g., "Coin", "Worker").
@export var tags: PackedStringArray = PackedStringArray([])

## The list of abilities attached to this token (data-driven or scripted).
@export var abilities: Array[TokenAbility] = []

## Short active effect description (displayed when token is the winner).
@export var activeDescription: String

## Short passive effect description (displayed otherwise or in tooltips).
@export var passiveDescription: String

const RARITY_COLORS := {
	"common": Color(1, 1, 1),            # white
	"uncommon": Color(0.45, 1.0, 0.45),  # green
	"rare": Color(0.4, 0.6, 1.0),        # blue
	"legendary": Color(1.0, 0.84, 0.0)   # gold
}

func get_color() -> Color:
	return RARITY_COLORS.get(rarity.to_lower(), Color.WHITE)
