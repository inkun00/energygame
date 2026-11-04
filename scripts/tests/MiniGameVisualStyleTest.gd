extends SceneTree

const STYLE = preload("res://scripts/minigames/MiniGameVisualStyle.gd")
const GAMES := ["SolarPanelDash3D", "WindTurbinePilot3D", "SmartGridBalance3D", "StandbyPowerHunt3D", "HydroGateRun3D", "EnergySourceSort3D", "BatteryShuttle3D", "SharedSchoolBus3D", "HeatLeakDash3D"]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[VisualStyle] " + message)

func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.stop_game()
	var player := {"char_icon": "res://assets/characters/eco_roster/captain_eco.webp"}
	for game_name in GAMES:
		var arcade: Node = load("res://scripts/minigames/%s.gd" % game_name).new()
		root.add_child(arcade)
		arcade.setup(player, 31)
		arcade.set_process(false)
		arcade.set_physics_process(false)
		var world: Node3D = arcade.get("world")
		var environment: WorldEnvironment = world.get_node("ArcadeEnvironment")
		var light: DirectionalLight3D = world.get_node("ArcadeKeyLight")
		_check(environment.environment.background_color == (STYLE.NIGHT_SKY if game_name == "SmartGridBalance3D" else STYLE.SKY), "%s shares the appropriate teal backdrop" % game_name)
		_check(environment.environment.ambient_light_energy < 0.621 and light.light_energy < 0.821, "%s avoids white clipping" % game_name)
		_check(not light.shadow_enabled and not environment.environment.glow_enabled and not environment.environment.ssao_enabled, "%s has no expensive shadow/ambient/glow pass" % game_name)
		if game_name != "SharedSchoolBus3D":
			var hero: Node3D = arcade.get("hero")
			_check(hero.avatar_sprite.modulate == STYLE.HERO_TINT, "%s keeps the same warm sprite colour temperature" % game_name)
		if game_name == "WindTurbinePilot3D":
			_check(arcade.storm_head_material.albedo_color == Color("ed5b53"), "Storm red must not be recoloured")
		if game_name == "SolarPanelDash3D":
			_check(arcade.correct_material.albedo_color == Color("48e58d") and arcade.wrong_material.albedo_color == Color("e65f58"), "Solar judgement green/red must remain intact")
			var sun_material: StandardMaterial3D = arcade.sun.material_override
			_check(sun_material.albedo_color == Color("ffd957") and not sun_material.emission_enabled and sun_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "The sun direction marker stays yellow instead of clipping white")
		if game_name == "HeatLeakDash3D":
			_check(arcade.windows[0]["particles"][0].material_override.albedo_color == Color("ff754f"), "Hot incoming air must stay orange/red")
		arcade.queue_free()
		await process_frame
	var original := StandardMaterial3D.new()
	original.albedo_color = Color.WHITE
	original.roughness = 0.15
	var imported := MeshInstance3D.new()
	imported.mesh = BoxMesh.new()
	imported.mesh.surface_set_material(0, original)
	STYLE.prepare_imported(imported)
	var adapted := imported.get_active_material(0) as StandardMaterial3D
	_check(adapted != original and is_equal_approx(original.roughness, 0.15) and original.albedo_color == Color.WHITE, "Imported materials must never mutate their shared source")
	_check(adapted.roughness >= STYLE.MATTE_ROUGHNESS and adapted.metallic_specular <= STYLE.SOFT_SPECULAR, "Imported white surfaces use the same soft matte material")
	var adapted_color := adapted.albedo_color
	STYLE.prepare_imported(imported)
	_check(imported.get_active_material(0) == adapted and adapted.albedo_color == adapted_color, "Repeated asset preparation must not duplicate or repeatedly yellow the same material")
	var cache_size: int = STYLE._imported_materials.size()
	for sample_index in range(20):
		var temporary := MeshInstance3D.new()
		temporary.mesh = BoxMesh.new()
		var local_tint := StandardMaterial3D.new()
		local_tint.albedo_color = Color(0.5 + sample_index * 0.01, 0.6, 0.65)
		temporary.mesh.surface_set_material(0, local_tint)
		STYLE.prepare_imported(temporary)
		temporary.free()
	_check(STYLE._imported_materials.size() == cache_size, "One-off house/device material duplicates must not accumulate in a permanent shared cache")
	var material := STYLE.material(Color("ff5148"), true)
	_check(material.albedo_color == Color("ff5148") and is_equal_approx(material.emission_energy_multiplier, STYLE.SIGNAL_EMISSION), "Signals keep their exact hue and restrained emission")
	_check(STYLE.material(Color("3f9bdfbd"), true).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Reservoir transparency must remain intact")
	imported.free()
	if failures.is_empty():
		print("[VisualStyle] PASS · 9 coherent scenes, sprite tint, low-cost light, signal hue and immutable imported assets")
	quit(0 if failures.is_empty() else 1)
