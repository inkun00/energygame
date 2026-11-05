extends Control
class_name LearningVillageUI

signal stage_visibility_changed(blocking: bool)

const UI = preload("res://scripts/ui/CommercialUI.gd")
const EnergyVillageView = preload("res://scripts/ui/VillageEnergyView.gd")
const COMPONENT_PURPOSES := {
	"solar_panel": "햇빛을 전기로 바꿔요", "wind_blade": "바람을 받아 터빈을 돌려요",
	"battery": "남는 전기를 저장해요", "insulation": "집 안팎으로 열이 오가는 것을 줄여요",
	"smart_grid": "필요한 곳에 전기를 보내요", "hydro_turbine": "물의 힘으로 돌아 발전기를 움직여요",
	"geothermal_core": "땅속 열을 전달해요", "tidal_generator": "밀물과 썰물의 힘을 받아요",
	"reactor_control_core": "원자로의 반응을 조절해요", "recycled_composite": "버려진 자원을 다시 써요",
	"fast_charge_module": "전기 버스의 배터리를 충전해요"
}
const PROJECT_PURPOSES := [
	"낮에 햇빛으로 발전", "바람으로 발전", "필요한 전기 줄이기", "남는 전기 저장",
	"흐르는 물로 발전", "땅속 열로 발전", "밀물·썰물로 발전", "핵분열의 열로 발전",
	"재사용으로 자원 절약", "함께 타기 · 낮에는 버스 충전"
]

var screen := ""
var component_state: Dictionary = {}
var plan_state: Dictionary = {}
var trial_state: Dictionary = {}
var panel: PanelContainer
var column: VBoxContainer
var heading: Label
var subheading: Label
var timer_label: Label
var content: VBoxContainer
var footer: HBoxContainer
var inventory_label: Label
var option_buttons: Array[Button] = []
var plan_buttons: Array[Button] = []
var plan_player_labels: Array[Label] = []
var plan_recipe_labels: Array[Label] = []
var plan_ready_button: Button
var plan_grid: GridContainer
var mode_buttons: Dictionary = {}
var district_views: Array[Dictionary] = []
var facility_images: Array[TextureRect] = []
var trial_phase_bar: ProgressBar
var trial_message: Label
var trial_confirm_button: Button
var trial_retry_button: Button
var waiting_chip: PanelContainer
var waiting_label: Label
var shown_choice_token := -1
var shown_phase := ""
var last_blocking := false
var flow_clock := 0.0
var energy_village_view: Control

func _ready() -> void:
	name = "LearningVillageUI"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.01, 0.04, 0.06, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 52
	panel.offset_right = -52
	panel.offset_top = 55
	panel.offset_bottom = -30
	panel.add_theme_stylebox_override("panel", UI.padded_panel(UI.PANEL, UI.TEAL_DARK, 20, 18))
	add_child(panel)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	heading = _label("", 30, UI.GOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	timer_label = _label("", 24, UI.GOLD)
	header.add_child(timer_label)
	subheading = _label("", 20)
	subheading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subheading)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	column.add_child(content)
	inventory_label = _label("", 17, UI.TEXT_MUTED)
	inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(inventory_label)
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	column.add_child(footer)
	waiting_chip = PanelContainer.new()
	waiting_chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	waiting_chip.offset_left = 350
	waiting_chip.offset_right = -350
	waiting_chip.offset_top = -90
	waiting_chip.offset_bottom = -26
	waiting_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	waiting_chip.add_theme_stylebox_override("panel", UI.padded_panel(UI.INK, UI.TEAL_DARK, 12))
	add_child(waiting_chip)
	waiting_label = _label("", 20)
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	waiting_chip.add_child(waiting_label)
	GameManager.component_choice_changed.connect(_on_component_changed)
	GameManager.team_plan_changed.connect(_on_plan_changed)
	GameManager.energy_trial_changed.connect(_on_trial_changed)
	GameManager.player_inventory_changed.connect(func(_idx: int, _inventory: Dictionary): _refresh_inventory())
	GameManager.game_over.connect(func(_rankings: Array): reset())
	GameManager.village_construction_started.connect(func(_inventories: Array): _show_screen(""))
	restore_state()
	resized.connect(_fit_layout)

