extends SceneTree
# Headless smoke: load GameState via autoload when run as main? Use --script instead.
func _init() -> void:
	print("SMOKE_START")
	quit()
