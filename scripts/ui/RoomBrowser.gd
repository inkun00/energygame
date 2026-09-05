extends Control

signal create_requested(settings)
signal join_requested(code, password)

const UI = preload("res://scripts/ui/CommercialUI.gd")
var _loaded_once := false
var _rows: VBoxContainer
var _status: Label
var _refresh: Button
var _create: Button
var _title: LineEdit
var _capacity: OptionButton
var _password_enabled: CheckBox
var _password: LineEdit
var _password_dialog: ConfirmationDialog
var _join_password: LineEdit
var _selected_code := ""
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.04, 0.06, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1120, 610)
	panel.add_theme_stylebox_override("panel", UI.padded_panel(UI.PANEL, UI.TEAL_DARK, 26, 20))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var heading := _label("온라인 모험 · 방 목록", 30)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var back := _button("돌아가기", false)
	back.pressed.connect(hide)
	header.add_child(back)
	content.add_child(_label("처음 입장할 때 목록을 불러옵니다. 최신 목록은 새로고침을 눌러 확인하세요.", 17))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var list_column := VBoxContainer.new()
	list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_column.add_theme_constant_override("separation", 12)
	columns.add_child(list_column)
	_refresh = _button("방 목록 새로고침", false)
	_refresh.pressed.connect(_request_refresh)
	list_column.add_child(_refresh)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_rows)
	_status = _label("", 16)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 42
	list_column.add_child(_status)
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 340
	form.add_theme_constant_override("separation", 12)
	columns.add_child(form)
	form.add_child(_label("새 방 만들기", 25))
	form.add_child(_label("방 제목", 17))
	_title = LineEdit.new()
	_title.max_length = 40
	_title.text = "함께하는 에너지 모험"
	UI.apply_input(_title)
	form.add_child(_title)
	form.add_child(_label("최대 인원 (AI 포함)", 17))
	_capacity = OptionButton.new()
	for count in range(2, 5):
		_capacity.add_item("%d명" % count, count)
	_capacity.select(2)
	UI.apply_input(_capacity)
	form.add_child(_capacity)
	_password_enabled = CheckBox.new()
	_password_enabled.text = "비밀번호 설정 (선택)"
	form.add_child(_password_enabled)
	_password = LineEdit.new()
	_password.secret = true
	_password.max_length = 64
	_password.placeholder_text = "비밀번호 입력"
	_password.editable = false
	UI.apply_input(_password)
	form.add_child(_password)
	_password_enabled.toggled.connect(func(enabled: bool):
		_password.editable = enabled
		if not enabled:
			_password.clear()
	)
	var note := _label("빈 자리는 설정한 인원까지 AI가 채웁니다.", 16)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(note)
	_create = _button("방 만들기", true)
	_create.custom_minimum_size.y = 52
	_create.pressed.connect(_create_room)
	form.add_child(_create)
	_password_dialog = ConfirmationDialog.new()
	_password_dialog.title = "비밀번호가 있는 방"
	_password_dialog.ok_button_text = "참가"
	_password_dialog.cancel_button_text = "취소"
	add_child(_password_dialog)
	_join_password = LineEdit.new()
	_join_password.secret = true
	_join_password.max_length = 64
	_join_password.placeholder_text = "방 비밀번호를 입력하세요"
	_join_password.custom_minimum_size = Vector2(360, 48)
	UI.apply_input(_join_password)
	_password_dialog.add_child(_join_password)
	_password_dialog.confirmed.connect(_confirm_password)
	NetworkManager.room_list_received.connect(_receive_rooms)
	NetworkManager.room_list_failed.connect(show_error)
	hide()

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UI.TEXT)
	return label

func _button(value: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = value
	if primary:
		UI.apply_primary_button(button)
	else:
		UI.apply_secondary_button(button)
	return button

func open_browser() -> void:
	show()
	if not _loaded_once:
		_loaded_once = true
		_request_refresh()

func _request_refresh() -> void:
	if _busy:
		return
	_refresh.disabled = true
	_status.text = "방 목록을 가져오는 중..."
	NetworkManager.request_room_list()

func _receive_rooms(rooms: Array) -> void:
	_refresh.disabled = _busy
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for room in rooms:
		if not (room is Dictionary):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var description := VBoxContainer.new()
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := _label(str(room.get("title", "에너지 모험")), 21)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.tooltip_text = title.text
		description.add_child(title)
		var locked := bool(room.get("password_required", false))
		var count := int(room.get("player_count", 0))
		var capacity := int(room.get("max_players", 4))
		var detail := _label("%s · %d/%d명 · %s" % [str(room.get("host_name", "방장")), count, capacity, "비밀번호 있음" if locked else "공개 방"], 16)
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		description.add_child(detail)
		row.add_child(description)
		var join := _button("참가" if count < capacity else "인원 가득 참", false)
		join.custom_minimum_size = Vector2(130, 58)
		join.disabled = count >= capacity or _busy or not OS.has_feature("web")
		join.pressed.connect(_select_room.bind(str(room.get("code", "")), locked))
		row.add_child(join)
		_rows.add_child(row)
	_status.text = "현재 표시된 방 %d개 · 목록은 자동으로 갱신되지 않습니다." % rooms.size() if not rooms.is_empty() else "생성된 방이 없습니다. 새 방을 만들거나 새로고침해 주세요."
	if not OS.has_feature("web"):
		_status.text = "웹 방 목록입니다. 목록의 방은 웹 버전에서 참가할 수 있습니다."

func _select_room(code: String, locked: bool) -> void:
	if _busy:
		return
	_selected_code = code
	if locked:
		_password_dialog.title = "비밀번호가 있는 방"
		_join_password.clear()
		_password_dialog.popup_centered(Vector2i(420, 150))
		_join_password.grab_focus()
	else:
		_join(code, "")

func prompt_code_join(code: String) -> void:
	_selected_code = code
	_password_dialog.title = "방 참가 · 비밀번호가 없으면 비워 두세요"
	_join_password.clear()
	_password_dialog.popup_centered(Vector2i(480, 150))
	_join_password.grab_focus()

func _confirm_password() -> void:
	if _join_password.has_ime_text():
		_join_password.apply_ime()
	_join(_selected_code, _join_password.text)

func _join(code: String, password: String) -> void:
	set_busy(true)
	_status.text = "게임방에 연결하는 중..."
	join_requested.emit(code, password)
	_join_password.clear()

func _create_room() -> void:
	if _busy:
		return
	if _title.has_ime_text():
		_title.apply_ime()
	if _password.has_ime_text():
		_password.apply_ime()
	if _title.text.strip_edges().is_empty():
		show_error("방 제목을 입력해 주세요.")
		return
	if _password_enabled.button_pressed and _password.text.is_empty():
		show_error("비밀번호를 입력하거나 비밀번호 설정을 해제해 주세요.")
		return
	set_busy(true)
	create_requested.emit({"title": _title.text.strip_edges(), "max_players": _capacity.get_selected_id(), "password": _password.text if _password_enabled.button_pressed else ""})
	_password.clear()

func set_busy(value: bool) -> void:
	_busy = value
	_create.disabled = value
	_refresh.disabled = value

func show_error(message: String) -> void:
	set_busy(false)
	_status.text = message
