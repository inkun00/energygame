extends SceneTree

const BACK_RUN_PATHS: Array[String] = [
	"res://assets/characters/eco_roster/sprites/back_run/captain_eco_back_run.png",
	"res://assets/characters/eco_roster/sprites/back_run/fairy_sparky_back_run.png",
	"res://assets/characters/eco_roster/sprites/back_run/water_popo_back_run.png",
	"res://assets/characters/eco_roster/sprites/back_run/bear_pongi_back_run.png",
	"res://assets/characters/eco_roster/sprites/back_run/solar_fox_sol_back_run.png",
	"res://assets/characters/eco_roster/sprites/back_run/wind_rabbit_bori_back_run.png",
	"res://assets/characters/eco_roster/sprites/back_run/recycle_raccoon_ringo_back_run.png",
	"res://assets/characters/eco_roster/sprites/back_run/earth_turtle_tori_back_run.png",
	"res://assets/characters/eco_roster/sprites/back_run/lightning_bird_pika_back_run.png",
	"res://assets/characters/eco_roster/sprites/back_run/mushroom_cat_momo_back_run.png",
]

func _initialize() -> void:
	for path in BACK_RUN_PATHS:
		var texture := load(path) as Texture2D
		if texture == null:
			_fail("텍스처 로드 실패: %s" % path)
			return
		var image := texture.get_image()
		if image.get_size() != Vector2i(2048, 768):
			_fail("규격 불일치: %s = %s" % [path, image.get_size()])
			return
		var transparent_samples := 0
		for y in range(0, image.get_height(), 16):
			for x in range(0, image.get_width(), 16):
				if image.get_pixel(x, y).a < 0.05:
					transparent_samples += 1
		if transparent_samples < 1000:
			_fail("실제 알파 투명도 부족: %s" % path)
			return
		var frame_hashes: Array[int] = []
		var unique_frame_hashes := {}
		for frame_index in range(4):
			var frame := image.get_region(Rect2i(frame_index * 512, 0, 512, 768))
			var frame_hash: int = hash(frame.get_data())
			frame_hashes.append(frame_hash)
			unique_frame_hashes[frame_hash] = true
		if unique_frame_hashes.size() != 4:
			_fail("네 프레임이 모두 달라야 합니다: %s" % path)
			return
		print("[BACK RUN] %s alpha=%d frames=%s" % [path.get_file(), transparent_samples, frame_hashes])
	print("[PASS] All 10 back-run animation sheets validated")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
