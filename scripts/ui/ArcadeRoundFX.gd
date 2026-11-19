extends Control

## Round-wide cues live above the guide and never consume an arcade input.
var arena: Control
var accent := Color("83efc6")
var reduced_motion := false
var countdown := 0
var headline := ""
var headline_left := 0.0
var headline_duration := 1.0
var final_seconds := 0
var last_score := 0
var queued_points := 0
var shown_points := 0
var shown_streak := 0
var points_left := 0.0
var debounce := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if OS.has_feature("web"):
		reduced_motion = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches", true))
	reset()

func reset(color: Color = Color("83efc6")) -> void:
	accent = color
	headline_left = 0.0
	points_left = 0.0
	final_seconds = 0
	countdown = 0
	last_score = 0
	queued_points = 0
	debounce = 0.0
	hide()
	set_process(false)

func show_count(value: int) -> void:
	if value == countdown:
		return
	countdown = value
	_head(str(value), 0.95)
	AudioManager.play_arcade_cue("arcade_tick")

func start_round() -> void:
	countdown = 0
	_head("시작!", 0.54)
	AudioManager.play_arcade_cue("arcade_start")

func clock_changed(seconds: int) -> void:
	if seconds < 1 or seconds > 5 or seconds == final_seconds:
		return
	if final_seconds == 0:
		AudioManager.play_arcade_cue("arcade_tick")
	final_seconds = seconds
	show()
	queue_redraw()

func score_changed(value: int, streak: int) -> void:
	if value == last_score:
		return
	queued_points += value - last_score
	last_score = value
	shown_streak = streak
	if debounce <= 0.0:
		_show_points()
	show()
	set_process(true)

func _show_points() -> void:
	shown_points = queued_points
	queued_points = 0
	points_left = 0.66
	debounce = 0.65

func _head(value: String, duration: float) -> void:
	headline = value
	headline_left = duration
	headline_duration = duration
	show()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	headline_left = maxf(0, headline_left - delta)
	points_left = maxf(0, points_left - delta)
	debounce = maxf(0, debounce - delta)
	if debounce == 0.0 and queued_points != 0:
		_show_points()
	if headline_left + points_left + debounce <= 0.0:
		set_process(false)
		visible = final_seconds > 0
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(arena):
		return
	var field := arena.get_global_rect()
	field.position -= global_position
	var font := get_theme_default_font()
	var dark := Color("0b2632f2")
	if headline_left > 0.0:
		var t := 1.0 - headline_left / headline_duration
		var center := size * 0.5 if countdown > 0 else Vector2(field.get_center().x, field.position.y + 58)
		var radius := 48.0 + (0.0 if reduced_motion else 10.0 * pow(1.0 - t, 3))
		draw_circle(center, radius, dark, true, -1, true)
		draw_arc(center, radius, -PI / 2, TAU - PI / 2, 64, Color(accent, 0.35), 3, true)
		draw_arc(center, radius + 2, -PI / 2, -PI / 2 + TAU * (1.0 if reduced_motion else maxf(0.03, 1.0 - t)), 64, accent, 5, true)
		draw_string(font, center + Vector2(-65, 16), headline, HORIZONTAL_ALIGNMENT_CENTER, 130, 42 if countdown > 0 else 33, Color.WHITE)
	if points_left > 0.0:
		var color := Color("9ff4c7") if shown_points > 0 else Color("ffc1a7")
		var origin := field.position + Vector2(field.size.x - 178, 20 + (0.0 if reduced_motion else points_left * 9))
		var caption := "%+d점" % shown_points
		if shown_points > 0 and shown_streak >= 2:
			caption += "  ·  %d연속" % shown_streak
		draw_rect(Rect2(origin, Vector2(158, 38)), dark)
		draw_rect(Rect2(origin, Vector2(4, 38)), color)
		draw_string(font, origin + Vector2(8, 26), caption, HORIZONTAL_ALIGNMENT_CENTER, 144, 19, color)
	if final_seconds > 0:
		var corner := Vector2(field.position.x + 15, field.end.y - 12)
		for index in range(5):
			draw_rect(Rect2(corner + Vector2(index * 19, -5), Vector2(14, 5)), Color("ffb478") if index < final_seconds else Color("54666e"))
