extends Control
class_name EndingCinematic

## Existing story art retells the village recovery; actual session-only team
## contributions remain visible without changing any game or ranking values.

signal animation_finished

const SCENE_DURATION := 6.0
const FINAL_SCENE_DURATION := 9.0
const CROSSFADE_DURATION := 0.72
const DURATION := SCENE_DURATION * 2.0 + FINAL_SCENE_DURATION
const UI = preload("res://scripts/ui/CommercialUI.gd")

const SUCCESS_SCENES: Array[Dictionary] = [
	{
		"image": "res://assets/kingdom/kingdom_stage_0.webp",
		"title": "함께 지은 마을",
		"caption": "모은 부품으로 시설을 짓고, 마을에 전기를 보냈어요."
	},
	{
		"image": "res://assets/kingdom/kingdom_stage_50.webp",
		"title": "낮과 밤의 전기",
		"caption": "낮에도 밤에도 마을에 필요한 전기를 마련했어요."
	},
	{
		"image": "res://assets/kingdom/kingdom_stage_100.webp",
		"title": "다시 불이 켜진 요정마을",
		"caption": "탐험대가 함께 마을의 에너지 위기를 해결했어요."
	}
]

const FAILURE_SCENES: Array[Dictionary] = [
	{
		"image": "res://assets/story/ending/failure_01_incomplete_grid.webp",
		"title": "아직 전기가 부족해요",
		"caption": "마을에 필요한 전기를 모두 보내지는 못했어요."
	},
	{
		"image": "res://assets/story/ending/failure_02_safe_night.webp",
		"title": "밤에는 무엇이 필요할까요?",
		"caption": "해가 지면 태양광 발전이 멈춰요. 저장한 전기나 다른 발전 시설이 필요해요."
	},
	{
		"image": "res://assets/story/ending/failure_03_new_plan.webp",
		"title": "마을 계획을 돌아봐요",
		"caption": "발전 시설과 배터리를 갖추고, 절전 시설로 필요한 전기를 줄일 수 있어요."
	}
]

var is_success := false
var village_energy := 0
var target_energy := 70
var elapsed := 0.0
var scene_elapsed := 0.0
var scene_index := 0
var title_text := ""
var subtitle_text := ""
var scenes: Array[Dictionary] = []
var _finished_emitted := false
var _active_layer := 0
var _scene_tween: Tween
var _image_layers: Array[TextureRect] = []
var _caption_panel: PanelContainer
var _title_label: Label
var _caption_label: Label
var _progress_label: Label
var _energy_label: Label
var team_snapshot: Array[Dictionary] = []
var trial_summary: Dictionary = {}
var _recovery_label: Label
var _team_panel: PanelContainer
var _team_row: HBoxContainer
var team_cards: Array[PanelContainer] = []

func setup(success: bool, energy_value: int, target_value: int, players_snapshot: Array = [], electricity_summary: Dictionary = {}) -> void:
	is_success = success
	village_energy = energy_value
	target_energy = target_value
	trial_summary = electricity_summary.duplicate(true)
	team_snapshot.clear()
	var source_players := players_snapshot
	if source_players.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		var manager := tree.root.get_node_or_null("GameManager") if tree != null else null
		if manager != null:
			source_players = manager.get("players")
	for player in source_players:
		if player is Dictionary and team_snapshot.size() < 4:
			team_snapshot.append(player.duplicate(true))
	team_snapshot.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("index", 0)) < int(b.get("index", 0)))
	scenes = (SUCCESS_SCENES if is_success else FAILURE_SCENES).duplicate(true)
	if is_node_ready():
		_restart_story()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	focus_mode = Control.FOCUS_ALL
	_build_view()
	_restart_story()
	grab_focus()