func _fit_layout() -> void:
	if is_instance_valid(plan_grid): plan_grid.columns = 2 if size.x < 1150 else 3
	var compact := size.y < 660
	column.add_theme_constant_override("separation", 8 if compact else 12)
	content.add_theme_constant_override("separation", 8 if compact else 12)
	heading.add_theme_font_size_override("font_size", 26 if compact else 30)
	panel.offset_top = 24 if screen == "trial" else 55
	panel.offset_bottom = -28 if screen == "trial" else -30
	panel.offset_left = 32 if screen == "trial" else 52
	panel.offset_right = -32 if screen == "trial" else -52
	for view in district_views:
		view["flow"].add_theme_font_size_override("font_size", 15 if compact else 16)
		view["supply_label"].add_theme_font_size_override("font_size", 16 if compact else 17)
	for illustration in facility_images: illustration.custom_minimum_size.y = 32 if compact else 40
	if is_instance_valid(trial_message): trial_message.add_theme_font_size_override("font_size", 17 if compact else 19)
	for button in option_buttons:
		var illustration := button.find_child("ComponentImage", true, false) as TextureRect
		if illustration: illustration.custom_minimum_size.y = 104 if compact else 140

func _process(delta: float) -> void:
	if screen != "trial" or str(trial_state.get("phase", "")) == "complete": return
	flow_clock += delta
	for view in district_views:
		view["flow"].modulate.a = 0.925 + 0.075 * sin(flow_clock * 5.0) if float(view["supply"].value) > 0.0 else 1.0

func _local_index() -> int:
	return NetworkManager.get_local_player_index() if NetworkManager.is_online else 0

func _label(value: String, font_size: int = 20, color: Color = UI.TEXT) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _button(value: String, action: Callable, primary: bool = false) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = 48
	result.add_theme_font_size_override("font_size", 20)
	result.focus_mode = Control.FOCUS_ALL
	if primary: UI.apply_primary_button(result)
	else: UI.apply_secondary_button(result)
	result.pressed.connect(action)
	return result

func _image(path: String, minimum: Vector2) -> TextureRect:
	var result := TextureRect.new()
	result.custom_minimum_size = minimum
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path): result.texture = load(path)
	return result

func _bar(color: Color, height: float = 20) -> ProgressBar:
	var result := ProgressBar.new()
	result.custom_minimum_size.y = height
	result.show_percentage = false
	result.add_theme_stylebox_override("background", UI.progress_background())
	result.add_theme_stylebox_override("fill", UI.progress_fill(color))
	return result

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func reset() -> void:
	component_state.clear()
	plan_state.clear()
	trial_state.clear()
	_show_screen("")
	waiting_chip.hide()
	hide()

func restore_state() -> void:
	component_state = GameManager.get_component_choice_state()
	plan_state = GameManager.get_team_plan_state()
	trial_state = GameManager.get_energy_trial_state()
	_refresh_stage()

func is_blocking_overlay_visible() -> bool:
	return is_visible_in_tree() and not screen.is_empty()

func _on_component_changed(state: Dictionary) -> void:
	component_state = state.duplicate(true)
	_refresh_stage()

func _on_plan_changed(state: Dictionary) -> void:
	plan_state = state.duplicate(true)
	_refresh_stage()

func _on_trial_changed(state: Dictionary) -> void:
	trial_state = state.duplicate(true)
	_refresh_stage()

func _refresh_stage() -> void:
	var trial_phase := str(trial_state.get("phase", ""))
	if trial_phase in ["day", "night", "complete"]:
		_show_screen("trial")
		_update_trial()
	elif bool(plan_state.get("active", false)):
		_show_screen("plan")
		_update_plan()
	else:
		var choices: Dictionary = component_state.get("choices", {})
		var own: Dictionary = choices.get(_local_index(), {})
		if str(own.get("phase", "")) == "choosing":
			if shown_choice_token != int(own.get("token", -1)):
				shown_choice_token = int(own.get("token", -1))
				_show_screen("")
			_show_screen("component")
			_update_component(own)
		else:
			_show_screen("")
			var waiting_names: Array[String] = []
			for idx in choices:
				if int(idx) != _local_index() and str(choices[idx].get("phase", "")) == "choosing":
					waiting_names.append(_player_name(int(idx)))
			waiting_chip.visible = not waiting_names.is_empty()
			waiting_label.text = "%s · 부품 고르는 중" % ", ".join(waiting_names)
			visible = waiting_chip.visible
	_refresh_inventory()

