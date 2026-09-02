extends Node

## NetworkManager: 4인 온라인 멀티플레이어 (ENet / RPC) 및 룸/로비 동기화

signal connection_succeeded
signal connection_failed
signal server_disconnected
signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal game_started_signal

const DEFAULT_PORT: int = 8910
const MAX_PLAYERS: int = 4

var is_online: bool = false
var is_host: bool = false
var my_peer_id: int = 1

# 연결된 플레이어 정보 목록 { peer_id: { "name": String, "char_id": String, "is_ai": bool } }
var connected_players: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_room(port: int = DEFAULT_PORT) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, MAX_PLAYERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		is_online = true
		is_host = true
		my_peer_id = 1
		print("[Network] 4인 멀티플레이어 호스트 서버 개설 완료! (포트: %d)" % port)
	return err

func join_room(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		is_online = true
		is_host = false
		print("[Network] 서버 연결 시도 중: %s:%d" % [address, port])
	return err

func disconnect_network() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_online = false
	is_host = false
	connected_players.clear()

func _on_peer_connected(id: int) -> void:
	print("[Network] 플레이어 입장: %d" % id)

func _on_peer_disconnected(id: int) -> void:
	print("[Network] 플레이어 퇴장: %d" % id)
	if connected_players.has(id):
		connected_players.erase(id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	my_peer_id = multiplayer.get_unique_id()
	print("[Network] 서버 접속 성공! 내 Peer ID: %d" % my_peer_id)
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("[Network] 서버 접속 실패!")
	connection_failed.emit()
	disconnect_network()

func _on_server_disconnected() -> void:
	print("[Network] 서버와의 연결이 끊어졌습니다.")
	server_disconnected.emit()
	disconnect_network()

# ----------------- RPC 동기화 메서드 -----------------

@rpc("any_peer", "call_local", "reliable")
func rpc_register_player(info: Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id
	connected_players[sender_id] = info
	player_connected.emit(sender_id, info)

@rpc("authority", "call_local", "reliable")
func rpc_start_game() -> void:
	game_started_signal.emit()

@rpc("any_peer", "call_local", "reliable")
func rpc_roll_dice(player_idx: int, dice_val: int) -> void:
	if GameManager:
		GameManager.on_network_dice_rolled(player_idx, dice_val)

@rpc("any_peer", "call_local", "reliable")
func rpc_submit_quiz(player_idx: int, is_correct: bool) -> void:
	if GameManager:
		GameManager.on_network_quiz_resolved(player_idx, is_correct)
