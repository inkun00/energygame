extends SceneTree

## ImageGen의 캐릭터별 원본을 런타임용 2048x768, 4프레임 시트로 정규화합니다.

const TARGET_SIZE := Vector2i(2048, 768)
const TARGETS: Array[String] = [
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

const MIN_BACKGROUND_CHANNEL := 0.70
const MAX_BACKGROUND_CHROMA := 0.18
const MIN_BACKGROUND_LUMA := 0.80

func _initialize() -> void:
	for path in TARGETS:
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			push_error("뒷모습 시트를 불러오지 못했습니다: %s" % path)
			quit(1)
			return
		image.convert(Image.FORMAT_RGBA8)
		var original_size := image.get_size()
		var transparent_before := _count_transparent_samples(image)
		var removed := 0
		if transparent_before < 100:
			removed = _extract_edge_connected_background(image)

		# 네 프레임의 경계가 정확히 같은 너비가 되도록 우측 잉여 픽셀만 제거합니다.
		var four_frame_width := int(image.get_width() / 4) * 4
		if four_frame_width != image.get_width():
			image.crop(four_frame_width, image.get_height())

		# 모든 시트를 같은 512x768 프레임 규격으로 맞추되 원본 종횡비와
		# ImageGen이 만든 프레임별 상하 움직임은 그대로 보존합니다.
		var scaled_height := roundi(float(image.get_height()) * float(TARGET_SIZE.x) / float(image.get_width()))
		if scaled_height > TARGET_SIZE.y:
			scaled_height = TARGET_SIZE.y
			var scaled_width := roundi(float(image.get_width()) * float(TARGET_SIZE.y) / float(image.get_height()))
			scaled_width = int(scaled_width / 4) * 4
			image.resize(scaled_width, TARGET_SIZE.y, Image.INTERPOLATE_LANCZOS)
		else:
			image.resize(TARGET_SIZE.x, scaled_height, Image.INTERPOLATE_LANCZOS)

		var normalized := Image.create(TARGET_SIZE.x, TARGET_SIZE.y, false, Image.FORMAT_RGBA8)
		normalized.fill(Color(0.0, 0.0, 0.0, 0.0))
		var destination := Vector2i(
			int((TARGET_SIZE.x - image.get_width()) / 2),
			int((TARGET_SIZE.y - image.get_height()) / 2)
		)
		normalized.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), destination)
		var error := normalized.save_png(ProjectSettings.globalize_path(path))
		if error != OK:
			push_error("뒷모습 시트 저장 실패: %s (%s)" % [path, error])
			quit(1)
			return
		print("[BACK RUN] %s %s -> %s alpha=%d removed=%d" % [
			path.get_file(), original_size, normalized.get_size(),
			_count_transparent_samples(normalized), removed,
		])
	print("[PASS] All 10 back-run sprite sheets prepared")
	quit(0)

func _count_transparent_samples(image: Image) -> int:
	var count := 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			if image.get_pixel(x, y).a < 0.05:
				count += 1
	return count

func _extract_edge_connected_background(image: Image) -> int:
	var width := image.get_width()
	var height := image.get_height()
	var pixel_count := width * height
	var background := PackedByteArray()
	background.resize(pixel_count)
	var queue := PackedInt32Array()
	queue.resize(pixel_count)
	var tail := 0
	for x in range(width):
		tail = _enqueue_if_background(image, x, 0, width, height, background, queue, tail)
		tail = _enqueue_if_background(image, x, height - 1, width, height, background, queue, tail)
	for y in range(1, height - 1):
		tail = _enqueue_if_background(image, 0, y, width, height, background, queue, tail)
		tail = _enqueue_if_background(image, width - 1, y, width, height, background, queue, tail)
	var head := 0
	while head < tail:
		var index := queue[head]
		head += 1
		var x: int = index % width
		var y: int = index / width
		tail = _enqueue_if_background(image, x - 1, y, width, height, background, queue, tail)
		tail = _enqueue_if_background(image, x + 1, y, width, height, background, queue, tail)
		tail = _enqueue_if_background(image, x, y - 1, width, height, background, queue, tail)
		tail = _enqueue_if_background(image, x, y + 1, width, height, background, queue, tail)
	for index in range(pixel_count):
		if background[index] == 0:
			continue
		image.set_pixel(index % width, index / width, Color(0.0, 0.0, 0.0, 0.0))
	return tail

func _enqueue_if_background(
	image: Image,
	x: int,
	y: int,
	width: int,
	height: int,
	background: PackedByteArray,
	queue: PackedInt32Array,
	tail: int
) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return tail
	var index := y * width + x
	if background[index] != 0 or not _is_background_pixel(image.get_pixel(x, y)):
		return tail
	background[index] = 1
	queue[tail] = index
	return tail + 1

func _is_background_pixel(color: Color) -> bool:
	if color.a < 0.01:
		return true
	var low: float = minf(color.r, minf(color.g, color.b))
	var high: float = maxf(color.r, maxf(color.g, color.b))
	var chroma := high - low
	var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return low >= MIN_BACKGROUND_CHANNEL and chroma <= MAX_BACKGROUND_CHROMA and luma >= MIN_BACKGROUND_LUMA
