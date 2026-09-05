extends Control
class_name LobbyUI

## Commercial-style title screen and four-player game setup.

signal start_game_requested(player_configs, duration_seconds)

const UI = preload("res://scripts/ui/CommercialUI.gd")

@onready var nickname_edit: LineEdit = $MenuPanel/Content/NicknameEdit
@onready var char_option_button: OptionButton = $MenuPanel/Content/CharOptionButton
@onready var character_strip: HBoxContainer = $MenuPanel/Content/CharacterStrip/Characters
@onready var mode_option_button: OptionButton = $MenuPanel/Content/ModeOptionButton
@onready var game_time_option_button: OptionButton = $MenuPanel/Content/GameTimeRow/GameTimeOptionButton
@onready var online_box: VBoxContainer = $MenuPanel/Content/OnlineBox
@onready var host_button: Button = $MenuPanel/Content/OnlineBox/NetworkButtons/HostButton
@onready var join_button: Button = $MenuPanel/Content/OnlineBox/NetworkButtons/JoinButton
@onready var local_start_button: Button = $MenuPanel/Content/LocalStartButton
@onready var ip_edit: LineEdit = $MenuPanel/Content/OnlineBox/IPEdit
@onready var status_label: Label = $MenuPanel/Content/StatusLabel
@onready var hero_portrait: TextureRect = $HeroPortrait
@onready var hero_glow: Panel = $HeroGlow
@onready var character_name_label: Label = $HeroBadge/Margin/VBox/CharacterName
@onready var character_role_label: Label = $HeroBadge/Margin/VBox/CharacterRole
@onready var skill_name_label: Label = $HeroBadge/Margin/VBox/SkillName
@onready var skill_description_label: Label = $HeroBadge/Margin/VBox/SkillDescription
@onready var logo_container: Control = $LogoContainer
@onready var menu_panel: Control = $MenuPanel
@onready var hero_badge: PanelContainer = $HeroBadge
@onready var help_button: Button = $TopBar/TopActions/HelpButton
@onready var sound_button: Button = $TopBar/TopActions/SoundButton
@onready var opening_story: Control = $OpeningStoryOverlay
@onready var opening_image: TextureRect = $OpeningStoryOverlay/StoryImage
@onready var opening_caption: Label = $OpeningStoryOverlay/CaptionPanel/Caption
@onready var opening_step_label: Label = $OpeningStoryOverlay/StepLabel
@onready var opening_skip_button: Button = $OpeningStoryOverlay/SkipButton

var characters: Array[Dictionary] = [
	{"name": "캡틴 에코", "icon": "res://assets/characters/eco_roster/captain_eco.webp", "color": Color(0.28, 0.90, 0.34), "role": "자연의 힘으로 도시를 회복하는 밸런스형 히어로"},
	{"name": "물방울 정령 포포", "icon": "res://assets/characters/eco_roster/water_popo.webp", "color": Color(0.20, 0.72, 0.96), "role": "깨끗한 물의 힘으로 오염을 씻어 내는 회복형 히어로"},
	{"name": "에코 베어 퐁이", "icon": "res://assets/characters/eco_roster/bear_pongi.webp", "color": Color(0.30, 0.92, 0.82), "role": "튼튼한 장비와 보호막으로 모두를 지키는 방어형 히어로"},
	{"name": "태양 여우 솔", "icon": "res://assets/characters/eco_roster/solar_fox_sol.webp", "color": Color(1.00, 0.58, 0.12), "role": "태양광 장비로 에너지를 충전하는 기술형 히어로"},
	{"name": "바람 토끼 보리", "icon": "res://assets/characters/eco_roster/wind_rabbit_bori.webp", "color": Color(0.22, 0.82, 0.92), "role": "바람보다 빠르게 길을 개척하는 기동형 히어로"},
	{"name": "재활용 너구리 링고", "icon": "res://assets/characters/eco_roster/recycle_raccoon_ringo.webp", "color": Color(0.36, 0.82, 0.28), "role": "버려진 자원을 멋진 도구로 바꾸는 발명형 히어로"},
	{"name": "대지 거북 토리", "icon": "res://assets/characters/eco_roster/earth_turtle_tori.webp", "color": Color(0.60, 0.72, 0.20), "role": "대지의 방패로 위험을 막아 내는 수호형 히어로"},
	{"name": "번개새 피카", "icon": "res://assets/characters/eco_roster/lightning_bird_pika.webp", "color": Color(1.00, 0.82, 0.10), "role": "깨끗한 전기를 다루는 초고속 정찰형 히어로"},
	{"name": "버섯 고양이 모모", "icon": "res://assets/characters/eco_roster/mushroom_cat_momo.webp", "color": Color(0.96, 0.30, 0.22), "role": "숲의 생명 에너지를 연구하는 연금술형 히어로"}
]

