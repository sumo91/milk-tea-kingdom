extends FlightDeckTest

const MainHud = preload("res://scripts/main.gd")


func test_iphone_portrait_fills_and_scales_up() -> void:
	# Lando's phone: logical viewport width ≥1170 must not letterbox a 720 column.
	for pixels in [Vector2(1170, 2532), Vector2(1179, 2556), Vector2(1284, 2778), Vector2(1080, 1920)]:
		assert_false(MainHud.should_cap_content_width(pixels), "portrait %s" % pixels)
		var scale := float(MainHud.portrait_upscale(pixels))
		assert_greater(scale, 1.0, "upscale %s" % pixels)
		assert_approx(scale, pixels.x / MainHud.DESIGN_W, 0.001, "width-limited %s" % pixels)


func test_narrow_portrait_stays_one_to_one() -> void:
	# 500×900 and the 720×1280 design window must not downscale hotzones.
	assert_false(MainHud.should_cap_content_width(Vector2(500, 900)))
	assert_equal(MainHud.portrait_upscale(Vector2(500, 900)), 1.0)
	assert_false(MainHud.should_cap_content_width(Vector2(720, 1280)))
	assert_equal(MainHud.portrait_upscale(Vector2(720, 1280)), 1.0)
	# Wider than 720 but too short to upscale without shrinking the 56px targets.
	assert_false(MainHud.should_cap_content_width(Vector2(800, 900)))
	assert_equal(MainHud.portrait_upscale(Vector2(800, 900)), 1.0)


func test_landscape_and_wide_desktop_keep_720_column() -> void:
	assert_true(MainHud.should_cap_content_width(Vector2(1920, 1080)))
	assert_equal(MainHud.portrait_upscale(Vector2(1920, 1080)), 1.0)
	assert_true(MainHud.should_cap_content_width(Vector2(1280, 800)))
	assert_equal(MainHud.portrait_upscale(Vector2(2560, 1440)), 1.0)
	# Landscape that is not wider than the column still fills.
	assert_false(MainHud.should_cap_content_width(Vector2(700, 400)))
	assert_equal(MainHud.portrait_upscale(Vector2(700, 400)), 1.0)
