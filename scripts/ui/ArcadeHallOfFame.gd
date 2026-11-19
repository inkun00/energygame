extends PanelContainer

signal back_requested
signal challenge_requested(game_id: String)

const UI = preload("res://scripts/ui/CommercialUI.gd")
var game_ids: Array[String] = []
var selected_game := ""
@onready var selector := OptionButton.new()
@onready var columns := BoxContainer.new()
@onready var poster := TextureRect.new()
@onready var event_name := Label.new()
@onready var best := Label.new()
@onready var player_alias := Label.new()
@onready var scope_label := Label.new()
@onready var rows := VBoxContainer.new()
@onready var challenge := Button.new()
@onready var back := Button.new()
@onready var scroll := ScrollContainer.new()

class Trophy extends Control:
	func _draw() -> void:
		var center := Vector2(size.x * 0.5, 44)
		var gold := Color("ffdb76")
		var shade := Color("df9a45")
		draw_circle(center, 42, Color("163e49"), true, -1, true)
		for side in [-1, 1]:
			var handle := center + Vector2(17 * side, -9)
			draw_arc(handle, 9, 0, TAU, 24, shade, 3.5, true)
		var cup := PackedVector2Array([Vector2(-18,-19), Vector2(18,-19), Vector2(15,-4), Vector2(9,3), Vector2(2,7), Vector2(2,17), Vector2(12,19), Vector2(12,22), Vector2(-12,22), Vector2(-12,19), Vector2(-2,17), Vector2(-2,7), Vector2(-9,3), Vector2(-15,-4)])
		for i in range(cup.size()):
			cup[i] += center
		draw_colored_polygon(cup, gold)
		draw_line(center + Vector2(-11,-14), center + Vector2(-9,-6), Color("fff3bf"), 3, true)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", UI.padded_panel(Color("0a2230"), Color("20485a"), 24, 0))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := Label.new()
	title.text = "명예의 전당"
	_style_text(title, 35, UI.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	back.text = "종목 선택으로"
	UI.apply_secondary_button(back)
	back.custom_minimum_size = Vector2(134, 54)
	back.pressed.connect(func(): back_requested.emit())
	header.add_child(back)
	selector.custom_minimum_size.y = 50
	selector.add_theme_font_size_override("font_size", 22)
	selector.get_popup().add_theme_font_size_override("font_size", 22)
	selector.get_popup().add_theme_constant_override("v_separation", 14)
	UI.apply_secondary_button(selector, UI.TEAL)
	selector.item_selected.connect(func(index: int): _select_game(game_ids[index]))
	body.add_child(selector)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	body.add_child(columns)
	var poster_panel := PanelContainer.new()
	poster_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	poster_panel.add_theme_stylebox_override("panel", UI.padded_panel(Color("103342"), Color("497d83"), 16, 14))
	columns.add_child(poster_panel)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	poster_panel.add_child(details)
	poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	poster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(poster)
	_style_text(event_name, 25, Color.WHITE)
	details.add_child(event_name)
	_style_text(best, 22, UI.GOLD)
	details.add_child(best)
	_style_text(player_alias, 18, Color("bddbd8"))
	player_alias.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(player_alias)
	challenge.text = "이 종목에 도전"
	challenge.custom_minimum_size.y = 52
	UI.apply_primary_button(challenge)
	challenge.pressed.connect(func(): challenge_requested.emit(selected_game))
	details.add_child(challenge)
	var leaderboard := PanelContainer.new()
	leaderboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leaderboard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	leaderboard.size_flags_stretch_ratio = 1.35
	leaderboard.add_theme_stylebox_override("panel", UI.padded_panel(Color("0a2937"), Color("365968"), 16, 14))
	columns.add_child(leaderboard)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	leaderboard.add_child(list)
	var list_header := HBoxContainer.new()
	list.add_child(list_header)
	_style_text(scope_label, 21, UI.TEAL)
	scope_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list_header.add_child(scope_label)
	var refresh := Button.new()
	refresh.text = "새로고침"
	refresh.custom_minimum_size.y = 44
	UI.apply_secondary_button(refresh)
	refresh.pressed.connect(func(): MiniGameRecords.fetch_board(selected_game))
	list_header.add_child(refresh)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	list.add_child(scroll)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 5)
	scroll.add_child(rows)
	MiniGameRecords.records_changed.connect(_render)
	resized.connect(_reflow)
	_reflow()

