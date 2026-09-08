extends Control
class_name TileMarker

## TileMarker: 보드판 위에 한글 타일명, 번호, 이벤트 아이콘 및 시각 효과를 렌더링하는 노드

var tile_index: int = 0
var tile_data: Dictionary = {}
var glow_panel: Panel
var label: Label
var icon_label: Label

func setup_tile(idx: int) -> void:
	tile_index = idx
	tile_data = BoardGrid.get_tile_data(idx)
	var pos = BoardGrid.get_tile_position(idx)
	
	# 50% 확대된 타일 크기: 220 x 96
	custom_minimum_size = Vector2(220, 96)
	position = pos - Vector2(110, 48)
	
	glow_panel = Panel.new()
	glow_panel.custom_minimum_size = Vector2(216, 92)
	glow_panel.position = Vector2(2, 2)
	glow_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(glow_panel)
	
	var sb = StyleBoxFlat.new()
	sb.set_corner_radius_all(14)
	sb.border_width_bottom = 3
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	
	var t_type = tile_data.get("type", BoardGrid.TileType.QUIZ_OX)
	var type_icon := "💡"
	var type_tag := "에너지 퀴즈"
	
	match t_type:
		BoardGrid.TileType.START:
			sb.bg_color = Color(0.08, 0.42, 0.22, 0.88)
			sb.border_color = Color(0.35, 1.0, 0.55)
			type_icon = "🚩"
			type_tag = "출발 지점"
		BoardGrid.TileType.FINISH:
			sb.bg_color = Color(0.68, 0.48, 0.08, 0.92)
			sb.border_color = Color(1.0, 0.92, 0.35)
			type_icon = "🏆"
			type_tag = "미래 그린 시티"
		BoardGrid.TileType.LADDER:
			sb.bg_color = Color(0.65, 0.46, 0.06, 0.88) # 황금 사다리
			sb.border_color = Color(1.0, 0.88, 0.32)
			type_icon = "🪜"
			type_tag = "스마트 사다리"
		BoardGrid.TileType.SLIDE:
			sb.bg_color = Color(0.58, 0.12, 0.15, 0.88) # 빨간색 미끄럼틀
			sb.border_color = Color(1.0, 0.35, 0.35)
			type_icon = "🛝"
			type_tag = "낭비 미끄럼틀"
		BoardGrid.TileType.POWERPLANT:
			sb.bg_color = Color(0.10, 0.38, 0.62, 0.88) # 청정 발전소
			sb.border_color = Color(0.32, 0.82, 1.0)
			type_icon = "⚡"
			type_tag = "친환경 발전소"
		BoardGrid.TileType.CHANCE_CARD:
			sb.bg_color = Color(0.22, 0.32, 0.55, 0.88)
			sb.border_color = Color(0.55, 0.78, 1.0)
			type_icon = "🎴"
			type_tag = "재료 보너스"
		BoardGrid.TileType.REST_TURN:
			sb.bg_color = Color(0.22, 0.38, 0.42, 0.85)
			sb.border_color = Color(0.55, 0.85, 0.88)
			type_icon = "☕"
			type_tag = "에코 쉼터"
		BoardGrid.TileType.MINIGAME:
			sb.bg_color = Color(0.42, 0.16, 0.58, 0.92)
			sb.border_color = Color(0.86, 0.50, 1.0)
			type_icon = "🎮"
			type_tag = "동시 미니게임"
		_:
			sb.bg_color = Color(0.14, 0.20, 0.30, 0.85) # 퀴즈 칸
			sb.border_color = Color(0.42, 0.68, 0.95)
			type_icon = "📝"
			type_tag = "객관식 퀴즈"
			
	glow_panel.add_theme_stylebox_override("panel", sb)
	
	# 내부 레이아웃 구성 (텍스트 크기 30%+ 확대 적용)
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	main_vbox.add_theme_constant_override("separation", 3)
	main_vbox.offset_left = 8
	main_vbox.offset_right = -8
	main_vbox.offset_top = 6
	main_vbox.offset_bottom = -6
	glow_panel.add_child(main_vbox)
	
	# 상단 헤더: 타일 번호 & 유형 뱃지
	var header_hbox = HBoxContainer.new()
	header_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	main_vbox.add_child(header_hbox)
	
	var num_lbl = Label.new()
	num_lbl.text = "NO.%02d" % idx
	num_lbl.add_theme_font_size_override("font_size", 16)
	num_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	num_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	num_lbl.add_theme_constant_override("outline_size", 4)
	header_hbox.add_child(num_lbl)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(spacer)
	
	var badge_lbl = Label.new()
	badge_lbl.text = "%s %s" % [type_icon, type_tag]
	badge_lbl.add_theme_font_size_override("font_size", 12)
	badge_lbl.add_theme_color_override("font_color", Color(0.9, 0.98, 1.0))
	badge_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	badge_lbl.add_theme_constant_override("outline_size", 3)
	header_hbox.add_child(badge_lbl)
	
	# 중앙 타일 이름 (기존 9 -> 13으로 44% 확대)
	var name_lbl = Label.new()
	var short_name = tile_data.get("name", "")
	name_lbl.text = short_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	main_vbox.add_child(name_lbl)
	
	# 하단 서브 설명 (11pt)
	var desc_lbl = Label.new()
	var desc_text: String = tile_data.get("desc", "")
	if desc_text.length() > 16:
		desc_text = desc_text.substr(0, 15) + ".."
	desc_lbl.text = desc_text
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.78, 0.92, 0.95, 0.85))
	desc_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	desc_lbl.add_theme_constant_override("outline_size", 2)
	desc_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	main_vbox.add_child(desc_lbl)
	
	# 마우스 호버 툴팁 및 인터랙션
	tooltip_text = "[%d번 칸: %s]\n%s" % [idx, tile_data.get("name", ""), tile_data.get("desc", "")]
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	if glow_panel:
		var tween = create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(glow_panel, "scale", Vector2(1.03, 1.03), 0.12)
		tween.tween_property(glow_panel, "modulate", Color(1.15, 1.15, 1.15), 0.12)

func _on_mouse_exited() -> void:
	if glow_panel:
		var tween = create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(glow_panel, "scale", Vector2.ONE, 0.12)
		tween.tween_property(glow_panel, "modulate", Color.WHITE, 0.12)
