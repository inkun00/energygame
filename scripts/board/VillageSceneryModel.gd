extends RefCounted

## Reuse one imported mesh/material per prop, even when several streets use it.
static var meshes: Dictionary[String, Mesh] = {}

static func make(model_id: String) -> MeshInstance3D:
	if not meshes.has(model_id):
		var source := load("res://assets/models/village/%s.glb" % model_id) as PackedScene
		var imported := source.instantiate()
		var visual := imported as MeshInstance3D
		if not visual:
			visual = imported.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
		meshes[model_id] = visual.mesh
		imported.free()
	var instance := MeshInstance3D.new()
	instance.name = model_id.to_pascal_case()
	instance.mesh = meshes[model_id]
	return instance