func _style_text(label: Label, points: int, color: Color) -> void:
	label.add_theme_font_size_override("font_size", points)
	label.add_theme_color_override("font_color", color)

func _reflow() -> void:
	columns.vertical = size.y > size.x
	poster.custom_minimum_size.y = 140 if columns.vertical else 154
	selector.custom_minimum_size.y = 60 if columns.vertical else 50
	challenge.custom_minimum_size.y = 60 if columns.vertical else 52
	back.custom_minimum_size.y = 60 if columns.vertical else 54

func open(ids: Array[String], requested: String, from_result: bool) -> void:
	if game_ids.is_empty():
		game_ids.assign(ids)
		for id in ids:
			selector.add_item(str(GameManager.MINIGAME_DEFINITIONS[id].title))
	back.text = "결과로 돌아가기" if from_result else "종목 선택으로"
	show()
	_select_game(requested if requested in ids else ids[0])
	selector.grab_focus()

func _select_game(id: String) -> void:
	selected_game = id
	selector.select(game_ids.find(id))
	event_name.text = str(GameManager.MINIGAME_DEFINITIONS[id].title)
	poster.texture = load("res://assets/images/minigame_previews/%s.png" % id)
	scroll.scroll_vertical = 0
	_render(id, MiniGameRecords.get_board(id))
	MiniGameRecords.fetch_board(id)

func _render(id: String, state: Dictionary) -> void:
	if id != selected_game or not visible:
		return
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var shared: bool = state.get("scope", "device") == "shared"
	var loading: bool = state.get("status", "") == "loading"
	var rank_value := int(state.get("personal_rank", 0))
	var record := int(state.get("personal_best", -1))
	var entries: Array = state.get("entries", [])
	var has_record := bool(state.get("has_personal_best", rank_value > 0 or record > 0))
	best.text = "내 최고  %d점" % maxi(0, record) if has_record else "첫 기록에 도전해요"
	player_alias.text = str(state.get("alias", ""))
	if rank_value > 0 and shared:
		player_alias.text += "  ·  전체 %d위" % rank_value
		if record > int(state.get("shared_best", record)):
			player_alias.text += " (%d점)" % int(state.shared_best)
	scope_label.text = "전체 순위  ·  상위 10명" if shared else "이 기기에 저장한 기록"
	if loading:
		scope_label.text += "  ·  순위 확인 중"
	elif not shared:
		scope_label.text += "  ·  오프라인"
	if entries.is_empty():
		var emblem := Trophy.new()
		emblem.custom_minimum_size.y = 93
		emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(emblem)
		var empty := Label.new()
		empty.text = "순위를 불러오는 중이에요…" if loading else "아직 기록이 없어요.\n한 판을 끝내고 첫 기록을 남겨 보세요!"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_style_text(empty, 20, Color("d0e1de"))
		rows.add_child(empty)
	for item in entries:
		_add_entry(item)

func _add_entry(item: Dictionary) -> void:
	var place := int(item.rank)
	var mine := bool(item.get("mine", false))
	var strip := PanelContainer.new()
	var ink := UI.GOLD if place == 1 else (Color("c9dfed") if place == 2 else (Color("edb38d") if place == 3 else UI.TEAL))
	strip.add_theme_stylebox_override("panel", UI.padded_panel(Color("174b4c") if mine else Color("102f3e"), ink if mine else Color("234757"), 7, 8))
	rows.add_child(strip)
	var line := HBoxContainer.new()
	strip.add_child(line)
	var badge := Label.new()
	badge.custom_minimum_size.x = 54
	badge.text = "%d위" % place
	_style_text(badge, 20, ink)
	line.add_child(badge)
	var who := Label.new()
	who.text = str(item.alias) + ("  ·  나" if mine else "")
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_style_text(who, 19, Color.WHITE)
	line.add_child(who)
	var value := Label.new()
	value.text = "%d점" % int(item.score)
	_style_text(value, 22, ink)
	line.add_child(value)
