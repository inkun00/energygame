extends SceneTree

const CHARACTER_IDS: Array[String] = [
	"captain_eco", "fairy_sparky", "water_popo", "bear_pongi", "solar_fox_sol",
	"wind_rabbit_bori", "recycle_raccoon_ringo", "earth_turtle_tori",
	"lightning_bird_pika", "mushroom_cat_momo",
]

func _initialize() -> void:
	for character_id in CHARACTER_IDS:
		var path := "res://assets/characters/eco_roster/sprites/side_run/%s_side_run.png" % character_id
		var texture := load(path) as Texture2D
		var image := texture.get_image() if texture != null else null
		if image == null or image.get_size() != Vector2i(2048, 768):
			push_error("[SIDE RUN] 잘못된 시트 크기: %s" % path)
			quit(1)
			return
		var transparent := 0
		var frame_hashes: Array[int] = []
		var unique_frame_hashes := {}
		for frame in range(4):
			var frame_image := image.get_region(Rect2i(frame * 512, 0, 512, 768))
			var frame_hash: int = hash(frame_image.get_data())
			frame_hashes.append(frame_hash)
			unique_frame_hashes[frame_hash] = true
		for y in range(0, image.get_height(), 8):
			for x in range(0, image.get_width(), 8):
				if image.get_pixel(x, y).a < 0.05:
					transparent += 1
		if transparent < 1000 or unique_frame_hashes.size() < 4:
			push_error("[SIDE RUN] 투명도 또는 프레임 변화 부족: %s" % path)
			quit(1)
			return
		print("[SIDE RUN] %s alpha=%d frames=%s" % [path.get_file(), transparent, frame_hashes])
	print("[PASS] All 10 side-run animation sheets validated")
	quit(0)
