extends RefCounted
class_name RenderQuality

## Event-driven presentation budget. Never pauses a SceneTree, gameplay timer,
## network peer, physics world or the separately rendered active arcade.
static func set_board_world_awake(viewport: SubViewport, backdrop: Node, pawns: Array, markers: Array, awake: bool) -> void:
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if awake else SubViewport.UPDATE_DISABLED
	if is_instance_valid(backdrop):
		backdrop.set_process(awake)
	for pawn in pawns:
		if is_instance_valid(pawn):
			pawn.set_process(awake)
	for marker in markers:
		if is_instance_valid(marker):
			# Only selectable skill targets pulse; the other 95-100 tiles are static.
			marker.set_process(awake and bool(marker.get("skill_targetable")))
