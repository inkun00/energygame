extends Control
class_name HUDController

## HUDController: 인게임 4인 상태창, 오른쪽 주사위, 건설재료 현황 및 랭킹 모달 제어

signal board_zoom_requested(direction: float)
signal special_skill_tile_targets_changed(tile_indices: Array)

const PLAYER_PANEL_TEXTURE: Texture2D = preload("res://assets/open_source/kenney_adventure/panel_grey_bolts_dark.webp")
const VILLAGE_DRAG_CARD = preload("res://scripts/ui/ConstructionDragCard.gd")
const SPECIAL_SKILL_CINEMATIC = preload("res://scripts/effects/SpecialSkillCinematic.gd")
const ENDING_CINEMATIC = preload("res://scripts/effects/EndingCinematic.gd")
const ADVENTURE_PLANNER = preload("res://scripts/ui/AdventurePlanner.gd")
const UI = preload("res://scripts/ui/CommercialUI.gd")

@onready var player_panels_container: HBoxContainer = $TopHUD/PlayerPanels
@onready var status_ticker_label: Label = $TopHUD/StatusTicker/Label
@onready var center_dice_panel: PanelContainer = $CenterDicePanel
@onready var center_dice_button: Button = $CenterDiceButton
@onready var dice_value_label: Label = $CenterDicePanel/VBox/DiceValueLabel
@onready var dice_face: DiceFace = $CenterDicePanel/VBox/DiceFace
@onready var special_skill_button: Button = $SpecialSkillButton
@onready var event_banner: PanelContainer = $EventBanner
@onready var event_banner_label: Label = $EventBanner/Label
@onready var turn_prompt_label: Label = $TurnPrompt
@onready var kingdom_progress_bar: ProgressBar = $MissionPanel/Margin/VBox/KingdomProgressBar
@onready var kingdom_status_label: Label = $MissionPanel/Margin/VBox/KingdomStatusLabel
@onready var item_icons: HBoxContainer = $MissionPanel/Margin/VBox/ItemIcons
@onready var game_time_panel: PanelContainer = $GameTimePanel
@onready var game_time_label: Label = $GameTimePanel/VBox/TimeLabel
@onready var construction_guide_panel: Panel = $ConstructionGuidePanel
@onready var help_button: Button = $RightRail/HelpButton
@onready var sound_button: Button = $RightRail/SoundButton
@onready var info_button: Button = $RightRail/InfoButton
@onready var zoom_in_button: Button = $RightRail/ZoomInButton
@onready var zoom_out_button: Button = $RightRail/ZoomOutButton
@onready var victory_modal: Panel = $VictoryModal
@onready var victory_dimmer: ColorRect = $VictoryDimmer
@onready var victory_title: Label = $VictoryModal/Title
@onready var rescue_story_label: Label = $VictoryModal/RescueStoryLabel
@onready var victory_rankings_label: Label = $VictoryModal/RankingsLabel
@onready var lobby_return_button: Button = $VictoryModal/ReturnButton
@onready var build_instruction_label: Label = $VictoryModal/BuildInstructionLabel
@onready var construction_list: GridContainer = $VictoryModal/ConstructionList
@onready var evaluate_button: Button = $VictoryModal/EvaluateButton
@onready var save_village_button: Button = $VictoryModal/SaveVillageButton
@onready var save_status_label: Label = $VictoryModal/SaveStatusLabel
@onready var village_map: Variant = $VictoryModal/KingdomPreviewFrame/VillageMap
@onready var kingdom_health_bar: ProgressBar = $VictoryModal/KingdomHealthBar
@onready var energy_resolution_label: Label = $VictoryModal/EnergyResolutionLabel
@onready var built_projects_row: HBoxContainer = $VictoryModal/BuiltProjectsRow
@onready var rankings_container: VBoxContainer = $VictoryModal/RankingsContainer

var player_panel_nodes: Array[Control] = []
var event_banner_tween: Tween
var dice_tween: Tween
var sound_muted: bool = false
var special_skill_target_panel: PanelContainer
var special_skill_title_label: Label
var special_skill_description_label: Label
var special_skill_target_hint_label: Label
var active_special_skill_player_idx := -1
var active_special_skill: Dictionary = {}
var adventure_planner: Control
var guide_inventory_count_labels: Dictionary = {}
var guide_recipe_cards: Array[PanelContainer] = []
var lap_reward_dimmer: ColorRect
var lap_reward_panel: PanelContainer
var lap_reward_title_label: Label
var lap_reward_remaining_label: Label
var ending_cinematic: Control
var open_market_dimmer: ColorRect
var open_market_panel: PanelContainer
var open_market_title_label: Label
var open_market_timer_label: Label
var open_market_status_label: Label
var open_market_quota_label: Label
var open_market_item_grid: GridContainer
var open_market_confirm_button: Button
var open_market_offer_selection: Dictionary = {}
var _open_market_last_phase := -1

func _local_player_index() -> int:
	if NetworkManager and NetworkManager.is_online:
		return NetworkManager.get_local_player_index()
	return 0

func _ready() -> void:
	_apply_commercial_ui()
	_configure_inventory_item_icons()
	_create_construction_guide()
	if victory_modal:
		victory_modal.visible = false
	if victory_dimmer:
		victory_dimmer.visible = false
	if lobby_return_button:
		lobby_return_button.pressed.connect(_on_return_to_lobby)
		_apply_secondary_button_style(lobby_return_button)
	if evaluate_button:
		evaluate_button.pressed.connect(_on_evaluate_village_pressed)
		UI.apply_primary_button(evaluate_button)
	if save_village_button:
		save_village_button.pressed.connect(_on_save_village_pressed)
		_apply_secondary_button_style(save_village_button)
	if village_map:
		village_map.project_drop_requested.connect(_on_village_project_dropped)
		village_map.project_drop_rejected.connect(_on_village_project_drop_rejected)
	if center_dice_button:
		center_dice_button.pressed.connect(_on_center_dice_pressed)
	if special_skill_button:
		special_skill_button.pressed.connect(_on_special_skill_pressed)
		_apply_secondary_button_style(special_skill_button)
	_create_special_skill_target_panel()
	_create_lap_reward_panel()
	_create_open_market_panel()
	if help_button:
		help_button.pressed.connect(_on_help_pressed)
	if sound_button:
		sound_button.pressed.connect(_on_sound_pressed)
	if info_button:
		info_button.pressed.connect(_on_info_pressed)
	if zoom_in_button:
		zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	if zoom_out_button:
		zoom_out_button.pressed.connect(_on_zoom_out_pressed)
		
	# GameManager 시그널 연결
	if GameManager:
		GameManager.turn_changed.connect(_on_turn_changed)
		GameManager.player_moved.connect(_on_player_moved)
		GameManager.player_state_changed.connect(_on_player_state_changed)
		GameManager.dice_rolled.connect(_on_dice_rolled)
		GameManager.dice_input_time_changed.connect(_on_dice_input_time_changed)
		GameManager.status_message_posted.connect(_on_status_message_posted)
		GameManager.kingdom_progress_changed.connect(_on_kingdom_progress_changed)
		GameManager.player_inventory_changed.connect(_on_player_inventory_changed)
		GameManager.special_skill_completed.connect(_on_special_skill_completed)
		GameManager.village_construction_started.connect(_on_village_construction_started)
		GameManager.village_construction_changed.connect(_on_village_construction_changed)
		GameManager.game_over.connect(_on_game_over)
		GameManager.game_time_changed.connect(_on_game_time_changed)
		GameManager.lap_reward_requested.connect(_on_lap_reward_requested)
		GameManager.lap_reward_completed.connect(_on_lap_reward_completed)
		GameManager.open_market_state_changed.connect(_on_open_market_state_changed)

func initialize_hud() -> void:
	adventure_planner.begin_exploration(_local_player_index())
	if is_instance_valid(ending_cinematic):
		ending_cinematic.queue_free()
	ending_cinematic = null
	victory_modal.visible = false
	if victory_dimmer:
		victory_dimmer.visible = false
	_set_village_construction_controls(false)
	event_banner.visible = false
	_hide_lap_reward_panel()
	_hide_open_market_panel()
	_on_game_time_changed(ceili(GameManager.game_time_remaining), GameManager.game_duration_seconds)
	dice_face.value = 1
	dice_value_label.text = "클릭해서 굴리기"
	_set_center_dice_visible(false, false)
	_update_kingdom_mission(GameManager.projects_built, GameManager.CONSTRUCTION_PROJECTS.size(), GameManager.kingdom_health)
	var local_idx := _local_player_index()
	if local_idx >= 0 and local_idx < GameManager.players.size():
		_update_inventory(local_idx, GameManager.players[local_idx].get("inventory", {}))
	village_map.reset_map()
	_update_kingdom_visual(GameManager.kingdom_health)
	_refresh_built_project_images()
	# 4인 플레이어 정보 패널 생성
	for child in player_panels_container.get_children():
		child.queue_free()
	player_panel_nodes.clear()
	
	for i in range(GameManager.players.size()):
		var p_data = GameManager.players[i]
		var panel = _create_player_panel(p_data)
		player_panels_container.add_child(panel)
		player_panel_nodes.append(panel)
		
	update_all_player_panels()
	_refresh_special_skill_button()

