extends CanvasLayer

signal leave_requested

var title_label: Label
var detail_label: Label
var countdown_label: Label
var progress_bar: ProgressBar

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 150
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.07, 0.10, 0.91)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(570, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("12313f")
	style.border_color = Color("51dac2")
	style.set_border_width_all(2)
	style.set_corner_radius_all(24)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 30
	style.content_margin_bottom = 28
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	card.add_child(column)
	title_label = _label(column, 28, Color("fff0ae"))
	detail_label = _label(column, 20, Color("d8eeee"))
	detail_label.custom_minimum_size.x = 500
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	countdown_label = _label(column, 22, Color("87ead6"))
	progress_bar = ProgressBar.new()
	progress_bar.max_value = NetworkManager.RECONNECT_GRACE_SECONDS
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size.y = 16
	column.add_child(progress_bar)
	var leave_button := Button.new()
	leave_button.text = "게임 나가기 · 로비로 돌아가기"
	leave_button.custom_minimum_size.y = 48
	CommercialUI.apply_secondary_button(leave_button)
	leave_button.pressed.connect(func(): leave_requested.emit())
	column.add_child(leave_button)
	NetworkManager.recovery_state_changed.connect(show_state)
	visible = false

func _label(parent: Node, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func show_state(state: Dictionary) -> void:
	var mode := str(state.get("mode", "hidden"))
	visible = mode != "hidden"
	if not visible:
		return
	var remaining := int(state.get("remaining", 30))
	progress_bar.visible = mode != "failed"
	progress_bar.value = remaining
	countdown_label.text = "%d초 동안 다시 연결합니다" % remaining
	if mode == "waiting":
		title_label.text = "친구의 연결을 기다리고 있어요"
		detail_label.text = "%s님이 다시 연결 중입니다.\n게임 시간과 조작이 잠시 멈췄어요.\n돌아오지 않으면 AI가 이어서 플레이해요." % ", ".join(state.get("names", []))
	elif mode == "reconnecting":
		title_label.text = "다시 연결하고 있어요"
		detail_label.text = "원래 캐릭터와 점수로 돌아갈 준비 중입니다.\n게임 화면을 닫지 말고 잠시 기다려 주세요."
	else:
		title_label.text = "연결을 복구하지 못했어요"
		detail_label.text = str(state.get("message", "방장과의 연결이 끊어졌습니다."))
		var player_idx := NetworkManager.get_local_player_index()
		if player_idx >= 0 and player_idx < GameManager.players.size():
			var player: Dictionary = GameManager.players[player_idx]
			countdown_label.text = "마지막 확인 기록 · 에너지 %d · 퀴즈 정답 %d" % [int(player.get("energy", 0)), int(player.get("quiz_correct", 0))]
		else:
			countdown_label.text = "로비에서 새 게임에 참가할 수 있어요."