var _character_buttons: Array[Button] = []
var _room_popup: Control
var _room_cards: HBoxContainer
var _room_code_label: Label
var _room_count_label: Label
var _room_status_label: Label
var _room_start_button: Button
var _room_browser: Control

var _hero_base_y := 178.0
var _intro_finished := false
var _sound_enabled := true
var _opening_step := 0
var _opening_sequence := 0
var _pending_player_configs: Array[Dictionary] = []
var _pending_game_duration_seconds := GameManager.DEFAULT_GAME_DURATION_SECONDS
var _is_finishing_opening := false

const OPENING_IMAGES := [
	preload("res://assets/story/opening/01_energy_waste.webp"),
	preload("res://assets/story/opening/02_fossil_fuel.webp"),
	preload("res://assets/story/opening/03_crisis.webp"),
	preload("res://assets/story/opening/04_renewable_plan.webp")
]

const OPENING_STORY := [
	{"caption": "에너지요정 나라는 풍부한 에너지를 당연하게 여기며, 불필요한 전기와 마법 에너지를 낭비했습니다."},
	{"caption": "에너지가 부족해지자 요정들은 화석연료를 마구 사용해 부족분을 메우려 했습니다."},
	{"caption": "그 결과 지구온난화·환경오염·자원고갈의 위기가 왕국을 뒤덮었습니다."},
	{"caption": "이제 퀴즈를 풀고 건설 아이템을 모아, 화력발전소를 재생에너지 발전소로 바꿔야 합니다!"}
]

func _ready() -> void:
	_apply_commercial_ui()
	_setup_character_selector()
	_setup_mode_selector()
	_setup_game_time_selector()
	_connect_actions()
	_build_room_popup()
	_room_browser = preload("res://scripts/ui/RoomBrowser.gd").new()
	add_child(_room_browser)
	_room_browser.create_requested.connect(_create_configured_room)
	_room_browser.join_requested.connect(_join_listed_room)
	char_option_button.select(0)
	_on_character_selected(0)
	_on_mode_selected(0)
	# 항상 보이는 드롭다운으로 캐릭터 선택을 보장합니다.
	char_option_button.visible = true
	character_strip.get_parent().visible = false
	if opening_story:
		opening_story.visible = false
		opening_story.gui_input.connect(_on_opening_story_input)
	if opening_skip_button:
		opening_skip_button.pressed.connect(_skip_opening_story)
	if NetworkManager:
		if not NetworkManager.connection_succeeded.is_connected(_on_network_connection_succeeded):
			NetworkManager.connection_succeeded.connect(_on_network_connection_succeeded)
		if not NetworkManager.connection_failed.is_connected(_on_network_connection_failed):
			NetworkManager.connection_failed.connect(_on_network_connection_failed)
		if not NetworkManager.room_state_changed.is_connected(_on_room_state_changed):
			NetworkManager.room_state_changed.connect(_on_room_state_changed)
		if not NetworkManager.room_code_lookup_failed.is_connected(_on_room_code_lookup_failed):
			NetworkManager.room_code_lookup_failed.connect(_on_room_code_lookup_failed)
		if not NetworkManager.room_code_created.is_connected(_on_room_code_created):
			NetworkManager.room_code_created.connect(_on_room_code_created)
		if not NetworkManager.external_room_ready.is_connected(_on_external_room_ready):
			NetworkManager.external_room_ready.connect(_on_external_room_ready)
		if not NetworkManager.external_room_failed.is_connected(_on_external_room_failed):
			NetworkManager.external_room_failed.connect(_on_external_room_failed)
	_play_intro_animation()


