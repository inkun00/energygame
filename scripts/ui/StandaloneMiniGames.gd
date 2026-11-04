extends CanvasLayer
class_name StandaloneMiniGames

## 웹 링크에서 보드 없이 미니게임을 체험합니다. 결과는 세션 밖에 저장하지 않습니다.

const UI = preload("res://scripts/ui/CommercialUI.gd")
const MINI_GAME_MODAL = preload("res://scenes/MiniGameModal.tscn")
const AVAILABLE_IDS: Array[String] = ["solar_align", "wind_rhythm", "grid_balance", "standby_hunt", "hydro_gate", "energy_sort", "battery_relay", "eco_commute", "heat_leak"]
const PREVIEWS := {
	"solar_align": "햇빛에 맞는 패널로 달려요",
	"wind_rhythm": "발전하다 돌풍에서는 멈춰요",
	"grid_balance": "도시 수요에 전기 공급을 맞춰요",
	"standby_hunt": "쓰지 않는 기기의 전원을 꺼요",
	"hydro_gate": "물을 모아 수문을 열고 닫아요",
	"energy_sort": "금방 다시 얻는 에너지를 나눠요",
	"battery_relay": "남는 전기 저장 → 흐릴 때 공급",
	"eco_commute": "학생을 태우고 학교에 멈춰요",
	"heat_leak": "열린 창문을 닫아 냉방을 지켜요",
}
const KEY_PREVIEWS := {
	"solar_align": "A/D · Space", "wind_rhythm": "A/D · Space",
	"grid_balance": "W/S 또는 ↑/↓", "standby_hunt": "A/D · W · Space",
	"hydro_gate": "A/D · W · Space · E", "energy_sort": "A/D",
	"battery_relay": "A/D", "eco_commute": "D/A · S · Space", "heat_leak": "A/D · Space"
}

var menu: PanelContainer
var modal: MiniGameUI
var current_game_id := ""
var cards_grid: GridContainer
var cards_scroll: ScrollContainer
var card_buttons: Array[Button] = []

func _ready() -> void:
	layer = 20
	_build_menu()
	get_viewport().size_changed.connect(_update_menu_layout)
	_update_menu_layout()
	modal = MINI_GAME_MODAL.instantiate() as MiniGameUI
	modal.standalone_mode = true
	add_child(modal)
	modal.standalone_replay_requested.connect(_replay)
	modal.standalone_menu_requested.connect(_show_menu)
	GameManager.minigame_finished.connect(_on_minigame_finished)
	DisplayServer.window_set_title("에코 히어로즈 · 미니게임 체험")

func open_request(requested_id: String) -> void:
	if requested_id in AVAILABLE_IDS:
		_start_game.call_deferred(requested_id)
	else:
		_show_menu()

func _build_menu() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("071d28")
	add_child(background)
	menu = PanelContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.offset_left = 24
	menu.offset_top = 16
	menu.offset_right = -24
	menu.offset_bottom = -16
	menu.add_theme_stylebox_override("panel", UI.padded_panel(Color("0b2833"), Color("42d6b0"), 16.0, 22))
	add_child(menu)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	menu.add_child(content)
	var eyebrow := Label.new()
	eyebrow.text = "에코 히어로즈 · 30~60초 아케이드"
	eyebrow.add_theme_font_size_override("font_size", 17)
	eyebrow.add_theme_color_override("font_color", Color("8fffe0"))
	content.add_child(eyebrow)
	var heading := Label.new()
	heading.text = "에너지 미니게임 체험"
	heading.add_theme_font_size_override("font_size", 31)
	heading.add_theme_color_override("font_color", Color("fff0a6"))
	content.add_child(heading)
	var intro := Label.new()
	intro.text = "미션을 고르면 P로 조작 연습을 할 수 있어요. 준비되면 나와 AI 3명이 함께 도전해요."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 18)
	intro.add_theme_color_override("font_color", Color("c9e5e1"))
	content.add_child(intro)
	cards_scroll = ScrollContainer.new()
	cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cards_scroll.follow_focus = true
	content.add_child(cards_scroll)
	cards_grid = GridContainer.new()
	cards_grid.name = "GameCards"
	cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_grid.columns = 3
	cards_grid.add_theme_constant_override("h_separation", 14)
	cards_grid.add_theme_constant_override("v_separation", 14)
	cards_scroll.add_child(cards_grid)
	for game_id in AVAILABLE_IDS:
		var definition: Dictionary = GameManager.MINIGAME_DEFINITIONS[game_id]
		var button := Button.new()
		button.name = "Card_" + game_id
		button.custom_minimum_size = Vector2(0, 226)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = str(definition["input_hint"])
		button.set_meta("minigame_id", game_id)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_start_game.bind(game_id))
		button.focus_entered.connect(_on_card_focused.bind(button))
		UI.apply_secondary_button(button, Color(str(definition["accent"])))
		cards_grid.add_child(button)
		card_buttons.append(button)
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 12
		box.offset_top = 10
		box.offset_right = -12
		box.offset_bottom = -10
		box.add_theme_constant_override("separation", 5)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(box)
		var picture := TextureRect.new()
		picture.name = "ScenePreview"
		picture.custom_minimum_size = Vector2(0, 116)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var preview_path := "res://assets/images/minigame_previews/%s.png" % game_id
		if ResourceLoader.exists(preview_path):
			picture.texture = load(preview_path)
		else:
			picture.texture = load("res://assets/images/card_solar_pv.webp")
		box.add_child(picture)
		var title := Label.new()
		title.text = str(definition["title"])
		title.name = "MissionTitle"
		title.add_theme_font_size_override("font_size", 20)
		title.add_theme_color_override("font_color", UI.GOLD)
		title.clip_text = true
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(title)
		var action := Label.new()
		action.name = "MissionAction"
		action.text = PREVIEWS[game_id]
		action.add_theme_font_size_override("font_size", 17)
		action.clip_text = true
		action.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		action.add_theme_color_override("font_color", Color("e4f2eb"))
		action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(action)
		var hint := Label.new()
		hint.text = "%d초 · %s" % [int(definition.get("duration", 30)), KEY_PREVIEWS[game_id]]
		hint.name = "MissionKeys"
		hint.add_theme_font_size_override("font_size", 16)
		hint.add_theme_color_override("font_color", UI.TEXT_MUTED)
		hint.clip_text = true
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(hint)
	var footer := Label.new()
	footer.text = "↑↓←→ 선택 · Enter 시작 · 아래로 스크롤"
	footer.add_theme_font_size_override("font_size", 16)
	footer.add_theme_color_override("font_color", Color("94b8be"))
	content.add_child(footer)

