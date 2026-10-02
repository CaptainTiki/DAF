class_name MarkLayer
extends MultiMeshInstance3D
## Translucent overlay for player marks: tiles to dig and stockpile spots.
## One MultiMesh instance per tile, hidden unless the tile is marked.

const DIG_COLOR := Color(1.0, 0.82, 0.2, 0.38)
const BUILD_COLOR := Color(0.4, 1.0, 0.5, 0.4)
const STOCKPILE_COLOR := Color(0.3, 0.65, 1.0, 0.3)
const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var _grid: TileGrid


func bind(sim: Simulation) -> void:
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
	var lane: float = ViewSpace.LANE_OVERLAY
	if _grid.is_dig_marked(x, y):
		color = DIG_COLOR
	elif _grid.is_build_marked(x, y):
		color = BUILD_COLOR
	elif _grid.is_stockpile(x, y):
		# Painted on the back wall, so it doesn't tint the pallets and dwarves in front.
		color = STOCKPILE_COLOR
		lane = ViewSpace.LANE_BACK_WALL + 0.1
	else:
		multimesh.set_instance_transform(index, HIDDEN)
		return
	multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, ViewSpace.tile_center(x, y, lane)))
	multimesh.set_instance_color(index, color)
