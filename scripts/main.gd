extends Control
## V0-M main HUD @ 720×1280 portrait — Idle美术 wireframe + portrait panel skin.

const ICON := "res://assets/ui/idle/icons/"
const MAIN := "res://assets/ui/idle/main/"
const UP := "res://assets/ui/idle/upgrade/"
const OFF := "res://assets/ui/idle/offline/"
const CJK_FONT: FontFile = preload("res://assets/fonts/ui_cjk_subset.otf")
const INK := Color("4A3728")
const INK_MUTED := Color("7A6554")
const PANEL_BG := Color("FFF3E8")

var lbl_ing: Label
var lbl_prod: Label
var lbl_gold: Label
var lbl_prestige: Label
var line_box: VBoxContainer
var upgrade_box: VBoxContainer
var offline_panel: Control
var offline_label: Label
var bar_ing: TextureProgressBar
var bar_prod: TextureProgressBar
var bar_prestige: TextureProgressBar
var _unlock_sig: String = ""
var toast_label: Label
var _ui_root: VBoxContainer
var _ui_pads: Array = []
var _toast_t: float = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_apply_cjk_theme()
	_build_ui()
	_rebuild_stations()
	_rebuild_upgrades()
	var off: Dictionary = GameState.pop_offline_pending()
	if off.get("seconds", 0.0) > 60.0:
		var mins := float(off["seconds"]) / 60.0
		var dur := GameState.ui_fmt("offline_duration_fmt", "离开了 {duration}", {"duration": "%.0f 分钟" % mins})
		var gain := GameState.ui_string("offline_gain_label", "店里多了")
		offline_label.text = "%s\n%s\n茶叶 +%.0f · 杯装 +%.0f · 金币 +%.0f" % [
			dur, gain, off.get("ingredient", 0.0), off.get("product", 0.0), off.get("gold", 0.0)
		]
		offline_panel.visible = true
	else:
		offline_panel.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_content_width_cap()


func _apply_content_width_cap() -> void:
	if _ui_root == null or _ui_pads.is_empty():
		return
	var inner_w := maxf(0.0, size.x - 48.0)
	if inner_w > 720.0:
		_ui_root.custom_minimum_size.x = 720.0
		_ui_root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_ui_root.size_flags_stretch_ratio = 0.0
		_ui_pads[0].size_flags_stretch_ratio = 1.0
		_ui_pads[1].size_flags_stretch_ratio = 1.0
	else:
		_ui_root.custom_minimum_size.x = 0.0
		_ui_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ui_root.size_flags_stretch_ratio = 1.0
		_ui_pads[0].size_flags_stretch_ratio = 0.001
		_ui_pads[1].size_flags_stretch_ratio = 0.001



func _process(delta: float) -> void:
	if lbl_ing == null:
		return
	if toast_label and _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			toast_label.visible = false
	if lbl_prod == null or lbl_gold == null or lbl_prestige == null:
		return
	lbl_ing.text = "%.0f / %.0f   +%.1f/分" % [GameState.ingredient, GameState.ingredient_cap, GameState.ingredient_rate()]
	lbl_prod.text = "%.0f / %.0f   调制 %.2f杯/分" % [GameState.product, GameState.product_cap, GameState.brew_cycles_per_min()]
	lbl_gold.text = "%.0f 金" % GameState.gold
	var gate := GameState.next_prestige_gate()
	lbl_prestige.text = GameState.ui_fmt("prestige_gate_fmt", "{cur} / 下一档 {next}", {"cur": "%.0f" % GameState.prestige, "next": "%.0f" % gate})
	if bar_ing:
		bar_ing.max_value = maxf(GameState.ingredient_cap, 1.0)
		bar_ing.value = GameState.ingredient
	if bar_prod:
		bar_prod.max_value = maxf(GameState.product_cap, 1.0)
		bar_prod.value = GameState.product
	if bar_prestige:
		bar_prestige.max_value = maxf(gate, 1.0)
		bar_prestige.value = GameState.prestige
	var sig := "%s|%s|%s" % [
		GameState.is_unlocked("tea_garden"),
		GameState.is_unlocked("brew_station"),
		GameState.is_unlocked("stall"),
	]
	if sig != _unlock_sig:
		_unlock_sig = sig
		_rebuild_stations()


