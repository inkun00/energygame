extends RefCounted
class_name MiniGameVisualStyle

## Shared low-cost art setup and visual-only contact helpers. Scoring colours,
## textures, collision shapes and weather stay game-owned.
const SKY := Color("88b3ad")
const NIGHT_SKY := Color("244650")
const FIELD := Color("769c83")
const CREAM := Color("ded2b9")
const WALL := Color("d9ddca")
const TEAL := Color("447c79")
const ROAD := Color("3b5d60")
const STONE := Color("92aaa2")
const INK := Color("203c43")
const MATTE_ROUGHNESS := 0.86
const SOFT_SPECULAR := 0.22
const SIGNAL_EMISSION := 0.34
const HERO_TINT := Color("f8f6ed")
const ADAPTED_MATERIAL_META := &"energy_arcade_adapted"
const SUCCESS_FLASH_ALPHA := 0.12
const WARNING_FLASH_ALPHA := 0.14

static var _imported_materials: Dictionary = {}

static func add_environment(world: Node3D, profile: String = "day") -> WorldEnvironment:
	var node := WorldEnvironment.new()
	node.name = "ArcadeEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = NIGHT_SKY if profile == "night" else SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e5eee2")
	environment.ambient_light_energy = 0.62 if profile == "night" else 0.56
	# Linear tone mapping is shared by native and the Compatibility web renderer.
	# Restrained light energy keeps cream/white asset surfaces from clipping.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.glow_enabled = false
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false
	environment.fog_enabled = false
	node.environment = environment
	world.add_child(node)
	return node

static func add_key_light(world: Node3D, rotation_value: Vector3, profile: String = "day") -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "ArcadeKeyLight"
	light.rotation_degrees = rotation_value
	light.light_color = Color("fff0da")
	light.light_energy = 0.72 if profile == "indoor" else (0.68 if profile == "night" else 0.82)
	# Existing pawn contact shadows provide grounding without a shadow-map pass.
	light.shadow_enabled = false
	world.add_child(light)
	return light

static func surface_color(color: Color) -> Color:
	# Only pale, near-neutral surfaces change. Red hazards, green successes,
	# water blue, sun yellow and source-category colours retain their hue.
	if color.s < 0.18 and color.v > 0.82:
		var softened := color.lerp(CREAM, 0.18)
		softened.a = color.a
		return softened
	return color

static func material(color: Color, glowing: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = surface_color(color)
	result.roughness = MATTE_ROUGHNESS
	result.metallic_specular = SOFT_SPECULAR
	if color.a < 1.0:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glowing:
		result.emission_enabled = true
		result.emission = Color(color.r, color.g, color.b)
		result.emission_energy_multiplier = SIGNAL_EMISSION
	return result

static func prepare_imported(model: Node3D) -> void:
	# Duplicate/cache surface overrides, never alter shared imported resources.
	var meshes: Array[Node] = []
	if model is MeshInstance3D:
		meshes.append(model)
	meshes.append_array(model.find_children("*", "MeshInstance3D", true, false))
	for mesh_node in meshes:
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for index in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(index)
			if not source is StandardMaterial3D:
				continue
			if source.get_meta(ADAPTED_MATERIAL_META, false):
				continue
			# Only shared imported resources belong in the shared cache. A tinted
			# per-device duplicate has no resource path and dies with that device;
			# caching its instance ID retained a new material on every house lap.
			var key := source.resource_path
			var cacheable := not key.is_empty() and key.begins_with("res://")
			var adapted: StandardMaterial3D = _imported_materials.get(key) if cacheable else null
			if adapted == null:
				adapted = source.duplicate() as StandardMaterial3D
				adapted.albedo_color = surface_color(adapted.albedo_color)
				adapted.roughness = maxf(adapted.roughness, MATTE_ROUGHNESS)
				adapted.metallic_specular = minf(adapted.metallic_specular, SOFT_SPECULAR)
				if adapted.emission_enabled:
					adapted.emission_energy_multiplier = minf(adapted.emission_energy_multiplier, SIGNAL_EMISSION)
				adapted.set_meta(ADAPTED_MATERIAL_META, true)
				if cacheable:
					_imported_materials[key] = adapted
			mesh.set_surface_override_material(index, adapted)

static func style_hero(hero: Node3D) -> void:
	var avatar: Variant = hero.get("avatar_sprite")
	if avatar is Sprite3D:
		avatar.modulate = HERO_TINT

static func update_contact_shadow(hero: Node3D, surface_world_y: float, lift_world: float) -> void:
	if not is_instance_valid(hero) or not hero.has_method("_update_ground_shadow"):
		return
	# Pawn's established method takes a height in its parent's coordinate space.
	# Mini-games magnify the pawn and sometimes parent it to a physics body, so
	# feeding raw world height sent the local shadow underground (or into the air).
	var vertical_scale := maxf(absf(hero.global_basis.get_scale().y), 0.001)
	var local_surface := hero.position.y + (surface_world_y - hero.global_position.y) / vertical_scale
	hero.call("_update_ground_shadow", local_surface, maxf(0.0, lift_world) / vertical_scale)
	var shadow: Variant = hero.get("shadow_mesh")
	if shadow is Node3D:
		# A running hero may bank sideways. Its contact mark belongs vertically
		# below it on the horizontal floor, not tilted by that decorative lean.
		shadow.global_position = Vector3(hero.global_position.x, surface_world_y + 0.014 * vertical_scale, hero.global_position.z)
		shadow.global_rotation = Vector3(0.0, hero.global_rotation.y, 0.0)
