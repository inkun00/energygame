extends Control

## A separate, silent scene. Only presentation state advances: no input polling,
## scoring, round clock, readiness, practice progress or network callbacks.
const CAPTIONS := {
	"solar_align": ["A / D", "햇빛을 정면으로 받는 패널로", "패널을 지나 발전!"],
	"wind_rhythm": ["A / D", "바람과 터빈 방향 맞추기", "방향이 맞으면 발전!"],
	"grid_balance": ["W / ↑", "공급 막대를 수요에 맞추기", "차이가 작아지면 불빛 안정!"],
	"standby_hunt": ["D → Space", "꺼진 기기의 플러그 뽑기", "대기전력 차단!"],
	"hydro_gate": ["Space × 3", "물이 모인 뒤 레버 연타", "물의 낙차로 터빈 회전!"],
	"energy_sort": ["A / ←", "에너지원을 알맞은 곳으로", "분류 완료!"],
	"battery_relay": ["A / D", "남는 전기를 배터리에 저장", "흐릴 때 도시로 공급!"],
	"eco_commute": ["D → S → Space", "정류장에 멈춰 학생 태우기", "함께 타고 출발!"],
	"heat_leak": ["A → Space", "열린 창문에 다가가 닫기", "더운 공기를 막았어요!"],
}
const OBJECTIVES := {
	"solar_align": "햇빛을 정면으로 받는 패널을 지나 전기를 모아요.",
	"wind_rhythm": "바람에 맞춰 발전하고, 위험한 돌풍에는 터빈을 멈춰요.",
	"grid_balance": "도시의 전력 수요와 공급의 차이를 줄여요.",
	"standby_hunt": "꺼진 기기의 대기전력을 차단해요. 사용 중인 기기는 그대로 두어요.",
	"hydro_gate": "물을 모아 낙차를 키우고, 넘치기 전에 수문을 열어 발전해요.",
	"energy_sort": "에너지원을 자연에서 다시 얻는 것과 곧 다시 생기지 않는 것으로 나눠요.",
	"battery_relay": "남는 전기를 저장하고, 흐릴 때 도시로 가져가요.",
	"eco_commute": "학생들을 함께 태우고 학교 정차선에 정확히 멈춰 내려 줘요.",
	"heat_leak": "열린 창문을 닫아 더운 공기를 막고 냉방 전기를 아껴요.",
}

var arcade: SubViewportContainer
var game_id := ""
var preview_time := 0.0
var caption: Label
var key_badge: Label
var progress: ProgressBar
var demo_record: Dictionary = {}
var demo_animators: Array[AnimationPlayer] = []

func _ready() -> void:
	name = "ActionDemonstration"
	clip_contents = true
	custom_minimum_size = Vector2(0, 196)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_sync_visibility)

func configure(scene_script: Script, id: String, player: Dictionary, seed_value: int) -> void:
	clear()
	game_id = id
	preview_time = 0.0
	demo_record = {}
	arcade = scene_script.new() as SubViewportContainer
	arcade.name = "DemonstrationScene"
	add_child(arcade)
	arcade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arcade.offset_bottom = -42
	arcade.custom_minimum_size = Vector2.ZERO
	arcade.call("setup", player.duplicate(true), seed_value)
	arcade.call("set_running", false)
	arcade.process_mode = Node.PROCESS_MODE_DISABLED
	arcade.set_process(false)
	arcade.set_physics_process(false)
	arcade.set_process_input(false)
	arcade.set_process_unhandled_input(false)
	arcade.set_block_signals(true)
	arcade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Keep the real 3D scene and remove its competitive HUD. Guide controls below
	# remain the one place to read all keys; the clip shows just one action.
	for child in arcade.get_children():
		if child is Control:
			child.hide()
	if id == "standby_hunt":
		for record in arcade.get("device_records"):
			if bool(record["waste"]):
				demo_record = record
				break
	elif id == "eco_commute":
		demo_record = arcade.get("segments")[0]["stops"][0]
		arcade.call("_activate_stop", demo_record)
	elif id == "heat_leak":
		demo_record = arcade.get("windows")[2]
	elif id == "solar_align":
		demo_record = arcade.get("panel_gates")[0]
		for record in arcade.get("panel_gates").slice(1):
			(record["node"] as Node3D).hide()
		for record in arcade.get("terrain_obstacles"):
			(record["node"] as Node3D).hide()
	elif id == "energy_sort":
		# A fixed teaching example is independent of the competitive shuffled bag.
		arcade.set("current_source", {"name": "햇빛", "kind": 0, "shape": "sun"})
		for child in (arcade.get("source_shape") as Node).get_children():
			child.free()
		arcade.call("_build_source_shape", "sun")
		(arcade.get("carried_name") as Label3D).text = "햇빛"
	demo_animators.clear()
	for node in arcade.find_children("*", "AnimationPlayer", true, false):
		demo_animators.append(node as AnimationPlayer)
	_build_caption()
	_sync_visibility()
	_animate_demo(0.0)

