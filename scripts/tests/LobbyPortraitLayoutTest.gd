extends SceneTree

var failures: Array[String] = []
var lobby: Control

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures.append(description)
		push_error(description)

func settle() -> void:
	for frame in range(4): await process_frame

func _run() -> void:
	root.size = Vector2i(390, 844)
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	lobby = main.lobby_ui
	await settle()
	var phone: Vector2 = root.content_scale_size
	check(phone.x == 600 and phone.y > 1200 and lobby.size == phone, "Portrait lobby uses the entire phone canvas")
	var bounds := Rect2(Vector2.ZERO, phone)
	for control in [lobby.game_time_option_button, lobby.learning_grade_option, lobby.quiz_challenge_option, lobby.reading_time_toggle, lobby.local_start_button, lobby.character_choose_button]:
		check(bounds.encloses(control.get_global_rect()) and control.size.y >= 60, "All initial choices are visible and touch-sized: " + str(control.name))
	check(not lobby.get_node("TopBar/TopActions").get_global_rect().intersects(lobby.character_choose_button.get_global_rect()), "Top actions leave room for the hero summary")
	lobby.character_choose_button.pressed.emit()
	await settle()
	check(root.content_scale_size == Vector2i(1280, 720) and lobby.character_gallery.visible, "Portrait hero gallery temporarily opens its complete authored canvas")
	lobby._character_buttons[5].pressed.emit()
	await settle()
	check(lobby.size == phone and lobby.char_option_button.selected == 5, "Hero selection returns to the full-height form and keeps the chosen character")
	OS.set_environment("ENERGYGAME_ROOM_DIRECTORY_URL", "")
	ProjectSettings.set_setting("network/room_directory_url", "")
	lobby._on_mode_selected(1)
	await settle()
	check(root.content_scale_size == Vector2i(1280, 720) and lobby._room_browser.visible, "Online rooms retain their full dialog canvas")
	exercise_room_browser()
	lobby._room_browser._close_browser()
	await settle()
	check(lobby.size == phone, "Closing online rooms restores the phone")
	lobby._on_local_start_pressed()
	for page in range(3): lobby.opening_next_button.pressed.emit()
	await settle()
	check(lobby.story_school.is_visible_in_tree() and lobby.opening_caption.text.contains("링고"), "The tall story includes the selected hero and the school")
	var art: Rect2 = lobby.opening_image.get_global_rect()
	var caption: Rect2 = lobby.opening_caption.get_global_rect()
	check(bounds.encloses(art) and art.end.y < caption.position.y and caption.end.y < lobby.opening_next_button.position.y, "Art, caption and Next are fully inside the tall screen in reading order")
	root.size = Vector2i(1280, 720)
	await settle()
	check(lobby.size == Vector2(1280, 720) and lobby.opening_image.get_global_rect() == Rect2(0, 0, 1280, 720), "Rotating back restores the full-bleed landscape story")
	lobby.hero_glow.hide()
	root.size = Vector2i(390, 844)
	await settle()
	root.size = Vector2i(1280, 720)
	await settle()
	check(not lobby.hero_glow.visible, "Returning to landscape preserves an intentionally hidden hero effect")
	main.queue_free()
	await settle()
	if failures.is_empty(): print("[PASS] Lobby portrait: full-height settings, modals return, hero story, landscape restoration")
	quit(0 if failures.is_empty() else 1)

func exercise_room_browser() -> void:
	var browser = lobby._room_browser
	var network = root.get_node("NetworkManager")
	var joins: Array = []
	var capture := func(code, password): joins.append([code, password])
	browser.join_requested.disconnect(lobby._join_listed_room)
	browser.join_requested.connect(capture)
	for control in [browser._code, browser._join_code]:
		check(browser.get_global_rect().encloses(control.get_global_rect()) and control.size.y >= 44, "Room code controls fit on the touch canvas")
	browser._code.text = "12"
	browser._join_code.pressed.emit()
	check(not browser._password_dialog.visible and joins.is_empty(), "Incomplete codes do not request admission")
	browser._code.text = "123456"
	browser._code.text_submitted.emit(browser._code.text)
	check(browser._password_dialog.visible, "Submitting a code opens the optional password dialog")
	browser._join_password.text = "classroom"
	browser._join_password.text_submitted.emit(browser._join_password.text)
	check(joins == [["123456", "classroom"]], "Enter submits the password and code once")
	var joining_status: String = browser._status.text
	network.room_list_failed.emit("late list error")
	check(browser._busy and browser._status.text == joining_status, "A room-list error cannot interrupt a pending join")
	browser._join_code.pressed.emit()
	check(joins.size() == 1, "A pending join cannot be submitted twice")
	browser.show_error("wrong password")
	network.room_list_received.emit([
		{"code": "234567", "player_count": 1, "max_players": 4},
		{"code": "345678", "player_count": 2, "max_players": 2},
		{"code": "456789", "player_count": 0, "max_players": 4},
		{"code": "567890", "player_count": 1, "max_players": 2, "password_required": true}
	])
	check(browser._status.text == "wrong password" and not browser._join_code.disabled, "A failed join keeps its error and permits a retry while the list updates")
	check(browser._rows.get_child_count() == 3 and browser._rows.get_child(1).get_child(1).disabled, "Empty rooms disappear and full rooms cannot be joined")
	browser._rows.get_child(2).get_child(1).pressed.emit()
	check(browser._password_dialog.visible and browser._join_password.text.is_empty(), "Locked rooms prompt for a fresh password")
	browser._join_password.text = "correct"
	browser._password_dialog.get_ok_button().pressed.emit()
	check(joins.back() == ["567890", "correct"], "The listed private room submits the correct code and password")
	browser.show_error("connection failed")
	browser._join_code.pressed.emit()
	browser._password_dialog.get_ok_button().pressed.emit()
	check(joins.back() == ["123456", ""], "A public room code accepts an empty password")
	browser.show_error("connection failed")
	browser._rows.get_child(0).get_child(1).pressed.emit()
	check(joins.back() == ["234567", ""], "The public room button submits its own code without a password")
	browser._close_browser()
	browser.open_browser()
	check(not browser._busy and browser._rows.get_child_count() == 0, "Reopening clears stale rooms and cancels any previous join")
	browser.join_requested.disconnect(capture)
	browser.join_requested.connect(lobby._join_listed_room)
	browser.join_requested.emit("12", "")
	check(browser._status.text.contains("숫자 6자리"), "A rejected code shows code-specific guidance")
