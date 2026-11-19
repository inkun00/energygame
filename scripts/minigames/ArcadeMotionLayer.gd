extends Control
## Draw a few short-lived marks over their actual 3D locations. No additional
## camera, render target, particles, physics bodies or per-effect nodes.
const MARK_LIMIT := 12
var world: Node3D
var view: SubViewport
var painter: Callable
var marks: Array[Dictionary] = []
var reduced := false
var last_trail := Vector3.INF
var draw_fit := Vector2.ONE

func attach(game: SubViewportContainer, scene_world: Node3D, draw_mark: Callable) -> void:
	name = "WorldMotion"
	world = scene_world
	view = world.get_viewport()
	painter = draw_mark
	# The arcade already owns this layer before it enters the tree.
	game.move_child(self, -1)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	if OS.has_feature("web"):
		reduced = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches"))

func clear() -> void:
	marks.clear()
	last_trail = Vector3.INF
	queue_redraw()

func mark(kind: StringName, from: Vector3, to: Vector3, seconds: float, amount: float = 1.0) -> void:
	if marks.size() == MARK_LIMIT: marks.pop_front()
	marks.append({"kind": kind, "a": from, "b": to, "age": 0.0, "life": seconds, "amount": amount})
	queue_redraw()

func trail(kind: StringName, point: Vector3, distance: float, life: float, amount: float = 1.0) -> void:
	if reduced: return
	if last_trail.is_finite():
		var travelled := point.distance_to(last_trail)
		if travelled < distance: return
		if travelled < distance * 4.0:
			mark(kind, last_trail, point, life, amount)
	last_trail = point

func advance(delta: float) -> void:
	if marks.is_empty(): return
	for i in range(marks.size() - 1, -1, -1):
		marks[i].age += delta
		if marks[i].age >= marks[i].life: marks.remove_at(i)
	queue_redraw()

func _draw() -> void:
	if marks.is_empty() or not is_instance_valid(view): return
	var camera := view.get_camera_3d()
	if camera == null or view.size.x < 1 or view.size.y < 1: return
	var ui_scale := clampf(minf(size.x / 700.0, size.y / 265.0), 0.65, 1.6)
	draw_fit = size / Vector2(view.size) / ui_scale
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * ui_scale)
	for entry in marks:
		var a := world.to_global(entry.a)
		var b := world.to_global(entry.b)
		if camera.is_position_behind(a) or camera.is_position_behind(b): continue
		var time := clampf(float(entry.age) / float(entry.life), 0.0, 1.0)
		var alpha := 1.0 - smoothstep(0.67, 1.0, time)
		painter.call(self, entry.kind, camera.unproject_position(a) * draw_fit, camera.unproject_position(b) * draw_fit, 0.45 if reduced else time, alpha, entry.amount)

func stroke(points: PackedVector2Array, hue: Color, width: float = 2.5) -> void:
	draw_polyline(points, Color(0.055, 0.11, 0.13, hue.a * 0.72), width + 2.1, true)
	draw_polyline(points, hue, width, true)

func badge(point: Vector2, hue: Color, radius: float) -> void:
	draw_circle(point, radius + 1.8, Color(0.055, 0.11, 0.13, hue.a * 0.75), true, -1, true)
	draw_circle(point, radius, hue, true, -1, true)

## A new judgement replaces a previous one on a single instrument.
func play_cue(kind: StringName, seconds: float) -> void:
	marks.clear()
	mark(kind, Vector3.ZERO, Vector3.ZERO, seconds)

## Additional 3D anchors, in the same scaled canvas coordinates as a and b.
func project(world_point: Vector3) -> Vector2:
	return view.get_camera_3d().unproject_position(world_point) * draw_fit

func arc(center: Vector2, radius: float, start: float, finish: float, hue: Color, width: float) -> void:
	draw_arc(center, radius, start, finish, 20, Color(0.055, 0.11, 0.13, hue.a * 0.72), width + 2.1, true)
	draw_arc(center, radius, start, finish, 20, hue, width, true)

func spark(center: Vector2, radius: float, hue: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2.UP * radius, center + Vector2.RIGHT * radius * 0.55,
		center + Vector2.DOWN * radius, center + Vector2.LEFT * radius * 0.55
	]), hue)