func _apply_commercial_ui() -> void:
	var top_bar := get_node_or_null("TopBar") as ColorRect
	if top_bar:
		top_bar.color = Color(0.015, 0.07, 0.09, 0.94)
	var frame := get_node_or_null("MenuPanel/Frame") as CanvasItem
	var old_shadow := get_node_or_null("MenuPanel/Shadow") as CanvasItem
	if frame:
		frame.visible = false
	if old_shadow:
		old_shadow.visible = false
	var shell := Panel.new()
	shell.name = "CommercialShell"
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_theme_stylebox_override("panel", UI.panel(Color("0b2530e8"), Color("3e8f94"), 18, 2, 14))
	menu_panel.add_child(shell)
	menu_panel.move_child(shell, 0)

	var form_backdrop := get_node_or_null("MenuPanel/FormBackdrop") as Panel
	if form_backdrop:
		form_backdrop.add_theme_stylebox_override("panel", UI.padded_panel(Color("102f3aeb"), Color("2d6570"), 12.0, 13))
	if hero_badge:
		hero_badge.add_theme_stylebox_override("panel", UI.padded_panel(Color("0b2631e8"), UI.TEAL_DARK, 12.0, 13))
	if hero_glow:
		hero_glow.visible = true
		hero_glow.add_theme_stylebox_override("panel", UI.panel(Color("54e2c018"), Color("54e2c038"), 96, 1, 18))

	for input_control in [nickname_edit, char_option_button, mode_option_button, game_time_option_button, ip_edit]:
		UI.apply_input(input_control)
	UI.apply_primary_button(local_start_button)
	UI.apply_primary_button(host_button)
	UI.apply_secondary_button(join_button, UI.TEAL)
	UI.apply_secondary_button(help_button, UI.GOLD)
	UI.apply_secondary_button(sound_button, UI.GOLD)

	var status := get_node_or_null("MenuPanel/Content/StatusLabel") as Label
	if status:
		status.add_theme_color_override("font_color", UI.TEXT_MUTED)
	var feature_title := get_node_or_null("MenuPanel/Content/FeatureTitle") as Label
	if feature_title:
		feature_title.text = "모험 핵심 요소"
		feature_title.add_theme_color_override("font_color", UI.GOLD)
	for chip_path in [
		"MenuPanel/Content/FeatureRow/QuizChip",
		"MenuPanel/Content/FeatureRow/SkillChip",
		"MenuPanel/Content/FeatureRow/VillageChip"
	]:
		var chip := get_node_or_null(chip_path) as PanelContainer
		if chip:
			chip.add_theme_stylebox_override("panel", UI.panel(Color("173b49dc"), Color("397685"), 9, 1, 2))
	var footer := get_node_or_null("Footer") as Label
	if footer:
		footer.text = "그린 킹덤 리빌드  •  에너지요정 나라 복원 프로젝트"
		footer.add_theme_color_override("font_color", UI.TEXT_MUTED)

	var story_caption := get_node_or_null("OpeningStoryOverlay/CaptionPanel") as PanelContainer
	if story_caption:
		story_caption.add_theme_stylebox_override("panel", UI.padded_panel(Color("071b25ee"), UI.GOLD_DARK, 20.0, 15))
	if opening_skip_button:
		UI.apply_secondary_button(opening_skip_button, UI.GOLD)

func _process(_delta: float) -> void:
	if _room_popup and _room_popup.visible:
		_room_status_label.text = status_label.text
	if not _intro_finished or not is_instance_valid(hero_portrait):
		return
	var time := Time.get_ticks_msec() / 1000.0
	hero_portrait.position.y = _hero_base_y + sin(time * 1.35) * 5.0
	hero_portrait.rotation = sin(time * 0.72) * 0.004

func _setup_character_selector() -> void:
	char_option_button.clear()
	for child in character_strip.get_children():
		child.queue_free()
	_character_buttons.clear()
	for index in range(characters.size()):
		var character := characters[index]
		char_option_button.add_item(character["name"])
		var button := Button.new()
		button.custom_minimum_size = Vector2(56, 56)
		button.tooltip_text = character["name"]
		button.clip_contents = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var portrait := TextureRect.new()
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait.offset_left = 4.0
		portrait.offset_top = 4.0
		portrait.offset_right = -4.0
		portrait.offset_bottom = -4.0
		portrait.texture = load(character["icon"])
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(portrait)
		button.pressed.connect(_select_character_from_button.bind(index))
		character_strip.add_child(button)
		_character_buttons.append(button)
	char_option_button.item_selected.connect(_on_character_selected)

