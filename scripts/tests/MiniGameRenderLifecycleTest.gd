extends SceneTree

const ARCADES := {
	"solar_align": preload("res://scripts/minigames/SolarPanelDash3D.gd"),
	"wind_rhythm": preload("res://scripts/minigames/WindTurbinePilot3D.gd"),
	"grid_balance": preload("res://scripts/minigames/SmartGridBalance3D.gd"),
	"standby_hunt": preload("res://scripts/minigames/StandbyPowerHunt3D.gd"),
	"hydro_gate": preload("res://scripts/minigames/HydroGateRun3D.gd"),
	"energy_sort": preload("res://scripts/minigames/EnergySourceSort3D.gd"),
	"battery_relay": preload("res://scripts/minigames/BatteryShuttle3D.gd"),
	"eco_commute": preload("res://scripts/minigames/SharedSchoolBus3D.gd"),
	"heat_leak": preload("res://scripts/minigames/HeatLeakDash3D.gd"),
}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[RenderLifecycleTest] " + message)

func _run() -> void:
	await process_frame
	for id_variant in ARCADES.keys():
		var game_id := str(id_variant)
		var arcade: SubViewportContainer = ARCADES[game_id].new()
		root.add_child(arcade)
		var viewport: SubViewport = arcade.get("viewport")
		_check(is_instance_valid(viewport), "%s: 3D viewport가 필요합니다." % game_id)
		if is_instance_valid(viewport):
			arcade.call("set_running", false)
			_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "%s: 안내·대기 중 렌더링을 멈춰야 합니다." % game_id)
			arcade.call("set_running", true)
			_check(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "%s: 플레이 중 매 프레임 렌더링해야 합니다." % game_id)
			arcade.call("set_running", false)
			_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "%s: 종료 후 다시 렌더링을 멈춰야 합니다." % game_id)
		arcade.queue_free()
		await process_frame

	var modal_scene := load("res://scenes/MiniGameModal.tscn") as PackedScene
	var modal := modal_scene.instantiate()
	root.add_child(modal)
	await process_frame
	modal._on_minigame_started({"id": "solar_align", "round_id": 731, "duration": 30.0, "seed": 42})
	_check(modal.solar_arcade.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "안내 팝업 중 실제 미니게임 렌더링이 중지돼야 합니다.")
	modal._begin_local_round()
	_check(modal.solar_arcade.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "공통 시작 때 실제 미니게임 렌더링이 다시 켜져야 합니다.")
	modal._set_arcades_running(false)
	_check(modal.solar_arcade.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "점수 제출 대기 중 실제 미니게임 렌더링이 중지돼야 합니다.")
	modal.queue_free()
	await process_frame
	if failures.is_empty():
		print("[RenderLifecycleTest] PASS · 9 arcades pause/resume 3D rendering with game lifecycle")
	quit(0 if failures.is_empty() else 1)
