class_name StructureLayer
extends MultiMeshInstance3D
## Draws built structures in the back lane. For now that means stairs: one
## sloped plank per stair tile, running through the point where a dwarf's feet go.
##
## Where a stairwell passes behind a floor, the floor is drawn cut away to show
## the stairs. A thin walkway strip is kept along the top of that floor tile, so
## dwarves crossing in front have something visible underfoot.

const STAIR_COLOR := Color(0.62, 0.45, 0.25)
## Drop the plank slightly so feet rest on top of it.
const FOOT_CLEARANCE: float = 0.15
const WALKWAY_THICKNESS: float = 0.2

@onready var _walkways: MultiMeshInstance3D = $Walkways

var _sim: Simulation
var _grid: TileGrid
var _tiles: Array[Vector2i] = []


func bind(sim: Simulation) -> void:
	_sim = sim
	_grid = sim.grid
	for y in _grid.height:
		for x in _grid.width:
			if _grid.has_stair(x, y):
				_tiles.append(Vector2i(x, y))
	_rebuild()


## Call when a tile changes. Picks up newly built stairs, and digging around
## existing ones, which can add or remove a walkway strip.
func refresh_tile(x: int, y: int) -> void:
	var tile := Vector2i(x, y)
	if _grid.has_stair(x, y) and not _tiles.has(tile):
		_tiles.append(tile)
	if not _tiles.is_empty():
		_rebuild()


func _rebuild() -> void:
	var stairs: MultiMesh = multimesh
	var walkways: MultiMesh = _walkways.multimesh
	_ensure_capacity(stairs, _tiles.size())
	_ensure_capacity(walkways, _tiles.size() * 2)
	var walkway_count: int = 0
	for i in _tiles.size():
		var tile: Vector2i = _tiles[i]
		var plank_basis := Basis(Vector3.BACK, -PI * 0.25 * _slope(tile))
		var origin: Vector3 = ViewSpace.tile_floor(tile.x, tile.y, ViewSpace.LANE_STRUCTURE)
		origin.y -= FOOT_CLEARANCE
		stairs.set_instance_transform(i, Transform3D(plank_basis, origin))
		stairs.set_instance_color(i, STAIR_COLOR)
		# The stair tile and the head space above it are both cut away.
		for rise in 2:
			var y: int = tile.y - rise
			if _needs_walkway(tile.x, y):
				_set_walkway(walkways, walkway_count, tile.x, y)
				walkway_count += 1
	stairs.visible_instance_count = _tiles.size()
	walkways.visible_instance_count = walkway_count


## A cut-away tile needs a strip if its rock is still there and someone can walk on top.
func _needs_walkway(x: int, y: int) -> bool:
	return _grid.is_solid(x, y) and _grid.is_open(x, y - 1)


func _set_walkway(mesh: MultiMesh, index: int, x: int, y: int) -> void:
	var strip_basis := Basis.from_scale(Vector3(1.0, WALKWAY_THICKNESS, 1.0))
	var origin := Vector3(x + 0.5, -y - WALKWAY_THICKNESS * 0.5, ViewSpace.LANE_SOLID)
	var color: Color = _sim.material_def(_grid.material_at(x, y)).color * ViewSpace.tile_jitter(x, y)
	color.a = 1.0
	mesh.set_instance_transform(index, Transform3D(strip_basis, origin))
	mesh.set_instance_color(index, color)


## 1 if the flight goes down to the right, -1 if down to the left.
## Judged from the neighbouring stairs; a lone tile slopes right.
func _slope(tile: Vector2i) -> float:
	if _grid.has_stair(tile.x + 1, tile.y + 1) or _grid.has_stair(tile.x - 1, tile.y - 1):
		return 1.0
	if _grid.has_stair(tile.x - 1, tile.y + 1) or _grid.has_stair(tile.x + 1, tile.y - 1):
		return -1.0
	return 1.0


func _ensure_capacity(mesh: MultiMesh, needed: int) -> void:
	if mesh.instance_count < needed:
		mesh.instance_count = maxi(64, needed * 2)