func _update_menu_layout() -> void:
	if not is_instance_valid(cards_grid):
		return
	# canvas_items may keep a 1280-unit logical canvas on a 1024px laptop.
	# Choose the readable card count from the actual window, not that canvas.
	cards_grid.columns = 2 if get_window().size.x < 1150 else 3
	for index in range(card_buttons.size()):
		var button := card_buttons[index]
		button.focus_neighbor_left = card_buttons[maxi(0, index - 1)].get_path()
		button.focus_neighbor_right = card_buttons[mini(card_buttons.size() - 1, index + 1)].get_path()
		button.focus_neighbor_top = card_buttons[maxi(0, index - cards_grid.columns)].get_path()
		button.focus_neighbor_bottom = card_buttons[mini(card_buttons.size() - 1, index + cards_grid.columns)].get_path()
		button.focus_next = card_buttons[(index + 1) % card_buttons.size()].get_path()
		button.focus_previous = card_buttons[posmod(index - 1, card_buttons.size())].get_path()
	_ensure_menu_focus_visible.call_deferred()

func _ensure_menu_focus_visible() -> void:
	# A resize can reflow the focused card without emitting focus_entered again.
	# Wait for the container's new row heights before correcting its scroll.
	await get_tree().process_frame
	if not is_inside_tree() or not menu.visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused in card_buttons:
		cards_scroll.ensure_control_visible(focused)

func _on_card_focused(button: Button) -> void:
	if menu.visible:
		cards_scroll.ensure_control_visible.call_deferred(button)

func _focus_menu_card() -> void:
	if not menu.visible or card_buttons.is_empty():
		return
	var selected := maxi(0, AVAILABLE_IDS.find(current_game_id))
	card_buttons[selected].grab_focus()
	cards_scroll.ensure_control_visible(card_buttons[selected])

func _start_game(game_id: String) -> void:
	if game_id not in AVAILABLE_IDS:
		return
	GameManager.stop_game()
	modal.cancel_minigame()
	current_game_id = game_id
	menu.visible = false
	get_viewport().gui_release_focus()
	var players: Array[Dictionary] = [
		{"name": "캡틴 에코 · 나", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"},
		{"name": "태양 여우 솔", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/solar_fox_sol.webp"},
		{"name": "물방울 포포", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/water_popo.webp"},
		{"name": "바람 토끼 보리", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/wind_rabbit_bori.webp"},
	]
	GameManager.setup_game(players, 600)
	GameManager._start_minigame(0, game_id)

func _on_minigame_finished(_results: Array) -> void:
	# 보드 턴 진행 예약을 취소하되 결과 화면은 재시작할 때까지 유지합니다.
	GameManager.stop_game.call_deferred()

func _replay() -> void:
	if not current_game_id.is_empty():
		_start_game(current_game_id)

func _show_menu() -> void:
	GameManager.stop_game()
	if is_instance_valid(modal):
		modal.cancel_minigame()
	menu.visible = true
	_focus_menu_card.call_deferred()