func _select_character_from_button(index: int) -> void:
	char_option_button.select(index)
	_on_character_selected(index)

func _setup_mode_selector() -> void:
	mode_option_button.clear()
	mode_option_button.add_item("싱글 플레이  •  AI가 빈 자리 자동 채움")
	mode_option_button.add_item("온라인 모험  •  플레이어 호스트 · 최대 4인")
	mode_option_button.item_selected.connect(_on_mode_selected)
	mode_option_button.hide()
	$MenuPanel/Content/ModeLabel.hide()
	var actions := HBoxContainer.new()
	actions.name = "PlayModeButtons"
	actions.add_theme_constant_override("separation", 12)
	var content := local_start_button.get_parent()
	var action_index := local_start_button.get_index()
	content.add_child(actions)
	content.move_child(actions, action_index)
	local_start_button.reparent(actions)
	local_start_button.text = "싱글 플레이"
	local_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var online_button := Button.new()
	online_button.name = "OnlinePlayButton"
	online_button.text = "온라인 모험"
	online_button.custom_minimum_size.y = 68
	online_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	online_button.add_theme_font_size_override("font_size", 23)
	online_button.focus_mode = Control.FOCUS_NONE
	UI.apply_secondary_button(online_button, UI.TEAL)
	online_button.pressed.connect(func():
		_commit_line_edit_ime(nickname_edit)
		mode_option_button.select(1)
		_on_mode_selected(1)
	)
	actions.add_child(online_button)

func _setup_game_time_selector() -> void:
	game_time_option_button.clear()
	for minutes in [5, 10, 15, 20]:
		game_time_option_button.add_item("%d분" % minutes)
		game_time_option_button.set_item_metadata(game_time_option_button.item_count - 1, minutes * 60)
	game_time_option_button.select(1)

func _connect_actions() -> void:
	local_start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	host_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	join_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	help_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sound_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 버튼을 클릭해도 LineEdit의 한글 IME 조합 중 문자를 먼저 확정할 수 있게 포커스를 유지합니다.
	for action_button in [local_start_button, host_button, join_button]:
		action_button.focus_mode = Control.FOCUS_NONE

	local_start_button.pressed.connect(_on_local_start_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	help_button.pressed.connect(_on_help_pressed)
	sound_button.pressed.connect(_on_sound_pressed)
	nickname_edit.focus_exited.connect(_commit_line_edit_ime.bind(nickname_edit))
	ip_edit.focus_exited.connect(_commit_line_edit_ime.bind(ip_edit))

func _commit_line_edit_ime(line_edit: LineEdit) -> void:
	if line_edit and line_edit.has_ime_text():
		line_edit.apply_ime()

func _play_intro_animation() -> void:
	var logo_target := logo_container.position
	var panel_target := menu_panel.position
	var hero_target := hero_portrait.position
	var badge_target := hero_badge.position
	_hero_base_y = hero_target.y

	logo_container.modulate.a = 0.0
	menu_panel.modulate.a = 0.0
	hero_portrait.modulate.a = 0.0
	hero_badge.modulate.a = 0.0
	logo_container.position = logo_target + Vector2(0, -28)
	menu_panel.position = panel_target + Vector2(54, 0)
	hero_portrait.position = hero_target + Vector2(-48, 18)
	hero_badge.position = badge_target + Vector2(0, 24)

	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(logo_container, "position", logo_target, 0.75)
	tween.tween_property(logo_container, "modulate:a", 1.0, 0.55)
	tween.tween_property(hero_portrait, "position", hero_target, 0.85).set_delay(0.10)
	tween.tween_property(hero_portrait, "modulate:a", 1.0, 0.60).set_delay(0.10)
	tween.tween_property(hero_badge, "position", badge_target, 0.62).set_delay(0.25)
	tween.tween_property(hero_badge, "modulate:a", 1.0, 0.42).set_delay(0.25)
	tween.tween_property(menu_panel, "position", panel_target, 0.72).set_delay(0.12)
	tween.tween_property(menu_panel, "modulate:a", 1.0, 0.52).set_delay(0.12)
	tween.chain().tween_callback(func(): _intro_finished = true)

func _on_character_selected(idx: int) -> void:
	if idx < 0 or idx >= characters.size():
		return
	var character := characters[idx]
	hero_portrait.texture = load(character["icon"])
	character_name_label.text = character["name"]
	character_role_label.text = character["role"]
	var skill: Dictionary = GameManager.SPECIAL_SKILLS_BY_ICON.get(str(character["icon"]), GameManager.DEFAULT_SPECIAL_SKILL)
	var target_type := str(skill.get("target_type", "tile"))
	var target_label := "자신에게 즉시 적용" if target_type == "self" else ("플레이어 지정" if target_type == "player" else "타일 지정")
	var skill_accent: Color = character.get("color", UI.TEAL)
	skill_name_label.text = "특수기술 · %s  |  필요 SP %d  |  %s" % [skill.get("name", "특수기술"), int(skill.get("cost", 0)), target_label]
	skill_name_label.add_theme_color_override("font_color", skill_accent.lightened(0.22))
	skill_description_label.text = "%s 턴당 1회 사용할 수 있으며, 사용 후에도 주사위를 굴릴 수 있습니다." % str(skill.get("description", ""))
	hero_glow.modulate = Color(character["color"], 0.22)
	_update_character_button_styles(idx)
	if _intro_finished:
		hero_portrait.scale = Vector2(0.96, 0.96)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(hero_portrait, "scale", Vector2.ONE, 0.28)
	if NetworkManager and NetworkManager.is_online:
		NetworkManager.update_local_player_info(_get_local_player_info())

func _update_character_button_styles(selected_index: int) -> void:
	for index in range(_character_buttons.size()):
		var button := _character_buttons[index]
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.025, 0.09, 0.055, 0.96)
		style.set_corner_radius_all(9)
		style.set_border_width_all(3 if index == selected_index else 1)
		style.border_color = Color(1.0, 0.82, 0.20) if index == selected_index else Color(0.32, 0.55, 0.30, 0.75)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)