func _apply_cjk_theme() -> void:
	# Web has no system CJK fallback — must embed glyphs (assets/fonts/README.md).
	var font: FontFile = CJK_FONT
	if font == null:
		font = load("res://assets/fonts/ui_cjk_subset.otf") as FontFile
	if font == null:
		var ff := FontFile.new()
		if ff.load_dynamic_font("res://assets/fonts/ui_cjk_subset.otf") != OK:
			push_warning("CJK font load failed")
			return
		font = ff
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	theme.set_font("font", "Label", font)
	theme.set_font("font", "Button", font)
	theme.set_font_size("font_size", "Label", 16)
	theme.set_font_size("font_size", "Button", 16)
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color("FFF3E8"))
	self.theme = theme


func _show_toast(msg: String) -> void:
	if toast_label == null:
		return
	toast_label.text = msg
	toast_label.visible = true
	_toast_t = 2.2

func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D

func _ink_label(l: Label, size: int = 16, muted: bool = false) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK_MUTED if muted else INK)
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)

func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p

func _build_ui() -> void:
	# Portrait 720×1280: 竖屏主底板（勿叠横版 UI_PANEL_MAIN_temp）
	var page := ColorRect.new()
	page.color = Color("FFFAF5")
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)

	var skin := TextureRect.new()
	skin.texture = _tex(MAIN + "UI_PANEL_MAIN_portrait_temp.png")
	skin.set_anchors_preset(Control.PRESET_FULL_RECT)
	skin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skin.stretch_mode = TextureRect.STRETCH_SCALE
	skin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skin)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 42)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(row)
	var pad_l := Control.new()
	pad_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(pad_l)
	var page_scroll := ScrollContainer.new()
	page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(page_scroll)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.custom_minimum_size = Vector2(0, 0)
	page_scroll.add_child(root)
	var pad_r := Control.new()
	pad_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad_r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(pad_r)
	_ui_root = root
	_ui_pads = [pad_l, pad_r]

	var title := Label.new()
	title.text = GameState.ui_string("title", GameState.content_title())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink_label(title, 26)
	root.add_child(title)

	toast_label = Label.new()
	toast_label.visible = false
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink_label(toast_label, 14)
	toast_label.add_theme_color_override("font_color", Color("3D9B4A"))
	root.add_child(toast_label)

	# Prestige thin bar under title (~10% band with title)
	var pr_wrap := _panel(root)
	var pr_box := VBoxContainer.new()
	pr_box.add_theme_constant_override("separation", 4)
	pr_wrap.add_child(pr_box)
	var pr_row := HBoxContainer.new()
	pr_row.add_theme_constant_override("separation", 8)
	pr_box.add_child(pr_row)
	var pr_name := Label.new()
	pr_name.text = str(GameState.content_resource("prestige").get("name", "声望"))
	_ink_label(pr_name, 14)
	pr_row.add_child(pr_name)
	lbl_prestige = Label.new()
	lbl_prestige.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_prestige.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ink_label(lbl_prestige, 13, true)
	pr_row.add_child(lbl_prestige)
	bar_prestige = TextureProgressBar.new()
	bar_prestige.custom_minimum_size = Vector2(0, 14)
	bar_prestige.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_prestige.texture_under = _tex(MAIN + "UI_BAR_BG_temp.png")
	bar_prestige.texture_progress = _tex(MAIN + "UI_BAR_FILL_PRESTIGE_temp.png")
	bar_prestige.nine_patch_stretch = true
	pr_box.add_child(bar_prestige)

	# Three resource tracks stacked (~18%)
	var tracks := VBoxContainer.new()
	tracks.add_theme_constant_override("separation", 6)
	root.add_child(tracks)
	var t_ing := _make_track(tracks, str(GameState.content_resource("ingredient").get("name", "茶叶")), ICON + "UI_ICON_INGREDIENT_temp.png", MAIN + "UI_BAR_FILL_INGREDIENT_temp.png")
	lbl_ing = t_ing["label"]
	bar_ing = t_ing["bar"]
	var t_prod := _make_track(tracks, str(GameState.content_resource("product").get("name", "杯装奶茶")), ICON + "UI_ICON_PRODUCT_temp.png", MAIN + "UI_BAR_FILL_PRODUCT_temp.png")
	lbl_prod = t_prod["label"]
	bar_prod = t_prod["bar"]
	lbl_gold = _make_gold_track(tracks)

	# Stations vertical (~32%) — each station is its own card
	var line_col := VBoxContainer.new()
	line_col.add_theme_constant_override("separation", 6)
	root.add_child(line_col)
	var lt := Label.new()
	lt.text = GameState.ui_string("line_title", "产线")
	_ink_label(lt, 18)
	line_col.add_child(lt)
	line_box = VBoxContainer.new()
	line_box.add_theme_constant_override("separation", 6)
	line_col.add_child(line_box)

	var sell := Button.new()
	sell.text = GameState.ui_string("sell_all", "卖出全部奶茶")
	sell.custom_minimum_size = Vector2(0, 56)
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_primary_btn(sell, true)
	sell.pressed.connect(_on_sell_pressed)
	root.add_child(sell)
	var hint := Label.new()
	hint.text = str(GameState.content_building("stall").get("short_desc", "自动卖"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ink_label(hint, 12, true)
	root.add_child(hint)

	# Upgrades: live in page scroll so ≥2 cards reachable; keep bottom safe margin
	var up_wrap := _panel(root)
	var up_col := VBoxContainer.new()
	up_col.add_theme_constant_override("separation", 8)
	up_wrap.add_child(up_col)
	var ut := Label.new()
	ut.text = GameState.ui_string("upgrade_title", "升级")
	_ink_label(ut, 18)
	up_col.add_child(ut)
	upgrade_box = VBoxContainer.new()
	upgrade_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_box.add_theme_constant_override("separation", 8)
	up_col.add_child(upgrade_box)

	_build_offline_modal()
	_apply_content_width_cap()


func _make_plus_btn() -> Button:
	var btn := Button.new()
	btn.text = "+"
	btn.custom_minimum_size = Vector2(56, 56)
	btn.size = Vector2(56, 56)
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("E8A0B0")
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", Color("4A3728"))
	btn.pressed.connect(func() -> void: _show_toast(GameState.ui_string("plus_soon", "扩容稍后开放")))
	return btn


func _style_primary_btn(btn: Button, enabled: bool) -> void:
	var btn_sb := StyleBoxFlat.new()
	btn_sb.bg_color = Color("3D9B4A") if enabled else Color("B5A498")
	btn_sb.corner_radius_top_left = 10
	btn_sb.corner_radius_top_right = 10
	btn_sb.corner_radius_bottom_left = 10
	btn_sb.corner_radius_bottom_right = 10
	btn_sb.content_margin_left = 14
	btn_sb.content_margin_right = 14
	btn_sb.content_margin_top = 12
	btn_sb.content_margin_bottom = 12
	if btn.custom_minimum_size.y < 56.0:
		btn.custom_minimum_size.y = 56.0
	btn.add_theme_stylebox_override("normal", btn_sb)
	btn.add_theme_stylebox_override("hover", btn_sb)
	btn.add_theme_stylebox_override("pressed", btn_sb)
	btn.add_theme_stylebox_override("disabled", btn_sb)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color("FFF3E8"))


func _build_offline_modal() -> void:
	offline_panel = Control.new()
	offline_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	offline_panel.visible = false
	offline_panel.z_index = 20
	add_child(offline_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	offline_panel.add_child(dim)
	var modal := PanelContainer.new()
	modal.custom_minimum_size = Vector2(480, 240)
	modal.anchor_left = 0.5
	modal.anchor_top = 0.5
	modal.anchor_right = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = -240
	modal.offset_top = -120
	modal.offset_right = 240
	modal.offset_bottom = 120
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("FFF8F0")
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	modal.add_theme_stylebox_override("panel", sb)
	offline_panel.add_child(modal)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	modal.add_child(inner)
	var ot := Label.new()
	ot.text = GameState.ui_string("offline_title", "店员帮你看店")
	ot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink_label(ot, 24)
	inner.add_child(ot)
	offline_label = Label.new()
	offline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink_label(offline_label, 16)
	inner.add_child(offline_label)
	var claim := Button.new()
	claim.text = GameState.ui_string("offline_claim", "收下")
	claim.custom_minimum_size = Vector2(0, 56)
	claim.pressed.connect(_on_offline_ok)
	inner.add_child(claim)

func _make_track(parent: Control, title: String, icon_path: String, fill_path: String) -> Dictionary:
	var wrap := _panel(parent)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	wrap.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	if icon_path != "":
		var icon := TextureRect.new()
		icon.texture = _tex(icon_path)
		icon.custom_minimum_size = Vector2(48, 48)
		icon.size = Vector2(48, 48)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	var name_l := Label.new()
	name_l.text = title
	_ink_label(name_l, 15)
	row.add_child(name_l)
	var bar := TextureProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.nine_patch_stretch = true
	bar.texture_under = _tex(MAIN + "UI_BAR_BG_temp.png")
	bar.texture_progress = _tex(fill_path)
	bar.custom_minimum_size = Vector2(0, 36)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(bar)
	var lab := Label.new()
	_ink_label(lab, 15)
	box.add_child(lab)
	var plus := _make_plus_btn()
	row.add_child(plus)
	return {"label": lab, "bar": bar}

func _make_gold_track(parent: Control) -> Label:
	var wrap := _panel(parent)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	wrap.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var icon := TextureRect.new()
	icon.texture = _tex(ICON + "UI_ICON_GOLD_temp.png")
	icon.custom_minimum_size = Vector2(48, 48)
	icon.size = Vector2(48, 48)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var name_l := Label.new()
	name_l.text = str(GameState.content_resource("gold").get("name", "金币"))
	_ink_label(name_l, 15)
	row.add_child(name_l)
	var plus := _make_plus_btn()
	row.add_child(plus)
	var lab := Label.new()
	_ink_label(lab, 22)
	box.add_child(lab)
	return lab

func _rebuild_stations() -> void:
	if line_box == null:
		return
	for c in line_box.get_children():
		c.queue_free()
	var icon_map := {
		"tea_garden": ICON + "UI_ICON_STATION_SHELF_temp.png",
		"brew_station": ICON + "UI_ICON_STATION_BREW_temp.png",
		"stall": ICON + "UI_ICON_STATION_STALL_temp.png",
	}
	for b in GameState.get_buildings():
		var id := str(b.get("id", ""))
		if id == "seal":
			continue
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 84)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color("FFF3E8")
		csb.corner_radius_top_left = 14
		csb.corner_radius_top_right = 14
		csb.corner_radius_bottom_left = 14
		csb.corner_radius_bottom_right = 14
		csb.border_width_left = 1
		csb.border_width_top = 1
		csb.border_width_right = 1
		csb.border_width_bottom = 1
		csb.border_color = Color("EDE4D7")
		csb.content_margin_left = 12
		csb.content_margin_right = 12
		csb.content_margin_top = 10
		csb.content_margin_bottom = 10
		card.add_theme_stylebox_override("panel", csb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var icon_slot := Control.new()
		icon_slot.custom_minimum_size = Vector2(64, 64)
		icon_slot.size = Vector2(64, 64)
		icon_slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		icon_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon_slot)
		var icon := TextureRect.new()
		icon.texture = _tex(icon_map.get(id, ICON + "UI_ICON_STATION_SHELF_temp.png"))
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon_slot.add_child(icon)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		var unlocked := GameState.is_unlocked(id)
		var lv := int(GameState.building_levels.get(id, 0))
		var cb: Dictionary = GameState.content_building(id)
		var disp_name := str(cb.get("name", b.get("name", "?")))
		var name_l := Label.new()
		name_l.text = "%s  ·  %s" % [disp_name, GameState.ui_fmt("level_fmt", "Lv{n}", {"n": lv})]
		_ink_label(name_l, 17)
		col.add_child(name_l)
		var short_l := Label.new()
		var short := str(cb.get("short_desc", ""))
		if short == "":
			short = str(cb.get("line_hint", ""))
		short_l.text = short
		_ink_label(short_l, 13, true)
		col.add_child(short_l)
		var st := Label.new()
		if unlocked:
			match id:
				"tea_garden":
					st.text = GameState.ui_fmt("rate_fmt", "+{n}/分", {"n": "%.1f" % GameState.ingredient_rate()})
				"brew_station":
					st.text = GameState.ui_fmt("rate_fmt", "+{n}/分", {"n": "%.2f" % GameState.brew_cycles_per_min()})
				"stall":
					st.text = GameState.ui_fmt("rate_fmt", "+{n}/分", {"n": "%.0f金/杯" % GameState.gold_per_cup})
				_:
					st.text = str(cb.get("line_hint", ""))
		else:
			var need := int(b.get("unlock_prestige", cb.get("unlock_prestige", 0)))
			st.text = GameState.ui_fmt("locked_fmt", "声望{n}", {"n": need})
		_ink_label(st, 13, true)
		col.add_child(st)
		card.modulate = Color(1, 1, 1, 1) if unlocked else Color(1, 1, 1, 0.55)
		line_box.add_child(card)

func _rebuild_upgrades() -> void:
	if upgrade_box == null:
		return
	for c in upgrade_box.get_children():
		c.queue_free()
	for u in GameState.get_upgrades():
		var id := str(u.get("id", ""))
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 76)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("FFF3E8")
		sb.corner_radius_top_left = 14
		sb.corner_radius_top_right = 14
		sb.corner_radius_bottom_left = 14
		sb.corner_radius_bottom_right = 14
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color("EDE4D7")
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		card.add_theme_stylebox_override("panel", sb)
		upgrade_box.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var uc: Dictionary = GameState.content_upgrade_copy(id)
		var name_l := Label.new()
		name_l.text = str(uc.get("name", u.get("name", id)))
		_ink_label(name_l, 16)
		info.add_child(name_l)
		var eff := Label.new()
		var effect := str(uc.get("effect_short", ""))
		if effect == "":
			effect = GameState.ui_fmt("upgrade_effect_fmt", "{effect}", {"effect": str(u.get("name", ""))})
		eff.text = effect
		_ink_label(eff, 12, true)
		info.add_child(eff)
		var pay := Label.new()
		var pb := str(uc.get("payback_short", ""))
		if pb == "":
			pb = GameState.ui_fmt("payback_fmt", "回本~{min}分", {"min": u.get("payback_min_hint", "?")})
		pay.text = "%s · %.0f金" % [pb, float(u.get("cost_gold", 0))]
		_ink_label(pay, 12, true)
		info.add_child(pay)
		var btn := Button.new()
		btn.text = GameState.ui_string("upgrade_btn", "升级")
		btn.custom_minimum_size = Vector2(120, 56)
		btn.size = Vector2(120, 56)
		var cost := float(u.get("cost_gold", 0))
		var can := GameState.gold >= cost
		btn.disabled = not can
		_style_primary_btn(btn, can)
		btn.pressed.connect(_on_upgrade.bind(id))
		row.add_child(btn)

