class_name TileGrid
extends RefCounted
## Side-view tile grid. Row 0 is the top of the world and y grows downward.
## Out-of-bounds tiles read as solid rock that can't be dug.

const NO_MATERIAL: int = 255
const NO_STRUCTURE: int = 0
## Structures are bits, so one tile can hold more than one.
## Built stairs sit in the back lane: the tile in front can stay solid (a floor
## others walk across) or be open room.
const STRUCTURE_STAIR: int = 1
## A built floor: a plank platform along the top of an open tile. It can be
## stood on like rock, and the space under it stays open.
const STRUCTURE_FLOOR: int = 2
## Scaffolding: a platform like a floor, that can also be climbed straight up
## and down. Towers of it let dwarves reach high places.
const STRUCTURE_SCAFFOLD: int = 4

const FLAG_SOLID: int = 1
const FLAG_DIG_MARK: int = 2
const FLAG_STOCKPILE: int = 4
const FLAG_BUILD_MARK: int = 8
const FLAG_ROOM: int = 16
## A floor is planned here. FLAG_BUILD_MARK is the same for stairs.
const FLAG_FLOOR_MARK: int = 32
## Something built here is to be taken down.
const FLAG_REMOVE_MARK: int = 64

var width: int
var height: int
var first_layer_row: int
var layer_height: int

var _materials: PackedByteArray
var _flags: PackedByteArray
## Built structures per tile, as STRUCTURE_ bits.
var _structures: PackedByteArray


func _init(p_width: int, p_height: int, p_first_layer_row: int, p_layer_height: int) -> void:
	width = p_width
	height = p_height
	first_layer_row = p_first_layer_row
	layer_height = p_layer_height
	var count: int = width * height
	_materials.resize(count)
	_materials.fill(NO_MATERIAL)
	_flags.resize(count)
	_structures.resize(count)


## The raw per-tile arrays, for saving.
func export_arrays() -> Dictionary:
	return {"materials": _materials, "flags": _flags, "structures": _structures}


func import_arrays(data: Dictionary) -> void:
	_materials = data["materials"]
	_flags = data["flags"]
	_structures = data["structures"]


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func is_solid(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return true
	return _flags[y * width + x] & FLAG_SOLID != 0


func is_open(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return _flags[y * width + x] & FLAG_SOLID == 0


func material_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return NO_MATERIAL
	return _materials[y * width + x]


func set_tile(x: int, y: int, material: int, solid: bool) -> void:
	var index: int = y * width + x
	_materials[index] = material
	if solid:
		_flags[index] = _flags[index] | FLAG_SOLID
	else:
		_flags[index] = _flags[index] & ~FLAG_SOLID


## Opens a tile, keeping its material so the back wall still shows what was there.
func set_open(x: int, y: int) -> void:
	var index: int = y * width + x
	_flags[index] = _flags[index] & ~FLAG_SOLID


func has_flag(x: int, y: int, flag: int) -> bool:
	if not in_bounds(x, y):
		return false
	return _flags[y * width + x] & flag != 0


func set_flag(x: int, y: int, flag: int, enabled: bool) -> void:
	var index: int = y * width + x
	if enabled:
		_flags[index] = _flags[index] | flag
	else:
		_flags[index] = _flags[index] & ~flag


func is_dig_marked(x: int, y: int) -> bool:
	return has_flag(x, y, FLAG_DIG_MARK)


func is_stockpile(x: int, y: int) -> bool:
	return has_flag(x, y, FLAG_STOCKPILE)


func is_build_marked(x: int, y: int) -> bool:
	return has_flag(x, y, FLAG_BUILD_MARK)


func is_remove_marked(x: int, y: int) -> bool:
	return has_flag(x, y, FLAG_REMOVE_MARK)


func is_floor_marked(x: int, y: int) -> bool:
	return has_flag(x, y, FLAG_FLOOR_MARK)


func has_stair(x: int, y: int) -> bool:
	return structure_at(x, y) & STRUCTURE_STAIR != 0


func has_floor(x: int, y: int) -> bool:
	return structure_at(x, y) & STRUCTURE_FLOOR != 0


func structure_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return NO_STRUCTURE
	return _structures[y * width + x]


func set_structure(x: int, y: int, structure: int) -> void:
	_structures[y * width + x] = structure


func has_scaffold(x: int, y: int) -> bool:
	return structure_at(x, y) & STRUCTURE_SCAFFOLD != 0


func add_structure(x: int, y: int, structure: int) -> void:
	_structures[y * width + x] = _structures[y * width + x] | structure


func remove_structure(x: int, y: int, structure: int) -> void:
	_structures[y * width + x] = _structures[y * width + x] & ~structure


## Something to stand on: rock, a built floor, or scaffolding.
func is_ground(x: int, y: int) -> bool:
	return is_solid(x, y) or structure_at(x, y) & (STRUCTURE_FLOOR | STRUCTURE_SCAFFOLD) != 0


func layer_count() -> int:
	@warning_ignore("integer_division")
	return (height - first_layer_row) / layer_height


## Layer index of a row. Rows above the first layer (sky, topsoil) are layer -1.
func layer_of_row(y: int) -> int:
	return floori(float(y - first_layer_row) / layer_height)


func layer_top_row(layer: int) -> int:
	return first_layer_row + layer * layer_height


func layer_floor_row(layer: int) -> int:
	return layer_top_row(layer) + layer_height - 1
