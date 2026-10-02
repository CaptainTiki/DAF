class_name ViewSpace
extends RefCounted
## Maps sim tiles to 3D positions. Tile (x, y) covers world x..x+1 and -y-1..-y.
##
## Depth is a set of lanes along Z. The camera is orthographic and looks straight
## down -Z, so a lane never shifts where something appears on screen, only what
## draws in front of what. Built stairs will sit in LANE_STRUCTURE, behind the
## dwarves walking past.

const LANE_BACK_WALL: float = -2.0
## Chair backs and benches stand against the back wall.
const LANE_SEAT: float = -1.8
const LANE_STRUCTURE: float = -1.6
## A dwarf sitting on a chair: in front of the chair, behind the table.
const LANE_SEATED: float = -1.5
const LANE_PALLET: float = -1.3
## Tables stand in front of whoever is sitting, behind whoever walks past.
const LANE_TABLE: float = -1.15
const LANE_ITEM: float = -1.0
const LANE_DWARF: float = -0.5
const LANE_SOLID: float = 0.0
const LANE_OVERLAY: float = 0.2


static func tile_center(x: float, y: float, lane: float) -> Vector3:
	return Vector3(x + 0.5, -(y + 0.5), lane)


## Middle of the tile's bottom edge, where things stand.
static func tile_floor(x: float, y: float, lane: float) -> Vector3:
	return Vector3(x + 0.5, -(y + 1.0), lane)


static func world_to_tile(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x), floori(-point.y))


## Small repeatable brightness variation per tile, so flat areas don't look painted.
static func tile_jitter(x: int, y: int) -> float:
	var h: int = ((x * 73856093) ^ (y * 19349663)) & 0xFF
	return 0.93 + h / 255.0 * 0.14
