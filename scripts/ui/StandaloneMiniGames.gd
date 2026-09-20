extends CanvasLayer
class_name StandaloneMiniGames

## 웹 링크에서 보드 없이 구현된 미니게임만 반복 체험하는 선택 화면입니다.

const UI = preload("res://scripts/ui/CommercialUI.gd")
const MINI_GAME_MODAL = preload("res://scenes/MiniGameModal.tscn")
const AVAILABLE_IDS: Array[String] = ["solar_align", "wind_rhythm", "grid_balance", "standby_hunt", "hydro_gate", "energy_sort", "battery_relay", "eco_commute", "heat_leak"]
const PREVIEWS := {
	"solar_align": "햇빛 방향을 읽고 올바른 패널 경로로 달리기",
	"wind_rhythm": "풍향에 맞춰 발전하고 위험 돌풍에서 멈추기",
	"grid_balance": "변하는 전력 수요와 공급을 계속 맞추기",
	"standby_hunt": "집 안을 달리며 낭비되는 대기전력 차단하기",
	"hydro_gate": "비 예보를 보며 수문까지 달려가 열고 닫기",
	"energy_sort": "햇빛·바람·물과 땅속 연료를 두 곳으로 배송하기",
	"battery_relay": "햇빛에 남은 전기를 저장하고 흐릴 때 도시에 보내기",
	"eco_commute": "직접 운전해 학생을 태우고 학교에 정확히 정차하기",
	"heat_leak": "여름 교실의 열린 창문을 닫아 에어컨 효율 높이기",
}

var menu: PanelContainer
var modal: MiniGameUI
var current_game_id := ""

func _ready() -> void:
	layer = 20
	_build_menu()
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
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.offset_left = -475
	menu.offset_top = -310
	menu.offset_right = 475
	menu.offset_bottom = 310
	menu.add_theme_stylebox_override("panel", UI.padded_panel(Color("0b2833"), Color("42d6b0"), 28.0, 22))
	add_child(menu)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 15)
	menu.add_child(content)
	var eyebrow := Label.new()
	eyebrow.text = "에코 히어로즈 · 30~60초 아케이드"
	eyebrow.add_theme_font_size_override("font_size", 17)
	eyebrow.add_theme_color_override("font_color", Color("8fffe0"))
	content.add_child(eyebrow)
	var heading := Label.new()
	heading.text = "에너지 미니게임 체험"
	heading.add_theme_font_size_override("font_size", 39)
	heading.add_theme_color_override("font_color", Color("fff0a6"))
	content.add_child(heading)
	var intro := Label.new()
	intro.text = "게임을 고르면 바로 시작합니다. 나와 AI 세 명이 동시에 도전하며, 종료 후 언제든 다시 플레이할 수 있어요."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 17)
	intro.add_theme_color_override("font_color", Color("c9e5e1"))
	content.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for game_id in AVAILABLE_IDS:
		var definition: Dictionary = GameManager.MINIGAME_DEFINITIONS[game_id]
		var button := Button.new()
		button.text = "%s\n%s" % [definition["title"], PREVIEWS[game_id]]
		button.custom_minimum_size = Vector2(430, 64)
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_start_game.bind(game_id))
		UI.apply_secondary_button(button, Color(str(definition["accent"])))
		grid.add_child(button)
	var footer := Label.new()
	footer.text = "키보드로 조작 · 노트북/PC 권장 · 새로고침 후에도 이 링크에서 다시 플레이 가능"
	footer.add_theme_font_size_override("font_size", 15)
	footer.add_theme_color_override("font_color", Color("94b8be"))
	content.add_child(footer)

func _start_game(game_id: String) -> void:
	if game_id not in AVAILABLE_IDS:
		return
	GameManager.stop_game()
	modal.cancel_minigame()
	current_game_id = game_id
	menu.visible = false
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
