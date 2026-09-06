extends Control

## Local presentation only: choosing a goal never consumes or reserves materials.
const UI = preload("res://scripts/ui/CommercialUI.gd")
var inventory_labels: Dictionary = {}
var recipe_cards: Array[PanelContainer] = []
var recipe_labels: Array[Label] = []
var goal_buttons: Array[Button] = []
var inventory: Dictionary = {}
var selected_goal := -1
var local_index := 0
var summary: PanelContainer
var goal_name: Label
var goal_materials: Label
var goal_progress: ProgressBar
var catalog: Control
var catalog_open_button: Button
var tutorial: PanelContainer
var tutorial_title: Label
var tutorial_body: Label
var tutorial_steps := {"dice": false, "pickup": false, "goal": false, "skill": false}
var tutorial_active := false
var exploration_active := false
var quiz_open := false
var settings_path := "user://adventure_guide.cfg"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_summary()
	_build_catalog()
	_build_tutorial()
	GameManager.dice_rolled.connect(func(idx: int, _value: int): record_step("dice", idx))
	GameManager.tile_item_collected.connect(func(_tile: int, idx: int, _item: String): record_step("pickup", idx))
	GameManager.special_skill_completed.connect(func(idx: int): record_step("skill", idx))
	GameManager.quiz_requested.connect(func(_idx: int, _data: Dictionary):
		quiz_open = true
		close_catalog()
		_refresh_visibility())
	GameManager.quiz_resolved.connect(func(_idx: int, _correct: bool):
		quiz_open = false
		_refresh_visibility())
	GameManager.open_market_state_changed.connect(func(state: Dictionary):
		if state.get("active", false): end_exploration())
	GameManager.village_construction_started.connect(func(_data: Array): end_exploration())
	GameManager.game_over.connect(func(_rankings: Array): end_exploration())

