extends Node
## Autoload: tick, offline settle, JSON save, table-driven. Web: user:// → IndexedDB.

const SAVE_PATH := "user://save.json"
const SEC_PER_MIN := 60.0
const OFFLINE_FACTOR := 0.7
const ING_PER_CUP := 10.0

var ingredient: float = 20.0
var product: float = 0.0
var gold: float = 50.0
var prestige: float = 0.0
var ingredient_cap: float = 120.0
var product_cap: float = 60.0
var prestige_next_unlock: float = 40.0
var last_logout_unix: float = 0.0
var building_levels: Dictionary = {"tea_garden": 0, "brew_station": 0, "stall": 0}
var gold_per_cup: float = 8.0
var tea_bonus_per_min: float = 0.0

var _buildings: Array = []
var _upgrades: Array = []
var _content: Dictionary = {}
var _offline_pending: Dictionary = {}

func _ready() -> void:
	_load_tables()
	load_game()
	var offline := settle_offline()
	if offline.get("seconds", 0.0) > 60.0:
		_offline_pending = offline
	set_process(true)

func _process(delta: float) -> void:
	_tick(delta)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST \
		or what == NOTIFICATION_APPLICATION_PAUSED \
		or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		save_on_pause()

func save_on_pause() -> void:
	save_game()
	_flush_web_fs()

func _flush_web_fs() -> void:
	# Web: hide/refresh won't run another frame — flush user:// into IndexedDB now.
	if not OS.has_feature("web"):
		return
	if not ClassDB.class_exists("JavaScriptBridge"):
		return
	JavaScriptBridge.eval("FS.syncfs(false, function(err) {})", true)

func _load_tables() -> void:
	_content = _read_json("res://data/content.json")
	var bdoc := _read_json("res://data/buildings.json")
	_buildings = bdoc.get("buildings", [])
	# V0: only three stations
	var keep := ["tea_garden", "brew_station", "stall"]
	var filtered: Array = []
	for b in _buildings:
		if str(b.get("id", "")) in keep:
			filtered.append(b)
	_buildings = filtered
	for b in _buildings:
		var id := str(b.get("id", ""))
		if id == "tea_garden":
			ingredient_cap = float(b.get("base_cap", b.get("hard_cap", 120)))
		elif id == "brew_station":
			product_cap = float(b.get("base_cap", 60))
		elif id == "stall":
			gold_per_cup = float(b.get("ratio_out", 8))
	_upgrades = _read_json("res://data/upgrades.json").get("upgrades", [])
	var res: Dictionary = _read_json("res://data/resources.json")
	if res.has("ingredient"):
		ingredient_cap = float(res["ingredient"].get("hard_cap", ingredient_cap))
		if not FileAccess.file_exists(SAVE_PATH):
			ingredient = float(res["ingredient"].get("start", ingredient))
	if res.has("product"):
		product_cap = float(res["product"].get("hard_cap", product_cap))
	if res.has("gold") and not FileAccess.file_exists(SAVE_PATH):
		gold = float(res["gold"].get("start", gold))
	if res.has("prestige"):
		prestige_next_unlock = float(res["prestige"].get("next_unlock", 40))