func _on_mode_selected(idx: int) -> void:
	var is_online_mode := idx == 1
	if not is_online_mode and NetworkManager.is_online and not NetworkManager.game_has_started:
		NetworkManager.disconnect_network()
		reset_network_controls()
	online_box.visible = false
	local_start_button.visible = true
	status_label.text = _online_mode_hint() if is_online_mode else "혼자 시작해도 AI 동료가 남은 3자리를 채워 4인 파티로 출발합니다."
	if is_online_mode and _room_browser:
		_room_browser.open_browser()

func _on_local_start_pressed() -> void:
	_commit_line_edit_ime(nickname_edit)
	var my_name := nickname_edit.text.strip_edges().left(6)
	if my_name.is_empty():
		my_name = "에코 히어로"

	var selected_index := clampi(char_option_button.selected, 0, characters.size() - 1)
	var my_character := characters[selected_index]
	var configs: Array[Dictionary] = [{"name": my_name, "is_ai": false, "char_icon": my_character["icon"], "char_color": my_character["color"]}]

	for offset in range(1, 4):
		var character_index := (selected_index + offset) % characters.size()
		var character := characters[character_index]
		configs.append({"name": character["name"] + " (AI)", "is_ai": true, "char_icon": character["icon"], "char_color": character["color"]})

	_pending_game_duration_seconds = int(game_time_option_button.get_selected_metadata())
	status_label.text = "%d분 동안 진행할 에너지 원정을 준비하는 중..." % (_pending_game_duration_seconds / 60)
	_begin_opening_story(configs)

func _on_host_pressed() -> void:
	if NetworkManager.is_online and NetworkManager.is_host:
		_pending_game_duration_seconds = int(game_time_option_button.get_selected_metadata())
		if NetworkManager.start_hosted_game(_pending_game_duration_seconds):
			status_label.text = "참가자들과 게임을 시작합니다..."
			host_button.disabled = true
		else:
			status_label.text = "이미 게임을 시작했거나 방을 시작할 수 없습니다."
		return
	_room_browser.open_browser()