func _label(text_value: String, font_size: int = 16, color: Color = UI.TEXT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text_value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", 15)
	UI.apply_secondary_button(button)
	button.pressed.connect(action)
	return button

func _image(path: String, dimensions: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = load(path)
	image.custom_minimum_size = dimensions
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _build_summary() -> void:
	summary = PanelContainer.new()
	summary.position = Vector2(12, 612)
	summary.size = Vector2(1256, 96)
	summary.add_theme_stylebox_override("panel", UI.padded_panel(UI.INK, UI.TEAL_DARK, 12))
	add_child(summary)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	summary.add_child(row)
	var heading := VBoxContainer.new()
	heading.custom_minimum_size.x = 250
	row.add_child(heading)
	heading.add_child(_label("나의 건설 목표", 13, UI.TEAL))
	goal_name = _label("첫 시설을 골라보세요", 20)
	heading.add_child(goal_name)
	var materials := VBoxContainer.new()
	materials.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	materials.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(materials)
	goal_materials = _label("모험에서 재료를 모아 종료 후 마을을 건설해요", 16)
	materials.add_child(goal_materials)
	goal_progress = ProgressBar.new()
	goal_progress.custom_minimum_size.y = 8
	goal_progress.show_percentage = false
	goal_progress.add_theme_stylebox_override("background", UI.panel(UI.PANEL_SOFT, UI.PANEL_SOFT, 4, 0, 0))
	goal_progress.add_theme_stylebox_override("fill", UI.panel(UI.TEAL, UI.TEAL, 4, 0, 0))
	materials.add_child(goal_progress)
	catalog_open_button = _button("재료 가방 · 목표 선택", open_catalog)
	catalog_open_button.custom_minimum_size = Vector2(220, 48)
	catalog_open_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(catalog_open_button)

func _build_catalog() -> void:
	catalog = Control.new()
	catalog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catalog.z_index = 20
	add_child(catalog)
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.02, 0.06, 0.09, 0.88)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catalog.add_child(dimmer)
	var panel := PanelContainer.new()
	panel.position = Vector2(100, 75)
	panel.size = Vector2(1080, 570)
	panel.add_theme_stylebox_override("panel", UI.padded_panel(UI.PANEL, UI.TEAL_DARK, 18))
	catalog.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := _label("재료 가방 & 건설 목표", 24, UI.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("닫기  ×", close_catalog))
	content.add_child(_label("모험 시간은 계속 흐릅니다. 목표는 자유롭게 변경하고, 모험과 교환이 끝난 뒤 건설해요.", 14, UI.TEXT_MUTED))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	content.add_child(columns)
	var bag := VBoxContainer.new()
	bag.custom_minimum_size.x = 250
	bag.add_theme_constant_override("separation", 2)
	columns.add_child(bag)
	for id in GameManager.ITEM_DEFINITIONS:
		var data: Dictionary = GameManager.ITEM_DEFINITIONS[id]
		var row := HBoxContainer.new()
		bag.add_child(row)
		row.add_child(_image(str(data["asset"]), Vector2(28, 28)))
		var name_label := _label(str(data["name"]), 13)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var count := _label("0개", 15, UI.GOLD)
		row.add_child(count)
		inventory_labels[id] = count
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	columns.add_child(grid)
	for index in range(GameManager.CONSTRUCTION_PROJECTS.size()):
		var project: Dictionary = GameManager.CONSTRUCTION_PROJECTS[index]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(350, 68)
		card.add_theme_stylebox_override("panel", UI.padded_panel(UI.PANEL_RAISED, UI.PANEL_SOFT, 6, 8))
		grid.add_child(card)
		recipe_cards.append(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		row.add_child(_image(str(project["image"]), Vector2(46, 46)))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		details.add_child(_label(str(project["name"]), 14))
		var counts := _label("", 11, UI.TEXT_MUTED)
		details.add_child(counts)
		recipe_labels.append(counts)
		var status := _label("재료 부족", 11, UI.TEXT_MUTED)
		status.name = "Status"
		details.add_child(status)
		var choose := _button("선택", select_goal.bind(index))
		choose.add_theme_font_size_override("font_size", 12)
		choose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(choose)
		goal_buttons.append(choose)
	catalog.hide()

func begin_exploration(index: int) -> void:
	local_index = index
	selected_goal = -1
	exploration_active = true
	quiz_open = false
	for step in tutorial_steps: tutorial_steps[step] = false
	var config := ConfigFile.new()
	config.load(settings_path)
	tutorial_active = not bool(config.get_value("guide", "completed", false))
	close_catalog()
	refresh({})
	_refresh_tutorial()

func end_exploration() -> void:
	exploration_active = false
	close_catalog()
	_refresh_visibility()

func open_catalog() -> void:
	if not exploration_active or quiz_open: return
	catalog.show()
	_refresh_visibility()
	goal_buttons[maxi(selected_goal, 0)].grab_focus()

func close_catalog() -> void:
	var was_open := catalog.visible
	catalog.hide()
	_refresh_visibility()
	if was_open and exploration_active: catalog_open_button.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if catalog.visible and event.is_action_pressed("ui_cancel"):
		close_catalog()
		get_viewport().set_input_as_handled()

func select_goal(index: int) -> void:
	if index < 0 or index >= GameManager.CONSTRUCTION_PROJECTS.size(): return
	selected_goal = index
	record_step("goal", local_index)
	refresh(inventory)
	close_catalog()

func missing_materials(index: int) -> Dictionary:
	var missing := {}
	for id in GameManager.CONSTRUCTION_PROJECTS[index]["requirements"]:
		var count := maxi(0, int(GameManager.CONSTRUCTION_PROJECTS[index]["requirements"][id]) - int(inventory.get(id, 0)))
		if count > 0: missing[id] = count
	return missing

func refresh(new_inventory: Dictionary) -> void:
	inventory = new_inventory.duplicate()
	for id in inventory_labels: inventory_labels[id].text = "%d개" % int(inventory.get(id, 0))
	for index in range(recipe_cards.size()):
		var counts: Array[String] = []
		for id in GameManager.CONSTRUCTION_PROJECTS[index]["requirements"]:
			counts.append("%s %d/%d" % [GameManager.ITEM_DEFINITIONS[id]["name"], int(inventory.get(id, 0)), GameManager.CONSTRUCTION_PROJECTS[index]["requirements"][id]])
		recipe_labels[index].text = "\n".join(counts)
		var ready := missing_materials(index).is_empty()
		var status := recipe_cards[index].find_child("Status", true, false) as Label
		status.text = "재료 준비 완료" if ready else "재료 부족"
		status.add_theme_color_override("font_color", UI.SUCCESS if ready else UI.TEXT_MUTED)
		goal_buttons[index].text = "목표 ✓" if index == selected_goal else "선택"
	if selected_goal < 0:
		goal_name.text = "첫 시설을 골라보세요"
		goal_materials.text = "모험에서 재료를 모아 종료 후 마을을 건설해요"
		goal_materials.add_theme_color_override("font_color", UI.TEXT)
		goal_progress.value = 0
		return
	var project: Dictionary = GameManager.CONSTRUCTION_PROJECTS[selected_goal]
	goal_name.text = str(project["name"])
	var missing := missing_materials(selected_goal)
	var parts: Array[String] = []
	var total := 0
	var owned := 0
	for id in project["requirements"]:
		total += int(project["requirements"][id])
		owned += mini(int(inventory.get(id, 0)), int(project["requirements"][id]))
	for id in missing: parts.append("%s %d개" % [GameManager.ITEM_DEFINITIONS[id]["name"], missing[id]])
	goal_materials.text = "준비 완료! 모험 종료 후 건설할 수 있어요" if missing.is_empty() else "더 모을 재료  ·  " + " · ".join(parts)
	goal_materials.add_theme_color_override("font_color", UI.SUCCESS if missing.is_empty() else UI.TEXT)
	goal_progress.max_value = maxi(total, 1)
	goal_progress.value = owned

func _build_tutorial() -> void:
	tutorial = PanelContainer.new()
	tutorial.position = Vector2(18, 150)
	tutorial.custom_minimum_size = Vector2(322, 0)
	tutorial.add_theme_stylebox_override("panel", UI.padded_panel(UI.INK, UI.TEAL_DARK, 14))
	add_child(tutorial)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	tutorial.add_child(content)
	tutorial_title = _label("첫 모험 안내", 17, UI.TEAL)
	content.add_child(tutorial_title)
	tutorial_body = _label("", 15)
	tutorial_body.custom_minimum_size.x = 290
	tutorial_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(tutorial_body)
	content.add_child(_button("안내 그만 보기", dismiss_tutorial))
	tutorial.hide()

func record_step(step: String, index: int) -> void:
	if not exploration_active or index != local_index or not tutorial_steps.has(step): return
	tutorial_steps[step] = true
	_refresh_tutorial()

func replay_tutorial() -> void:
	if not exploration_active: return
	for step in tutorial_steps: tutorial_steps[step] = false
	if selected_goal >= 0: tutorial_steps["goal"] = true
	tutorial_active = true
	_refresh_tutorial()

func dismiss_tutorial() -> void:
	tutorial_active = false
	var config := ConfigFile.new()
	config.set_value("guide", "completed", true)
	config.save(settings_path)
	_refresh_visibility()

func _refresh_tutorial() -> void:
	var descriptions := ["내 턴에 오른쪽 주사위를 눌러 이동해 보세요.", "도착한 칸의 재료를 모아보세요. 재료는 자동으로 가방에 들어와요.", "하단 ‘목표 선택’을 눌러 만들고 싶은 시설을 선택하세요.", "퀴즈 정답으로 SP를 모으고, 내 턴에 특수기술 버튼을 눌러보세요."]
	var index := 0
	for step in tutorial_steps:
		if not tutorial_steps[step]: break
		index += 1
	if index == 4:
		if tutorial_active: dismiss_tutorial()
		return
	tutorial_title.text = "첫 모험 안내  %d / 4" % (index + 1)
	tutorial_body.text = descriptions[index]
	_refresh_visibility()

func _refresh_visibility() -> void:
	if not is_instance_valid(tutorial): return
	summary.visible = exploration_active and not quiz_open
	tutorial.visible = exploration_active and tutorial_active and not quiz_open and not catalog.visible
