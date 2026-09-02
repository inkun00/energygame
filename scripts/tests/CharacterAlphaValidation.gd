extends SceneTree

const CHARACTER_PATHS: Array[String] = [
	"res://assets/characters/eco_roster/captain_eco.png",
	"res://assets/characters/eco_roster/fairy_sparky.png",
	"res://assets/characters/eco_roster/water_popo.png",
	"res://assets/characters/eco_roster/bear_pongi.png",
	"res://assets/characters/eco_roster/solar_fox_sol.png",
	"res://assets/characters/eco_roster/wind_rabbit_bori.png",
	"res://assets/characters/eco_roster/recycle_raccoon_ringo.png",
	"res://assets/characters/eco_roster/earth_turtle_tori.png",
	"res://assets/characters/eco_roster/lightning_bird_pika.png",
	"res://assets/characters/eco_roster/mushroom_cat_momo.png",
]

func _initialize() -> void:
	for path in CHARACTER_PATHS:
		var texture := load(path) as Texture2D
		if texture == null:
			push_error("캐릭터 텍스처 로드 실패: %s" % path)
			quit(1)
			return
		var image := texture.get_image()
		var width := image.get_width()
		var height := image.get_height()
		var transparent_samples := 0
		var opaque_white_samples := 0
		for y in range(0, height, 4):
			for x in range(0, width, 4):
				var color := image.get_pixel(x, y)
				if color.a < 0.05:
					transparent_samples += 1
				elif color.a > 0.95 and minf(color.r, minf(color.g, color.b)) > 0.85:
					opaque_white_samples += 1
		if transparent_samples < 100:
			push_error("투명 배경 샘플이 부족합니다: %s" % path)
			quit(1)
			return
		if opaque_white_samples < 10:
			push_error("보존된 흰색 전경 샘플이 부족합니다: %s" % path)
			quit(1)
			return
		print("[ALPHA] %s: transparent=%d, opaque-white=%d" % [path.get_file(), transparent_samples, opaque_white_samples])
	print("[PASS] All 10 character alpha assets validated")
	quit(0)
