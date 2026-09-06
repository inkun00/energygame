extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	if OS.has_feature("web"):
		var button := Button.new()
		button.text = "효과음 재생 검사 시작"
		button.position = Vector2(40, 40)
		button.size = Vector2(500, 100)
		root.add_child(button)
		button.pressed.connect(func():
			button.queue_free()
			_run(), CONNECT_ONE_SHOT)
	else:
		_run()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	var manager = root.get_node("AudioManager")
	check(manager.CLIPS.size() == 17, "All original effects must be bundled")
	var data_bytes := 0
	for id in manager.CLIPS:
		var clip: AudioStreamWAV = manager.CLIPS[id]
		check(clip != null and clip.get_length() > 0.04, "%s: missing/empty clip" % id)
		check(not clip.stereo and clip.mix_rate == 22050, "%s: expected compact mono audio" % id)
		check(clip.format == AudioStreamWAV.FORMAT_QOA, "%s: expected QOA compression" % id)
		check(clip.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s: must not loop" % id)
		data_bytes += clip.data.size()
	check(data_bytes < 100000, "Combined compressed effects must stay below 100 KB")
	for id in manager.CLIPS:
		var started := Time.get_ticks_usec()
		manager._play_clip(id)
		var cost := Time.get_ticks_usec() - started
		var voice: AudioStreamPlayer = manager.voices[0]
		check(voice.playing and voice.stream == manager.CLIPS[id], "%s: failed to start" % id)
		if OS.has_feature("web"):
			check(voice.playback_type == AudioServer.PLAYBACK_TYPE_SAMPLE, "Web must use sample playback")
		await create_timer(manager.CLIPS[id].get_length() + 0.25).timeout
		check(not voice.playing, "%s: playback must finish naturally" % id)
		print("[AUDIO] %s start_us=%d" % [id, cost])
	# Concurrent effects may overlap; reusing a busy voice must not cut a sound short.
	for i in range(manager.MAX_VOICES): manager._play_clip("mycelium_harvest")
	manager._play_clip("move")
	check(manager.get_child_count() == manager.MAX_VOICES, "Repeated playback must not allocate nodes")
	for voice in manager.voices:
		check(voice.playing and voice.stream == manager.CLIPS["mycelium_harvest"], "Pool overflow must preserve active effects")
	await create_timer(1.0).timeout
	for voice in manager.voices: check(not voice.playing, "All voices should become reusable")
	var message := "PASS: 17 local audio clips; %d compressed bytes; natural completion; bounded voice reuse" % data_bytes
	if not failures.is_empty(): message = "FAIL: " + "; ".join(failures)
	print(message)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("var report=document.createElement('pre');report.id='audio-test-result';report.style='position:fixed;inset:20px;background:white;color:black;z-index:9999;padding:20px;white-space:pre-wrap';report.textContent=" + JSON.stringify(message) + ";document.body.appendChild(report);", true)
	else:
		quit(0 if failures.is_empty() else 1)
