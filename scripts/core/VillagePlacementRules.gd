extends RefCounted

## Screen-independent village construction cells shared by authority and UI.
## Network placements are normalized cell centers, never display pixels.
const INVALID_POSITION := Vector2(-1, -1)
const CELL_EPSILON := 0.0001
const TERRAIN_ZONES := {
	"wind_plain": {"label": "바람 초원", "rect": Rect2(0.08, 0.06, 0.33, 0.30), "color": Color("78d9ba")},
	"wind_coast": {"label": "바람 해안 절벽", "rect": Rect2(0.05, 0.28, 0.27, 0.34), "color": Color("58c4dd")},
	"solar_field": {"label": "햇빛 평야", "rect": Rect2(0.60, 0.06, 0.35, 0.29), "color": Color("ffd362")},
	"riverbank": {"label": "산골 강변", "rect": Rect2(0.42, 0.06, 0.19, 0.55), "color": Color("55bff2")},
	"eco_city": {"label": "친환경 마을", "rect": Rect2(0.62, 0.33, 0.31, 0.29), "color": Color("88d77b")},
	"grid_hub": {"label": "다리 옆 전력 광장", "rect": Rect2(0.39, 0.40, 0.23, 0.20), "color": Color("9aaeff")},
	"tidal_lagoon": {"label": "바닷가 조력 석호", "rect": Rect2(0.05, 0.63, 0.40, 0.32), "color": Color("35d8d0")},
	"nuclear_site": {"label": "안전 관리 고원", "rect": Rect2(0.37, 0.60, 0.28, 0.31), "color": Color("b9d3e6")},
	"geothermal_field": {"label": "화산 지열 산지", "rect": Rect2(0.66, 0.59, 0.30, 0.35), "color": Color("f2a567")}
}
const PLACEMENT_CELLS := {
	"wind_plain": [Vector2(0.18, 0.15), Vector2(0.31, 0.18), Vector2(0.20, 0.29), Vector2(0.34, 0.30)],
	"wind_coast": [Vector2(0.19, 0.29), Vector2(0.30, 0.35), Vector2(0.22, 0.44), Vector2(0.16, 0.53)],
	"solar_field": [Vector2(0.65, 0.18), Vector2(0.81, 0.13), Vector2(0.79, 0.23), Vector2(0.88, 0.31)],
	"riverbank": [Vector2(0.48, 0.17), Vector2(0.53, 0.31), Vector2(0.47, 0.45), Vector2(0.54, 0.56)],
	"eco_city": [Vector2(0.71, 0.36), Vector2(0.81, 0.41), Vector2(0.68, 0.51), Vector2(0.79, 0.49)],
	"grid_hub": [Vector2(0.44, 0.44), Vector2(0.56, 0.44), Vector2(0.45, 0.55), Vector2(0.57, 0.55)],
	"tidal_lagoon": [Vector2(0.14, 0.71), Vector2(0.29, 0.72), Vector2(0.16, 0.86), Vector2(0.34, 0.85)],
	"nuclear_site": [Vector2(0.45, 0.64), Vector2(0.55, 0.64), Vector2(0.45, 0.72), Vector2(0.55, 0.72)],
	"geothermal_field": [Vector2(0.77, 0.73), Vector2(0.85, 0.75), Vector2(0.78, 0.81), Vector2(0.90, 0.86)]
}

static func resolve_placement(project: Dictionary, requested: Vector2, existing: Dictionary) -> Vector2:
	if not requested.is_finite():
		return INVALID_POSITION
	var use_default := requested == INVALID_POSITION
	for terrain in project.get("terrains", []):
		for cell: Vector2 in PLACEMENT_CELLS.get(terrain, []):
			if not use_default and cell.distance_to(requested) > CELL_EPSILON:
				continue
			var occupied := false
			for position: Vector2 in existing.values():
				if cell.distance_to(position) <= CELL_EPSILON:
					occupied = true
					break
			if not occupied:
				return cell
	return INVALID_POSITION