func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	arcade = null
	demo_animators.clear()
	set_process(false)

func _build_caption() -> void:
	var strip := PanelContainer.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -42
	strip.add_theme_stylebox_override("panel", preload("res://scripts/ui/CommercialUI.gd").padded_panel(Color("102c38f2"), Color("315967"), 8.0, 8))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	strip.add_child(row)
	key_badge = Label.new()
	key_badge.custom_minimum_size.x = 170
	key_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_badge.add_theme_font_size_override("font_size", 18)
	row.add_child(key_badge)
	caption = Label.new()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_theme_font_size_override("font_size", 18)
	row.add_child(caption)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(92, 8)
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress.show_percentage = false
	progress.max_value = 6.0
	progress.add_theme_stylebox_override("background", preload("res://scripts/ui/CommercialUI.gd").progress_background())
	progress.add_theme_stylebox_override("fill", preload("res://scripts/ui/CommercialUI.gd").progress_fill())
	row.add_child(progress)
	var demo_tag := Label.new()
	demo_tag.text = "조작 시범"
	demo_tag.position = Vector2(12, 8)
	demo_tag.add_theme_font_size_override("font_size", 15)
	demo_tag.add_theme_color_override("font_outline_color", Color("102c38"))
	demo_tag.add_theme_constant_override("outline_size", 5)
	add_child(demo_tag)

