extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var lobby: Node = main.get_node_or_null("LobbyUI")
	if not lobby:
		push_error("LobbyUI를 찾을 수 없습니다.")
		quit(1)
		return
	var game_manager: Node = root.get_node("GameManager")
	for index in range(lobby.characters.size()):
		lobby._on_character_selected(index)
		var character: Dictionary = lobby.characters[index]
		var skill: Dictionary = game_manager.SPECIAL_SKILLS_BY_ICON.get(str(character["icon"]), game_manager.DEFAULT_SPECIAL_SKILL)
		var target_type := str(skill.get("target_type", "tile"))
		var expected_target := "자신에게 즉시 적용" if target_type == "self" else ("플레이어 지정" if target_type == "player" else "타일 지정")
		var skill_header: String = lobby.skill_name_label.text
		var skill_body: String = lobby.skill_description_label.text
		if not skill_header.contains(str(skill.get("name", ""))):
			push_error("%s의 특수기술 이름이 소개 창에 표시되지 않았습니다." % character["name"])
			quit(1)
			return
		if not skill_header.contains("필요 SP %d" % int(skill.get("cost", 0))) or not skill_header.contains(expected_target):
			push_error("%s의 특수기술 비용 또는 대상 정보가 올바르지 않습니다." % character["name"])
			quit(1)
			return
		if not skill_body.contains(str(skill.get("description", ""))) or not skill_body.contains("사용 후에도 주사위를 굴릴 수 있습니다"):
			push_error("%s의 특수기술 효과 설명이 올바르지 않습니다." % character["name"])
			quit(1)
			return
	lobby._select_character_from_button(4) # White-furred rabbit: strongest alpha-regression case.
	await create_timer(1.1).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png("res://.godot/lobby_preview.png")
	if error != OK:
		push_error("로비 미리보기 저장 실패: %s" % error)
		quit(1)
		return
	lobby._room_browser._loaded_once = true
	lobby.mode_option_button.select(1)
	lobby._on_mode_selected(1)
	lobby._room_browser._receive_rooms([
		{"code": "267302", "title": "함께 지구를 지켜요!", "host_name": "로코코", "max_players": 4, "player_count": 2, "password_required": 0},
		{"code": "345678", "title": "우리 반 친구들의 에너지 모험", "host_name": "울랄라", "max_players": 3, "player_count": 1, "password_required": 1},
		{"code": "456789", "title": "둘이서 도전하는 왕국 복원", "host_name": "에코", "max_players": 2, "player_count": 2, "password_required": 0}
	])
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://.godot/room_browser_preview.png")
	lobby._room_browser.hide()
	await process_frame
	await create_timer(0.15).timeout
	var multiplayer_image := root.get_texture().get_image()
	var multiplayer_error := multiplayer_image.save_png("res://.godot/multiplayer_lobby_preview.png")
	if multiplayer_error != OK:
		push_error("멀티플레이 로비 미리보기 저장 실패: %s" % multiplayer_error)
		quit(1)
		return
	var network: Node = root.get_node("NetworkManager")
	network.is_online = true
	network.is_host = true
	network.room_code = "267302"
	var roster := {
		1: {"name": "로코코", "char_icon": lobby.characters[0]["icon"]},
		2: {"name": "울랄라", "char_icon": lobby.characters[4]["icon"]}
	}
	lobby._on_room_state_changed(roster)
	await process_frame
	await process_frame
	if not lobby._room_popup.visible or lobby._room_cards.get_child_count() != 4 or lobby._room_start_button.disabled:
		push_error("방장 팝업 또는 참가자 카드 표시 실패")
		quit(1)
		return
	root.get_texture().get_image().save_png("res://.godot/online_room_popup_preview.png")
	network.is_host = false
	network.my_peer_id = 2
	roster.erase(1)
	lobby._on_room_state_changed(roster)
	if not lobby._room_start_button.disabled or lobby._room_count_label.text != "1 / 4명":
		push_error("참가자 시작 제한 또는 퇴장 인원 갱신 실패")
		quit(1)
		return
	lobby._leave_room_popup()
	if lobby._room_popup.visible or network.is_online or not lobby.nickname_edit.editable:
		push_error("방 나가기 후 로비 복원 실패")
		quit(1)
		return
	# 선택한 정원은 실제 게임과 AI 채움에도 적용됩니다.
	for capacity in [2, 3, 4]:
		network.is_online = true
		network.is_host = true
		network.room_capacity = capacity
		var configs: Array[Dictionary] = [{"name": "테스트", "is_ai": false}]
		game_manager.setup_game(configs)
		if game_manager.players.size() != capacity or game_manager.ai_fill_count != capacity - 1:
			push_error("온라인 방 정원과 AI 인원이 일치하지 않습니다.")
			quit(1)
			return
		game_manager.stop_game()
	network.disconnect_network()
	print("[PASS] Lobby previews, room roster updates, guest start restriction and leave reset")
	quit(0)