func _show_screen(value: String) -> void:
	visible = not value.is_empty()
	panel.visible = visible
	$Shade.visible = visible
	waiting_chip.hide()
	if screen != value:
		screen = value
		_clear_children(content)
		_clear_children(footer)
		option_buttons.clear()
		plan_buttons.clear()
		plan_recipe_labels.clear()
		plan_player_labels.clear()
		mode_buttons.clear()
		district_views.clear()
		facility_images.clear()
		energy_village_view = null
		shown_phase = ""
		match screen:
			"component": _build_component()
			"plan": _build_plan()
			"trial": _build_trial()
		_fit_layout()
	var blocking := not value.is_empty()
	if last_blocking != blocking:
		last_blocking = blocking
		stage_visibility_changed.emit(blocking)

func _build_component() -> void:
	heading.text = "필요한 부품 1개 고르기"
	subheading.text = "만들고 싶은 시설에 쓸 부품을 골라요."
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cards)
	var choice: Dictionary = component_state.get("choices", {}).get(_local_index(), {})
	var options: Array = choice.get("options", [])
	for index in range(options.size()):
		var item_id := str(options[index])
		var item: Dictionary = GameManager.ITEM_DEFINITIONS[item_id]
		var button := _button("", _choose_component.bind(item_id, int(choice.get("token", -1))))
		button.set_meta("item_id", item_id)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 16)
		margin.add_theme_constant_override("margin_right", 16)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_theme_constant_override("margin_bottom", 20)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(margin)
		var stack := VBoxContainer.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.add_theme_constant_override("separation", 15)
		margin.add_child(stack)
		var illustration := _image(str(item["asset"]), Vector2(120, 140))
		illustration.name = "ComponentImage"
		stack.add_child(illustration)
		var title := _label("%d  %s" % [index + 1, item["name"]], 22, UI.GOLD)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(title)
		var purpose := _label(str(COMPONENT_PURPOSES.get(item_id, "시설을 만드는 재료")), 19)
		purpose.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		purpose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(purpose)
		option_buttons.append(button)
	_link_focus(option_buttons)
	if not option_buttons.is_empty(): call_deferred("_focus_if_visible", option_buttons[0])

func _update_component(choice: Dictionary) -> void:
	timer_label.text = "%d초" % ceili(float(choice.get("remaining", 8.0)))
	var project_idx := int(choice.get("project_idx", -1))
	if project_idx >= 0 and project_idx < GameManager.CONSTRUCTION_PROJECTS.size():
		subheading.text = "내 목표: %s · 1 / 2 / 3 또는 방향키 + Enter" % GameManager.CONSTRUCTION_PROJECTS[project_idx]["name"]

func _choose_component(item_id: String, token: int) -> void:
	GameManager.choose_quiz_component(_local_index(), item_id, token)

func _build_plan() -> void:
	heading.text = "함께 지을 시설 고르기"
	subheading.text = "각자 시설을 추천해요. 모은 재료는 함께 써요."
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	var grid := GridContainer.new()
	plan_grid = grid
	grid.columns = 2 if size.x < 1150 else 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for idx in range(GameManager.CONSTRUCTION_PROJECTS.size()):
		var project: Dictionary = GameManager.CONSTRUCTION_PROJECTS[idx]
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		var button := _button(str(project["name"]), _recommend_project.bind(idx))
		button.icon = load(str(project["image"]))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 62)
		button.custom_minimum_size = Vector2(210, 76)
		button.add_theme_font_size_override("font_size", 18)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(button)
		plan_buttons.append(button)
		var purpose := _label(PROJECT_PURPOSES[idx], 16, UI.TEXT_MUTED)
		purpose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(purpose)
		var recipe := _label("", 16)
		recipe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(recipe)
		plan_recipe_labels.append(recipe)
	var players := VBoxContainer.new()
	players.custom_minimum_size.x = 265
	players.add_theme_constant_override("separation", 14)
	row.add_child(players)
	players.add_child(_label("친구들의 추천", 22, UI.GOLD))
	for idx in range(GameManager.players.size()):
		var label := _label("", 18)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		players.add_child(label)
		plan_player_labels.append(label)
	plan_ready_button = _button("추천 완료", _confirm_plan, true)
	footer.add_child(plan_ready_button)
	var focusables: Array[Button] = plan_buttons.duplicate()
	focusables.append(plan_ready_button)
	_link_focus(focusables)
	var own := int(plan_state.get("choices", {}).get(_local_index(), 0))
	call_deferred("_focus_if_visible", plan_buttons[clampi(own, 0, plan_buttons.size() - 1)])

