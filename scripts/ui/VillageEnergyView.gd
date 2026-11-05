extends Control
class_name VillageEnergyView
## A view of the host's energy snapshot; animations never advance the simulation.

const MapView = preload("res://scripts/ui/VillageMap.gd")
const TrialRules = preload("res://scripts/core/VillageEnergyTrial.gd")
const DISTRICT_POINTS := [Vector2(0.68, 0.42), Vector2(0.76, 0.39), Vector2(0.69, 0.53), Vector2(0.80, 0.51)]
const PLAYER_COLORS := [Color("62d9bc"), Color("7db8ff"), Color("ffb566"), Color("d2a3f4")]

class EnergyOverlay extends Control:
	var energy_view: Control
	func _draw() -> void:
		if is_instance_valid(energy_view): energy_view.draw_energy(self)

var village_map: Control
var overlay: Control
var district_markers: Array[Control] = []
var snapshot: Dictionary = {}
var local_index := 0
var animation_clock := 0.0
var night_blend := 0.0
var has_snapshot := false
var layout_map_rect := Rect2()

func _ready() -> void:
	name = "VillageEnergyView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	village_map = MapView.new()
	village_map.name = "BuiltVillage"
	village_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	village_map.focus_mode = Control.FOCUS_NONE
	add_child(village_map)
	village_map.set_drop_enabled(false)
	overlay = EnergyOverlay.new()
	overlay.energy_view = self
	overlay.name = "EnergyFlow"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	resized.connect(_layout)
	_layout()

func add_district_marker(marker: Control) -> void:
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	district_markers.append(marker)
	add_child(marker)
	_layout()

func update_snapshot(value: Dictionary, own_index: int) -> void:
	snapshot = value.duplicate(true)
	local_index = own_index
	if not has_snapshot:
		night_blend = 0.0 if str(snapshot.get("phase", "day")) == "day" else 1.0
		has_snapshot = true
	var built_ids: Array[int] = []
	for project_id in snapshot.get("built_ids", []): built_ids.append(int(project_id))
	# Use the same normalized construction cells and owner badges as the build stage.
	village_map.sync_projects(GameManager.CONSTRUCTION_PROJECTS, built_ids, GameManager.built_project_placements, GameManager.built_project_owners, GameManager.players, GameManager.kingdom_health, false)
	village_map.set_environment_health(GameManager.kingdom_health, false)
	overlay.queue_redraw()

func _layout() -> void:
	if not is_instance_valid(village_map): return
	var side_width := clampf(size.x * 0.18, 148.0, 194.0)
	var available := Vector2(maxf(120.0, size.x - side_width * 2.0 - 20.0), maxf(120.0, size.y))
	var aspect := float(MapView.MAP_TEXTURE.get_width()) / float(MapView.MAP_TEXTURE.get_height())
	var map_size := Vector2(minf(available.x, available.y * aspect), minf(available.y, available.x / aspect))
	layout_map_rect = Rect2((size - map_size) * 0.5, map_size)
	village_map.position = layout_map_rect.position
	# Keep facilities proportional to the terrain on small laptop windows too.
	# The build map uses logical pixels; the whole village scales as one scene.
	village_map.size = Vector2(760.0, 760.0 / aspect)
	village_map.scale = map_size / village_map.size
	for idx in range(district_markers.size()):
		var marker := district_markers[idx]
		marker.size = Vector2(side_width, 100)
		var is_right := idx % 2 == 1
		marker.position = Vector2(size.x - side_width if is_right else 0.0, maxf(0.0, size.y * (0.16 if idx < 2 else 0.62) - 20.0))
	overlay.queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or snapshot.is_empty(): return
	if str(snapshot.get("phase", "")) != "complete": animation_clock += delta
	var target := 0.0 if str(snapshot.get("phase", "day")) == "day" else 1.0
	night_blend = move_toward(night_blend, target, delta * 1.8)
	village_map.modulate = Color.WHITE.lerp(Color("627b9e"), night_blend * 0.62)
	overlay.queue_redraw()

func _project_point(project_id: int) -> Vector2:
	var visual: Control = village_map.placed_project_nodes.get(project_id)
	if is_instance_valid(visual):
		return village_map.position + (visual.position + MapView.BUILDING_SIZE * 0.5) * village_map.scale
	return layout_map_rect.position + layout_map_rect.size * Vector2(0.5, 0.48)

func _point(normalized: Vector2) -> Vector2:
	return layout_map_rect.position + layout_map_rect.size * normalized

