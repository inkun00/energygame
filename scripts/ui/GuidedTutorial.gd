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
	_set_stage("dice", "1 / 5  주사위와 이동", "오른쪽 주사위를 눌러 보세요.\n연습에서는 1이 나와 재료 칸으로 이동해요.\n시간에 쫓기지 않고 천천히 해도 괜찮아요.")
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
	var modal_open: bool = board.quiz_modal.visible or board.minigame_modal.visible
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
		board.hud.build_instruction_label.text = "연습 5/5 · 시설 선택 → 빛나는 칸 클릭 · 팀 보유 / 필요"

func _on_turn_finished() -> void:
	if not active:
		return
	if stage == "dice":
		_set_stage("materials", "2 / 5  재료와 목표", "재료가 가방에 들어왔어요!\n왼쪽 아래 ‘건설 도감’을 열고, 만들고 싶은 시설의 ‘목표’ 버튼을 눌러 보세요.")
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
	_set_stage("quiz_intro", "2 / 5  목표 선택 완료", "%s의 재료를 확인했어요.\n실제 모험에서는 길에서 모은 재료를 친구들과 함께 써요.\n이번에는 퀴즈 칸으로 이동해 볼까요?" % GameManager.CONSTRUCTION_PROJECTS[index]["name"], "퀴즈 칸으로 이동")

func _on_quiz_reviewed() -> void:
	if not active or stage != "quiz":
		return
	_set_stage("mini_intro", "3 / 5  퀴즈 완료", "답을 고르고 이유까지 확인했어요.\n정답이면 에너지와 특수기술 SP를 받아요.\n다음은 AI 친구 3명과 함께 30초 미니게임을 해볼 거예요.", "미니게임 연습 시작")

func _on_minigame_finished(results: Array) -> void:
	if not active or stage != "mini":
		return
	last_results = results.duplicate(true)
	var reward := 0
	for result in results:
		if int(result.get("player_idx", -1)) == 0:
			reward = int(result.get("reward", 0))
	_set_stage("reward", "4 / 5  미니게임 완료", "이번 연습에서 보너스 에너지 %d를 얻었어요.\n목표 행동으로 점수를 얻으면 순위에 따라 20·10·5·1 에너지를 받아요.\n공동 1위 두 명이면 20·20·5·1이에요." % reward, "마을 건설 연습")
	action_button.disabled = true

func _advance() -> void:
	if not active or action_button.disabled:
		return
	match stage:
		"quiz_intro":
			_set_stage("quiz", "3 / 5  퀴즈", "퀴즈에서 답을 선택하고 해설을 읽어 보세요.")
			GameManager.current_state = GameManager.TurnState.PLAYER_MOVING
			GameManager.move_player_to(0, 4)
		"mini_intro":
			_set_stage("mini", "4 / 5  미니게임", "조작 안내를 읽고 준비 버튼을 누르세요.\nW / S 또는 ↑ / ↓로 공급을 조절해\n도시의 수요에 맞춰요.")
			GameManager._start_minigame(0, "grid_balance")
		"reward":
			_set_stage("build", "5 / 5  함께 건설", "연습용 재료로 시설을 지어 보세요.")
			var inventory: Dictionary = GameManager.players[0]["inventory"]
			for item_id in GameManager.CONSTRUCTION_PROJECTS[goal_index]["requirements"]:
				inventory[item_id] = maxi(int(inventory.get(item_id, 0)), int(GameManager.CONSTRUCTION_PROJECTS[goal_index]["requirements"][item_id]))
			GameManager._start_village_construction_phase()
			# The learner selects the card and places it on a valid pad through
			# exactly the same authoritative path as a normal game.
			if board.hud.construction_list.get_child_count() > 0:
				board.hud.construction_list.get_child(0).grab_focus()
		"complete":
			adventure_requested.emit()

func _on_build_changed(_inventories: Array, projects: int, _health: int) -> void:
	if not active or stage != "build" or projects < 1:
		return
	_set_stage("complete", "5 / 5  튜토리얼 완료!", "시설을 지어 마을 지수가 올랐어요!\n주사위로 이동하고 재료를 모아,\n친구들과 깨끗한 마을을 만들어요.\n\n이제 새 모험을 시작해 볼까요?", "새 모험 시작")
	coach.custom_minimum_size.x = 520
	body_label.custom_minimum_size.x = 484
	coach.position = Vector2(380, 218)
	board.hud.village_map.set_drop_enabled(false)
