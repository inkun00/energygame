extends Node

## Lobby, board and arcade reflow in portrait. Fixed-size dialogs retain their
## authored canvas until they close, including during online recovery.
const DESKTOP_SIZE := Vector2i(1280, 720)
const PORTRAIT_WIDTH := 680
var board: GameBoardController
var standalone: CanvasLayer
var lobby: LobbyUI
var last_lobby_size := Vector2i.ZERO
var last_board_size := Vector2i.ZERO
var web_portrait_hint := false

func setup(game_board: GameBoardController, lobby_view: LobbyUI, arcade_hub: CanvasLayer) -> void:
	lobby = lobby_view
	board = game_board
	standalone = arcade_hub
	get_window().size_changed.connect(refresh)
	board.layout_state_changed.connect(refresh)
	lobby.visibility_changed.connect(refresh)
	lobby.portrait_layout_changed.connect(refresh)
	for overlay in [board.hud.lap_reward_panel, board.hud.special_skill_target_panel]:
		overlay.visibility_changed.connect(refresh)
	if is_instance_valid(standalone):
		standalone.modal.visibility_changed.connect(refresh)
		standalone.menu.visibility_changed.connect(refresh)
	refresh()

func refresh() -> void:
	var window := get_window()
	var native_size := window.size
	if native_size.x <= 0 or native_size.y <= 0:
		return
	var portrait := native_size.y > native_size.x
	var board_game := board.board_surface_active and board.visible
	var arcade: bool = (board_game and board.minigame_modal.visible) or (is_instance_valid(standalone) and standalone.modal.visible)
	var board_play: bool = board_game and not GameManager.guided_tutorial_active and not board.hud.special_skill_target_panel.visible and not board.hud.lap_reward_panel.visible and (not board._board_overlay_is_visible() or GameManager.adventure_waiting_for_start)
	var arcade_menu: bool = is_instance_valid(standalone) and standalone.menu.visible
	var lobby_open: bool = lobby.supports_portrait_layout()
	var layout_adapts := arcade or arcade_menu or board_play or lobby_open
	var show_hint := portrait and not layout_adapts
	if OS.has_feature("web") and web_portrait_hint != show_hint:
		web_portrait_hint = show_hint
		JavaScriptBridge.eval("if (window.energyGameSetPortraitHint) window.energyGameSetPortraitHint(%s)" % ("true" if show_hint else "false"))
	var target := DESKTOP_SIZE
	if portrait and layout_adapts:
		var base_width := 600 if lobby_open else PORTRAIT_WIDTH
		target = Vector2i(base_width, roundi(float(base_width) * native_size.y / native_size.x))
	elif arcade and MiniGameInput.uses_touch() and native_size.x > native_size.y * 1.8:
		target = Vector2i(roundi(720.0 * native_size.x / native_size.y), 720)
	if window.content_scale_size != target:
		window.content_scale_size = target
	var lobby_size := target if portrait and lobby_open else DESKTOP_SIZE
	if lobby_size != last_lobby_size:
		last_lobby_size = lobby_size
		lobby.apply_lobby_layout(Vector2(lobby_size), lobby_size != DESKTOP_SIZE)
	var board_size := target if portrait and board_play and not arcade else DESKTOP_SIZE
	if board_size != last_board_size:
		last_board_size = board_size
		board.viewport_container.size = Vector2(board_size)
		board.camera3d.keep_aspect = Camera3D.KEEP_WIDTH if board_size != DESKTOP_SIZE else Camera3D.KEEP_HEIGHT
		board.hud.apply_board_layout(Vector2(board_size), board_size != DESKTOP_SIZE)
