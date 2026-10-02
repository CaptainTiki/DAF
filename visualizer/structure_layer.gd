class_name StructureLayer
extends MultiMeshInstance3D
## Draws built structures in the back lane. For now that means stairs: one
## sloped plank per stair tile, running through the point where a dwarf's feet go.

const STAIR_COLOR := Color(0.62, 0.45, 0.25)
## Drop the plank slightly so feet rest on top of it.
const FOOT_CLEARANCE: float = 0.15

var _grid: TileGrid
var _tiles: Array[Vector2i] = []


func bind(sim: Simulation) -> void:
	_grid = sim.grid
	for y in _grid.height:
		for x in _grid.width:
			if _grid.has_stair(x, y):
				_tiles.append(Vector2i(x, y))
	_rebuild()


## Call when a tile changes. Picks up newly built stairs.
func refresh_tile(x: int, y: int) -> void:
	var tile := Vector2i(x, y)
	if not _grid.has_stair(x, y) or _tiles.has(tile):
		return
	_tiles.append(tile)
	_rebuild()


func _rebuild() -> void:
	if multimesh.instance_count < _tiles.size():
		multimesh.instance_count = maxi(64, _tiles.size() * 2)
	for i in _tiles.size():
		var tile: Vector2i = _tiles[i]
		var basis := Basis(Vector3.BACK, -PI * 0.25 * _slope(tile))
		var origin: Vector3 = ViewSpace.tile_floor(tile.x, tile.y, ViewSpace.LANE_STRUCTURE)
		origin.y -= FOOT_CLEARANCE
		multimesh.set_instance_transform(i, Transform3D(basis, origin))
		multimesh.set_instance_color(i, STAIR_COLOR)
	multimesh.visible_instance_count = _tiles.size()


## 1 if the flight goes down to the right, -1 if down to the left.
## Judged from the neighbouring stairs; a lone tile slopes right.
func _slope(tile: Vector2i) -> float:
	if _grid.has_stair(tile.x + 1, tile.y + 1) or _grid.has_stair(tile.x - 1, tile.y - 1):
		return 1.0
	if _grid.has_stair(tile.x - 1, tile.y + 1) or _grid.has_stair(tile.x + 1, tile.y - 1):
		return -1.0
	return 1.0
