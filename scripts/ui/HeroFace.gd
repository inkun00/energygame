extends RefCounted

## Matching face medallions for four HUD cards and the current 3D pawn.
const ATLAS = preload("res://assets/characters/eco_roster/board_faces.webp")
const SLUGS := ["captain_eco", "water_popo", "bear_pongi", "solar_fox_sol", "wind_rabbit_bori", "recycle_raccoon_ringo", "earth_turtle_tori", "lightning_bird_pika", "mushroom_cat_momo"]
static var faces: Dictionary = {}

static func for_portrait(path: String) -> Texture2D:
	var slug := path.get_file().get_basename().trim_prefix("char_")
	if slug == "fairy_sparky":
		slug = "captain_eco"
	var index := SLUGS.find(slug)
	if index < 0:
		return load(path) as Texture2D if ResourceLoader.exists(path) else null
	if not faces.has(slug):
		var face := AtlasTexture.new()
		face.atlas = ATLAS
		face.region = Rect2((index % 3) * 128, floori(index / 3.0) * 128, 128, 128)
		face.filter_clip = true
		faces[slug] = face
	return faces[slug]
