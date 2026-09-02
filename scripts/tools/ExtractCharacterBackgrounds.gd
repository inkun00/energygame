extends SceneTree

## Converts the six white-matte ImageGen portraits to real-alpha PNGs.
## Only near-neutral light pixels connected to the canvas edge are removed, so
## white fur, highlights, clothing, eyes, and enclosed details stay intact.

const TARGETS: Array[String] = [
	"res://assets/characters/eco_roster/fairy_sparky.webp",
	"res://assets/characters/eco_roster/solar_fox_sol.webp",
	"res://assets/characters/eco_roster/wind_rabbit_bori.webp",
	"res://assets/characters/eco_roster/recycle_raccoon_ringo.webp",
	"res://assets/characters/eco_roster/earth_turtle_tori.webp",
	"res://assets/characters/eco_roster/lightning_bird_pika.webp",
	"res://assets/characters/eco_roster/mushroom_cat_momo.webp",
]

const MIN_BACKGROUND_CHANNEL := 0.70
const MAX_BACKGROUND_CHROMA := 0.18
const MIN_BACKGROUND_LUMA := 0.80

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in TARGETS:
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			push_error("이미지를 불러오지 못했습니다: %s" % path)
			quit(1)
			return
		image.convert(Image.FORMAT_RGBA8)
		var removed := _extract_edge_connected_background(image)
		var error := image.save_png(ProjectSettings.globalize_path(path))
		if error != OK:
			push_error("투명 PNG 저장에 실패했습니다: %s (%s)" % [path, error])
			quit(1)
			return
		print("[ALPHA] %s: removed %d connected background pixels" % [path.get_file(), removed])
	print("[PASS] Character background extraction complete")
	quit(0)

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
		var x: int = index % width
		var y: int = index / width
		image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
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
	if background[index] != 0:
		return tail
	if not _is_background_pixel(image.get_pixel(x, y)):
		return tail
	background[index] = 1
	queue[tail] = index
	return tail + 1

func _is_background_pixel(color: Color) -> bool:
	if color.a < 0.01:
		return true
	var low: float = minf(color.r, minf(color.g, color.b))
	var high: float = maxf(color.r, maxf(color.g, color.b))
	var chroma: float = high - low
	var luma: float = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return low >= MIN_BACKGROUND_CHANNEL and chroma <= MAX_BACKGROUND_CHROMA and luma >= MIN_BACKGROUND_LUMA
