class_name TileLayer
extends MultiMeshInstance3D
## Draws every tile as one quad: solid tiles at the front, dug tiles as a darker
## back wall. One MultiMesh instance per tile, updated individually as tiles change.

const UNKNOWN_COLOR := Color(0.085, 0.08, 0.09)
const GRASS_COLOR := Color(0.33, 0.55, 0.24)
const BACK_WALL_SHADE: float = 0.36
const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

## When off, rock is only shown where it borders open space.
var reveal_all: bool = true: set = set_reveal_all

var _sim: Simulation
var _grid: TileGrid
var _surface_row: int


func bind(sim: Simulation) -> void:
	_sim = sim
	_grid = sim.grid
	_surface_row = sim.config.world_gen.sky_rows
	multimesh.instance_count = _grid.width * _grid.height
	refresh_all()


func set_reveal_all(value: bool) -> void:
	if reveal_all == value:
		return
	reveal_all = value
	if _grid != null:
		refresh_all()


func refresh_all() -> void:
	for y in _grid.height:
		for x in _grid.width:
			refresh_tile(x, y)


## Redraws a tile and its neighbours, whose fog state may depend on it.
func refresh_around(x: int, y: int) -> void:
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if _grid.in_bounds(nx, ny):
				refresh_tile(nx, ny)


func refresh_tile(x: int, y: int) -> void:
	var index: int = y * _grid.width + x
	var material: int = _grid.material_at(x, y)
	if material == TileGrid.NO_MATERIAL:
		multimesh.set_instance_transform(index, HIDDEN)
		return
	var color: Color = _sim.material_def(material).color
	var lane: float = ViewSpace.LANE_SOLID
	# A stair tile is drawn cut away even if the rock in front is intact, so the
	# stairs behind it can be seen.
	if _grid.is_open(x, y) or _grid.has_stair(x, y):
		color = color * BACK_WALL_SHADE
		lane = ViewSpace.LANE_BACK_WALL
	elif not reveal_all and not _is_exposed(x, y):
		color = UNKNOWN_COLOR
	elif y == _surface_row:
		color = GRASS_COLOR
	color = color * ViewSpace.tile_jitter(x, y)
	color.a = 1.0
	multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, ViewSpace.tile_center(x, y, lane)))
	multimesh.set_instance_color(index, color)


func _is_exposed(x: int, y: int) -> bool:
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if _grid.is_open(nx, ny) or _grid.has_stair(nx, ny):
				return true
	return false
