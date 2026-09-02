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
	{"name": "캡틴 에코", "icon": "res://assets/characters/eco_roster/captain_eco.png", "color": Color(0.28, 0.90, 0.34), "role": "자연의 힘으로 도시를 회복하는 밸런스형 히어로"},
	{"name": "물방울 정령 포포", "icon": "res://assets/characters/eco_roster/water_popo.png", "color": Color(0.20, 0.72, 0.96), "role": "깨끗한 물의 힘으로 오염을 씻어 내는 회복형 히어로"},
	{"name": "에코 베어 퐁이", "icon": "res://assets/characters/eco_roster/bear_pongi.png", "color": Color(0.30, 0.92, 0.82), "role": "튼튼한 장비와 보호막으로 모두를 지키는 방어형 히어로"},
	{"name": "태양 여우 솔", "icon": "res://assets/characters/eco_roster/solar_fox_sol.png", "color": Color(1.00, 0.58, 0.12), "role": "태양광 장비로 에너지를 충전하는 기술형 히어로"},
	{"name": "바람 토끼 보리", "icon": "res://assets/characters/eco_roster/wind_rabbit_bori.png", "color": Color(0.22, 0.82, 0.92), "role": "바람보다 빠르게 길을 개척하는 기동형 히어로"},
	{"name": "재활용 너구리 링고", "icon": "res://assets/characters/eco_roster/recycle_raccoon_ringo.png", "color": Color(0.36, 0.82, 0.28), "role": "버려진 자원을 멋진 도구로 바꾸는 발명형 히어로"},
	{"name": "대지 거북 토리", "icon": "res://assets/characters/eco_roster/earth_turtle_tori.png", "color": Color(0.60, 0.72, 0.20), "role": "대지의 방패로 위험을 막아 내는 수호형 히어로"},
	{"name": "번개새 피카", "icon": "res://assets/characters/eco_roster/lightning_bird_pika.png", "color": Color(1.00, 0.82, 0.10), "role": "깨끗한 전기를 다루는 초고속 정찰형 히어로"},
	{"name": "버섯 고양이 모모", "icon": "res://assets/characters/eco_roster/mushroom_cat_momo.png", "color": Color(0.96, 0.30, 0.22), "role": "숲의 생명 에너지를 연구하는 연금술형 히어로"}
]

var _character_buttons: Array[Button] = []

var _hero_base_y := 178.0
var _intro_finished := false
var _sound_enabled := true
var _opening_step := 0
var _opening_sequence := 0
var _pending_player_configs: Array[Dictionary] = []
var _pending_game_duration_seconds := GameManager.DEFAULT_GAME_DURATION_SECONDS
var _is_finishing_opening := false

const OPENING_IMAGES := [
	preload("res://assets/story/opening/01_energy_waste.png"),
	preload("res://assets/story/opening/02_fossil_fuel.png"),
	preload("res://assets/story/opening/03_crisis.png"),
	preload("res://assets/story/opening/04_renewable_plan.png")
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
	mode_option_button.add_item("온라인 모험  •  최대 4인")
	mode_option_button.item_selected.connect(_on_mode_selected)

func _setup_game_time_selector() -> void:
	game_time_option_button.clear()
	for minutes in [5, 10, 15, 20]:
		game_time_option_button.add_item("%d분 동안 계속 플레이" % minutes)
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
	online_box.visible = is_online_mode
	local_start_button.visible = not is_online_mode
	status_label.text = "서버를 만들거나 IP 주소를 입력해 왕국 복원대와 합류하세요. 부족한 자리는 AI 동료로 채울 수 있습니다." if is_online_mode else "혼자 시작해도 AI 동료가 남은 3자리를 채워 4인 파티로 출발합니다."

func _on_local_start_pressed() -> void:
	_commit_line_edit_ime(nickname_edit)
	var my_name := nickname_edit.text.strip_edges()
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
	var error := NetworkManager.create_room()
	if error == OK:
		status_label.text = "방이 열렸습니다. 다른 히어로를 기다리는 중..."
		_on_local_start_pressed()
	else:
		status_label.text = "방을 만들지 못했습니다. 포트 사용 상태를 확인하세요."

func _on_join_pressed() -> void:
	_commit_line_edit_ime(ip_edit)
	var target_ip := ip_edit.text.strip_edges()
	if target_ip.is_empty():
		target_ip = "127.0.0.1"
	status_label.text = "%s 서버에 연결하는 중..." % target_ip
	var error := NetworkManager.join_room(target_ip)
	if error != OK:
		status_label.text = "서버에 연결하지 못했습니다. IP 주소를 확인하세요."

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