func _update_plan() -> void:
	timer_label.text = "%d초" % ceili(float(plan_state.get("remaining", 20.0)))
	var choices: Dictionary = plan_state.get("choices", {})
	var ready: Dictionary = plan_state.get("ready", {})
	var inventory: Dictionary = GameManager.get_team_inventory()
	for idx in range(plan_buttons.size()):
		var selected := int(choices.get(_local_index(), -1)) == idx
		UI.apply_secondary_button(plan_buttons[idx], UI.GOLD if selected else UI.TEAL)
		plan_buttons[idx].disabled = bool(ready.get(_local_index(), false))
		var requirement: Dictionary = GameManager.CONSTRUCTION_PROJECTS[idx]["requirements"]
		var missing: Array[String] = []
		for item in requirement:
			var count := maxi(0, int(requirement[item]) - int(inventory.get(item, 0)))
			if count > 0: missing.append("%s %d" % [GameManager.ITEM_DEFINITIONS[item]["name"], count])
		plan_recipe_labels[idx].text = "건설 가능" if missing.is_empty() else "더 필요: " + " · ".join(missing)
		plan_recipe_labels[idx].add_theme_color_override("font_color", UI.SUCCESS if missing.is_empty() else UI.TEXT_MUTED)
	for idx in range(plan_player_labels.size()):
		var selected := int(choices.get(idx, -1))
		var project := str(GameManager.CONSTRUCTION_PROJECTS[selected]["name"]) if selected >= 0 and selected < GameManager.CONSTRUCTION_PROJECTS.size() else "고르는 중"
		plan_player_labels[idx].text = "%s%s\n%s" % [_player_name(idx), "  ✓" if bool(ready.get(idx, false)) else "", project]
	plan_ready_button.disabled = bool(ready.get(_local_index(), false)) or not choices.has(_local_index())
	plan_ready_button.text = "친구 기다리는 중" if bool(ready.get(_local_index(), false)) else "추천 완료"

func _recommend_project(index: int) -> void:
	GameManager.select_team_project(_local_index(), index)

func _confirm_plan() -> void:
	GameManager.confirm_team_plan(_local_index())

func _build_trial() -> void:
	heading.text = "우리 마을에 전기 보내기"
	subheading.text = "1 남는 전기 저장  ·  2 배터리 전기 사용"
	trial_phase_bar = _bar(UI.GOLD, 6)
	content.add_child(trial_phase_bar)
	energy_village_view = EnergyVillageView.new()
	energy_village_view.custom_minimum_size.y = 210
	energy_village_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	energy_village_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(energy_village_view)
	for idx in range(GameManager.players.size()):
		var stack := VBoxContainer.new()
		stack.name = "District%d" % (idx + 1)
		stack.add_theme_constant_override("separation", 3)
		energy_village_view.add_district_marker(stack)
		var name_label := _label("%d  %s" % [idx + 1, _player_name(idx)], 18, UI.GOLD if idx == _local_index() else UI.TEXT)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		stack.add_child(name_label)
		var supply := _bar(EnergyVillageView.PLAYER_COLORS[idx % 4], 5)
		stack.add_child(supply)
		var supply_label := _label("", 17)
		stack.add_child(supply_label)
		var battery := _bar(UI.GOLD, 5)
		stack.add_child(battery)
		var battery_label := _label("", 16, UI.TEXT_MUTED)
		stack.add_child(battery_label)
		var flow := _label("", 16, UI.TEXT_MUTED)
		stack.add_child(flow)
		district_views.append({"name": name_label, "flow": flow, "supply": supply, "supply_label": supply_label, "battery": battery, "battery_label": battery_label})
	trial_message = _label("", 19, UI.TEXT)
	trial_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trial_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(trial_message)
	mode_buttons["store"] = _button("1  내 구역에 전기 저장", _choose_mode.bind("store"))
	mode_buttons["supply"] = _button("2  내 배터리 전기 사용", _choose_mode.bind("supply"))
	footer.add_child(mode_buttons["store"])
	footer.add_child(mode_buttons["supply"])
	trial_retry_button = _button("시설 보완하기", _finish_trial.bind(true))
	footer.add_child(trial_retry_button)
	trial_confirm_button = _button("결과 확인 완료", _finish_trial.bind(false), true)
	footer.add_child(trial_confirm_button)
	trial_retry_button.hide()
	trial_confirm_button.hide()
	_link_focus([mode_buttons["store"], mode_buttons["supply"]])
	call_deferred("_focus_if_visible", mode_buttons["supply"])

