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
	lobby._room_browser._loaded_once = true
	lobby._on_mode_selected(1)
	await settle()
	check(root.content_scale_size == Vector2i(1280, 720) and lobby._room_browser.visible, "Online rooms retain their full dialog canvas")
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