func _create_configured_room(settings: Dictionary) -> void:
	var error := NetworkManager.create_room(NetworkManager.DEFAULT_PORT, _get_local_player_info(), settings)
	if error == OK:
		ip_edit.text = NetworkManager.room_code
		if NetworkManager.is_external_room_directory_configured():
			status_label.text = "방 생성 완료 · 코드 %s · 외부 네트워크 연결을 준비하는 중..." % NetworkManager.room_code
		else:
			status_label.text = "방 생성 완료 · 코드 %s · 같은 네트워크에서 참가할 수 있습니다. 현재 1/4명" % NetworkManager.room_code
		host_button.text = "게임 시작  •  빈 자리 AI 채움 ▶"
		join_button.disabled = true
		ip_edit.editable = false
		_show_room_popup(NetworkManager.connected_players)
	else:
		status_label.text = "방을 만들지 못했습니다. 포트 사용 상태를 확인하세요."
		_room_browser.show_error(status_label.text)


func _join_listed_room(code: String, password: String) -> void:
	ip_edit.text = code
	var error := NetworkManager.join_room_by_code(code, _get_local_player_info(), password)
	if error != OK:
		_room_browser.show_error("방에 참가하지 못했습니다. 네트워크 상태를 확인하세요.")

func _on_join_pressed() -> void:
	_commit_line_edit_ime(ip_edit)
	var target_code := ip_edit.text.strip_edges()
	if not NetworkManager.is_valid_room_code(target_code):
		status_label.text = "방장이 알려준 숫자 6자리를 정확히 입력하세요."
		return
	_room_browser.open_browser()
	_room_browser.prompt_code_join(target_code)


func _get_local_player_info() -> Dictionary:
	_commit_line_edit_ime(nickname_edit)
	var player_name := nickname_edit.text.strip_edges().left(6)
	if player_name.is_empty():
		player_name = "에코 히어로"
	var selected_index := clampi(char_option_button.selected, 0, characters.size() - 1)
	var character: Dictionary = characters[selected_index]
	return {
		"name": player_name,
		"char_icon": character["icon"],
		"char_color": character["color"]
	}


func _on_network_connection_succeeded() -> void:
	status_label.text = "게임방 참가 완료 · 방장이 게임을 시작할 때까지 기다려 주세요."
	char_option_button.disabled = true
	nickname_edit.editable = false
	ip_edit.editable = false
	_show_room_popup(NetworkManager.connected_players)


func _on_network_connection_failed() -> void:
	reset_network_controls()
	status_label.text = "게임방에 연결하지 못했습니다. 방 코드와 방장의 연결 상태를 확인하세요."
	host_button.disabled = false
	join_button.disabled = false
	ip_edit.editable = true
	_room_browser.show_error(status_label.text)


func _on_room_state_changed(players_data: Dictionary) -> void:
	if not visible or not NetworkManager.is_online:
		return
	_show_room_popup(players_data)
	if NetworkManager.is_host:
		status_label.text = "모두 모이면 게임 시작을 누르세요. 선택한 플레이 시간은 %d분입니다." % (int(game_time_option_button.get_selected_metadata()) / 60)
		host_button.disabled = false
	else:
		status_label.text = "게임방에 참가했습니다. 방장이 모험을 시작할 때까지 기다려 주세요."


func reset_network_controls(message: String = "") -> void:
	if _room_popup:
		_room_popup.hide()
	mode_option_button.disabled = false
	game_time_option_button.disabled = false
	if _room_browser:
		_room_browser.set_busy(false)
	host_button.text = "방 목록 / 만들기"
	host_button.disabled = false
	join_button.disabled = false
	nickname_edit.editable = true
	char_option_button.disabled = false
	ip_edit.editable = true
	if not message.is_empty():
		status_label.text = message
	elif mode_option_button.selected == 1:
		status_label.text = _online_mode_hint()


func _on_room_code_lookup_failed(message: String) -> void:
	status_label.text = message
	host_button.disabled = false
	join_button.disabled = false
	ip_edit.editable = true
	_room_browser.show_error(message)


func _on_room_code_created(code: String) -> void:
	if NetworkManager.is_host:
		ip_edit.text = code
		if _room_code_label:
			_room_code_label.text = "방 코드  %s" % code


func _on_external_room_ready(code: String) -> void:
	if visible and NetworkManager.is_host and not NetworkManager.game_has_started:
		status_label.text = "외부 네트워크 접속 준비 완료 · 참가자에게 코드 %s 를 알려주세요." % code