func _create_player_panel(p_data: Dictionary) -> Control:
	var p_box = PanelContainer.new()
	p_box.custom_minimum_size = Vector2(296, 64)
	p_box.mouse_filter = Control.MOUSE_FILTER_STOP
	p_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p_box.tooltip_text = "%s의 상세 상태 보기" % p_data.get("name", "플레이어")
	
	var panel_color: Color = p_data.get("char_color", Color(0.3, 0.8, 0.5))
	var sb := UI.padded_panel(Color("112b36"), panel_color.darkened(0.16), 8.0, 9)
	sb.shadow_size = 4
	p_box.add_theme_stylebox_override("panel", sb)
	p_box.set_meta("player_color", panel_color)
	
	var h_box = HBoxContainer.new()
	h_box.add_theme_constant_override("separation", 8)
	p_box.add_child(h_box)

	var turn_marker = Label.new()
	turn_marker.name = "TurnMarker"
	turn_marker.custom_minimum_size = Vector2(26, 0)
	turn_marker.text = "▶"
	turn_marker.visible = false
	turn_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_marker.add_theme_font_size_override("font_size", 13) # 기존 10 -> 13
	turn_marker.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22))
	turn_marker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	turn_marker.add_theme_constant_override("outline_size", 3)
	h_box.add_child(turn_marker)
	
	var avatar = TextureRect.new()
	avatar.custom_minimum_size = Vector2(52, 52)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path = p_data.get("char_icon", "res://assets/images/char_captain_eco.webp")
	if ResourceLoader.exists(icon_path):
		avatar.texture = load(icon_path)
	h_box.add_child(avatar)
	
	var v_info = VBoxContainer.new()
	v_info.alignment = BoxContainer.ALIGNMENT_CENTER
	v_info.add_theme_constant_override("separation", 1)
	h_box.add_child(v_info)
	
	var name_lbl = Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.text = p_data.get("name", "")
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.custom_minimum_size = Vector2(155, 0)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	name_lbl.add_theme_constant_override("outline_size", 3)
	v_info.add_child(name_lbl)
	
	var stat_lbl = Label.new()
	stat_lbl.name = "StatLabel"
	stat_lbl.text = "에너지 %d  ·  SP %d" % [p_data.get("energy", 0), p_data.get("skill_energy", 0)]
	stat_lbl.add_theme_font_size_override("font_size", 12)
	stat_lbl.add_theme_color_override("font_color", Color(0.48, 0.98, 0.90))
	stat_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	stat_lbl.add_theme_constant_override("outline_size", 2)
	v_info.add_child(stat_lbl)

	_set_descendant_mouse_filter_ignore(p_box)
	p_box.gui_input.connect(_on_player_panel_gui_input.bind(int(p_data.get("index", 0))))
	
	return p_box

