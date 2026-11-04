extends CanvasLayer
class_name GuidedTutorial

## A disposable practice session using the real board, quiz, arcade and building
## actions. Progress changes only when those actions succeed, never on a timer.
signal leave_requested
signal adventure_requested

const UI = preload("res://scripts/ui/CommercialUI.gd")
var active := false
var stage := ""
var board: Node
var goal_index := 0
var root_control: Control
var coach: PanelContainer
var title_label: Label
var body_label: Label
var stage_label: Label
var stage_badge: PanelContainer
var action_button: Button
var exit_button: Button
var focus_outline: Panel
var focused_control: Control
var last_results: Array = []

func _ready() -> void:
	layer = 40
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	focus_outline = Panel.new()
	focus_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_outline.add_theme_stylebox_override("panel", UI.panel(Color(0, 0, 0, 0), UI.GOLD, 14, 3, 0))
	root_control.add_child(focus_outline)
	stage_label = _label("", 18, UI.GOLD)
	stage_badge = PanelContainer.new()
	stage_badge.position = Vector2(18, 5)
	stage_badge.add_theme_stylebox_override("panel", UI.padded_panel(UI.INK, UI.TEAL_DARK, 5, 6))
	stage_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(stage_badge)
	stage_badge.add_child(stage_label)
	exit_button = Button.new()
	exit_button.text = "연습 나가기"
	root_control.add_child(exit_button)
	exit_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	exit_button.offset_left = -190
	exit_button.offset_right = -22
	exit_button.offset_top = 5
	exit_button.offset_bottom = 47
	exit_button.add_theme_font_size_override("font_size", 18)
	UI.apply_secondary_button(exit_button)
	exit_button.pressed.connect(func(): leave_requested.emit())
	coach = PanelContainer.new()
	coach.position = Vector2(22, 158)
	coach.custom_minimum_size.x = 420
	coach.add_theme_stylebox_override("panel", UI.padded_panel(UI.INK, UI.TEAL, 18, 16))
	root_control.add_child(coach)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	coach.add_child(column)
	title_label = _label("", 24, UI.GOLD)
	column.add_child(title_label)
	body_label = _label("", 21)
	body_label.custom_minimum_size.x = 384
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body_label)
	action_button = Button.new()
	action_button.custom_minimum_size.y = 46
	action_button.add_theme_font_size_override("font_size", 20)
	UI.apply_primary_button(action_button)
	action_button.pressed.connect(_advance)
	column.add_child(action_button)
	GameManager.tutorial_turn_finished.connect(_on_turn_finished)
	GameManager.minigame_finished.connect(_on_minigame_finished)
	GameManager.village_construction_changed.connect(_on_build_changed)
	GameManager.component_choice_changed.connect(_on_component_changed)
	GameManager.village_construction_started.connect(_on_construction_started)
	GameManager.energy_trial_changed.connect(_on_energy_trial_changed)
	hide()

func _label(value: String, font_size: int, color: Color = UI.TEXT) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func begin(game_board: Node) -> void:
	board = game_board
	active = true
	goal_index = 0
	last_results.clear()
	if not board.hud.adventure_planner.goal_selected.is_connected(_on_goal_selected):
		board.hud.adventure_planner.goal_selected.connect(_on_goal_selected)
	if not board.quiz_modal.review_completed.is_connected(_on_quiz_reviewed):
		board.quiz_modal.review_completed.connect(_on_quiz_reviewed)
	show()
	_set_stage("dice", "1 / 7  주사위와 이동", "주사위를 눌러 재료 칸으로 이동하세요.")
	focused_control = board.hud.center_dice_button
	board.hud.center_dice_button.grab_focus()

func stop() -> void:
	active = false
	stage = ""
	focused_control = null
	focus_outline.hide()
	hide()

func _set_stage(value: String, title: String, instruction: String, action: String = "") -> void:
	stage = value
	GameManager.guided_tutorial_step = value
	stage_label.text = "튜토리얼  ·  " + title
	title_label.text = title
	body_label.text = instruction
	coach.position = Vector2(22, 158)
	coach.custom_minimum_size.x = 420
	body_label.custom_minimum_size.x = 384
	coach.size = Vector2(420, 0)
	coach.show()
	action_button.text = action
	action_button.visible = not action.is_empty()
	action_button.disabled = false
	focused_control = null
	if action_button.visible:
		action_button.grab_focus()

func _process(_delta: float) -> void:
	if not active:
		return
	# One instruction surface at a time. The actual quiz/arcade guide owns the
	# screen while in use; this coach never blocks its keys or answer choices.
	var modal_open: bool = board.quiz_modal.visible or board.minigame_modal.visible or board.hud.is_blocking_overlay_visible()
	var catalog_open: bool = board.hud.adventure_planner.catalog.visible
	coach.visible = not modal_open and not catalog_open
	stage_badge.visible = modal_open or stage == "build"
	if modal_open or stage == "build" or stage == "complete" or catalog_open:
		exit_button.position = Vector2(1090, 5)
	else:
		exit_button.position = Vector2(22, 590)
	focus_outline.visible = coach.visible and is_instance_valid(focused_control) and focused_control.is_visible_in_tree()
	if focus_outline.visible:
		var rect := focused_control.get_global_rect().grow(5)
		focus_outline.position = rect.position
		focus_outline.size = rect.size
	board.hud.game_time_label.text = "연습 모드"
	board.hud.turn_prompt_label.visible = false
	if stage != "dice":
		board.hud.center_dice_button.disabled = true
	if stage == "build":
		coach.hide()
		board.hud.build_instruction_label.text = "태양광 발전소와 에너지 저장소를 지어요. 시설 선택 → 빛나는 칸 클릭"