func _update_trial() -> void:
	var phase := str(trial_state.get("phase", "day"))
	var complete := phase == "complete"
	var players: Array = trial_state.get("players", [])
	var summary: Dictionary = trial_state.get("summary", trial_state)
	timer_label.text = "완료" if complete else "%s · %d초" % ["낮" if phase == "day" else "밤", ceili(float(trial_state.get("phase_remaining", 20.0)))]
	trial_phase_bar.value = float(trial_state.get("elapsed", 0.0)) / 40.0 * 100.0
	panel.add_theme_stylebox_override("panel", UI.padded_panel(UI.PANEL, UI.TEAL_DARK, 16, 12))
	energy_village_view.update_snapshot(trial_state, _local_index())
	for idx in range(mini(players.size(), district_views.size())):
		district_views[idx]["name"].text = "%d  %s%s" % [idx + 1, _player_name(idx), " (나)" if idx == _local_index() else ""]
		_update_district(district_views[idx], players[idx], complete)
	var own: Dictionary = players[_local_index()] if _local_index() >= 0 and _local_index() < players.size() else {}
	for mode in mode_buttons:
		mode_buttons[mode].visible = not complete
		mode_buttons[mode].disabled = float(own.get("capacity", 0.0)) <= 0.0
		UI.apply_secondary_button(mode_buttons[mode], UI.GOLD if str(own.get("mode", "supply")) == mode else UI.TEAL)
	trial_confirm_button.visible = complete
	trial_retry_button.visible = complete and not bool(summary.get("success", false)) and bool(trial_state.get("can_retry", false))
	if complete:
		heading.text = "낮과 밤의 전력 확인"
		subheading.text = "필요한 전기를 보낸 비율 · 낮 %d%% / 밤 %d%%" % [roundi(float(summary.get("daytime_coverage", 0.0)) * 100.0), roundi(float(summary.get("night_coverage", 0.0)) * 100.0)]
		trial_message.text = "마을에 필요한 전기를 보냈어요." if bool(summary.get("success", false)) else "밤에 쓸 전기를 더 준비해요." if float(summary.get("night_coverage", 0.0)) < float(summary.get("daytime_coverage", 0.0)) else "발전 시설을 늘리거나 필요한 전기를 줄여 봐요."
		var ready: Dictionary = trial_state.get("ready", {})
		trial_confirm_button.disabled = bool(ready.get(_local_index(), false))
		trial_confirm_button.text = "친구 기다리는 중" if trial_confirm_button.disabled else "결과 확인 완료"
		trial_retry_button.disabled = trial_confirm_button.disabled
	else:
		heading.text = "우리 마을에 전기 보내기"
		subheading.text = "이번 %s: %s" % ["낮" if phase == "day" else "밤", str(trial_state.get("condition_label", ""))]
		var electricity := "만든 전기 %.1f칸 / 필요한 전기 %.1f칸\n" % [float(trial_state.get("generation", 0.0)), float(trial_state.get("demand", 0.0))]
		if float(own.get("capacity", 0.0)) <= 0.0:
			trial_message.text = electricity + "저장소가 없어요. 발전소에서 만든 전기만 보낼 수 있어요."
		elif float(own.get("generation", 0.0)) >= float(own.get("demand", 0.0)):
			trial_message.text = electricity + "집에 보내고 남은 전기를 저장해 두세요."
		elif float(own.get("battery", 0.0)) <= 0.001:
			trial_message.text = electricity + "배터리가 비어 전기를 꺼낼 수 없어요."
		elif phase == "night" and 0 in trial_state.get("built_ids", []):
			trial_message.text = electricity + "밤에는 태양광 발전이 멈춰요. 저장한 전기를 보내세요."
		else:
			trial_message.text = electricity + "만든 전기가 부족해요. 배터리의 전기를 보내세요."
	if shown_phase != phase:
		shown_phase = phase
		if complete:
			var actions: Array[Button] = []
			if trial_retry_button.visible: actions.append(trial_retry_button)
			actions.append(trial_confirm_button)
			_link_focus(actions)
			call_deferred("_focus_if_visible", actions[0])