func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("missing table: %s" % path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if typeof(data) == TYPE_DICTIONARY else {}

func is_unlocked(building_id: String) -> bool:
	for b in _buildings:
		if str(b.get("id", "")) == building_id:
			return prestige >= float(b.get("unlock_prestige", 0))
	return false

func ingredient_rate() -> float:
	if not is_unlocked("tea_garden"):
		return 0.0
	var base := 10.0
	for b in _buildings:
		if str(b.get("id", "")) == "tea_garden":
			base = float(b.get("base_rate_per_min", 10))
			break
	var lv := int(building_levels.get("tea_garden", 0))
	return base + float(lv) * 5.0 + tea_bonus_per_min

func brew_cycles_per_min() -> float:
	if not is_unlocked("brew_station"):
		return 0.0
	var base := 1.0
	for b in _buildings:
		if str(b.get("id", "")) == "brew_station":
			base = float(b.get("base_cycles_per_min", 1.0))
			break
	var lv := int(building_levels.get("brew_station", 0))
	return base + float(lv) * 0.25

func _tick(delta: float) -> void:
	var mins := delta / SEC_PER_MIN
	ingredient = minf(ingredient_cap, ingredient + ingredient_rate() * mins)
	var cycles := brew_cycles_per_min() * mins
	var can_make := minf(cycles, ingredient / ING_PER_CUP)
	can_make = minf(can_make, product_cap - product)
	if can_make > 0.0:
		ingredient -= can_make * ING_PER_CUP
		product += can_make
	if is_unlocked("stall") and product > 0.0:
		_sell_amount(product)

func _sell_amount(amount: float) -> void:
	if amount <= 0.0:
		return
	product -= amount
	gold += amount * gold_per_cup
	prestige += amount

func sell_all_product() -> float:
	var amt := product
	_sell_amount(amt)
	return amt

func try_buy_upgrade(id: String) -> bool:
	for u in _upgrades:
		if str(u.get("id", "")) != id:
			continue
		# Level chain upgrades
		if u.has("building_id"):
			var bid := str(u.get("building_id", ""))
			var to_lv := int(u.get("to_level", 0))
			var cur := int(building_levels.get(bid, 0))
			if cur >= to_lv or to_lv != cur + 1:
				return false
			if not is_unlocked(bid):
				return false
			var cost := float(u.get("cost_gold", 0))
			if gold < cost:
				return false
			gold -= cost
			building_levels[bid] = to_lv
			if bid == "stall":
				gold_per_cup = 8.0 + float(to_lv)
			return true
		# Flat effect upgrades (tea_up / waste_down / speed_up placeholders)
		var cost2 := float(u.get("cost_gold", 0))
		if gold < cost2:
			return false
		if str(u.get("id", "")) == "tea_up" or str(u.get("id", "")) == "output_up":
			gold -= cost2
			tea_bonus_per_min += float(u.get("effect", {}).get("ingredient_per_min", u.get("delta_ingredient_per_min", 5)))
			return true
		# Unknown flat upgrade: still charge + no-op effect reserved
		gold -= cost2
		return true
	return false

func settle_offline() -> Dictionary:
	if last_logout_unix <= 0.0:
		last_logout_unix = Time.get_unix_time_from_system()
		return {}
	var now := Time.get_unix_time_from_system()
	var seconds: float = maxf(0.0, now - last_logout_unix)
	var mins := seconds / SEC_PER_MIN * OFFLINE_FACTOR
	var d_ing := ingredient_rate() * mins
	ingredient = minf(ingredient_cap, ingredient + d_ing)
	var d_prod := brew_cycles_per_min() * mins
	d_prod = minf(d_prod, ingredient / ING_PER_CUP)
	d_prod = minf(d_prod, product_cap - product)
	ingredient -= d_prod * ING_PER_CUP
	product += d_prod
	var d_gold := 0.0
	if is_unlocked("stall") and product > 0.0:
		d_gold = product * gold_per_cup
		prestige += product
		product = 0.0
		gold += d_gold
	last_logout_unix = now
	return {"seconds": seconds, "ingredient": d_ing, "product": d_prod, "gold": d_gold}

func pop_offline_pending() -> Dictionary:
	var d := _offline_pending.duplicate()
	_offline_pending.clear()
	return d

func save_game() -> void:
	last_logout_unix = Time.get_unix_time_from_system()
	var payload := {
		"ingredient": ingredient,
		"product": product,
		"gold": gold,
		"prestige": prestige,
		"last_logout_at": last_logout_unix,
		"building_levels": building_levels,
		"gold_per_cup": gold_per_cup,
		"tea_bonus_per_min": tea_bonus_per_min,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		last_logout_unix = Time.get_unix_time_from_system()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	ingredient = float(data.get("ingredient", ingredient))
	product = float(data.get("product", product))
	gold = float(data.get("gold", gold))
	prestige = float(data.get("prestige", prestige))
	last_logout_unix = float(data.get("last_logout_at", 0.0))
	gold_per_cup = float(data.get("gold_per_cup", gold_per_cup))
	tea_bonus_per_min = float(data.get("tea_bonus_per_min", 0.0))
	var bl = data.get("building_levels", {})
	if typeof(bl) == TYPE_DICTIONARY:
		building_levels = bl

func get_upgrades() -> Array:
	# Next level only; hide upgrades for locked buildings (avoids dead clicks)
	var shown: Array = []
	var seen_next := {}
	for u in _upgrades:
		var bid := str(u.get("building_id", ""))
		if bid == "":
			shown.append(u)
			continue
		if not is_unlocked(bid):
			continue
		var to_lv := int(u.get("to_level", 0))
		var cur := int(building_levels.get(bid, 0))
		if to_lv == cur + 1 and not seen_next.has(bid):
			shown.append(u)
			seen_next[bid] = true
	return shown


func get_buildings() -> Array:
	return _buildings

func next_prestige_gate() -> float:
	for b in _buildings:
		var need := float(b.get("unlock_prestige", 0))
		if prestige < need:
			return need
	return prestige_next_unlock

func content_title() -> String:
	return str(_content.get("theme_title", "奶茶王国"))

func ui_string(key: String, fallback: String = "") -> String:
	var us = _content.get("ui_strings", {})
	if typeof(us) == TYPE_DICTIONARY and us.has(key):
		return str(us[key])
	return fallback if fallback != "" else key

func ui_fmt(key: String, fallback: String, replacements: Dictionary) -> String:
	var s := ui_string(key, fallback)
	for k in replacements:
		s = s.replace("{%s}" % str(k), str(replacements[k]))
	return s

func content_building(id: String) -> Dictionary:
	var arr = _content.get("buildings", [])
	if typeof(arr) != TYPE_ARRAY:
		return {}
	for b in arr:
		if str(b.get("id", "")) == id:
			return b
	return {}

func content_resource(key: String) -> Dictionary:
	var arr = _content.get("resources", [])
	if typeof(arr) != TYPE_ARRAY:
		return {}
	for r in arr:
		if str(r.get("key", "")) == key:
			return r
	return {}

func content_upgrade_copy(id: String) -> Dictionary:
	var arr = _content.get("upgrade_copy", [])
	if typeof(arr) != TYPE_ARRAY:
		return {}
	for u in arr:
		if str(u.get("id", "")) == id:
			return u
	return {}

