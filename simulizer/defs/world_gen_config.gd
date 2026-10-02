class_name WorldGenConfig
extends Resource
## Size and material tables for world generation.

@export var width: int = 160
@export var layer_count: int = 30
## Tiles per layer: the bottom row is floor, the rest is room height.
@export var layer_height: int = 4
## Open rows above the ground.
@export var sky_rows: int = 8
## Width of a pre-dug room on the first layer. 0 for none: the dwarves start on the surface.
@export var entry_room_width: int = 0
## How far (in depth fraction) noise can push a band boundary up or down.
@export var band_jitter: float = 0.03
## Must be sorted by start_depth, first band starting at 0.
@export var bands: Array[DepthBand] = []

@export_group("Surface")
@export var tree: PlantDef
@export var tree_count: int = 8
## No trees this close to the middle of the map, where the dwarves arrive.
@export var tree_clearing: int = 5


## One row of topsoil sits between the sky and the first layer.
func first_layer_row() -> int:
	return sky_rows + 1


func height() -> int:
	return first_layer_row() + layer_count * layer_height


## Row a dwarf's feet are on when standing on the surface.
func surface_feet_row() -> int:
	return sky_rows - 1
