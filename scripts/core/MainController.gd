extends Node2D
class_name MainController

## MainController: 메인 씬 라이프사이클 및 화면 전환(로비 ↔ 인게임 보드) 제어

@onready var lobby_ui: Control = $LobbyUI
@onready var game_board: Node2D = $GameBoard

func _ready() -> void:
	if lobby_ui:
		lobby_ui.start_game_requested.connect(_on_start_game_requested)
	switch_to_lobby()

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
