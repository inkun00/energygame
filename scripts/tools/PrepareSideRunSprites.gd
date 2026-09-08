extends SceneTree

## ImageGen 원본을 런타임용 2048x768, 4프레임 투명 횡이동 시트로 정규화합니다.

const TARGET_SIZE := Vector2i(2048, 768)
const CHARACTER_IDS: Array[String] = [
	"captain_eco", "fairy_sparky", "water_popo", "bear_pongi", "solar_fox_sol",
	"wind_rabbit_bori", "recycle_raccoon_ringo", "earth_turtle_tori",
	"lightning_bird_pika", "mushroom_cat_momo",
]

func _initialize() -> void:
	for character_id in CHARACTER_IDS:
		var source_path := "res://assets/characters/eco_roster/sprites/side_run/%s_side_run_raw.png" % character_id
		var target_path := "res://assets/characters/eco_roster/sprites/side_run/%s_side_run.png" % character_id
		var image := Image.load_from_file(source_path)
		if image == null or image.is_empty():
			push_error("횡이동 원본 시트를 불러오지 못했습니다: %s" % source_path)
			quit(1)
			return
		image.convert(Image.FORMAT_RGBA8)
		var original_size := image.get_size()
		var removed := _extract_edge_connected_background(image)
		var four_frame_width := int(image.get_width() / 4) * 4
		if four_frame_width != image.get_width():
			image.crop(four_frame_width, image.get_height())
		var scaled_height := roundi(float(image.get_height()) * float(TARGET_SIZE.x) / float(image.get_width()))
		if scaled_height > TARGET_SIZE.y:
			scaled_height = TARGET_SIZE.y
			var scaled_width := int(round(float(image.get_width()) * float(TARGET_SIZE.y) / float(image.get_height())) / 4.0) * 4
			image.resize(scaled_width, TARGET_SIZE.y, Image.INTERPOLATE_LANCZOS)
		else:
			image.resize(TARGET_SIZE.x, scaled_height, Image.INTERPOLATE_LANCZOS)
		var normalized := Image.create(TARGET_SIZE.x, TARGET_SIZE.y, false, Image.FORMAT_RGBA8)
		normalized.fill(Color(0, 0, 0, 0))
		var destination := Vector2i(int((TARGET_SIZE.x - image.get_width()) / 2), int((TARGET_SIZE.y - image.get_height()) / 2))
		normalized.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), destination)
		var error := normalized.save_png(ProjectSettings.globalize_path(target_path))
		if error != OK:
			push_error("횡이동 시트 저장 실패: %s" % target_path)
			quit(1)
			return
		print("[SIDE RUN] %s %s -> %s alpha=%d removed=%d" % [character_id, original_size, normalized.get_size(), _count_transparent_samples(normalized), removed])
	print("[PASS] All 10 side-run sprite sheets prepared")
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
		if background[index] != 0:
			image.set_pixel(index % width, index / width, Color(0, 0, 0, 0))
	return tail

func _enqueue_if_background(image: Image, x: int, y: int, width: int, height: int, background: PackedByteArray, queue: PackedInt32Array, tail: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return tail
	var index := y * width + x
	if background[index] != 0 or not _is_generated_background(image.get_pixel(x, y)):
		return tail
	background[index] = 1
	queue[tail] = index
	return tail + 1

func _is_generated_background(color: Color) -> bool:
	if color.a < 0.02:
		return true
	var low := minf(color.r, minf(color.g, color.b))
	var high := maxf(color.r, maxf(color.g, color.b))
	var chroma := high - low
	var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return chroma <= 0.11 and (luma <= 0.10 or (luma >= 0.45 and luma <= 0.96))