func _focus_if_visible(button: Variant) -> void:
	if is_instance_valid(button) and button.is_inside_tree() and button.is_visible_in_tree() and not button.disabled:
		button.grab_focus()

func _update_district(view: Dictionary, district: Dictionary, complete: bool) -> void:
	var demand := float(district.get("demand", 0.0))
	var supplied := float(district.get("delivered", 0.0))
	var ratio := float(district.get("light_ratio", clampf(supplied / maxf(demand, 0.001), 0.0, 1.0)))
	if complete: ratio = float(district.get("coverage", ratio))
	if complete: view["flow"].modulate.a = 1.0
	view["supply"].value = ratio * 100.0
	view["supply_label"].text = ("전체 공급 %d%%" if complete else "전기 공급 %d%%") % roundi(ratio * 100.0)
	view["flow"].text = "시험 완료" if complete else "남는 전기 저장 중" if float(district.get("charging", 0.0)) > 0.01 else ("배터리 전기 사용 중" if float(district.get("discharging", 0.0)) > 0.01 else ("발전소에서 공급 중" if supplied > 0.01 else "전기가 부족해요"))
	view["flow"].add_theme_color_override("font_color", UI.SUCCESS if ratio >= 0.99 else UI.GOLD)
	var capacity := float(district.get("capacity", 0.0))
	var stored := float(district.get("battery", 0.0))
	view["battery"].value = stored / maxf(capacity, 0.001) * 100.0
	view["battery_label"].text = "저장소 없음" if capacity <= 0.0 else "배터리 %d%%" % roundi(stored / capacity * 100.0)

func _choose_mode(mode: String) -> void:
	GameManager.set_energy_trial_mode(_local_index(), mode)

func _finish_trial(retry: bool) -> void:
	GameManager.finish_energy_trial(_local_index(), retry)

func _refresh_inventory() -> void:
	if not is_instance_valid(inventory_label): return
	inventory_label.visible = screen in ["component", "plan"]
	if not inventory_label.visible: return
	var inventory: Dictionary = GameManager.get_team_inventory()
	var parts: Array[String] = []
	for item_id in GameManager.ITEM_DEFINITIONS:
		var count := int(inventory.get(item_id, 0))
		if count > 0: parts.append("%s %d" % [GameManager.ITEM_DEFINITIONS[item_id]["name"], count])
	inventory_label.text = "함께 모은 재료  ·  " + ("아직 없어요" if parts.is_empty() else " / ".join(parts))

func _player_name(idx: int) -> String:
	if idx < 0 or idx >= GameManager.players.size(): return "친구"
	var player: Dictionary = GameManager.players[idx]
	var player_name := str(player.get("name", "친구"))
	return player_name + " (AI)" if bool(player.get("is_ai", false)) and not player_name.ends_with("(AI)") else player_name

func _link_focus(buttons: Array[Button]) -> void:
	if buttons.is_empty(): return
	for idx in range(buttons.size()):
		var previous := buttons[(idx + buttons.size() - 1) % buttons.size()]
		var next := buttons[(idx + 1) % buttons.size()]
		buttons[idx].focus_neighbor_left = buttons[idx].get_path_to(previous)
		buttons[idx].focus_neighbor_right = buttons[idx].get_path_to(next)
		buttons[idx].focus_neighbor_top = buttons[idx].get_path_to(previous)
		buttons[idx].focus_neighbor_bottom = buttons[idx].get_path_to(next)
		buttons[idx].focus_previous = buttons[idx].get_path_to(previous)
		buttons[idx].focus_next = buttons[idx].get_path_to(next)

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_blocking_overlay_visible() or not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if screen == "component" and key >= KEY_1 and key <= KEY_3:
		var idx := key - KEY_1
		if idx < option_buttons.size(): option_buttons[idx].pressed.emit()
		get_viewport().set_input_as_handled()
	elif screen == "trial" and str(trial_state.get("phase", "")) != "complete" and key in [KEY_1, KEY_2]:
		var mode := "store" if key == KEY_1 else "supply"
		if not mode_buttons[mode].disabled: _choose_mode(mode)
		get_viewport().set_input_as_handled()
