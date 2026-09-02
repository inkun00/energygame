extends SceneTree

## UI 없이 프로젝트의 NetworkManager를 사용해 로컬 ENet 호스트를 실행합니다.

func _initialize() -> void:
	call_deferred("_start_server")

func _start_server() -> void:
	var network_manager = root.get_node_or_null("NetworkManager")
	if network_manager == null:
		push_error("[DedicatedServer] NetworkManager autoload를 찾을 수 없습니다.")
		quit(1)
		return

	var error: Error = network_manager.create_room(network_manager.DEFAULT_PORT)
	if error != OK:
		push_error("[DedicatedServer] 서버 개설 실패: %s" % error_string(error))
		quit(error)
		return

	network_manager.player_connected.connect(func(peer_id: int, info: Dictionary):
		print("[DedicatedServer] 플레이어 등록: %d / %s" % [peer_id, info.get("name", "이름 없음")])
	)
	network_manager.player_disconnected.connect(func(peer_id: int):
		print("[DedicatedServer] 플레이어 연결 종료: %d" % peer_id)
	)
	print("[DedicatedServer] READY udp://0.0.0.0:%d" % network_manager.DEFAULT_PORT)