func _build_view() -> void:
	for layer_index in range(2):
		var image := TextureRect.new()
		image.name = "SceneImage%d" % (layer_index + 1)
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.visible = false
		add_child(image)
		_image_layers.append(image)

	var top_shade := ColorRect.new()
	top_shade.name = "TopShade"
	top_shade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_shade.offset_bottom = 92.0
	top_shade.color = Color(0.01, 0.04, 0.06, 0.66)
	top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_shade)

	_energy_label = Label.new()
	_energy_label.name = "EnergyResult"
	_energy_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_energy_label.offset_left = -292.0
	_energy_label.offset_top = 20.0
	_energy_label.offset_right = -28.0
	_energy_label.offset_bottom = 60.0
	_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_energy_label.add_theme_font_size_override("font_size", 20)
	_energy_label.add_theme_color_override("font_color", Color("bfffea") if is_success else Color("d4e8ef"))
	_energy_label.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.07, 0.92))
	_energy_label.add_theme_constant_override("outline_size", 4)
	_energy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_energy_label)
	_recovery_label = Label.new()
	_recovery_label.name = "VillageRecoveryStages"
	_recovery_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_recovery_label.offset_left = 28.0
	_recovery_label.offset_top = 22.0
	_recovery_label.offset_right = -328.0
	_recovery_label.offset_bottom = 62.0
	_recovery_label.add_theme_font_size_override("font_size", 20)
	_recovery_label.add_theme_color_override("font_color", UI.TEXT)
	_recovery_label.clip_text = true
	_recovery_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_recovery_label)

	_team_panel = PanelContainer.new()
	_team_panel.name = "TeamContributionPanel"
	_team_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_team_panel.offset_left = 28.0
	_team_panel.offset_right = -28.0
	_team_panel.offset_top = -286.0
	_team_panel.offset_bottom = -186.0
	_team_panel.add_theme_stylebox_override("panel", UI.padded_panel(Color("102c38e8"), UI.TEAL_DARK, 8, 12))
	_team_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_team_panel)
	_team_row = HBoxContainer.new()
	_team_row.add_theme_constant_override("separation", 10)
	_team_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_team_panel.add_child(_team_row)

	_caption_panel = PanelContainer.new()
	_caption_panel.name = "CaptionPanel"
	_caption_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption_panel.offset_left = 94.0
	_caption_panel.offset_top = -176.0
	_caption_panel.offset_right = -94.0
	_caption_panel.offset_bottom = -28.0
	_caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption_style := StyleBoxFlat.new()
	caption_style.bg_color = Color(0.015, 0.055, 0.065, 0.84)
	caption_style.border_color = Color("62e8bd") if is_success else Color("7aa8bc")
	caption_style.set_border_width_all(2)
	caption_style.set_corner_radius_all(18)
	caption_style.content_margin_left = 28.0
	caption_style.content_margin_right = 28.0
	caption_style.content_margin_top = 15.0
	caption_style.content_margin_bottom = 14.0
	_caption_panel.add_theme_stylebox_override("panel", caption_style)
	add_child(_caption_panel)

	var caption_box := VBoxContainer.new()
	caption_box.add_theme_constant_override("separation", 5)
	_caption_panel.add_child(caption_box)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 27)
	_title_label.add_theme_color_override("font_color", Color("ffe47a") if is_success else Color("c8e7f2"))
	caption_box.add_child(_title_label)
	_caption_label = Label.new()
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.add_theme_font_size_override("font_size", 19)
	_caption_label.add_theme_color_override("font_color", Color("effff9"))
	caption_box.add_child(_caption_label)
	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 16)
	_progress_label.add_theme_color_override("font_color", Color(0.70, 0.88, 0.86, 0.82))
	caption_box.add_child(_progress_label)

func _rebuild_team_cards() -> void:
	for child in _team_row.get_children():
		_team_row.remove_child(child)
		child.queue_free()
	team_cards.clear()
	_team_panel.visible = not team_snapshot.is_empty()
	for player in team_snapshot:
		var card := PanelContainer.new()
		card.name = "HeroContribution%d" % int(player.get("index", team_cards.size()))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", UI.padded_panel(UI.PANEL, UI.BORDER_MUTED, 6, 8))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_team_row.add_child(card)
		team_cards.append(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(row)
		var portrait := TextureRect.new()
		portrait.name = "HeroPortrait"
		portrait.custom_minimum_size = Vector2(52, 64)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_path := str(player.get("char_icon", ""))
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			portrait.texture = load(icon_path)
		row.add_child(portrait)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 2)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text)
		var name_label := _team_text("HeroName", str(player.get("name", "탐험대원")), 18, UI.GOLD)
		text.add_child(name_label)
		text.add_child(_team_text("LearningContribution", "퀴즈 %d · 재료 %d" % [int(player.get("quiz_correct", 0)), int(player.get("construction_contribution", 0))], 17, UI.TEXT))
		text.add_child(_team_text("BuildingContribution", "시설 %d곳 완공" % int(player.get("project_completion_bonus", 0)), 17, UI.TEAL))

