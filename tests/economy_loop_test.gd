extends FlightDeckTest

func test_buy_brew_and_sell() -> void:
	GameState.gold = 50.0
	GameState.product = 0.0
	GameState.prestige = 0.0
	GameState.building_levels = {"tea_garden": 0, "brew_station": 0, "stall": 0}
	var ok := GameState.try_buy_upgrade("brew_station_1")
	assert_true(ok, "brew_station_1 should buy")
	assert_equal(int(GameState.building_levels["brew_station"]), 1)
	assert_true(GameState.gold < 50.0, "gold spent")
	GameState.product = 5.0
	var sold := GameState.sell_all_product()
	assert_true(sold > 4.9, "sold cups")
	assert_true(GameState.product < 0.01, "cups cleared")
	assert_true(GameState.gold > 0.0, "gold gained")
	# V0-Q: stall unlock_prestige 0 → auto-sell open; buying stall_1 should work with gold
	GameState.gold = 100.0
	var stall_ok := GameState.try_buy_upgrade("stall_1")
	assert_true(stall_ok, "stall_1 buyable when unlock_prestige 0")
	assert_true(GameState.is_unlocked("stall"), "stall unlocked at prestige 0")
