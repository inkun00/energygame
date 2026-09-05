extends Node2D
class_name MainController

## MainController: 메인 씬 라이프사이클 및 화면 전환(로비 ↔ 인게임 보드) 제어

@onready var lobby_ui: Control = $LobbyUI
@onready var game_board: Node2D = $GameBoard

func _ready() -> void:
	if lobby_ui:
		lobby_ui.start_game_requested.connect(_on_start_game_requested)
	if NetworkManager:
		if not NetworkManager.game_started_signal.is_connected(_on_network_game_started):
			NetworkManager.game_started_signal.connect(_on_network_game_started)
		if not NetworkManager.server_disconnected.is_connected(_on_network_server_disconnected):
			NetworkManager.server_disconnected.connect(_on_network_server_disconnected)
	switch_to_lobby()
	if OS.has_feature("web"):
		_finish_web_loading.call_deferred()


func _finish_web_loading() -> void:
	await RenderingServer.frame_post_draw
	JavaScriptBridge.eval("if (window.energyGameReady) window.energyGameReady();")

func switch_to_lobby() -> void:
	if GameManager and GameManager.is_game_active:
		GameManager.stop_game()
	if NetworkManager and NetworkManager.is_online:
		NetworkManager.disconnect_network()
	if game_board and game_board.has_method("stop_board_game"):
		game_board.stop_board_game()
	elif game_board and game_board.has_method("set_board_active"):
		game_board.set_board_active(false)
	elif game_board:
		game_board.visible = false
	if lobby_ui:
		lobby_ui.visible = true
		if lobby_ui.has_method("reset_network_controls"):
			lobby_ui.reset_network_controls()

func _on_start_game_requested(player_configs: Array[Dictionary], duration_seconds: int = GameManager.DEFAULT_GAME_DURATION_SECONDS) -> void:
	if lobby_ui:
		lobby_ui.visible = false
	if game_board:
		if game_board.has_method("set_board_active"):
			game_board.set_board_active(true)
		else:
			game_board.visible = true
		if game_board.has_method("start_board_game"):
			game_board.start_board_game(player_configs, duration_seconds)


func _on_network_game_started(player_configs: Array[Dictionary], duration_seconds: int) -> void:
	_on_start_game_requested(player_configs, duration_seconds)


func _on_network_server_disconnected() -> void:
	if GameManager:
		GameManager.stop_game()
	if game_board and game_board.has_method("stop_board_game"):
		game_board.stop_board_game()
	if lobby_ui:
		lobby_ui.visible = true
		if lobby_ui.has_method("reset_network_controls"):
			lobby_ui.reset_network_controls("방장과의 연결이 끊어져 로비로 돌아왔습니다.")