func _flow(canvas: Control, start: Vector2, finish: Vector2, color: Color, amount: float, bend: float = 0.0) -> void:
	if amount <= 0.001: return
	var middle := (start + finish) * 0.5 + Vector2(0, bend)
	var points := PackedVector2Array([start, middle, finish])
	canvas.draw_polyline(points, Color("123838"), 5.0, true)
	canvas.draw_polyline(points, Color(color, 0.72), 2.0, true)
	if str(snapshot.get("phase", "")) == "complete": return
	for index in range(3):
		var progress := fposmod(animation_clock * 0.45 + float(index) / 3.0, 1.0)
		var position := start.lerp(middle, progress * 2.0) if progress < 0.5 else middle.lerp(finish, (progress - 0.5) * 2.0)
		canvas.draw_circle(position, 5.0, Color(color, 0.16))
		canvas.draw_circle(position, 2.6, color)

func draw_energy(canvas: Control) -> void:
	if snapshot.is_empty() or layout_map_rect.size.x < 1.0: return
	var font := get_theme_default_font()
	var is_day := str(snapshot.get("phase", "day")) == "day"
	var complete := str(snapshot.get("phase", "")) == "complete"
	var hub := _point(Vector2(0.51, 0.47))
	var total_generation := float(snapshot.get("generation", 0.0))
	var energy_color := Color("ffe496")
	# A small sky cue belongs to the village, while all quantities stay in the HUD.
	var sky := layout_map_rect.position + Vector2(26, 25)
	canvas.draw_circle(sky, 15, Color("ffdc75") if is_day else Color("dceaff"))
	if is_day:
		for ray in range(8):
			var direction := Vector2.from_angle(float(ray) * TAU / 8.0)
			canvas.draw_line(sky + direction * 20, sky + direction * 25, Color("ffdc75"), 2.0, true)
	else:
		canvas.draw_circle(sky + Vector2(6, -5), 12, Color("36516b"))
	var built: Array = snapshot.get("built_ids", [])
	for project_id in built:
		if not TrialRules.GENERATION.has(int(project_id)): continue
		var profile: Vector2 = TrialRules.GENERATION[int(project_id)]
		var operates := (profile.x if is_day else profile.y) > 0.0 and total_generation > 0.001
		var source := _project_point(int(project_id))
		if operates and not complete:
			canvas.draw_arc(source, 12, 0, TAU, 24, Color(energy_color, 0.75), 1.5, true)
			_flow(canvas, source, hub, energy_color, total_generation, -8)
		elif int(project_id) == 0 and not is_day:
			canvas.draw_string(font, source + Vector2(-20, 27), "발전 멈춤", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f0f4fa"))
	var battery := _project_point(3)
	if 3 in built:
		_flow(canvas, hub, battery, Color("7ce0c4"), float(snapshot.get("charging", 0.0)), -12)
		var capacity := float(snapshot.get("capacity", 0.0))
		var stored := float(snapshot.get("battery", 0.0)) / maxf(capacity, 0.001)
		var battery_rect := Rect2(battery + Vector2(-18, 22), Vector2(36, 7))
		canvas.draw_rect(battery_rect, Color("132f37"))
		canvas.draw_rect(Rect2(battery_rect.position + Vector2.ONE, Vector2(34 * clampf(stored, 0, 1), 5)), Color("7ce0c4"))
	var players: Array = snapshot.get("players", [])
	for idx in range(mini(players.size(), 4)):
		var district: Dictionary = players[idx]
		var receiver := _point(DISTRICT_POINTS[idx])
		var color: Color = PLAYER_COLORS[idx]
		var ratio := clampf(float(district.get("coverage" if complete else "light_ratio", 0.0)), 0.0, 1.0)
		if not complete:
			_flow(canvas, hub, receiver, energy_color, float(district.get("direct", 0.0)), 10)
			if 3 in built: _flow(canvas, battery, receiver, Color("7ce0c4"), float(district.get("discharging", 0.0)), 14)
		# Window-shaped lights, not extra power plants. Brightness follows delivered demand.
		canvas.draw_circle(receiver, 15, Color(color, 0.15 + ratio * 0.12))
		canvas.draw_circle(receiver, 11, Color("193842"))
		for window in range(4):
			var window_position := receiver + Vector2(-6 + (window % 2) * 7, -6 + (window / 2) * 7)
			canvas.draw_rect(Rect2(window_position, Vector2(5, 5)), Color("3d5865").lerp(Color("fff1b0"), ratio))
		canvas.draw_arc(receiver, 13, 0, TAU, 24, color, 2.0 if idx == local_index else 1.0, true)
		canvas.draw_string(font, receiver + Vector2(-3, -19), str(idx + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		if idx < district_markers.size():
			var marker := district_markers[idx]
			var side := Vector2(marker.size.x, 20) if idx % 2 == 0 else Vector2(0, 20)
			var marker_point := marker.position + side
			canvas.draw_polyline(PackedVector2Array([marker_point, Vector2(receiver.x, marker_point.y), receiver]), Color(color, 0.35), 1.0, true)
