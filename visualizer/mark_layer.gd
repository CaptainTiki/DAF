class_name MarkLayer
extends MultiMeshInstance3D
## Translucent overlay for what the player has marked: tiles to dig, planned
## stairs, stockpile spots and rooms.
## One MultiMesh instance per tile, hidden unless the tile is marked.

const DIG_COLOR := Color(1.0, 0.82, 0.2, 0.38)
const BUILD_COLOR := Color(0.4, 1.0, 0.5, 0.4)
const FLOOR_COLOR := Color(1.0, 0.6, 0.25, 0.4)
const REMOVE_COLOR := Color(1.0, 0.25, 0.2, 0.45)
const STOCKPILE_COLOR := Color(0.3, 0.65, 1.0, 0.3)
const ROOM_ALPHA: float = 0.2
const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

## Whether rooms are tinted with their colour.
var show_rooms: bool = true: set = set_show_rooms

var _sim: Simulation
var _grid: TileGrid


func set_show_rooms(value: bool) -> void:
	if show_rooms == value:
		return
	show_rooms = value
	if _sim == null:
		return
	for room: Room in _sim.rooms.rooms:
		refresh_rect(room.rect)


func bind(sim: Simulation) -> void:
	_sim = sim
	_grid = sim.grid
	multimesh.instance_count = _grid.width * _grid.height
	refresh_rect(Rect2i(0, 0, _grid.width, _grid.height))


func refresh_rect(rect: Rect2i) -> void:
	var clipped: Rect2i = rect.intersection(Rect2i(0, 0, _grid.width, _grid.height))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			refresh_tile(x, y)


func refresh_tile(x: int, y: int) -> void:
	var index: int = y * _grid.width + x
	var color: Color
	# Marks on open space are painted on the back wall, so they don't tint the
	# dwarves and goods in front.
	var lane: float = ViewSpace.LANE_BACK_WALL + 0.1
	if _grid.is_dig_marked(x, y):
		color = DIG_COLOR
		lane = ViewSpace.LANE_OVERLAY
	elif _grid.is_remove_marked(x, y):
		color = REMOVE_COLOR
		lane = ViewSpace.LANE_OVERLAY
	elif _grid.is_build_marked(x, y):
		color = BUILD_COLOR
		lane = ViewSpace.LANE_OVERLAY
	elif _grid.is_floor_marked(x, y):
		color = FLOOR_COLOR
		lane = ViewSpace.LANE_OVERLAY
	elif _grid.is_stockpile(x, y):
		color = STOCKPILE_COLOR
	elif show_rooms and _grid.has_flag(x, y, TileGrid.FLAG_ROOM):
		var room: Room = _sim.rooms.room_at(Vector2i(x, y))
		color = Color(room.def.color, ROOM_ALPHA) if room != null else Color(1, 1, 1, ROOM_ALPHA)
	else:
		multimesh.set_instance_transform(index, HIDDEN)
		return
	multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, ViewSpace.tile_center(x, y, lane)))
	multimesh.set_instance_color(index, color)
