extends FlightDeckTest

func test_ui_strings_present() -> void:
	assert_true(GameState.ui_string("sell_all", "") != "", "sell_all")
	assert_true(GameState.ui_string("upgrade_btn", "") != "", "upgrade_btn")
	var stall := GameState.content_building("stall")
	assert_true(str(stall.get("unlock_copy", "")) != "", "stall unlock_copy")
	assert_true(str(stall.get("short_desc", "")) != "", "stall short_desc")
	assert_equal(GameState.content_title(), "奶茶王国")
