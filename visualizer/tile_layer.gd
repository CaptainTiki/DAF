class_name TileLayer
extends MultiMeshInstance3D
## Draws every tile as one quad: solid tiles at the front, dug tiles as a darker
## back wall. One MultiMesh instance per tile, updated individually as tiles change.

const UNKNOWN_COLOR := Color(0.085, 0.08, 0.09)
const GRASS_COLOR := Color(0.33, 0.55, 0.24)
const BACK_WALL_SHADE: float = 0.36
## How much of a tile is left just before it gives way.
const MIN_DUG_HEIGHT: float = 0.12
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


## Shows a tile being dug: it shrinks down towards the floor of its cell as
## the work goes on, so digging reads as something happening even when it is
## slow. Call refresh_tile to put it back.
func show_dig_progress(x: int, y: int, fraction: float) -> void:
	var index: int = y * _grid.width + x
	var height: float = lerpf(1.0, MIN_DUG_HEIGHT, clampf(fraction, 0.0, 1.0))
	var centre: Vector3 = ViewSpace.tile_center(x, y, ViewSpace.LANE_SOLID)
	centre.y -= (1.0 - height) * 0.5
	multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(1.0, height, 1.0)), centre))


func refresh_tile(x: int, y: int) -> void:
	var index: int = y * _grid.width + x
	var material: int = _grid.material_at(x, y)
	if material == TileGrid.NO_MATERIAL:
		multimesh.set_instance_transform(index, HIDDEN)
		return
	var color: Color = _sim.material_def(material).color
	var lane: float = ViewSpace.LANE_SOLID
	if _grid.is_open(x, y) or is_stairwell(_grid, x, y):
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
			if _grid.is_open(nx, ny) or is_stairwell(_grid, nx, ny):
				return true
	return false


## A stair tile or the head space above one. Stairs run behind the rock, so
## these are drawn cut away, two tiles tall, even where the rock in front is
## intact: the dwarf on the stairs is seen whole, never with a head in the dirt.
static func is_stairwell(grid: TileGrid, x: int, y: int) -> bool:
	return grid.has_stair(x, y) or grid.has_stair(x, y + 1)