func _on_turn_finished() -> void:
	if not active:
		return
	if stage == "dice":
		_set_stage("materials", "2 / 7  재료와 목표", "‘건설 도감’을 열고 만들고 싶은 시설을 골라요.")
		focused_control = board.hud.adventure_planner.catalog_open_button
		focused_control.grab_focus()
	elif stage == "reward":
		action_button.disabled = false
		board.minigame_modal.cancel_minigame()
		coach.show()
		action_button.grab_focus()

func _on_goal_selected(index: int) -> void:
	if not active or stage != "materials":
		return
	goal_index = index
	_set_stage("quiz_intro", "2 / 7  목표 선택", "%s에 쓸 재료를 모아 봐요." % GameManager.CONSTRUCTION_PROJECTS[index]["name"], "퀴즈 칸으로 이동")

func _on_quiz_reviewed() -> void:
	if not active or stage != "quiz":
		return
	if GameManager.get_component_choice_state().get("choices", {}).has(0):
		_set_stage("component", "3 / 7  필요한 부품", "목표 시설에 필요한 부품을 하나 골라요.")
	else:
		_set_stage("quiz_intro", "3 / 7  퀴즈와 부품", "정답을 맞히고 필요한 부품을 골라요.", "다시 풀기")

func _on_component_changed(state: Dictionary) -> void:
	if active and stage == "component" and not state.get("choices", {}).has(0):
		_show_mini_intro()

func _show_mini_intro() -> void:
	_set_stage("mini_intro", "4 / 7  함께 미니게임", "컴퓨터 플레이어 3명과 30초 동안 도전해요.", "미니게임 연습 시작")

func _on_minigame_finished(results: Array) -> void:
	if not active or stage != "mini":
		return
	last_results = results.duplicate(true)
	var reward := 0
	for result in results:
		if int(result.get("player_idx", -1)) == 0:
			reward = int(result.get("reward", 0))
	_set_stage("reward", "4 / 7  미니게임 완료", "보너스 에너지 +%d\n1~4위 보상은 20·10·5·1이에요." % reward, "함께 지을 시설 고르기")
	action_button.disabled = true

func _advance() -> void:
	if not active or action_button.disabled:
		return
	match stage:
		"quiz_intro":
			_set_stage("quiz", "3 / 7  퀴즈와 부품", "답을 고르고 이유를 확인하세요.")
			GameManager.current_state = GameManager.TurnState.PLAYER_MOVING
			GameManager.move_player_to(0, 4)
		"mini_intro":
			_set_stage("mini", "4 / 7  미니게임", "W / S 또는 ↑ / ↓로 공급을 조절해 도시의 수요에 맞춰요.")
			GameManager._start_minigame(0, "grid_balance")
		"reward":
			_set_stage("plan", "5 / 7  함께 계획", "짓고 싶은 시설을 추천하고 준비를 마쳐요.")
			var inventory: Dictionary = GameManager.players[0]["inventory"]
			for project in [0, 3]:
				for item_id in GameManager.CONSTRUCTION_PROJECTS[project]["requirements"]:
					inventory[item_id] = int(inventory.get(item_id, 0)) + int(GameManager.CONSTRUCTION_PROJECTS[project]["requirements"][item_id])
			GameManager._start_team_planning_phase()
		"trial_intro":
			_set_stage("trial", "7 / 7  낮과 밤의 전기", "낮에는 남는 전기를 저장하고 밤에는 꺼내 써요.")
			GameManager.finish_village_construction(0)
		"complete":
			adventure_requested.emit()

func _on_build_changed(_inventories: Array, projects: int, _health: int) -> void:
	if not active or stage != "build" or projects < 2 or not GameManager.built_project_owners.has(0) or not GameManager.built_project_owners.has(3):
		return
	_set_stage("trial_intro", "7 / 7  낮과 밤의 전기", "태양광 발전소와 저장소를 지었어요.\n낮에는 남는 전기를 저장하고,\n밤에는 배터리의 전기를 보내 보세요.", "전기 보내기 시작")
	coach.custom_minimum_size.x = 520
	body_label.custom_minimum_size.x = 484
	coach.position = Vector2(380, 218)
	board.hud.village_map.set_drop_enabled(false)

func _on_construction_started(_inventories: Array) -> void:
	if not active or stage != "plan": return
	_set_stage("build", "6 / 7  함께 건설", "태양광 발전소와 에너지 저장소를 지어요.")
	board.hud._refresh_construction_choices()
	if board.hud.construction_list.get_child_count() > 0:
		board.hud.construction_list.get_child(0).call_deferred("grab_focus")

func _on_energy_trial_changed(state: Dictionary) -> void:
	if not active or stage not in ["trial", "complete"]: return
	if str(state.get("phase", "")) == "complete":
		_set_stage("complete", "7 / 7  연습 완료", "낮에 저장한 전기는 밤에도 쓸 수 있어요.", "새 모험 시작")
		# The normal result owns the screen. In practice its confirmation starts
		# a fresh adventure, rather than saving or ranking the practice session.
		var learning: Control = board.hud.learning_village_ui
		learning.trial_retry_button.hide()
		learning.trial_confirm_button.text = "새 모험 시작"
		if not learning.trial_confirm_button.pressed.is_connected(_complete_trial_practice):
			for connection in learning.trial_confirm_button.pressed.get_connections():
				learning.trial_confirm_button.pressed.disconnect(connection["callable"])
			learning.trial_confirm_button.pressed.connect(_complete_trial_practice)

func _complete_trial_practice() -> void:
	adventure_requested.emit()
