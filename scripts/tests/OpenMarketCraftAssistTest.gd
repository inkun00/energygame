extends SceneTree

# OpenMarketCraftAssistTest.gd
# 오픈마켓 출품/획득 단계에서의 건설 가능 시설 확인, 완공 기회 감지, 레시피 팝오버 기능 검증

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("[FAIL] " + message)

func _run() -> void:
	print("--- Starting OpenMarketCraftAssistTest ---")
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	var gm = root.get_node("GameManager")
	var hud = main.find_child("HUD", true, false)
	check(hud != null, "HUD must exist in Main scene")
	check(gm != null, "GameManager autoload must exist")

	var configs: Array[Dictionary] = [
		{"name": "플레이어", "is_ai": false},
		{"name": "AI 1", "is_ai": true},
		{"name": "AI 2", "is_ai": true},
		{"name": "AI 3", "is_ai": true}
	]
	main._on_start_game_requested(configs, 600)
	await create_timer(0.2).timeout
	gm.set_process(false)

	# 1. 헬퍼 분석 로직 검증
	print("  1. Testing analysis helper functions...")
	# 태양광 발전소: solar_panel 2개 + battery 1개
	var inv1 := { "solar_panel": 2, "battery": 1 }
	var buildable = hud._get_player_buildable_projects(inv1)
	var found_solar := false
	for p in buildable:
		if p["name"] == "태양광 발전소":
			found_solar = true
			break
	check(found_solar, "solar power plant should be buildable with 2 solar panels and 1 battery")

	# 1개 부족한 상황 (battery만 있으면 태양광 완성)
	var inv2 := { "solar_panel": 2, "battery": 0 }
	var opp_battery = hud._get_item_completion_opportunity("battery", inv2)
	check(opp_battery["completes"].has("태양광 발전소"), "battery should complete the solar power plant")

	# 2. UI 노드 생성 확인
	print("  2. Testing UI node presence...")
	check(hud.open_market_panel != null, "open_market_panel must be created")
	check(hud.open_market_guide_banner != null, "open_market_guide_banner must exist")
	check(hud.open_market_guide_label != null, "open_market_guide_label must exist")
	check(hud.open_market_inspect_box != null, "open_market_inspect_box must exist")
	check(hud.open_market_inspect_label != null, "open_market_inspect_label must exist")
	check(hud.open_market_recipe_button != null, "open_market_recipe_button must exist")
	check(hud.open_market_recipe_popover != null, "open_market_recipe_popover must exist")

	# 3. 출품(OFFERING) 단계 분석 브리핑 테스트
	print("  3. Testing offering phase craft analysis...")
	gm.players[0]["inventory"] = { "wind_blade": 2, "smart_grid": 1, "battery": 1 }
	var state_offering := {
		"active": true,
		"phase": gm.OpenMarketPhase.OFFERING,
		"time_remaining": 20,
		"submitted_players": {},
		"player_count": 4
	}
	hud._on_open_market_state_changed(state_offering)
	check(hud.open_market_panel.visible, "Open market panel should be visible in offering phase")
	check(hud.open_market_guide_label.text.contains("풍력") or hud.open_market_guide_label.text.contains("즉시"),
		"Guide banner should announce wind farm immediate buildability")

	# 풍력 블레이드 판매 예정으로 지정 시 완공 불능 경고 인스펙션 확인
	hud.open_market_offer_selection["wind_blade"] = 1
	hud._inspect_open_market_item("wind_blade", gm.OpenMarketPhase.OFFERING, true)
	check(hud.open_market_inspect_label.text.contains("주의") or hud.open_market_inspect_label.text.contains("완공이 불가능"),
		"Inspector should warn that selling crucial component prevents wind farm construction")

	# 4. 획득(TAKING) 단계 완공 기회 분석 브리핑 테스트
	print("  4. Testing taking phase completion opportunity highlights...")
	gm.players[0]["inventory"] = { "hydro_turbine": 2 }
	var state_taking := {
		"active": true,
		"phase": gm.OpenMarketPhase.TAKING,
		"time_remaining": 15,
		"allowances": { 0: 2 },
		"taken_counts": { 0: 0 },
		"stock": { "smart_grid": 2, "solar_panel": 1 }
	}
	hud._on_open_market_state_changed(state_taking)
	check(hud.open_market_guide_label.text.contains("완성") or hud.open_market_guide_label.text.contains("기회"),
		"Taking guide banner should highlight completion opportunity")

	# 인스펙터 호버 테스트: smart_grid 호버 시 즉시 완공 브리핑
	hud._inspect_open_market_item("smart_grid", gm.OpenMarketPhase.TAKING, true)
	check(hud.open_market_inspect_label.text.contains("즉시 완공") or hud.open_market_inspect_label.text.contains("완성"),
		"Inspector should highlight immediate completion when inspecting smart_grid")

	# 5. 10종 레시피 팝오버 토글 테스트
	print("  5. Testing 10-project recipe popover...")
	check(not hud.open_market_recipe_popover.visible, "Popover should be hidden initially")
	hud._toggle_open_market_recipe_popover()
	check(hud.open_market_recipe_popover.visible, "Popover should be visible after toggle")
	check(hud.open_market_recipe_grid.get_child_count() == gm.CONSTRUCTION_PROJECTS.size(),
		"Popover must contain all 10 construction projects")
	hud._toggle_open_market_recipe_popover()
	check(not hud.open_market_recipe_popover.visible, "Popover should hide on toggle again")

	if failures.is_empty():
		print("[PASS] OpenMarketCraftAssistTest: All craft analysis and recipe checks passed!")
		quit()
	else:
		printerr("[FAIL] OpenMarketCraftAssistTest failed with %d errors" % failures.size())
		quit(1)
