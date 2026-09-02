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
	if error == OK:
		print("[PASS] Lobby preview captured")
		quit(0)
	else:
		push_error("로비 미리보기 저장 실패: %s" % error)
		quit(1)
