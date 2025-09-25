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

func test_collect_on_removed_commands_destroys_coins_for_executive() -> void:
	var coin_template := load(COIN_TOKEN_PATH)
	var coin_a := coin_template.duplicate(true)
	var coin_b := coin_template.duplicate(true)
	var coin_c := coin_template.duplicate(true)
	var owner := _add_inventory_owner([coin_a, coin_b, coin_c])

	var slot_a := Control.new()
	slot_a.set_meta("token_data", coin_a)
	add_child_autofree(slot_a)
	var slot_b := Control.new()
	slot_b.set_meta("token_data", coin_b)
	add_child_autofree(slot_b)
	var slot_c := Control.new()
	slot_c.set_meta("token_data", coin_c)
	add_child_autofree(slot_c)

	var ctx := {
		"slot_map": {0: slot_a, 1: slot_b, 2: slot_c}
	}

	var exec_token := load(EXECUTIVE_TOKEN_PATH).duplicate(true)
	var cmds := coin_manager._collect_on_removed_commands(ctx, exec_token)
	assert_eq(cmds.size(), 0, "executive fallback should not emit extra commands")
	assert_true(coin_manager._is_empty_token(owner.items[0]), "first coin should be replaced with an empty")
	assert_true(coin_manager._is_empty_token(owner.items[1]), "second coin should be replaced with an empty")
	assert_true(coin_manager._token_has_tag(owner.items[2], "coin"), "third coin should remain intact")
	assert_true(ctx.has("board_tokens"), "context should capture refreshed board tokens")
	var empties := 0
	for token in ctx["board_tokens"]:
		if coin_manager._is_empty_token(token):
			empties += 1
	assert_eq(empties, 2, "two empties should be present after destruction")

func test_resync_permanent_add_updates_triggered_coin() -> void:
	var coin_template := load(COIN_TOKEN_PATH)
	var coin := coin_template.duplicate(true)
	coin.set("value", 2)
	var owner := _add_inventory_owner([coin])

	var slot := Control.new()
	slot.set_meta("token_data", coin)
	add_child_autofree(slot)

	var contrib := {
		"offset": 0,
		"token": coin,
		"base": 2,
		"delta": 0,
		"mult": 1.0,
		"steps": [],
		"meta": {}
	}
	var contribs := [contrib]
	var ctx := {
		"slot_map": {0: slot}
	}

	coin_manager._apply_permanent_add_inventory("tag", 0, "coin", "", -1, false, ctx, false)
	coin_manager._resync_contribs_from_board(ctx, contribs)

	assert_eq(contrib["base"], 1, "coin base should drop by 1 after permanent add")
	assert_eq(coin_manager._compute_value(contrib), 1, "triggered coin value should reflect updated base")
	assert_true(contrib.has("steps") and contrib["steps"] is Array and !contrib["steps"].is_empty(), "resync should log a replacement/value step")
	assert_true(ctx.has("board_tokens"), "context should refresh board snapshot after permanent add")
	assert_eq(owner.items[0].get("value"), 1, "inventory coin should match updated value")
