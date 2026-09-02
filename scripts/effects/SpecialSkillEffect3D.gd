extends Node3D
class_name SpecialSkillEffect3D

## 캐릭터 특수기술의 성격을 보드 위 절차형 3D 애니메이션으로 표현합니다.

const EFFECT_SECONDS := 1.65


func play(skill: Dictionary, source_position: Vector3, target_position: Vector3) -> void:
	var skill_id := str(skill.get("id", "eco_dash"))
	match skill_id:
		"eco_dash":
			_play_path_dash(source_position, target_position, Color("61ef88"), "leaf")
		"wind_path":
			_play_path_dash(source_position, target_position, Color("70e8ff"), "wind")
		"lightning_leap":
			_play_lightning(source_position, target_position)
		"solar_charge":
			_play_solar_charge(source_position, target_position)
		"starlight_charge":
			_play_starlight_charge(source_position, target_position)
		"purifying_wave":
			_play_purifying_wave(source_position, target_position)
		"earth_barrier":
			_play_earth_barrier(target_position)
		"forest_supply":
			_play_forest_supply(source_position, target_position)
		"recycle_salvage":
			_play_collection_flow(target_position, source_position, Color("61f08a"), "recycle")
		"mycelium_harvest":
			_play_collection_flow(target_position, source_position, Color("d58cff"), "spore")
		_:
			_play_path_dash(source_position, target_position, Color("61ef88"), "leaf")
	get_tree().create_timer(EFFECT_SECONDS).timeout.connect(queue_free)


