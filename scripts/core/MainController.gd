extends Node2D
class_name MainController

## MainController: 메인 씬 라이프사이클 및 화면 전환(로비 ↔ 인게임 보드) 제어

@onready var lobby_ui: Control = $LobbyUI
@onready var game_board: Node2D = $GameBoard

var session_open := false
var exit_confirmation: ConfirmationDialog

func _create_exit_confirmation() -> void:
	exit_confirmation = ConfirmationDialog.new()
	exit_confirmation.title = "게임 종료"
	exit_confirmation.dialog_text = "게임을 종료하고 로비로 돌아갈까요?\n진행 중인 게임으로 돌아올 수 없습니다.\n확인창을 보는 동안에도 게임 시간은 흐릅니다."
	exit_confirmation.ok_button_text = "게임 종료"
	exit_confirmation.cancel_button_text = "계속 플레이"
	exit_confirmation.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	add_child(exit_confirmation)
	exit_confirmation.confirmed.connect(switch_to_lobby)
	exit_confirmation.get_cancel_button().pressed.connect(exit_confirmation.hide)
	CommercialUI.apply_secondary_button(exit_confirmation.get_ok_button(), CommercialUI.DANGER)
	CommercialUI.apply_primary_button(exit_confirmation.get_cancel_button())

func _set_session_open(value: bool) -> void:
	session_open = value
	if not value and exit_confirmation:
		exit_confirmation.hide()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if (window.energyGameSetExitGuard) window.energyGameSetExitGuard(%s);" % ("true" if value else "false"))

func request_game_exit() -> void:
	if not session_open or exit_confirmation.visible:
		return
	exit_confirmation.popup_centered(Vector2i(540, 210))
	exit_confirmation.get_cancel_button().grab_focus()

func _input(event: InputEvent) -> void:
	if session_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		request_game_exit()
		get_viewport().set_input_as_handled()

func _ready() -> void:
	_create_exit_confirmation()
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
	if game_board and game_board.has_method("begin_render_warmup"):
		game_board.begin_render_warmup()
		# 첫 프레임에서 셰이더를 컴파일하고 다음 프레임까지 실제 출력이 끝났는지
		# 확인한 뒤 로딩 화면을 닫습니다.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		game_board.end_render_warmup()
	else:
		await RenderingServer.frame_post_draw
	JavaScriptBridge.eval("if (window.energyGameReady) window.energyGameReady();")

func switch_to_lobby() -> void:
	_set_session_open(false)
	if GameManager:
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
	_set_session_open(true)
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
	_set_session_open(false)
	if GameManager:
		GameManager.stop_game()
	if game_board and game_board.has_method("stop_board_game"):
		game_board.stop_board_game()
	if lobby_ui:
		lobby_ui.visible = true
		if lobby_ui.has_method("reset_network_controls"):
			lobby_ui.reset_network_controls("방장과의 연결이 끊어져 로비로 돌아왔습니다.")
