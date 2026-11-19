@tool
extends EditorScenePostImport

## These Blender meshes bake their albedo into the glTF COLOR_0 stream.
func _post_import(scene: Node) -> Object:
	var visuals := scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D:
		visuals.append(scene)
	for visual: MeshInstance3D in visuals:
		var mesh := visual.mesh as ArrayMesh
		for surface in range(mesh.get_surface_count()):
			var material := visual.get_active_material(surface) as StandardMaterial3D
			if material and (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) != 0:
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false
	return scene