func _team_text(node_name: String, message: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = message
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _restart_story() -> void:
	if scenes.is_empty() or _image_layers.is_empty():
		return
	elapsed = 0.0
	scene_elapsed = 0.0
	scene_index = 0
	_finished_emitted = false
	_active_layer = 0
	if _scene_tween and _scene_tween.is_valid():
		_scene_tween.kill()
	_rebuild_team_cards()
	for image in _image_layers:
		image.visible = false
	_show_scene(0, true)

func _show_scene(next_index: int, immediate: bool = false) -> void:
	if next_index < 0 or next_index >= scenes.size():
		_finish()
		return
	scene_index = next_index
	scene_elapsed = 0.0
	var scene: Dictionary = scenes[scene_index]
	title_text = str(scene["title"])
	subtitle_text = str(scene["caption"])
	if _energy_label:
		if trial_summary.is_empty():
			_energy_label.text = "전기 공급 성공" if is_success else "전기 공급 부족"
		else:
			_energy_label.text = "공급 · 낮 %d%% / 밤 %d%%" % [roundi(float(trial_summary.get("daytime_coverage", 0.0)) * 100.0), roundi(float(trial_summary.get("night_coverage", 0.0)) * 100.0)]
		_energy_label.add_theme_color_override("font_color", UI.TEAL if is_success else Color("d4e8ef"))
	if _recovery_label:
		var stages := ["함께 건설", "낮과 밤", "마을 회복"] if is_success else ["공급 부족", "밤의 전기", "마을 계획"]
		var stage_text := ""
		for index in range(stages.size()):
			stage_text += ("▶ " if index == scene_index else "") + str(stages[index])
			if index < stages.size() - 1: stage_text += "  →  "
		_recovery_label.text = stage_text
	if _title_label:
		_title_label.text = title_text
		_title_label.add_theme_color_override("font_color", UI.GOLD if is_success else Color("c8e7f2"))
	if _caption_panel:
		(_caption_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color = UI.TEAL if is_success else Color("7aa8bc")
	if _caption_label:
		_caption_label.text = subtitle_text
	if _progress_label:
		var dots := ""
		for dot_index in range(scenes.size()):
			dots += "●" if dot_index == scene_index else "○"
			dots += "  " if dot_index < scenes.size() - 1 else ""
		_progress_label.text = "%s    클릭 · Enter · Space로 다음" % dots

	var old_layer := _image_layers[_active_layer]
	_active_layer = 1 - _active_layer
	var new_layer := _image_layers[_active_layer]
	var image_path := str(scene["image"])
	if ResourceLoader.exists(image_path):
		new_layer.texture = load(image_path)
	new_layer.visible = true
	new_layer.modulate = Color.WHITE if immediate else Color(1.0, 1.0, 1.0, 0.0)
	new_layer.pivot_offset = size * 0.5
	new_layer.scale = Vector2.ONE if immediate else Vector2.ONE * 1.035
	if immediate:
		if _scene_tween and _scene_tween.is_valid():
			_scene_tween.kill()
		old_layer.visible = false
		return
	if _scene_tween and _scene_tween.is_valid():
		_scene_tween.kill()
	_scene_tween = create_tween().set_parallel(true)
	_scene_tween.tween_property(new_layer, "modulate", Color.WHITE, CROSSFADE_DURATION)
	_scene_tween.tween_property(new_layer, "scale", Vector2.ONE, CROSSFADE_DURATION + 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_scene_tween.tween_property(old_layer, "modulate", Color(1.0, 1.0, 1.0, 0.0), CROSSFADE_DURATION)
	_scene_tween.chain().tween_callback(func(): old_layer.visible = false)

func _process(delta: float) -> void:
	if _finished_emitted or scenes.is_empty():
		return
	elapsed += delta
	scene_elapsed += delta
	var reading_time := FINAL_SCENE_DURATION if scene_index == scenes.size() - 1 else SCENE_DURATION
	if scene_elapsed >= reading_time:
		_advance_scene()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_scene()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER]:
		_advance_scene()

func _advance_scene() -> void:
	if _finished_emitted:
		return
	if scene_index + 1 >= scenes.size():
		_finish()
	else:
		_show_scene(scene_index + 1)

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	animation_finished.emit()
	queue_free()
