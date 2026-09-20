extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._open_standalone_minigames("hub")
	await create_timer(0.4).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png("res://.godot/standalone_minigames_preview.png")
	print("[StandaloneVisual] %s" % ("PASS" if error == OK else "FAIL"))
	quit(0 if error == OK else 1)