func _on_external_room_failed(message: String) -> void:
	if not visible or NetworkManager.game_has_started:
		return
	status_label.text = message
	if not NetworkManager.is_online:
		reset_network_controls(message)
		_room_browser.open_browser()
		_room_browser.show_error(message)
		host_button.disabled = false
		join_button.disabled = false
		join_button.visible = true
		host_button.text = "멀티 방 만들기  •  코드 자동 생성 ▶"
		char_option_button.disabled = false
		nickname_edit.editable = true
		ip_edit.editable = true


func _build_room_popup() -> void:
	_room_popup = Control.new()
	_room_popup.name = "OnlineRoomPopup"
	_room_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_room_popup.z_index = 50
	add_child(_room_popup)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.04, 0.06, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_room_popup.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_room_popup.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1080, 570)
	panel.add_theme_stylebox_override("panel", UI.padded_panel(UI.PANEL, UI.TEAL_DARK, 28, 20))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := _room_label("온라인 모험 · 대기실", 30, UI.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_room_count_label = _room_label("1 / 4명", 23, UI.TEAL)
	header.add_child(_room_count_label)
	_room_code_label = _room_label("방 코드", 34, UI.GOLD)
	content.add_child(_room_code_label)
	content.add_child(_room_label("친구에게 6자리 코드를 알려주고 함께 모험을 준비하세요.", 18, UI.TEXT_MUTED))
	_room_cards = HBoxContainer.new()
	_room_cards.add_theme_constant_override("separation", 14)
	content.add_child(_room_cards)
	_room_status_label = _room_label("", 18, UI.TEXT_MUTED)
	_room_status_label.custom_minimum_size.y = 50
	_room_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_room_status_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	content.add_child(actions)
	var leave := Button.new()
	leave.text = "방 나가기"
	leave.custom_minimum_size = Vector2(190, 52)
	UI.apply_secondary_button(leave)
	leave.pressed.connect(_leave_room_popup)
	actions.add_child(leave)
	_room_start_button = Button.new()
	_room_start_button.custom_minimum_size.y = 52
	_room_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.apply_primary_button(_room_start_button)
	_room_start_button.pressed.connect(_on_host_pressed)
	actions.add_child(_room_start_button)
	_room_popup.hide()


func _room_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _show_room_popup(players_data: Dictionary) -> void:
	if NetworkManager.game_has_started:
		return
	if _room_browser:
		_room_browser.hide()
		_room_browser.set_busy(false)
	_room_popup.show()
	_room_popup.move_to_front()
	nickname_edit.editable = false
	char_option_button.disabled = true
	mode_option_button.disabled = true
	game_time_option_button.disabled = true
	_room_code_label.text = "%s  ·  %s" % [NetworkManager.room_code, NetworkManager.room_title]
	_room_code_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_room_count_label.text = "%d / %d명" % [players_data.size(), NetworkManager.room_capacity]
	_room_start_button.disabled = not NetworkManager.is_host
	_room_start_button.text = "게임 시작 · 빈 자리는 AI가 채워요 ▶" if NetworkManager.is_host else "방장이 게임을 시작할 때까지 기다려 주세요"
	for child in _room_cards.get_children():
		_room_cards.remove_child(child)
		child.queue_free()
	var peer_ids := players_data.keys()
	peer_ids.sort()
	for slot in range(NetworkManager.room_capacity):
		var occupied := slot < peer_ids.size()
		var peer_id := int(peer_ids[slot]) if occupied else 0
		var info: Dictionary = players_data[peer_ids[slot]] if occupied else {}
		var character: Dictionary = {}
		for candidate in characters:
			if str(candidate["icon"]) == str(info.get("char_icon", "")):
				character = candidate
				break
		var accent: Color = character.get("color", UI.TEAL_DARK)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 265)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", UI.padded_panel(UI.PANEL_RAISED if occupied else UI.INK, accent if occupied else Color("31515c"), 14, 12))
		_room_cards.add_child(card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		card.add_child(column)
		var tag := "방장" if peer_id == 1 else "참가자"
		if peer_id == NetworkManager.my_peer_id:
			tag += " · 나"
		var badge := _room_label(tag if occupied else "빈 자리", 16, accent if occupied else UI.TEXT_MUTED)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(badge)
		var portrait := TextureRect.new()
		portrait.custom_minimum_size.y = 140
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if not character.is_empty():
			portrait.texture = load(str(character["icon"]))
		column.add_child(portrait)
		var nickname := _room_label(str(info.get("name", "플레이어")) if occupied else "친구를 기다리는 중", 22, UI.TEXT if occupied else UI.TEXT_MUTED)
		nickname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nickname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nickname.tooltip_text = nickname.text
		column.add_child(nickname)
		var character_name := _room_label(str(character.get("name", "에코 히어로")) if occupied else "시작하면 AI가 참가해요", 16, UI.TEXT_MUTED)
		character_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		character_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		column.add_child(character_name)


func _leave_room_popup() -> void:
	NetworkManager.disconnect_network()
	reset_network_controls("방에서 나왔습니다. 새 방을 만들거나 다른 방에 참가하세요.")
	ip_edit.text = ""
	_room_browser.open_browser()


func _online_mode_hint() -> String:
	if NetworkManager.is_external_room_directory_configured():
		return "방장이 만든 6자리 코드만 입력하면 다른 네트워크에서도 참가할 수 있습니다. 빈 자리는 AI가 채웁니다."
	return "방장이 만든 6자리 코드를 같은 네트워크의 친구가 입력하면 자동으로 참가합니다. 빈 자리는 AI가 채웁니다."

func _on_help_pressed() -> void:
	status_label.text = "퀴즈로 발전소 자재를 모아 화력발전소를 재생에너지 발전소로 바꿔 보세요!"
	var tween := create_tween()
	tween.tween_property(status_label, "modulate", Color(1.0, 0.9, 0.38, 1.0), 0.14)
	tween.tween_property(status_label, "modulate", Color.WHITE, 0.35)

func _on_sound_pressed() -> void:
	_sound_enabled = not _sound_enabled
	AudioServer.set_bus_mute(0, not _sound_enabled)
	sound_button.text = "SFX" if _sound_enabled else "MUTE"
	status_label.text = "사운드가 켜졌습니다." if _sound_enabled else "사운드가 꺼졌습니다."

func _begin_opening_story(configs: Array[Dictionary]) -> void:
	_pending_player_configs = configs
	_opening_sequence += 1
	_opening_step = 0
	_is_finishing_opening = false
	if opening_story == null:
		start_game_requested.emit(_pending_player_configs, _pending_game_duration_seconds)
		return
	opening_story.z_index = 100
	opening_story.modulate = Color.WHITE
	opening_story.visible = true
	opening_story.move_to_front()
	_show_opening_step()

func _show_opening_step() -> void:
	if _opening_step >= OPENING_STORY.size():
		_finish_opening_story()
		return
	var step: Dictionary = OPENING_STORY[_opening_step]
	if opening_image == null or _opening_step >= OPENING_IMAGES.size():
		_finish_opening_story()
		return
	opening_image.texture = OPENING_IMAGES[_opening_step]
	opening_image.visible = true
	opening_image.modulate = Color.WHITE
	opening_caption.text = step["caption"]
	opening_step_label.text = "STORY  %d / %d   •   클릭하여 다음  |  언제든 게임 바로 시작" % [_opening_step + 1, OPENING_STORY.size()]
	var sequence := _opening_sequence
	get_tree().create_timer(3.4).timeout.connect(func():
		if sequence == _opening_sequence and opening_story.visible:
			_advance_opening_story()
	)

func _on_opening_story_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_advance_opening_story()
		opening_story.accept_event()
	elif event.is_action_pressed("ui_accept"):
		_advance_opening_story()
		opening_story.accept_event()

func _advance_opening_story() -> void:
	if opening_story == null or not opening_story.visible:
		return
	_opening_step += 1
	_show_opening_step()

func _skip_opening_story() -> void:
	if opening_story == null or not opening_story.visible:
		return
	# 기존 자동 넘김 타이머를 무효화하고 즉시 게임 화면으로 전환합니다.
	_opening_sequence += 1
	_finish_opening_story()

func _finish_opening_story() -> void:
	if _is_finishing_opening:
		return
	_is_finishing_opening = true
	if opening_story:
		opening_story.visible = false
	start_game_requested.emit(_pending_player_configs, _pending_game_duration_seconds)