func _set_descendant_mouse_filter_ignore(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_descendant_mouse_filter_ignore(child)

func _on_player_panel_gui_input(event: InputEvent, player_index: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if _is_special_skill_player_targeting():
				_try_activate_special_skill(player_index)
				return
			if player_index >= 0 and player_index < GameManager.players.size():
				var player: Dictionary = GameManager.players[player_index]
				var shield_text := " • 방패 보유" if player.get("shield", false) else ""
				var item_count := _get_inventory_total(player.get("inventory", {}))
				_show_event_banner("%s  •  퀴즈 정답 %d  •  관전 보너스 %d점  •  특수 에너지 %d  •  개인 재료 %d  •  %d번 칸%s" % [player["name"], player.get("quiz_correct", 0), player.get("bonus_quiz_score", 0), player.get("skill_energy", 0), item_count, player["position"], shield_text])

func _create_special_skill_target_panel() -> void:
	if special_skill_target_panel != null:
		return
	special_skill_target_panel = PanelContainer.new()
	special_skill_target_panel.name = "SpecialSkillTargetPanel"
	# 플레이어 카드 아래의 상단 안내 영역에 얕고 넓게 배치해 지도 중앙과
	# 타일 선택 영역을 최대한 가리지 않습니다.
	special_skill_target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	special_skill_target_panel.offset_left = -365.0
	special_skill_target_panel.offset_top = 104.0
	special_skill_target_panel.offset_right = 365.0
	special_skill_target_panel.offset_bottom = 218.0
	special_skill_target_panel.z_index = 30
	special_skill_target_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("163a42")
	panel_style.border_color = Color("68e8bf")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(14)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
	panel_style.shadow_size = 7
	panel_style.content_margin_left = 18.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_right = 18.0
	panel_style.content_margin_bottom = 10.0
	special_skill_target_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(special_skill_target_panel)

	var content := HBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 16)
	special_skill_target_panel.add_child(content)
	special_skill_title_label = Label.new()
	special_skill_title_label.custom_minimum_size = Vector2(205, 0)
	special_skill_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	special_skill_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	special_skill_title_label.add_theme_font_size_override("font_size", 20)
	special_skill_title_label.add_theme_color_override("font_color", Color("fff0a4"))
	special_skill_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	special_skill_title_label.add_theme_constant_override("outline_size", 3)
	content.add_child(special_skill_title_label)
	var guidance := VBoxContainer.new()
	guidance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guidance.alignment = BoxContainer.ALIGNMENT_CENTER
	guidance.add_theme_constant_override("separation", 4)
	content.add_child(guidance)
	special_skill_description_label = Label.new()
	special_skill_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	special_skill_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	special_skill_description_label.add_theme_font_size_override("font_size", 14)
	special_skill_description_label.add_theme_color_override("font_color", Color("e8fff7"))
	guidance.add_child(special_skill_description_label)
	special_skill_target_hint_label = Label.new()
	special_skill_target_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	special_skill_target_hint_label.add_theme_font_size_override("font_size", 15)
	special_skill_target_hint_label.add_theme_color_override("font_color", Color("7dffe0"))
	guidance.add_child(special_skill_target_hint_label)
	var cancel_button := Button.new()
	cancel_button.text = "취소"
	cancel_button.custom_minimum_size = Vector2(92, 40)
	cancel_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel_button.pressed.connect(_cancel_special_skill_targeting)
	_apply_secondary_button_style(cancel_button)
	content.add_child(cancel_button)
	special_skill_target_panel.visible = false

func _create_lap_reward_panel() -> void:
	if lap_reward_panel != null:
		return
	lap_reward_dimmer = ColorRect.new()
	lap_reward_dimmer.name = "LapRewardDimmer"
	lap_reward_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lap_reward_dimmer.color = Color(0.005, 0.025, 0.04, 0.78)
	lap_reward_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	lap_reward_dimmer.z_index = 44
	add_child(lap_reward_dimmer)

	lap_reward_panel = PanelContainer.new()
	lap_reward_panel.name = "LapRewardPanel"
	lap_reward_panel.set_anchors_preset(Control.PRESET_CENTER)
	lap_reward_panel.offset_left = -420.0
	lap_reward_panel.offset_top = -245.0
	lap_reward_panel.offset_right = 420.0
	lap_reward_panel.offset_bottom = 245.0
	lap_reward_panel.z_index = 45
	lap_reward_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	lap_reward_panel.add_theme_stylebox_override("panel", UI.padded_panel(Color("0c2d38f5"), UI.GOLD, 20.0, 22))
	add_child(lap_reward_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	lap_reward_panel.add_child(content)
	lap_reward_title_label = Label.new()
	lap_reward_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lap_reward_title_label.add_theme_font_size_override("font_size", 29)
	lap_reward_title_label.add_theme_color_override("font_color", UI.GOLD)
	content.add_child(lap_reward_title_label)
	lap_reward_remaining_label = Label.new()
	lap_reward_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lap_reward_remaining_label.add_theme_font_size_override("font_size", 17)
	lap_reward_remaining_label.add_theme_color_override("font_color", UI.TEXT)
	content.add_child(lap_reward_remaining_label)

	var item_grid := GridContainer.new()
	item_grid.name = "ItemGrid"
	item_grid.columns = 3
	item_grid.add_theme_constant_override("h_separation", 9)
	item_grid.add_theme_constant_override("v_separation", 9)
	content.add_child(item_grid)
	for item_id_variant in GameManager.ITEM_DEFINITIONS:
		var item_id := str(item_id_variant)
		var item_data: Dictionary = GameManager.ITEM_DEFINITIONS[item_id]
		var button := Button.new()
		button.name = "Reward_%s" % item_id
		button.custom_minimum_size = Vector2(252, 78)
		button.text = str(item_data["name"])
		button.icon = load(str(item_data["asset"]))
		button.expand_icon = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		UI.apply_secondary_button(button, UI.TEAL)
		button.pressed.connect(_on_lap_reward_item_pressed.bind(item_id))
		item_grid.add_child(button)

	var hint := Label.new()
	hint.text = "같은 부품을 여러 번 선택해도 됩니다. 보상을 고르는 동안 플레이 시간은 멈춥니다."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", UI.TEXT_MUTED)
	content.add_child(hint)
	_hide_lap_reward_panel()

func _on_lap_reward_requested(player_idx: int, rank: int, reward_count: int) -> void:
	if player_idx < 0 or player_idx >= GameManager.players.size():
		return
	if player_idx != _local_player_index():
		return
	lap_reward_title_label.text = "🏁 %d등 완주 보상" % rank
	lap_reward_remaining_label.text = "%s님, 원하는 발전소 부품을 고르세요  ·  남은 선택 %d개" % [GameManager.players[player_idx]["name"], reward_count]
	lap_reward_dimmer.visible = true
	lap_reward_panel.visible = true
	lap_reward_panel.scale = Vector2(0.92, 0.92)
	lap_reward_panel.pivot_offset = lap_reward_panel.size * 0.5
	create_tween().tween_property(lap_reward_panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_lap_reward_item_pressed(item_id: String) -> void:
	if GameManager.pending_lap_reward.is_empty():
		_hide_lap_reward_panel()
		return
	var player_idx := int(GameManager.pending_lap_reward.get("player_idx", -1))
	if NetworkManager.is_online:
		NetworkManager.request_lap_reward(player_idx, item_id)
		return
	if GameManager.claim_lap_reward(player_idx, item_id) and not GameManager.pending_lap_reward.is_empty():
		lap_reward_remaining_label.text = "%s님, 원하는 발전소 부품을 고르세요  ·  남은 선택 %d개" % [GameManager.players[player_idx]["name"], int(GameManager.pending_lap_reward.get("remaining", 0))]

func _on_lap_reward_completed(_player_idx: int, _selected_items: Array) -> void:
	_hide_lap_reward_panel()

func _hide_lap_reward_panel() -> void:
	if lap_reward_dimmer:
		lap_reward_dimmer.visible = false
	if lap_reward_panel:
		lap_reward_panel.visible = false


func _create_open_market_panel() -> void:
	if open_market_panel:
		return
	open_market_dimmer = ColorRect.new()
	open_market_dimmer.name = "OpenMarketDimmer"
	open_market_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	open_market_dimmer.color = Color(0.005, 0.025, 0.04, 0.86)
	open_market_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	open_market_dimmer.z_index = 58
	add_child(open_market_dimmer)

	open_market_panel = PanelContainer.new()
	open_market_panel.name = "OpenMarketPanel"
	open_market_panel.set_anchors_preset(Control.PRESET_CENTER)
	open_market_panel.offset_left = -560.0
	open_market_panel.offset_top = -305.0
	open_market_panel.offset_right = 560.0
	open_market_panel.offset_bottom = 305.0
	open_market_panel.z_index = 59
	open_market_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	open_market_panel.add_theme_stylebox_override("panel", UI.padded_panel(Color("0b2833fa"), UI.TEAL, 20.0, 22))
	add_child(open_market_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	open_market_panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	open_market_title_label = Label.new()
	open_market_title_label.text = "오픈마켓 · 비공개 선택"
	open_market_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_market_title_label.add_theme_font_size_override("font_size", 28)
	open_market_title_label.add_theme_color_override("font_color", UI.GOLD)
	header.add_child(open_market_title_label)
	open_market_timer_label = Label.new()
	open_market_timer_label.custom_minimum_size = Vector2(135, 0)
	open_market_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	open_market_timer_label.add_theme_font_size_override("font_size", 24)
	open_market_timer_label.add_theme_color_override("font_color", UI.GOLD)
	header.add_child(open_market_timer_label)

	open_market_status_label = Label.new()
	open_market_status_label.custom_minimum_size = Vector2(0, 48)
	open_market_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	open_market_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	open_market_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	open_market_status_label.add_theme_font_size_override("font_size", 17)
	open_market_status_label.add_theme_color_override("font_color", UI.TEXT)
	content.add_child(open_market_status_label)

	open_market_quota_label = Label.new()
	open_market_quota_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	open_market_quota_label.add_theme_font_size_override("font_size", 17)
	open_market_quota_label.add_theme_color_override("font_color", Color("8fffe0"))
	content.add_child(open_market_quota_label)

	open_market_item_grid = GridContainer.new()
	open_market_item_grid.columns = 4
	open_market_item_grid.add_theme_constant_override("h_separation", 8)
	open_market_item_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(open_market_item_grid)

	open_market_confirm_button = Button.new()
	open_market_confirm_button.custom_minimum_size = Vector2(0, 50)
	open_market_confirm_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	open_market_confirm_button.pressed.connect(_on_open_market_offer_confirmed)
	UI.apply_primary_button(open_market_confirm_button)
	content.add_child(open_market_confirm_button)

	var hint := Label.new()
	hint.text = "판매 선택은 모두가 확정할 때까지 비공개입니다. 공개 후에는 서버에 먼저 도착한 요청부터 처리됩니다."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UI.TEXT_MUTED)
	content.add_child(hint)
	_hide_open_market_panel()


func _on_open_market_state_changed(state: Dictionary) -> void:
	if not bool(state.get("active", false)):
		_hide_open_market_panel()
		return
	_hide_lap_reward_panel()
	_set_center_dice_visible(false, false)
	if victory_modal:
		victory_modal.visible = false
	if victory_dimmer:
		victory_dimmer.visible = false
	open_market_dimmer.visible = true
	open_market_panel.visible = true
	var phase := int(state.get("phase", GameManager.OpenMarketPhase.INACTIVE))
	if phase != _open_market_last_phase:
		_open_market_last_phase = phase
		if phase == GameManager.OpenMarketPhase.OFFERING:
			open_market_offer_selection = GameManager._create_empty_inventory()
	_refresh_open_market_panel(state)


func _refresh_open_market_panel(state: Dictionary) -> void:
	if not open_market_panel or not open_market_item_grid:
		return
	for child in open_market_item_grid.get_children():
		open_market_item_grid.remove_child(child)
		child.queue_free()
	var local_idx := _local_player_index()
	var phase := int(state.get("phase", GameManager.OpenMarketPhase.INACTIVE))
	var remaining_seconds := int(state.get("time_remaining", 0))
	open_market_timer_label.text = "%d초" % maxi(remaining_seconds, 0)
	open_market_timer_label.add_theme_color_override("font_color", UI.DANGER if remaining_seconds <= 5 else UI.GOLD)
	var submitted: Dictionary = state.get("submitted_players", {})
	var local_submitted := submitted.has(local_idx)
	var local_is_ai := local_idx >= 0 and local_idx < GameManager.players.size() and bool(GameManager.players[local_idx].get("is_ai", false))

	if phase == GameManager.OpenMarketPhase.OFFERING:
		open_market_title_label.text = "오픈마켓 · 비공개 판매 선택"
		open_market_status_label.text = "내놓을 부품 수량을 고르세요. 모두 확정한 순간에만 시장에 동시에 공개됩니다."
		open_market_quota_label.text = "결정 완료 %d / %d명%s" % [submitted.size(), int(state.get("player_count", GameManager.players.size())), " · 내 선택 확정됨" if local_submitted else ""]
		var inventory: Dictionary = GameManager.players[local_idx].get("inventory", {}) if local_idx >= 0 and local_idx < GameManager.players.size() else {}
		for item_id_variant in GameManager.ITEM_DEFINITIONS.keys():
			var item_id := str(item_id_variant)
			var owned := int(inventory.get(item_id, 0))
			var selected := clampi(int(open_market_offer_selection.get(item_id, 0)), 0, owned)
			open_market_offer_selection[item_id] = selected
			var button := _create_open_market_item_button(item_id, "%s\n판매 %d / 보유 %d" % [GameManager.ITEM_DEFINITIONS[item_id]["name"], selected, owned])
			button.disabled = local_submitted or local_is_ai or owned <= 0
			button.tooltip_text = "누를 때마다 판매 수량이 1개씩 늘고, 최대 수량 다음에는 0개로 돌아갑니다."
			button.pressed.connect(_on_open_market_offer_item_pressed.bind(item_id, owned))
			open_market_item_grid.add_child(button)
		var selected_total := _get_inventory_total(open_market_offer_selection)
		open_market_confirm_button.visible = true
		open_market_confirm_button.disabled = local_submitted or local_is_ai
		open_market_confirm_button.text = "선택한 부품 %d개를 동시에 올리기" % selected_total if not local_submitted else "판매 선택 확정 · 다른 플레이어를 기다리는 중"
	else:
		open_market_title_label.text = "오픈마켓 · 선착순 부품 획득"
		var allowances: Dictionary = state.get("allowances", {})
		var taken_counts: Dictionary = state.get("taken_counts", {})
		var allowance := int(allowances.get(local_idx, 0))
		var taken := int(taken_counts.get(local_idx, 0))
		var quota_remaining := maxi(0, allowance - taken)
		open_market_status_label.text = "시장에 공개된 부품을 누르세요. 먼저 도착한 요청이 가져갑니다!"
		open_market_quota_label.text = "내가 올린 부품 %d개 · 가져갈 수 있는 부품 %d개 남음" % [allowance, quota_remaining]
		var stock: Dictionary = state.get("stock", {})
		for item_id_variant in GameManager.ITEM_DEFINITIONS.keys():
			var item_id := str(item_id_variant)
			var amount := int(stock.get(item_id, 0))
			var button := _create_open_market_item_button(item_id, "%s\n시장 재고 ×%d" % [GameManager.ITEM_DEFINITIONS[item_id]["name"], amount])
			button.disabled = local_is_ai or quota_remaining <= 0 or amount <= 0
			button.tooltip_text = "클릭하면 이 부품 1개를 선착순으로 가져옵니다."
			button.pressed.connect(_on_open_market_take_item_pressed.bind(item_id))
			open_market_item_grid.add_child(button)
		open_market_confirm_button.visible = false


func _create_open_market_item_button(item_id: String, label_text: String) -> Button:
	var item_data: Dictionary = GameManager.ITEM_DEFINITIONS[item_id]
	var button := Button.new()
	button.custom_minimum_size = Vector2(252, 82)
	button.text = label_text
	button.icon = load(str(item_data["asset"]))
	button.expand_icon = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UI.apply_secondary_button(button, UI.TEAL)
	return button


func _on_open_market_offer_item_pressed(item_id: String, owned: int) -> void:
	var selected := int(open_market_offer_selection.get(item_id, 0)) + 1
	open_market_offer_selection[item_id] = 0 if selected > owned else selected
	_refresh_open_market_panel(GameManager.get_open_market_state())


func _on_open_market_offer_confirmed() -> void:
	var local_idx := _local_player_index()
	if NetworkManager.is_online:
		NetworkManager.request_open_market_offer(local_idx, open_market_offer_selection)
	else:
		GameManager.submit_open_market_offer(local_idx, open_market_offer_selection)


func _on_open_market_take_item_pressed(item_id: String) -> void:
	var local_idx := _local_player_index()
	if NetworkManager.is_online:
		NetworkManager.request_open_market_take(local_idx, item_id)
	else:
		GameManager.take_open_market_item(local_idx, item_id)


func _hide_open_market_panel() -> void:
	if open_market_dimmer:
		open_market_dimmer.visible = false
	if open_market_panel:
		open_market_panel.visible = false
	_open_market_last_phase = -1
	open_market_offer_selection.clear()

func _on_game_time_changed(remaining_seconds: int, _total_seconds: int) -> void:
	if not game_time_label:
		return
	var minutes := remaining_seconds / 60
	var seconds := remaining_seconds % 60
	game_time_label.text = "%02d:%02d" % [minutes, seconds]
	game_time_label.add_theme_color_override("font_color", Color("ff6b55") if remaining_seconds <= 60 else UI.GOLD)

func _refresh_special_skill_button() -> void:
	if special_skill_button == null:
		return
	if GameManager.players.is_empty():
		special_skill_button.disabled = true
		return
	var local_idx := _local_player_index()
	if local_idx < 0 or local_idx >= GameManager.players.size():
		special_skill_button.disabled = true
		return
	var local_player: Dictionary = GameManager.players[local_idx]
	var skill := GameManager.get_player_special_skill(local_idx)
	var skill_energy := int(local_player.get("skill_energy", 0))
	var cost := int(skill.get("cost", 0))
	if GameManager.current_turn_idx == local_idx and GameManager.special_skill_used_this_turn:
		special_skill_button.text = "%s\n이번 턴 사용 완료" % skill["name"]
	else:
		special_skill_button.text = "%s\nSP %d / %d" % [skill["name"], skill_energy, cost]
	var target_label := "자신" if skill.get("target_type") == "self" else ("플레이어" if skill.get("target_type") == "player" else "게임판 타일")
	special_skill_button.tooltip_text = "%s\n대상: %s · 퀴즈 특수 에너지 %d / %d" % [skill["description"], target_label, skill_energy, cost]
	var local_is_human := not bool(local_player.get("is_ai", false))
	special_skill_button.disabled = not local_is_human or not GameManager.can_use_special_skill(local_idx)

func _on_special_skill_pressed() -> void:
	var local_idx := _local_player_index()
	if not GameManager.can_use_special_skill(local_idx):
		_show_event_banner("특수기술은 내 턴에, 퀴즈 정답으로 모은 특수 에너지가 충분할 때 사용할 수 있습니다.")
		_refresh_special_skill_button()
		return
	active_special_skill_player_idx = local_idx
	active_special_skill = GameManager.get_player_special_skill(local_idx)
	if active_special_skill.get("target_type") == "self":
		_try_activate_special_skill(local_idx)
		return
	if special_skill_target_panel:
		special_skill_title_label.text = "%s  ·  필요 SP %d" % [active_special_skill["name"], int(active_special_skill["cost"])]
		special_skill_description_label.text = str(active_special_skill["description"])
		if active_special_skill.get("target_type") == "player":
			special_skill_target_hint_label.text = "상단의 플레이어 카드를 눌러 대상을 지정하세요."
		elif active_special_skill.get("effect") == "move":
			var valid_targets := GameManager.get_valid_special_skill_targets(active_special_skill_player_idx)
			special_skill_target_hint_label.text = "게임판에서 밝게 표시된 타일을 선택하세요."
			special_skill_tile_targets_changed.emit(valid_targets)
		else:
			special_skill_target_hint_label.text = "게임판의 타일을 눌러 대상을 지정하세요."
		special_skill_target_panel.visible = true
	special_skill_button.disabled = true
	_refresh_primary_action_controls()
	_show_event_banner("%s: %s" % [active_special_skill["name"], special_skill_target_hint_label.text])

func _is_special_skill_player_targeting() -> bool:
	return active_special_skill_player_idx >= 0 and str(active_special_skill.get("target_type", "")) == "player"

func try_select_special_skill_tile(tile_index: int) -> bool:
	if active_special_skill_player_idx < 0 or str(active_special_skill.get("target_type", "")) != "tile":
		return false
	_try_activate_special_skill(tile_index)
	return true

func _try_activate_special_skill(target_index: int) -> void:
	if active_special_skill_player_idx < 0:
		return
	if NetworkManager.is_online:
		NetworkManager.request_special_skill(active_special_skill_player_idx, target_index)
		_cancel_special_skill_targeting()
		return
	if GameManager.use_special_skill(active_special_skill_player_idx, target_index):
		_cancel_special_skill_targeting()
		_refresh_special_skill_button()

func _cancel_special_skill_targeting() -> void:
	special_skill_tile_targets_changed.emit([])
	active_special_skill_player_idx = -1
	active_special_skill.clear()
	if special_skill_target_panel:
		special_skill_target_panel.visible = false
	_refresh_special_skill_button()
	_refresh_primary_action_controls()


func _refresh_primary_action_controls() -> void:
	var action_ready := false
	var is_local_turn := false
	if GameManager and not GameManager.players.is_empty():
		var local_idx := _local_player_index()
		is_local_turn = local_idx >= 0 and GameManager.current_turn_idx == local_idx and not bool(GameManager.players[local_idx].get("is_ai", false))
		action_ready = is_local_turn and GameManager.current_state == GameManager.TurnState.WAIT_ACTION and active_special_skill_player_idx < 0
	# 굴림 중에는 결과 연출이 끝날 때까지 오른쪽 주사위를 유지합니다.
	if GameManager and GameManager.current_state == GameManager.TurnState.ROLLING_DICE:
		_set_center_dice_visible(true, false)
	else:
		_set_center_dice_visible(action_ready, action_ready)


func _on_special_skill_completed(player_idx: int) -> void:
	if player_idx != _local_player_index():
		return
	_refresh_special_skill_button()
	_refresh_primary_action_controls()
	if turn_prompt_label:
		turn_prompt_label.text = "특수기술 완료  •  오른쪽 주사위를 클릭하세요"
		turn_prompt_label.add_theme_color_override("font_color", UI.GOLD)
		_animate_turn_prompt()


func play_special_skill_cinematic(player_idx: int, skill: Dictionary, screen_position: Vector2) -> void:
	var cinematic := SPECIAL_SKILL_CINEMATIC.new()
	cinematic.name = "SpecialSkillCinematic"
	add_child(cinematic)
	cinematic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cinematic.z_index = 40
	var character_color := UI.TEAL
	if GameManager and player_idx >= 0 and player_idx < GameManager.players.size():
		character_color = GameManager.players[player_idx].get("char_color", UI.TEAL)
	cinematic.setup(skill, screen_position, character_color)

func show_tile_info(tile_data: Dictionary) -> void:
	_show_event_banner("%02d번  •  %s\n%s" % [tile_data.get("index", 0), tile_data.get("name", "타일"), tile_data.get("desc", "")])

func show_zoom_level(percent: int) -> void:
	_show_event_banner("보드 확대/축소  •  %d%%" % percent)

func _on_kingdom_progress_changed(projects_built: int, total_projects: int, health: int) -> void:
	_update_kingdom_mission(projects_built, total_projects, health)
	_update_kingdom_visual(health)
	_refresh_built_project_images()

func _update_kingdom_mission(projects_built: int, total_projects: int, _health: int) -> void:
	if kingdom_progress_bar:
		kingdom_progress_bar.max_value = max(total_projects, 1)
		kingdom_progress_bar.value = clampi(projects_built, 0, total_projects)
	if kingdom_status_label:
		var shown_player_idx := clampi(_local_player_index(), 0, max(GameManager.players.size() - 1, 0))
		var material_total := _get_inventory_total(GameManager.players[shown_player_idx].get("inventory", {})) if not GameManager.players.is_empty() else 0
		# 이 패널은 현재 플레이어의 개인 재료를 보여주므로, 마을 전체 공동 지수를
		# 개인 능력치처럼 함께 표시하지 않습니다.
		kingdom_status_label.text = "개인 재료 %d개  •  공동 건설 %d / %d" % [material_total, projects_built, total_projects]

func _on_player_inventory_changed(player_idx: int, inventory: Dictionary) -> void:
	var local_idx := _local_player_index()
	if player_idx == local_idx:
		_update_inventory(player_idx, inventory)
	if player_idx == local_idx:
		_update_kingdom_mission(GameManager.projects_built, GameManager.CONSTRUCTION_PROJECTS.size(), GameManager.kingdom_health)
		if not GameManager.pending_lap_reward.is_empty() and int(GameManager.pending_lap_reward.get("player_idx", -1)) == local_idx and lap_reward_remaining_label:
			lap_reward_remaining_label.text = "%s님, 원하는 발전소 부품을 고르세요  ·  남은 선택 %d개" % [GameManager.players[local_idx]["name"], int(GameManager.pending_lap_reward.get("remaining", 0))]
	if GameManager.village_construction_active:
		_refresh_construction_choices()

func _configure_inventory_item_icons() -> void:
	if not item_icons:
		return
	item_icons.visible = false
	item_icons.add_theme_constant_override("separation", 2)
	for item_id_variant in GameManager.ITEM_DEFINITIONS:
		var item_id := str(item_id_variant)
		var item_data: Dictionary = GameManager.ITEM_DEFINITIONS[item_id]
		var item_box := item_icons.get_node_or_null(item_id) as VBoxContainer
		if not item_box:
			item_box = VBoxContainer.new()
			item_box.name = item_id
			item_box.alignment = BoxContainer.ALIGNMENT_CENTER
			item_icons.add_child(item_box)
			var icon := TextureRect.new()
			icon.name = "Icon"
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			item_box.add_child(icon)
			var count := Label.new()
			count.name = "Count"
			count.text = "×0"
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			count.add_theme_color_override("font_color", Color(1, 0.92, 0.58))
			count.add_theme_font_size_override("font_size", 10)
			item_box.add_child(count)
		item_box.custom_minimum_size = Vector2(24, 0)
		var icon_node := item_box.get_node_or_null("Icon") as TextureRect
		if icon_node:
			icon_node.custom_minimum_size = Vector2(23, 31)
			icon_node.tooltip_text = str(item_data["name"])
			icon_node.texture = load(str(item_data["asset"]))


func _create_construction_guide() -> void:
	construction_guide_panel.hide()
	adventure_planner = ADVENTURE_PLANNER.new()
	adventure_planner.name = "AdventurePlanner"
	adventure_planner.z_index = 3
	add_child(adventure_planner)
	guide_inventory_count_labels = adventure_planner.inventory_labels
	guide_recipe_cards = adventure_planner.recipe_cards

func _refresh_construction_guide(_player_idx: int, inventory: Dictionary) -> void:
	adventure_planner.refresh(inventory)

func _update_inventory(player_idx: int, inventory: Dictionary) -> void:
	if not item_icons:
		return
	for item_id in GameManager.ITEM_DEFINITIONS:
		var count_label := item_icons.get_node_or_null("%s/Count" % item_id) as Label
		if count_label:
			count_label.text = "×%d" % inventory.get(item_id, 0)
	_refresh_construction_guide(player_idx, inventory)

func _get_inventory_total(inventory: Dictionary) -> int:
	var total := 0
	for item_count in inventory.values():
		total += int(item_count)
	return total

func update_all_player_panels() -> void:
	for i in range(GameManager.players.size()):
		if i < player_panel_nodes.size():
			var p_data = GameManager.players[i]
			var panel = player_panel_nodes[i]
			var stat_lbl = panel.find_child("StatLabel", true, false)
			if stat_lbl:
				var shield_tag = "  ·  방패" if p_data.get("shield", false) else ""
				var energy_rank := 1
				for other in GameManager.players:
					if int(other.get("energy", 0)) > int(p_data.get("energy", 0)): energy_rank += 1
				stat_lbl.text = "에너지 %d  ·  현재 %d위\nSP %d  ·  %d번 칸%s" % [p_data.get("energy", 0), energy_rank, p_data.get("skill_energy", 0), p_data["position"], shield_tag]
				panel.tooltip_text = "현재 에너지 순위 · 종료 시 이동 보상이 합산됩니다. 클릭하면 상세 상태를 볼 수 있어요."
			var name_label := panel.find_child("NameLabel", true, false) as Label
			if name_label:
				name_label.text = str(p_data.get("name", "")) + (" · 나" if i == _local_player_index() else "")
			var turn_marker = panel.find_child("TurnMarker", true, false)
				
			# 현재 턴 플레이어는 밝은 초록 골드 테두리 및 펄스
			var is_current = (i == GameManager.current_turn_idx)
			var sb = panel.get_theme_stylebox("panel") as StyleBoxFlat
			if sb:
				var player_color: Color = p_data.get("char_color", Color(0.4, 0.5, 0.6))
				if is_current:
					sb.bg_color = Color("1b3b43")
					sb.border_color = UI.GOLD
					sb.set_border_width_all(3)
					panel.modulate = Color.WHITE
				else:
					sb.bg_color = Color("102832")
					sb.border_color = player_color.darkened(0.25)
					sb.set_border_width_all(2)
					panel.modulate = Color(0.78, 0.84, 0.88)
			if turn_marker:
				turn_marker.visible = is_current
	_refresh_special_skill_button()

func _on_turn_changed(turn_idx: int) -> void:
	_cancel_special_skill_targeting()
	update_all_player_panels()
	var cur_p = GameManager.players[turn_idx]
	var local_idx := _local_player_index()
	if local_idx >= 0 and local_idx < GameManager.players.size():
		_update_inventory(local_idx, GameManager.players[local_idx].get("inventory", {}))
	_update_kingdom_mission(GameManager.projects_built, GameManager.CONSTRUCTION_PROJECTS.size(), GameManager.kingdom_health)
	var is_my_turn = (turn_idx == local_idx and not cur_p["is_ai"])
	if turn_prompt_label:
		if is_my_turn:
			turn_prompt_label.text = "내 턴  •  오른쪽 주사위 또는 특수기술을 선택하세요"
			turn_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.32))
		else:
			turn_prompt_label.text = "%s의 턴  ·  다음 건설 목표를 골라보세요" % cur_p["name"]
			turn_prompt_label.add_theme_color_override("font_color", Color(0.48, 0.9, 0.86))
		_animate_turn_prompt()
	_refresh_primary_action_controls()

func _on_center_dice_pressed() -> void:
	var local_idx := _local_player_index()
	if not GameManager or GameManager.current_turn_idx != local_idx or GameManager.current_state != GameManager.TurnState.WAIT_ACTION:
		return
	_set_center_dice_visible(true, false)
	if turn_prompt_label:
		turn_prompt_label.text = "오른쪽 주사위가 회전합니다!"
	if NetworkManager.is_online:
		NetworkManager.request_roll_dice(local_idx)
	else:
		GameManager.execute_roll_dice(local_idx)

func _on_player_moved(_p_idx: int, _from_t: int, _to_t: int) -> void:
	update_all_player_panels()

func _on_player_state_changed(_p_idx: int) -> void:
	update_all_player_panels()
	_refresh_special_skill_button()
	_refresh_primary_action_controls()

func _on_dice_rolled(_p_idx: int, val: int) -> void:
	if not dice_value_label:
		return
	_cancel_special_skill_targeting()
	dice_value_label.add_theme_color_override("font_color", UI.GOLD)
	# 화면 중앙에서 0.7초간 눈금과 회전을 바꾸고 결과를 공개한 뒤,
	# GameManager의 1.1초 굴림 시간이 끝나는 순간 주사위를 숨깁니다.
	_set_center_dice_visible(true, false)
	if dice_tween and dice_tween.is_valid():
		dice_tween.kill()
	dice_face.pivot_offset = dice_face.size * 0.5
	dice_face.rotation = 0.0
	dice_face.scale = Vector2.ONE
	dice_tween = create_tween()
	for frame in range(7):
		var rolling_value := ((val + frame * 3) % 6) + 1
		dice_tween.tween_callback(_set_dice_roll_frame.bind(rolling_value))
		dice_tween.tween_property(dice_face, "rotation", PI * 0.5, 0.10).as_relative().set_trans(Tween.TRANS_QUAD)
	dice_tween.tween_callback(_show_dice_result.bind(val))
	dice_tween.tween_property(dice_face, "scale", Vector2(1.18, 1.18), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	dice_tween.tween_property(dice_face, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dice_tween.tween_interval(0.14)
	dice_tween.tween_callback(_set_center_dice_visible.bind(false, false))

func _on_dice_input_time_changed(player_idx: int, remaining_seconds: int) -> void:
	if player_idx != _local_player_index() or not dice_value_label or not GameManager or GameManager.current_state != GameManager.TurnState.WAIT_ACTION:
		return
	dice_value_label.text = "클릭해서 굴리기  ·  %d초" % maxi(remaining_seconds, 0)
	dice_value_label.add_theme_color_override("font_color", UI.DANGER if remaining_seconds <= 3 else UI.GOLD)

func _set_dice_roll_frame(rolling_value: int) -> void:
	dice_face.value = rolling_value
	dice_value_label.text = "굴리는 중  ·  %d" % rolling_value

func _show_dice_result(value: int) -> void:
	dice_face.rotation = 0.0
	dice_face.value = value
	dice_value_label.text = "결과  ·  %d" % value

func _set_center_dice_visible(should_show: bool, clickable: bool) -> void:
	if center_dice_panel:
		center_dice_panel.visible = should_show
	if center_dice_button:
		center_dice_button.visible = should_show
		center_dice_button.disabled = not clickable
	if should_show and clickable:
		dice_face.rotation = 0.0
		dice_face.scale = Vector2.ONE
		var remaining_seconds := ceili(GameManager.dice_input_time_remaining) if GameManager else 20
		dice_value_label.text = "클릭해서 굴리기  ·  %d초" % maxi(remaining_seconds, 0)
		dice_value_label.add_theme_color_override("font_color", UI.DANGER if remaining_seconds <= 3 else UI.GOLD)

func _on_status_message_posted(msg: String) -> void:
	if status_ticker_label:
		status_ticker_label.text = msg
	_show_event_banner(msg)

func _on_game_over(rankings: Array) -> void:
	_hide_lap_reward_panel()
	_set_center_dice_visible(false, false)
	_set_village_construction_controls(false)
	if victory_modal:
		victory_modal.visible = false
	if victory_dimmer:
		victory_dimmer.visible = false
	if victory_title:
		victory_title.text = "왕국 복원 성공!" if GameManager.kingdom_recovered else "왕국 복원 미달 · 다음 도전 준비"
	if rescue_story_label:
		rescue_story_label.visible = false
	if victory_rankings_label:
		victory_rankings_label.visible = false
	_update_kingdom_visual(GameManager.kingdom_health)
	_refresh_built_project_images()
	_refresh_ranking_cards(rankings)
	_play_ending_cinematic(GameManager.kingdom_recovered, rankings)

func _play_ending_cinematic(is_success: bool, rankings: Array) -> void:
	if is_instance_valid(ending_cinematic):
		ending_cinematic.queue_free()
	ending_cinematic = ENDING_CINEMATIC.new()
	ending_cinematic.name = "EndingCinematic"
	ending_cinematic.setup(is_success, GameManager.kingdom_health, GameManager.VILLAGE_RECOVERY_TARGET)
	ending_cinematic.animation_finished.connect(_show_game_over_results.bind(rankings.duplicate(true)), CONNECT_ONE_SHOT)
	add_child(ending_cinematic)

func _show_game_over_results(_rankings: Array) -> void:
	ending_cinematic = null
	if not victory_modal:
		return
	if victory_dimmer:
		victory_dimmer.visible = true
	victory_modal.visible = true
	victory_modal.modulate = Color(1, 1, 1, 0)
	victory_modal.scale = Vector2(0.92, 0.92)
	victory_modal.pivot_offset = victory_modal.size / 2.0
	var modal_tween = create_tween().set_parallel(true)
	modal_tween.tween_property(victory_modal, "modulate", Color.WHITE, 0.25)
	modal_tween.tween_property(victory_modal, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_village_construction_started(_inventories: Array) -> void:
	_hide_lap_reward_panel()
	if not victory_modal:
		return
	if victory_dimmer:
		victory_dimmer.visible = true
	victory_modal.visible = true
	victory_modal.modulate = Color.WHITE
	victory_modal.scale = Vector2.ONE
	if victory_title:
		victory_title.text = "친환경 마을 건설"
	if rescue_story_label:
		rescue_story_label.visible = false
	if save_status_label:
		save_status_label.text = ""
	_set_village_construction_controls(true)
	_update_kingdom_visual(GameManager.kingdom_health)
	_refresh_built_project_images()
	_refresh_construction_choices()

func _on_village_construction_changed(_inventories: Array, _projects_built: int, _health: int) -> void:
	_update_kingdom_visual(GameManager.kingdom_health)
	_refresh_built_project_images()
	_refresh_construction_choices()

func _set_village_construction_controls(is_construction_phase: bool) -> void:
	if village_map:
		village_map.set_drop_enabled(is_construction_phase)
	if build_instruction_label:
		build_instruction_label.visible = is_construction_phase
	if construction_list:
		construction_list.visible = is_construction_phase
	if evaluate_button:
		evaluate_button.visible = is_construction_phase
		evaluate_button.disabled = is_construction_phase and NetworkManager.is_online and not NetworkManager.is_host
		evaluate_button.tooltip_text = "방장이 공동 마을의 완성도를 확인합니다." if evaluate_button.disabled else "현재 공동 마을의 완성도를 확인합니다."
	if victory_rankings_label:
		victory_rankings_label.visible = false
	if rankings_container:
		rankings_container.visible = not is_construction_phase
	if save_village_button:
		save_village_button.visible = not is_construction_phase
	if save_status_label:
		save_status_label.visible = not is_construction_phase
	if lobby_return_button:
		lobby_return_button.visible = not is_construction_phase

func _refresh_construction_choices() -> void:
	if not construction_list or not GameManager.village_construction_active:
		return
	for child in construction_list.get_children():
		construction_list.remove_child(child)
		child.queue_free()
	var very_compact_cards := GameManager.CONSTRUCTION_PROJECTS.size() > 7
	var ultra_compact_cards := GameManager.CONSTRUCTION_PROJECTS.size() > 8
	construction_list.add_theme_constant_override("separation", 4 if very_compact_cards else 6)
	for project_index in range(GameManager.CONSTRUCTION_PROJECTS.size()):
		var project: Dictionary = GameManager.CONSTRUCTION_PROJECTS[project_index]
		var build_button: Button = VILLAGE_DRAG_CARD.new()
		var compact_cards := GameManager.CONSTRUCTION_PROJECTS.size() > 4
		build_button.custom_minimum_size = Vector2(286, 46 if ultra_compact_cards else (58 if very_compact_cards else (66 if compact_cards else 116)))
		build_button.text = ""
		build_button.clip_contents = true
		var already_built := project_index in GameManager.built_project_ids
		var builders: Array[int] = []
		if not already_built:
			builders = GameManager.get_project_builder_indices(project_index)
		var builder_idx := builders[0] if not builders.is_empty() else -1
		# 온라인에서는 각 화면에서 자기 개인 재료로만 건설을 요청할 수 있습니다.
		if NetworkManager.is_online:
			var local_idx := _local_player_index()
			builder_idx = local_idx if local_idx in builders else -1
		build_button.tooltip_text = "%s · 공동 친환경 지수 +%d · 적합 지형: %s · 마을 지도 위로 끌어 배치하세요." % [project["name"], int(project["health"]), project.get("terrain_label", "지정 구역")]
		_apply_secondary_button_style(build_button)

		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var card_margin := 2 if ultra_compact_cards else (4 if compact_cards else 8)
		margin.add_theme_constant_override("margin_left", card_margin)
		margin.add_theme_constant_override("margin_top", 3 if compact_cards else 7)
		margin.add_theme_constant_override("margin_right", card_margin)
		margin.add_theme_constant_override("margin_bottom", 3 if compact_cards else 7)
		build_button.add_child(margin)
		var content := HBoxContainer.new()
		content.add_theme_constant_override("separation", 7)
		margin.add_child(content)

		# 각 시설은 투명 PNG를 같은 크기의 전용 프레임 안에 넣어, 원본 이미지의 여백이 달라도
		# 카드 왼쪽에서 흔들리거나 제목 줄과 겹치지 않도록 한다.
		var thumbnail_center := CenterContainer.new()
		thumbnail_center.custom_minimum_size = Vector2(42, 38) if ultra_compact_cards else (Vector2(56, 50) if very_compact_cards else Vector2(64, 58))
		thumbnail_center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_child(thumbnail_center)
		var compact_image_size := Vector2(38, 36) if ultra_compact_cards else (Vector2(48, 46) if very_compact_cards else Vector2(54, 52))
		var building_image := _create_asset_texture_rect(str(project.get("image", "")), compact_image_size if compact_cards else Vector2(92, 92))
		building_image.tooltip_text = project["name"]
		building_image.modulate = Color(0.55, 0.62, 0.62, 0.72) if builder_idx < 0 and not already_built else Color.WHITE
		thumbnail_center.add_child(building_image)
		build_button.call("configure", project_index, builder_idx, building_image.texture, not already_built and builder_idx >= 0)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_child(info)
		var project_label := Label.new()
		var category_prefix := "%s · " % str(project.get("category", "")) if project.has("category") else ""
		project_label.text = ("완공 · " if already_built else "") + category_prefix + str(project["name"]) + "  +%d%%" % int(project["health"])
		project_label.add_theme_font_size_override("font_size", 11 if ultra_compact_cards else (13 if compact_cards else 15))
		project_label.add_theme_color_override("font_color", UI.GOLD if builder_idx >= 0 or already_built else UI.TEXT_MUTED)
		project_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.add_child(project_label)

		var requirements_row := HBoxContainer.new()
		requirements_row.add_theme_constant_override("separation", 4 if ultra_compact_cards else 7)
		requirements_row.alignment = BoxContainer.ALIGNMENT_CENTER
		info.add_child(requirements_row)
		for requirement_item_id in project["requirements"]:
			var item_id := str(requirement_item_id)
			var item: Dictionary = GameManager.ITEM_DEFINITIONS[item_id]
			var requirement_box := VBoxContainer.new()
			requirement_box.custom_minimum_size = Vector2(24 if ultra_compact_cards else (30 if compact_cards else 42), 0)
			requirement_box.tooltip_text = item["name"]
			requirements_row.add_child(requirement_box)
			requirement_box.add_child(_create_asset_texture_rect(str(item["asset"]), Vector2(18, 18) if ultra_compact_cards else (Vector2(24, 24) if compact_cards else Vector2(38, 38))))
			var amount_label := Label.new()
			amount_label.text = "×%d" % int(project["requirements"][item_id])
			amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			amount_label.add_theme_font_size_override("font_size", 9 if ultra_compact_cards else (10 if compact_cards else 13))
			amount_label.add_theme_color_override("font_color", UI.TEXT_MUTED)
			requirement_box.add_child(amount_label)

		var completed_owner_idx := int(GameManager.built_project_owners.get(project_index, -1))
		var owner_label := Label.new()
		if already_built and completed_owner_idx >= 0 and completed_owner_idx < GameManager.players.size():
			owner_label.text = "완공 · " + str(GameManager.players[completed_owner_idx]["name"])
		else:
			owner_label.text = str(GameManager.players[builder_idx]["name"]) if builder_idx >= 0 else ("완공" if already_built else "재료 부족")
		owner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		owner_label.add_theme_font_size_override("font_size", 10 if compact_cards else 12)
		owner_label.add_theme_color_override("font_color", UI.SUCCESS if builder_idx >= 0 or already_built else UI.DANGER)
		owner_label.visible = not ultra_compact_cards
		info.add_child(owner_label)
		_set_descendant_mouse_filter_ignore(margin)
		construction_list.add_child(build_button)
	if build_instruction_label:
		build_instruction_label.text = "시설 카드를 마을 지도 위 원하는 곳으로 끌어놓으세요.\n배치할 때 한 플레이어의 개인 재료가 사용됩니다."

func _create_asset_texture_rect(asset_path: String, minimum_size: Vector2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = minimum_size
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not asset_path.is_empty() and ResourceLoader.exists(asset_path):
		texture_rect.texture = load(asset_path)
	return texture_rect

func _update_kingdom_visual(health: int) -> void:
	if kingdom_health_bar:
		kingdom_health_bar.value = clampi(health, 0, 100)
	if energy_resolution_label:
		var target := GameManager.VILLAGE_RECOVERY_TARGET
		if health >= target:
			energy_resolution_label.text = "친환경 에너지 지수 %d / %d  ·  요정마을 에너지 문제 해결 완료" % [health, target]
			energy_resolution_label.add_theme_color_override("font_color", Color("a8ffe0"))
		else:
			energy_resolution_label.text = "친환경 에너지 지수 %d / %d  ·  문제 해결까지 %d" % [health, target, target - health]
			energy_resolution_label.add_theme_color_override("font_color", Color("fff0a4"))
	if village_map:
		village_map.set_environment_health(health)
		# 지도 중앙을 가리는 장시간 툴팁 대신 상단 안내 문구로 정보를 전달합니다.
		village_map.tooltip_text = ""

func _refresh_built_project_images() -> void:
	if not village_map:
		return
	village_map.sync_projects(GameManager.CONSTRUCTION_PROJECTS, GameManager.built_project_ids, GameManager.built_project_placements, GameManager.built_project_owners, GameManager.players, GameManager.kingdom_health)

func _refresh_ranking_cards(rankings: Array) -> void:
	if not rankings_container:
		return
	for child in rankings_container.get_children():
		rankings_container.remove_child(child)
		child.queue_free()
	var rank_colors: Array[Color] = [Color("c9952f"), Color("7c98aa"), Color("a86f49"), Color("315f58")]
	for rank_index in range(rankings.size()):
		var player: Dictionary = rankings[rank_index]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(322, 112)
		var rank_color: Color = rank_colors[min(rank_index, rank_colors.size() - 1)]
		var panel_style := UI.padded_panel(Color("112c36"), rank_color, 8.0, 12)
		panel_style.shadow_size = 5
		panel.add_theme_stylebox_override("panel", panel_style)
		rankings_container.add_child(panel)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_top", 7)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_bottom", 7)
		panel.add_child(margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		margin.add_child(row)
		var portrait := _create_asset_texture_rect(str(player.get("char_icon", "")), Vector2(78, 78))
		portrait.tooltip_text = player.get("name", "플레이어")
		row.add_child(portrait)
		var rank_badge := Label.new()
		rank_badge.custom_minimum_size = Vector2(32, 0)
		rank_badge.text = str(rank_index + 1)
		rank_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rank_badge.add_theme_font_size_override("font_size", 28)
		rank_badge.add_theme_color_override("font_color", rank_color.lightened(0.28))
		row.add_child(rank_badge)
		var score_label := Label.new()
		score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 재료 획득 공헌과 실제 발전소 완공 수를 분리해, BUILD가 완공 수로 오해되지 않게 합니다.
		score_label.text = "%s\n⚡ 순위 에너지 %d  •  이동 %d칸 (+%d)\n퀴즈 %d  •  재료 %d  •  완공 %d" % [player.get("name", "플레이어"), player.get("energy", 0), player.get("total_tiles_moved", 0), player.get("movement_reward_energy", 0), player.get("quiz_correct", 0), player.get("construction_contribution", 0), player.get("project_completion_bonus", 0)]
		score_label.tooltip_text = "이동 보상: 누적 이동 거리 1위부터 순서대로 에너지 120·80·40·20을 받습니다. 최종 순위는 보상까지 포함한 일반 에너지 순서입니다."
		score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		score_label.add_theme_font_size_override("font_size", 14)
		score_label.add_theme_color_override("font_color", Color("effff9"))
		score_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(score_label)

func _on_build_project_pressed(project_index: int, player_idx: int) -> void:
	if NetworkManager.is_online:
		NetworkManager.request_build_project(project_index, player_idx, Vector2(-1, -1))
		return
	if GameManager.build_village_project(project_index, player_idx):
		_refresh_construction_choices()

func _on_village_project_dropped(project_index: int, player_idx: int, map_position: Vector2) -> void:
	if NetworkManager.is_online:
		NetworkManager.request_build_project(project_index, player_idx, map_position)
		return
	if not GameManager.build_village_project(project_index, player_idx, map_position):
		village_map.cancel_project_placement(project_index)
		_show_event_banner("이 시설은 지금 배치할 수 없습니다. 개인 재료를 확인하세요.")

func _on_village_project_drop_rejected(message: String) -> void:
	_show_event_banner("이 시설은 %s" % message)

func _on_evaluate_village_pressed() -> void:
	if NetworkManager.is_online:
		if NetworkManager.is_host:
			NetworkManager.request_evaluate_village()
		else:
			_show_event_banner("마을 완성도 확인은 방장이 진행합니다.")
		return
	GameManager.evaluate_village()

func _on_save_village_pressed() -> void:
	if not village_map:
		if save_status_label:
			save_status_label.text = "저장할 마을 지도를 찾지 못했습니다."
		return
	if save_village_button:
		save_village_button.disabled = true
	if save_status_label:
		save_status_label.text = "마을 이미지를 저장하고 있어요..."
	var viewport_image := get_viewport().get_texture().get_image()
	var map_rect: Rect2 = village_map.get_global_rect()
	var capture_rect := Rect2i(Vector2i(map_rect.position), Vector2i(map_rect.size))
	capture_rect = capture_rect.intersection(Rect2i(Vector2i.ZERO, viewport_image.get_size()))
	var image := viewport_image.get_region(capture_rect)
	var save_path := "user://energy_fairy_village_%d.png" % int(Time.get_unix_time_from_system())
	var absolute_save_path := ProjectSettings.globalize_path(save_path)
	var result := image.save_png(absolute_save_path)
	if save_status_label:
		save_status_label.text = "저장 완료: %s" % absolute_save_path if result == OK else "이미지 저장에 실패했습니다."
	if save_village_button:
		save_village_button.disabled = false

func _on_return_to_lobby() -> void:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node and main_node.has_method("switch_to_lobby"):
		main_node.switch_to_lobby()

func _apply_commercial_ui() -> void:
	var top_backdrop := get_node_or_null("TopBackdrop") as ColorRect
	if top_backdrop:
		top_backdrop.color = Color(0.018, 0.065, 0.09, 0.96)
	var status_panel := get_node_or_null("TopHUD/StatusTicker") as PanelContainer
	if status_panel:
		status_panel.add_theme_stylebox_override("panel", UI.padded_panel(Color("0d2834"), Color("285465"), 5.0, 8))
	var mission_panel := get_node_or_null("MissionPanel") as PanelContainer
	if mission_panel:
		mission_panel.add_theme_stylebox_override("panel", UI.padded_panel(Color(0.035, 0.13, 0.17, 0.96), UI.TEAL_DARK, 10.0, 12))
	if game_time_panel:
		game_time_panel.add_theme_stylebox_override("panel", UI.padded_panel(Color("0d2834f2"), UI.GOLD_DARK, 10.0, 10))
	var turn_plate := get_node_or_null("TurnPromptPlate") as Panel
	if turn_plate:
		turn_plate.add_theme_stylebox_override("panel", UI.panel(Color(0.025, 0.12, 0.16, 0.94), UI.GOLD_DARK, 12, 2, 6))
	var dice_panel := get_node_or_null("CenterDicePanel") as PanelContainer
	if dice_panel:
		dice_panel.add_theme_stylebox_override("panel", UI.padded_panel(Color("122f3b"), Color("4d7280"), 8.0, 11))
	if event_banner:
		event_banner.add_theme_stylebox_override("panel", UI.padded_panel(Color(0.05, 0.19, 0.24, 0.98), UI.TEAL, 12.0, 12))
	if victory_modal:
		victory_modal.add_theme_stylebox_override("panel", UI.padded_panel(Color("102d37"), UI.TEAL_DARK, 18.0, 18))
	var preview_frame := get_node_or_null("VictoryModal/KingdomPreviewFrame") as Panel
	if preview_frame:
		preview_frame.add_theme_stylebox_override("panel", UI.panel(Color("071b24"), Color("3f6f79"), 12, 2, 6))
	var construction_pane := get_node_or_null("VictoryModal/ConstructionPane") as Panel
	if construction_pane:
		construction_pane.add_theme_stylebox_override("panel", UI.panel(Color("0a222c"), Color("315e69"), 12, 1, 4))
	if kingdom_progress_bar:
		kingdom_progress_bar.add_theme_stylebox_override("background", UI.progress_background())
		kingdom_progress_bar.add_theme_stylebox_override("fill", UI.progress_fill(UI.TEAL))
	if kingdom_health_bar:
		kingdom_health_bar.add_theme_stylebox_override("background", UI.progress_background())
		kingdom_health_bar.add_theme_stylebox_override("fill", UI.progress_fill(UI.GOLD))
	for utility_button in [help_button, sound_button, info_button, zoom_in_button, zoom_out_button]:
		if utility_button:
			UI.apply_secondary_button(utility_button, Color("72cfe0"))

func _apply_secondary_button_style(button: Button) -> void:
	UI.apply_secondary_button(button, UI.GOLD)

func _make_button_texture_style(texture: Texture2D, tint: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 12.0
	style.texture_margin_top = 8.0
	style.texture_margin_right = 12.0
	style.texture_margin_bottom = 8.0
	style.content_margin_left = 14.0
	style.content_margin_top = 7.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 7.0
	style.modulate_color = tint
	return style

func _show_event_banner(message: String) -> void:
	if not event_banner or not event_banner_label:
		return
	if event_banner_tween and event_banner_tween.is_valid():
		event_banner_tween.kill()
	event_banner.visible = true
	event_banner_label.text = message
	event_banner.modulate = Color(1, 1, 1, 0)
	event_banner.scale = Vector2(0.9, 0.9)
	event_banner.pivot_offset = event_banner.size / 2.0
	event_banner_tween = create_tween()
	event_banner_tween.set_parallel(true)
	event_banner_tween.tween_property(event_banner, "modulate", Color.WHITE, 0.16)
	event_banner_tween.tween_property(event_banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	event_banner_tween.chain().tween_interval(1.25)
	event_banner_tween.chain().tween_property(event_banner, "modulate", Color(1, 1, 1, 0), 0.24)
	event_banner_tween.chain().tween_callback(func(): event_banner.visible = false)

func _animate_turn_prompt() -> void:
	if not turn_prompt_label:
		return
	turn_prompt_label.scale = Vector2(0.96, 0.96)
	turn_prompt_label.pivot_offset = turn_prompt_label.size / 2.0
	create_tween().tween_property(turn_prompt_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_help_pressed() -> void:
	adventure_planner.replay_tutorial()
	_show_event_banner("말 이동 중: 자동 추적·확대  •  왼쪽 드래그: 카메라 이동  •  오른쪽 드래그: 회전  •  휠: 확대/축소")

func _on_sound_pressed() -> void:
	sound_muted = not sound_muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), sound_muted)
	sound_button.text = "×" if sound_muted else "♪"
	_show_event_banner("효과음을 껐습니다." if sound_muted else "효과음을 켰습니다.")

func _on_info_pressed() -> void:
	_show_event_banner("🏗️ 공동 건설 %d / %d  •  친환경 에너지 지수 %d / %d  •  ROUND %d" % [GameManager.projects_built, GameManager.CONSTRUCTION_PROJECTS.size(), GameManager.kingdom_health, GameManager.VILLAGE_RECOVERY_TARGET, GameManager.total_turns / 4 + 1])

func _on_zoom_in_pressed() -> void:
	board_zoom_requested.emit(1.0)

func _on_zoom_out_pressed() -> void:
	board_zoom_requested.emit(-1.0)
