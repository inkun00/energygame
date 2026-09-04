extends Control
class_name EndingCinematic

## ImageGen으로 제작한 3장의 연속 장면을 교차 페이드하는 이미지 기반 엔딩 컷신입니다.

signal animation_finished

const SCENE_DURATION := 3.8
const CROSSFADE_DURATION := 0.72
const DURATION := SCENE_DURATION * 3.0

const SUCCESS_SCENES: Array[Dictionary] = [
	{
		"image": "res://assets/story/ending/success_01_last_connection.webp",
		"title": "마지막 에너지 연결",
		"caption": "탐험대는 마을의 마지막 에너지 연결 장치 앞에 섰습니다. 모두의 힘을 하나로 모을 시간입니다."
	},
	{
		"image": "res://assets/story/ending/success_02_energy_wave.webp",
		"title": "마을을 달리는 깨끗한 빛",
		"caption": "태양과 바람, 물의 에너지가 이어지며 밝은 빛이 요정마을 곳곳으로 퍼져 나갑니다."
	},
	{
		"image": "res://assets/story/ending/success_03_restored_kingdom.webp",
		"title": "다시 빛나는 에너지 요정 왕국",
		"caption": "모든 시설이 힘차게 움직이고 주민들의 웃음이 돌아왔습니다. 에너지요정왕국의 에너지 위기 탈출에 성공했습니다!"
	}
]

const FAILURE_SCENES: Array[Dictionary] = [
	{
		"image": "res://assets/story/ending/failure_01_incomplete_grid.webp",
		"title": "아직 이어지지 않은 에너지 길",
		"caption": "몇몇 시설은 움직였지만 마을 전체를 밝히기에는 연결과 에너지가 조금 부족했습니다."
	},
	{
		"image": "res://assets/story/ending/failure_02_safe_night.webp",
		"title": "어둠 속에서도 함께",
		"caption": "탐험대는 작은 빛을 나누며 주민들을 안전하게 도왔습니다. 누구도 포기하지 않았습니다."
	},
	{
		"image": "res://assets/story/ending/failure_03_new_plan.webp",
		"title": "다음 도전을 위한 약속",
		"caption": "비가 그친 새벽, 탐험대는 남은 재료와 지도를 펼치고 에너지요정왕국의 회복을 위해 또 다시 도전할 계획입니다."
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

func setup(success: bool, energy_value: int, target_value: int) -> void:
	is_success = success
	village_energy = energy_value
	target_energy = target_value
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
	_caption_label.add_theme_font_size_override("font_size", 17)
	_caption_label.add_theme_color_override("font_color", Color("effff9"))
	caption_box.add_child(_caption_label)
	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 15)
	_progress_label.add_theme_color_override("font_color", Color(0.70, 0.88, 0.86, 0.82))
	caption_box.add_child(_progress_label)

func _restart_story() -> void:
	if scenes.is_empty() or _image_layers.is_empty():
		return
	elapsed = 0.0
	scene_elapsed = 0.0
	scene_index = 0
	_finished_emitted = false
	_active_layer = 0
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
		_energy_label.text = "친환경 에너지 지수  %d / %d" % [village_energy, target_energy]
	if _title_label:
		_title_label.text = title_text
	if _caption_label:
		_caption_label.text = subtitle_text
	if _progress_label:
		var dots := ""
		for dot_index in range(scenes.size()):
			dots += "●" if dot_index == scene_index else "○"
			dots += "  " if dot_index < scenes.size() - 1 else ""
		_progress_label.text = "%s    클릭하여 다음 장면" % dots

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
	if scene_elapsed >= SCENE_DURATION:
		_advance_scene()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_advance_scene()
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_SPACE, KEY_ENTER]:
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
