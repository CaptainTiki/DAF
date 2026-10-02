class_name StructureLayer
extends MultiMeshInstance3D
## Draws built structures: stairs in the back lane, and floors.
##
## Stairs are drawn as half planks, one from the middle of each stair tile
## towards each stair it connects to, so runs join up where they meet and a
## zig-zag turns a corner instead of leaving a gap.
##
## Where a stairwell passes behind rock, the rock is drawn cut away to show the
## stairs; a strip of that rock is kept along the top, where dwarves walk.
## A built floor is a plank along the top of its tile.

const STAIR_COLOR := Color(0.62, 0.45, 0.25)
const FLOOR_COLOR := Color(0.7, 0.52, 0.3)
## Drop the plank slightly so feet rest on top of it.
const FOOT_CLEARANCE: float = 0.15
const STRIP_THICKNESS: float = 0.2
## The plank mesh is one full tile diagonal long; a half plank is scaled to
## this much of it, a little over half so neighbours overlap.
const HALF_PLANK_SCALE: float = 0.54
const DIAGONALS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]

@onready var _strips: MultiMeshInstance3D = $Walkways

var _sim: Simulation
var _grid: TileGrid
var _stairs: Array[Vector2i] = []
var _floors: Array[Vector2i] = []


func bind(sim: Simulation) -> void:
	_sim = sim
	_grid = sim.grid
	for y in _grid.height:
		for x in _grid.width:
			_track(Vector2i(x, y))
	_rebuild()


## Call when a tile changes. Picks up structures built or removed there, and
## digging around existing ones, which changes what is drawn.
func refresh_tile(x: int, y: int) -> void:
	_track(Vector2i(x, y))
	if not _stairs.is_empty() or not _floors.is_empty() or multimesh.visible_instance_count > 0:
		_rebuild()


func _track(tile: Vector2i) -> void:
	_set_listed(_stairs, tile, _grid.has_stair(tile.x, tile.y))
	_set_listed(_floors, tile, _grid.has_floor(tile.x, tile.y))


func _set_listed(list: Array[Vector2i], tile: Vector2i, present: bool) -> void:
	var index: int = list.find(tile)
	if present and index < 0:
		list.append(tile)
	elif not present and index >= 0:
		list.remove_at(index)


func _rebuild() -> void:
	var planks: MultiMesh = multimesh
	_ensure_capacity(planks, _stairs.size() * 4)
	var plank_count: int = 0
	for tile: Vector2i in _stairs:
		for direction: Vector2i in _plank_directions(tile):
			planks.set_instance_transform(plank_count, _half_plank(tile, direction))
			planks.set_instance_color(plank_count, STAIR_COLOR)
			plank_count += 1
	planks.visible_instance_count = plank_count

	var strips: MultiMesh = _strips.multimesh
	_ensure_capacity(strips, _stairs.size() * 2 + _floors.size())
	var strip_count: int = 0
	for tile: Vector2i in _stairs:
		# The stair tile and the head space above it are both drawn cut away.
		for rise in 2:
			var y: int = tile.y - rise
			if _grid.is_solid(tile.x, y) and _grid.is_open(tile.x, y - 1) and not _grid.has_floor(tile.x, y):
				var color: Color = _sim.material_def(_grid.material_at(tile.x, y)).color * ViewSpace.tile_jitter(tile.x, y)
				_set_strip(strips, strip_count, tile.x, y, color)
				strip_count += 1
	for tile: Vector2i in _floors:
		_set_strip(strips, strip_count, tile.x, tile.y, FLOOR_COLOR * ViewSpace.tile_jitter(tile.x, tile.y))
		strip_count += 1
	strips.visible_instance_count = strip_count


## Which ways planks run from the middle of a stair tile: towards every stair
## it touches diagonally. A tile at the end of a run also gets the opposite
## half, so the run reaches the edge of its last tile; a lone tile slopes right.
func _plank_directions(tile: Vector2i) -> Array[Vector2i]:
	var directions: Array[Vector2i] = []
	for diagonal: Vector2i in DIAGONALS:
		if _grid.has_stair(tile.x + diagonal.x, tile.y + diagonal.y):
			directions.append(diagonal)
	if directions.is_empty():
		directions.append(Vector2i(-1, -1))
		directions.append(Vector2i(1, 1))
	elif directions.size() == 1:
		directions.append(-directions[0])
	return directions


## A plank from the point where feet go in this tile, halfway to the same
## point in the diagonal neighbour.
func _half_plank(tile: Vector2i, direction: Vector2i) -> Transform3D:
	# Tile rows grow downward; world Y grows upward.
	var toward := Vector3(direction.x, -direction.y, 0.0)
	var plank_basis: Basis = Basis(Vector3.BACK, atan2(toward.y, toward.x)) * Basis.from_scale(Vector3(HALF_PLANK_SCALE, 1.0, 1.0))
	var origin: Vector3 = ViewSpace.tile_floor(tile.x, tile.y, ViewSpace.LANE_STRUCTURE) + toward * 0.25
	origin.y -= FOOT_CLEARANCE
	return Transform3D(plank_basis, origin)


## A thin strip along the top edge of a tile, at the front.
func _set_strip(mesh: MultiMesh, index: int, x: int, y: int, color: Color) -> void:
	var strip_basis := Basis.from_scale(Vector3(1.0, STRIP_THICKNESS, 1.0))
	var origin := Vector3(x + 0.5, -y - STRIP_THICKNESS * 0.5, ViewSpace.LANE_SOLID)
	color.a = 1.0
	mesh.set_instance_transform(index, Transform3D(strip_basis, origin))
	mesh.set_instance_color(index, color)


func _ensure_capacity(mesh: MultiMesh, needed: int) -> void:
	if mesh.instance_count < needed:
		mesh.instance_count = maxi(64, needed * 2)
