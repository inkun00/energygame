extends SceneTree

## 모든 캐릭터별 특수기술의 3D/화면 애니메이션 분기를 한 번씩 생성합니다.

const EFFECT_3D = preload("res://scripts/effects/SpecialSkillEffect3D.gd")
const CINEMATIC = preload("res://scripts/effects/SpecialSkillCinematic.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node.new()
	root.add_child(scene)
	var world := Node3D.new()
	scene.add_child(world)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.add_child(canvas)
	var game_manager: Node = root.get_node("GameManager")
	var skills_by_icon: Dictionary = game_manager.SPECIAL_SKILLS_BY_ICON
	var index := 0
	for icon_path in skills_by_icon:
		var skill: Dictionary = skills_by_icon[icon_path]
		var effect := EFFECT_3D.new()
		world.add_child(effect)
		effect.play(skill, Vector3(-1.5, 0.2, 0), Vector3(1.5, 0.2, 0))
		var cinematic := CINEMATIC.new()
		canvas.add_child(cinematic)
		cinematic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cinematic.setup(skill, Vector2(180 + (index % 5) * 220, 180 + (index / 5) * 300), Color("62df9a"))
		index += 1
	await create_timer(0.18).timeout
	if world.get_child_count() != skills_by_icon.size():
		push_error("일부 특수기술 3D 효과가 생성되지 않았습니다.")
		quit(1)
		return
	if canvas.get_child_count() != skills_by_icon.size():
		push_error("일부 특수기술 화면 효과가 생성되지 않았습니다.")
		quit(1)
		return
	print("[PASS] %d character special-skill animation variants created" % index)
	quit(0)
