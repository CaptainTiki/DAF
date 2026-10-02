class_name Plant
extends RefCounted
## One growing thing on a tile: a surface tree, a farmed mushroom.

var def: PlantDef
## Tile at its base, where a dwarf's feet would be.
var tile: Vector2i
## Ticks grown so far, up to def.grow_ticks.
var growth: int = 0
## The harvest job on the board while it is full grown.
var job: Job
var removed: bool = false


func growth_fraction() -> float:
	return clampf(float(growth) / maxi(def.grow_ticks, 1), 0.0, 1.0)


func is_grown() -> bool:
	return growth >= def.grow_ticks
