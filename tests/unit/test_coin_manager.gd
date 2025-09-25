extends GutTest

const CoinManager := preload("res://coinManager.gd")
const EMPTY_TOKEN_PATH := "res://tokens/empty.tres"
const COIN_TOKEN_PATH := "res://tokens/coin.tres"
const COPPER_TOKEN_PATH := "res://tokens/copperCoin.tres"
const EXECUTIVE_TOKEN_PATH := "res://tokens/executive.tres"

class DummyInventoryOwner:
	extends Node
	var items: Array = []
	func _update_inventory_strip() -> void:
		pass

var coin_manager: CoinManager

func before_each() -> void:
	coin_manager = CoinManager.new()
	coin_manager.debug_spin = false
	coin_manager.empty_token_path = EMPTY_TOKEN_PATH
	add_child_autofree(coin_manager)
	coin_manager._ready()

func _add_inventory_owner(initial_items: Array = []) -> DummyInventoryOwner:
	var owner := DummyInventoryOwner.new()
	owner.name = "InventoryOwner"
	owner.items = initial_items
	add_child_autofree(owner)
	coin_manager.inventory_owner_path = owner.get_path()
	return owner

func test_get_requirement_for_round_handles_schedule_and_increment() -> void:
	coin_manager.ante_schedule = PackedInt32Array([25, 45, 65])
	coin_manager.ante_increment_after_schedule = 20

	assert_eq(coin_manager._get_requirement_for_round(0), 0, "round 0 should require 0")
	assert_eq(coin_manager._get_requirement_for_round(1), 25, "first schedule entry should be used")
	assert_eq(coin_manager._get_requirement_for_round(3), 65, "last schedule entry should be used for matching round")
	assert_eq(coin_manager._get_requirement_for_round(4), 85, "first post-schedule round should add increment once")
	assert_eq(coin_manager._get_requirement_for_round(6), 125, "post-schedule rounds should keep adding increment")

func test_apply_rarity_modifiers_shifts_common_weight_by_empty_bonus() -> void:
	var empty_a := load(EMPTY_TOKEN_PATH).duplicate(true)
	var empty_b := load(EMPTY_TOKEN_PATH).duplicate(true)
	var owner := _add_inventory_owner([empty_a, empty_b])

	coin_manager.empty_non_common_bonus_per = 0.1
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var base := {
		"common": 0.5,
		"rare": 0.3,
		"epic": 0.2
	}

	var result := coin_manager._apply_rarity_modifiers(base, 2, rng)

	assert_almost_eq(result["common"], 0.3, 0.0001, "empties should shift mass away from common")
	assert_almost_eq(result["rare"], 0.42, 0.0001, "rare should gain proportional weight")
	assert_almost_eq(result["epic"], 0.28, 0.0001, "epic should gain complementary weight")
	assert_almost_eq(result["common"] + result["rare"] + result["epic"], 1.0, 0.0001, "weights should normalize")
	assert_eq(owner.items.size(), 2, "inventory should remain intact")

func test_apply_permanent_add_inventory_propagates_same_key() -> void:
	var owner := _add_inventory_owner()
	var coin_template := load(COIN_TOKEN_PATH)
	var coin_a := coin_template.duplicate(true)
	var coin_b := coin_template.duplicate(true)
	coin_a.set("value", 3)
	coin_b.set("value", 5)
	var other := load(COPPER_TOKEN_PATH).duplicate(true)
	other.set("value", 7)
	owner.items = [coin_a, coin_b, other]

	var slot := Control.new()
	slot.set_meta("token_data", coin_a)
	add_child_autofree(slot)
	var ctx := {
		"slot_map": {0: slot}
	}

	coin_manager._apply_permanent_add_inventory("offset", 0, "", "", 2, false, ctx, true)

	assert_eq(coin_a.get("value"), 5, "anchor token should gain the permanent amount")
	assert_eq(coin_b.get("value"), 7, "same-key token should inherit the permanent amount")
	assert_eq(other.get("value"), 7, "unrelated token should stay unchanged")
	assert_eq(ctx["board_tokens"].size(), 3, "context board tokens should refresh inventory snapshot")
	assert_eq(coin_manager._token_value_offsets.get("coin", 0), 2, "per-run offset should track one increment per key")

func test_collect_on_removed_commands_returns_executive_penalty() -> void:
	var exec_token := load(EXECUTIVE_TOKEN_PATH).duplicate(true)
	exec_token.set("value", 4)
	var cmds := coin_manager._collect_on_removed_commands({}, exec_token)
	assert_true(cmds.size() > 0, "executive should emit a removal penalty command")
	var found := false
	for cmd in cmds:
		if typeof(cmd) == TYPE_DICTIONARY and String(cmd.get("op", "")) == "adjust_run_total":
			assert_eq(cmd.get("amount", 0), -20, "penalty amount should be -5x token value")
			found = true
	assert_true(found, "penalty command should be present for executive fallback")