func _sync_visibility() -> void:
	if not is_instance_valid(arcade):
		return
	var showing := is_visible_in_tree()
	(arcade.get("viewport") as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if showing else SubViewport.UPDATE_DISABLED
	set_process(showing)

func _process(delta: float) -> void:
	preview_time = fposmod(preview_time + minf(delta, 0.1), 6.0)
	_animate_demo(delta)

func _animate_demo(delta: float) -> void:
	if not is_instance_valid(arcade):
		return
	var t := preview_time
	var moving := t > 1.0 and t < 3.6
	var done := t >= 3.6
	var q := smoothstep(1.0, 3.6, t)
	var text: Array = CAPTIONS[game_id]
	key_badge.text = str(text[0])
	key_badge.modulate = Color("ffd166") if moving else Color("bed5d2")
	caption.text = str(text[2] if done else text[1])
	caption.modulate = Color("9af0c9") if done else Color("f3fbf8")
	progress.value = t
	for animator in demo_animators:
		if is_instance_valid(animator):
			animator.advance(delta)
	match game_id:
		"solar_align":
			var lane := int(demo_record["correct_lane"])
			(arcade.get("hero_body") as Node3D).position.x = lerpf(0.0, [-2.7, 0.0, 2.7][lane], q)
			(demo_record["node"] as Node3D).position.z = lerpf(-7.0, 3.4, q)
			_pose(moving)
		"wind_rhythm":
			arcade.set("wind_angle", 28.0)
			arcade.set("turbine_yaw", lerpf(-28.0, 28.0, q))
			(arcade.get("turbine_head") as Node3D).rotation.y = deg_to_rad(float(arcade.get("turbine_yaw")))
			(arcade.get("wind_vane") as Node3D).rotation.y = deg_to_rad(28.0)
			arcade.call("_update_rotor", delta, q * 100.0)
			arcade.call("_update_wind_streaks", delta)
		"grid_balance":
			arcade.set("demand", 80.0)
			arcade.set("supply", lerpf(35.0, 80.0, q))
			arcade.set("visual_time", t)
			arcade.call("_update_city_visuals", delta, float(arcade.get("supply")) - 80.0, done)
			# The two live bars are the action target, not competitive score UI.
			for bar_name in ["supply_bar", "demand_bar"]:
				var bar: Control = arcade.get(bar_name)
				bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
				bar.position = Vector2(88.0, maxf(70.0, size.y - 112.0) + (28.0 if bar_name == "demand_bar" else 0.0))
				bar.size = Vector2(maxf(200.0, size.x - 180.0), 16.0)
				bar.show()
			for node in arcade.get_children():
				if node is Label and node.text in ["공급", "수요"]:
					node.set_anchors_preset(Control.PRESET_TOP_LEFT)
					node.position = Vector2(18.0, maxf(70.0, size.y - 116.0) + (28.0 if node.text == "수요" else 0.0))
					node.show()
			arcade.call("_update_hud", float(arcade.get("supply")) - 80.0, done)
		"standby_hunt":
			if demo_record.is_empty():
				return
			var x := float(demo_record["x"])
			(arcade.get("hero") as Node3D).position.x = lerpf(x - 2.0, x - 0.5, q)
			(arcade.get("camera") as Camera3D).position.x = x
			(demo_record["plug"] as Node3D).position.x = 0.72 + (0.30 if done else 0.0)
			(demo_record["label"] as Label3D).text = "%s\n%s" % [demo_record["name"], "0 W" if done else "%d W · 대기 중" % int(demo_record["watt"])]
			var led: Node3D = (demo_record["node"] as Node).get_node_or_null("StandbyLED")
			if led:
				led.visible = not done
			_pose(moving)
		"hydro_gate":
			arcade.set("water_level", lerpf(44.0, 76.0, minf(t / 2.0, 1.0)) if not done else 70.0)
			arcade.set("selected_gate", 0)
			arcade.set("open_gate", 0 if done else -1)
			arcade.set("charge", minf(1.0, floorf(maxf(0.0, t - 1.6) * 2.0) * 0.34))
			arcade.set("hero_x", 0.42)
			arcade.set("visual_time", t)
			arcade.call("_update_visuals")
			arcade.call("_animate_world", delta)
			(arcade.get("choice_label") as Control).hide()
			(arcade.get("charge_bar") as Control).visible = not done
			key_badge.modulate = Color("ffd166") if moving and fposmod(t, 0.5) < 0.22 else Color("bed5d2")
		"energy_sort":
			arcade.set("hero_x", -4.25 * q)
			arcade.set("carry_direction", -1.0)
			(arcade.get("hero") as Node3D).position.x = -4.25 * q
			(arcade.get("icon_anchor") as Node3D).visible = not done
			arcade.call("_update_carried_source")
			(arcade.get("left_light") as MeshInstance3D).material_override = arcade.get("left_material") if done else arcade.get("idle_light_material")
			_pose(moving, true)
		"battery_relay":
			var charge_stage := t < 3.0
			var travel := smoothstep(0.8, 2.7, t) if charge_stage else smoothstep(3.2, 4.8, t)
			var x := lerpf(-4.3, 0.0, travel) if charge_stage else lerpf(0.0, 4.3, travel)
			arcade.set("elapsed", 0.0 if charge_stage else 7.0)
			arcade.set("visual_time", t)
			arcade.set("cargo", 1 if charge_stage else (2 if t < 4.8 else 0))
			arcade.set("battery_units", 1 if t > 2.7 and t < 3.3 else 0)
			arcade.set("city_energy_remaining", 1.0 if t >= 4.8 else 0.0)
			(arcade.get("hero") as Node3D).position.x = x
			(arcade.get("cargo_orb") as Node3D).position.x = x
			arcade.call("_update_visuals")
			_pose(t < 4.8)
		"eco_commute":
			arcade.set("bus_x", lerpf(8.0, 12.0, smoothstep(0.7, 2.5, t)))
			arcade.set("elapsed", t)
			arcade.call("_update_camera_and_bus")
			arcade.set("bus_door_open", smoothstep(2.5, 3.2, t))
			arcade.call("_set_bus_door_position")
			var index := 0
			for state in demo_record["states"]:
				var pupil := state["node"] as Node3D
				var travel := smoothstep(3.0 + index * 0.04, 4.1 + index * 0.04, t)
				pupil.position = Vector3(float(state["base_x"]), 0.255, float(state["base_z"])).lerp(Vector3(13.08, 0.335, 1.98), travel)
				pupil.visible = index < 6 and travel < 1.0
				arcade.call("_play_student_animation", state["animator"], "walk" if travel > 0.0 and travel < 1.0 else "idle", float(state["phase"]), 1.0)
				index += 1
			key_badge.text = "D" if t < 2.5 else ("S" if t < 3.0 else "Space")
		"heat_leak":
			demo_record["open"] = not done
			demo_record["closed"] = done
			arcade.set("elapsed", t)
			(arcade.get("hero") as Node3D).position.x = lerpf(0.0, -1.2, q)
			arcade.call("_update_window_visual", demo_record)
			arcade.call("_animate_heat", delta)
			_pose(moving, true)

func _pose(moving: bool, left: bool = false) -> void:
	var hero: Node3D = arcade.get("hero")
	if not is_instance_valid(hero):
		return
	hero.call("_set_avatar_animation_state", moving)
	var sprite: Sprite3D = hero.get("avatar_sprite")
	if sprite:
		sprite.flip_h = left
		sprite.frame = int(preview_time * 10.0) % maxi(1, sprite.hframes) if moving else 0