func _play_path_dash(from_position: Vector3, to_position: Vector3, color: Color, kind: String) -> void:
	_add_expanding_ring(from_position, color, 0.0, 1.5)
	_add_expanding_ring(to_position, color.lightened(0.18), 0.55, 2.0)
	var direction := to_position - from_position
	for index in range(12):
		var ratio := float(index) / 11.0
		var position := from_position.lerp(to_position, ratio)
		position.y += 0.35 + sin(ratio * PI) * (0.7 if kind == "leaf" else 0.38)
		var streak := _add_box(position, Vector3(0.10, 0.035, 0.28 if kind == "leaf" else 0.52), color, 0.9)
		streak.rotation.y = atan2(direction.x, direction.z) + (ratio * 2.4 if kind == "leaf" else 0.0)
		streak.scale = Vector3.ZERO
		var delay := ratio * 0.52
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_property(streak, "scale", Vector3.ONE * (1.25 if kind == "leaf" else 1.0), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(streak, "position:y", position.y + 0.32, 0.42)
		tween.tween_property(streak, "scale", Vector3.ZERO, 0.22)


func _play_lightning(from_position: Vector3, to_position: Vector3) -> void:
	_add_expanding_ring(from_position, Color("ffe45c"), 0.0, 1.45)
	_add_expanding_ring(to_position, Color.WHITE, 0.42, 2.15)
	var points: Array[Vector3] = [from_position + Vector3.UP * 0.8]
	for index in range(1, 9):
		var ratio := float(index) / 9.0
		var zigzag := Vector3(0.26 if index % 2 == 0 else -0.26, sin(ratio * PI) * 0.7, -0.18 if index % 3 == 0 else 0.18)
		points.append(from_position.lerp(to_position, ratio) + Vector3.UP * 0.8 + zigzag)
	points.append(to_position + Vector3.UP * 0.8)
	for index in range(points.size() - 1):
		var bolt := _add_beam(points[index], points[index + 1], Color("fff272"), 0.10)
		bolt.scale = Vector3(0.02, 0.02, 1.0)
		var tween := create_tween()
		tween.tween_interval(float(index) * 0.035)
		tween.tween_property(bolt, "scale", Vector3.ONE, 0.055)
		tween.tween_property(bolt, "scale", Vector3(0.12, 0.12, 1.0), 0.28)
	for spark_index in range(10):
		_add_rising_spark(to_position, Color("fff8b8"), spark_index, 0.36)


func _play_solar_charge(from_position: Vector3, to_position: Vector3) -> void:
	_add_energy_beam(from_position, to_position, Color("ffd34f"))
	var sun_position := to_position + Vector3.UP * 1.65
	var sun := _add_sphere(sun_position, 0.34, Color("ffd84f"), 0.96)
	sun.scale = Vector3.ZERO
	var sun_tween := create_tween()
	sun_tween.tween_property(sun, "scale", Vector3.ONE * 1.35, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sun_tween.tween_interval(0.45)
	sun_tween.tween_property(sun, "scale", Vector3.ZERO, 0.30)
	for ray_index in range(10):
		var angle := TAU * float(ray_index) / 10.0
		var ray_position := sun_position + Vector3(cos(angle), 0.0, sin(angle)) * 0.72
		var ray := _add_box(ray_position, Vector3(0.09, 0.05, 0.42), Color("fff09a"), 0.9)
		ray.rotation.y = -angle
		ray.scale = Vector3.ZERO
		var tween := create_tween()
		tween.tween_interval(0.12 + float(ray_index % 2) * 0.04)
		tween.tween_property(ray, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK)
		tween.tween_interval(0.38)
		tween.tween_property(ray, "scale", Vector3.ZERO, 0.22)
	_add_expanding_ring(to_position, Color("ffd34f"), 0.28, 2.0)


func _play_starlight_charge(from_position: Vector3, to_position: Vector3) -> void:
	_add_energy_beam(from_position, to_position, Color("b9f5ff"))
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var start := to_position + Vector3(cos(angle), 1.0 + float(index % 3) * 0.22, sin(angle)) * 1.2
		var star := _add_cross(start, Color("efffff"), 0.16)
		star.scale = Vector3.ZERO
		var tween := create_tween()
		tween.tween_interval(float(index) * 0.035)
		tween.tween_property(star, "scale", Vector3.ONE * 1.4, 0.18).set_trans(Tween.TRANS_BACK)
		tween.parallel().tween_property(star, "position", to_position + Vector3.UP * 0.8, 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(star, "scale", Vector3.ZERO, 0.18)
	_add_expanding_ring(to_position, Color("c8fbff"), 0.48, 1.9)


func _play_purifying_wave(from_position: Vector3, to_position: Vector3) -> void:
	_add_energy_beam(from_position, to_position, Color("5cdcff"))
	for ring_index in range(3):
		_add_expanding_ring(to_position + Vector3.UP * (0.08 + ring_index * 0.30), Color("5cdcff"), float(ring_index) * 0.18, 1.75 + ring_index * 0.25)
	var bubble := _add_sphere(to_position + Vector3.UP * 0.85, 0.78, Color("6de6ff"), 0.24)
	bubble.scale = Vector3.ZERO
	var bubble_tween := create_tween()
	bubble_tween.tween_interval(0.25)
	bubble_tween.tween_property(bubble, "scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_BACK)
	bubble_tween.tween_property(bubble, "scale", Vector3.ONE * 1.12, 0.52)
	bubble_tween.tween_property(bubble, "scale", Vector3.ZERO, 0.26)
	for index in range(10):
		_add_rising_spark(to_position, Color("bdf8ff"), index, 0.12)


func _play_earth_barrier(target_position: Vector3) -> void:
	_add_expanding_ring(target_position, Color("e0b46b"), 0.0, 2.0)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var stone_position := target_position + Vector3(cos(angle), 0.18, sin(angle)) * 1.05
		var stone := _add_box(stone_position, Vector3(0.34, 0.42, 0.30), Color("9c7650"), 1.0)
		stone.rotation = Vector3(0.25, angle, 0.18)
		stone.scale = Vector3.ZERO
		var tween := create_tween()
		tween.tween_interval(float(index) * 0.045)
		tween.tween_property(stone, "scale", Vector3.ONE, 0.24).set_trans(Tween.TRANS_BACK)
		tween.parallel().tween_property(stone, "position:y", 0.72, 0.34).as_relative()
		tween.tween_interval(0.42)
		tween.tween_property(stone, "scale", Vector3.ZERO, 0.24)
	var shield := _add_sphere(target_position + Vector3.UP * 0.82, 0.86, Color("efc879"), 0.20)
	shield.scale = Vector3.ZERO
	var shield_tween := create_tween()
	shield_tween.tween_interval(0.24)
	shield_tween.tween_property(shield, "scale", Vector3.ONE, 0.30).set_trans(Tween.TRANS_BACK)
	shield_tween.tween_interval(0.55)
	shield_tween.tween_property(shield, "scale", Vector3.ZERO, 0.24)


func _play_forest_supply(from_position: Vector3, to_position: Vector3) -> void:
	_add_energy_beam(from_position, to_position, Color("71e68b"))
	_add_expanding_ring(to_position, Color("67e685"), 0.18, 1.8)
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var leaf_position := to_position + Vector3(cos(angle), 0.25, sin(angle)) * (0.55 + float(index % 3) * 0.18)
		var leaf := _add_box(leaf_position, Vector3(0.10, 0.03, 0.28), Color("77ee8e") if index % 2 == 0 else Color("ffe16d"), 0.95)
		leaf.rotation.y = angle
		leaf.scale = Vector3.ZERO
		var tween := create_tween()
		tween.tween_interval(float(index) * 0.035)
		tween.tween_property(leaf, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK)
		tween.parallel().tween_property(leaf, "position:y", leaf_position.y + 1.15, 0.62)
		tween.parallel().tween_property(leaf, "rotation:y", angle + PI * 1.5, 0.62)
		tween.tween_property(leaf, "scale", Vector3.ZERO, 0.22)


func _play_collection_flow(from_position: Vector3, to_position: Vector3, color: Color, kind: String) -> void:
	_add_expanding_ring(from_position, color, 0.0, 1.7)
	_add_energy_beam(from_position, to_position, color)
	for index in range(14):
		var ratio := float(index) / 13.0
		var start := from_position + Vector3(cos(index * 1.9), 0.25 + float(index % 4) * 0.16, sin(index * 1.9)) * 0.55
		var particle := _add_sphere(start, 0.07 if kind == "spore" else 0.09, color.lightened(float(index % 3) * 0.08), 0.92)
		if kind == "recycle":
			particle.scale = Vector3(1.5, 0.7, 0.7)
		else:
			particle.scale = Vector3.ZERO
		var destination := from_position.lerp(to_position, 1.0) + Vector3.UP * (0.6 + float(index % 3) * 0.13)
		var tween := create_tween()
		tween.tween_interval(ratio * 0.34)
		if kind == "spore":
			tween.tween_property(particle, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK)
		tween.tween_property(particle, "position", destination, 0.58).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(particle, "rotation:y", TAU * 1.5, 0.58)
		tween.tween_property(particle, "scale", Vector3.ZERO, 0.16)
	_add_expanding_ring(to_position, color.lightened(0.18), 0.62, 1.6)


func _add_energy_beam(from_position: Vector3, to_position: Vector3, color: Color) -> void:
	if from_position.distance_squared_to(to_position) < 0.08:
		return
	var beam := _add_beam(from_position + Vector3.UP * 0.72, to_position + Vector3.UP * 0.72, color, 0.075)
	beam.scale = Vector3(0.02, 0.02, 1.0)
	var tween := create_tween()
	tween.tween_property(beam, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.44)
	tween.tween_property(beam, "scale", Vector3(0.02, 0.02, 1.0), 0.24)


func _add_expanding_ring(position: Vector3, color: Color, delay: float, max_scale: float) -> void:
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.62
	mesh.bottom_radius = 0.62
	mesh.height = 0.025
	ring.mesh = mesh
	ring.material_override = _make_material(color, 0.52)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = position + Vector3.UP * 0.08
	ring.scale = Vector3(0.08, 1.0, 0.08)
	add_child(ring)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(ring, "scale", Vector3(max_scale, 1.0, max_scale), 0.48).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "scale", Vector3(max_scale * 1.18, 0.05, max_scale * 1.18), 0.28)


func _add_rising_spark(origin: Vector3, color: Color, index: int, delay: float) -> void:
	var angle := TAU * float(index) / 10.0
	var position := origin + Vector3(cos(angle), 0.24, sin(angle)) * (0.45 + float(index % 3) * 0.12)
	var spark := _add_sphere(position, 0.07, color, 0.95)
	spark.scale = Vector3.ZERO
	var tween := create_tween()
	tween.tween_interval(delay + float(index) * 0.025)
	tween.tween_property(spark, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(spark, "position:y", position.y + 1.2, 0.52)
	tween.tween_property(spark, "scale", Vector3.ZERO, 0.18)


func _add_cross(position: Vector3, color: Color, size: float) -> Node3D:
	var cross := Node3D.new()
	cross.position = position
	add_child(cross)
	var horizontal := _new_box(Vector3(size * 2.4, size * 0.32, size * 0.32), color, 0.95)
	var vertical := _new_box(Vector3(size * 0.32, size * 2.4, size * 0.32), color, 0.95)
	cross.add_child(horizontal)
	cross.add_child(vertical)
	return cross


func _add_sphere(position: Vector3, radius: float, color: Color, alpha: float) -> MeshInstance3D:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	sphere.mesh = mesh
	sphere.material_override = _make_material(color, alpha)
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sphere.position = position
	add_child(sphere)
	return sphere


func _add_box(position: Vector3, size: Vector3, color: Color, alpha: float) -> MeshInstance3D:
	var box := _new_box(size, color, alpha)
	box.position = position
	add_child(box)
	return box


func _new_box(size: Vector3, color: Color, alpha: float) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = _make_material(color, alpha)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return box


func _add_beam(from_position: Vector3, to_position: Vector3, color: Color, width: float) -> MeshInstance3D:
	var difference := to_position - from_position
	var beam := _new_box(Vector3(width, width, maxf(difference.length(), 0.01)), color, 0.92)
	beam.position = (from_position + to_position) * 0.5
	add_child(beam)
	beam.look_at(to_position, Vector3.UP)
	return beam


func _make_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, alpha)
	material.emission_enabled = true
	material.emission = color * 1.45
	material.emission_energy_multiplier = 1.25
	material.no_depth_test = false
	return material