func _on_upgrade(id: String) -> void:
	var gold_before := GameState.gold
	if GameState.try_buy_upgrade(id):
		_rebuild_stations()
		_rebuild_upgrades()
		GameState.save_on_pause()
		_show_toast(GameState.ui_fmt("toast_upgraded", "{name} 升到 Lv{n}", {"name": id, "n": "?"}))
		# refine with building level if upgrade id encodes building_level
		var parts := id.rsplit("_", true, 1)
		if parts.size() == 2:
			var maybe_bid := parts[0]
			var lv_now := int(GameState.building_levels.get(maybe_bid, 0))
			var cb2: Dictionary = GameState.content_building(maybe_bid)
			var nm := str(cb2.get("name", maybe_bid))
			_show_toast(GameState.ui_fmt("toast_upgraded", "{name} 升到 Lv{n}", {"name": nm, "n": lv_now}))
	else:
		_show_toast("升级失败：金币不足或未解锁")

func _on_sell_pressed() -> void:
	var sold := GameState.sell_all_product()
	_rebuild_stations()
	_rebuild_upgrades()
	GameState.save_on_pause()
	if sold <= 0.001:
		_show_toast("暂无杯装可卖 · 等调制台产出")
	else:
		_show_toast(GameState.ui_fmt("toast_sold", "卖掉了 {n} 杯", {"n": "%.1f" % sold}))

func _on_offline_ok() -> void:
	offline_panel.visible = false
	GameState.save_on_pause()
